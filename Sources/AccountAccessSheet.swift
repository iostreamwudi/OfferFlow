import SwiftUI

/// Authentication adapters own network requests and session persistence. This screen
/// never stores passwords or turns a local workspace into an authenticated account.
struct CareerAccountIdentity: Equatable {
    let id: String
    let displayName: String
}

enum AccountAccessResult {
    case authenticated(CareerAccountIdentity)
    case confirmationRequired(String)
}

@MainActor protocol AccountAuthenticating {
    var accountAvailable: Bool { get }
    var weChatAvailable: Bool { get }
    func signIn(account: String, password: String) async throws -> AccountAccessResult
    func register(account: String, password: String) async throws -> AccountAccessResult
    func signInWithWeChat() async throws -> AccountAccessResult
}

private enum AccountAccessError: LocalizedError {
    case accountUnavailable
    case weChatUnavailable

    var errorDescription: String? {
        switch self {
        case .accountUnavailable:
            return "账号服务尚未开放，暂时无法注册或登录。你可以先使用本机工作区。"
        case .weChatUnavailable:
            return "微信登录尚未开放。你可以先使用本机工作区，已有岗位和草稿会保留。"
        }
    }
}

@MainActor private struct UnavailableAccountService: AccountAuthenticating {
    let accountAvailable = false
    let weChatAvailable = false

    func signIn(account: String, password: String) async throws -> AccountAccessResult {
        throw AccountAccessError.accountUnavailable
    }
    func register(account: String, password: String) async throws -> AccountAccessResult {
        throw AccountAccessError.accountUnavailable
    }
    func signInWithWeChat() async throws -> AccountAccessResult {
        throw AccountAccessError.weChatUnavailable
    }
}

@MainActor struct AccountAccessSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .signIn
    @State private var account = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var passwordVisible = false
    @State private var message = ""
    @State private var messageIsError = false
    @State private var busy = false
    @State private var request: Task<Void, Never>?
    @FocusState private var focusedField: Field?

    private let notice: String
    private let service: any AccountAuthenticating
    private let onAuthenticated: (CareerAccountIdentity) -> Void
    private let accountInk = Color(red: 0.16, green: 0.20, blue: 0.26)
    private let accountBlue = Color(red: 0.24, green: 0.33, blue: 0.48)
    private let secondaryInk = Color(red: 0.48, green: 0.52, blue: 0.58)

    private enum Mode: String, CaseIterable { case signIn = "登录", register = "注册" }
    private enum Field: Hashable { case account, password, confirmation }

    init(service: (any AccountAuthenticating)? = nil, notice: String = "",
         onAuthenticated: @escaping (CareerAccountIdentity) -> Void = { _ in }) {
        self.notice = notice
        self.service = service ?? UnavailableAccountService()
        self.onAuthenticated = onAuthenticated
    }

    var body: some View {
        FlowSurface {
        HStack(spacing: 0) {
            introduction.frame(width: 302)
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { leave() } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain).foregroundStyle(secondaryInk)
                    .help("返回工作区").accessibilityLabel("关闭登录窗口")
                }.padding(.top, 16).padding(.trailing, 18)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(mode == .signIn ? "欢迎回来" : "创建你的账号")
                            .font(.system(size: 27, weight: .semibold))
                        Text(mode == .signIn ? "继续你的下一步求职计划。" : "让求职资料与准备过程有序积累。")
                            .font(.system(size: 12)).foregroundStyle(secondaryInk).padding(.top, 8)

                        if !notice.isEmpty { Text(notice).font(.system(size: 12)).foregroundStyle(secondaryInk).padding(.top, 12).fixedSize(horizontal: false, vertical: true) }

                        HStack(spacing: 4) {
                            ForEach(Mode.allCases, id: \.self) { item in
                                Button { changeMode(item) } label: {
                                    Text(item.rawValue).font(.system(size: 13, weight: .medium))
                                        .frame(maxWidth: .infinity).frame(height: 34)
                                        .background(mode == item ? Color.white : .clear,
                                                    in: RoundedRectangle(cornerRadius: 6))
                                        .foregroundStyle(mode == item ? accountInk : secondaryInk)
                                }
                                .buttonStyle(.plain).disabled(busy)
                                .accessibilityLabel("切换到\(item.rawValue)")
                                .accessibilityAddTraits(mode == item ? .isSelected : [])
                            }
                        }
                        .padding(3).background(Color(red: 0.94, green: 0.95, blue: 0.97),
                                               in: RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 22)

                        if !service.accountAvailable || !service.weChatAvailable {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "info.circle").padding(.top, 1)
                                Text(availabilityMessage).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.system(size: 11)).foregroundStyle(secondaryInk).lineSpacing(3)
                            .padding(.vertical, 14)
                        } else { Color.clear.frame(height: 18) }

                        VStack(alignment: .leading, spacing: 13) {
                            fieldLabel("账号") {
                                TextField(mode == .register ? "3–32 位字母、数字或下划线" : "请输入账号", text: $account)
                                    .textFieldStyle(.plain).font(.system(size: 13))
                                    .textContentType(.username).focused($focusedField, equals: .account)
                                    .accessibilityLabel("账号")
                                    .onSubmit { focusedField = .password }
                                    .padding(.horizontal, 12).frame(height: 40)
                                    .background(fieldBackground(focusedField == .account))
                            }
                            passwordField("密码", value: $password, field: .password,
                                          placeholder: mode == .register ? "设置 8–64 位密码" : "请输入密码")
                            if mode == .register {
                                passwordField("确认密码", value: $confirmation, field: .confirmation,
                                              placeholder: "再次输入密码")
                            }
                        }.disabled(busy)

                        if !message.isEmpty {
                            Text(message).font(.system(size: 11)).lineSpacing(3)
                                .foregroundStyle(messageIsError ? Color(red: 0.66, green: 0.29, blue: 0.25) : secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("账号提示：\(message)")
                                .padding(.top, 12)
                        }

                        Button { submitAccount() } label: {
                            HStack(spacing: 8) {
                                if busy { ProgressView().controlSize(.small).tint(.white) }
                                Text(busy ? "正在处理…" : mode == .signIn ? "登录" : "创建账号")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(accountBlue.opacity(busy ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(.white)
                        }.buttonStyle(.plain).disabled(busy).padding(.top, 18)

                        HStack(spacing: 12) {
                            Rectangle().fill(Color.gray.opacity(0.17)).frame(height: 1)
                            Text("或").font(.system(size: 11)).foregroundStyle(secondaryInk)
                            Rectangle().fill(Color.gray.opacity(0.17)).frame(height: 1)
                        }.padding(.vertical, 15)

                        Button { submitWeChat() } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: 17)).foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))
                                Text("微信登录").font(.system(size: 13, weight: .medium))
                            }
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 7).stroke(Color.gray.opacity(0.22)))
                        }.buttonStyle(.plain).disabled(busy)
                    }.padding(.horizontal, 42).padding(.top, 2).padding(.bottom, 16)
                }.scrollIndicators(.hidden)

                VStack(spacing: 7) {
                    Button("暂不登录，使用本机工作区") { leave() }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accountBlue).keyboardShortcut(.cancelAction)
                    Text("本机模式可继续使用已有岗位与草稿")
                        .font(.system(size: 10)).foregroundStyle(secondaryInk)
                }.padding(.top, 12).padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity).background(.white)
        }
        .frame(width: 830, height: 650)
        .foregroundStyle(accountInk).tint(accountBlue)
        .onDisappear { request?.cancel(); password = ""; confirmation = "" }
    
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.right.square.fill")
                    .font(.system(size: 28)).foregroundStyle(accountBlue)
                Text("OfferFlow").font(.system(size: 21, weight: .semibold))
            }
            Spacer()
            Text("把精力留给\n真正的机会。")
                .font(.system(size: 30, weight: .semibold)).lineSpacing(9)
            Text("从发现岗位，到准备下一次面试。\n让每一步求职行动更清楚。")
                .font(.system(size: 12)).foregroundStyle(secondaryInk).lineSpacing(7)
                .padding(.top, 20)
            VStack(alignment: .leading, spacing: 18) {
                introductionItem("magnifyingglass", "发现合适的岗位")
                introductionItem("tray.full", "整理投递与沟通进展")
                introductionItem("text.bubble", "围绕目标做好准备")
            }.padding(.top, 36)
            Spacer()
            HStack(spacing: 7) {
                Image(systemName: "desktopcomputer").font(.system(size: 12))
                Text("为专注的求职过程而设计").font(.system(size: 10))
            }.foregroundStyle(secondaryInk)
        }
        .padding(.horizontal, 34).padding(.vertical, 38)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(red: 0.94, green: 0.95, blue: 0.97))
    }

    private var availabilityMessage: String {
        if !service.accountAvailable && !service.weChatAvailable {
            return "账号与微信登录正在准备中。当前可先使用本机工作区，无需填写密码。"
        }
        return service.accountAvailable ? "微信登录正在准备中，可先使用账号密码登录。" : "账号注册与密码登录正在准备中，可使用微信登录。"
    }

    private func introductionItem(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 15)).frame(width: 20)
                .foregroundStyle(accountBlue)
            Text(title).font(.system(size: 12)).foregroundStyle(accountInk.opacity(0.85))
        }
    }

    private func fieldLabel<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(accountInk.opacity(0.85))
            content()
        }
    }

    private func fieldBackground(_ focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7).fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(focused ? accountBlue.opacity(0.75) : Color.gray.opacity(0.25), lineWidth: 1))
    }

    private func passwordField(_ label: String, value: Binding<String>, field: Field, placeholder: String) -> some View {
        fieldLabel(label) {
            HStack(spacing: 8) {
                Group {
                    if passwordVisible { TextField(placeholder, text: value) }
                    else { SecureField(placeholder, text: value) }
                }
                .textFieldStyle(.plain).font(.system(size: 13))
                .textContentType(mode == .register ? .newPassword : .password)
                .focused($focusedField, equals: field).accessibilityLabel(label)
                .onSubmit {
                    if field == .password && mode == .register { focusedField = .confirmation }
                    else { submitAccount() }
                }
                Button {
                    passwordVisible.toggle()
                    focusedField = field
                } label: {
                    Image(systemName: passwordVisible ? "eye.slash" : "eye")
                        .font(.system(size: 12)).frame(width: 24, height: 28)
                }
                .buttonStyle(.plain).foregroundStyle(secondaryInk)
                .accessibilityLabel(passwordVisible ? "隐藏\(label)" : "显示\(label)")
            }
            .padding(.horizontal, 12).frame(height: 40)
            .background(fieldBackground(focusedField == field))
        }
    }

    private func changeMode(_ newMode: Mode) {
        guard !busy, mode != newMode else { return }
        mode = newMode
        password = ""; confirmation = ""; passwordVisible = false; message = ""
        focusedField = .account
    }

    private func submitAccount() {
        guard !busy else { return }
        let identifier = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { showError("请输入账号。"); focusedField = .account; return }
        guard !password.isEmpty else { showError("请输入密码。"); focusedField = .password; return }
        if mode == .register {
            guard identifier.range(of: "^[A-Za-z0-9_]{3,32}$", options: .regularExpression) != nil else {
                showError("账号需为 3–32 位字母、数字或下划线。"); focusedField = .account; return
            }
            guard (8...64).contains(password.count) else {
                showError("请设置 8–64 位密码。"); focusedField = .password; return
            }
            guard password == confirmation else {
                showError("两次输入的密码不一致。"); focusedField = .confirmation; return
            }
        }
        guard service.accountAvailable else {
            password = ""; confirmation = ""; passwordVisible = false
            showError(AccountAccessError.accountUnavailable.localizedDescription); return
        }
        let submittedPassword = password
        let submittedMode = mode
        perform {
            if submittedMode == .register { return try await service.register(account: identifier, password: submittedPassword) }
            return try await service.signIn(account: identifier, password: submittedPassword)
        }
    }

    private func submitWeChat() {
        guard !busy else { return }
        guard service.weChatAvailable else { showError(AccountAccessError.weChatUnavailable.localizedDescription); return }
        perform { try await service.signInWithWeChat() }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> AccountAccessResult) {
        busy = true; message = ""; focusedField = nil
        request = Task { @MainActor in
            defer { busy = false; password = ""; confirmation = ""; passwordVisible = false }
            do {
                let result = try await operation()
                guard !Task.isCancelled else { return }
                switch result {
                case .authenticated(let identity): onAuthenticated(identity); dismiss()
                case .confirmationRequired(let instruction): message = instruction; messageIsError = false
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ text: String) { message = text; messageIsError = true }
    private func leave() { request?.cancel(); password = ""; confirmation = ""; dismiss() }
}
