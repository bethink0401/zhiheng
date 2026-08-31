import Foundation

struct AIServiceConfiguration: Equatable, Sendable {
    let endpoint: URL?

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard
    ) -> AIServiceConfiguration {
        if let value = environment["ZHIHENG_AI_PROXY_URL"],
           let url = validatedEndpoint(value) {
            return AIServiceConfiguration(endpoint: url)
        }
        if let value = userDefaults.string(forKey: "zhihengAIProxyURL"),
           let url = validatedEndpoint(value) {
            return AIServiceConfiguration(endpoint: url)
        }
#if DEBUG
        return AIServiceConfiguration(
            endpoint: URL(string: "http://127.0.0.1:8787/v1/health-assistant/respond")
        )
#else
        return AIServiceConfiguration(endpoint: nil)
#endif
    }

    private static func validatedEndpoint(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || isLocalDevelopmentURL(url)
        else {
            return nil
        }
        return url
    }

    private static func isLocalDevelopmentURL(_ url: URL) -> Bool {
#if DEBUG
        guard url.scheme?.lowercased() == "http" else { return false }
        return ["127.0.0.1", "localhost"].contains(url.host?.lowercased() ?? "")
#else
        return false
#endif
    }
}

struct OpenAIProxyService: AIService, Sendable {
    private let configuration: AIServiceConfiguration
    private let session: URLSession

    init(
        configuration: AIServiceConfiguration = .current(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    func respond(to request: HealthAIRequest) async throws -> HealthAIResponse {
        guard let endpoint = configuration.endpoint else {
            throw HealthAIServiceError.notConfigured
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let body = try? encoder.encode(request) else {
            throw HealthAIServiceError.invalidRequest
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 45
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = body

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HealthAIServiceError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw HealthAIServiceError.serviceRejected(
                    statusCode: httpResponse.statusCode
                )
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let modelResponse = try? decoder.decode(
                HealthAIResponse.self,
                from: data
            ) else {
                throw HealthAIServiceError.invalidResponse
            }
            return try HealthAIResponseValidator.validate(
                modelResponse,
                against: request.factPack
            )
        } catch is CancellationError {
            throw HealthAIServiceError.cancelled
        } catch let error as HealthAIServiceError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw HealthAIServiceError.timedOut
        } catch {
            throw HealthAIServiceError.networkUnavailable
        }
    }

    func streamResponse(
        to request: HealthAIRequest
    ) -> AsyncThrowingStream<HealthAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await streamResponse(to: request, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: HealthAIServiceError.cancelled)
                } catch let error as HealthAIServiceError {
                    continuation.finish(throwing: error)
                } catch let error as URLError where error.code == .timedOut {
                    continuation.finish(throwing: HealthAIServiceError.timedOut)
                } catch {
                    continuation.finish(throwing: HealthAIServiceError.networkUnavailable)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func streamResponse(
        to request: HealthAIRequest,
        continuation: AsyncThrowingStream<HealthAIStreamEvent, Error>.Continuation
    ) async throws {
        guard let endpoint = configuration.endpoint else {
            throw HealthAIServiceError.notConfigured
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let body = try? encoder.encode(request) else {
            throw HealthAIServiceError.invalidRequest
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = body

        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HealthAIServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HealthAIServiceError.serviceRejected(
                statusCode: httpResponse.statusCode
            )
        }

        var didComplete = false
        var structuredDecoder = StructuredHealthResponseStreamDecoder()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payloadText = line.dropFirst(5).trimmingCharacters(
                in: .whitespaces
            )
            guard let payloadData = payloadText.data(using: .utf8),
                  let event = try? decoder.decode(
                    ProxyHealthAIStreamEvent.self,
                    from: payloadData
                  )
            else { continue }

            switch event.type {
            case "response.output_text.delta":
                if let delta = event.delta, !delta.isEmpty {
                    let visibleDelta = structuredDecoder.append(delta)
                    if !visibleDelta.isEmpty {
                        continuation.yield(.textDelta(visibleDelta))
                    }
                }
            case "response.completed":
                guard let response = event.response else {
                    throw HealthAIServiceError.invalidResponse
                }
                let validated = try HealthAIResponseValidator.validate(
                    response,
                    against: request.factPack
                )
                continuation.yield(.completed(validated))
                didComplete = true
            case "response.incomplete", "response.failed":
                throw HealthAIServiceError.invalidResponse
            default:
                continue
            }
            if didComplete { break }
        }
        guard didComplete else {
            throw HealthAIServiceError.invalidResponse
        }
    }
}

private struct ProxyHealthAIStreamEvent: Decodable {
    let type: String
    let delta: String?
    let response: HealthAIResponse?
}
