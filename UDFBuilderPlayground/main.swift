import Foundation
import UDFKit

// ============================================================
// MARK: - Domain stubs
// ============================================================

struct AppState: StoreState {
    var counter: CounterState = .init()
    var analytics: AnalyticsState = .init()
    var timer: TimerState = .init()
    var payment: PaymentState = .init()
}

struct CounterState: StoreState { var count: Int = 0 }
struct AnalyticsState: StoreState { var lastEvent: String = "" }
struct TimerState: StoreState { var ticks: Int = 0 }
struct PaymentState: StoreState { var processed: Int = 0 }

enum AppAction: StoreAction {
    case increment
    case setCount(Int)
    case trackEvent(String)
    case tick
    case pay
    case noop
}

// ============================================================
// MARK: - AppReducer
// Necesario para el Store — maneja todas las actions root.
// ============================================================

struct AppReducer: Reducer {
    func reduce(oldState: AppState, with action: AppAction) -> AppState {
        var state = oldState
        switch action {
        case .increment:           state.counter.count += 1
        case .setCount(let n):     state.counter.count = n
        case .trackEvent(let e):   state.analytics.lastEvent = e
        case .tick:                state.timer.ticks += 1
        case .pay:                 state.payment.processed += 1
        case .noop:                break
        }
        return state
    }
}

// ============================================================
// MARK: - Test effects
// ============================================================

actor FastEffect: Effect {
    let delay: UInt64
    private(set) var callCount: Int = 0
    init(delay: UInt64 = 10_000_000) { self.delay = delay }
    func process(state: CounterState, with action: AppAction) async -> AppAction? {
        guard case .increment = action else { return nil }  // solo responde a .increment
        callCount += 1
        try? await Task.sleep(nanoseconds: delay)
        guard !Task.isCancelled else { return nil }
        return .setCount(state.count + 1)
    }
}

actor AnalyticsEffect: Effect {
    private(set) var trackedEvents: [String] = []
    func process(state: AnalyticsState, with action: AppAction) async -> AppAction? {
        if case .trackEvent(let event) = action { trackedEvents.append(event) }
        return nil  // siempre nil — analytics nunca emite actions
    }
}

actor MultiEmitEffect: Effect {
    let emitCount: Int
    let delayBetween: UInt64
    init(emitCount: Int = 3, delayBetween: UInt64 = 5_000_000) {
        self.emitCount = emitCount
        self.delayBetween = delayBetween
    }
    func process(state: TimerState, with action: AppAction) async -> AsyncStream<AppAction> {
        guard case .tick = action else { return .finished }
        let count = emitCount
        let delay = delayBetween
        return AsyncStream { continuation in
            let task = Task {
                for i in 1...count {
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(nanoseconds: delay)
                    continuation.yield(.setCount(i))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

actor SlowEffect: Effect {
    let delay: UInt64
    private(set) var startedCount: Int = 0
    private(set) var completedCount: Int = 0
    init(delay: UInt64 = 2_000_000_000) { self.delay = delay }
    func process(state: CounterState, with action: AppAction) async -> AppAction? {
        guard case .increment = action else { return nil }  // solo responde a .increment
        startedCount += 1
        try? await Task.sleep(nanoseconds: delay)
        guard !Task.isCancelled else { return nil }
        completedCount += 1
        return .setCount(99)
    }
}

actor PaymentEffect: Effect {
    private var isProcessing = false
    private(set) var processedCount: Int = 0
    func process(state: PaymentState, with action: AppAction) async -> AppAction? {
        guard case .pay = action else { return nil }
        guard !isProcessing else { return nil }
        isProcessing = true
        defer { isProcessing = false }
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard !Task.isCancelled else { return nil }
        processedCount += 1
        return .setCount(processedCount)
    }
}

actor SearchEffect: Effect {
    let searchDelay: UInt64
    private var currentTask: Task<Void, Never>?
    private(set) var startedCount: Int = 0
    private(set) var completedCount: Int = 0
    private(set) var cancelledCount: Int = 0
    init(searchDelay: UInt64 = 200_000_000) { self.searchDelay = searchDelay }
    func process(state: CounterState, with action: AppAction) async -> AppAction? {
        guard case .increment = action else { return nil }
        if let previous = currentTask { previous.cancel(); cancelledCount += 1 }
        startedCount += 1
        let delay = searchDelay
        let started = startedCount
        let task = Task<Void, Never> { try? await Task.sleep(nanoseconds: delay) }
        currentTask = task
        await task.value
        guard !task.isCancelled else { return nil }
        completedCount += 1
        return .setCount(started)
    }
}

actor FetchOnAppearEffect: Effect {
    let fetchDelay: UInt64
    private(set) var startedCount: Int = 0
    private(set) var completedCount: Int = 0
    init(fetchDelay: UInt64 = 300_000_000) { self.fetchDelay = fetchDelay }
    func process(state: CounterState, with action: AppAction) async -> AppAction? {
        guard case .increment = action else { return nil }
        startedCount += 1
        try? await Task.sleep(nanoseconds: fetchDelay)
        completedCount += 1
        return .setCount(completedCount)
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
// MARK: - Test 1 — Parallel execution
// ============================================================

@MainActor
func testParallelExecution() async {
    header("TEST 1 — Parallel execution")

    let e1 = FastEffect(delay: 50_000_000)
    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.self, AppReducer())
    } effects: {
        EffectScope(\.counter, e1)
    }
    await waitForRegistration()

    let start = Date()
    await store.dispatch(.increment)
    let elapsed = Date().timeIntervalSince(start)

    print("  ⏱  elapsed: \(String(format: "%.0f", elapsed * 1000))ms")
    print("  📦 state.counter.count: \(store.state.counter.count)")
    check(elapsed < 0.120, "Completed in < 120ms")
    check(store.state.counter.count == 2, "State updated: reducer(+1) + effect(.setCount(2))")
}

// ============================================================
// MARK: - Test 2 — Analytics returns nil
// ============================================================

@MainActor
func testAnalyticsReturnsNoActions() async {
    header("TEST 2 — Analytics returns nil")

    let analytics = AnalyticsEffect()
    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.self, AppReducer())
    } effects: {
        EffectScope(\.analytics, analytics)
    }
    await waitForRegistration()

    await store.dispatch(.trackEvent("home_viewed"))

    let tracked = await analytics.trackedEvents
    print("  📦 state unchanged: \(store.state.counter.count == 0)")
    print("  📋 tracked events: \(tracked)")
    check(store.state.counter.count == 0, "0 actions emitted — analytics does not emit")
    check(tracked == ["home_viewed"], "Event tracked correctly")
}

// ============================================================
// MARK: - Test 3 — MultiEmit: N actions per dispatch
// ============================================================

@MainActor
func testMultiEmitEffect() async {
    header("TEST 3 — MultiEmit: N actions per dispatch")

    let multi = MultiEmitEffect(emitCount: 5, delayBetween: 10_000_000)
    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.self, AppReducer())
    } effects: {
        EffectScope(\.timer, multi)
    }
    await waitForRegistration()

    await store.dispatch(.tick)

    print("  📦 state.counter.count: \(store.state.counter.count)")
    check(store.state.counter.count == 5, "Last .setCount(5) applied — 5 actions dispatched")
}

// ============================================================
// MARK: - Test 4 — Single effect dispatches correctly
// (DSL by design lists each effect once — no deduplication needed)
// ============================================================

@MainActor
func testSingleEffectDispatchesCorrectly() async {
    header("TEST 4 — Single effect dispatches correctly")

    let effect = FastEffect(delay: 10_000_000)
    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.self, AppReducer())
    } effects: {
        EffectScope(\.counter, effect)
    }
    await waitForRegistration()

    await store.dispatch(.increment)

    let calls = await effect.callCount
    print("  📦 effect callCount: \(calls)")
    print("  📦 state.counter.count: \(store.state.counter.count)")
    check(calls == 1,                       "Effect called exactly once")
    check(store.state.counter.count == 2,   "State updated: reducer(+1) + effect(.setCount(2))")
}

// ============================================================
// MARK: - Test 5 — Cancellation via onTermination
// ============================================================

@MainActor
func testCancellationViaOnTermination() async {
    header("TEST 5 — Cancellation via onTermination")

    let slow = SlowEffect(delay: 2_000_000_000)
    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.self, AppReducer())
    } effects: {
        EffectScope(\.counter, slow)
    }
    await waitForRegistration()

    let dispatchTask = Task { @MainActor in
        await store.dispatch(.increment)
    }

    try? await Task.sleep(nanoseconds: 100_000_000) // let effect start
    dispatchTask.cancel()
    try? await Task.sleep(nanoseconds: 300_000_000) // let cancellation propagate

    let started   = await slow.startedCount
    let completed = await slow.completedCount

    print("  🚀 startedCount:   \(started)")
    print("  ✋ completedCount: \(completed)")
    check(started >= 1,   "Effect started")
    check(completed == 0, "Effect cancelled before completing ← onTermination worked")
}

// ============================================================
// MARK: - Test 6 — Track without Cancel: duplicate payment ignored
// ============================================================

@MainActor
func testTrackWithoutCancelPreventsDuplicates() async {
    header("TEST 6 — Track without Cancel: duplicate payment ignored")

    let payment = PaymentEffect()
    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.self, AppReducer())
    } effects: {
        EffectScope(\.payment, payment)
    }
    await waitForRegistration()

    async let r1: () = store.dispatch(.pay)
    async let r2: () = store.dispatch(.pay)
    async let r3: () = store.dispatch(.pay)
    await (r1, r2, r3)

    let processed = await payment.processedCount
    print("  💳 payments processed: \(processed)")
    print("  📦 state.counter.count: \(store.state.counter.count)")
    check(processed == 1,               "Only 1 payment processed")
    check(store.state.counter.count == 1, "Only 1 action emitted")
}

// ============================================================
// MARK: - Test 7 — Multiple effects registered
// ============================================================

@MainActor
func testMultipleEffectsRegistered() async {
    header("TEST 7 — Multiple effects registered")

    let analytics = AnalyticsEffect()
    let counter = FastEffect(delay: 10_000_000)

    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.self, AppReducer())
    } effects: {
        EffectScope(\.analytics, analytics)
        EffectScope(\.counter, counter)
    }
    await waitForRegistration()

    await store.dispatch(.increment)

    let tracked = await analytics.trackedEvents
    let calls = await counter.callCount
    print("  📦 counter effect calls: \(calls)")
    print("  📋 analytics events: \(tracked.count)")
    check(calls == 1,          "Counter responded to .increment")
    check(tracked.isEmpty,     "Analytics did not respond to .increment")
    check(store.state.counter.count == 2, "State updated: reducer(+1) + effect(.setCount(2))")
}

// ============================================================
// MARK: - Test 8 — No effects: dispatch completes immediately
// ============================================================

@MainActor
func testNoEffectsDispatchesImmediately() async {
    header("TEST 8 — No effects: dispatch completes immediately")

    let store = Store<AppState,AppAction>(
        state: .init()) {
            ReducerScope(\.self, AppReducer())
        }

    let start = Date()
    await store.dispatch(.increment)
    let elapsed = Date().timeIntervalSince(start)

    print("  ⏱  elapsed: \(String(format: "%.0f", elapsed * 1000))ms")
    check(store.state.counter.count == 1, "State updated by reducer")
    check(elapsed < 0.100,               "Completed in < 100ms")
}

// ============================================================
// MARK: - Test 9 — Stress: 20 consecutive dispatches
// ============================================================

@MainActor
func testStress20ConsecutiveDispatches() async {
    header("TEST 9 — Stress: 20 consecutive dispatches")

    let effect = FastEffect(delay: 20_000_000)
    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.self, AppReducer())
    } effects: {
        EffectScope(\.counter, effect)
    }
    await waitForRegistration()

    let start = Date()
    for i in 1...20 {
        await store.dispatch(.increment)
        print("  dispatch \(String(format: "%02d", i)): count=\(store.state.counter.count)")
    }
    let elapsed = Date().timeIntervalSince(start)

    let calls = await effect.callCount
    print("  ⏱  total: \(String(format: "%.0f", elapsed * 1000))ms")
    check(calls == 20, "Effect called 20 times (got \(calls))")
    check(elapsed < 2.0, "Completed in < 2s")
}

// ============================================================
// MARK: - Test 10 — Track & Cancel: search bar
// ============================================================

@MainActor
func testTrackAndCancelSearchBar() async {
    header("TEST 10 — Track & Cancel: search bar")

    let search = SearchEffect(searchDelay: 200_000_000)
    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.self, AppReducer())
    } effects: {
        EffectScope(\.counter, search)
    }
    await waitForRegistration()

    print("  ⌨️  Simulating 5 fast keystrokes (every 30ms)...")

    var tasks: [Task<Void, Never>] = []
    for i in 1...5 {
        print("  keystroke \(i): dispatch .increment")
        let t = Task { @MainActor in await store.dispatch(.increment) }
        tasks.append(t)
        try? await Task.sleep(nanoseconds: 30_000_000)
    }
    for t in tasks { await t.value }

    let started   = await search.startedCount
    let completed = await search.completedCount
    let cancelled = await search.cancelledCount

    print("  🚀 searches started:    \(started)")
    print("  ✅ searches completed:  \(completed)")
    print("  ❌ searches cancelled:  \(cancelled)")
    check(started == 5,   "5 searches started")
    check(completed == 1, "Only 1 search completed — Track & Cancel worked ✅")
    check(cancelled == 4, "4 searches cancelled ✅")
}

// ============================================================
// MARK: - Test 11 — onAppear vs .task(): zombie Tasks
// ============================================================

@MainActor
func testOnAppearVsTaskModifier() async {
    header("TEST 11 — onAppear vs .task(): zombie Tasks")

    // ─── Case A: onAppear anti-pattern ───────────────────────
    print("\n  ── Case A: onAppear anti-pattern (no Track & Cancel) ──")

    let fetchEffect = FetchOnAppearEffect(fetchDelay: 200_000_000)

    print("  👁  View appears (1st time) → fetch started")
    let t1 = Task { await fetchEffect.process(state: CounterState(), with: .increment) }
    try? await Task.sleep(nanoseconds: 30_000_000)

    print("  👁  View appears (2nd time) → fetch started (1st still alive ⚠️)")
    let t2 = Task { await fetchEffect.process(state: CounterState(), with: .increment) }
    try? await Task.sleep(nanoseconds: 30_000_000)

    print("  👁  View appears (3rd time) → fetch started")
    let t3 = Task { await fetchEffect.process(state: CounterState(), with: .increment) }
    _ = await (t1.value, t2.value, t3.value)

    let fetchCompleted = await fetchEffect.completedCount
    check(fetchCompleted == 3, "⚠️  3 fetches completed — ANTI-PATTERN: zombie Tasks")

    // ─── Case B: correct with Store DSL + Track & Cancel ─────
    print("\n  ── Case B: correct with Store DSL + Track & Cancel ──")

    let search = SearchEffect(searchDelay: 200_000_000)
    let store = Store<AppState, AppAction>(state: .init()) {
        ReducerScope(\.self, AppReducer())
    } effects: {
        EffectScope(\.counter, search)
    }
    await waitForRegistration()

    print("  👁  View appears (1st time) → fetch started")
    let s1 = Task { @MainActor in await store.dispatch(.increment) }
    try? await Task.sleep(nanoseconds: 30_000_000)

    print("  👁  View appears (2nd time) → previous cancelled ✅")
    let s2 = Task { @MainActor in await store.dispatch(.increment) }
    try? await Task.sleep(nanoseconds: 30_000_000)

    print("  👁  View appears (3rd time) → previous cancelled ✅")
    let s3 = Task { @MainActor in await store.dispatch(.increment) }
    await (s1.value, s2.value, s3.value)

    let searchCompleted = await search.completedCount
    let searchCancelled = await search.cancelledCount

    print("  ✅ fetches completed: \(searchCompleted)")
    print("  ❌ fetches cancelled: \(searchCancelled)")
    check(searchCompleted == 1, "Only 1 fetch completed — Track & Cancel correct ✅")
    check(searchCancelled == 2, "2 fetches cancelled — no zombie Tasks ✅")

    print("\n  📌 Summary:")
    print("     onAppear → \(fetchCompleted) fetches completed (zombie Tasks ⚠️)")
    print("     .task()  → \(searchCompleted) fetch completed  (correct cancellation ✅)")
}

// ============================================================
// MARK: - Entry point
// ============================================================

await testParallelExecution()
await testAnalyticsReturnsNoActions()
await testMultiEmitEffect()
await testSingleEffectDispatchesCorrectly()
await testCancellationViaOnTermination()
await testTrackWithoutCancelPreventsDuplicates()
await testMultipleEffectsRegistered()
await testNoEffectsDispatchesImmediately()
await testStress20ConsecutiveDispatches()
await testTrackAndCancelSearchBar()
await testOnAppearVsTaskModifier()

print("\n" + String(repeating: "─", count: 50))
print("  DONE")
print(String(repeating: "─", count: 50))
