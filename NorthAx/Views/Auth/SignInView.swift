import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthService.self) private var auth

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
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
#if os(iOS)
            .scrollBounceBehavior(.basedOnSize)
#endif
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                signInArea
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                    .background(Color.axBackground)
            }
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

    // MARK: - Sign In

    private var signInArea: some View {
        VStack(spacing: 14) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                auth.handleAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if let error = auth.authError {
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
                .background(Color.axRed.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.axRed.opacity(0.2), lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeInOut(duration: 0.25), value: auth.authError != nil)
            }

#if DEBUG
            debugBypass
#endif

            Text("Your data stays on device. NorthAx never shares personal health information.")
                .font(.caption2)
                .foregroundStyle(.axTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
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
