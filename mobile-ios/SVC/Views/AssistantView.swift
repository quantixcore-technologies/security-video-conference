import SwiftUI

/// Ilova ichidagi yordamchi (S39) — Android/Tauri/web bilan bir xil server API'si
/// (`/api/assistant/*`). Kontent va matching serverda; bu ekran faqat ko'rsatadi.
struct AssistantView: View {
    let session: Session
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var items: [ChatItem] = []
    @State private var suggestions: [AssistantEntry] = []
    @State private var input = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            greeting
                            if items.isEmpty, !suggestions.isEmpty {
                                EntryChips(title: "Tez-tez so'raladi:", entries: suggestions) { open($0) }
                            }
                            ForEach(items) { row($0) }
                            if busy {
                                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding()
                    }
                    .onChange(of: items.count) { _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
                inputBar
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Yordamchi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Yopish") { dismiss() }.foregroundColor(Theme.accent)
                }
            }
            .task { await loadSuggestions() }
        }
    }

    // MARK: Bo'laklar

    private var greeting: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundColor(Theme.accent)
                .font(.system(size: 18))
            Text("Salom! Men SVC yordamchisiman. Tizimdan foydalanish bo'yicha savolingizni yozing.")
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func row(_ item: ChatItem) -> some View {
        switch item.kind {
        case let .user(text):
            Text(text)
                .foregroundColor(.white)
                .padding(10)
                .background(Theme.accent.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .trailing)

        case let .answer(entry, related):
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.answer)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if !related.isEmpty {
                    EntryChips(title: "O'xshash savollar:", entries: related) { open($0) }
                }
            }
            .answerBubble()

        case let .unsure(candidates):
            VStack(alignment: .leading, spacing: 8) {
                Text("Aniq tushunolmadim. Shulardan birini nazarda tutdingizmi?")
                    .foregroundColor(.white)
                EntryChips(title: nil, entries: candidates) { open($0) }
            }
            .answerBubble()

        case let .restricted(roles):
            VStack(alignment: .leading, spacing: 6) {
                Text("Bu amal sizning rolingizda mavjud emas.")
                    .foregroundColor(.white)
                if !roles.isEmpty {
                    Text("Kimga murojaat qilish kerak: \(roles.joined(separator: ", "))")
                        .foregroundColor(Theme.muted)
                        .font(.footnote)
                }
            }
            .answerBubble()

        case let .noMatch(suggestions):
            VStack(alignment: .leading, spacing: 8) {
                Text("Bunga tayyor javob topilmadi. Balki shulardan biri kerakdir:")
                    .foregroundColor(.white)
                EntryChips(title: nil, entries: suggestions) { open($0) }
            }
            .answerBubble()

        case let .error(text):
            Text(text).foregroundColor(Theme.danger).answerBubble()
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Savolingiz…", text: $input)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .padding(10)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .submitLabel(.send)
                .onSubmit { ask(input) }
            Button {
                ask(input)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(input.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.muted : Theme.accent)
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || busy)
        }
        .padding(10)
        .background(Theme.bg)
    }

    // MARK: Amallar

    @MainActor
    private func loadSuggestions() async {
        suggestions = (try? await state.api.assistantSuggestions(token: session.token)) ?? []
    }

    private func ask(_ question: String) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        input = ""
        items.append(ChatItem(kind: .user(text)))
        busy = true
        Task { @MainActor in
            do {
                append(from: try await state.api.assistantAsk(token: session.token, question: text))
            } catch {
                items.append(ChatItem(kind: .error("Javob olib bo'lmadi. Qayta urinib ko'ring.")))
            }
            busy = false
        }
    }

    /// "O'xshash savol" yoki taklif bosilganda — id bo'yicha aniq javob (Android bilan bir xil).
    private func open(_ entry: AssistantEntry) {
        guard !busy else { return }
        items.append(ChatItem(kind: .user(entry.question)))
        busy = true
        Task { @MainActor in
            do {
                let full = try await state.api.assistantEntry(token: session.token, id: entry.id)
                items.append(ChatItem(kind: .answer(full, related: [])))
            } catch {
                items.append(ChatItem(kind: .error("Javob olib bo'lmadi.")))
            }
            busy = false
        }
    }

    @MainActor
    private func append(from result: AssistResult) {
        switch result {
        case let .ok(entry, related): items.append(ChatItem(kind: .answer(entry, related: related)))
        case let .unsure(candidates): items.append(ChatItem(kind: .unsure(candidates)))
        case let .restricted(_, roles): items.append(ChatItem(kind: .restricted(roles)))
        case let .noMatch(suggestions): items.append(ChatItem(kind: .noMatch(suggestions)))
        }
    }
}

/// Suhbatdagi bitta element.
private struct ChatItem: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case user(String)
        case answer(AssistantEntry, related: [AssistantEntry])
        case unsure([AssistantEntry])
        case restricted([String])
        case noMatch([AssistantEntry])
        case error(String)
    }
}

/// Bosiladigan savol-yozuvlar ro'yxati (takliflar / o'xshash savollar / nomzodlar).
private struct EntryChips: View {
    let title: String?
    let entries: [AssistantEntry]
    let action: (AssistantEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).foregroundColor(Theme.muted).font(.footnote)
            }
            ForEach(entries) { entry in
                Button { action(entry) } label: {
                    HStack {
                        Text(entry.question)
                            .foregroundColor(Theme.accent)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right").foregroundColor(Theme.muted).font(.caption)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.panelHi)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

private extension View {
    /// Yordamchi javob "puffagi" — bir xil ko'rinish.
    func answerBubble() -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
