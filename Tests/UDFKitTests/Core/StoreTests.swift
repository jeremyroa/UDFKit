import Testing
@testable import UDFKit

@Suite("Store")
struct StoreTests {
    private func makeSUT() -> Store<StateMock, ActionMock> {
        Store(
            initialState: StateMock(someValue: false, asyncValue: []),
            reducer: MockReducer()
        )
    }

    @Test("environment binding propagates state bidirectionally")
    func environment_propagates_state_bidirectionally() async {
        let sut = makeSUT()
        let storeEnv = sut.environment()
        await storeEnv.wrappedValue.dispatch(.changeSomeValue(true))
        #expect(sut.someValue)
        #expect(storeEnv.wrappedValue.someValue)
    }

    @Test("binding calls setter and updates state when value toggles")
    func binding_updates_state_and_calls_setter() async {
        let sut = makeSUT()
        var setCalled = false

        let storeBinding = sut.binding(
            \.someValue,
            set: { someValue in
                setCalled = true
                return .changeSomeValue(someValue)
            }
        )

        storeBinding.wrappedValue.toggle()

        // Wait briefly for the internal Task dispatch to complete
        try? await Task.sleep(for: .milliseconds(100))

        #expect(sut.someValue)
        #expect(storeBinding.wrappedValue)
        #expect(setCalled)
    }

    @Test("dispatch applies reducer then runs effects")
    func dispatch_applies_reducer_then_effects() async {
        let sut = makeSUT()
        await sut.dispatch(.changeSomeValue(true))
        #expect(sut.someValue)
    }
}
