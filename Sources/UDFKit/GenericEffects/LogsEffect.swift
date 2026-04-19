import Foundation

public struct LogsEffect<GenericState: StoreState, GenericAction: StoreAction>: Effect {
    public typealias State = GenericState
    public typealias Action = GenericAction

    private let isEnabled: Bool

    private static var actionPrefix: String {
        "🎯 Action"
    }

    private static var statePrefix: String {
        "📦 State"
    }

    private static var separator: String {
        "\n----------------------------------------\n"
    }

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    public func process(state: GenericState, with action: GenericAction) async -> GenericAction? {
        if isEnabled {
            Self.logStateChange(action: action, state: state)
        }
        return nil
    }

    private static func logStateChange(action: GenericAction, state: GenericState) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())

        let message = """
        \(separator)🔨UDF Log:\n
        ⏱ [\(timestamp)]

        \(actionPrefix):
        \(prettyPrintEnum(action))

        \(statePrefix):
        \(prettyPrintState(state))
        \(separator)
        """

        print(message)
    }

    private static func prettyPrintEnum(_ action: GenericAction) -> String {
        let mirror = Mirror(reflecting: action)
        if mirror.children.isEmpty {
            return "  └─ .\(action)"
        } else {
            let caseName = String(describing: action).split(separator: "(").first ?? ""
            let parameters = mirror.children.map { child in
                if let label = child.label {
                    return "\(label): \(child.value)"
                }
                return "\(child.value)"
            }.joined(separator: ", ")
            return "  └─ .\(caseName)(\(parameters))"
        }
    }

    private static func prettyPrintState(_ state: GenericState) -> String {
        let mirror = Mirror(reflecting: state)
        return mirror.children.map { child in
            if let label = child.label {
                let value = prettyPrintValue(child.value)
                return "  ├─ \(label): \(value)"
            }
            return "  └─ \(child.value)"
        }.joined(separator: "\n")
    }

    private static func prettyPrintValue(_ value: Any) -> String {
        if let array = value as? [Any] {
            if array.isEmpty {
                return "[]"
            }
            return "[\n    \(array.map { "    \($0)" }.joined(separator: ",\n"))\n  ]"
        }
        return "\(value)"
    }
}
