import Testing
@testable import UDFKit

@Suite("BuilderEffects Tests")
struct BuilderEffectsTests {

    @Test("GIVEN CounterEffect WHEN count is below threshold THEN returns empty stream")
    func sut_whenCountBelowThreshold_thenReturnsEmptyStream() async throws {
        let sut = try await makeSUT(with: CounterEffect(), on: \.counterState)

        let stream = await sut.process(state: RootState(), with: .counter(.increment))
        let results = await collect(stream)

        #expect(results.isEmpty)
    }

    @Test("GIVEN CounterEffect WHEN count is at threshold THEN emits re-wrapped increment action")
    func sut_whenCountAtThreshold_thenEmitsReWrappedAction() async throws {
        var state = RootState()
        state.counterState.count = 10
        let sut = try await makeSUT(with: CounterEffect(), on: \.counterState)

        let stream = await sut.process(state: state, with: .counter(.increment))
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

    @Test("GIVEN CounterEffect registered WHEN process called with unrelated text action THEN returns empty stream")
    func sut_whenNonMatchingAction_thenReturnsEmptyStream() async throws {
        let sut = try await makeSUT(with: CounterEffect(), on: \.counterState)

        let stream = await sut.process(state: RootState(), with: .text(.append("Test")))
        let results = await collect(stream)

        #expect(results.isEmpty)
    }

    @Test("GIVEN TextEffect WHEN text is empty THEN emits re-wrapped greeting action")
    func sut_whenTextIsEmpty_thenEmitsGreetingAction() async throws {
        let sut = try await makeSUT(with: TextEffect(), on: \.textState)

        let stream = await sut.process(state: RootState(), with: .text(.append("Test")))
        let results = await collect(stream)

        guard let first = results.first else {
            Issue.record("Expected one action but received none")
            return
        }
        guard case .text(.append(let value)) = first else {
            Issue.record("Expected .text(.append) but received \(first)")
            return
        }
        #expect(value == "Hello!!")
    }

    @Test("GIVEN TextEffect WHEN text is non-empty THEN returns empty stream")
    func sut_whenTextIsNonEmpty_thenReturnsEmptyStream() async throws {
        var state = RootState()
        state.textState.text = "Not empty"
        let sut = try await makeSUT(with: TextEffect(), on: \.textState)

        let stream = await sut.process(state: state, with: .text(.append("Test")))
        let results = await collect(stream)

        #expect(results.isEmpty)
    }

    @Test("GIVEN BuilderEffects<TextState TextActions> with self keyPath WHEN action matches THEN emits action directly without re-wrapping")
    func sut_whenSelfKeyPathWithNonWrapperAction_thenEmitsDirectly() async throws {
        let sut = BuilderEffects<TextState, TextActions>()
        sut.registerEffect(\.self, TextEffect())
        try await Task.sleep(for: .milliseconds(100))

        let stream = await sut.process(state: TextState(), with: .append("Test"))
        let results = await collectText(stream)

        guard let first = results.first else {
            Issue.record("Expected one action but received none")
            return
        }
        guard case .append(let value) = first else {
            Issue.record("Expected .append but received \(first)")
            return
        }
        #expect(value == "Hello!!")
    }

    @Test("GIVEN same effect registered twice WHEN process called THEN emits only once — no duplicate")
    func sut_whenSameEffectRegisteredTwice_thenEmitsOnce() async throws {
        var state = RootState()
        state.counterState.count = 10
        let sut = BuilderEffects<RootState, RootActions>()
        sut.registerEffect(\.counterState, CounterEffect())
        sut.registerEffect(\.counterState, CounterEffect())
        try await Task.sleep(for: .milliseconds(100))

        let stream = await sut.process(state: state, with: .counter(.increment))
        let results = await collect(stream)

        #expect(results.count == 1)
    }

    @Test("GIVEN multiple distinct effects WHEN action matches only one THEN only that effect emits")
    func sut_whenOnlyOneEffectMatchesAction_thenOnlyThatEffectEmits() async throws {
        var state = RootState()
        state.counterState.count = 10
        let sut = BuilderEffects<RootState, RootActions>()
        sut.registerEffect(\.counterState, CounterEffect())
        sut.registerEffect(\.textState, TextEffect())
        try await Task.sleep(for: .milliseconds(100))

        let stream = await sut.process(state: state, with: .counter(.increment))
        let results = await collect(stream)

        #expect(results.count == 1)
        guard case .counter(.increment) = results.first else {
            Issue.record("Expected .counter(.increment) but received \(results)")
            return
        }
    }

    @Test("GIVEN multiple distinct effects WHEN no effect matches action THEN returns empty stream")
    func sut_whenNoEffectMatchesAction_thenReturnsEmptyStream() async throws {
        let sut = BuilderEffects<RootState, RootActions>()
        sut.registerEffect(\.counterState, CounterEffect())
        sut.registerEffect(\.textState, TextEffect())
        try await Task.sleep(for: .milliseconds(100))

        let stream = await sut.process(state: RootState(), with: .counter(.increment))
        let results = await collect(stream)

        #expect(results.isEmpty)
    }

    @Test("GIVEN effects registered via fluent chaining WHEN process called THEN all registered effects are active")
    func sut_whenEffectsRegisteredFluently_thenAllAreActive() async throws {
        var state = RootState()
        state.counterState.count = 10
        let sut = BuilderEffects<RootState, RootActions>()
        sut
            .registerEffect(\.counterState, CounterEffect())
            .registerEffect(\.textState, TextEffect())
        try await Task.sleep(for: .milliseconds(100))

        let stream = await sut.process(state: state, with: .counter(.increment))
        let results = await collect(stream)

        #expect(results.count == 1)
    }
}

private extension BuilderEffectsTests {

    func makeSUT<E: Effect>(
        with effect: E,
        on keyPath: KeyPath<RootState, E.State> & Sendable
    ) async throws -> BuilderEffects<RootState, RootActions> where E.Action: StoreAction {
        let sut = BuilderEffects<RootState, RootActions>()
        sut.registerEffect(keyPath, effect)
        try await Task.sleep(for: .milliseconds(100))
        return sut
    }

    func collect(_ stream: AsyncStream<RootActions>) async -> [RootActions] {
        var results: [RootActions] = []
        for await action in stream { results.append(action) }
        return results
    }

    func collectText(_ stream: AsyncStream<TextActions>) async -> [TextActions] {
        var results: [TextActions] = []
        for await action in stream { results.append(action) }
        return results
    }
}
