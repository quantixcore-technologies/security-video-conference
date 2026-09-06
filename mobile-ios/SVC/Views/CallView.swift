import SwiftUI
import UIKit

/// Qo'ng'iroq ekrani.
///
/// **Anti-capture (ADR D-013):** iOS'da Android'dagi `FLAG_SECURE` ekvivalenti YO'Q —
/// skrinshot/ekran-yozuvni bloklab bo'lmaydi, faqat **aniqlash** mumkin. Shuning uchun:
///   • ekran yozuvi/translyatsiya aniqlansa — kontent yashiriladi va serverga qayd ketadi;
///   • skrinshot olinsa — hodisa serverga yoziladi (audit + forensika).
///
/// **Video (LiveKit):** 2-bosqichda ulanadi — hozir server tomonda LiveKit media
/// oqimi qurilmalararo o'tmaydi (NAT/tunnel). Cloud yoki statik IP ulangach qo'shiladi.
struct CallView: View {
    let room: RoomInfo
    var meetingId: Int64? = nil

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var capture = CaptureMonitor()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().overlay(Theme.panel)

            if capture.isBeingCaptured {
                // Ekran yozilmoqda — maxfiy kontentni ko'rsatmaymiz.
                blockedContent
            } else {
                content
            }

            controls
        }
        .svcBackground()
        .onAppear {
            capture.start { kind in
                Task {
                    guard let token = state.session?.token else { return }
                    await state.api.reportCapture(
                        token: token,
                        meetingId: meetingId,
                        kind: kind,
                        severity: kind == "screen_record_detected" ? "critical" : "warning"
                    )
                }
            }
        }
        .onDisappear { capture.stop() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.fill").foregroundColor(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(room.room)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(capture.isBeingCaptured ? "Ekran yozilmoqda — himoya faol" : "Ulandi")
                    .font(.caption)
                    .foregroundColor(capture.isBeingCaptured ? Theme.danger : Theme.muted)
            }
            Spacer()
        }
        .padding(16)
        .background(Theme.panel)
    }

    private var content: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "video.badge.waveform")
                .font(.system(size: 48))
                .foregroundColor(Theme.muted)

            Text("Video kutilmoqda…")
                .font(.headline)
                .foregroundColor(.white)

            Text("Qurilmalararo video oqimi LiveKit ulangach faollashadi.\nMajlisga ulanish qayd etildi.")
                .font(.caption)
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if capture.screenshotCount > 0 {
                Label("\(capture.screenshotCount) ta skrinshot aniqlandi va qayd etildi",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(Theme.danger)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var blockedContent: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.danger)
            Text("Kontent yashirildi")
                .font(.headline)
                .foregroundColor(.white)
            Text("Ekran yozuvi yoki translyatsiya aniqlandi. Hodisa xavfsizlik jurnaliga yozildi.")
                .font(.caption)
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.danger)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Qo'ng'iroqni tugatish")
            Spacer()
        }
        .padding(.vertical, 18)
        .background(Theme.panel)
    }
}

/// Ekran yozuvi va skrinshotni kuzatuvchi (iOS faqat aniqlay oladi, blokla olmaydi).
@MainActor
final class CaptureMonitor: ObservableObject {
    @Published private(set) var isBeingCaptured = false
    @Published private(set) var screenshotCount = 0

    private var observers: [NSObjectProtocol] = []
    private var onEvent: ((String) -> Void)?

    func start(onEvent: @escaping (String) -> Void) {
        guard observers.isEmpty else { return }
        self.onEvent = onEvent

        // Boshlang'ich holat: qo'ng'iroq ochilganda allaqachon yozilayotgan bo'lishi mumkin.
        isBeingCaptured = UIScreen.main.isCaptured
        if isBeingCaptured { onEvent("screen_record_detected") }

        let nc = NotificationCenter.default

        observers.append(nc.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let captured = UIScreen.main.isCaptured
                if captured != self.isBeingCaptured {
                    self.isBeingCaptured = captured
                    if captured { self.onEvent?("screen_record_detected") }
                }
            }
        })

        observers.append(nc.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.screenshotCount += 1
                self.onEvent?("screenshot_detected")
            }
        })
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        onEvent = nil
    }
}
