import SwiftUI

@dynamicMemberLookup
public class Store<State: StoreState, Action: StoreAction>: ObservableObject {
    @Published private var state: State
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

    /// Dispatches an action to the reducer and runs all registered effects.
    @MainActor
    public func dispatch(_ action: Action) async {
        apply(action)
        await intercept(action)
    }

    private func apply(_ action: Action) {
        state = reducer.reduce(oldState: state, with: action)
    }

    @MainActor
    private func intercept(_ action: Action) async {
        let currentState = state
        await withTaskGroup(of: Action?.self) { group in
            for effect in effects {
                group.addTask { [weak self] in
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

extension Store: @unchecked Sendable {}

public extension Store {
    /// Returns a `Binding<Store>` for use as a global shared state via SwiftUI environment.
    func environment() -> Binding<Store> {
        .init {
            self
        } set: { [weak self] newValue in
            self?.state = newValue.state
        }
    }
}

public extension Store {
    /// Creates a two-way `Binding<Value>` that dispatches an action when the value changes.
    func binding<Value>(
        _ keyPath: WritableKeyPath<State, Value>,
        set: @escaping (Value) -> Action
    ) -> Binding<Value> {
        .init(
            get: { self.state[keyPath: keyPath] },
            set: { [weak self] newValue in
                guard let self else { return }
                let action = set(newValue)
                self.apply(action)
                Task { @MainActor in
                    await self.intercept(action)
                }
            }
        )
    }
}
