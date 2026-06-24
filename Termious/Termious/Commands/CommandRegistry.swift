import Foundation

public struct CommandContext {
    public let fs: VirtualFileSystem
    public let env: [String: String]
    public let stdin: String
    public let stdout: (String) -> Void
    public let stderr: (String) -> Void

    public init(fs: VirtualFileSystem, env: [String: String], stdin: String,
                stdout: @escaping (String) -> Void, stderr: @escaping (String) -> Void) {
        self.fs = fs
        self.env = env
        self.stdin = stdin
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol BuiltinCommand {
    var name: String { get }
    var summary: String { get }
    var usage: String { get }
    var operands: [Operand] { get }
    func run(arguments: [String], context: CommandContext) -> Int32
}

/// Describes a single operand (argument) that a command accepts.
public struct Operand: Equatable {
    public let name: String
    public let description: String
    public let required: Bool
    public let type: OperandType

    public init(name: String, description: String, required: Bool = false, type: OperandType = .string) {
        self.name = name
        self.description = description
        self.required = required
        self.type = type
    }
}

public enum OperandType: Equatable {
    case string
    case path
    case number
    case pattern
    case `file`
    case directory
}

/// Default implementation so commands without explicit operands don't need to declare them.
public extension BuiltinCommand {
    var operands: [Operand] { [] }
}

public final class CommandRegistry {
    public private(set) var commands: [String: BuiltinCommand] = [:]

    public init() {
        register(LsCommand())
        register(CdCommand())
        register(PwdCommand())
        register(EchoCommand())
        register(CatCommand())
        register(MkdirCommand())
        register(RmCommand())
        register(CpCommand())
        register(MvCommand())
        register(TouchCommand())
        register(HeadCommand())
        register(TailCommand())
        register(WcCommand())
        register(GrepCommand())
        register(FindCommand())
        register(ClearCommand())
        register(HelpCommand())
        register(ExitCommand())
        register(BookmarksCommand())
        register(OpenCommand())
        register(WriteCommand())
        register(TreeCommand())
        register(DateCommand())
        register(WhoamiCommand())
        register(EnvCommand())
        register(SortCommand())
        register(UniqCommand())
        register(StatCommand())
        register(DuCommand())
        register(AeroCommand())
        register(SudoCommand())
        register(PasswdCommand())
        register(ChownCommand())
        register(ChmodCommand())
        register(ChgrpCommand())
        register(WgetCommand())
        register(CurlCommand())
        register(ZipCommand())
        register(UnzipCommand())
        register(TarCommand())
        register(SedCommand())
        register(AwkCommand())
        register(CutCommand())
        register(TrCommand())
        register(DiffCommand())
        register(RevCommand())
        register(PasteCommand())
        register(BasenameCommand())
        register(DirnameCommand())
        register(RealpathCommand())
        register(FileCommand())
        register(WhichCommand())
        register(HistoryCommand())
        register(ManCommand())
        register(DfCommand())
        register(FreeCommand())
        register(UnameCommand())
        register(UptimeCommand())
        register(HostnameCommand())
        register(IdCommand())
        register(YesCommand())
        register(SeqCommand())
        register(NlCommand())
        register(TacCommand())
        register(HashCommand())
        register(Base64Command())
        register(SleepCommand())
        register(TimeCommand())
        register(ExportCommand())
        register(AliasCommand())
        register(PingCommand())
        register(LnCommand())
        register(InfoCommand())
        register(WatchCommand())
        register(RebootCommand())
        register(CreditsCommand())
        register(ColorsCommand())
        register(TeeCommand())
        register(XargsCommand())
        register(PrintfCommand())
        register(TestCommand())
        register(ExprCommand())
        register(BcCommand())
        register(CalCommand())
        register(ShufCommand())
        register(FactorCommand())
        register(CommCommand())
        register(JoinCommand())
        register(FmtCommand())
        register(FoldCommand())
        register(ExpandCommand())
        register(ColumnCommand())
        register(TsortCommand())
        register(SplitCommand())
        register(DdCommand())
        register(TruncateCommand())
        register(MktempCommand())
        register(ShredCommand())
        register(InstallCommand())
        register(TrueCommand())
        register(FalseCommand())
        register(LookCommand())
        register(CksumCommand())
        register(SumCommand())
        register(Sha1sumCommand())
        register(Sha256sumCommand())
        register(Sha512sumCommand())
        register(Base32Command())
        register(StringsCommand())
        register(OdCommand())
        register(XxdCommand())
        register(ReadlinkCommand())
        register(NprocCommand())
        register(LscpuCommand())
        register(GetconfCommand())
        register(UmaskCommand())
        register(UlimitCommand())
        register(TputCommand())
        register(SttyCommand())
        register(AproposCommand())
        register(TypeCommand())
        register(CommandCommand())
        register(PrintenvCommand())
        register(UnsetCommand())
        register(DirsCommand())
        register(PushdCommand())
        register(PopdCommand())
        register(UnaliasCommand())
        register(WCommand())
        register(UsersCommand())
        register(LastCommand())
        register(DmesgCommand())
        register(LoggerCommand())
        register(LsofCommand())
        register(VmstatCommand())
        register(IostatCommand())
        register(LsblkCommand())
        register(MountCommand())
        register(PsCommand())
        register(KillCommand())
        register(UniqCCommand())
        register(ColormanCommand())
        register(ThemeCommand())
        register(ResizeCommand())
        register(HostnamectlCommand())
        register(TimedatectlCommand())
        register(UnitsCommand())
        register(BgCommand())
        register(GitCommand())
        register(SshKeygenCommand())
        register(NslookupCommand())
        register(DigCommand())
        register(HostCommand())
        register(IfconfigCommand())
        register(IpCommand())
        register(RouteCommand())
        register(ArpCommand())
        register(NetstatCommand())
        register(SystemctlCommand())
        register(JournalctlCommand())
        register(LoginctlCommand())
        register(ResolvectlCommand())
        register(LocalectlCommand())
        register(SystemdAnalyzeCommand())
        register(CrontabCommand())
        register(AtCommand())
        register(AtqCommand())
        register(AtrmCommand())
        register(AnacronCommand())
        register(CoredumpctlCommand())
        register(BusctlCommand())
        register(MachinectlCommand())
        register(UseraddCommand())
        register(UserdelCommand())
        register(UsermodCommand())
        register(GroupaddCommand())
        register(GroupdelCommand())
        register(GroupmodCommand())
        register(SuCommand())
        register(RunuserCommand())
        register(NiceCommand())
        register(ReniceCommand())
        register(ChrootCommand())
        register(SourceCommand())
        register(EvalCommand())
        register(ExecCommand())
        register(WaitCommand())
        register(LogoutCommand())
        register(LoginCommand())
        register(NewgrpCommand())
        register(FallocateCommand())
        register(RenameCommand())
        register(FindmntCommand())
        register(LslocksCommand())
        register(FuserCommand())
        register(LsattrCommand())
        register(ChattrCommand())
        register(GetfaclCommand())
        register(SetfaclCommand())
        register(MkfsCommand())
        register(LocaleCmdCommand())
        register(LocaledefCommand())
        register(LognameCommand())
        register(GroupsCommand())
        register(GetentCommand())
        register(GpasswdCommand())
        register(PwckCommand())
        register(GrpckCommand())
        register(VipwCommand())
        register(CompactCommand())
        register(BatchCommand())
        register(JobsCommand())
        register(DisownCommand())
        register(TrapCommand())
        register(SuspendCommand())
        register(ChfnCommand())
        register(ChshCommand())
        register(TineoCommand())
        register(XdgOpenCommand())
        register(SafariCommand())
        register(ClaudeCommand())
        register(HermesCommand())
        register(OpenClawCommand())
        register(AiCommand())
        register(GpuCommand())
        register(MetalCommand())
    }

    public func register(_ command: BuiltinCommand) {
        commands[command.name] = command
    }

    public func resolve(_ name: String) -> BuiltinCommand? {
        commands[name]
    }

    public var availableCommands: [String] {
        commands.keys.sorted()
    }
}