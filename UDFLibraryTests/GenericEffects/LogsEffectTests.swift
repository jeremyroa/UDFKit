import XCTest
@testable import UDFLibrary

final class LogsEffectTests: XCTestCase {

    var sut: LogsEffect<StateMock, ActionMock>!

    override func setUpWithError() throws {
        sut = LogsEffect<StateMock, ActionMock>()
    }

    override func tearDownWithError() throws {
        sut = nil
    }

    func test_process_whenActionIsProccessed_returnNilAndStateNotChanged() async throws {
        let state: StateMock = .init(someValue: true, asyncValue: [])
        let result1 = await sut.process(state: state, with: .changeSomeValue(false))
        let result2 = await sut.process(state: state, with: .fetchValue)
        let result3 = await sut.process(state: state, with: .fetchValueSuccess([]))
        let result4 = await sut.process(state: state, with: .fetchValueSuccess([false]))

        XCTAssertNil(result1)
        XCTAssertNil(result2)
        XCTAssertNil(result3)
        XCTAssertNil(result4)
        XCTAssertTrue(state.someValue)
    }

}
