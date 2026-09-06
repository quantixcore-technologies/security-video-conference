import SwiftUI
import UIKit
import AVFoundation
import LiveKit

/// Qo'ng'iroq ekrani — nativ LiveKit (WebRTC), webview emas (ADR D-001).
///
/// **Anti-capture (ADR D-013):** iOS'da Android'dagi `FLAG_SECURE` ekvivalenti YO'Q —
/// skrinshot/ekran-yozuvni bloklab bo'lmaydi, faqat **aniqlash** mumkin:
///   • `UIScreen.isCaptured` → video yashiriladi va hodisa serverga yoziladi;
///   • skrinshot → `/api/capture-events` ga qayd (audit + forensika).
struct CallView: View {
    let room: RoomInfo
    var meetingId: Int64? = nil

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var call = CallModel()
    @StateObject private var capture = CaptureMonitor()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.panel)

            ZStack {
                if capture.isBeingCaptured {
                    blockedContent      // ekran yozilmoqda — kontentni ko'rsatmaymiz
                } else {
                    videoArea
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            controls
        }
        .svcBackground()
        .task {
            startCaptureMonitor()
            await call.connect(url: room.url, token: room.token)
        }
        .onDisappear {
            capture.stop()
            Task { await call.disconnect() }
        }
    }

    // MARK: Bo'limlar

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.fill").foregroundColor(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(room.room)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(capture.isBeingCaptured ? "Ekran yozilmoqda — himoya faol" : call.status)
                    .font(.caption)
                    .foregroundColor(capture.isBeingCaptured ? Theme.danger : Theme.muted)
            }
            Spacer()
            if capture.screenshotCount > 0 {
                Label("\(capture.screenshotCount)", systemImage: "camera.viewfinder")
                    .font(.caption)
                    .foregroundColor(Theme.danger)
            }
        }
        .padding(16)
        .background(Theme.panel)
    }

    @ViewBuilder
    private var videoArea: some View {
        if call.tiles.isEmpty {
            VStack(spacing: 10) {
                ProgressView().tint(Theme.accent)
                Text("Video kutilmoqda…")
                    .font(.subheadline)
                    .foregroundColor(Theme.muted)
            }
        } else {
            ScrollView {
                LazyVGrid(
                    columns: call.tiles.count == 1
                        ? [GridItem(.flexible())]
                        : [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 8
                ) {
                    ForEach(call.tiles) { tile in
                        ZStack(alignment: .bottomLeading) {
                            LKVideoView(track: tile.track)
                                .frame(height: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            Text(tile.label)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .padding(6)
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private var blockedContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.danger)
            Text("Kontent yashirildi")
                .font(.headline)
                .foregroundColor(.white)
            Text("Ekran yozuvi yoki translyatsiya aniqlandi.\nHodisa xavfsizlik jurnaliga yozildi.")
                .font(.caption)
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var controls: some View {
        HStack(spacing: 26) {
            CallButton(
                icon: call.micOn ? "mic.fill" : "mic.slash.fill",
                label: "Mikrofon"
            ) {
                Task { await call.toggleMic() }
            }

            CallButton(
                icon: call.camOn ? "video.fill" : "video.slash.fill",
                label: "Kamera"
            ) {
                Task { await call.toggleCam() }
            }

            CallButton(icon: "phone.down.fill", label: "Tugatish", tint: Theme.danger) {
                dismiss()
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Theme.panel)
    }

    // MARK: Anti-capture

    private func startCaptureMonitor() {
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
}

struct CallButton: View {
    let icon: String
    let label: String
    var tint: Color = Theme.panelHi
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(tint)
                .clipShape(Circle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - LiveKit

struct TrackTile: Identifiable {
    let id: String
    let label: String
    let track: VideoTrack
}

/// UIKit `VideoView` ni SwiftUI'ga o'rash (LiveKit SwiftUI komponentlari alohida
/// paketda — qo'shimcha bog'liqlikni oldini olamiz).
struct LKVideoView: UIViewRepresentable {
    let track: VideoTrack

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.layoutMode = .fill
        view.track = track
        return view
    }

    func updateUIView(_ uiView: VideoView, context: Context) {
        if uiView.track !== track {
            uiView.track = track
        }
    }

    static func dismantleUIView(_ uiView: VideoView, coordinator: ()) {
        uiView.track = nil
    }
}

/// Qo'ng'iroq holati: ulanish, mikrofon/kamera, video treklar.
/// Delegat chaqiruvlari fon oqimidan kelishi mumkin → `nonisolated` + MainActor'ga o'tish.
@MainActor
final class CallModel: ObservableObject {
    @Published private(set) var tiles: [TrackTile] = []
    @Published private(set) var status = "Ulanmoqda…"
    @Published private(set) var micOn = true
    @Published private(set) var camOn = true

    private let room = Room()
    private lazy var proxy = RoomDelegateProxy(model: self)

    func connect(url: String, token: String) async {
        room.add(delegate: proxy)

        // Mikrofon/kamera ruxsati — LiveKit trek yaratishdan oldin so'raladi.
        await AVCaptureDevice.requestAccess(for: .video)
        await AVCaptureDevice.requestAccess(for: .audio)

        do {
            try await room.connect(url: url, token: token)
            status = "Efirda"
            try await room.localParticipant.setMicrophone(enabled: true)
            try await room.localParticipant.setCamera(enabled: true)
        } catch {
            status = "Xatolik: \(error.localizedDescription)"
        }
    }

    func disconnect() async {
        await room.disconnect()
    }

    func toggleMic() async {
        micOn.toggle()
        try? await room.localParticipant.setMicrophone(enabled: micOn)
    }

    func toggleCam() async {
        camOn.toggle()
        try? await room.localParticipant.setCamera(enabled: camOn)
    }

    // Delegatdan chaqiriladi (MainActor'da).

    func addTile(label: String, track: VideoTrack) {
        let id = String(UInt(bitPattern: ObjectIdentifier(track).hashValue))
        guard !tiles.contains(where: { $0.id == id }) else { return }
        tiles.append(TrackTile(id: id, label: label, track: track))
    }

    func removeTile(track: VideoTrack) {
        let id = String(UInt(bitPattern: ObjectIdentifier(track).hashValue))
        tiles.removeAll { $0.id == id }
    }
}

/// `RoomDelegate` — alohida sinf: `CallModel` MainActor'da, delegat esa emas.
final class RoomDelegateProxy: RoomDelegate {
    private weak var model: CallModel?

    init(model: CallModel) {
        self.model = model
    }

    func room(_ room: Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) {
        guard let track = publication.track as? VideoTrack else { return }
        Task { @MainActor [weak model] in
            model?.addTile(label: "Siz", track: track)
        }
    }

    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        guard let track = publication.track as? VideoTrack else { return }
        let label = participant.identity.map { "\($0)" } ?? "ishtirokchi"
        Task { @MainActor [weak model] in
            model?.addTile(label: label, track: track)
        }
    }

    func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        guard let track = publication.track as? VideoTrack else { return }
        Task { @MainActor [weak model] in
            model?.removeTile(track: track)
        }
    }
}

// MARK: - Ekran yozuvi / skrinshot aniqlash

/// iOS faqat **aniqlay** oladi, blokla olmaydi (ADR D-013).
@MainActor
final class CaptureMonitor: ObservableObject {
    @Published private(set) var isBeingCaptured = false
    @Published private(set) var screenshotCount = 0

    private var observers: [NSObjectProtocol] = []
    private var onEvent: ((String) -> Void)?

    func start(onEvent: @escaping (String) -> Void) {
        guard observers.isEmpty else { return }
        self.onEvent = onEvent

        // Qo'ng'iroq ochilganda allaqachon yozilayotgan bo'lishi mumkin.
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
                guard captured != self.isBeingCaptured else { return }
                self.isBeingCaptured = captured
                if captured { self.onEvent?("screen_record_detected") }
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
