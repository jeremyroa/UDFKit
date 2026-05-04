/// Single implementation of sub-state reducer application logic.
/// Used by both BuilderReducer.registerReducer and ReducerDSL.buildExpression.
/// One place to maintain — zero duplication.
func applyReducer<State: StoreState, Action: StoreAction, R: Reducer>(
    state: State,
    action: Action,
    keyPath: WritableKeyPath<State, R.State>,
    reducer: R
) -> State where R.Action: StoreAction {
    // Extract sub-action (with or without StoreActionWrapper)
    let subAction: R.Action? = switch action {
    case let w as any StoreActionWrapper: w.unwrapAs()
    case let d as R.Action:               d
    default:                              nil
    }
    guard let subAction else { return state }
    // Apply the reducer to the sub-state
    var newState = state
    newState[keyPath: keyPath] = reducer.reduce(
        oldState: state[keyPath: keyPath],
        with: subAction
    )
    return newState
}

/// Single implementation of sub-state effect application logic.
/// Used by both BuilderEffects.makeBoxedEffect and EffectsDSL.buildExpression.
/// One place to maintain — zero duplication.
///
/// Handles:
/// 1. StoreActionWrapper detection
/// 2. Sub-action extraction
/// 3. Effect invocation via extractSubState
/// 4. Result re-wrapping into the parent Action type
/// 5. Cancellation via onTermination
func applyEffect<State: StoreState, Action: StoreAction, E: Effect>(
    state: State,
    action: Action,
    extractSubState: @Sendable (State) -> E.State,
    effect: E
) async -> AsyncStream<Action> where E.Action: StoreAction {
    // Detect wrapper type — needed to re-wrap the result
    let mainWrapperType = action is any StoreActionWrapper ? type(of: action) : nil
    // Extract sub-action
    let subAction: E.Action? = switch action {
    case let w as any StoreActionWrapper:
        w.unwrapAs()
    case let d as E.Action:
        d
    default:
        nil
    }
    guard let subAction else { return .finished }
    // Call the effect with the extracted sub-state
    let subStream: AsyncStream<E.Action> = await effect.process(
        state: extractSubState(state),
        with: subAction
    )
    // Re-wrap each result into the parent Action type and forward
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
        continuation.onTermination = { _ in innerTask.cancel() }
    }
}
