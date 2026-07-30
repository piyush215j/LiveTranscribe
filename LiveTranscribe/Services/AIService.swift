// AIService.swift
// LiveTranscribe
//
// Talks to a local Ollama instance (http://localhost:11434) to provide
// AI-powered features: summarisation, study notes, flashcards, key points,
// action items, and free-form chat with the transcript.

import Foundation
import Combine

// MARK: - AI feature types

enum AIFeature: String, CaseIterable, Identifiable {
    case summarise   = "summarise"
    case studyNotes  = "study_notes"
    case flashcards  = "flashcards"
    case keyPoints   = "key_points"
    case actionItems = "action_items"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .summarise:   return "Summarise"
        case .studyNotes:  return "Study Notes"
        case .flashcards:  return "Flashcards"
        case .keyPoints:   return "Key Points"
        case .actionItems: return "Action Items"
        }
    }

    var icon: String {
        switch self {
        case .summarise:   return "text.alignleft"
        case .studyNotes:  return "note.text"
        case .flashcards:  return "square.stack"
        case .keyPoints:   return "list.bullet"
        case .actionItems: return "checklist"
        }
    }

    var prompt: String {
        switch self {
        case .summarise:
            return """
            Provide a concise summary of the following transcript. \
            Focus on the main topics covered. Use plain prose, 3-5 paragraphs.

            TRANSCRIPT:
            """
        case .studyNotes:
            return """
            Create structured study notes from the following transcript. \
            Use headers, bullet points, and highlight key terms in bold. \
            Organise by topic.

            TRANSCRIPT:
            """
        case .flashcards:
            return """
            Generate 10-15 question-and-answer flashcards from the following transcript. \
            Format each card as:
            Q: <question>
            A: <answer>

            TRANSCRIPT:
            """
        case .keyPoints:
            return """
            Extract the most important key points from the following transcript. \
            Present as a numbered list of concise statements.

            TRANSCRIPT:
            """
        case .actionItems:
            return """
            Identify any action items, tasks, or follow-ups mentioned in the \
            following transcript. Present as a checkbox list (- [ ] item).

            TRANSCRIPT:
            """
        }
    }
}

// MARK: - Chat message

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    var content: String
    let timestamp = Date()

    enum Role: String {
        case user, assistant, system
    }
}

// MARK: - AIService

/// Interfaces with Ollama for local LLM inference.
final class AIService: ObservableObject {

    static let shared = AIService()

    // MARK: Published state
    @Published private(set) var isAvailable = false
    @Published private(set) var availableModels: [String] = []
    @Published private(set) var selectedModel: String = "llama3"

    private let baseURL = URL(string: "http://localhost:11434")!
    private let session = URLSession.shared

    private init() {}

    // MARK: - Discovery

    /// Pings Ollama and fetches the model list.
    func checkAvailability() async {
        do {
            let url = baseURL.appendingPathComponent("api/tags")
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                await setAvailable(false)
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let names = models.compactMap { $0["name"] as? String }
                await setModels(names)
                if let first = names.first {
                    await setSelectedModel(first)
                }
            }
            await setAvailable(true)
        } catch {
            await setAvailable(false)
        }
    }

    // MARK: - Feature generation (streaming)

    /// Streams the AI response for a given feature using the transcript as context.
    func generate(
        feature: AIFeature,
        transcript: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        let prompt = "\(feature.prompt)\n\n\(transcript)"
        return streamGenerate(prompt: prompt, model: model)
    }

    /// Streams the AI response for a chat message with transcript context.
    func chat(
        messages: [ChatMessage],
        transcript: String,
        model: String
    ) -> AsyncThrowingStream<String, Error> {
        var ollamaMessages: [[String: String]] = [
            [
                "role": "system",
                "content": "You are a helpful assistant. The following is the transcript context:\n\n\(transcript)"
            ]
        ]
        for msg in messages {
            ollamaMessages.append(["role": msg.role.rawValue, "content": msg.content])
        }
        return streamChat(messages: ollamaMessages, model: model)
    }

    // MARK: - Ollama REST calls

    private func streamGenerate(
        prompt: String, model: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = self.baseURL.appendingPathComponent("api/generate")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body: [String: Any] = [
                        "model": model,
                        "prompt": prompt,
                        "stream": true
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, _) = try await self.session.bytes(for: request)
                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let token = json["response"] as? String
                        else { continue }
                        continuation.yield(token)
                        if json["done"] as? Bool == true { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func streamChat(
        messages: [[String: String]], model: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = self.baseURL.appendingPathComponent("api/chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body: [String: Any] = [
                        "model": model,
                        "messages": messages,
                        "stream": true
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, _) = try await self.session.bytes(for: request)
                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let message = json["message"] as? [String: Any],
                              let content = message["content"] as? String
                        else { continue }
                        continuation.yield(content)
                        if json["done"] as? Bool == true { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - MainActor helpers

    @MainActor private func setAvailable(_ value: Bool) {
        isAvailable = value
    }

    @MainActor private func setModels(_ models: [String]) {
        availableModels = models
    }

    @MainActor private func setSelectedModel(_ model: String) {
        selectedModel = model
    }

    func selectModel(_ model: String) {
        Task { @MainActor in selectedModel = model }
    }
}
