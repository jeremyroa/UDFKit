#if canImport(MacrosLibrary)
import XCTest
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import MacrosLibrary

public protocol StoreAction: Equatable {}

final class StoreActionWrapperTests: XCTestCase {

    private let macros: [String: Macro.Type] = [
        "StoreActionWrapper": StoreActionWrapperMacro.self
    ]
    
    func testBasicEnumExpansion() {
        let input = """
        @StoreActionWrapper
        enum TestAction {
            case login(LoginAction)
            case logout(LogoutAction)
        }
        """
        
        let expected = """
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
        """
        
        assertMacroExpansion(
            input,
            expandedSource: expected,
            macros: macros
        )
    }
    
    func test_EmptyEnumExpansion() {
        let input = """
        @StoreActionWrapper
        enum EmptyAction {
        }
        """
        
        let expected = """
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
        """
        
        assertMacroExpansion(
            input,
            expandedSource: expected,
            macros: macros
        )
    }
    
    func test_NonEnumDeclaration() {
        let input = """
        @StoreActionWrapper
        struct InvalidTest {
        }
        """
        
        assertMacroExpansion(
            input,
            expandedSource: input,
            diagnostics: [
                DiagnosticSpec(
                    message: "onlyApplicableToEnum",
                    line: 1,
                    column: 1
                )
            ],
            macros: macros
        )
    }
    
    func test_ComplexEnumExpansion() {
        let input = """
        @StoreActionWrapper
        enum ComplexAction {
            case fetch(FetchAction)
            case update(UpdateAction)
            case delete(DeleteAction)
            
            var description: String {
                return "Complex Action"
            }
        }
        """
        
        let expected = """
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
        """
        
        assertMacroExpansion(
            input,
            expandedSource: expected,
            macros: macros
        )
    }
    
    func test_MultipleAssociatedValuesExpansion() {
        let input = """
        @StoreActionWrapper
        enum MultiValueAction {
            case complex(MainAction, context: ContextAction)
        }
        """
        
        let expected = """
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
        """
        
        assertMacroExpansion(
            input,
            expandedSource: expected,
            macros: macros
        )
    }
}
#endif
