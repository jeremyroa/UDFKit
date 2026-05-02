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

    @Test("binding set updates state synchronously")
    func binding_updates_state_synchronously() {
        let sut = makeSUT()
        let storeBinding = sut.binding(\.someValue, set: { .changeSomeValue($0) })
        storeBinding.wrappedValue = true

        #expect(sut.someValue)
        #expect(storeBinding.wrappedValue)
    }

    @Test("binding state update does not wait for slow effects")
    func binding_stateUpdates_beforeEffectCompletes() {
        let sut = Store(
            initialState: CounterState(count: 0),
            reducer: CounterReducer(),
            AnyEffect(SlowEffect())
        )
        let storeBinding = sut.binding(\.count, set: { _ in .increment })

        storeBinding.wrappedValue = 1

        #expect(sut.state.count == 1)
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
