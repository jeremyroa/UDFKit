/// Composable effect that runs multiple registered child effects in parallel.
public actor BuilderEffects<State: StoreState, Action: StoreAction>: Effect {
    private typealias DispatchFn = (@Sendable (Action) async -> Void)?
    private typealias ProcessFn = (State, Action, DispatchFn) async -> Action?

    /// @unchecked Sendable: the closure captures a concrete Effect (Sendable) and an immutable
    /// KeyPath (value type). Actor isolation ensures exclusive access during storage.
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
    public nonisolated func registerEffect<E: Effect>(
        _ keyPath: KeyPath<State, E.State>,
        _ effect: E
    ) where E.Action: StoreAction {
        // Build the boxed effect here (nonisolated) so only the @unchecked Sendable
        // BoxedEffect crosses the actor boundary — not the raw keyPath.
        let boxed = Self.makeBoxedEffect(effect: effect, keyPath: keyPath)
        // Fire-and-forget Task: no handle, cannot be cancelled. Safe because
        // storeEffect is idempotent (duplicate IDs are ignored) and BoxedEffect
        // is value-typed — losing the task only skips registration, never corrupts state.
        Task { [weak self] in
            await self?.storeEffect(boxed)
        }
    }

    private nonisolated static func makeBoxedEffect<E: Effect>(
        effect: E,
        keyPath: KeyPath<State, E.State>
    ) -> BoxedEffect where E.Action: StoreAction {
        BoxedEffect(id: "\(type(of: effect))_\(keyPath)") { state, action, mainDispatch in
            let mainWrapperType = action is any StoreActionWrapper ? type(of: action) : nil

            let subAction: E.Action? = switch action {
            case let wrapped as any StoreActionWrapper: wrapped.unwrapAs()
            case let direct as E.Action: direct
            default: nil
            }

            guard let subAction else { return nil }

            let subDispatch: (@Sendable (E.Action) async -> Void)? = if let mainDispatch {
                { @Sendable [mainWrapperType] subEffectAction in
                    let wrapped: Action? = if let wrapperType = mainWrapperType as? any StoreActionWrapper.Type {
                        wrapperType.wrap(subEffectAction) as? Action
                    } else {
                        subEffectAction as? Action
                    }
                    if let wrapped { await mainDispatch(wrapped) }
                }
            } else {
                nil
            }

            let result = await effect.process(
                state: state[keyPath: keyPath],
                with: subAction,
                dispatch: subDispatch
            )

            guard let result else { return nil }

            if let wrapperType = mainWrapperType as? any StoreActionWrapper.Type {
                return wrapperType.wrap(result) as? Action
            }
            return result as? Action
        }
    }

    private func storeEffect(_ boxed: BoxedEffect) {
        guard registeredEffects[boxed.id] == nil else { return }
        registeredEffects[boxed.id] = boxed
    }

    public func process(
        state: State,
        with action: Action,
        dispatch: (@Sendable (Action) async -> Void)?
    ) async -> Action? {
        await withTaskGroup(of: Action?.self) { group in
            for runner in registeredEffects.values {
                group.addTask {
                    await runner.process(state, action, dispatch)
                }
            }
            for await result in group {
                if let action = result { return action }
            }
            return nil
        }
    }
}
