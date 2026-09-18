import Foundation

/// The one HTTP call an adapter makes, behind a seam a test can stand in for.
///
/// The adapters reached for `URLSession.shared` directly, which meant the only
/// way to exercise a 401, a 429 or a truncated body was to actually provoke one
/// against a live account. Everything below the seam is unchanged — `URLSession`
/// satisfies it as-is — but a fixture can now answer instead.
public protocol UsageTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: UsageTransport {}

/// What a provider's answer tells us about whether we have a reading.
public enum UsageFetchResult {
    case success(Data)
    case failure(UsageUnavailableReason)
}

public extension UsageTransport {
    /// Performs the request and classifies the outcome.
    ///
    /// Classification lives here rather than in each adapter because the
    /// distinction that matters — is this a credential problem, a rate problem,
    /// a network problem, or a provider problem — is identical for all of them,
    /// and every adapter that reimplemented it collapsed the four into a single
    /// "return a plausible number" branch.
    func usageData(for request: URLRequest) async -> UsageFetchResult {
        do {
            let (data, response) = try await data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.malformedResponse)
            }
            guard http.statusCode == 200 else {
                return .failure(UsageUnavailableReason(httpStatus: http.statusCode))
            }
            return .success(data)
        } catch {
            return .failure(UsageUnavailableReason(transportError: error))
        }
    }
}

public extension UsageUnavailableReason {
    /// The reason a status code implies.
    init(httpStatus code: Int) {
        switch code {
        case 401, 403: self = .authenticationFailed
        case 429: self = .rateLimited
        default: self = .providerError
        }
    }

    /// The reason a thrown transport error implies.
    ///
    /// A timeout is a network failure and not a provider one: the provider
    /// never got the chance to answer, so nothing about the account has been
    /// established either way.
    init(transportError error: Error) {
        switch (error as? URLError)?.code {
        case .userAuthenticationRequired: self = .authenticationFailed
        default: self = .networkFailure
        }
    }
}
