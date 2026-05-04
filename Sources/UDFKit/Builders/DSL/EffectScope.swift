// MARK: - EffectScope

/// Binds a child Effect to a sub-state keyPath of the root State.
/// Action is intentionally absent — it is provided by EffectsDSL<State, Action> in buildBlock.
///
/// The keyPath is captured as a @Sendable closure (extractSubState) in the init,
/// where the & Sendable constraint exists. This sidesteps the Swift limitation
/// that & Sendable cannot be stored as a property type.
public struct EffectScope<State: StoreState, E: Effect>: Sendable where E.Action: StoreAction {

    /// Captures the keyPath (with & Sendable from init) as a @Sendable closure.
    let extractSubState: @Sendable (State) -> E.State
    let effect: E

    public init(
        _ keyPath: KeyPath<State, E.State> & Sendable,
        _ effect: E
    ) {
        // keyPath has & Sendable here — captured safely into a @Sendable closure
        self.extractSubState = { $0[keyPath: keyPath] }
        self.effect = effect
    }
}

// MARK: - EffectsDSL

@resultBuilder
public struct EffectsDSL<State: StoreState, Action: StoreAction> {

    /// Converts an EffectScope into a @Sendable (State, Action) async -> AsyncStream<Action>.
    /// buildExpression processes one expression at a time — type inference works correctly.
    /// Delegates to applyEffect — no duplicated unwrapping/rewrapping logic.
    /// scope is Sendable (extractSubState: @Sendable + effect: E: Sendable) — safe to capture. 
    public static func buildExpression<E: Effect>(
        _ scope: EffectScope<State, E>
    ) -> @Sendable (State, Action) async -> AsyncStream<Action>
    where E.Action: StoreAction {
        { state, action in
            await applyEffect(
                state: state,
                action: action,
                extractSubState: scope.extractSubState,
                effect: scope.effect
            )
        }
    }

    /// Accumulates the closures produced by buildExpression into a BuilderEffects.
    /// Returns some Effect<State, Action> — hides BuilderEffects behind an opaque type. ✅
    public static func buildBlock(
        _ processes: (@Sendable (State, Action) async -> AsyncStream<Action>)...
    ) -> some Effect<State, Action> {
        let builder = BuilderEffects<State, Action>()
        for (index, process) in processes.enumerated() {
            builder.registerProcess(process, id: "\(index)")
        }
        return builder
    }
}
