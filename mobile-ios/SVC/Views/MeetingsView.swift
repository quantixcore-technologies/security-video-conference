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
    // S43: "Joriy" / "Tarix" — o'tgan majlislar qachon bo'lgani ko'rinadi.
    @State private var showHistory = false
    @State private var history: [MeetingItem]?
    @State private var closingMeeting: MeetingItem?
    @State private var closeSummary = ""
    @State private var controlBusyId: Int64?
    // S44: "chaqiruv yuborildi" xabari
    @State private var calledNote: String?

    var body: some View {
        NavigationStack {
            content
                .svcBackground()
                .navigationTitle(showHistory ? "Majlislar tarixi" : "Uchrashuvlar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Text(session.fullName)
                            .font(.caption)
                            .foregroundColor(Theme.muted)
                            .lineLimit(1)
                    }
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        if canOrganize && !showHistory {
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
        .sheet(item: $closingMeeting) { meeting in
            CloseMeetingSheet(
                meeting: meeting,
                summary: $closeSummary,
                onCancel: { closingMeeting = nil },
                onConfirm: {
                    let text = closeSummary
                    closingMeeting = nil
                    closeSummary = ""
                    Task { await close(meeting, summary: text) }
                }
            )
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

            if let calledNote {
                Text(calledNote)
                    .font(.footnote)
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }

            Picker("", selection: $showHistory) {
                Text("Joriy").tag(false)
                Text("Tarix").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .onChange(of: showHistory) { _ in Task { await load() } }

            if let loadError {
                StateMessage(text: loadError) { Task { await load() } }
            } else if showHistory {
                if let history {
                    if history.isEmpty {
                        StateMessage(text: "Tarix hali bo'sh")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(history) { MeetingHistoryRow(meeting: $0) }
                            }
                            .padding(16)
                        }
                    }
                } else {
                    LoadingView()
                }
            } else if let meetings {
                if meetings.isEmpty {
                    StateMessage(text: "Hozircha uchrashuvlar yo'q")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(meetings) { m in
                                MeetingRow(
                                    meeting: m,
                                    busy: joiningId == m.id || controlBusyId == m.id,
                                    enabled: joiningId == nil && controlBusyId == nil,
                                    onJoin: { Task { await join(m) } },
                                    onOpen: { Task { await open(m) } },
                                    onClose: {
                                        closeSummary = ""
                                        closingMeeting = m
                                    },
                                    onCall: { Task { await call(m) } }
                                )
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
        do {
            if showHistory {
                history = nil
                history = try await state.api.meetingHistory(token: session.token)
            } else {
                meetings = nil
                let page = try await state.api.meetings(token: session.token)
                meetings = page.meetings
                canOrganize = page.canOrganize ?? session.canOrganize
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// S43. Majlisni ochish — shundan keyin uni ochgan xodim yakunlaydi.
    @MainActor
    private func open(_ m: MeetingItem) async {
        joinError = nil
        controlBusyId = m.id
        defer { controlBusyId = nil }
        do {
            try await state.api.openMeeting(token: session.token, meetingId: m.id)
            await load()
        } catch {
            joinError = error.localizedDescription
        }
    }

    /// S44. Hali kirmaganlarni majlisga chaqirish.
    @MainActor
    private func call(_ m: MeetingItem) async {
        joinError = nil
        calledNote = nil
        controlBusyId = m.id
        defer { controlBusyId = nil }
        do {
            let n = try await state.api.nudgeMeeting(token: session.token, meetingId: m.id)
            calledNote = "Chaqiruv yuborildi: \(n) ta xodim"
            await load()
        } catch {
            joinError = error.localizedDescription
        }
    }

    @MainActor
    private func close(_ m: MeetingItem, summary: String) async {
        joinError = nil
        controlBusyId = m.id
        defer { controlBusyId = nil }
        do {
            try await state.api.closeMeeting(
                token: session.token,
                meetingId: m.id,
                summary: summary
            )
            await load()
        } catch {
            joinError = error.localizedDescription
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
    let onOpen: () -> Void
    let onClose: () -> Void
    let onCall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

            if let purpose = meeting.purpose, !purpose.isEmpty {
                Text("Sabab: \(purpose)")
                    .font(.caption)
                    .foregroundColor(Theme.muted)
                    .padding(.top, 8)
            }

            // S43: majlisni ochgan xodim uni yakunlaydi — tugma faqat unga.
            if meeting.mayOpen {
                Button(action: onOpen) {
                    Text("Majlisni boshlash")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(.white)
                        .background(Theme.success)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!enabled)
                .padding(.top, 12)
            } else if meeting.mayClose {
                Button(action: onClose) {
                    Text("Majlisni yakunlash")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(Theme.danger)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.danger.opacity(0.6), lineWidth: 1)
                        )
                }
                .disabled(!enabled)
                .padding(.top, 12)
            }

            // S44: kechikayotganlarni chaqirish — hali kirmaganlar bo'lsa.
            if meeting.mayClose && meeting.pending > 0 {
                Button(action: onCall) {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge.fill")
                        Text("Majlisga chaqirish (\(meeting.pending))")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(Theme.accent)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.accent.opacity(0.55), lineWidth: 1)
                    )
                }
                .disabled(!enabled)
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Tugagan majlis: qachondan qachongacha, nima uchun, kim ochib kim yopgan.
struct MeetingHistoryRow: View {
    let meeting: MeetingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)

            Text(
                [meeting.sessionRange, Labels.duration(meeting.durationSeconds)]
                    .compactMap { $0 }
                    .joined(separator: " · ")
            )
            .font(.caption)
            .foregroundColor(Theme.accent)

            if let purpose = meeting.purpose, !purpose.isEmpty {
                Text("Sabab: \(purpose)").font(.caption).foregroundColor(.white)
            }
            if let summary = meeting.summary, !summary.isEmpty {
                Text("Natija: \(summary)").font(.caption).foregroundColor(.white)
            }

            let people = [
                meeting.startedByName.map { "Ochdi: \($0)" },
                meeting.endedByName.map { "Yakunladi: \($0)" }
            ].compactMap { $0 }

            if !people.isEmpty {
                Text(people.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundColor(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Yakunlash oynasi: natija majlis tarixida saqlanadi.
struct CloseMeetingSheet: View {
    let meeting: MeetingItem
    @Binding var summary: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(meeting.displayTitle)
                    .font(.headline)
                    .foregroundColor(.white)

                Text("Natija (ixtiyoriy) — majlis tarixida saqlanadi.")
                    .font(.caption)
                    .foregroundColor(Theme.muted)

                TextEditor(text: $summary)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Theme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .svcBackground()
            .navigationTitle("Majlisni yakunlash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Bekor qilish", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Yakunlash", action: onConfirm)
                }
            }
        }
        .tint(Theme.accent)
    }
}

/// `sheet(item:)` uchun.
extension MeetingItem: Equatable {
    static func == (a: MeetingItem, b: MeetingItem) -> Bool { a.id == b.id }
}

/// `fullScreenCover(item:)` uchun kerak.
extension RoomInfo: Identifiable {
    var id: String { room }
}
