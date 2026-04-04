import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MacrosLibraryPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StoreActionWrapperMacro.self
    ]
}
