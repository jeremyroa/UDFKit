import UDFKit

struct ExampleFormState: StoreState {
    var name: String = ""
    var count: Int = 0
}

enum ExampleFormAction: StoreAction {
    case setName(String)
    case setCount(Int)
    case reset
}

struct ExampleFormReducer: Reducer {
    func reduce(oldState: ExampleFormState, with action: ExampleFormAction) -> ExampleFormState {
        var state = oldState
        switch action {
        case let .setName(name):
            state.name = name
        case let .setCount(count):
            state.count = count
        case .reset:
            state = ExampleFormState()
        }
        return state
    }
}
