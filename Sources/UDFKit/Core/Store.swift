import Observation
import SwiftUI

@Observable
@MainActor
@dynamicMemberLookup
public final class Store<State: StoreState, Action: StoreAction> {
    public private(set) var state: State
    private let reducer: any Reducer<State, Action>
    private var effects: [AnyEffect<State, Action>] = []

    public init(
        initialState state: State,
        reducer: some Reducer<State, Action>,
        _ effects: AnyEffect<State, Action>...
    ) {
        self.state = state
        self.reducer = reducer
        self.effects = effects
    }

    public subscript<T>(dynamicMember keyPath: KeyPath<State, T>) -> T {
        state[keyPath: keyPath]
    }

    public func dispatch(_ action: Action) async {
        apply(action)
        await intercept(action)
    }

    private func apply(_ action: Action) {
        state = reducer.reduce(oldState: state, with: action)
    }

    private func intercept(_ action: Action) async {
        let currentState = state
        await withTaskGroup(of: Action?.self) { group in
            for effect in effects {
                group.addTask { [weak self] in
                    // [weak self]: if Store deallocates mid-effect the dispatcher silently no-ops
                    let dispatcher: @Sendable (Action) async -> Void = { [weak self] in
                        await self?.dispatch($0)
                    }
                    return await effect.wrapped.process(
                        state: currentState,
                        with: action,
                        dispatch: dispatcher
                    )
                }
            }
            for await case let nextAction? in group {
                await dispatch(nextAction)
            }
        }
    }
}

public extension Store {
    // nonisolated because Binding.get/set are synchronous non-isolated closures.
    // Safe: SwiftUI always invokes Binding.get/set on the main thread.
    nonisolated func binding<Value: Sendable>(
        _ keyPath: KeyPath<State, Value> & Sendable,
        set: @escaping @Sendable (Value) -> Action
    ) -> Binding<Value> {
        .init(
            get: { MainActor.assumeIsolated { self.state[keyPath: keyPath] } },
            set: { newValue in
                Task { @MainActor [weak self] in
                    await self?.dispatch(set(newValue))
                }
            }
        )
    }
}
