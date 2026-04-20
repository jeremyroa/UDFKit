import Foundation
import UDFKit

// MARK: - Benchmark infrastructure

func measure(_ label: String, iterations: Int = 1000, _ work: @Sendable () async -> Void) async {
    let clock = ContinuousClock()
    let elapsed = await clock.measure {
        for _ in 0 ..< iterations {
            await work()
        }
    }
    let totalMs = elapsed.components.attoseconds / 1_000_000_000_000_000
    let avgNs = elapsed.components.attoseconds / Int64(iterations) / 1_000_000_000
    let paddedLabel = label.padding(toLength: 60, withPad: " ", startingAt: 0)
    print("\(paddedLabel)  \(totalMs)ms total  \(avgNs)ns avg")
}

// MARK: - Benchmark state / actions / reducers

struct BenchState: StoreState {
    var count: Int = 0
    var text: String = ""
}

enum BenchAction: StoreAction {
    case increment
    case setText(String)
}

struct BenchReducer: Reducer {
    func reduce(oldState: BenchState, with action: BenchAction) -> BenchState {
        var state = oldState
        switch action {
        case .increment: state.count += 1
        case let .setText(text): state.text = text
        }
        return state
    }
}

struct NoOpEffect: Effect {
    func process(state: BenchState, with action: BenchAction) async -> BenchAction? {
        nil
    }
}

// MARK: - Run

Task { @MainActor in
    print("UDFKit Benchmark Suite")
    print(String(repeating: "-", count: 72))

    // 1. Single reducer — 10 000 sequential dispatches
    let store1 = Store(initialState: BenchState(), reducer: BenchReducer())
    await measure("Single reducer — 10 000 dispatches", iterations: 10000) {
        await store1.dispatch(.increment)
    }

    // 2. BuilderReducer with 1, 10, 50 sub-reducers — 1 000 dispatches each
    for count in [1, 10, 50] {
        var builder = BuilderReducer<BenchState, BenchAction>()
        for _ in 0 ..< count {
            builder = builder.registerReducer(\.self, BenchReducer())
        }
        let store = Store(initialState: BenchState(), reducer: builder)
        await measure("BuilderReducer \(count) sub-reducers — 1 000 dispatches") {
            await store.dispatch(.increment)
        }
    }

    // 3. BuilderEffects with 1, 10, 50 no-op effects — 1 000 dispatches each
    for count in [1, 10, 50] {
        let effects = BuilderEffects<BenchState, BenchAction>()
        for _ in 0 ..< count {
            effects.registerEffect(\.self, NoOpEffect())
        }
        try? await Task.sleep(for: .milliseconds(100))
        let store = Store(
            initialState: BenchState(),
            reducer: BenchReducer(),
            AnyEffect(effects)
        )
        await measure("BuilderEffects \(count) no-op effects — 1 000 dispatches") {
            await store.dispatch(.increment)
        }
    }

    // 4. Store dispatch latency — 1 000 sequential dispatches
    let store4 = Store(initialState: BenchState(), reducer: BenchReducer())
    await measure("Store dispatch latency — 1 000 sequential dispatches") {
        await store4.dispatch(.increment)
    }

    // 5. Concurrent dispatch — 100 tasks × 10 dispatches
    let store5 = Store(initialState: BenchState(), reducer: BenchReducer())
    let clock5 = ContinuousClock()
    let elapsed5 = await clock5.measure {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    for _ in 0 ..< 10 {
                        await store5.dispatch(.increment)
                    }
                }
            }
        }
    }
    let ms5 = elapsed5.components.attoseconds / 1_000_000_000_000_000
    let label5 = "Concurrent dispatch 100×10".padding(toLength: 60, withPad: " ", startingAt: 0)
    print("\(label5)  \(ms5)ms total  final count=\(store5.state.count)")

    print(String(repeating: "-", count: 72))
    exit(0)
}

RunLoop.main.run()
