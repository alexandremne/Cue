import Foundation

/// Provider-agnostic seam for the agent's model calls. The concrete provider is
/// isolated behind this protocol so it can be swapped (or mocked in previews/tests)
/// without touching the agent loop.
protocol AnthropicClient: Sendable {
    /// Sends a Messages API request and returns the decoded response. Runs off the
    /// main actor. Throws `APIError` on any failure.
    func send(_ request: MessagesRequest) async throws -> MessagesResponse
}

/// Runtime configuration for the model provider. Injected so the model id, token
/// budget, endpoint, and API version can change without touching call sites.
struct AnthropicConfiguration: Sendable {
    var apiKey: String
    var model: String
    var maxTokens: Int
    var baseURLString: String
    var apiVersion: String

    /// Default model per spec; `claude-haiku-4-5` is an acceptable faster alternative.
    static let defaultModel = "claude-sonnet-4-6"

    init(apiKey: String,
         model: String = AnthropicConfiguration.defaultModel,
         maxTokens: Int = 1024,
         baseURLString: String = "https://api.anthropic.com/v1/messages",
         apiVersion: String = "2023-06-01") {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.baseURLString = baseURLString
        self.apiVersion = apiVersion
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Reads runtime configuration (the API key) from the app's Info.plist — which is
/// populated from `Secrets.xcconfig` at build time — and falls back to the process
/// environment so SwiftUI previews and tests can inject a key without a build setting.
enum AppConfig {
    static var apiKey: String {
        if let environment = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
           !environment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return environment.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let key = Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String {
            return key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    static var configuration: AnthropicConfiguration {
        AnthropicConfiguration(apiKey: apiKey)
    }
}

/// Concrete `AnthropicClient` backed by `URLSession` and the Anthropic Messages
/// API. Uses `async/await`, typed `Codable` models, explicit error mapping, set
/// timeouts, and no force-unwraps.
struct URLSessionAnthropicClient: AnthropicClient {
    let configuration: AnthropicConfiguration
    let session: URLSession

    init(configuration: AnthropicConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        guard configuration.hasAPIKey else { throw APIError.missingAPIKey }
        guard let url = URL(string: configuration.baseURLString) else { throw APIError.invalidURL }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(configuration.apiVersion, forHTTPHeaderField: "anthropic-version")

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw APIError.decoding("Failed to encode request: \(error.localizedDescription)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
            switch urlError.code {
            case .timedOut:
                throw APIError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                 .cannotConnectToHost, .cannotFindHost, .internationalRoamingOff:
                throw APIError.offline
            default:
                throw APIError.offline
            }
        } catch {
            throw APIError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }

        do {
            return try JSONDecoder().decode(MessagesResponse.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error?.message
    }
}
