import SwiftUI

/// Kirish ekrani — server manzili ham, uchrashuv ID ham so'ralmaydi.
/// Parol maydonida ko'z ikonkasi (ko'rsatish/yashirish) — Android bilan bir xil.
struct LoginView: View {
    @EnvironmentObject private var state: AppState

    @State private var username = ""
    @State private var password = ""
    @State private var passwordVisible = false
    @State private var totpToken: String?
    @State private var totpCode = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    state.showLogin = false
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                        .padding(8)
                }
                .accessibilityLabel("Orqaga")

                Text("Tizimga kirish")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider().overlay(Theme.panel)

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 60)

                    Image(systemName: "shield.fill")
                        .font(.system(size: 52))
                        .foregroundColor(Theme.accent)

                    Text("Security Video Conference")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.top, 8)

                    Text("Xavfsiz video-aloqa")
                        .font(.subheadline)
                        .foregroundColor(Theme.muted)

                    if totpToken == nil {
                        credentialsFields.padding(.top, 28)
                    } else {
                        totpFields.padding(.top, 28)
                    }

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(Theme.danger)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                    }

                    primaryButton.padding(.top, 24)

                    if totpToken != nil {
                        Button("Orqaga") {
                            totpToken = nil
                            totpCode = ""
                            error = nil
                        }
                        .foregroundColor(Theme.muted)
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .svcBackground()
    }

    // MARK: Maydonlar

    private var credentialsFields: some View {
        VStack(spacing: 12) {
            TextField("", text: $username, prompt: Text("Login").foregroundColor(Theme.muted))
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(Theme.panel)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 0) {
                Group {
                    if passwordVisible {
                        TextField("", text: $password, prompt: Text("Parol").foregroundColor(Theme.muted))
                    } else {
                        SecureField("", text: $password, prompt: Text("Parol").foregroundColor(Theme.muted))
                    }
                }
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)

                Button {
                    passwordVisible.toggle()
                } label: {
                    Image(systemName: passwordVisible ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(Theme.muted)
                }
                .accessibilityLabel(passwordVisible ? "Parolni yashirish" : "Parolni ko'rsatish")
            }
            .padding(14)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var totpFields: some View {
        VStack(spacing: 10) {
            Text("Ikki bosqichli tasdiqlash")
                .font(.headline)
                .foregroundColor(.white)
            Text("Autentifikator ilovasidagi 6 xonali kodni kiriting")
                .font(.caption)
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)

            TextField("", text: $totpCode, prompt: Text("2FA kod").foregroundColor(Theme.muted))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .padding(14)
                .background(Theme.panel)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onChange(of: totpCode) { newValue in
                    let digits = newValue.filter(\.isNumber)
                    totpCode = String(digits.prefix(6))
                }
        }
    }

    private var primaryButton: some View {
        Button {
            Task { await submit() }
        } label: {
            ZStack {
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Text(totpToken == nil ? "Kirish" : "Kodni tasdiqlash")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(canSubmit ? Theme.accent : Theme.accent.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!canSubmit)
    }

    private var canSubmit: Bool {
        if busy { return false }
        if totpToken == nil {
            return !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
        }
        return totpCode.count == 6
    }

    // MARK: Amal

    @MainActor
    private func submit() async {
        error = nil
        busy = true
        defer { busy = false }

        do {
            if let t = totpToken {
                let s = try await state.api.verifyTotp(totpToken: t, code: totpCode)
                state.signIn(s)
            } else {
                let res = try await state.api.login(
                    username: username.trimmingCharacters(in: .whitespaces),
                    password: password
                )
                switch res {
                case let .success(s):
                    state.signIn(s)
                case let .totpRequired(t):
                    totpToken = t
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
