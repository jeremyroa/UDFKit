/// Composable effect that runs multiple registered child effects in parallel.
public actor BuilderEffects<State: StoreState, Action: StoreAction>: Effect {
    private typealias ProcessFn = @Sendable (State, Action) -> AsyncStream<Action>

    /// @unchecked Sendable: the closure is @Sendable and captures only Sendable values
    /// (concrete Effect + immutable KeyPath). Actor isolation ensures exclusive access during storage.
    private struct BoxedEffect: @unchecked Sendable {
        let id: String
        let process: ProcessFn
    }

    private var registeredEffects: [String: BoxedEffect]

    public init() {
        registeredEffects = [:]
    }

    /// Registers a child effect scoped to a sub-state keyPath.
    /// Duplicate registrations (same type + keyPath) are ignored.
    /// Returns `self` to enable fluent chaining.
    @discardableResult
    public nonisolated func registerEffect<E: Effect>(
        _ keyPath: KeyPath<State, E.State>,
        _ effect: E
    ) -> Self where E.Action: StoreAction {
        let boxed = Self.makeBoxedEffect(effect: effect, keyPath: keyPath)
        Task { [weak self] in
            await self?.storeEffect(boxed)
        }
        return self
    }

    private nonisolated static func makeBoxedEffect<E: Effect>(
        effect: E,
        keyPath: KeyPath<State, E.State>
    ) -> BoxedEffect where E.Action: StoreAction {
        BoxedEffect(id: "\(type(of: effect))_\(keyPath)") { state, action in
            let mainWrapperType = action is any StoreActionWrapper ? type(of: action) : nil

            let subAction: E.Action? = switch action {
            case let wrapped as any StoreActionWrapper: wrapped.unwrapAs()
            case let direct as E.Action: direct
            default: nil
            }

            guard let subAction else {
                return AsyncStream { $0.finish() }
            }

            let subStream: AsyncStream<E.Action> = effect.process(
                state: state[keyPath: keyPath],
                with: subAction
            )

            let (stream, continuation) = AsyncStream.makeStream(of: Action.self)
            let task = Task {
                for await subEffectAction in subStream {
                    let wrappedAction: Action?
                    if let wrapperType = mainWrapperType as? any StoreActionWrapper.Type {
                        wrappedAction = wrapperType.wrap(subEffectAction) as? Action
                    } else {
                        wrappedAction = subEffectAction as? Action
                    }
                    if let wrapped = wrappedAction { continuation.yield(wrapped) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
            return stream
        }
    }

    private func storeEffect(_ boxed: BoxedEffect) {
        guard registeredEffects[boxed.id] == nil else { return }
        registeredEffects[boxed.id] = boxed
    }

    /// Merges all child effect streams; yields every action emitted by any child.
    public nonisolated func process(state: State, with action: Action) -> AsyncStream<Action> {
        let (stream, continuation) = AsyncStream.makeStream(of: Action.self)
        let task = Task { [weak self] in
            guard let self else {
                continuation.finish()
                return
            }
            let runners = await self.getRunners()
            await withTaskGroup(of: Void.self) { group in
                for runner in runners {
                    group.addTask {
                        let subStream = runner.process(state, action)
                        for await nextAction in subStream {
                            continuation.yield(nextAction)
                        }
                    }
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func getRunners() -> [BoxedEffect] {
        Array(registeredEffects.values)
    }

    // Stub: the store always calls the stream overload above.
    public func process(state: State, with action: Action) async -> Action? { nil }
}
