import SwiftUI

/// Xabarlar: majlis taklifi, topshiriq/buyruq, eslatma (backend `Svc.Notifications`).
struct NotificationsView: View {
    let session: Session
    @Binding var unread: Int

    @EnvironmentObject private var state: AppState
    @State private var page: NotificationsPage?
    @State private var loadError: String?
    // S45: xabar ustiga bosilganda majlisga o'tkazamiz.
    @State private var joinError: String?
    @State private var joinWarning: String?
    @State private var joiningId: Int64?
    @State private var joinedMeetingId: Int64?
    @State private var room: RoomInfo?

    var body: some View {
        NavigationStack {
            content
                .svcBackground()
                .navigationTitle("Xabarlar")
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
        .fullScreenCover(item: $room) { info in
            CallView(room: info, meetingId: joinedMeetingId)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if let joinError {
                Text(joinError)
                    .font(.footnote)
                    .foregroundColor(Theme.danger)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            if let joinWarning {
                Text(joinWarning)
                    .font(.footnote)
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            list
        }
    }

    @ViewBuilder
    private var list: some View {
        if let loadError {
            StateMessage(text: loadError) { Task { await load() } }
        } else if let page {
            if page.notifications.isEmpty {
                StateMessage(text: "Hozircha xabarlar yo'q")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if (page.unread ?? 0) > 0 {
                            Button("Hammasini o'qilgan deb belgilash") {
                                Task { await markAll() }
                            }
                            .font(.footnote)
                            .foregroundColor(Theme.accent)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.bottom, 4)
                        }

                        ForEach(page.notifications) { n in
                            NotificationRow(item: n, busy: joiningId == n.id) {
                                Task { await open(n) }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        } else {
            LoadingView()
        }
    }

    @MainActor
    private func load() async {
        loadError = nil
        page = nil
        do {
            let p = try await state.api.notifications(token: session.token)
            page = p
            unread = p.unread ?? 0
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Xabarni o'qilgan deb belgilaydi va majlisga tegishli bo'lsa — o'sha majlisga kiradi.
    @MainActor
    private func open(_ n: NotificationItem) async {
        joinError = nil
        joinWarning = nil

        if n.isUnread {
            try? await state.api.markRead(token: session.token, id: n.id)
        }

        guard let mid = n.meetingId else {
            await load()
            return
        }

        joiningId = n.id
        defer { joiningId = nil }

        GeoProvider.shared.request()
        do {
            let info = try await state.api.join(
                token: session.token,
                meetingId: mid,
                geo: GeoProvider.shared.current()
            )
            joinWarning = info.warning
            joinedMeetingId = mid
            room = info
        } catch {
            joinError = error.localizedDescription
        }
        await load()
    }

    @MainActor
    private func markAll() async {
        try? await state.api.markAllRead(token: session.token)
        await load()
    }
}

struct NotificationRow: View {
    let item: NotificationItem
    var busy: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: Labels.kindIcon(item.kindValue))
                    .font(.title3)
                    .foregroundColor(item.isUnread ? Theme.accent : Theme.muted)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? "")
                        .font(.subheadline.weight(item.isUnread ? .bold : .regular))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)

                    if let body = item.body, !body.isEmpty {
                        Text(body)
                            .font(.caption)
                            .foregroundColor(Theme.muted)
                            .multilineTextAlignment(.leading)
                    }
                    if let d = Labels.date(item.insertedAt) {
                        Text(d)
                            .font(.caption2)
                            .foregroundColor(Theme.muted)
                    }
                }

                Spacer(minLength: 0)

                if busy {
                    ProgressView().tint(Theme.accent).padding(.top, 2)
                } else if item.meetingId != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(item.isUnread ? Theme.accent : Theme.muted)
                        .padding(.top, 4)
                }

                if item.isUnread {
                    Circle().fill(Theme.accent).frame(width: 9, height: 9).padding(.top, 6)
                }
            }
            .padding(14)
            .background(item.isUnread ? Theme.panelHi : Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
