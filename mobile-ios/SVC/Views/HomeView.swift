import SwiftUI
import UIKit   // UITabBarAppearance / UINavigationBarAppearance

/// Login'dan keyingi asosiy ekran: 4 bo'lim (Android'dagi pastki navigatsiya bilan bir xil).
struct HomeView: View {
    let session: Session
    @EnvironmentObject private var state: AppState
    @State private var unread = 0

    init(session: Session) {
        self.session = session

        // Pastki panel — qorong'i tema (SwiftUI TabView UIKit appearance'dan oladi).
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.panel)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.bg)
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }

    var body: some View {
        TabView {
            MeetingsView(session: session)
                .tabItem { Label("Uchrashuvlar", systemImage: "video.fill") }

            NotificationsView(session: session, unread: $unread)
                .tabItem { Label("Xabarlar", systemImage: "bell.fill") }
                .badge(unread)

            DepartmentView(session: session)
                .tabItem { Label("Bo'lim", systemImage: "person.3.fill") }

            ProfileView(session: session)
                .tabItem { Label("Profil", systemImage: "person.fill") }
        }
        .tint(Theme.accent)
        .task { await refreshUnread() }
    }

    @MainActor
    private func refreshUnread() async {
        if let page = try? await state.api.notifications(token: session.token) {
            unread = page.unread ?? 0
        }
    }
}

// MARK: - Umumiy yordamchi ko'rinishlar

/// Yuklanmoqda / xato / bo'sh holatlar uchun bir xil ko'rinish.
struct StateMessage: View {
    let text: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Text(text)
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Qayta urinish", action: retry)
                    .foregroundColor(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct LoadingView: View {
    var body: some View {
        ProgressView()
            .tint(Theme.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Ism bosh harfi bilan avatar.
struct InitialAvatar: View {
    let text: String
    var size: CGFloat = 42
    var background: Color = Theme.bg

    var body: some View {
        ZStack {
            Circle().fill(background)
            Text(text.isEmpty ? "•" : text)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(Theme.accent)
        }
        .frame(width: size, height: size)
    }
}
