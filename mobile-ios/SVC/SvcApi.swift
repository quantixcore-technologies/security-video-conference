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

    func createMeeting(token: String, title: String, inviteeIds: [Int64]) async throws -> Int64 {
        let json = try await postJSON(
            "/api/meetings",
            body: ["title": title, "invitee_ids": inviteeIds.map { NSNumber(value: $0) }],
            token: token
        )
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
