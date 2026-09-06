import SwiftUI

/// Ilova ochilganda ko'rinadigan bosh sahifa — kirish o'ng yuqorida (profil ikonkasi).
/// Android'dagi `LandingScreen` bilan bir xil tuzilish.
struct LandingView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Yuqori panel: brend + kirish ikonkasi
            HStack {
                Image(systemName: "shield.fill")
                    .foregroundColor(Theme.accent)
                    .font(.title3)
                Text("SVC")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                Spacer()
                Button {
                    state.showLogin = true
                } label: {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(Theme.accent)
                }
                .accessibilityLabel("Kirish")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().overlay(Theme.panel)

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 28)

                    Image(systemName: "shield.fill")
                        .font(.system(size: 64))
                        .foregroundColor(Theme.accent)

                    Text("Security Video Conference")
                        .font(.title.bold())
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)

                    Text("Davlat va korporativ tuzilmalar uchun xavfsiz video-aloqa platformasi")
                        .font(.body)
                        .foregroundColor(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)

                    VStack(spacing: 12) {
                        FeatureCard(icon: "lock.fill",
                                    title: "Himoyalangan aloqa",
                                    text: "Media oqimlari zamonaviy shifrlash (DTLS-SRTP) bilan uzatiladi")
                        FeatureCard(icon: "key.fill",
                                    title: "Ikki bosqichli kirish",
                                    text: "Parol va bir martalik kod (2FA) orqali autentifikatsiya")
                        FeatureCard(icon: "video.fill",
                                    title: "Video va ekran namoyishi",
                                    text: "Yuqori sifatli video, guruh chati va ekranni ulashish")
                        FeatureCard(icon: "eye.slash.fill",
                                    title: "Yozib olishni aniqlash",
                                    text: "Ekran yozuvi va skrinshot aniqlanadi hamda qayd etiladi")
                    }
                    .padding(.top, 32)

                    Button {
                        state.showLogin = true
                    } label: {
                        Text("Tizimga kirish")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.top, 32)

                    Text("QuantixCore Technologies · O'zbekiston")
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                        .padding(.vertical, 24)
                }
                .padding(.horizontal, 24)
            }
        }
        .svcBackground()
    }
}

struct FeatureCard: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(Theme.accent)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text(text)
                    .font(.caption)
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
