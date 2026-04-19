import XCTest
@testable import UDFLibrary

final class StoreTests: XCTestCase {

    var sut: Store<StateMock, ActionMock>!

    override func setUpWithError() throws {
        sut = .init(
            initialState: .init(someValue: false, asyncValue: []),
            reducer: MockReducer()
        )
    }

    override func tearDownWithError() throws {
        sut = nil
    }

    func test_environment_when_state_isFalse_and_Action_is_changeSomeValueHasTrue_SomeValueShouldBeTrue() async throws {
        let storeEnv = sut.environment()
        await storeEnv.wrappedValue.dispatch(.changeSomeValue(true))
        XCTAssertTrue(sut.someValue)
        XCTAssertTrue(storeEnv.wrappedValue.someValue)
    }

    func test_binding_whenSomeValueisTrue_and_toggleCalled_SomeValueShouldBeTrue() throws {
        let expect = expectation(description: "completion block was called")
        var setCalled = false

        let storeBinding = sut.binding(
            \.someValue,
             set: { someValue in
                 setCalled = true
                 Task {
                     expect.fulfill()
                 }
                 return .changeSomeValue(someValue)
             }
        )
        
        storeBinding.wrappedValue.toggle()
        wait(for: [expect], timeout: 1)
        XCTAssertTrue(sut.someValue)
        XCTAssertTrue(storeBinding.wrappedValue)
        XCTAssertTrue(setCalled)

    }

    func test_dispatch_WithEffects() async throws {
        await sut.dispatch(.changeSomeValue(true))

        XCTAssertTrue(sut.someValue)
    }
}
