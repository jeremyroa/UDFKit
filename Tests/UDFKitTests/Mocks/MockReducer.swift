@testable import UDFKit

struct MockReducer: Reducer {
    func reduce(oldState: StateMock, with action: ActionMock) -> StateMock {
        var newState = oldState
        switch action {
        case let .changeSomeValue(value):
            newState.someValue = value
        case let .fetchValueSuccess(value):
            newState.someValue = value.isEmpty
            newState.asyncValue = value
        case .fetchValue:
            break
        }

        return newState
    }
}
