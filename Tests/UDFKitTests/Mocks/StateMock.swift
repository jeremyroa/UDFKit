@testable import UDFKit

struct StateMock: StoreState {
    var someValue: Bool
    var asyncValue: [Bool]
}
