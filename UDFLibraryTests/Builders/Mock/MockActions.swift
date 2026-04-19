import UDFLibrary

enum CounterActions: StoreAction {
    case increment
}

enum TextActions: StoreAction {
    case append(String)
}

enum RootActions: StoreAction {
    case counter(CounterActions)
    case text(TextActions)
}
