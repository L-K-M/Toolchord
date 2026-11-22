import Foundation

public let providerServiceName = "ch.lkmc.Toolchord.AuthoringProvider"

/// The authoring process accepts only these operations. Document payloads,
/// trial inputs and clipboard values have no field in this protocol.
public enum ProviderMessage: Codable, Sendable {
    case listHarnesses
    case listModels(provider: String, endpoint: String)
    case generate(provider: String, endpoint: String, model: String, prompt: String)
    case hasKey(endpoint: String)
    case setKey(endpoint: String, key: String?)
}

@objc(ToolchordAuthoringProvider)
public protocol ProviderRemote {
    func perform(_ message: Data, withReply reply: @escaping @Sendable (Data?, String?) -> Void)
}

public struct ProviderFailure: LocalizedError, Sendable {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}
