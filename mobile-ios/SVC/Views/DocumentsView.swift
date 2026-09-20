import SwiftUI
import QuickLook

/// Hujjatlar (S41) — kelgan hujjatlar ro'yxati.
///
/// Xodimga eng kerakli uchta narsa kartaning tepasida turadi: **kimdan** kelgan,
/// **nima qilish** kerak (rezolyutsiya) va **qachongacha**. Shuning uchun fayl
/// nomi va hajmi pastga tushirilgan — ular ikkinchi darajali.
///
/// Fayl vaqtinchalik papkaga yoziladi va tizim ko'ruvchisida ochiladi: hujjat
/// ilova xotirasida qolmaydi va tashqi papkalarga tushmaydi.
struct DocumentsView: View {
    let session: Session
    @EnvironmentObject private var state: AppState

    @State private var documents: [DocumentItem]?
    @State private var loadError: String?
    @State private var busyId: Int64?
    @State private var notice: String?
    @State private var previewURL: URL?

    var body: some View {
        NavigationStack {
            content
                .svcBackground()
                .navigationTitle("Hujjatlar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task { await load() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Yangilash")
                    }
                }
        }
        .tint(Theme.accent)
        .task { await load() }
        .quickLookPreview($previewURL)
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            StateMessage(text: loadError) { Task { await load() } }
        } else if let documents {
            if documents.isEmpty {
                StateMessage(text: "Hozircha hujjat yo'q")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if let notice {
                            Text(notice)
                                .font(.caption)
                                .foregroundColor(Theme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ForEach(documents) { document in
                            card(document)
                        }
                    }
                    .padding(16)
                }
            }
        } else {
            ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func card(_ document: DocumentItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Labels.documentAction(document.action, fallback: document.actionLabel))
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(actionColor(document.action).opacity(0.18))
                    .foregroundColor(actionColor(document.action))
                    .clipShape(Capsule())

                Spacer(minLength: 0)

                if let due = document.dueAt, !due.isEmpty {
                    Text("muddat: " + shortDate(due))
                        .font(.caption2)
                        .foregroundColor(Theme.danger)
                }
            }

            Text(document.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)

            Text(document.isMine ? "Siz yubordingiz" : "Kimdan: \(document.senderName)")
                .font(.caption)
                .foregroundColor(Theme.muted)

            if let note = document.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundColor(Color(white: 0.8))
            }

            Text("\(document.filename) · \(humanSize(document.byteSize))")
                .font(.caption2)
                .foregroundColor(Theme.muted)

            HStack(spacing: 12) {
                Button {
                    Task { await open(document) }
                } label: {
                    Label(busyId == document.id ? "Kuting…" : "Ochish",
                          systemImage: "arrow.down.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(busyId != nil)

                if !document.isMine {
                    if document.isAcknowledged {
                        Text("✓ tanishdingiz")
                            .font(.caption2)
                            .foregroundColor(Theme.accent)
                    } else {
                        Button("Tanishdim") {
                            Task { await acknowledge(document) }
                        }
                        .font(.caption)
                        .tint(Theme.accent)
                        .disabled(busyId != nil)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Amallar

    private func load() async {
        loadError = nil
        documents = nil
        do {
            documents = try await state.api.documents(token: session.token)
        } catch {
            loadError = friendly(error)
        }
    }

    private func open(_ document: DocumentItem) async {
        busyId = document.id
        defer { busyId = nil }
        do {
            let data = try await state.api.downloadDocument(token: session.token, id: document.id)
            previewURL = try write(data, name: document.filename)
        } catch {
            notice = friendly(error)
        }
    }

    private func acknowledge(_ document: DocumentItem) async {
        busyId = document.id
        defer { busyId = nil }
        do {
            try await state.api.acknowledgeDocument(token: session.token, id: document.id)
            notice = "Belgilandi: tanishdim"
            await load()
        } catch {
            notice = friendly(error)
        }
    }

    /// Vaqtinchalik papkaga yozamiz: tizim uni o'zi tozalaydi va hujjat
    /// foydalanuvchi fayllari orasida qolib ketmaydi.
    private func write(_ data: Data, name: String) throws -> URL {
        let safe = (name as NSString).lastPathComponent
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("documents", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(safe.isEmpty ? "hujjat" : safe)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func friendly(_ error: Error) -> String {
        if let api = error as? ApiError {
            switch api {
            case .forbidden: return "Ruxsat yo'q"
            case .http(404, _): return "Hujjat topilmadi"
            default: return "Xatolik yuz berdi"
            }
        }
        return "Tarmoq xatosi"
    }

    private func actionColor(_ action: String) -> Color {
        switch action {
        case "signature": return Color(red: 0.96, green: 0.62, blue: 0.04)
        case "execution": return Theme.danger
        case "review": return Color(red: 0.22, green: 0.74, blue: 0.97)
        default: return Theme.accent
        }
    }

    private func humanSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }

    /// "2026-09-22T07:05:00Z" → "2026-09-22"
    private func shortDate(_ iso: String) -> String {
        String(iso.prefix(10))
    }
}
