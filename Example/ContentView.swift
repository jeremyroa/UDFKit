import SwiftUI
import UDFKit

struct ContentView: View {
    @State private var store = Store(
        initialState: ExampleFormState(),
        reducer: ExampleFormReducer()
    )

    var body: some View {
        NavigationStack {
            FormView()
                .environment(\.formStore, store)
                .navigationTitle("UDFKit Example")
        }
    }
}

struct FormView: View {
    @Environment(\.formStore) private var store

    var body: some View {
        guard let store else { return AnyView(Text("No store in environment")) }
        return AnyView(FormContentView(store: store))
    }
}

struct FormContentView: View {
    let store: Store<ExampleFormState, ExampleFormAction>

    var body: some View {
        Form {
            Section("Name") {
                TextField("Enter name", text: store.binding(\.name, set: { .setName($0) }))
            }
            Section("Count") {
                Stepper(
                    "Count: \(store.count)",
                    onIncrement: { Task { await store.dispatch(.setCount(store.count + 1)) } },
                    onDecrement: { Task { await store.dispatch(.setCount(store.count - 1)) } }
                )
            }
            Section {
                Button("Reset") { Task { await store.dispatch(.reset) } }
                    .foregroundStyle(.red)
            }
        }
    }
}
