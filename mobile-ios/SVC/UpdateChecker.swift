import Foundation

/// Majburiy yangilanish — iOS varianti (Android'dagi `UpdateManager.kt` bilan juftlik).
///
/// **Android'dan farqi — bu Apple cheklovi, kamchilik emas:** iOS'da ilova o'zini
/// o'zi o'rnata olmaydi (App Store'dan tashqari o'rnatish taqiqlangan). Shu sababli
/// bu yerda faqat *bloklash* qismi bir xil: eski build ishlamaydi, foydalanuvchi
/// TestFlight/App Store sahifasiga yo'naltiriladi. Yuklab olish va o'rnatishni tizim
/// bajaradi.
///
/// Server bitta `version.json` beradi; iOS o'z bo'limini (`ios`) o'qiydi.
enum UpdateChecker {

    private static let versionURL = URL(string: "https://svc.co1nlist.uz/downloads/version.json")!

    struct Info {
        let build: Int
        let versionName: String
        let url: URL?
        let notes: String?
        /// true — yangilanmaguncha ilova bloklanadi.
        let mandatory: Bool
    }

    /// Info.plist'dagi `CFBundleVersion` (project.yml → CURRENT_PROJECT_VERSION).
    static var installedBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    static var installedVersionName: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// nil — yangilanish yo'q yoki tekshirib bo'lmadi.
    ///
    /// Tarmoq yo'q bo'lsa ilova bloklanmaydi (fail-open): serversiz ilova baribir
    /// foydasiz, lekin uni "g'ishtga" aylantirmaymiz.
    static func check() async -> Info? {
        var req = URLRequest(url: versionURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 10

        guard
            let (data, resp) = try? await URLSession.shared.data(for: req),
            (resp as? HTTPURLResponse)?.statusCode == 200,
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let ios = root["ios"] as? [String: Any],
            let latest = ios["build"] as? Int
        else { return nil }

        let installed = installedBuild
        guard latest > installed else { return nil }

        // minBuild ko'rsatilmagan bo'lsa — yangilanish ixtiyoriy.
        let minRequired = ios["minBuild"] as? Int ?? 0
        let notes = (ios["notes"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        return Info(
            build: latest,
            versionName: ios["versionName"] as? String ?? "\(latest)",
            url: (ios["url"] as? String).flatMap(URL.init(string:)),
            notes: notes,
            mandatory: installed < minRequired
        )
    }
}
