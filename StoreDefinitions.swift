import Foundation

public protocol StoreState: Equatable {}
public protocol StoreAction: Equatable {}

public protocol StoreActionWrapper: StoreAction {
    func unwrapAs<T: StoreAction>() -> T?
    static func wrap(_ action: any StoreAction) -> Self?
}

@attached(extension, conformances: StoreActionWrapper, names: arbitrary)
public macro StoreActionWrapper() = #externalMacro(
    module: "MacrosLibrary",
    type: "StoreActionWrapperMacro"
)
