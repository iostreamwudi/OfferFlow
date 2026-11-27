import Foundation

struct CareerMailProvider {
    let name: String
    let domain: String
    let credentialLabel: String
    let helpURL: String
    let oauthOnly: Bool
    var imapHost: String { oauthOnly ? "" : "imap." + domain }
    var smtpHost: String { oauthOnly ? "" : "smtp." + domain }
    var hint: String {
        domain == "gmail.com" ? "请填写 Google 应用专用密码，不是 Google 登录密码。" : "请填写邮箱设置中生成的客户端授权码，不是网页登录密码。"
    }
    var steps: String {
        if domain == "gmail.com" {
            return "1. 在 Google 账号中开启两步验证。\n2. 创建供 OfferFlow 使用的应用专用密码。\n3. 回到这里粘贴应用专用密码并连接。若账号不提供此选项，请遵循账号管理员的要求。"
        }
        if domain == "qq.com" {
            return "1. 打开 QQ 邮箱网页版，登录自己的账号。\n2. 进入设置，找到账号或第三方服务中的 IMAP/SMTP 服务。\n3. 开启服务，按页面提示完成验证，生成并复制授权码。\n4. 回到 OfferFlow，输入完整邮箱地址和授权码，点击连接邮箱。"
        }
        return "1. 打开网易邮箱网页版，登录自己的账号。\n2. 进入设置 → POP3/SMTP/IMAP 或客户端授权设置。\n3. 开启 IMAP/SMTP 服务，完成验证，新增并复制客户端授权码。\n4. 回到 OfferFlow，输入完整邮箱地址和授权码，点击连接邮箱。"
    }
    static func detect(_ address: String) -> Self? {
        let parts = address.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        let domain = parts[1].lowercased()
        switch domain {
        case "163.com", "126.com":
            return .init(name: "网易 " + domain, domain: domain, credentialLabel: "客户端授权码",
                         helpURL: "https://mail." + domain + "/", oauthOnly: false)
        case "qq.com", "foxmail.com":
            return .init(name: "QQ 邮箱", domain: "qq.com", credentialLabel: "客户端授权码",
                         helpURL: "https://mail.qq.com/", oauthOnly: false)
        case "gmail.com", "googlemail.com":
            return .init(name: "Gmail", domain: "gmail.com", credentialLabel: "应用专用密码",
                         helpURL: "https://support.google.com/mail/answer/185833?hl=zh-Hans", oauthOnly: false)
        case "outlook.com", "hotmail.com", "live.com", "msn.com", "outlook.cn":
            return .init(name: "Microsoft Outlook", domain: domain, credentialLabel: "官方授权登录",
                         helpURL: "https://outlook.live.com/", oauthOnly: true)
        default: return nil
        }
    }
    static func failureMessage(_ code: Int32) -> String {
        switch code {
        case 67: return "邮箱未接受登录。请检查邮箱地址，并使用客户端授权码或应用专用密码；确认已开启 IMAP 服务。"
        case 6: return "无法找到邮箱服务器。请检查网络；自定义邮箱请核对高级设置中的服务器地址。"
        case 7, 28: return "暂时无法连接邮箱服务器或连接超时，请检查网络后重试。"
        case 35, 60: return "邮箱的加密连接验证失败，请检查网络或联系邮箱服务商。"
        default: return "邮箱连接失败（代码 \(code)）。请确认已开启 IMAP 服务，并核对授权码；自定义邮箱请检查高级设置。"
        }
    }
}
