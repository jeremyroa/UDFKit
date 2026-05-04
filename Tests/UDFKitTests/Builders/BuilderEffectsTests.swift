import Testing
@testable import UDFKit

@Suite("BuilderEffects Tests")
struct BuilderEffectsTests {

    @Test("GIVEN CounterEffect WHEN count is below threshold THEN returns empty stream")
    func sut_whenCountBelowThreshold_thenReturnsEmptyStream() async throws {
        let sut = try await makeSUT(registering: Mocks.counterProcess, id: Mocks.counterId)

        let results = await collect(sut.process(state: RootState(), with: .counter(.increment)))

        #expect(results.isEmpty)
    }

    @Test("GIVEN CounterEffect WHEN count is at threshold THEN emits re-wrapped increment action")
    func sut_whenCountAtThreshold_thenEmitsReWrappedAction() async throws {
        var state = RootState()
        state.counterState.count = 10
        let sut = try await makeSUT(registering: Mocks.counterProcess, id: Mocks.counterId)

        let results = await collect(sut.process(state: state, with: .counter(.increment)))

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
        let sut = try await makeSUT(registering: Mocks.counterProcess, id: Mocks.counterId)

        let results = await collect(sut.process(state: RootState(), with: .text(.append("Test"))))

        #expect(results.isEmpty)
    }

    @Test("GIVEN TextEffect WHEN text is empty THEN emits re-wrapped greeting action")
    func sut_whenTextIsEmpty_thenEmitsGreetingAction() async throws {
        let sut = try await makeSUT(registering: Mocks.textProcess, id: Mocks.textId)

        let results = await collect(sut.process(state: RootState(), with: .text(.append("Test"))))

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
        let sut = try await makeSUT(registering: Mocks.textProcess, id: Mocks.textId)

        let results = await collect(sut.process(state: state, with: .text(.append("Test"))))

        #expect(results.isEmpty)
    }

    @Test("GIVEN BuilderEffects with self keyPath WHEN action matches THEN emits action directly without re-wrapping")
    func sut_whenSelfKeyPath_thenEmitsDirectly() async throws {
        let sut = BuilderEffects<TextState, TextActions>()
        sut.registerProcess(Mocks.textSelfProcess, id: Mocks.textSelfId)
        try await waitForRegistration()

        let results = await collectText(sut.process(state: TextState(), with: .append("Test")))

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

    @Test("GIVEN same process registered twice WHEN process called THEN emits only once")
    func sut_whenSameProcessRegisteredTwice_thenEmitsOnce() async throws {
        var state = RootState()
        state.counterState.count = 10
        let sut = BuilderEffects<RootState, RootActions>()
        sut.registerProcess(Mocks.counterProcess, id: Mocks.counterId)
        sut.registerProcess(Mocks.counterProcess, id: Mocks.counterId)
        try await waitForRegistration()

        let results = await collect(sut.process(state: state, with: .counter(.increment)))

        #expect(results.count == 1)
    }

    @Test("GIVEN multiple distinct processes WHEN action matches only one THEN only that process emits")
    func sut_whenOnlyOneProcessMatchesAction_thenOnlyThatProcessEmits() async throws {
        var state = RootState()
        state.counterState.count = 10
        let sut = BuilderEffects<RootState, RootActions>()
        sut.registerProcess(Mocks.counterProcess, id: Mocks.counterId)
        sut.registerProcess(Mocks.textProcess, id: Mocks.textId)
        try await waitForRegistration()

        let results = await collect(sut.process(state: state, with: .counter(.increment)))

        #expect(results.count == 1)
        guard case .counter(.increment) = results.first else {
            Issue.record("Expected .counter(.increment) but received \(results)")
            return
        }
    }

    @Test("GIVEN multiple distinct processes WHEN no process matches action THEN returns empty stream")
    func sut_whenNoProcessMatchesAction_thenReturnsEmptyStream() async throws {
        let sut = BuilderEffects<RootState, RootActions>()
        sut.registerProcess(Mocks.counterProcess, id: Mocks.counterId)
        sut.registerProcess(Mocks.textProcess, id: Mocks.textId)
        try await waitForRegistration()

        let results = await collect(sut.process(state: RootState(), with: .counter(.increment)))

        #expect(results.isEmpty)
    }
}

private extension BuilderEffectsTests {

    func makeSUT(
        registering process: @escaping @Sendable (RootState, RootActions) async -> AsyncStream<RootActions>,
        id: String
    ) async throws -> BuilderEffects<RootState, RootActions> {
        let sut = BuilderEffects<RootState, RootActions>()
        sut.registerProcess(process, id: id)
        try await waitForRegistration()
        return sut
    }

    func waitForRegistration() async throws {
        try await Task.sleep(for: .milliseconds(100))
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

    struct Mocks {
        static let counterId = "CounterEffect_counterState"
        static let textId = "TextEffect_textState"
        static let textSelfId = "TextEffect_self"

        static let counterProcess: @Sendable (RootState, RootActions) async -> AsyncStream<RootActions> = { state, action in
            AsyncStream { continuation in
                Task {
                    guard state.counterState.count >= 10,
                          case .counter(.increment) = action else {
                        continuation.finish()
                        return
                    }
                    continuation.yield(.counter(.increment))
                    continuation.finish()
                }
            }
        }

        static let textProcess: @Sendable (RootState, RootActions) async -> AsyncStream<RootActions> = { state, action in
            AsyncStream { continuation in
                Task {
                    guard state.textState.text.isEmpty,
                          case .text(.append) = action else {
                        continuation.finish()
                        return
                    }
                    continuation.yield(.text(.append("Hello!!")))
                    continuation.finish()
                }
            }
        }

        static let textSelfProcess: @Sendable (TextState, TextActions) async -> AsyncStream<TextActions> = { state, action in
            AsyncStream { continuation in
                Task {
                    guard state.text.isEmpty,
                          case .append = action else {
                        continuation.finish()
                        return
                    }
                    continuation.yield(.append("Hello!!"))
                    continuation.finish()
                }
            }
        }
    }
}
