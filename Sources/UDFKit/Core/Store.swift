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
        _ effects: any Effect<State, Action>...
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

    func apply(_ action: Action) {
        state = reducer.reduce(oldState: state, with: action)
    }

    /// Runs all registered effects in parallel for the given action.
    /// Each effect returns an AsyncStream — the Store consumes it via `for await`,
    /// dispatching every emitted action back through the full dispatch cycle.
    private func intercept(_ action: Action) async {
        let currentState = state
        await withTaskGroup(of: Void.self) { group in
            for effect in effects {
                group.addTask { [weak self] in
                    // Explicit type resolves the process() overload unambiguously.
                    // [weak self]: if Store deallocates mid-effect the loop exits silently.
                    let stream: AsyncStream<Action> = await effect.process(
                        state: currentState,
                        with: action
                    )
                    for await nextAction in stream {
                        await self?.dispatch(nextAction)
                    }
                }
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
                self.applyAndIntercept(set(newValue))
            }
        )
    }

    private nonisolated func applyAndIntercept(_ action: Action) {
        // apply is synchronous — UI updates in the same run loop cycle.
        MainActor.assumeIsolated {
            self.apply(action)
        }
        // intercept is async — effects run after state is already visible.
        Task { @MainActor [weak self] in
            await self?.intercept(action)
        }
    }
}
