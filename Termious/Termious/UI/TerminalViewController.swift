import UIKit

public final class TerminalViewController: UIViewController {
    private let host = ShellHost()
    private let consoleView = ConsoleView()
    private let inputBar = InputBar()
    private var history: [String] = []
    private var historyIndex: Int = -1
    private var currentInput: String = ""
    private var inputBarBottom: NSLayoutConstraint!
    private var pendingSudoCommand: String? = nil
    private var watchTimer: Timer? = nil
    private var bgManager = BackgroundManager.shared

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        host.delegate = self
        setupSubviews()
        registerForKeyboard()
        bgManager.attach(to: view)
        printWelcome()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        bgManager.resize(to: view.bounds)
    }

    private func setupSubviews() {
        consoleView.translatesAutoresizingMaskIntoConstraints = false
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(consoleView)
        view.addSubview(inputBar)

        inputBar.delegate = self
        consoleView.delegate2 = self

        NSLayoutConstraint.activate([
            consoleView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            consoleView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            consoleView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            consoleView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 56)
        ])
        inputBarBottom = inputBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        inputBarBottom.isActive = true
    }

    private func registerForKeyboard() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    @objc private func keyboardChanged(_ note: Notification) {
        guard let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }
        let height = view.convert(frame, from: nil).intersection(view.bounds).height
        inputBarBottom.constant = -height
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    private func printWelcome() {
        let banner = "\u{001B}[32mTermious\u{001B}[0m 1.0 - a sandboxed terminal for iOS\n"
                    + "Custom shell with aero package manager, sudo, and 50+ commands.\n"
                    + "Type 'help' for commands, 'aero search <query>' for GitHub repos.\n\n"
        consoleView.appendOutput(banner, color: Theme.dim)
        renderPrompt()
    }

    private func renderPrompt() {
        consoleView.appendPrompt(host.prompt)
    }

    private func runCommand(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        consoleView.appendOutput("\n", color: Theme.foreground)

        guard !trimmed.isEmpty else {
            renderPrompt()
            return
        }

        history.append(trimmed)
        historyIndex = history.count

        host.execute(trimmed,
                     onOutput: { [weak self] text in
                         self?.consoleView.appendOutput(text, color: Theme.foreground)
                     },
                     onError: { [weak self] text in
                         self?.consoleView.appendOutput(text, color: Theme.error)
                     })
        renderPrompt()
    }

    private func executeSudoCommand(_ command: String) {
        consoleView.appendOutput("Running as root: \(command)\n", color: Theme.accent)
        host.execute(command,
                     onOutput: { [weak self] text in
                         self?.consoleView.appendOutput(text, color: Theme.foreground)
                     },
                     onError: { [weak self] text in
                         self?.consoleView.appendOutput(text, color: Theme.error)
                     })
        renderPrompt()
    }
}

// MARK: - InputBarDelegate

extension TerminalViewController: InputBarDelegate {
    public func inputBar(_ bar: InputBar, didSubmit text: String) {
        runCommand(text)
        bar.clear()
    }

    public func inputBar(_ bar: InputBar, didChange text: String) {
        currentInput = text
    }

    public func inputBarDidTapUp(_ bar: InputBar) {
        guard !history.isEmpty else { return }
        historyIndex = max(0, historyIndex - 1)
        bar.setText(history[historyIndex])
    }

    public func inputBarDidTapDown(_ bar: InputBar) {
        guard !history.isEmpty else { return }
        historyIndex = min(history.count, historyIndex + 1)
        if historyIndex >= history.count {
            bar.setText(currentInput)
        } else {
            bar.setText(history[historyIndex])
        }
    }

    public func inputBarDidTapTab(_ bar: InputBar) {
        let text = bar.text
        let parts = text.split(separator: " ", omittingEmptySubsequences: false)
        guard let last = parts.last else { return }
        let prefix = String(last)
        let matches = host.registry.availableCommands.filter { $0.hasPrefix(prefix) }
        if matches.count == 1 {
            let replaced = String(text.dropLast(prefix.count)) + matches[0] + " "
            bar.setText(replaced)
        } else if matches.count > 1 {
            consoleView.appendOutput("\n" + matches.joined(separator: "  ") + "\n",
                                     color: Theme.accent)
            consoleView.appendPrompt(host.prompt + text)
        }
    }
}

extension TerminalViewController: ConsoleViewDelegate {
    public func consoleViewDidScrollToBottom(_ view: ConsoleView) {}
}

// MARK: - ShellHostDelegate

extension TerminalViewController: ShellHostDelegate {
    public func shellHostDidRequestOpenPicker(_ host: ShellHost) {
        DispatchQueue.main.async { [weak self] in self?.presentDocumentPicker() }
    }

    public func shellHostDidRequestExit(_ host: ShellHost) {
        consoleView.appendOutput("\n[session ended]\n", color: Theme.dim)
    }

    public func shellHostDidRequestClearScreen(_ host: ShellHost) {
        consoleView.clear()
        renderPrompt()
    }

    public func shellHostDidRequestSudoPrompt(_ host: ShellHost, command: String) {
        pendingSudoCommand = command
        DispatchQueue.main.async { [weak self] in self?.presentSudoPasswordAlert() }
    }

    public func shellHostDidRequestSudoExec(_ host: ShellHost, command: String) {
        executeSudoCommand(command)
    }

    public func shellHostDidRequestPasswdChange(_ host: ShellHost) {
        DispatchQueue.main.async { [weak self] in self?.presentPasswdChangeAlert() }
    }

    public func shellHostDidRequestShowHistory(_ host: ShellHost) {
        if history.isEmpty {
            consoleView.appendOutput("No history yet.\n", color: Theme.dim)
        } else {
            for (i, cmd) in history.enumerated() {
                consoleView.appendOutput(String(format: "%5d  %@\n", i + 1, cmd),
                                         color: Theme.foreground)
            }
        }
        renderPrompt()
    }

    public func shellHostDidRequestManPage(_ host: ShellHost, command: String) {
        guard let cmd = host.registry.resolve(command) else {
            consoleView.appendOutput("No manual entry for \(command)\n", color: Theme.error)
            renderPrompt()
            return
        }
        var man = "\u{001B}[33m\(cmd.name)(1)\u{001B}[0m\n\n"
        man += "NAME\n    \(cmd.name) - \(cmd.summary)\n\n"
        man += "SYNOPSIS\n    \(cmd.usage)\n\n"
        if !cmd.operands.isEmpty {
            man += "OPERANDS\n"
            for op in cmd.operands {
                let req = op.required ? "required" : "optional"
                man += "    \(op.name)  (\(req), \(op.type))  \(op.description)\n"
            }
            man += "\n"
        }
        man += "DESCRIPTION\n    \(cmd.summary). This is a builtin command in the Termious shell.\n\n"
        man += "SEE ALSO\n    help, aero, sudo\n\n"
        consoleView.appendOutput(man, color: Theme.foreground)
        renderPrompt()
    }

    public func shellHostDidRequestTimeCommand(_ host: ShellHost, command: String) {
        let start = Date()
        host.execute(command,
                     onOutput: { [weak self] text in
                         self?.consoleView.appendOutput(text, color: Theme.foreground)
                     },
                     onError: { [weak self] text in
                         self?.consoleView.appendOutput(text, color: Theme.error)
                     })
        let elapsed = Date().timeIntervalSince(start)
        consoleView.appendOutput(String(format: "real %.3fs\n", elapsed),
                                 color: Theme.dim)
        renderPrompt()
    }

    public func shellHostDidRequestWatch(_ host: ShellHost, interval: Double, command: String) {
        watchTimer?.invalidate()
        consoleView.appendOutput("Watching: \(command) every \(interval)s (Ctrl-C to stop)\n",
                                 color: Theme.accent)
        var iteration = 0
        watchTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            iteration += 1
            self.consoleView.appendOutput("\u{001B}[36m[watch #\(iteration)]\u{001B}[0m\n",
                                          color: Theme.dim)
            self.host.execute(command,
                              onOutput: { [weak self] text in
                                  self?.consoleView.appendOutput(text, color: Theme.foreground)
                              },
                              onError: { [weak self] text in
                                  self?.consoleView.appendOutput(text, color: Theme.error)
                              })
            if iteration >= 10 {
                self.consoleView.appendOutput("[watch: stopped after 10 iterations]\n",
                                              color: Theme.dim)
                timer.invalidate()
                self.renderPrompt()
            }
        }
    }

    public func shellHostDidRequestReboot(_ host: ShellHost) {
        watchTimer?.invalidate()
        SudoSession.shared.invalidate()
        consoleView.clear()
        printWelcome()
    }

    public func shellHostDidRequestThemeChange(_ host: ShellHost, scheme: String) {
        let schemes: [String: (bg: UIColor, fg: UIColor, prompt: UIColor)] = [
            "dark":       (UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1),
                           UIColor(red: 0.88, green: 0.90, blue: 0.92, alpha: 1),
                           UIColor(red: 0.30, green: 0.85, blue: 0.55, alpha: 1)),
            "light":      (UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1),
                           UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1),
                           UIColor(red: 0.10, green: 0.50, blue: 0.20, alpha: 1)),
            "green":      (UIColor(red: 0.02, green: 0.08, blue: 0.02, alpha: 1),
                           UIColor(red: 0.40, green: 0.90, blue: 0.40, alpha: 1),
                           UIColor(red: 0.60, green: 1.00, blue: 0.40, alpha: 1)),
            "amber":      (UIColor(red: 0.05, green: 0.03, blue: 0.01, alpha: 1),
                           UIColor(red: 0.90, green: 0.65, blue: 0.20, alpha: 1),
                           UIColor(red: 1.00, green: 0.75, blue: 0.30, alpha: 1)),
            "blue":       (UIColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1),
                           UIColor(red: 0.60, green: 0.75, blue: 0.95, alpha: 1),
                           UIColor(red: 0.40, green: 0.80, blue: 1.00, alpha: 1)),
            "solarized":  (UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1),
                           UIColor(red: 0.90, green: 0.90, blue: 0.80, alpha: 1),
                           UIColor(red: 0.15, green: 0.55, blue: 0.55, alpha: 1)),
        ]
        if let s = schemes[scheme] {
            Theme.apply(background: s.bg, foreground: s.fg, prompt: s.prompt)
            view.backgroundColor = s.bg
            consoleView.applyTheme()
            consoleView.appendOutput("Theme changed to: \(scheme)\n", color: Theme.accent)
        } else {
            consoleView.appendOutput("Unknown theme: \(scheme). Available: dark light green amber blue solarized\n",
                                     color: Theme.error)
        }
        renderPrompt()
    }

    public func shellHostDidRequestBackgroundChange(_ host: ShellHost, styleName: String) {
        if styleName == "off" {
            bgManager.clear()
            view.backgroundColor = Theme.background
            consoleView.appendOutput("Background cleared.\n", color: Theme.accent)
        } else if bgManager.apply(styleName, to: view) {
            bgManager.resize(to: view.bounds)
            let style = BackgroundManager.shared.styles.first { $0.name == styleName }
            let kind = style?.kind.rawValue ?? ""
            let desc = style?.description ?? ""
            consoleView.appendOutput("Background: \u{001B}[32m\(styleName)\u{001B}[0m (\(kind)) - \(desc)\n",
                                     color: Theme.accent)
        } else {
            consoleView.appendOutput("bg: unknown style '\(styleName)'\n", color: Theme.error)
        }
        renderPrompt()
    }

    public func shellHostDidRequestTineoEdit(_ host: ShellHost, mode: String, path: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if mode == "NEW" {
                // Create empty file
                if let url = self.host.fs.resolve(path) {
                    let started = self.host.fs.startRootAccess()
                    if !FileManager.default.fileExists(atPath: url.path) {
                        FileManager.default.createFile(atPath: url.path, contents: Data())
                    }
                    if started { self.host.fs.stopRootAccess() }
                }
            }
            let editor = TineoEditorViewController(filePath: path, fs: self.host.fs)
            let nav = UINavigationController(rootViewController: editor)
            nav.modalPresentationStyle = .fullScreen
            self.present(nav, animated: true) {
                self.consoleView.appendOutput("Tineo: opened '\(path)'\n", color: Theme.accent)
                self.renderPrompt()
            }
        }
    }

    public func shellHostDidRequestOpenURL(_ host: ShellHost, url: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var urlStr = url
            if urlStr.hasPrefix("file://") { urlStr = String(urlStr.dropFirst(7)) }
            if let actualURL = URL(string: urlStr), UIApplication.shared.canOpenURL(actualURL) {
                UIApplication.shared.open(actualURL, options: [:]) { success in
                    if success {
                        self.consoleView.appendOutput("Opened \(urlStr) in Safari\n", color: Theme.accent)
                    } else {
                        self.consoleView.appendOutput("Failed to open \(urlStr)\n", color: Theme.error)
                    }
                    self.renderPrompt()
                }
            } else if let actualURL = URL(string: "https://\(urlStr)") {
                UIApplication.shared.open(actualURL, options: [:]) { _ in self.renderPrompt() }
            }
        }
    }

    public func shellHostDidRequestSourceExec(_ host: ShellHost, content: String) {
        host.execute(content,
                     onOutput: { [weak self] text in self?.consoleView.appendOutput(text, color: Theme.foreground) },
                     onError: { [weak self] text in self?.consoleView.appendOutput(text, color: Theme.error) })
        renderPrompt()
    }

    public func shellHostDidRequestAeroClone(_ host: ShellHost, repo: String, name: String) {
        consoleView.appendOutput("Cloning \(repo) as \(name)...\n", color: Theme.accent)
        let group = DispatchGroup()
        group.enter()
        AeroPackageManager.shared.install(
            repo: repo, ref: nil, name: name, fs: host.fs,
            progress: { [weak self] msg in self?.consoleView.appendOutput(msg + "\n", color: Theme.dim) }
        ) { [weak self] result in
            switch result {
            case .success: self?.consoleView.appendOutput("Cloned \(repo) as \(name)\n", color: Theme.accent)
            case .failure(let err): self?.consoleView.appendOutput("clone failed: \(err)\n", color: Theme.error)
            }
            group.leave()
        }
        group.wait()
        renderPrompt()
    }

    // MARK: - Document picker

    private func presentDocumentPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    // MARK: - Sudo password alert

    private func presentSudoPasswordAlert() {
        let alert = UIAlertController(
            title: "sudo password",
            message: "Enter the sudo password to run the command.",
            preferredStyle: .alert)
        alert.addTextField { tf in
            tf.isSecureTextEntry = true
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.placeholder = "password (default: alpine)"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.consoleView.appendOutput("sudo: authentication cancelled\n", color: Theme.error)
            self?.renderPrompt()
            self?.pendingSudoCommand = nil
        })
        alert.addAction(UIAlertAction(title: "Authenticate", style: .default) { [weak self] _ in
            let pw = alert.textFields?.first?.text ?? ""
            guard let cmd = self?.pendingSudoCommand else { return }
            if PasswordManager.shared.verify(pw) {
                SudoSession.shared.markAuthenticated()
                self?.consoleView.appendOutput("Authenticated. Running command...\n",
                                               color: Theme.accent)
                self?.executeSudoCommand(cmd)
            } else {
                self?.consoleView.appendOutput("sudo: incorrect password\n", color: Theme.error)
                self?.renderPrompt()
            }
            self?.pendingSudoCommand = nil
        })
        present(alert, animated: true)
    }

    // MARK: - Passwd change alert

    private func presentPasswdChangeAlert() {
        let alert = UIAlertController(
            title: "Change sudo password",
            message: "Enter the current password, then a new password.",
            preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "current password"
            tf.isSecureTextEntry = true
            tf.autocapitalizationType = .none
        }
        alert.addTextField { tf in
            tf.placeholder = "new password"
            tf.isSecureTextEntry = true
            tf.autocapitalizationType = .none
        }
        alert.addTextField { tf in
            tf.placeholder = "confirm new password"
            tf.isSecureTextEntry = true
            tf.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.renderPrompt()
        })
        alert.addAction(UIAlertAction(title: "Change", style: .default) { [weak self] _ in
            let old = alert.textFields?[0].text ?? ""
            let new = alert.textFields?[1].text ?? ""
            let confirm = alert.textFields?[2].text ?? ""
            if new != confirm {
                self?.consoleView.appendOutput("passwd: passwords do not match\n",
                                               color: Theme.error)
            } else if !PasswordManager.shared.changePassword(oldPlaintext: old, newPlaintext: new) {
                self?.consoleView.appendOutput("passwd: incorrect current password\n",
                                               color: Theme.error)
            } else {
                self?.consoleView.appendOutput("Password updated successfully.\n",
                                               color: Theme.accent)
            }
            self?.renderPrompt()
        })
        present(alert, animated: true)
    }
}

extension TerminalViewController: UIDocumentPickerDelegate {
    public public func documentPicker(_ controller: UIDocumentPickerViewController,
                               didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        if let id = host.fs.addBookmark(for: url) {
            host.fs.rootKind = .bookmark(id)
            host.fs.cwd = "/"
            consoleView.appendOutput("Granted access to: \(id)\n", color: Theme.accent)
            renderPrompt()
        } else {
            consoleView.appendOutput("Failed to bookmark \(url.lastPathComponent)\n",
                                     color: Theme.error)
        }
    }

    public public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        renderPrompt()
    }
}