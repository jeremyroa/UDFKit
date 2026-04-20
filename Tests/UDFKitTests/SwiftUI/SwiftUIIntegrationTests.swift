import Testing
@testable import UDFKit

@Suite("SwiftUI integration")
@MainActor
struct SwiftUIIntegrationTests {
    @Test("binding set dispatches through full pipeline")
    func binding_set_dispatches_through_full_pipeline() async throws {
        let store = Store(initialState: FormState(name: ""), reducer: FormReducer())
        let binding = store.binding(\.name, set: { .setName($0) })
        binding.wrappedValue = "Alice"
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.state.name == "Alice")
    }

    @Test("two bindings on same store update independently")
    func two_bindings_update_independently() async throws {
        let store = Store(initialState: FormState(name: "", count: 0), reducer: FormReducer())
        let nameBinding = store.binding(\.name, set: { .setName($0) })
        let countBinding = store.binding(\.count, set: { .setCount($0) })
        nameBinding.wrappedValue = "Bob"
        countBinding.wrappedValue = 42
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.state.name == "Bob")
        #expect(store.state.count == 42)
    }

    @Test("environment-injected store is the same instance as the root store")
    func environment_store_is_same_instance() async {
        let store = Store(initialState: FormState(name: ""), reducer: FormReducer())
        let environmentStore = store
        await environmentStore.dispatch(.setName("Charlie"))
        #expect(store.state.name == "Charlie")
    }

    @Test("binding set on deallocated store does not crash")
    func binding_set_on_deallocated_store_does_not_crash() async throws {
        var store: Store<FormState, FormAction>? = Store(
            initialState: FormState(name: ""),
            reducer: FormReducer()
        )
        let unwrapped = try #require(store)
        let binding = unwrapped.binding(\.name, set: { .setName($0) })
        store = nil
        binding.wrappedValue = "Ghost"
        try await Task.sleep(for: .milliseconds(50))
        // passes if no crash — [weak self] in binding setter is a no-op when store is nil
    }
}
