enum HealthAIStreamEvent: Equatable, Sendable {
    case textDelta(String)
    case completed(HealthAIResponse)
}

protocol AIService: Sendable {
    func respond(to request: HealthAIRequest) async throws -> HealthAIResponse
    func streamResponse(
        to request: HealthAIRequest
    ) -> AsyncThrowingStream<HealthAIStreamEvent, Error>
}

extension AIService {
    func streamResponse(
        to request: HealthAIRequest
    ) -> AsyncThrowingStream<HealthAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await respond(to: request)
                    try Task.checkCancellation()
                    continuation.yield(.textDelta(response.summary))
                    continuation.yield(.completed(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
