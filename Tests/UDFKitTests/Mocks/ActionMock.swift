@testable import UDFKit

enum ActionMock: StoreAction {
    case changeSomeValue(Bool)
    case fetchValue
    case fetchValueSuccess([Bool])
}
