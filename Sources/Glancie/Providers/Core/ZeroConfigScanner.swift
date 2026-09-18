import Foundation

public final class ZeroConfigScanner {
    public let allAdapters: [AIProviderAdapter]
    
    public init(adapters: [AIProviderAdapter] = [
        ClaudeCodeAdapter(),
        OpenAI_CodexAdapter(),
        AntigravityAdapter(),
        CursorAdapter(),
        CopilotAdapter(),
        DeepSeekAdapter(),
        OpenRouterAdapter(),
        GroqAdapter(),
        OllamaAdapter(),
        MistralAdapter(),
        KimiAdapter(),
        ElevenLabsAdapter(),
        WindsurfAdapter(),
        ZedAdapter()
    ]) {
        self.allAdapters = adapters
    }
    
    public func scanAvailableProviders() async -> [AIProviderAdapter] {
        var available: [AIProviderAdapter] = []
        for adapter in allAdapters {
            if await adapter.checkAvailability() {
                available.append(adapter)
            }
        }
        return available
    }
}
