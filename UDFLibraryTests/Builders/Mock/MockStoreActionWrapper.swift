import UDFLibrary

extension RootActions: StoreActionWrapper {
    
    static func wrap(_ action: any StoreAction) -> RootActions? {
        switch action {
        case let counterActions as CounterActions:
            return .counter(counterActions)
            case let textActions as TextActions:
            return .text(textActions)
        default:
            return nil
        }
    }
    
    func unwrapAs<T>() -> T? where T : StoreAction {
        switch self {
        case .counter(let counterActions):
            return counterActions as?  T
        case .text(let textActions):
            return textActions as? T
        }
    }
}
