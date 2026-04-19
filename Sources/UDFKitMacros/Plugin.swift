import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct UDFKitMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StoreActionWrapperMacro.self
    ]
}
