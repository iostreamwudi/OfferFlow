import Foundation

@main struct CareerMailProviderTests {
    static func main() {
        let netease = CareerMailProvider.detect("  demo@163.COM \n")!
        precondition(netease.imapHost == "imap.163.com" && netease.smtpHost == "smtp.163.com")
        precondition(CareerMailProvider.detect("demo@foxmail.com")?.imapHost == "imap.qq.com")
        precondition(CareerMailProvider.detect("demo@googlemail.com")?.smtpHost == "smtp.gmail.com")
        for unknown in ["demo@163.com.evil.example", "demo@custom.example", "demo@@163.com", "@163.com", "163.com"] {
            precondition(CareerMailProvider.detect(unknown) == nil)
        }
        let outlook = CareerMailProvider.detect("demo@outlook.com")!
        precondition(outlook.oauthOnly && outlook.imapHost.isEmpty && outlook.smtpHost.isEmpty)
        precondition(CareerMailProvider.failureMessage(67).contains("授权码"))
        precondition(CareerMailProvider.failureMessage(28).contains("超时"))
        print("PASS exact-domain detection, aliases, unknown/spoofed domain rejection, OAuth-only provider and error guidance")
    }
}
