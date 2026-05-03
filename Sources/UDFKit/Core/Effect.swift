/// - Important: Implement at least one `process` overload.
///   Implementing neither causes a stack overflow on the first dispatch.
///   - Use `async -> Action?` for effects that emit at most one follow-up action.
///   - Use `-> AsyncStream<Action>` for effects that emit zero or many follow-up actions.
public protocol Effect<State, Action>: Sendable {
    associatedtype State: StoreState
    associatedtype Action: StoreAction

    func process(state: State, with action: Action) async -> Action?
    func process(state: State, with action: Action) -> AsyncStream<Action>
}

public extension Effect {
    // Store path — wraps the single-action result, cancellation-safe.
    // Delegates to `async -> Action?` if not overridden.
    func process(state: State, with action: Action) -> AsyncStream<Action> {
        let (stream, continuation) = AsyncStream.makeStream(of: Action.self)
        let task = Task {
            let result: Action? = await self.process(state: state, with: action)
            if let result { continuation.yield(result) }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    // Caller/test convenience — returns the first action from the stream.
    // Never called by the store.
    func process(state: State, with action: Action) async -> Action? {
        let stream: AsyncStream<Action> = self.process(state: state, with: action)
        return await stream.first(where: { _ in true })
    }
}
