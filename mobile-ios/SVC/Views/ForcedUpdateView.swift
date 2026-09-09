import SwiftUI

/// Majburiy yangilanish ekrani — eski build'da ilovaning yagona ko'rinadigan ekrani.
/// Orqaga qaytish yo'q: `RootView` boshqa hech narsani ko'rsatmaydi.
struct ForcedUpdateView: View {
    let info: UpdateChecker.Info

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 64))
                .foregroundColor(Theme.accent)

            Text("Yangilanish talab qilinadi")
                .font(.title2.bold())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            Text("Ilovaning bu versiyasi eskirgan va xavfsizlik siyosati bo'yicha bloklandi. Davom etish uchun yangilang.")
                .font(.body)
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 6) {
                Text("Sizda: v\(UpdateChecker.installedVersionName)")
                Text("Yangi: v\(info.versionName)")
                    .foregroundColor(Theme.accent)
                if let notes = info.notes {
                    Text(notes)
                        .foregroundColor(Theme.muted)
                        .padding(.top, 4)
                }
            }
            .font(.subheadline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.panel)
            .cornerRadius(12)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            if let url = info.url {
                Link(destination: url) {
                    Label("Yangilash", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            } else {
                // Havola yo'q — hech bo'lmaganda nima qilish kerakligini aytamiz.
                Text("Yangi versiyani administratordan so'rang.")
                    .font(.subheadline)
                    .foregroundColor(Theme.muted)
                    .padding(.top, 24)
            }

            Spacer()

            Text("QuantixCore Technologies")
                .font(.caption)
                .foregroundColor(Theme.muted)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .svcBackground()
    }
}

/// Ixtiyoriy yangilanish — ishlashga xalaqit bermaydi, "Keyinroq" bilan yopiladi.
/// Majburiy yangilanishda ko'rinmaydi: u yerda `ForcedUpdateView` butun ekranni egallaydi.
struct OptionalUpdateWrapper: ViewModifier {
    @EnvironmentObject private var state: AppState

    func body(content: Content) -> some View {
        content.alert("Yangi versiya mavjud", isPresented: $state.showOptionalUpdate) {
            if let url = state.update?.url {
                Link("Yangilash", destination: url)
            }
            Button("Keyinroq", role: .cancel) { state.showOptionalUpdate = false }
        } message: {
            if let info = state.update {
                Text("v\(info.versionName)" + (info.notes.map { "\n\($0)" } ?? ""))
            }
        }
    }
}
