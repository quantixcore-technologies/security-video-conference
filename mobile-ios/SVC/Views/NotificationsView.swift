import SwiftUI

/// Xabarlar: majlis taklifi, topshiriq/buyruq, eslatma (backend `Svc.Notifications`).
struct NotificationsView: View {
    let session: Session
    @Binding var unread: Int

    @EnvironmentObject private var state: AppState
    @State private var page: NotificationsPage?
    @State private var loadError: String?

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
    }

    @ViewBuilder
    private var content: some View {
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
                            NotificationRow(item: n) {
                                Task { await markOne(n) }
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

    @MainActor
    private func markOne(_ n: NotificationItem) async {
        guard n.isUnread else { return }
        try? await state.api.markRead(token: session.token, id: n.id)
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
