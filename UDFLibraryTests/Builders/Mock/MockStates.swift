import UDFLibrary

struct TextState: StoreState {
    var text: String = ""
}

struct CounterState: StoreState {
    var count: Int = 0
}

struct RootState: StoreState {
    var counterState = CounterState()
    var textState = TextState()
}
