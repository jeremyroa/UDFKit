// MARK: - ReducerScope

/// Binds a child Reducer to a sub-state keyPath of the root State.
/// Action is intentionally absent — it is provided by ReducerDSL<State, Action> in buildBlock,
/// allowing the compiler to infer State and R without needing Action at the call site.
public struct ReducerScope<State: StoreState, R: Reducer> {
    let keyPath: WritableKeyPath<State, R.State>
    let reducer: R

    public init(
        _ keyPath: WritableKeyPath<State, R.State>,
        _ reducer: R
    ) {
        self.keyPath = keyPath
        self.reducer = reducer
    }
}

// MARK: - ReducerDSL

@resultBuilder
public struct ReducerDSL<State: StoreState, Action: StoreAction> {

    /// Converts a ReducerScope into a (State, Action) -> State closure.
    /// buildExpression processes one expression at a time — the compiler can infer
    /// State from ReducerScope<State, R> without ambiguity.
    /// Delegates to applyReducer — no duplicated unwrapping logic.
    public static func buildExpression<R: Reducer>(
        _ scope: ReducerScope<State, R>
    ) -> (State, Action) -> State where R.Action: StoreAction {
        let keyPath = scope.keyPath
        let reducer = scope.reducer
        return { state, action in
            applyReducer(state: state, action: action, keyPath: keyPath, reducer: reducer)
        }
    }

    /// Accumulates the closures produced by buildExpression into a BuilderReducer.
    /// Returns some Reducer<State, Action> — hides BuilderReducer behind an opaque type.
    public static func buildBlock(
        _ reducers: ((State, Action) -> State)...
    ) -> some Reducer<State, Action> {
        reducers.reduce(into: BuilderReducer<State, Action>()) { builder, reduce in
            builder = builder.registerBlock(reduce)
        }
    }
}
