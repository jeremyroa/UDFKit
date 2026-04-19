public protocol Reducer<State, Action> {
    associatedtype State: StoreState
    associatedtype Action: StoreAction

    func reduce(oldState: State, with action: Action) -> State
}
