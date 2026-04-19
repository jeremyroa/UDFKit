import Foundation

public struct AnyEffect<State: StoreState, Action: StoreAction>: Sendable {
    let wrapped: any Effect<State, Action>

    public static func createEffect(_ wrapped: any Effect<State, Action>) -> Self {
        .init(wrapped: wrapped)
    }
}

public protocol Effect<State, Action>: Sendable {
    associatedtype State: StoreState
    associatedtype Action: StoreAction

    func process(state: State, with action: Action) async -> Action?

    func process(
        state: State,
        with action: Action,
        dispatch: (@Sendable (Action) async -> Void)?
    ) async -> Action?
}

public extension Effect {
    func process(
        state: State,
        with action: Action,
        dispatch _: (@Sendable (Action) async -> Void)?
    ) async -> Action? {
        await process(state: state, with: action)
    }

    func process(state: State, with action: Action) async -> Action? {
        await process(state: state, with: action, dispatch: nil)
    }
}
