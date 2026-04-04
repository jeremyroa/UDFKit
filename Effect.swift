import Foundation

public struct AnyEffect<State: StoreState, Action: StoreAction> {
    let wrapped: any Effect<State, Action>

    public static func createEffect(_ wrapped: any Effect<State, Action>) -> Self {
        .init(wrapped: wrapped)
    }
}

public protocol Effect<State, Action> {
    associatedtype State: StoreState
    associatedtype Action: StoreAction

    func process(state: State, with action: Action) async -> Action?

    func process(state: State, with action: Action, dispatch: ((Action) async -> Void)?) async -> Action?
}

public extension Effect {
    func process(state: State, with action: Action, dispatch _: ((Action) async -> Void)?) async -> Action? {
        await process(state: state, with: action)
    }

    func process(state: State, with action: Action) async -> Action? {
        await process(state: state, with: action, dispatch: nil)
    }
}
