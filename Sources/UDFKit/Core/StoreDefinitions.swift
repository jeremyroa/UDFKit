import Foundation

/// Marks a type as a UDFKit state container. Must be `Equatable` for diffing and `Sendable` for concurrency.
public protocol StoreState: Equatable, Sendable {}

/// Marks a type as a dispatchable action in a UDFKit store. Typically an enum.
public protocol StoreAction: Equatable, Sendable {}

/// A composite action type that wraps child action enums. Use `@StoreActionWrapper` to auto-generate conformance.
public protocol StoreActionWrapper: StoreAction {
    /// Attempts to extract the wrapped child action as type `T`.
    func unwrapAs<T: StoreAction>() -> T?
    /// Wraps any `StoreAction` value into this type, returning `nil` if the action is not a supported child type.
    static func wrap(_ action: any StoreAction) -> Self?
}

/// Generates `StoreActionWrapper` conformance for a root action enum, producing `unwrapAs` and `wrap` methods.
@attached(extension, conformances: StoreActionWrapper, names: arbitrary)
public macro StoreActionWrapper() = #externalMacro(
    module: "UDFKitMacros",
    type: "StoreActionWrapperMacro"
)
