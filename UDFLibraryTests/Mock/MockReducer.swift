@testable import UDFLibrary

struct MockReducer: Reducer {
    func reduce(oldState: StateMock, with action: ActionMock) -> StateMock {
        var newState = oldState
        switch action {
            case .changeSomeValue(let value):
                newState.someValue = value
            case .fetchValueSuccess(let value):
                newState.someValue = value.isEmpty
                newState.asyncValue = value
            case .fetchValue:
                break
        }

        return newState
    }
}
