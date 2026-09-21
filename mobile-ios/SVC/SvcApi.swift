import Foundation

// MARK: - Modellar
// Barcha JSON kalitlari snake_case (Phoenix) — dekoder .convertFromSnakeCase bilan
// avtomatik camelCase'ga o'giradi, shuning uchun CodingKeys yozilmaydi.

struct NamedRef: Decodable {
    let id: Int64?
    let name: String?
}

struct Profile: Decodable, Identifiable {
    let id: Int64
    let username: String?
    let fullName: String?
    let role: String?
    let phone: String?
    let status: String?
    let department: NamedRef?
    let organization: NamedRef?

    var displayName: String {
        let n = fullName ?? ""
        return n.isEmpty ? (username ?? "—") : n
    }
    var roleValue: String { role ?? "" }
}

struct Colleague: Decodable, Identifiable {
    let id: Int64
    let username: String?
    let fullName: String?
    let role: String?
    let phone: String?
    let status: String?

    var displayName: String {
        let n = fullName ?? ""
        return n.isEmpty ? (username ?? "—") : n
    }
    var roleValue: String { role ?? "" }
    var isActive: Bool { (status ?? "active") == "active" }
    /// Avatar uchun bosh harf.
    var initial: String {
        String(displayName.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}

struct MeetingItem: Decodable, Identifiable {
    let id: Int64
    let title: String?
    let status: String?
    let type: String?
    let scheduledStart: String?
    // S43 — majlis tarixi: nima uchun yig'ilgan, qachon ochilib yopilgan, natija.
    let purpose: String?
    let summary: String?
    let startedAt: String?
    let endedAt: String?
    let durationSeconds: Int?
    let startedByName: String?
    let endedByName: String?
    /// Serverning ruxsat hisobi — tugmani kimga ko'rsatishni bilish uchun
    /// (server har bir so'rovda baribir qayta tekshiradi).
    let canOpen: Bool?
    let canClose: Bool?
    /// S44: hali majlisga kirmagan taklif qilinganlar soni.
    let pendingCount: Int?

    var mayOpen: Bool { canOpen ?? false }
    var mayClose: Bool { canClose ?? false }
    var pending: Int { pendingCount ?? 0 }

    /// "21.09 15:40 — 16:25" — majlis haqiqatda qachon bo'lgani.
    var sessionRange: String? {
        guard let from = Labels.localDateTime(startedAt) else { return nil }
        guard let to = Labels.localTime(endedAt) else { return from }
        return "\(from) — \(to)"
    }

    var displayTitle: String {
        let t = title ?? ""
        return t.isEmpty ? "Uchrashuv №\(id)" : t
    }
    var subtitle: String {
        [Labels.meetingStatus(status ?? ""), Labels.date(scheduledStart)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

struct NotificationItem: Decodable, Identifiable {
    let id: Int64
    let kind: String?
    let title: String?
    let body: String?
    let readAt: String?
    let insertedAt: String?

    var isUnread: Bool { readAt == nil }
    var kindValue: String { kind ?? "" }
}

struct MeetingsPage: Decodable {
    let meetings: [MeetingItem]
    let canOrganize: Bool?
}

struct NotificationsPage: Decodable {
    let unread: Int?
    let notifications: [NotificationItem]
}

struct Session {
    let token: String
    let fullName: String
    let role: String

    /// Majlis yarata oladigan rollar (D-015/D-016). Serverda ham tekshiriladi.
    var canOrganize: Bool { role == "super_admin" || role == "manager" }
}

struct RoomInfo {
    let url: String
    let token: String
    let room: String
}

struct GeoPoint {
    let lat: Double
    let lon: Double
    let accuracy: Double?
}

enum LoginResult {
    case success(Session)
    case totpRequired(String)
}

/// Yordamchi bazasidagi bitta yozuv (S39) — server bilan bir xil: id/topic/question/answer.
/// Hujjat (S41). Xodimga eng kerakli uchtasi: KIMDAN, NIMA QILISH, QACHONGACHA.
struct DocumentItem: Decodable, Identifiable {
    struct Sender: Decodable {
        let id: Int64?
        let fullName: String?
    }

    let id: Int64
    let title: String
    let filename: String
    let byteSize: Int64
    let action: String
    let actionLabel: String?
    let note: String?
    let dueAt: String?
    let from: Sender?
    let mine: Bool?
    let acknowledgedAt: String?

    var isMine: Bool { mine ?? false }
    var senderName: String { from?.fullName ?? "" }
    var isAcknowledged: Bool { acknowledgedAt != nil }
}

struct DocumentsPage: Decodable {
    let documents: [DocumentItem]
}

struct AssistantEntry: Decodable, Identifiable, Hashable {
    let id: String
    let topic: String
    let question: String
    let answer: String
    static let empty = AssistantEntry(id: "", topic: "", question: "", answer: "")
}

/// `/api/assistant/ask` javobi — serverdagi to'rt holat (S37/D-019).
enum AssistResult {
    case ok(AssistantEntry, related: [AssistantEntry])
    case unsure([AssistantEntry])
    case restricted(question: String, roleLabels: [String])
    case noMatch([AssistantEntry])
}

enum ApiError: LocalizedError {
    case http(Int, String?)
    case forbidden
    case badResponse

    var errorDescription: String? {
        switch self {
        case .forbidden:
            return "Ruxsat yo'q"
        case .badResponse:
            return "Serverdan noto'g'ri javob"
        case let .http(code, msg):
            if code == 401 { return "Login yoki parol noto'g'ri" }
            if let msg { return "Xatolik (\(code)): \(msg)" }
            return "Xatolik (\(code))"
        }
    }
}

// MARK: - Klient

/// Phoenix REST API klienti — Android'dagi `SvcApi.kt` bilan bir xil endpointlar.
/// Server manzili UI'da ko'rsatilmaydi (konstanta).
actor SvcApi {
    static let serverURL = "https://admin.co1nlist.uz"

    private let base: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: String = SvcApi.serverURL) {
        guard let url = URL(string: baseURL) else {
            fatalError("Noto'g'ri server URL: \(baseURL)")
        }
        self.base = url

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)

        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = d
    }

    // MARK: Auth

    func login(username: String, password: String) async throws -> LoginResult {
        let json = try await postJSON("/api/login", body: ["username": username, "password": password])
        if json["totp_required"] as? Bool == true, let t = json["totp_token"] as? String {
            return .totpRequired(t)
        }
        return .success(try parseSession(json))
    }

    func verifyTotp(totpToken: String, code: String) async throws -> Session {
        let json = try await postJSON("/api/login/totp", body: ["totp_token": totpToken, "code": code])
        return try parseSession(json)
    }

    private func parseSession(_ json: [String: Any]) throws -> Session {
        guard let token = json["token"] as? String,
              let user = json["user"] as? [String: Any]
        else { throw ApiError.badResponse }
        return Session(
            token: token,
            fullName: user["full_name"] as? String ?? "",
            role: user["role"] as? String ?? ""
        )
    }

    // MARK: Ma'lumotlar

    func me(token: String) async throws -> Profile {
        struct Wrap: Decodable { let user: Profile }
        let data = try await getData("/api/me", token: token)
        return try decoder.decode(Wrap.self, from: data).user
    }

    func colleagues(token: String) async throws -> [Colleague] {
        try await userList(path: "/api/users", token: token)
    }

    func assignable(token: String) async throws -> [Colleague] {
        try await userList(path: "/api/assignable", token: token)
    }

    private func userList(path: String, token: String) async throws -> [Colleague] {
        struct Wrap: Decodable { let users: [Colleague] }
        let data = try await getData(path, token: token)
        return try decoder.decode(Wrap.self, from: data).users
    }

    func meetings(token: String) async throws -> MeetingsPage {
        let data = try await getData("/api/meetings", token: token)
        return try decoder.decode(MeetingsPage.self, from: data)
    }

    /// S43. Majlisni OCHISH — kim va qachon ochgani serverda qoladi.
    /// Ochgan xodim keyin uni yakunlaydi.
    func openMeeting(token: String, meetingId: Int64) async throws {
        _ = try await postJSON("/api/meetings/\(meetingId)/open", body: [:], token: token)
    }

    /// S43. Majlisni YAKUNLASH — natija tarixga yoziladi.
    func closeMeeting(token: String, meetingId: Int64, summary: String?) async throws {
        var body: [String: Any] = [:]
        if let s = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            body["summary"] = s
        }
        _ = try await postJSON("/api/meetings/\(meetingId)/close", body: body, token: token)
    }

    /// S43. Tugagan majlislar tarixi.
    func meetingHistory(token: String) async throws -> [MeetingItem] {
        let data = try await getData("/api/meetings/history", token: token)
        return try decoder.decode(MeetingsPage.self, from: data).meetings
    }

    /// S44. Kechikayotganlarni majlisga chaqirish — qaytaradi nechta odam chaqirilgani.
    @discardableResult
    func nudgeMeeting(token: String, meetingId: Int64) async throws -> Int {
        let json = try await postJSON("/api/meetings/\(meetingId)/nudge", body: [:], token: token)
        return (json["called"] as? NSNumber)?.intValue ?? 0
    }

    /// - Parameter scheduledStart: "yyyy-MM-ddTHH:mm" — MAHALLIY devor-soati,
    ///   mintaqasiz: server rejalashtirilgan vaqtni veb-shakl bilan bir xil saqlaydi.
    func createMeeting(
        token: String,
        title: String,
        inviteeIds: [Int64],
        purpose: String? = nil,
        scheduledStart: String? = nil
    ) async throws -> Int64 {
        var body: [String: Any] = [
            "title": title,
            "invitee_ids": inviteeIds.map { NSNumber(value: $0) }
        ]
        if let p = purpose?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            body["purpose"] = p
        }
        if let s = scheduledStart, !s.isEmpty { body["scheduled_start"] = s }
        let json = try await postJSON("/api/meetings", body: body, token: token)
        guard let n = json["id"] as? NSNumber else { throw ApiError.badResponse }
        return n.int64Value
    }

    func notifications(token: String) async throws -> NotificationsPage {
        let data = try await getData("/api/notifications", token: token)
        return try decoder.decode(NotificationsPage.self, from: data)
    }

    func markRead(token: String, id: Int64) async throws {
        _ = try await postJSON("/api/notifications/\(id)/read", body: [:], token: token)
    }

    func markAllRead(token: String) async throws {
        _ = try await postJSON("/api/notifications/read-all", body: [:], token: token)
    }

    // MARK: Anti-capture (E5)

    /// iOS'da skrinshot/ekran-yozuvni **bloklab bo'lmaydi** — faqat aniqlanadi (ADR D-013).
    /// Aniqlangan hodisa serverga yoziladi (audit + per-meeting siyosat).
    func reportCapture(
        token: String,
        meetingId: Int64?,
        kind: String,
        severity: String = "warning"
    ) async {
        var body: [String: Any] = [
            "kind": kind,
            "platform": "ios",
            "severity": severity
        ]
        if let meetingId { body["meeting_id"] = NSNumber(value: meetingId) }
        // Best-effort: xato bo'lsa ham qo'ng'iroqqa xalaqit bermaydi.
        _ = try? await postJSON("/api/capture-events", body: body, token: token)
    }

    // MARK: Majlisga ulanish

    func join(token: String, meetingId: Int64, geo: GeoPoint?) async throws -> RoomInfo {
        var body: [String: Any] = [:]
        if let g = geo {
            body["lat"] = g.lat
            body["lon"] = g.lon
            if let a = g.accuracy { body["accuracy"] = a }
        }
        let json = try await postJSON("/api/meetings/\(meetingId)/join", body: body, token: token)
        guard let url = json["url"] as? String,
              let tok = json["token"] as? String,
              let room = json["room"] as? String
        else { throw ApiError.badResponse }
        return RoomInfo(url: rewriteHost(url), token: tok, room: room)
    }

    /// Backend loopback (`ws://127.0.0.1:7880`) qaytarishi mumkin — qurilmada bu o'zini
    /// anglatadi, shuning uchun server hostiga almashtiramiz. `ws://` → `wss://`:
    /// iOS App Transport Security shifrlanmagan ulanishni bloklaydi.
    private func rewriteHost(_ wsUrl: String) -> String {
        let host = base.host ?? ""
        var s = wsUrl
            .replacingOccurrences(of: "127.0.0.1", with: host)
            .replacingOccurrences(of: "localhost", with: host)
        if s.hasPrefix("ws://") {
            s = "wss://" + s.dropFirst(5)
        }
        return s
    }

    // MARK: Yordamchi (S39)

    /// Qurilma tili (uz/ru/en); qo'llab-quvvatlanmasa serverning standarti (ru).
    static var deviceLocale: String {
        let code = (Locale.preferredLanguages.first ?? "ru").prefix(2).lowercased()
        return ["uz", "ru", "en"].contains(code) ? code : "ru"
    }

    /// Boshlang'ich takliflar (birinchi savoldan oldin ko'rsatiladi).
    func assistantSuggestions(token: String) async throws -> [AssistantEntry] {
        struct Wrap: Decodable { let suggestions: [AssistantEntry] }
        let data = try await getData("/api/assistant/suggestions?locale=\(SvcApi.deviceLocale)", token: token)
        return try decoder.decode(Wrap.self, from: data).suggestions
    }

    /// Bitta yozuv id bo'yicha ("o'xshash savollar" bosilganda).
    func assistantEntry(token: String, id: String) async throws -> AssistantEntry {
        struct Wrap: Decodable { let answer: AssistantEntry }
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let data = try await getData("/api/assistant/\(enc)?locale=\(SvcApi.deviceLocale)", token: token)
        return try decoder.decode(Wrap.self, from: data).answer
    }

    /// Foydalanuvchi savoli. Server matchingi rol bilan hisoblab, to'rt holatdan birini qaytaradi.
    func assistantAsk(token: String, question: String) async throws -> AssistResult {
        let json = try await postJSON(
            "/api/assistant/ask",
            body: ["question": question, "locale": SvcApi.deviceLocale],
            token: token
        )
        switch json["status"] as? String {
        case "ok":
            return .ok(Self.entry(json["answer"]) ?? .empty, related: Self.entries(json["related"]))
        case "unsure":
            return .unsure(Self.entries(json["candidates"]))
        case "restricted":
            let q = json["question"] as? String ?? question
            let labels = (json["allowed_role_labels"] as? [Any])?.compactMap { $0 as? String } ?? []
            return .restricted(question: q, roleLabels: labels)
        default:  // "no_match"
            return .noMatch(Self.entries(json["suggestions"]))
        }
    }

    // `ask` javobi JSONSerialization bilan o'qiladi (snake_case saqlanadi) — qo'lda yig'amiz.
    private static func entry(_ any: Any?) -> AssistantEntry? {
        guard let d = any as? [String: Any],
              let id = d["id"] as? String, let topic = d["topic"] as? String,
              let question = d["question"] as? String, let answer = d["answer"] as? String
        else { return nil }
        return AssistantEntry(id: id, topic: topic, question: question, answer: answer)
    }

    private static func entries(_ any: Any?) -> [AssistantEntry] {
        (any as? [Any])?.compactMap { entry($0) } ?? []
    }

    // MARK: Hujjatlar (S41)

    func documents(token: String) async throws -> [DocumentItem] {
        let data = try await getData("/api/documents", token: token)
        return try decoder.decode(DocumentsPage.self, from: data).documents
    }

    /// Faylni yuklab oladi. Mazmun xotirada — hujjat limiti 25 MB.
    func downloadDocument(token: String, id: Int64) async throws -> Data {
        try await getData("/api/documents/\(id)/download", token: token)
    }

    /// "Tanishdim / ijro etdim" — yuboruvchi buni ko'radi ("yuklab oldi"dan farqli).
    func acknowledgeDocument(token: String, id: Int64) async throws {
        _ = try await postJSON("/api/documents/\(id)/ack", body: [:], token: token)
    }

    // MARK: HTTP

    private func url(_ path: String) -> URL {
        URL(string: base.absoluteString + path) ?? base
    }

    private func getData(_ path: String, token: String) async throws -> Data {
        var req = URLRequest(url: url(path))
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    @discardableResult
    private func postJSON(_ path: String, body: [String: Any], token: String? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(req)
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any]
        else { return [:] }
        return dict
    }

    private func send(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ApiError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 403 { throw ApiError.forbidden }
            let obj = try? JSONSerialization.jsonObject(with: data)
            let msg = (obj as? [String: Any])?["error"] as? String
            throw ApiError.http(http.statusCode, msg)
        }
        return data
    }
}

// MARK: - Ko'rsatish uchun matnlar

enum Labels {
    static func role(_ r: String) -> String {
        switch r {
        case "super_admin": return "Super administrator"
        case "admin_hr": return "HR administrator"
        case "manager": return "Rahbar"
        case "employee": return "Xodim"
        case "security_officer": return "Xavfsizlik ofitseri"
        default: return r
        }
    }

    /// Rezolyutsiya nomi o'zbekchada: server hujjat aylanishi atamalarini rus
    /// tilida qaytaradi, ilova esa o'zbek tilida.
    static func documentAction(_ action: String, fallback: String?) -> String {
        switch action {
        case "information": return "Tanishish uchun"
        case "review": return "Ko'rib chiqish uchun"
        case "signature": return "Imzolash uchun"
        case "execution": return "Ijro uchun"
        default:
            let f = fallback ?? ""
            return f.isEmpty ? "Hujjat" : f
        }
    }

    static func meetingStatus(_ s: String) -> String {
        switch s {
        case "planned": return "Rejalashtirilgan"
        case "active", "started", "in_progress": return "Davom etmoqda"
        case "finished", "ended", "completed": return "Yakunlangan"
        case "canceled", "cancelled": return "Bekor qilingan"
        default: return s
        }
    }

    /// "2026-09-07T14:30:00.000000Z" → "2026-09-07 14:30"
    static func date(_ iso: String?) -> String? {
        guard let iso, iso.count >= 16 else { return nil }
        return String(iso.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }

    /// UTC ISO → qurilma mintaqasi bo'yicha "21.09 15:40".
    /// `date(_:)` dan farqi: u rejalashtirilgan (naiv) vaqt uchun, bu esa
    /// haqiqiy UTC belgisi uchun — aks holda soat 5 soatga surilib ko'rinadi.
    static func localDateTime(_ iso: String?) -> String? { formatLocal(iso, "dd.MM HH:mm") }

    static func localTime(_ iso: String?) -> String? { formatLocal(iso, "HH:mm") }

    private static func formatLocal(_ iso: String?, _ pattern: String) -> String? {
        guard let iso, iso.count >= 19 else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let date = parser.date(from: String(iso.prefix(19))) else { return nil }

        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = pattern
        return out.string(from: date)
    }

    /// Sana → "yyyy-MM-ddTHH:mm" (mintaqasiz, mahalliy devor-soati).
    static func isoLocal(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.string(from: date)
    }

    /// "45 daqiqa" / "1 soat 20 daqiqa".
    static func duration(_ seconds: Int?) -> String? {
        guard let s = seconds, s > 0 else { return nil }
        if s < 60 { return "\(s) soniya" }
        if s < 3600 { return "\(s / 60) daqiqa" }
        return "\(s / 3600) soat \((s % 3600) / 60) daqiqa"
    }

    /// Bildirishnoma turiga mos SF Symbol nomi.
    static func kindIcon(_ kind: String) -> String {
        switch kind {
        case "invite": return "video.fill"
        case "task": return "doc.text.fill"
        case "reminder": return "alarm.fill"
        case "cancel": return "xmark.circle.fill"
        default: return "info.circle.fill"
        }
    }
}
