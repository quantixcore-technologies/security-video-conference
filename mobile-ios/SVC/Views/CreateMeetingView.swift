import SwiftUI

/// Majlis yaratish (super_admin / manager). Biriktiriladiganlar ro'yxati serverdan
/// `/api/assignable` orqali keladi — rahbar faqat teng/past unvonni ko'radi (D-016).
struct CreateMeetingView: View {
    let session: Session
    let onCreated: () -> Void

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var people: [Colleague]?
    @State private var selected: Set<Int64> = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TextField("", text: $title,
                              prompt: Text("Majlis nomi").foregroundColor(Theme.muted))
                        .padding(14)
                        .background(Theme.panel)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text("Ishtirokchilar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.top, 20)

                    Text("Biriktirish ro'yxati sizning unvoningizga qarab cheklangan")
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                        .padding(.top, 2)

                    participants.padding(.top, 10)

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(Theme.danger)
                            .padding(.top, 12)
                    }

                    Button {
                        Task { await create() }
                    } label: {
                        ZStack {
                            if busy {
                                ProgressView().tint(.white)
                            } else {
                                Text("Yaratish").font(.headline).foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(canSubmit ? Theme.accent : Theme.accent.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canSubmit)
                    .padding(.top, 24)
                }
                .padding(20)
            }
            .svcBackground()
            .navigationTitle("Majlis yaratish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Bekor qilish") { dismiss() }
                        .foregroundColor(Theme.muted)
                }
            }
        }
        .tint(Theme.accent)
        .task { await loadPeople() }
    }

    @ViewBuilder
    private var participants: some View {
        if let people {
            if people.isEmpty {
                Text("Biriktiriladigan xodim yo'q")
                    .font(.footnote)
                    .foregroundColor(Theme.muted)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(people) { u in
                        let on = selected.contains(u.id)
                        Button {
                            if on { selected.remove(u.id) } else { selected.insert(u.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: on ? "checkmark.square.fill" : "square")
                                    .foregroundColor(on ? Theme.accent : Theme.muted)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(u.displayName)
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                    Text(Labels.role(u.roleValue))
                                        .font(.caption)
                                        .foregroundColor(Theme.muted)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .background(on ? Theme.panelHi : Theme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            ProgressView()
                .tint(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
    }

    private var canSubmit: Bool {
        !busy && !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @MainActor
    private func loadPeople() async {
        do {
            people = try await state.api.assignable(token: session.token)
        } catch {
            self.error = error.localizedDescription
            people = []
        }
    }

    @MainActor
    private func create() async {
        error = nil
        busy = true
        defer { busy = false }

        do {
            _ = try await state.api.createMeeting(
                token: session.token,
                title: title.trimmingCharacters(in: .whitespaces),
                inviteeIds: Array(selected)
            )
            onCreated()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
