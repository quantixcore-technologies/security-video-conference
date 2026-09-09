import SwiftUI

@main
struct SVCApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
        }
    }
}

/// Ilova sessiyasi: token Keychain'da saqlanadi, ochilishda `/api/me` bilan tekshiriladi.
@MainActor
final class AppState: ObservableObject {
    @Published var session: Session?
    @Published var checking = true
    @Published var showLogin = false
    @Published var update: UpdateChecker.Info?
    @Published var showOptionalUpdate = false

    let api = SvcApi()

    /// Auto-login: saqlangan token yaroqli bo'lsa — to'g'ridan-to'g'ri ish ekraniga.
    /// Avval yangilanish tekshiriladi: majburiy bo'lsa ilova umuman ochilmaydi.
    func restore() async {
        defer { checking = false }

        update = await UpdateChecker.check()
        if update?.mandatory == true { return }
        showOptionalUpdate = update != nil

        guard let token = Prefs.token() else { return }
        do {
            let p = try await api.me(token: token)
            session = Session(token: token, fullName: p.displayName, role: p.roleValue)
        } catch {
            Prefs.clear()   // token eskirgan yoki bekor qilingan
        }
    }

    func signIn(_ s: Session) {
        Prefs.saveToken(s.token)
        session = s
        showLogin = false
    }

    func signOut() {
        Prefs.clear()
        session = nil
        showLogin = false
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            if state.checking {
                ProgressView()
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .svcBackground()
            } else if let update = state.update, update.mandatory {
                // Yangilanmaguncha boshqa hech qanday ekran ko'rsatilmaydi.
                ForcedUpdateView(info: update)
            } else if let session = state.session {
                HomeView(session: session)
            } else if state.showLogin {
                LoginView()
            } else {
                LandingView()
            }
        }
        .modifier(OptionalUpdateWrapper())
        .task { await state.restore() }
    }
}
