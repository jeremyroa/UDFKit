import UDFKit

extension RootActions: StoreActionWrapper {
    static func wrap(_ action: any StoreAction) -> RootActions? {
        switch action {
        case let counterActions as CounterActions:
            .counter(counterActions)
        case let textActions as TextActions:
            .text(textActions)
        default:
            nil
        }
    }

    func unwrapAs<T: StoreAction>() -> T? {
        switch self {
        case let .counter(counterActions):
            counterActions as? T
        case let .text(textActions):
            textActions as? T
        }
    }
}
