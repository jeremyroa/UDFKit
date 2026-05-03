import Observation
import SwiftUI

@Observable
@MainActor
@dynamicMemberLookup
public final class Store<State: StoreState, Action: StoreAction> {
    public private(set) var state: State
    private let reducer: any Reducer<State, Action>
    private var effects: [any Effect<State, Action>] = []

    public init(
        initialState state: State,
        reducer: some Reducer<State, Action>,
        _ effects: (any Effect<State, Action>)...
    ) {
        self.state = state
        self.reducer = reducer
        self.effects = Array(effects)
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
        await withTaskGroup(of: Void.self) { group in
            for effect in effects {
                group.addTask { [weak self] in
                    let stream: AsyncStream<Action> = effect.process(state: currentState, with: action)
                    for await nextAction in stream {
                        await self?.dispatch(nextAction)
                    }
                }
            }
        }
    }
}

public extension Store {
    // nonisolated: Binding.get/set are synchronous non-isolated closures.
    // Safe: SwiftUI always invokes Binding on the main thread.
    nonisolated func binding<Value: Sendable>(
        _ keyPath: KeyPath<State, Value> & Sendable,
        set: @escaping @Sendable (Value) -> Action
    ) -> Binding<Value> {
        .init(
            get: {
                MainActor.assumeIsolated { self.state[keyPath: keyPath] }
            },
            set: { newValue in
                let action = set(newValue)
                MainActor.assumeIsolated { self.apply(action) }
                Task { @MainActor [weak self] in
                    await self?.intercept(action)
                }
            }
        )
    }
}
