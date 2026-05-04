import Testing
@testable import UDFKit

// MARK: - applyReducer Tests

@Suite("applyReducer Tests")
struct ApplyReducerTests {

    @Test("GIVEN StoreActionWrapper action WHEN sub-action matches reducer type THEN updates sub-state")
    func sut_whenWrappedActionMatchesReducerType_thenUpdatesSubState() {
        let result = applyReducer(
            state: RootState(),
            action: RootActions.counter(.increment),
            keyPath: \RootState.counterState,
            reducer: CounterReducer()
        )

        #expect(result.counterState.count == 1)
        #expect(result.textState.text == "")
    }

    @Test("GIVEN direct action matching reducer type WHEN applied THEN updates sub-state")
    func sut_whenDirectActionMatchesReducerType_thenUpdatesSubState() {
        let result = applyReducer(
            state: CounterState(count: 0),
            action: CounterActions.increment,
            keyPath: \CounterState.self,
            reducer: CounterReducer()
        )

        #expect(result.count == 1)
    }

    @Test("GIVEN StoreActionWrapper action WHEN sub-action does not match reducer type THEN state is unchanged")
    func sut_whenWrappedActionDoesNotMatchReducerType_thenStateIsUnchanged() {
        let initial = RootState()

        let result = applyReducer(
            state: initial,
            action: RootActions.text(.append("Test")),
            keyPath: \RootState.counterState,
            reducer: CounterReducer()
        )

        #expect(result.counterState.count == initial.counterState.count)
    }

    @Test("GIVEN unrelated action WHEN applied THEN state is unchanged")
    func sut_whenUnrelatedAction_thenStateIsUnchanged() {
        let initial = RootState()

        let result = applyReducer(
            state: initial,
            action: RootActions.counter(.increment),
            keyPath: \RootState.textState,
            reducer: TextReducer()
        )

        #expect(result.textState.text == initial.textState.text)
    }
}

// MARK: - applyEffect Tests

@Suite("applyEffect Tests")
struct ApplyEffectTests {

    @Test("GIVEN StoreActionWrapper action WHEN sub-action matches effect type THEN emits re-wrapped result")
    func sut_whenWrappedActionMatchesEffectType_thenEmitsReWrappedResult() async {
        let stream = await applyEffect(
            state: RootState(),
            action: RootActions.counter(.increment),
            extractSubState: { $0.counterState },
            effect: CounterEchoEffect()
        )

        let results = await collect(stream)

        guard let first = results.first else {
            Issue.record("Expected one action but received none")
            return
        }
        guard case .counter(.increment) = first else {
            Issue.record("Expected .counter(.increment) but received \(first)")
            return
        }
    }

    @Test("GIVEN direct action matching effect type WHEN applied THEN emits result without re-wrapping")
    func sut_whenDirectActionMatchesEffectType_thenEmitsResult() async {
        let stream = await applyEffect(
            state: CounterState(count: 0),
            action: CounterActions.increment,
            extractSubState: { $0 },
            effect: CounterEchoEffect()
        )

        let results = await collectCounter(stream)

        #expect(results.first == .increment)
    }

    @Test("GIVEN StoreActionWrapper action WHEN sub-action does not match effect type THEN returns empty stream")
    func sut_whenWrappedActionDoesNotMatchEffectType_thenReturnsEmptyStream() async {
        let stream = await applyEffect(
            state: RootState(),
            action: RootActions.text(.append("Test")),
            extractSubState: { $0.counterState },
            effect: CounterEchoEffect()
        )

        let results = await collect(stream)

        #expect(results.isEmpty)
    }

    @Test("GIVEN unrelated action WHEN applied THEN returns empty stream")
    func sut_whenUnrelatedAction_thenReturnsEmptyStream() async {
        let stream = await applyEffect(
            state: RootState(),
            action: RootActions.counter(.increment),
            extractSubState: { $0.textState },
            effect: TextEchoEffect()
        )

        let results = await collect(stream)

        #expect(results.isEmpty)
    }
}


private func collect(_ stream: AsyncStream<RootActions>) async -> [RootActions] {
    var results: [RootActions] = []
    for await action in stream { results.append(action) }
    return results
}

private func collectCounter(_ stream: AsyncStream<CounterActions>) async -> [CounterActions] {
    var results: [CounterActions] = []
    for await action in stream { results.append(action) }
    return results
}
