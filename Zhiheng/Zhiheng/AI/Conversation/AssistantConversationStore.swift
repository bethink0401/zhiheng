import Foundation

struct AssistantChatMessage: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String
    let response: HealthAIResponse?

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        response: HealthAIResponse? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.response = response
    }
}

struct AssistantConversationStore: Sendable {
    static let maximumStoredMessages = 80

    private let fileURL: URL

    init(
        scope: String = HealthDataMode.live.rawValue,
        fileURL: URL? = nil
    ) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let baseURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.fileURL = baseURL
                .appendingPathComponent("AIConversations", isDirectory: true)
                .appendingPathComponent("\(scope)-current.json", isDirectory: false)
        }
    }

    func load() throws -> [AssistantChatMessage] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([AssistantChatMessage].self, from: data)
    }

    func save(_ messages: [AssistantChatMessage]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let retainedMessages = Array(messages.suffix(Self.maximumStoredMessages))
        let data = try JSONEncoder().encode(retainedMessages)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
