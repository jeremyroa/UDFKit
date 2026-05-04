import Testing
@testable import UDFKit

@Suite("EffectScope Tests")
struct EffectScopeTests {

    @Test("GIVEN EffectScope WHEN initialized with keyPath THEN extractSubState returns correct sub-state")
    func sut_whenInitWithKeyPath_thenExtractSubStateReturnsCorrectSubState() {
        var rootState = RootState()
        rootState.counterState.count = 42
        let sut = EffectScope(\RootState.counterState, CounterEchoEffect())

        let extracted = sut.extractSubState(rootState)

        #expect(extracted.count == 42)
    }

    @Test("GIVEN EffectScope WHEN initialized with different keyPath THEN extractSubState returns correct sub-state")
    func sut_whenInitWithTextKeyPath_thenExtractSubStateReturnsCorrectSubState() {
        var rootState = RootState()
        rootState.textState.text = "hello"
        let sut = EffectScope(\RootState.textState, TextEchoEffect())

        let extracted = sut.extractSubState(rootState)

        #expect(extracted.text == "hello")
    }
}


@Suite("EffectsDSL Tests")
struct EffectsDSLTests {

    @Test("GIVEN buildExpression WHEN action does not match effect type THEN closure returns empty stream")
    func sut_whenBuildExpressionWithNonMatchingAction_thenReturnsEmptyStream() async {
        let scope = EffectScope(\RootState.counterState, CounterEchoEffect())
        let process = EffectsDSL<RootState, RootActions>.buildExpression(scope)

        let results = await collect(process(RootState(), .text(.append("Test"))))

        #expect(results.isEmpty)
    }

    @Test("GIVEN buildExpression WHEN action matches effect type THEN closure emits re-wrapped action")
    func sut_whenBuildExpressionWithMatchingAction_thenEmitsReWrappedAction() async {
        let scope = EffectScope(\RootState.counterState, CounterEchoEffect())
        let process = EffectsDSL<RootState, RootActions>.buildExpression(scope)

        let results = await collect(process(RootState(), .counter(.increment)))

        guard let first = results.first else {
            Issue.record("Expected one action but received none")
            return
        }
        guard case .counter(.increment) = first else {
            Issue.record("Expected .counter(.increment) but received \(first)")
            return
        }
    }

    @Test("GIVEN buildBlock with no processes WHEN action is dispatched THEN returns empty stream")
    func sut_whenBuildBlockEmpty_thenReturnsEmptyStream() async throws {
        let sut = EffectsDSL<RootState, RootActions>.buildBlock()
        try await waitForRegistration()

        let results = await collect(sut.process(state: RootState(), with: .counter(.increment)))

        #expect(results.isEmpty)
    }

    @Test("GIVEN buildBlock with one process WHEN matching action is dispatched THEN emits action")
    func sut_whenBuildBlockWithOneProcess_thenEmitsAction() async throws {
        let scope = EffectScope(\RootState.counterState, CounterEchoEffect())
        let sut = EffectsDSL<RootState, RootActions>.buildBlock(
            EffectsDSL.buildExpression(scope)
        )
        try await waitForRegistration()

        let results = await collect(sut.process(state: RootState(), with: .counter(.increment)))

        guard case .counter(.increment) = results.first else {
            Issue.record("Expected .counter(.increment) but received \(results)")
            return
        }
    }

    @Test("GIVEN buildBlock with multiple processes WHEN each matching action is dispatched THEN each routes independently")
    func sut_whenBuildBlockWithMultipleProcesses_thenEachRoutesIndependently() async throws {
        let sut = EffectsDSL<RootState, RootActions>.buildBlock(
            EffectsDSL.buildExpression(EffectScope(\RootState.counterState, CounterEchoEffect())),
            EffectsDSL.buildExpression(EffectScope(\RootState.textState, TextEchoEffect()))
        )
        try await waitForRegistration()

        let counterResults = await collect(sut.process(state: RootState(), with: .counter(.increment)))
        let textResults = await collect(sut.process(state: RootState(), with: .text(.append("Test"))))

        guard case .counter(.increment) = counterResults.first else {
            Issue.record("Expected .counter(.increment) but received \(counterResults)")
            return
        }
        guard case .text(.append(let value)) = textResults.first else {
            Issue.record("Expected .text(.append) but received \(textResults)")
            return
        }
        #expect(value == "Test")
    }

    @Test("GIVEN buildBlock with same process passed twice WHEN action is dispatched THEN emits twice because each gets a unique index-based id")
    func sut_whenBuildBlockWithSameProcessTwice_thenEmitsTwice() async throws {
        let process = EffectsDSL<RootState, RootActions>.buildExpression(
            EffectScope(\RootState.counterState, CounterEchoEffect())
        )
        let sut = EffectsDSL<RootState, RootActions>.buildBlock(process, process)
        try await waitForRegistration()

        let results = await collect(sut.process(state: RootState(), with: .counter(.increment)))

        #expect(results.count == 2)
    }

    @Test("GIVEN DSL result builder syntax WHEN matching action is dispatched THEN emits re-wrapped action")
    func sut_whenBuiltWithDSLSyntax_thenEmitsReWrappedAction() async throws {
        let sut = makeDSLEffect {
            EffectScope(\RootState.counterState, CounterEchoEffect())
        }
        try await waitForRegistration()

        let results = await collect(sut.process(state: RootState(), with: .counter(.increment)))

        guard case .counter(.increment) = results.first else {
            Issue.record("Expected .counter(.increment) but received \(results)")
            return
        }
    }
}

private extension EffectsDSLTests {

    func makeDSLEffect(
        @EffectsDSL<RootState, RootActions> _ build: () -> some Effect<RootState, RootActions>
    ) -> some Effect<RootState, RootActions> {
        build()
    }

    func waitForRegistration() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    func collect(_ stream: AsyncStream<RootActions>) async -> [RootActions] {
        var results: [RootActions] = []
        for await action in stream { results.append(action) }
        return results
    }
}
