import Foundation
import CryptoKit

public enum UsageFetchError: Error, Equatable, LocalizedError {
    case missingCredentials
    case httpStatus(Int)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .missingCredentials: return L10n.errorMissingCredentials.text
        case .httpStatus(let status): return L10n.errorHTTPStatus(status).text
        case .invalidResponse: return L10n.errorInvalidResponse.text
        }
    }
}

/// A failed read must never be turned into a freshly measured percentage.
enum UsageHTTPClient {
    static func data(for request: URLRequest, session: URLSession) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageFetchError.invalidResponse }
        guard http.statusCode == 200 else { throw UsageFetchError.httpStatus(http.statusCode) }
        return (data, http)
    }
}

/// Last-success cache scoped to a credential, never shared across key changes.
final class UsageReadCache {
    private let last = Locked<(fingerprint: SHA256.Digest, snapshot: UsageSnapshot)?>(nil)

    func read(credential: String, fetch: () async throws -> UsageSnapshot) async throws -> UsageSnapshot {
        let fingerprint = SHA256.hash(data: Data(credential.utf8))
        do {
            let snapshot = try await fetch()
            last.value = (fingerprint, snapshot)
            return snapshot
        } catch {
            guard let cached = last.value, cached.fingerprint == fingerprint else { throw error }
            var previous = cached.snapshot
            previous.fetchError = (error as? UsageFetchError)?.localizedDescription
                ?? L10n.errorNetworkRefreshFailed.text
            return previous
        }
    }
}
