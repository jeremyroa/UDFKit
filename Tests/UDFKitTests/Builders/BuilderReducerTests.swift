import Testing
@testable import UDFKit

@Suite("BuilderReducer")
struct BuilderReducerTests {
    private func makeSUT() -> BuilderReducer<RootState, RootActions> {
        BuilderReducer()
    }

    @Test("empty builder returns original state unchanged")
    func emptyBuilder_returnsOriginalState() {
        let sut = makeSUT()
        let initial = RootState()
        let new = sut.reduce(oldState: initial, with: .counter(.increment))
        #expect(new.counterState.count == initial.counterState.count)
        #expect(new.textState.text == initial.textState.text)
    }

    @Test("registered counter reducer handles counter action")
    func registerCounterReducer_handlesCounterAction() {
        let sut = makeSUT().registerReducer(\.counterState, CounterReducer())
        let new = sut.reduce(oldState: RootState(), with: .counter(.increment))
        #expect(new.counterState.count == 1)
        #expect(new.textState.text == "")
    }

    @Test("wrapped counter action handled correctly")
    func wrappedCounterAction_handlesCorrectly() {
        let sut = makeSUT().registerReducer(\.counterState, CounterReducer())
        guard let wrapped = RootActions.wrap(CounterActions.increment) else {
            Issue.record("Failed to wrap CounterActions.increment")
            return
        }
        let new = sut.reduce(oldState: RootState(), with: wrapped)
        #expect(new.counterState.count == 1)
    }

    @Test("wrapped text action handled correctly")
    func wrappedTextAction_handlesCorrectly() {
        let sut = makeSUT().registerReducer(\.textState, TextReducer())
        guard let wrapped = RootActions.wrap(TextActions.append("Test")) else {
            Issue.record("Failed to wrap TextActions.append")
            return
        }
        let new = sut.reduce(oldState: RootState(), with: wrapped)
        #expect(new.textState.text == "Test")
    }

    @Test("unwrap counter action returns correct type")
    func unwrapCounterAction_returnsCorrectType() {
        let action = RootActions.counter(.increment)
        let unwrapped: CounterActions? = action.unwrapAs()
        #expect(unwrapped == .increment)
    }

    @Test("unwrap text action returns correct type")
    func unwrapTextAction_returnsCorrectType() {
        let action = RootActions.text(.append("Test"))
        let unwrapped: TextActions? = action.unwrapAs()
        #expect(unwrapped == .append("Test"))
    }

    @Test("unwrap to wrong type returns nil")
    func unwrapToWrongType_returnsNil() {
        let action = RootActions.counter(.increment)
        let unwrapped: TextActions? = action.unwrapAs()
        #expect(unwrapped == nil)
    }

    @Test("mixed actions apply to correct sub-state")
    func mixedActionsHandling() {
        let sut = makeSUT()
            .registerReducer(\.counterState, CounterReducer())
            .registerReducer(\.textState, TextReducer())

        var state = RootState()
        if let wrappedCounter = RootActions.wrap(CounterActions.increment) {
            state = sut.reduce(oldState: state, with: wrappedCounter)
        }
        if let wrappedText = RootActions.wrap(TextActions.append("Test")) {
            state = sut.reduce(oldState: state, with: wrappedText)
        }
        #expect(state.counterState.count == 1)
        #expect(state.textState.text == "Test")
    }
}
