/// Composable effect that dispatches an incoming action to all registered child effects
/// in parallel and merges their output streams into a single `AsyncStream<Action>`.
///
/// # Architecture
/// ```
/// Store.dispatch(action)
///     └─ BuilderEffects.process(state, action)
///             ├─ CounterEffect   → AsyncStream<CounterAction>  → re-wrapped → AsyncStream<Action>
///             ├─ ProfileEffect   → AsyncStream<ProfileAction>  → re-wrapped → AsyncStream<Action>
///             └─ AnalyticsEffect → AsyncStream<Action> (empty — analytics return nil)
/// ```
///
/// # Cancellation chain
/// When the Store's TaskGroup cancels the consumer `for await`:
/// ```
/// Store TaskGroup cancelled
///     └─ for await in outerStream stops
///     └─ outerStream.onTermination fires
///     └─ outerTask.cancel()
///     └─ withTaskGroup children cancelled  (structured concurrency)
///     └─ for await in subStream stops per runner
///     └─ subStream.onTermination fires per runner
///     └─ innerTask.cancel() per runner
/// ```
actor BuilderEffects<State: StoreState, Action: StoreAction>: Effect {
    /// @Sendable async closure built once at registration time by EffectsDSL.buildExpression.
    /// Receives full State + Action, returns a re-wrapped AsyncStream<Action>.
    private typealias ProcessFn = @Sendable (State, Action) async -> AsyncStream<Action>

    /// Type-erased wrapper for a registered child Effect.
    /// 3. `private` to the actor — never escapes the isolation domain.
    private struct BoxedEffect {
        let id: String
        let process: ProcessFn
    }

    // MARK: - State

    /// Keyed by `"\(EffectType)_\(keyPath)"` — prevents duplicate registrations.
    private var registeredEffects: [String: BoxedEffect]

    // MARK: - Init

    init() {
        registeredEffects = [:]
    }

    // MARK: - Registration

    /// DSL-only entry point — receives a pre-built ProcessFn from EffectsDSL.buildExpression.
    /// nonisolated: buildBlock is synchronous and cannot await into the actor directly.
    /// The actual storage crosses into the actor via Task { await self?.storeEffect(...) }.
    /// Duplicate registrations (same id) are silently ignored — idempotent.
    nonisolated func registerProcess(
        _ process: @escaping @Sendable (State, Action) async -> AsyncStream<Action>,
        id: String
    ) {
        let boxed = BoxedEffect(id: id, process: process)
        Task {
            [weak self] in await self?.storeEffect(boxed)
        }
    }

    private func storeEffect(_ boxed: BoxedEffect) {
        guard registeredEffects[boxed.id] == nil else {
            return
        }
        registeredEffects[boxed.id] = boxed
    }

    // MARK: - Effect

    /// Dispatches the action to all registered child effects in parallel and merges
    /// their output into a single `AsyncStream<Action>`.
    ///
    /// - All emitted actions from every child are forwarded — not just the first.
    /// - Analytics effects return empty streams — they don't generate new actions.
    /// - outerTask is tied to continuation.onTermination: if the Store's TaskGroup
    ///   cancels the consumer, the entire withTaskGroup and all its children are cancelled.
    /// - O(n) task-spawning overhead — suitable for ≤ 20 registered effects.
    func process(
        state: State,
        with action: Action
    ) async -> AsyncStream<Action> {
        // Capture registeredEffects before the AsyncStream closure (actor boundary).
        // Inside the closure we're no longer on the actor — capturing `self` would require await.
        let runners = Array(registeredEffects.values)

        return AsyncStream { continuation in
            let outerTask = Task {
                await withTaskGroup(of: Void.self) { group in
                    for runner in runners {
                        group.addTask {
                            // Each runner returns its own AsyncStream<Action> (already re-wrapped).
                            // We consume it and forward every result to the merged continuation.
                            let subStream = await runner.process(state, action)
                            for await result in subStream {
                                continuation.yield(result)
                            }
                        }
                    }
                    // withTaskGroup waits for all children before returning.
                }
                continuation.finish()
            }
            // When the Store stops consuming this stream (TaskGroup cancelled, Store deallocated),
            // the outerTask is cancelled — which propagates into withTaskGroup and all its children.
            continuation.onTermination = {
                _ in outerTask.cancel()
            }
        }
    }
}
