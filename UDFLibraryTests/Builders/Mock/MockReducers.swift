import UDFLibrary


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
        case .append(let text):
            newState.text += text
        }
        return newState
    }
}
