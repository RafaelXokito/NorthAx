import SwiftUI

struct CoachView: View {
    @Environment(AthleteStore.self) private var store
    @State private var inputText = ""
    @State private var isTyping = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            messageList
            if !inputFocused { quickQuestionsBar }
            inputBar
        }
        .background(Color.axBackground.ignoresSafeArea())
        .navigationTitle("Your Coach")
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(store.messages) { msg in
                        ChatBubble(message: msg)
                            .id(msg.id)
                    }

                    if isTyping {
                        TypingIndicator()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 20)
                            .id("typing")
                    }

                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
            .onChange(of: store.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: isTyping) { _, typing in
                if typing {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Quick questions

    private var quickQuestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CoachMessage.quickQuestions, id: \.self) { q in
                    Button(q) {
                        send(q)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.axPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.axSurface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.axBorder, lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask your coach...", text: $inputText)
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(Color.axSurface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.axBorder, lineWidth: 1))
                .focused($inputFocused)
                .onSubmit { if !inputText.trimmingCharacters(in: .whitespaces).isEmpty { send(inputText) } }

            let trimmed = inputText.trimmingCharacters(in: .whitespaces)
            Button {
                send(trimmed)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(trimmed.isEmpty ? Color.axSecondary : Color.axAccent)
                    .clipShape(Circle())
            }
            .disabled(trimmed.isEmpty)
            .animation(.easeInOut(duration: 0.15), value: trimmed.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Send logic

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        store.messages.append(CoachMessage(content: trimmed, isCoach: false, timestamp: Date()))
        inputText = ""
        inputFocused = false
        isTyping = true

        Task {
            await store.respond(to: trimmed)
            isTyping = false
        }
    }
}

// MARK: - Chat bubble

struct ChatBubble: View {
    let message: CoachMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isCoach {
                coachAvatar
            } else {
                Spacer(minLength: 60)
            }

            Text(message.content)
                .font(.subheadline)
                .foregroundStyle(message.isCoach ? .axPrimary : Color.black)
                .lineSpacing(4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    message.isCoach
                        ? Color.axSurface
                        : Color.axAccent
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 18)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            message.isCoach ? Color.axBorder : Color.clear,
                            lineWidth: 1
                        )
                )
                .frame(maxWidth: .infinity, alignment: message.isCoach ? .leading : .trailing)

            if !message.isCoach {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
    }

    private var coachAvatar: some View {
        Image(systemName: "brain.head.profile")
            .font(.system(size: 14))
            .foregroundStyle(.axAccent)
            .frame(width: 32, height: 32)
            .background(Color.axAccent.opacity(0.12))
            .clipShape(Circle())
    }
}

// MARK: - Typing indicator

struct TypingIndicator: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.axSecondary)
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == i ? 1.3 : 0.8)
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.axBorder, lineWidth: 1))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                phase = (phase + 1) % 3
            }
        }
    }
}

#Preview {
    NavigationStack {
        CoachView()
            .environment(AthleteStore())
    }
}
