import UDFKit

struct FormState: StoreState {
    var name: String = ""
    var count: Int = 0
}

enum FormAction: StoreAction {
    case setName(String)
    case setCount(Int)
}

struct FormReducer: Reducer {
    func reduce(oldState: FormState, with action: FormAction) -> FormState {
        var state = oldState
        switch action {
        case let .setName(name):
            state.name = name
        case let .setCount(count):
            state.count = count
        }
        return state
    }
}
