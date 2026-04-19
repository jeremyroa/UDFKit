import UDFLibrary

actor CounterEffect: Effect {
    typealias State = CounterState
    typealias Action = CounterActions
    
    func process(state: State, with action: Action) async -> Action? {
        switch action {
        case .increment where state.count >= 10:
            return .increment
        default:
            return nil
        }
    }
}

actor TextEffect: Effect {
    typealias State = TextState
    typealias Action = TextActions
    
    func process(state: State, with action: Action) async -> Action? {
        switch action {
        case .append(_) where state.text.isEmpty:
            return .append("Hello!!")
        default:
            return nil
        }
    }
}

actor RootEffect: Effect {
    func process(state: RootState, with action: RootActions) async -> RootActions? {
        switch action {
        case .counter(.increment):
            if state.counterState.count == 9 && state.textState.text.isEmpty {
                return .text(.append("About to reach 10!"))
            }
            return nil
        case .text(.append):
            if !state.textState.text.isEmpty && state.counterState.count > 5 {
                return .counter(.increment)
            }
            return nil
        }
    }
}
