import SwiftUI

struct SignInView: View {
    @Environment(AuthService.self) private var auth

    @State private var isRegistering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field { case name, email, password }

    var body: some View {
        ZStack {
            Color.axBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    branding
                        .padding(.top, 52)
                        .padding(.bottom, 36)
                    features
                        .padding(.bottom, 24)
                    signInArea
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
#if os(iOS)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
#endif
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Branding

    private var branding: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.axAccent.opacity(0.15))
                    .frame(width: 88, height: 88)
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.axAccent)
            }

            VStack(spacing: 8) {
                Text("NorthAx")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Your intelligent training OS")
                    .font(.title3)
                    .foregroundStyle(.axSecondary)
            }
        }
    }

    // MARK: - Feature list

    private var features: some View {
        VStack(alignment: .leading, spacing: 18) {
            featureRow(
                icon: "waveform.path.ecg",
                color: .axGreen,
                title: "Reads your body every morning",
                subtitle: "HRV, sleep, and training load analysed daily"
            )
            featureRow(
                icon: "brain.head.profile",
                color: .axBlue,
                title: "Explains every recommendation",
                subtitle: "Science-backed coaching in plain language"
            )
            featureRow(
                icon: "calendar.badge.plus",
                color: .axAccent,
                title: "Builds your plan automatically",
                subtitle: "Adjusts forward whenever your life changes"
            )
        }
        .padding(24)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.axBorder, lineWidth: 1))
    }

    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.axSecondary)
                    .lineSpacing(2)
            }
        }
    }

    // MARK: - Sign In / Register

    private var signInArea: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                if isRegistering {
                    nameField
                }
                emailField
                passwordField
            }

            submitButton

            if let error = auth.authError {
                errorBanner(error)
            }

            toggleModeButton

#if DEBUG
            debugBypass
#endif

            Text("Your data stays on device. NorthAx never shares personal health information.")
                .font(.caption2)
                .foregroundStyle(.axTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .animation(.easeInOut(duration: 0.2), value: isRegistering)
        .onSubmit(advanceFocus)
    }

    // MARK: - Fields

    private var nameField: some View {
        fieldContainer(icon: "person") {
            TextField("Name", text: $name)
                .textContentType(.name)
                .submitLabel(.next)
                .focused($focusedField, equals: .name)
        }
    }

    private var emailField: some View {
        fieldContainer(icon: "envelope") {
            emailTextField
        }
    }

    private var emailTextField: some View {
        let field = TextField("Email", text: $email)
            .textContentType(.username)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($focusedField, equals: .email)
#if os(iOS)
        return field
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
#else
        return field
#endif
    }

    private var passwordField: some View {
        fieldContainer(icon: "lock") {
            SecureField("Password", text: $password)
                .textContentType(isRegistering ? .newPassword : .password)
                .submitLabel(.go)
                .focused($focusedField, equals: .password)
                .onSubmit(submit)
        }
    }

    private func fieldContainer<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.axSecondary)
                .frame(width: 20)
            content()
                .foregroundStyle(.white)
                .tint(.axAccent)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.axBorder, lineWidth: 1))
    }

    // MARK: - Actions

    private var submitButton: some View {
        Button(action: submit) {
            ZStack {
                if auth.isAuthenticating {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text(isRegistering ? "Create Account" : "Sign In")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.white)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(auth.isAuthenticating)
    }

    private var toggleModeButton: some View {
        Button {
            auth.authError = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                isRegistering.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Text(isRegistering ? "Already have an account?" : "Don't have an account?")
                    .foregroundStyle(.axSecondary)
                Text(isRegistering ? "Sign in" : "Create one")
                    .foregroundStyle(.axAccent)
                    .fontWeight(.semibold)
            }
            .font(.caption)
        }
        .padding(.top, 2)
    }

    private func submit() {
        focusedField = nil
        if isRegistering {
            auth.register(name: name, email: email, password: password)
        } else {
            auth.signIn(email: email, password: password)
        }
    }

    private func advanceFocus() {
        switch focusedField {
        case .name:  focusedField = .email
        case .email: focusedField = .password
        default:     break
        }
    }

    private func errorBanner(_ error: AuthSignInError) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.axRed)
                .font(.caption)
                .padding(.top, 1)
            Text(error.errorDescription ?? "")
                .font(.caption)
                .foregroundStyle(.axRed)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.axRed.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.axRed.opacity(0.2), lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.easeInOut(duration: 0.25), value: auth.authError != nil)
    }

#if DEBUG
    private var debugBypass: some View {
        Button {
            auth.signInAsDebugUser()
        } label: {
            Text("Continue as Debug User")
                .font(.caption.weight(.medium))
                .foregroundStyle(.axSecondary)
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.axBorder, lineWidth: 1))
        }
    }
#endif
}

#Preview {
    SignInView()
        .environment(AuthService())
}
