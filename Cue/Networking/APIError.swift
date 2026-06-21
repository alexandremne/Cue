import Foundation

/// Typed errors for the Anthropic networking layer.
///
/// `errorDescription` carries friendly, user-facing copy so the agent can surface
/// failures inline as an assistant message without leaking internals or crashing.
enum APIError: LocalizedError, Equatable {
    /// No API key configured (Secrets.xcconfig empty / missing).
    case missingAPIKey
    /// The endpoint URL could not be formed.
    case invalidURL
    /// The response was not a valid HTTP response or could not be understood.
    case invalidResponse
    /// The device appears to be offline (airplane mode, no connection).
    case offline
    /// The request timed out.
    case timedOut
    /// A non-2xx HTTP status, with the model's error message when available.
    case http(status: Int, message: String?)
    /// Failed to encode the request or decode the response.
    case decoding(String)
    /// The model returned no usable content.
    case noAssistantContent

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key is set. Add your Anthropic key in Config/Secrets.xcconfig to enable Cue (see the README)."
        case .invalidURL:
            return "Cue is misconfigured — the model endpoint is invalid."
        case .invalidResponse:
            return "I got an unexpected response from the model. Please try again."
        case .offline:
            return "I couldn't reach the model — check your connection and try again."
        case .timedOut:
            return "That took too long. Check your connection and try again."
        case .http(let status, let message):
            switch status {
            case 401:
                return "The API key looks invalid. Double-check it in Config/Secrets.xcconfig."
            case 429:
                return "The model is rate-limiting requests. Give it a moment and try again."
            case 500...599:
                return "The model service had a problem. Please try again in a moment."
            default:
                if let message, !message.isEmpty {
                    return "The model returned an error (\(status)): \(message)"
                }
                return "The model returned an error (\(status)). Please try again."
            }
        case .decoding:
            return "I couldn't understand the model's response. Please try again."
        case .noAssistantContent:
            return "The model didn't return anything. Please try again."
        }
    }
}
