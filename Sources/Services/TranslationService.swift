//
//  TranslationService.swift
//  X-Reader
//
//  Translation via Google Translate & Baidu Translate
//


import Foundation
import CryptoKit

class TranslationService: ObservableObject {
    
    // MARK: - Engine Selection
    
    enum Engine: String, CaseIterable, Identifiable {
        case google = "google"
        case baidu = "baidu"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .google: return "Google 翻译"
            case .baidu: return "百度翻译"
            }
        }
    }
    
    // Use UserDefaults directly (not @AppStorage — this isn't a View)
    
    private static let engineKey = "translation_engine"
    private static let baiduAppIdKey = "baidu_app_id"
    private static let baiduSecretKeyKey = "baidu_secret_key"
    
    var currentEngine: Engine {
        get { Engine(rawValue: UserDefaults.standard.string(forKey: Self.engineKey) ?? "") ?? .google }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.engineKey) }
    }
    
    var baiduAppId: String {
        get { UserDefaults.standard.string(forKey: Self.baiduAppIdKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.baiduAppIdKey) }
    }
    
    var baiduSecretKey: String {
        get { UserDefaults.standard.string(forKey: Self.baiduSecretKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.baiduSecretKeyKey) }
    }
    
    var isBaiduConfigured: Bool {
        !baiduAppId.trimmingCharacters(in: .whitespaces).isEmpty &&
        !baiduSecretKey.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private let session = URLSession.shared
    
    // MARK: - Result type
    
    struct TranslateResult {
        let text: String
        let error: String?
    }
    
    // MARK: - Public
    
    func translate(_ text: String) async -> String {
        let result = await translateWithFeedback(text)
        return result.text
    }
    
    /// Translate with error feedback — returns both text and error message
    func translateWithFeedback(_ text: String) async -> TranslateResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return TranslateResult(text: "", error: nil)
        }
        
        switch currentEngine {
        case .google:
            let result = await translateWithGoogle(text)
            if result.isEmpty {
                return TranslateResult(text: "", error: "Google 翻译失败")
            }
            return TranslateResult(text: result, error: nil)
        case .baidu:
            if isBaiduConfigured {
                let baiduResult = await translateWithBaidu(text)
                if let error = baiduResult.error {
                    // Baidu failed — show error + fallback to Google
                    let googleResult = await translateWithGoogle(text)
                    if googleResult.isEmpty {
                        return TranslateResult(text: "", error: "百度翻译: \(error)\nGoogle 翻译也失败了")
                    }
                    return TranslateResult(text: googleResult, error: "百度翻译: \(error)（已自动切换 Google）")
                }
                return baiduResult
            }
            // Baidu not configured, use Google
            let result = await translateWithGoogle(text)
            if result.isEmpty {
                return TranslateResult(text: "", error: "百度翻译未配置，Google 翻译也失败了")
            }
            return TranslateResult(text: result, error: nil)
        }
    }
    
    // MARK: - Google Translate
    
    private func translateWithGoogle(_ text: String) async -> String {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return "" }
        let urlString = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=zh-CN&dt=t&q=\(encoded)"
        guard let url = URL(string: urlString) else { return "" }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("[TranslationService] Google HTTP error: \(response)")
                return ""
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                  let translations = json.first as? [[Any]] else {
                print("[TranslationService] Google parse error")
                return ""
            }
            
            var result = ""
            for item in translations {
                if let textArray = item as? [Any], textArray.count > 0,
                   let translated = textArray[0] as? String {
                    result += translated
                }
            }
            
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch {
            print("[TranslationService] Google error: \(error)")
            return ""
        }
    }
    
    // MARK: - Baidu Translate
    
    private func translateWithBaidu(_ text: String) async -> TranslateResult {
        let appId = baiduAppId.trimmingCharacters(in: .whitespaces)
        let secretKey = baiduSecretKey.trimmingCharacters(in: .whitespaces)
        
        guard !appId.isEmpty && !secretKey.isEmpty else {
            return TranslateResult(text: "", error: "未配置 App ID 或密钥")
        }
        
        let salt = String(Int(Date().timeIntervalSince1970))
        let signInput = appId + text + salt + secretKey
        
        // MD5 hash
        let sign = Insecure.MD5.hash(data: Data(signInput.utf8))
            .map { String(format: "%02hhx", $0) }
            .joined()
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "fanyi-api.baidu.com"
        components.path = "/api/trans/vip/translate"
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "from", value: "en"),
            URLQueryItem(name: "to", value: "zh"),
            URLQueryItem(name: "appid", value: appId),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "sign", value: sign),
        ]
        
        guard let url = components.url else {
            return TranslateResult(text: "", error: "URL 构建失败")
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return TranslateResult(text: "", error: "无网络响应")
            }
            
            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return TranslateResult(text: "", error: "HTTP \(httpResponse.statusCode): \(body)")
            }
            
            let parsed = try JSONSerialization.jsonObject(with: data)
            guard let json = parsed as? [String: Any] else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return TranslateResult(text: "", error: "返回数据格式错误: \(body)")
            }
            
            // Check for API error
            if let errorCode = json["error_code"] as? String, let errorMsg = json["error_msg"] as? String {
                return TranslateResult(text: "", error: "错误 \(errorCode): \(errorMsg)")
            }
            if let errorCode = json["error_code"] as? Int {
                let errorMsg = json["error_msg"] as? String ?? "未知错误"
                // Map common error codes to helpful messages
                let hint: String
                switch errorCode {
                case 54001:
                    hint = "签名错误 — 请检查 App ID 和密钥是否正确、是否复制完整（密钥通常为 32 位）"
                case 54003:
                    hint = "未授权 — 请在百度翻译开放平台开通「通用文本翻译」服务"
                case 54004:
                    hint = "账户余额不足 — 请充值或等待免费额度恢复"
                case 54005:
                    hint = "请求频率过高 — 请稍后再试"
                case 58002:
                    hint = "服务关闭 — 请在控制台重新开通翻译服务"
                default:
                    hint = errorMsg
                }
                return TranslateResult(text: "", error: "错误 \(errorCode): \(hint)")
            }
            
            guard let transResult = json["trans_result"] as? [[String: Any]] else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return TranslateResult(text: "", error: "无翻译结果: \(body)")
            }
            
            let result = transResult.compactMap { $0["dst"] as? String }.joined(separator: "")
            let text = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return TranslateResult(text: "", error: "翻译结果为空")
            }
            return TranslateResult(text: text, error: nil)
            
        } catch {
            return TranslateResult(text: "", error: "网络错误: \(error.localizedDescription)")
        }
    }
}
