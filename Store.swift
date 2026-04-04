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

    @MainActor
    public func dispatch(_ action: Action) async {
        apply(action)
        await intercept(action)
    }

    private func apply(_ action: Action) {
        state = reducer.reduce(oldState: state, with: action)
    }

    private func intercept(_ action: Action) async {
        await withTaskGroup(of: Action?.self) { group in
            for effect in effects {
                group.addTask { [state, dispatch] in
                    await effect.wrapped.process(state: state, with: action, dispatch: dispatch)
                }
            }

            for await case let nextAction? in group {
                await dispatch(nextAction)
            }
        }
    }
}

public extension Store {
    /**
     func environment() -> Binding<Store>
     - returns: A store as Binding to use as global state in your module or app with the modifier environment
     #Example
     public struct SomeStoreKey: EnvironmentKey {
      public static let defaultValue: Binding<SomeStore> = .constant(.default)
     }
     public extension EnvironmentValues {
      var someStore: Binding<SomeStore> {
        get { self[SomeStoreKey.self] }
        set { self[SomeStoreKey.self] = newValue }
      }
     }

     public struct ParentView: View {
      @StateObject var store: SomeStore
      var body: some View {
        ChildView()
        .environment(\.someStore, store.environment())
      }

      func onForceSkipped() {
        Task {
        await store.dispatch(.fetch)
        }
      }
     }

     struct ChildView: View {
      @Environment(\.productsEnabledStore) @Binding var store
      var body: some View {
        Text(store.someValue)
        .task {
          await store.dispatch(.fetch)
        }
      }
     }
     */
    func environment() -> Binding<Store> {
        .init {
            self
        } set: { newValue in
            self.state = newValue.state
        }
    }
}

public extension Store {
    /**
      func binding<Value>(
      _ path: WritableKeyPath<State, Value>,
      `set`: @escaping (Value) -> Action
      ) -> Binding<Value>
       - keyPath: indicate the value that you need with your state. ej: \.value
       - set: closure to indicate the action that modify the value in the state
       - returns: a Binding<Value> to handle in child view

     #Example
     public struct ParentView: View {
       @StateObject var store: SomeStore
        var body: some View {
         ChildView(
           value: store.binding(
             \.someBool,
             set: { value in
               return .toggleValue(value)
             }
           )
         )
        }
     }

     struct ChildView: View {
       @Binding var value: Bool
       var body: some View {
         Toggle("On", value)
       }
     }
     */
    func binding<Value>(
        _ keyPath: WritableKeyPath<State, Value>,
        set: @escaping (Value) -> Action
    ) -> Binding<Value> {
        .init(
            get: { self.state[keyPath: keyPath] },
            set: { newValue in
                let action = set(newValue)

                self.apply(action)

                Task {
                    await self.intercept(action)
                }
            }
        )
    }
}
