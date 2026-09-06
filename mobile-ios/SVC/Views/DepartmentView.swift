import SwiftUI

/// Bo'lim xodimlari (`/api/users` — o'z bo'limi bilan cheklangan).
struct DepartmentView: View {
    let session: Session
    @EnvironmentObject private var state: AppState

    @State private var users: [Colleague]?
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            content
                .svcBackground()
                .navigationTitle("Bo'lim")
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
        } else if let users {
            if users.isEmpty {
                StateMessage(text: "Bo'limda boshqa xodim yo'q")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(users) { u in
                            HStack(spacing: 12) {
                                InitialAvatar(text: u.initial)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(u.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.white)
                                    Text([Labels.role(u.roleValue), u.phone]
                                            .compactMap { $0 }
                                            .filter { !$0.isEmpty }
                                            .joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundColor(Theme.muted)
                                }

                                Spacer(minLength: 0)

                                if !u.isActive {
                                    Text("nofaol")
                                        .font(.caption2)
                                        .foregroundColor(Theme.danger)
                                }
                            }
                            .padding(14)
                            .background(Theme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
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
        users = nil
        do {
            users = try await state.api.colleagues(token: session.token)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
