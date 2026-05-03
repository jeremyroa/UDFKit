import Testing
@testable import UDFKit

@Suite("BuilderEffects")
struct BuilderEffectsTests {
    private func registered<E: Effect>(
        _ effect: E,
        on keyPath: KeyPath<RootState, E.State>
    ) async -> BuilderEffects<RootState, RootActions> where E.Action: StoreAction {
        let sut = BuilderEffects<RootState, RootActions>()
        sut.registerEffect(keyPath, effect)
        try? await Task.sleep(for: .milliseconds(100))
        return sut
    }

    private func firstAction(
        from sut: BuilderEffects<RootState, RootActions>,
        state: RootState = RootState(),
        action: RootActions
    ) async -> RootActions? {
        let stream = sut.process(state: state, with: action)
        return await stream.first(where: { _ in true })
    }

    @Test("counter effect returns nil when count is below threshold")
    func counterEffect_returnsNil_whenCountLow() async {
        let sut = await registered(CounterEffect(), on: \.counterState)
        let result = await firstAction(from: sut, action: .counter(.increment))
        #expect(result == nil)
    }

    @Test("counter effect returns increment action when count is at threshold")
    func counterEffect_returnsIncrement_whenCountHigh() async {
        var state = RootState()
        state.counterState.count = 10
        let sut = await registered(CounterEffect(), on: \.counterState)
        let result = await firstAction(from: sut, state: state, action: .counter(.increment))
        #expect(result == .counter(.increment))
    }

    @Test("text effect appends greeting when text is empty")
    func textEffect_appendsGreeting_whenEmpty() async {
        let sut = await registered(TextEffect(), on: \.textState)
        let result = await firstAction(from: sut, action: .text(.append("Test")))
        #expect(result == .text(.append("Hello!!")))
    }

    @Test("text effect returns nil when text is non-empty")
    func textEffect_returnsNil_whenNonEmpty() async {
        var state = RootState()
        state.textState.text = "Not empty"
        let sut = await registered(TextEffect(), on: \.textState)
        let result = await firstAction(from: sut, state: state, action: .text(.append("Test")))
        #expect(result == nil)
    }

    @Test("multiple registered effects process independently")
    func multipleEffects_processIndependently() async {
        let sut = BuilderEffects<RootState, RootActions>()
        sut.registerEffect(\.counterState, CounterEffect())
        sut.registerEffect(\.textState, TextEffect())
        try? await Task.sleep(for: .milliseconds(100))
        let result = await firstAction(from: sut, action: .counter(.increment))
        #expect(result == nil)
    }

    @Test("re-registering same effect has no duplicate")
    func reRegistering_sameEffect_noDuplicate() async {
        var state = RootState()
        state.counterState.count = 10
        let sut = BuilderEffects<RootState, RootActions>()
        sut.registerEffect(\.counterState, CounterEffect())
        sut.registerEffect(\.counterState, CounterEffect())
        try? await Task.sleep(for: .milliseconds(100))
        let result = await firstAction(from: sut, state: state, action: .counter(.increment))
        #expect(result == .counter(.increment))
    }

    @Test("non-matching action returns nil")
    func processingNonMatchingAction_returnsNil() async {
        let sut = await registered(CounterEffect(), on: \.counterState)
        let result = await firstAction(from: sut, action: .text(.append("Test")))
        #expect(result == nil)
    }

    @Test("direct counter effect registration handles action")
    func directCounterEffect_handlesAction() async {
        var state = RootState()
        state.counterState.count = 10
        let sut = await registered(CounterEffect(), on: \.counterState)
        let result = await firstAction(from: sut, state: state, action: .counter(.increment))
        #expect(result == .counter(.increment))
    }

    @Test("nested wrapped action is processed correctly")
    func nestedAction_processedCorrectly() async {
        var state = RootState()
        state.counterState.count = 10
        let sut = await registered(CounterEffect(), on: \.counterState)
        let result = await firstAction(from: sut, state: state, action: .counter(.increment))
        #expect(result == .counter(.increment))
    }

    @Test("direct and nested effects both produce results")
    func directAndNestedEffects_combination() async {
        var state = RootState()
        state.counterState.count = 10
        let sut = BuilderEffects<RootState, RootActions>()
        sut.registerEffect(\.self, RootEffect())
        sut.registerEffect(\.counterState, CounterEffect())
        try? await Task.sleep(for: .milliseconds(100))
        let result = await firstAction(from: sut, state: state, action: .counter(.increment))
        #expect(result != nil)
    }

    @Test("effect registered with self keyPath processes state directly")
    func directRegistration_withSelfKeyPath() async {
        let sut = BuilderEffects<TextState, TextActions>()
        sut.registerEffect(\.self, TextEffect())
        try? await Task.sleep(for: .milliseconds(100))
        let stream = sut.process(state: TextState(), with: .append("Test"))
        let result = await stream.first(where: { _ in true })
        #expect(result == .append("Hello!!"))
    }

    @Test("multi-action child effect emits all actions through merged stream")
    func multiActionChildEffect_emitsAllActionsInStream() async {
        let sut = BuilderEffects<CounterState, CounterActions>()
        sut.registerEffect(\.self, MultiActionCounterEffect())
        try? await Task.sleep(for: .milliseconds(100))
        let stream = sut.process(state: CounterState(), with: .increment)
        var collected: [CounterActions] = []
        for await action in stream { collected.append(action) }
        #expect(collected.count == 2)
    }

    @Test("empty child effect stream yields no actions")
    func emptyChildEffect_yieldsNoActions() async {
        let sut = BuilderEffects<CounterState, CounterActions>()
        sut.registerEffect(\.self, EmptyCounterEffect())
        try? await Task.sleep(for: .milliseconds(100))
        let stream = sut.process(state: CounterState(), with: .increment)
        var collected: [CounterActions] = []
        for await action in stream { collected.append(action) }
        #expect(collected.isEmpty)
    }
}
