// AIPanelView.swift
// LiveTranscribe
//
// Sheet presenting AI-powered analysis tools:
// Summarise, Study Notes, Flashcards, Key Points, Action Items, and Chat.

import SwiftUI

struct AIPanelView: View {

    let session: TranscriptSession

    @EnvironmentObject var aiVM: AIViewModel
    @Environment(\.dismiss) var dismiss

    @State private var activeTab: Tab = .features

    enum Tab { case features, chat }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────
            header

            Divider()

            // ── Ollama status banner ──────────────────────────────────────
            if !aiVM.isOllamaAvailable {
                ollamaBanner
            }

            // ── Tab switcher ─────────────────────────────────────────────
            Picker("", selection: $activeTab) {
                Text("AI Features").tag(Tab.features)
                Text("Chat").tag(Tab.chat)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Divider().padding(.top, 12)

            // ── Content ───────────────────────────────────────────────────
            Group {
                if activeTab == .features {
                    featuresPane
                } else {
                    chatPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label("AI Features", systemImage: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                Text(session.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Model picker
            if aiVM.isOllamaAvailable && !aiVM.availableModels.isEmpty {
                Picker("Model", selection: $aiVM.selectedModel) {
                    ForEach(aiVM.availableModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Ollama banner

    private var ollamaBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ollama not detected")
                    .font(.system(size: 12, weight: .semibold))
                Text("Install Ollama and run `ollama serve` to enable AI features.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") {
                Task { await aiVM.refreshOllama() }
            }
            .buttonStyle(.bordered)
            Link("Install", destination: URL(string: "https://ollama.ai")!)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Features pane

    private var featuresPane: some View {
        HSplitView {
            // Feature selector
            List(AIFeature.allCases, selection: $aiVM.selectedFeature) { f in
                Label(f.displayName, systemImage: f.icon)
                    .tag(f)
                    .padding(.vertical, 3)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 160, maxWidth: 200)

            // Generated output
            VStack(spacing: 0) {
                // Generate button
                HStack {
                    Text(aiVM.selectedFeature.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if !aiVM.generatedText.isEmpty {
                        Button {
                            aiVM.copyGeneratedText()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        Button {
                            aiVM.clearGenerated()
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    Button {
                        Task { await aiVM.generate(for: session) }
                    } label: {
                        if aiVM.isGenerating {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Label("Generate", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(aiVM.isGenerating || !aiVM.isOllamaAvailable)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                // Output area
                ScrollView {
                    if let err = aiVM.errorMessage {
                        errorView(err)
                    } else if aiVM.isGenerating && aiVM.generatedText.isEmpty {
                        ProgressView("Generating…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 60)
                    } else if aiVM.generatedText.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: aiVM.selectedFeature.icon)
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary.opacity(0.4))
                            Text("Click Generate to analyse this transcript.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 60)
                    } else {
                        Text(aiVM.generatedText)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
            }
        }
    }

    // MARK: - Chat pane

    private var chatPane: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(aiVM.chatMessages) { msg in
                            ChatBubble(message: msg)
                                .id(msg.id)
                        }
                        if aiVM.isChatting {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Thinking…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                        }
                        Color.clear.frame(height: 1).id("chatBottom")
                    }
                    .padding(16)
                }
                .onChange(of: aiVM.chatMessages.count) { _ in
                    withAnimation { proxy.scrollTo("chatBottom") }
                }
            }

            Divider()

            // Input bar
            HStack(spacing: 10) {
                TextField("Ask about the transcript…", text: $aiVM.chatInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit {
                        if !aiVM.chatInput.isEmpty {
                            Task { await aiVM.sendChatMessage(for: session) }
                        }
                    }

                Button {
                    Task { await aiVM.sendChatMessage(for: session) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(aiVM.chatInput.isEmpty || aiVM.isChatting || !aiVM.isOllamaAvailable)

                Button {
                    aiVM.clearChat()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear chat history")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Error view

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Chat bubble

private struct ChatBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            Text(message.content)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isUser
                    ? Color.accentColor.opacity(0.85)
                    : Color.secondary.opacity(0.12)
                )
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if !isUser { Spacer(minLength: 60) }
        }
    }
}
