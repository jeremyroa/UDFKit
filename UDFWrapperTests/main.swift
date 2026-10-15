import Foundation
import UDFKit

// ============================================================
// MARK: - Sub-actions per feature
// Each feature owns its own action type.
// The @StoreActionWrapper macro generates unwrapAs() and wrap() automatically.
// ============================================================

enum CounterAction: StoreAction {
    case increment
    case decrement
    case setCount(Int)
}

enum AnalyticsAction: StoreAction {
    case trackEvent(String)
    case reset
}

enum TimerAction: StoreAction {
    case start
    case tick
    case setTicks(Int)
}

enum PaymentAction: StoreAction {
    case pay
    case setProcessed(Int)
}

enum SearchAction: StoreAction {
    case search(String)
    case setResult(Int)
    case clear
}

// ============================================================
// MARK: - Root action with @StoreActionWrapper
// The macro generates StoreActionWrapper conformance:
//   - unwrapAs<T>() -> T?   (extracts the sub-action)
//   - wrap(_ action:) -> Self? (re-wraps a sub-action)
// ============================================================

@StoreActionWrapper
enum AppAction: StoreAction {
    case counter(CounterAction)
    case analytics(AnalyticsAction)
    case timer(TimerAction)
    case payment(PaymentAction)
    case search(SearchAction)
}

// ============================================================
// MARK: - States
// ============================================================

struct AppState: StoreState {
    var counter:   CounterState   = .init()
    var analytics: AnalyticsState = .init()
    var timer:     TimerState     = .init()
    var payment:   PaymentState   = .init()
    var search:    SearchState    = .init()
}

struct CounterState:   StoreState { var count: Int = 0 }
struct AnalyticsState: StoreState { var events: [String] = [] }
struct TimerState:     StoreState { var ticks: Int = 0 }
struct PaymentState:   StoreState { var processed: Int = 0 }
struct SearchState:    StoreState { var result: Int = 0 }

// ============================================================
// MARK: - Reducers per feature
// Each reducer operates ONLY on its own sub-state and sub-action.
// It has no knowledge of the root AppAction type.
// ============================================================

struct CounterReducer: Reducer {
    func reduce(oldState: CounterState, with action: CounterAction) -> CounterState {
        var s = oldState
        switch action {
        case .increment:        s.count += 1
        case .decrement:        s.count -= 1
        case .setCount(let n):  s.count = n
        }
        return s
    }
}

struct AnalyticsReducer: Reducer {
    func reduce(oldState: AnalyticsState, with action: AnalyticsAction) -> AnalyticsState {
        var s = oldState
        switch action {
        case .trackEvent(let e): s.events.append(e)
        case .reset:             s.events = []
        }
        return s
    }
}

struct TimerReducer: Reducer {
    func reduce(oldState: TimerState, with action: TimerAction) -> TimerState {
        var s = oldState
        switch action {
        case .start:            s.ticks = 0
        case .tick:             s.ticks += 1
        case .setTicks(let n):  s.ticks = n
        }
        return s
    }
}

struct PaymentReducer: Reducer {
    func reduce(oldState: PaymentState, with action: PaymentAction) -> PaymentState {
        var s = oldState
        switch action {
        case .pay:                   break // handled by effect
        case .setProcessed(let n):   s.processed = n
        }
        return s
    }
}

struct SearchReducer: Reducer {
    func reduce(oldState: SearchState, with action: SearchAction) -> SearchState {
        var s = oldState
        switch action {
        case .search:           break // handled by effect
        case .setResult(let n): s.result = n
        case .clear:            s.result = 0
        }
        return s
    }
}

// ============================================================
// MARK: - Effects per feature
// Each effect receives ONLY its own sub-action — no guards needed.
// The macro guarantees that unwrapAs() and wrap() work correctly.
// ============================================================

/// Increments the count with a delay. Only receives CounterAction.
actor CounterEffect: Effect {
    let delay: UInt64
    private(set) var callCount: Int = 0

    init(delay: UInt64 = 10_000_000) { self.delay = delay }

    func process(state: CounterState, with action: CounterAction) async -> CounterAction? {
        // No guard needed — only receives CounterAction thanks to the wrapper ✅
        guard case .increment = action else { return nil }
        callCount += 1
        try? await Task.sleep(nanoseconds: delay)
        guard !Task.isCancelled else { return nil }
        return .setCount(state.count + 1)
    }
}

/// Tracks analytics events. Only receives AnalyticsAction.
actor AnalyticsEffect: Effect {
    private(set) var trackedEvents: [String] = []

    func process(state: AnalyticsState, with action: AnalyticsAction) async -> AnalyticsAction? {
        // No guard needed — only receives AnalyticsAction ✅
        if case .trackEvent(let event) = action {
            trackedEvents.append(event)
        }
        return nil // analytics never emits actions back to the Store
    }
}

/// Emits N ticks. Only receives TimerAction.
actor MultiTickEffect: Effect {
    let tickCount: Int
    let delayBetween: UInt64

    init(tickCount: Int = 3, delayBetween: UInt64 = 5_000_000) {
        self.tickCount = tickCount
        self.delayBetween = delayBetween
    }

    func process(state: TimerState, with action: TimerAction) async -> AsyncStream<TimerAction> {
        // No guard needed — only receives TimerAction ✅
        guard case .start = action else { return .finished }
        let count = tickCount
        let delay = delayBetween
        return AsyncStream { continuation in
            let task = Task {
                for i in 1...count {
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(nanoseconds: delay)
                    continuation.yield(.setTicks(i))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Track without Cancel — only one payment processed at a time.
actor PaymentEffect: Effect {
    private var isProcessing = false
    private(set) var processedCount: Int = 0

    func process(state: PaymentState, with action: PaymentAction) async -> PaymentAction? {
        // No guard needed — only receives PaymentAction ✅
        guard case .pay = action else { return nil }
        guard !isProcessing else { return nil }

        isProcessing = true
        defer { isProcessing = false }

        try? await Task.sleep(nanoseconds: 100_000_000)
        guard !Task.isCancelled else { return nil }

        processedCount += 1
        return .setProcessed(processedCount)
    }
}

/// Track & Cancel — simulates a search bar.
actor SearchEffect: Effect {
    let searchDelay: UInt64
    private var currentTask: Task<Void, Never>?
    private(set) var startedCount: Int = 0
    private(set) var completedCount: Int = 0
    private(set) var cancelledCount: Int = 0

    init(searchDelay: UInt64 = 200_000_000) { self.searchDelay = searchDelay }

    func process(state: SearchState, with action: SearchAction) async -> SearchAction? {
        // No guard needed — only receives SearchAction ✅
        guard case .search(_) = action else { return nil }

        if let previous = currentTask {
            previous.cancel()
            cancelledCount += 1
        }

        startedCount += 1
        let delay = searchDelay
        let started = startedCount

        let task = Task<Void, Never> { try? await Task.sleep(nanoseconds: delay) }
        currentTask = task
        await task.value

        guard !task.isCancelled else { return nil }

        completedCount += 1
        return .setResult(started)
    }
}

// ============================================================
// MARK: - Helpers
// ============================================================

func waitForRegistration() async {
    try? await Task.sleep(nanoseconds: 50_000_000)
}

func header(_ title: String) {
    print("\n" + String(repeating: "─", count: 50))
    print("  \(title)")
    print(String(repeating: "─", count: 50))
}

func check(_ passed: Bool, _ msg: String) {
    print("  \(passed ? "✅" : "❌") \(msg)")
}

// ============================================================
// MARK: - Test 1 — StoreActionWrapper: unwrap and re-wrap
//
// Verifies that dispatching .counter(.increment):
// 1. The macro's unwrapAs() extracts CounterAction.increment
// 2. CounterEffect receives only CounterAction — not AppAction
// 3. The result CounterAction.setCount() is re-wrapped into AppAction
// 4. CounterReducer applies setCount to the state
// ============================================================

@MainActor
func testStoreActionWrapperUnwrapAndRewrap() async {
    header("TEST 1 — StoreActionWrapper: unwrap and re-wrap")

    let counterEffect = CounterEffect(delay: 10_000_000)

    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.counter, CounterReducer())
    } effects: {
        EffectScope(\.counter, counterEffect)
    }
    await waitForRegistration()

    print("  📊 Initial state: count=\(store.state.counter.count)")

    // Dispatching .counter(.increment):
    // → unwrapAs() extracts CounterAction.increment
    // → CounterEffect returns CounterAction.setCount(1)
    // → wrap() re-wraps into AppAction.counter(.setCount(1))
    // → CounterReducer applies setCount(1)
    await store.dispatch(.counter(.increment))

    let calls = await counterEffect.callCount
    print("  📦 effect callCount: \(calls)")
    print("  📊 Final state: count=\(store.state.counter.count)")

    check(calls == 1,                     "CounterEffect called once ← unwrap worked ✅")
    check(store.state.counter.count == 2, "count=2 (reducer+1, effect setCount(2)) ← re-wrap worked ✅")
}

// ============================================================
// MARK: - Test 2 — Feature isolation
//
// Dispatching .counter(.increment) should only trigger CounterEffect.
// AnalyticsEffect must receive nothing.
// Demonstrates the isolation provided by @StoreActionWrapper.
// ============================================================

@MainActor
func testFeatureIsolation() async {
    header("TEST 2 — Feature isolation")

    let counterEffect   = CounterEffect(delay: 10_000_000)
    let analyticsEffect = AnalyticsEffect()

    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.counter,   CounterReducer())
        ReducerScope(\.analytics, AnalyticsReducer())
    } effects: {
        EffectScope(\.counter,   counterEffect)
        EffectScope(\.analytics, analyticsEffect)
    }
    await waitForRegistration()

    await store.dispatch(.counter(.increment))

    let counterCalls    = await counterEffect.callCount
    let analyticsEvents = await analyticsEffect.trackedEvents

    print("  📦 counterEffect.callCount: \(counterCalls)")
    print("  📋 analyticsEffect.events:  \(analyticsEvents.count)")

    check(counterCalls == 1,       "CounterEffect responded to .counter(.increment) ✅")
    check(analyticsEvents.isEmpty, "AnalyticsEffect ignored .counter(.increment) ✅")
}

// ============================================================
// MARK: - Test 3 — Multiple features in sequence
//
// Dispatches actions to multiple features in sequence and verifies
// that each feature updates its own state independently.
// ============================================================

@MainActor
func testMultipleFeaturesInParallel() async {
    header("TEST 3 — Multiple features in sequence")

    let counterEffect   = CounterEffect(delay: 10_000_000)
    let analyticsEffect = AnalyticsEffect()

    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.counter,   CounterReducer())
        ReducerScope(\.analytics, AnalyticsReducer())
    } effects: {
        EffectScope(\.counter,   counterEffect)
        EffectScope(\.analytics, analyticsEffect)
    }
    await waitForRegistration()

    await store.dispatch(.counter(.increment))
    await store.dispatch(.analytics(.trackEvent("page_viewed")))
    await store.dispatch(.analytics(.trackEvent("button_tapped")))
    await store.dispatch(.counter(.increment))

    let tracked = await analyticsEffect.trackedEvents

    print("  📊 counter.count:    \(store.state.counter.count)")
    print("  📋 analytics.events: \(store.state.analytics.events)")

    check(store.state.counter.count == 4,          "Counter: 2 increments → count=4 (reducer+effect each time)")
    check(store.state.analytics.events.count == 2, "Analytics: 2 events recorded")
    check(tracked == ["page_viewed", "button_tapped"], "Events in correct order")
}

// ============================================================
// MARK: - Test 4 — MultiEmit with wrapper
//
// MultiTickEffect emits N TimerAction.setTicks() actions.
// Each one is re-wrapped into AppAction.timer(.setTicks())
// and dispatched to the Store. TimerReducer updates the state.
// ============================================================

@MainActor
func testMultiEmitWithWrapper() async {
    header("TEST 4 — MultiEmit with wrapper")

    let timerEffect = MultiTickEffect(tickCount: 5, delayBetween: 10_000_000)

    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.timer, TimerReducer())
    } effects: {
        EffectScope(\.timer, timerEffect)
    }
    await waitForRegistration()

    await store.dispatch(.timer(.start))

    print("  📊 timer.ticks: \(store.state.timer.ticks)")
    check(store.state.timer.ticks == 5, "5 ticks emitted and applied ← MultiEmit with wrapper ✅")
}

// ============================================================
// MARK: - Test 5 — Track without Cancel with wrapper
//
// PaymentEffect ignores .pay if already processing.
// PaymentAction sub-actions are handled independently from other features.
// ============================================================

@MainActor
func testTrackWithoutCancelWithWrapper() async {
    header("TEST 5 — Track without Cancel with wrapper")

    let paymentEffect = PaymentEffect()

    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.payment, PaymentReducer())
    } effects: {
        EffectScope(\.payment, paymentEffect)
    }
    await waitForRegistration()

    async let r1: () = store.dispatch(.payment(.pay))
    async let r2: () = store.dispatch(.payment(.pay))
    async let r3: () = store.dispatch(.payment(.pay))
    await (r1, r2, r3)

    let processed = await paymentEffect.processedCount
    print("  💳 payments processed: \(processed)")
    print("  📊 payment.processed:  \(store.state.payment.processed)")

    check(processed == 1,                     "Only 1 payment processed ✅")
    check(store.state.payment.processed == 1, "State updated correctly ✅")
}

// ============================================================
// MARK: - Test 6 — Track & Cancel with wrapper
//
// SearchEffect cancels the previous search when a new one arrives.
// SearchAction sub-actions are handled in isolation from other features.
// ============================================================

@MainActor
func testTrackAndCancelWithWrapper() async {
    header("TEST 6 — Track & Cancel with wrapper")

    let searchEffect = SearchEffect(searchDelay: 200_000_000)

    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.search, SearchReducer())
    } effects: {
        EffectScope(\.search, searchEffect)
    }
    await waitForRegistration()

    print("  ⌨️  5 fast keystrokes (every 30ms, search delay 200ms)...")

    var tasks: [Task<Void, Never>] = []
    for i in 1...5 {
        print("  keystroke \(i): dispatch .search(.search(\"query\(i)\"))")
        let t = Task { @MainActor in
            await store.dispatch(.search(.search("query\(i)")))
        }
        tasks.append(t)
        try? await Task.sleep(nanoseconds: 30_000_000)
    }
    for t in tasks { await t.value }

    let started   = await searchEffect.startedCount
    let completed = await searchEffect.completedCount
    let cancelled = await searchEffect.cancelledCount

    print("  🚀 started:    \(started)")
    print("  ✅ completed:  \(completed)")
    print("  ❌ cancelled:  \(cancelled)")

    check(started == 5,   "5 searches started ✅")
    check(completed == 1, "Only 1 completed — Track & Cancel worked ✅")
    check(cancelled == 4, "4 cancelled ✅")
}

// ============================================================
// MARK: - Test 7 — Isolated reducers without effects
//
// Verifies that reducers correctly receive sub-actions via the wrapper
// without needing any effects.
// ============================================================

@MainActor
func testIsolatedReducersWithWrapper() async {
    header("TEST 7 — Isolated reducers without effects")

    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.counter,   CounterReducer())
        ReducerScope(\.analytics, AnalyticsReducer())
        ReducerScope(\.timer,     TimerReducer())
    } effects: {}

    await store.dispatch(.counter(.increment))
    await store.dispatch(.counter(.increment))
    await store.dispatch(.counter(.decrement))
    await store.dispatch(.analytics(.trackEvent("test")))
    await store.dispatch(.analytics(.trackEvent("test2")))
    await store.dispatch(.timer(.tick))
    await store.dispatch(.timer(.tick))
    await store.dispatch(.timer(.tick))

    print("  📊 counter.count:    \(store.state.counter.count)")
    print("  📋 analytics.events: \(store.state.analytics.events)")
    print("  ⏱  timer.ticks:      \(store.state.timer.ticks)")

    check(store.state.counter.count == 1,                   "increment×2, decrement×1 → count=1 ✅")
    check(store.state.analytics.events.count == 2,          "2 events recorded ✅")
    check(store.state.analytics.events == ["test","test2"], "Events in correct order ✅")
    check(store.state.timer.ticks == 3,                     "3 ticks → ticks=3 ✅")
}

// ============================================================
// MARK: - Test 8 — Stress: multiple features simultaneously
//
// Dispatches actions to multiple features in sequence.
// Verifies that each feature's state is independent.
// ============================================================

@MainActor
func testStressMultipleFeatures() async {
    header("TEST 8 — Stress: multiple features simultaneously")

    let counterEffect   = CounterEffect(delay: 5_000_000)
    let analyticsEffect = AnalyticsEffect()

    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.counter,   CounterReducer())
        ReducerScope(\.analytics, AnalyticsReducer())
    } effects: {
        EffectScope(\.counter,   counterEffect)
        EffectScope(\.analytics, analyticsEffect)
    }
    await waitForRegistration()

    let start = Date()
    for i in 1...10 {
        await store.dispatch(.counter(.increment))
        await store.dispatch(.analytics(.trackEvent("event_\(i)")))
    }
    let elapsed = Date().timeIntervalSince(start)

    let counterCalls = await counterEffect.callCount
    let tracked      = await analyticsEffect.trackedEvents

    print("  ⏱  elapsed: \(String(format: "%.0f", elapsed * 1000))ms")
    print("  📊 counter.count:       \(store.state.counter.count)")
    print("  📦 counterEffect.calls: \(counterCalls)")
    print("  📋 analytics.events:    \(tracked.count)")

    check(counterCalls == 10,                           "10 calls to CounterEffect ✅")
    check(tracked.count == 10,                          "10 events in AnalyticsEffect ✅")
    check(store.state.analytics.events.count == 10,     "10 events in state ✅")
    check(elapsed < 2.0,                                "Completed in < 2s ✅")
}

// ============================================================
// MARK: - Entry point
// ============================================================

await testStoreActionWrapperUnwrapAndRewrap()
await testFeatureIsolation()
await testMultipleFeaturesInParallel()
await testMultiEmitWithWrapper()
await testTrackWithoutCancelWithWrapper()
await testTrackAndCancelWithWrapper()
await testIsolatedReducersWithWrapper()
await testStressMultipleFeatures()

print("\n" + String(repeating: "─", count: 50))
print("  DONE")
print(String(repeating: "─", count: 50))
