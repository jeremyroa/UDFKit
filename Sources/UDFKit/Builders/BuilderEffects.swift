/// Composable effect that dispatches an incoming action to all registered child effects
/// in parallel and merges their output streams into a single `AsyncStream<Action>`.
///
/// # Architecture
/// ```
/// Store.dispatch(action)
///     └─ BuilderEffects.process(state, action)
///             ├─ BannersEffect   → AsyncStream<BannersAction>  → re-wrapped → AsyncStream<Action>
///             ├─ MovementsEffect → AsyncStream<MovementsAction> → re-wrapped → AsyncStream<Action>
///             └─ AnalyticsEffect → AsyncStream<Action> (empty — analytics return nil)
/// ```
///
/// # Cancellation chain
/// When the Store's TaskGroup cancels the consumer `for await`:
/// ```
/// Store TaskGroup cancelled
///     └─ for await in outerStream stops              (consumer gone)
///     └─ outerStream.onTermination fires             (AsyncStream detects no consumer)
///     └─ outerTask.cancel()                          (outer Task dies)
///     └─ withTaskGroup children cancelled            (structured concurrency)
///     └─ for await in subStream stops per runner
///     └─ subStream.onTermination fires per runner    (inner level)
///     └─ innerTask.cancel() per runner               (inner Task dies)
/// ```
public actor BuilderEffects<State: StoreState, Action: StoreAction>: Effect {

    // MARK: - Types

    /// @Sendable async closure that receives the full State + Action and returns
    /// a re-wrapped `AsyncStream<Action>` ready for the Store's dispatch cycle.
    /// Built once at registration time — captures the Effect and keyPath.
    private typealias ProcessFn = @Sendable (State, Action) async -> AsyncStream<Action>

    /// Type-erased wrapper for a registered child Effect.
    ///
    /// `@unchecked Sendable` — 3 checks pass:
    /// 1. `id` and `process` are `let` — no mutation after creation.
    /// 2. `process` is `@Sendable` — already thread-safe by declaration.
    /// 3. `private` to the actor — never escapes the isolation domain.
    private struct BoxedEffect: @unchecked Sendable {
        let id: String
        let process: ProcessFn
    }

    // MARK: - State

    /// Keyed by `"\(EffectType)_\(keyPath)"` — prevents duplicate registrations.
    private var registeredEffects: [String: BoxedEffect]

    // MARK: - Init

    public init() {
        registeredEffects = [:]
    }

    // MARK: - Registration

    /// Registers a child effect scoped to a sub-state keyPath.
    ///
    /// - `nonisolated`: callable synchronously from DI setup (e.g. Swinject) without `await`.
    ///   The real work crosses into the actor via `Task { await self?.storeEffect(...) }`.
    /// - `KeyPath & Sendable`: lets the compiler verify the keyPath capture inside
    ///   the `@Sendable ProcessFn` closure is safe at the call site.
    /// - Duplicate registrations (same type + keyPath) are silently ignored — idempotent.
    /// - `@discardableResult` enables fluent chaining: `.registerEffect(...).registerEffect(...)`.
    @discardableResult
    public nonisolated func registerEffect<E: Effect>(
        _ keyPath: KeyPath<State, E.State> & Sendable,
        _ effect: E
    ) -> Self where E.Action: StoreAction {
        // BoxedEffect is built here (nonisolated) so only the @unchecked Sendable struct
        // crosses the actor boundary — not the raw Effect or keyPath directly.
        let boxed = Self.makeBoxedEffect(effect: effect, keyPath: keyPath)
        Task { [weak self] in
            await self?.storeEffect(boxed)
        }
        return self
    }

    /// Converts a concrete `Effect<SubState, SubAction>` into a `BoxedEffect` whose
    /// `ProcessFn` speaks the parent `(State, Action)` language.
    ///
    /// Steps inside the closure (executed per dispatch):
    /// 1. Detect if the action is a wrapper (e.g. `HomeAction.banners`).
    /// 2. Extract the sub-action the child Effect understands (`BannersAction`).
    /// 3. Call the child Effect — get back `AsyncStream<E.Action>`.
    /// 4. Re-wrap each emitted sub-action into the parent `Action` type before yielding.
    ///    Cancellation: `innerTask` is tied to `continuation.onTermination` so it dies
    ///    when the outer consumer stops iterating.
    private nonisolated static func makeBoxedEffect<E: Effect>(
        effect: E,
        keyPath: KeyPath<State, E.State> & Sendable
    ) -> BoxedEffect where E.Action: StoreAction {
        BoxedEffect(id: "\(type(of: effect))_\(keyPath)") {
            state,
            action in
            
            // Step 1 — detect wrapper (e.g. HomeAction wrapping BannersAction)
            // Computed here — no metatype captured outside the closure.
            let mainWrapperType = action is any StoreActionWrapper ? type(of: action) : nil
            
            // Step 2 — extract the sub-action for this child Effect
            let subAction: E.Action? = switch action {
            case let wrapped as any StoreActionWrapper: wrapped.unwrapAs()
            case let direct as E.Action:                direct
            default:                                    nil
            }
            
            guard let subAction else {
                return .finished
            }
            
            // Step 3 — call the child Effect
            // Explicit type annotation resolves the process() overload unambiguously.
            let subStream: AsyncStream<E.Action> = await effect.process(
                state: state[keyPath: keyPath],
                with: subAction
            )
            
            // Step 4 — re-wrap and forward each sub-action to the parent stream.
            // innerTask is cancelled via onTermination when the outer consumer stops.
            return AsyncStream { continuation in
                let innerTask = Task {
                    for await result in subStream {
                        let wrapped: Action? = if let wt = mainWrapperType as? any StoreActionWrapper.Type {
                            wt.wrap(result) as? Action
                        } else {
                            result as? Action
                        }
                        if let wrapped { continuation.yield(wrapped) }
                    }
                    continuation.finish()
                }
                // When the outer consumer (BuilderEffects.process) stops iterating,
                // the inner Task dies — no orphaned Task left running.
                continuation.onTermination = {
                    _ in innerTask.cancel()
                }
            }
        }
    }

    /// Stores a `BoxedEffect` — called from within the actor so access is serialized.
    /// Guard prevents double registration if `registerEffect` is called twice for the same effect.
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
    /// - `outerTask` is tied to `continuation.onTermination`: if the Store's TaskGroup
    ///   cancels the consumer, the entire `withTaskGroup` and all its children are cancelled.
    /// - O(n) task-spawning overhead — suitable for ≤ 20 registered effects.
    public func process(
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
