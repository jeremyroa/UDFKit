import Testing
@testable import UDFKit

@Suite("Store")
@MainActor
struct StoreTests {
    private func makeSUT() -> Store<StateMock, ActionMock> {
        Store(
            initialState: StateMock(someValue: false, asyncValue: []),
            reducer: MockReducer()
        )
    }

    @Test("dispatch applies reducer then runs effects")
    func dispatch_applies_reducer_then_effects() async {
        let sut = makeSUT()
        await sut.dispatch(.changeSomeValue(true))
        #expect(sut.someValue)
    }

    @Test("binding set dispatches action and updates state")
    func binding_updates_state_via_dispatch() async throws {
        let sut = makeSUT()
        let storeBinding = sut.binding(\.someValue, set: { .changeSomeValue($0) })
        storeBinding.wrappedValue = true
        try await Task.sleep(for: .milliseconds(100))
        #expect(sut.someValue)
        #expect(storeBinding.wrappedValue)
    }

    @Test("binding dispatches action through full pipeline")
    func binding_routes_through_dispatch_pipeline() async throws {
        let sut = makeSUT()
        let binding = sut.binding(\.someValue, set: { .changeSomeValue($0) })
        binding.wrappedValue = true
        try await Task.sleep(for: .milliseconds(50))
        #expect(sut.state.someValue)
    }

    @Test("concurrent dispatch converges to correct final state")
    func concurrentDispatch_convergesToCorrectFinalState() async {
        let store = Store(initialState: CounterState(count: 0), reducer: CounterReducer())
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask { await store.dispatch(.increment) }
            }
        }
        #expect(store.state.count == 100)
    }

    @Test("dispatching to deallocated store does not crash")
    func deallocatedStore_dispatchDoesNotCrash() async {
        var store: Store<CounterState, CounterActions>? = Store(
            initialState: CounterState(count: 0),
            reducer: CounterReducer(),
            AnyEffect(SlowEffect())
        )
        weak let weakStore = store
        store = nil
        await weakStore?.dispatch(.increment)
        // passes if no crash — weak reference becomes nil and dispatch is a no-op
    }
}
