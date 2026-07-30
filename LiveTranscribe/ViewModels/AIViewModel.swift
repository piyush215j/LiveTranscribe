// AIViewModel.swift
// LiveTranscribe
//
// Manages AI feature interactions (summarise, notes, flashcards, chat)
// via the local Ollama LLM bridge.

import Foundation
import Combine
import AppKit

@MainActor
final class AIViewModel: ObservableObject {

    // MARK: - Published state

    @Published var selectedFeature: AIFeature = .summarise
    @Published private(set) var generatedText = ""
    @Published private(set) var isGenerating  = false
    @Published private(set) var errorMessage: String?

    // Chat
    @Published var chatMessages: [ChatMessage] = []
    @Published var chatInput = ""
    @Published private(set) var isChatting = false

    // Ollama status
    @Published private(set) var isOllamaAvailable = false
    @Published var selectedModel = ""

    // MARK: - Private

    private let ai = AIService.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        ai.$isAvailable
            .receive(on: DispatchQueue.main)
            .assign(to: &$isOllamaAvailable)

        ai.$selectedModel
            .receive(on: DispatchQueue.main)
            .assign(to: &$selectedModel)

        Task { await ai.checkAvailability() }
    }

    // MARK: - Feature generation

    func generate(for session: TranscriptSession) async {
        guard !isGenerating else { return }
        guard isOllamaAvailable else {
            errorMessage = "Ollama is not running. Start it with: ollama serve"
            return
        }

        let transcript = session.segments.map { "\($0.formattedStartTime) \($0.text)" }
            .joined(separator: "\n")

        guard !transcript.isEmpty else {
            errorMessage = "This session has no transcript content yet."
            return
        }

        isGenerating  = true
        generatedText = ""
        errorMessage  = nil

        let model = selectedModel.isEmpty ? "llama3" : selectedModel

        do {
            for try await token in ai.generate(
                feature: selectedFeature,
                transcript: transcript,
                model: model
            ) {
                generatedText += token
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }

    // MARK: - Chat

    func sendChatMessage(for session: TranscriptSession) async {
        let input = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !isChatting else { return }

        guard isOllamaAvailable else {
            errorMessage = "Ollama is not running. Start it with: ollama serve"
            return
        }

        let userMessage = ChatMessage(role: .user, content: input)
        chatMessages.append(userMessage)
        chatInput = ""
        isChatting = true
        errorMessage = nil

        let transcript = session.segments.map { "\($0.formattedStartTime) \($0.text)" }
            .joined(separator: "\n")

        var assistantMessage = ChatMessage(role: .assistant, content: "")
        chatMessages.append(assistantMessage)
        let assistantIndex = chatMessages.count - 1

        let model = selectedModel.isEmpty ? "llama3" : selectedModel

        do {
            for try await token in ai.chat(
                messages: chatMessages.dropLast(),   // don't include the empty placeholder
                transcript: transcript,
                model: model
            ) {
                assistantMessage.content += token
                chatMessages[assistantIndex] = assistantMessage
            }
        } catch {
            errorMessage = error.localizedDescription
            chatMessages[assistantIndex].content = "Error: \(error.localizedDescription)"
        }

        isChatting = false
    }

    func clearChat() {
        chatMessages = []
        chatInput = ""
    }

    func clearGenerated() {
        generatedText = ""
        errorMessage  = nil
    }

    // MARK: - Copy to clipboard

    func copyGeneratedText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(generatedText, forType: .string)
    }

    // MARK: - Ollama refresh

    func refreshOllama() async {
        await ai.checkAvailability()
        selectedModel = ai.selectedModel
    }

    var availableModels: [String] { ai.availableModels }
}
