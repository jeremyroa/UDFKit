import Testing
@testable import UDFKit

// MARK: - ReducerScope Tests

@Suite("ReducerScope Tests")
struct ReducerScopeTests {

    @Test("GIVEN ReducerScope WHEN initialized THEN keyPath writes to correct sub-state")
    func sut_whenInit_thenKeyPathWritesToCorrectSubState() {
        let sut = ReducerScope(\RootState.counterState, CounterReducer())

        var state = RootState()
        state[keyPath: sut.keyPath].count = 42

        #expect(state.counterState.count == 42)
    }

    @Test("GIVEN ReducerScope WHEN initialized THEN stored reducer applies correctly")
    func sut_whenInit_thenStoredReducerAppliesCorrectly() {
        let sut = ReducerScope(\RootState.counterState, CounterReducer())

        let result = sut.reducer.reduce(oldState: CounterState(count: 0), with: .increment)

        #expect(result.count == 1)
    }
}

// MARK: - ReducerDSL Tests

@Suite("ReducerDSL Tests")
struct ReducerDSLTests {

    @Test("GIVEN buildExpression WHEN action matches reducer type THEN updates sub-state")
    func sut_whenBuildExpressionWithMatchingAction_thenUpdatesSubState() {
        let scope = ReducerScope(\RootState.counterState, CounterReducer())
        let reduce = ReducerDSL<RootState, RootActions>.buildExpression(scope)

        let result = reduce(RootState(), .counter(.increment))

        #expect(result.counterState.count == 1)
        #expect(result.textState.text == "")
    }

    @Test("GIVEN buildExpression WHEN action does not match reducer type THEN state is unchanged")
    func sut_whenBuildExpressionWithNonMatchingAction_thenStateIsUnchanged() {
        let scope = ReducerScope(\RootState.counterState, CounterReducer())
        let reduce = ReducerDSL<RootState, RootActions>.buildExpression(scope)
        let initial = RootState()

        let result = reduce(initial, .text(.append("Test")))

        #expect(result.counterState.count == initial.counterState.count)
    }

    @Test("GIVEN buildBlock with no reducers WHEN action is dispatched THEN state is unchanged")
    func sut_whenBuildBlockEmpty_thenStateIsUnchanged() {
        let sut = ReducerDSL<RootState, RootActions>.buildBlock()
        let initial = RootState()

        let result = sut.reduce(oldState: initial, with: .counter(.increment))

        #expect(result.counterState.count == initial.counterState.count)
        #expect(result.textState.text == initial.textState.text)
    }

    @Test("GIVEN buildBlock with one reducer WHEN matching action is dispatched THEN updates sub-state")
    func sut_whenBuildBlockWithOneReducer_thenUpdatesSubState() {
        let sut = ReducerDSL<RootState, RootActions>.buildBlock(
            ReducerDSL.buildExpression(ReducerScope(\RootState.counterState, CounterReducer()))
        )

        let result = sut.reduce(oldState: RootState(), with: .counter(.increment))

        #expect(result.counterState.count == 1)
    }

    @Test("GIVEN buildBlock with multiple reducers WHEN each matching action is dispatched THEN each updates its own sub-state")
    func sut_whenBuildBlockWithMultipleReducers_thenEachUpdatesOwnSubState() {
        let sut = ReducerDSL<RootState, RootActions>.buildBlock(
            ReducerDSL.buildExpression(ReducerScope(\RootState.counterState, CounterReducer())),
            ReducerDSL.buildExpression(ReducerScope(\RootState.textState, TextReducer()))
        )

        let afterCounter = sut.reduce(oldState: RootState(), with: .counter(.increment))
        let result = sut.reduce(oldState: afterCounter, with: .text(.append("hello")))

        #expect(result.counterState.count == 1)
        #expect(result.textState.text == "hello")
    }

    @Test("GIVEN buildBlock with multiple reducers WHEN unrelated action is dispatched THEN only matching sub-state changes")
    func sut_whenBuildBlockWithMultipleReducers_thenOnlyMatchingSubStateChanges() {
        let sut = ReducerDSL<RootState, RootActions>.buildBlock(
            ReducerDSL.buildExpression(ReducerScope(\RootState.counterState, CounterReducer())),
            ReducerDSL.buildExpression(ReducerScope(\RootState.textState, TextReducer()))
        )

        let result = sut.reduce(oldState: RootState(), with: .counter(.increment))

        #expect(result.counterState.count == 1)
        #expect(result.textState.text == "")
    }

    @Test("GIVEN DSL result builder syntax WHEN action is dispatched THEN updates state correctly")
    func sut_whenBuiltWithDSLSyntax_thenUpdatesState() {
        let sut = makeReducer {
            ReducerScope(\RootState.counterState, CounterReducer())
            ReducerScope(\RootState.textState, TextReducer())
        }

        let afterCounter = sut.reduce(oldState: RootState(), with: .counter(.increment))
        let result = sut.reduce(oldState: afterCounter, with: .text(.append("hello")))

        #expect(result.counterState.count == 1)
        #expect(result.textState.text == "hello")
    }
}

private extension ReducerDSLTests {

    func makeReducer(
        @ReducerDSL<RootState, RootActions> _ build: () -> some Reducer<RootState, RootActions>
    ) -> some Reducer<RootState, RootActions> {
        build()
    }
}
