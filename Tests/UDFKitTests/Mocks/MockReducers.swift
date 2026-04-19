import UDFKit

struct CounterReducer: Reducer {
    typealias State = CounterState

    typealias Action = CounterActions

    func reduce(oldState: State, with action: Action) -> State {
        var newState = oldState
        switch action {
        case .increment:
            newState.count += 1
        }

        return newState
    }
}

struct TextReducer: Reducer {
    typealias State = TextState

    typealias Action = TextActions

    func reduce(oldState: State, with action: Action) -> State {
        var newState = oldState
        switch action {
        case let .append(text):
            newState.text += text
        }
        return newState
    }
}
