import SwiftUI

/// Uchrashuvlar ro'yxati — uchrashuv ID so'ralmaydi, foydalanuvchi o'z majlislarini ko'radi.
/// Rahbar/super_admin uchun "+" tugmasi — ilovadan majlis yaratish.
struct MeetingsView: View {
    let session: Session
    @EnvironmentObject private var state: AppState

    @State private var meetings: [MeetingItem]?
    @State private var canOrganize = false
    @State private var loadError: String?
    @State private var joinError: String?
    @State private var joiningId: Int64?
    @State private var joinedMeetingId: Int64?
    @State private var room: RoomInfo?
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            content
                .svcBackground()
                .navigationTitle("Uchrashuvlar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Text(session.fullName)
                            .font(.caption)
                            .foregroundColor(Theme.muted)
                            .lineLimit(1)
                    }
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        if canOrganize {
                            Button {
                                showCreate = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Majlis yaratish")
                        }
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
        .sheet(isPresented: $showCreate) {
            CreateMeetingView(session: session) {
                showCreate = false
                Task { await load() }
            }
        }
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

            if let loadError {
                StateMessage(text: loadError) { Task { await load() } }
            } else if let meetings {
                if meetings.isEmpty {
                    StateMessage(text: "Hozircha uchrashuvlar yo'q")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(meetings) { m in
                                MeetingRow(
                                    meeting: m,
                                    busy: joiningId == m.id,
                                    enabled: joiningId == nil
                                ) {
                                    Task { await join(m) }
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
    }

    @MainActor
    private func load() async {
        loadError = nil
        meetings = nil
        do {
            let page = try await state.api.meetings(token: session.token)
            meetings = page.meetings
            canOrganize = page.canOrganize ?? session.canOrganize
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func join(_ m: MeetingItem) async {
        joinError = nil
        joiningId = m.id
        defer { joiningId = nil }

        GeoProvider.shared.request()
        do {
            let info = try await state.api.join(
                token: session.token,
                meetingId: m.id,
                geo: GeoProvider.shared.current()
            )
            joinedMeetingId = m.id
            room = info
        } catch {
            joinError = error.localizedDescription
        }
    }
}

struct MeetingRow: View {
    let meeting: MeetingItem
    let busy: Bool
    let enabled: Bool
    let onJoin: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text(meeting.subtitle)
                    .font(.caption)
                    .foregroundColor(Theme.muted)
            }
            Spacer(minLength: 8)

            Button(action: onJoin) {
                ZStack {
                    if busy {
                        ProgressView().tint(.white)
                    } else {
                        Text("Kirish").font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Theme.accent)
                .clipShape(Capsule())
            }
            .disabled(!enabled)
        }
        .padding(16)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// `fullScreenCover(item:)` uchun kerak.
extension RoomInfo: Identifiable {
    var id: String { room }
}
