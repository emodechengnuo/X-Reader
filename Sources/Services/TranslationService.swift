//
//  TranslationService.swift
//  X-Reader
//
//  Translation via Apple Translation, Google Translate & Baidu Translate
//


import Foundation
import CryptoKit
import Translation

class TranslationService: ObservableObject {
    
    // MARK: - Engine Selection
    
    enum Engine: String, CaseIterable, Identifiable {
        case apple = "apple"
        case google = "google"
        case baidu = "baidu"
        
        var id: String { rawValue }
        
        /// 本地化显示名（中文：苹果本地/谷歌在线/百度在线；英文：Apple/Google/Baidu）
        func displayName(lang: AppLanguage = L10n.shared.language) -> String {
            switch lang {
            case .chinese:
                switch self {
                case .apple:  return "苹果本地"
                case .google: return "谷歌在线"
                case .baidu:  return "百度在线"
                }
            case .english:
                switch self {
                case .apple:  return "Apple"
                case .google: return "Google"
                case .baidu:  return "Baidu"
                }
            }
        }
        
        /// 设置页 Picker 所用的完整名称
        func fullDisplayName(lang: AppLanguage = L10n.shared.language) -> String {
            switch lang {
            case .chinese:
                switch self {
                case .apple:  return "苹果本地"
                case .google: return "谷歌在线"
                case .baidu:  return "百度在线"
                }
            case .english:
                switch self {
                case .apple:  return "Apple (Local)"
                case .google: return "Google (Online)"
                case .baidu:  return "Baidu (Online)"
                }
            }
        }
    }
    
    // MARK: - Apple Translation Session (macOS 15+)
    
    private var appleSession: TranslationSession?
    
    // Use UserDefaults directly (not @AppStorage — this isn't a View)
    
    private static let engineKey = "translation_engine"
    private static let baiduAppIdKey = "baidu_app_id"
    private static let baiduSecretKeyKey = "baidu_secret_key"
    
    var currentEngine: Engine {
        get { Engine(rawValue: UserDefaults.standard.string(forKey: Self.engineKey) ?? "") ?? .google }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.engineKey)
            objectWillChange.send()  // 通知 @ObservedObject 刷新 UI
        }
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
        
        let isChinese = L10n.shared.language == .chinese
        let selected = currentEngine
        
        // Build fallback chain: selected engine first, then Google → Baidu → Apple (excluding selected)
        let fallbackOrder: [Engine] = [.google, .baidu, .apple].filter { $0 != selected }
        let chain: [Engine] = [selected] + fallbackOrder
        
        var errors: [(engine: Engine, message: String)] = []
        
        for engine in chain {
            // Skip Baidu if not configured
            if engine == .baidu && !isBaiduConfigured {
                let msg = isChinese ? "百度在线未配置（需填入 App ID 和密钥）" : "Baidu not configured (App ID & Secret Key required)"
                errors.append((engine, msg))
                continue
            }
            
            let (resultText, errorMsg) = await callEngine(engine, text: text)
            
            if !resultText.isEmpty {
                // Success — if we fell back, note it in error field AND update currentEngine
                if engine != selected {
                    currentEngine = engine  // 持久化切换，下次翻译也用这个引擎
                    let usedName = engine.displayName(lang: L10n.shared.language)
                    let selectedName = selected.displayName(lang: L10n.shared.language)
                    let note = isChinese
                        ? "[\(selectedName) 失败，已自动切换至 \(usedName)]"
                        : "[\(selectedName) failed, switched to \(usedName)]"
                    return TranslateResult(text: resultText, error: note)
                }
                return TranslateResult(text: resultText, error: nil)
            }
            
            // Record failure
            let engineName = engine.displayName(lang: L10n.shared.language)
            let msg = errorMsg ?? (isChinese ? "未知错误" : "Unknown error")
            errors.append((engine, "\(engineName): \(msg)"))
        }
        
        // All engines failed
        let details = errors.map { $0.message }.joined(separator: "\n")
        let header = isChinese ? "所有翻译引擎均失败：\n" : "All engines failed:\n"
        return TranslateResult(text: "", error: header + details)
    }
    
    /// Call a single engine, returns (translatedText, errorMessage)
    private func callEngine(_ engine: Engine, text: String) async -> (String, String?) {
        switch engine {
        case .apple:
            let result = await translateWithApple(text)
            if result.isEmpty {
                let msg = L10n.shared.language == .chinese
                    ? "Apple 翻译无响应（可能需要网络或系统语言包）"
                    : "Apple Translate returned no result (may need network or language pack)"
                return ("", msg)
            }
            return (result, nil)
        case .google:
            let result = await translateWithGoogle(text)
            if result.isEmpty {
                let msg = L10n.shared.language == .chinese
                    ? "网络请求失败或响应解析错误"
                    : "Network request failed or response parse error"
                return ("", msg)
            }
            return (result, nil)
        case .baidu:
            let baiduResult = await translateWithBaidu(text)
            if let err = baiduResult.error {
                return ("", err)
            }
            return (baiduResult.text, nil)
        }
    }
    
    // MARK: - Apple Translation (macOS 15+)
    
    /// Lazy-initialize session on first use (TranslationSession requires user-gesture to present)
    private func translateWithApple(_ text: String) async -> String {
        guard let session = appleSession else {
            // Fallback chain in translateWithFeedback will handle this
            return ""
        }
        do {
            let response = try await session.translate(text)
            return response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("[TranslationService] Apple translate error: \(error)")
            return ""
        }
    }
    
    /// Called by .translationTask view modifier to set the session from SwiftUI
    func setAppleSession(_ session: TranslationSession) {
        self.appleSession = session
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
