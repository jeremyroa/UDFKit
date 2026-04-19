import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import UDFKitMacros

/// StoreAction protocol stub for macro expansion testing (not importing UDFKit here)
private protocol StoreAction: Equatable {}

private let testMacros: [String: Macro.Type] = [
    "StoreActionWrapper": StoreActionWrapperMacro.self,
]

@Suite("StoreActionWrapperMacro")
struct StoreActionWrapperMacrosTests {
    @Test("basic enum expands to StoreActionWrapper conformance")
    func basicEnumExpansion() {
        assertMacroExpansion(
            """
            @StoreActionWrapper
            enum TestAction {
                case login(LoginAction)
                case logout(LogoutAction)
            }
            """,
            expandedSource: """
            enum TestAction {
                case login(LoginAction)
                case logout(LogoutAction)
            }

            extension TestAction: StoreActionWrapper {
                public func unwrapAs<T>() -> T? where T: StoreAction {
                    switch self {
                    case let .login(login): return login as? T
                    case let .logout(logout): return logout as? T
                    }
                }

                public static func wrap(_ action: any StoreAction) -> TestAction? {
                    switch action {
                    case let login as LoginAction: return .login(login)
                    case let logout as LogoutAction: return .logout(logout)
                    default: return nil
                    }
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test("empty enum expands with empty switch bodies")
    func emptyEnumExpansion() {
        assertMacroExpansion(
            """
            @StoreActionWrapper
            enum EmptyAction {
            }
            """,
            expandedSource: """
            enum EmptyAction {
            }

            extension EmptyAction: StoreActionWrapper {
                public func unwrapAs<T>() -> T? where T: StoreAction {
                    switch self {
                    }
                }

                public static func wrap(_ action: any StoreAction) -> EmptyAction? {
                    switch action {
                    default: return nil
                    }
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test("applying macro to struct emits diagnostic error")
    func nonEnumDeclarationProducesDiagnostic() {
        assertMacroExpansion(
            """
            @StoreActionWrapper
            struct InvalidTest {
            }
            """,
            expandedSource: """
            @StoreActionWrapper
            struct InvalidTest {
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "onlyApplicableToEnum", line: 1, column: 1),
            ],
            macros: testMacros
        )
    }

    @Test("complex enum with computed property expands correctly")
    func complexEnumExpansion() {
        assertMacroExpansion(
            """
            @StoreActionWrapper
            enum ComplexAction {
                case fetch(FetchAction)
                case update(UpdateAction)
                case delete(DeleteAction)

                var description: String {
                    return "Complex Action"
                }
            }
            """,
            expandedSource: """
            enum ComplexAction {
                case fetch(FetchAction)
                case update(UpdateAction)
                case delete(DeleteAction)

                var description: String {
                    return "Complex Action"
                }
            }

            extension ComplexAction: StoreActionWrapper {
                public func unwrapAs<T>() -> T? where T: StoreAction {
                    switch self {
                    case let .fetch(fetch): return fetch as? T
                    case let .update(update): return update as? T
                    case let .delete(delete): return delete as? T
                    }
                }

                public static func wrap(_ action: any StoreAction) -> ComplexAction? {
                    switch action {
                    case let fetch as FetchAction: return .fetch(fetch)
                    case let update as UpdateAction: return .update(update)
                    case let delete as DeleteAction: return .delete(delete)
                    default: return nil
                    }
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test("case with multiple associated values uses only first parameter")
    func multipleAssociatedValuesExpansion() {
        assertMacroExpansion(
            """
            @StoreActionWrapper
            enum MultiValueAction {
                case complex(MainAction, context: ContextAction)
            }
            """,
            expandedSource: """
            enum MultiValueAction {
                case complex(MainAction, context: ContextAction)
            }

            extension MultiValueAction: StoreActionWrapper {
                public func unwrapAs<T>() -> T? where T: StoreAction {
                    switch self {
                    case let .complex(complex): return complex as? T
                    }
                }

                public static func wrap(_ action: any StoreAction) -> MultiValueAction? {
                    switch action {
                    case let complex as MainAction: return .complex(complex)
                    default: return nil
                    }
                }
            }
            """,
            macros: testMacros
        )
    }
}
