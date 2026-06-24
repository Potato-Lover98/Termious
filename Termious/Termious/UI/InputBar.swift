import UIKit

public protocol InputBarDelegate: AnyObject {
    func inputBar(_ bar: InputBar, didSubmit text: String)
    func inputBar(_ bar: InputBar, didChange text: String)
    func inputBarDidTapUp(_ bar: InputBar)
    func inputBarDidTapDown(_ bar: InputBar)
    func inputBarDidTapTab(_ bar: InputBar)
}

/// A bottom-anchored input bar with a UITextField and a small toolbar that
/// provides up/down (history), tab (completion), and enter (submit).
public final class InputBar: UIView, UITextFieldDelegate {
    public weak var delegate: InputBarDelegate?

    private let textField = UITextField()
    private let toolbar = UIToolbar()

    public var text: String { textField.text ?? "" }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor(white: 0.04, alpha: 1.0)
        layer.borderWidth = 0.5
        layer.borderColor = UIColor(white: 0.18, alpha: 1.0).cgColor

        textField.font = Theme.font
        textField.textColor = Theme.foreground
        textField.backgroundColor = UIColor(white: 0.08, alpha: 1.0)
        textField.layer.cornerRadius = 8
        textField.layer.masksToBounds = true
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 0))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 0))
        textField.rightViewMode = .always
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.keyboardType = .default
        textField.returnKeyType = .send
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Type a command…"
        textField.tintColor = Theme.prompt

        let upButton = UIBarButtonItem(image: UIImage(systemName: "chevron.up"),
                                       style: .plain, target: self, action: #selector(tapUp))
        let downButton = UIBarButtonItem(image: UIImage(systemName: "chevron.down"),
                                         style: .plain, target: self, action: #selector(tapDown))
        let tabButton = UIBarButtonItem(title: "Tab",
                                        style: .plain, target: self, action: #selector(tapTab))
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let runButton = UIBarButtonItem(image: UIImage(systemName: "return"),
                                        style: .done, target: self, action: #selector(submit))
        upButton.tintColor = Theme.accent
        downButton.tintColor = Theme.accent
        tabButton.tintColor = Theme.accent
        runButton.tintColor = Theme.prompt

        toolbar.items = [upButton, downButton, tabButton, spacer, runButton]
        toolbar.sizeToFit()
        toolbar.barTintColor = UIColor(white: 0.06, alpha: 1.0)
        textField.inputAccessoryView = toolbar

        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            textField.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
    }

    public func updateBottomInset(_ keyboardHeight: CGFloat) {
        // The owning view controller adjusts the bottom constraint it owns;
        // the InputBar itself only needs to notify via the delegate if needed.
        // No-op here — keyboard inset is handled by TerminalViewController.
    }

    public func clear() {
        textField.text = ""
        delegate?.inputBar(self, didChange: "")
    }

    public func setText(_ text: String) {
        textField.text = text
        delegate?.inputBar(self, didChange: text)
    }

    @objc private func submit() {
        let value = textField.text ?? ""
        delegate?.inputBar(self, didSubmit: value)
    }

    @objc private func tapUp() {
        delegate?.inputBarDidTapUp(self)
    }

    @objc private func tapDown() {
        delegate?.inputBarDidTapDown(self)
    }

    @objc private func tapTab() {
        delegate?.inputBarDidTapTab(self)
    }

    // MARK: - UITextFieldDelegate

    public func textField(_ textField: UITextField,
                          shouldChangeCharactersIn range: NSRange,
                          replacementString string: String) -> Bool {
        let updated = (textField.text as NSString?)?.replacingCharacters(in: range, with: string)
        delegate?.inputBar(self, didChange: updated ?? "")
        return true
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit()
        return false
    }
}