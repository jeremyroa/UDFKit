import SwiftUI
import UDFKit

extension EnvironmentValues {
    @Entry var formStore: Store<ExampleFormState, ExampleFormAction>? = nil
}
