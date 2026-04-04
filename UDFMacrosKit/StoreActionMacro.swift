import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct StoreActionWrapperMacro: ExtensionMacro {
    public static func expansion(
        of _: SwiftSyntax.AttributeSyntax,
        attachedTo declaration: some SwiftSyntax.DeclGroupSyntax,
        providingExtensionsOf type: some SwiftSyntax.TypeSyntaxProtocol,
        conformingTo protocols: [SwiftSyntax.TypeSyntax],
        in _: some SwiftSyntaxMacros.MacroExpansionContext
    ) throws -> [SwiftSyntax.ExtensionDeclSyntax] {
        let enumDecl = try validateEnumDeclaration(declaration)

        let extensionDecl = try generateExtensionDeclaration(
            forType: type,
            conformingTo: protocols,
            withUnwrapCases: generateUnwrapCases(from: enumDecl),
            andWrapCases: generateWrapCases(from: enumDecl)
        )

        return [extensionDecl]
    }

    private static func validateEnumDeclaration(_ declaration: some DeclGroupSyntax) throws -> EnumDeclSyntax {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw Error.onlyApplicableToEnum
        }
        return enumDecl
    }

    private static func generateUnwrapCases(from enumDecl: EnumDeclSyntax) -> String {
        enumDecl.memberBlock.members
            .compactMap { member in
                guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self),
                      let firstCase = caseDecl.elements.first else {
                    return nil
                }

                let caseName = firstCase.name.text

                return "case let .\(caseName)(\(caseName)): return \(caseName) as? T"
            }
            .joined(separator: "\n        ")
    }

    private static func generateWrapCases(from enumDecl: EnumDeclSyntax) -> String {
        enumDecl.memberBlock.members
            .compactMap { member in
                guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self),
                      let firstCase = caseDecl.elements.first else {
                    return nil
                }

                let caseName = firstCase.name.text

                guard let parameterList = firstCase.parameterClause?.parameters,
                      let firstParam = parameterList.first,
                      let associatedType = firstParam.type.as(IdentifierTypeSyntax.self)?.name.text
                else {
                    return nil
                }

                return "case let \(caseName) as \(associatedType): return .\(caseName)(\(caseName))"
            }
            .joined(separator: "\n        ")
    }

    private static func generateExtensionDeclaration(
        forType type: some TypeSyntaxProtocol,
        conformingTo protocols: [SwiftSyntax.TypeSyntax],
        withUnwrapCases unwrapCases: String,
        andWrapCases wrapCases: String
    ) throws -> ExtensionDeclSyntax {
        try ExtensionDeclSyntax(
            """
            extension \(type.trimmed): \(protocols.first!) {
                public func unwrapAs<T>() -> T? where T: StoreAction {
                    switch self {
                    \(raw: unwrapCases)
                    }
                }

                public static func wrap(_ action: any StoreAction) -> \(type.trimmed)? {
                    switch action {
                    \(raw: wrapCases)
                    default: return nil
                    }
                }
            }
            """
        )
    }
}

enum Error: Swift.Error {
    case onlyApplicableToEnum
}
