@testable import UDFLibrary

struct StateMock: StoreState {
    var someValue: Bool
    var asyncValue: [Bool]
}
