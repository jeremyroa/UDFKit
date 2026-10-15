import Foundation

public protocol Effect<State, Action>: Sendable {
    associatedtype State: StoreState
    associatedtype Action: StoreAction

    // Stream variant — Store always calls this.
    // Long-running effects (WebSocket, timers) override this directly.
    func process(state: State, with action: Action) async -> AsyncStream<Action>

    // One-shot variant — simple effects override this instead
    // The stream variant's default implementation bridges here automatically
    func process(state: State, with action: Action) async -> Action?
}

public extension Effect {
    // Default stream bridges to the optional Action variant
    // Effects that only need to return one action override process(...) -> Action? and never touch this
    func process(state: State, with action: Action) async -> AsyncStream<Action> {
        let result: Action? = await process(state: state, with: action)
        return AsyncStream { continuation in
            if let action = result { continuation.yield(action) }
            continuation.finish()
        }
    }

    // Default one-shot: ignore the action
    func process(state: State, with action: Action) async -> Action? { nil }
}

public extension AsyncStream {
    // Convenience — effects that emit nothing for a given action
    static var finished: AsyncStream { .init { $0.finish() } }
}
