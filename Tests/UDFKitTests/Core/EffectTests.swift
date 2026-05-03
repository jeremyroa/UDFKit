import Testing
@testable import UDFKit

@Suite("Effect")
struct EffectTests {
    // MARK: - Default stream wrapping `async -> Action?`

    @Test("default stream wraps single action result")
    func default_stream_wrapsActionResult() async {
        let effect = CounterEffect()
        var state = CounterState()
        state.count = 10
        let stream: AsyncStream<CounterActions> = effect.process(state: state, with: .increment)
        var collected: [CounterActions] = []
        for await action in stream { collected.append(action) }
        #expect(collected == [.increment])
    }

    @Test("default stream emits nothing when nil returned")
    func default_stream_emitsNothingForNil() async {
        let effect = CounterEffect()
        let stream: AsyncStream<CounterActions> = effect.process(state: CounterState(), with: .increment)
        var collected: [CounterActions] = []
        for await action in stream { collected.append(action) }
        #expect(collected.isEmpty)
    }

    // MARK: - Default `async -> Action?` reading from stream

    @Test("default async overload returns first element from stream")
    func default_async_returnsFirstFromStream() async {
        let effect = MultiActionCounterEffect()
        let result = await effect.process(state: CounterState(), with: .increment)
        #expect(result == .increment)
    }

    // MARK: - Multi-action streams

    @Test("multi-action stream emits all yielded actions")
    func multiAction_stream_emitsAllActions() async {
        let effect = MultiActionCounterEffect()
        let stream: AsyncStream<CounterActions> = effect.process(state: CounterState(), with: .increment)
        var collected: [CounterActions] = []
        for await action in stream { collected.append(action) }
        #expect(collected == [.increment, .increment])
    }

    // MARK: - Empty streams

    @Test("empty stream yields no actions")
    func empty_stream_yieldsNoActions() async {
        let effect = EmptyCounterEffect()
        let stream: AsyncStream<CounterActions> = effect.process(state: CounterState(), with: .increment)
        var collected: [CounterActions] = []
        for await action in stream { collected.append(action) }
        #expect(collected.isEmpty)
    }

    // MARK: - Cancellation

    @Test("default stream cancels inner task when consumer task is cancelled")
    func cancellation_innerTaskCancelledOnConsumerCancel() async {
        actor CancellationFlag {
            var wasCancelled = false
            func markCancelled() { wasCancelled = true }
        }

        let flag = CancellationFlag()

        struct LongRunningEffect: Effect {
            let flag: CancellationFlag

            func process(state: CounterState, with action: CounterActions) async -> CounterActions? {
                await withTaskCancellationHandler {
                    try? await Task.sleep(for: .seconds(10))
                    return nil
                } onCancel: {
                    Task { await flag.markCancelled() }
                }
            }
        }

        let task = Task {
            let stream: AsyncStream<CounterActions> = LongRunningEffect(flag: flag).process(
                state: CounterState(),
                with: .increment
            )
            for await _ in stream { }
        }

        try? await Task.sleep(for: .milliseconds(10))
        task.cancel()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(await flag.wasCancelled)
    }
}
