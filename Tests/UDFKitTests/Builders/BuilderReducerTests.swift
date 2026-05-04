import Testing
@testable import UDFKit

@Suite("BuilderReducer Tests")
struct BuilderReducerTests {

    @Test("GIVEN empty BuilderReducer WHEN reduce is called THEN returns original state unchanged")
    func sut_whenEmpty_thenReturnsOriginalState() {
        let sut = makeSUT()
        let initial = RootState()

        let result = sut.reduce(oldState: initial, with: .counter(.increment))

        #expect(result.counterState.count == initial.counterState.count)
        #expect(result.textState.text == initial.textState.text)
    }

    @Test("GIVEN counter block registered WHEN counter action is dispatched THEN updates counter sub-state only")
    func sut_whenCounterBlockRegistered_thenUpdatesCounterSubState() {
        let sut = makeSUT().registerBlock { state, action in
            guard let counterAction: CounterActions = action.unwrapAs() else { return state }
            var newState = state
            newState.counterState = CounterReducer().reduce(oldState: state.counterState, with: counterAction)
            return newState
        }

        let result = sut.reduce(oldState: RootState(), with: .counter(.increment))

        #expect(result.counterState.count == 1)
        #expect(result.textState.text == "")
    }

    @Test("GIVEN text block registered WHEN text action is dispatched THEN updates text sub-state only")
    func sut_whenTextBlockRegistered_thenUpdatesTextSubState() {
        let sut = makeSUT().registerBlock { state, action in
            guard let textAction: TextActions = action.unwrapAs() else { return state }
            var newState = state
            newState.textState = TextReducer().reduce(oldState: state.textState, with: textAction)
            return newState
        }

        let result = sut.reduce(oldState: RootState(), with: .text(.append("Test")))

        #expect(result.textState.text == "Test")
        #expect(result.counterState.count == 0)
    }

    @Test("GIVEN multiple blocks registered WHEN mixed actions are dispatched THEN each updates its own sub-state")
    func sut_whenMultipleBlocksRegistered_thenEachUpdatesOwnSubState() {
        let sut = makeSUT()
            .registerBlock { state, action in
                guard let counterAction: CounterActions = action.unwrapAs() else { return state }
                var newState = state
                newState.counterState = CounterReducer().reduce(oldState: state.counterState, with: counterAction)
                return newState
            }
            .registerBlock { state, action in
                guard let textAction: TextActions = action.unwrapAs() else { return state }
                var newState = state
                newState.textState = TextReducer().reduce(oldState: state.textState, with: textAction)
                return newState
            }

        let afterCounter = sut.reduce(oldState: RootState(), with: .counter(.increment))
        let result = sut.reduce(oldState: afterCounter, with: .text(.append("Test")))

        #expect(result.counterState.count == 1)
        #expect(result.textState.text == "Test")
    }

    @Test("GIVEN counter action WHEN unwrapped THEN returns correct CounterActions value")
    func sut_whenUnwrapCounterAction_thenReturnsCounterActions() {
        let action = RootActions.counter(.increment)

        let unwrapped: CounterActions? = action.unwrapAs()

        #expect(unwrapped == .increment)
    }

    @Test("GIVEN text action WHEN unwrapped THEN returns correct TextActions value")
    func sut_whenUnwrapTextAction_thenReturnsTextActions() {
        let action = RootActions.text(.append("Test"))

        let unwrapped: TextActions? = action.unwrapAs()

        #expect(unwrapped == .append("Test"))
    }

    @Test("GIVEN counter action WHEN unwrapped as TextActions THEN returns nil")
    func sut_whenUnwrapCounterActionAsWrongType_thenReturnsNil() {
        let action = RootActions.counter(.increment)

        let unwrapped: TextActions? = action.unwrapAs()

        #expect(unwrapped == nil)
    }

    @Test(
        "GIVEN multiple blocks registered WHEN action is dispatched THEN only matching block updates its sub-state",
        arguments: [
            (action: RootActions.counter(.increment), expectedCount: 1, expectedText: ""),
            (action: RootActions.text(.append("hello")), expectedCount: 0, expectedText: "hello")
        ]
    )
    func sut_whenActionDispatched_thenOnlyMatchingBlockUpdatesSubState(
        mapping: (action: RootActions, expectedCount: Int, expectedText: String)
    ) {
        let sut = makeSUT()
            .registerBlock { state, action in
                guard let counterAction: CounterActions = action.unwrapAs() else { return state }
                var newState = state
                newState.counterState = CounterReducer().reduce(oldState: state.counterState, with: counterAction)
                return newState
            }
            .registerBlock { state, action in
                guard let textAction: TextActions = action.unwrapAs() else { return state }
                var newState = state
                newState.textState = TextReducer().reduce(oldState: state.textState, with: textAction)
                return newState
            }

        let result = sut.reduce(oldState: RootState(), with: mapping.action)

        #expect(result.counterState.count == mapping.expectedCount)
        #expect(result.textState.text == mapping.expectedText)
    }
}

private extension BuilderReducerTests {

    func makeSUT() -> BuilderReducer<RootState, RootActions> {
        BuilderReducer()
    }
}
