/// Composable reducer that delegates sub-state handling to registered child reducers.
public struct BuilderReducer<State: StoreState, Action: StoreAction>: Reducer {
    private typealias ReducerFunction = (State, Action) -> State
    private struct ReducerRegistration {
        let identifier: String
        let reduce: ReducerFunction

        init<R: Reducer>(
            reducer: R,
            keyPath: WritableKeyPath<State, R.State>
        ) where R.Action: StoreAction {
            identifier = "\(type(of: R.self))_\(keyPath)"
            reduce = { state, action in
                var newState = state
                var subState = state[keyPath: keyPath]
                switch action {
                case let wrappedAction as any StoreActionWrapper:
                    if let unwrappedAction = wrappedAction.unwrapAs() as R.Action? {
                        subState = reducer.reduce(oldState: subState, with: unwrappedAction)
                        newState[keyPath: keyPath] = subState
                        return newState
                    }
                case let directAction as R.Action:
                    subState = reducer.reduce(oldState: subState, with: directAction)
                    newState[keyPath: keyPath] = subState
                    return newState
                default:
                    return state
                }
                return state
            }
        }
    }

    private let reducerRegistrations: [String: ReducerRegistration]

    public init() {
        reducerRegistrations = [:]
    }

    private init(registrations: [String: ReducerRegistration]) {
        reducerRegistrations = registrations
    }

    /// Registers a child reducer scoped to a sub-state keyPath.
    /// Returns a new `BuilderReducer` with the registration added.
    public func registerReducer<R: Reducer>(
        _ keyPath: WritableKeyPath<State, R.State>,
        _ reducer: R
    ) -> Self where R.Action: StoreAction {
        let registration = ReducerRegistration(reducer: reducer, keyPath: keyPath)

        var newRegistrations = reducerRegistrations
        newRegistrations[registration.identifier] = registration

        return BuilderReducer(registrations: newRegistrations)
    }

    /// O(n) where n = registered reducer count; suitable for ≤ 50 sub-reducers
    public func reduce(oldState: State, with action: Action) -> State {
        processReducers(state: oldState, action: action)
    }

    private func processReducers(state: State, action: Action) -> State {
        reducerRegistrations.values.reduce(state) { currentState, registration in
            registration.reduce(currentState, action)
        }
    }
}
