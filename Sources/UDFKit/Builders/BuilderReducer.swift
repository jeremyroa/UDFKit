import Foundation
/// Composable reducer that delegates sub-state handling to registered child reducers.
/// Internal — used by ReducerDSL.buildBlock. Not part of the public API.
struct BuilderReducer<State: StoreState, Action: StoreAction>: Reducer {
    private typealias ReducerFunction = (State, Action) -> State

    /// Plain container — holds only an identifier and a pre-built reduce closure.
    /// All unwrapping/apply logic lives in applyReducer (called from ReducerDSL.buildExpression).
    private struct ReducerRegistration {
        let identifier: String
        let reduce: ReducerFunction
    }

    private let reducerRegistrations: [String: ReducerRegistration]

    init() {
        reducerRegistrations = [:]
    }

    private init(registrations: [String: ReducerRegistration]) {
        reducerRegistrations = registrations
    }

    /// DSL-only entry point — receives a pre-built closure from ReducerDSL.buildExpression.
    func registerBlock(_ reduce: @escaping (State, Action) -> State) -> Self {
        let id = UUID().uuidString
        var regs = reducerRegistrations
        regs[id] = ReducerRegistration(identifier: id, reduce: reduce)
        return BuilderReducer(registrations: regs)
    }

    /// O(n) where n = registered reducer count; suitable for ≤ 50 sub-reducers.
    func reduce(oldState: State, with action: Action) -> State {
        reducerRegistrations.values.reduce(oldState) { currentState, registration in
            registration.reduce(currentState, action)
        }
    }
}
