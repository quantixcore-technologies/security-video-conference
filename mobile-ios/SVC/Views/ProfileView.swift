import SwiftUI

/// Foydalanuvchi profili (`/api/me`) + chiqish.
struct ProfileView: View {
    let session: Session
    @EnvironmentObject private var state: AppState

    @State private var profile: Profile?
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            content
                .svcBackground()
                .navigationTitle("Profil")
                .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Theme.accent)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            StateMessage(text: loadError) { Task { await load() } }
        } else if let p = profile {
            ScrollView {
                VStack(spacing: 0) {
                    InitialAvatar(
                        text: String(p.displayName.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased(),
                        size: 88,
                        background: Theme.panel
                    )
                    .padding(.top, 16)

                    Text(p.displayName)
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .padding(.top, 14)

                    Text("@\(p.username ?? "")")
                        .font(.subheadline)
                        .foregroundColor(Theme.muted)

                    VStack(spacing: 8) {
                        ProfileRow(label: "Lavozim", value: Labels.role(p.roleValue))
                        if let d = p.department?.name { ProfileRow(label: "Bo'lim", value: d) }
                        if let o = p.organization?.name { ProfileRow(label: "Tashkilot", value: o) }
                        if let ph = p.phone, !ph.isEmpty { ProfileRow(label: "Telefon", value: ph) }
                    }
                    .padding(.top, 24)

                    Button {
                        state.signOut()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Chiqish").font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.danger)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.top, 32)

                    Text("SVC v0.1.0 · QuantixCore Technologies")
                        .font(.caption2)
                        .foregroundColor(Theme.muted)
                        .padding(.vertical, 16)
                }
                .padding(.horizontal, 24)
            }
        } else {
            LoadingView()
        }
    }

    @MainActor
    private func load() async {
        loadError = nil
        profile = nil
        do {
            profile = try await state.api.me(token: session.token)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct ProfileRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(Theme.muted)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
