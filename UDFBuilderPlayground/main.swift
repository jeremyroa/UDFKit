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
// MARK: - Test effects
// ============================================================

/// One-shot effect with configurable delay. Returns .setCount(count + 1).
actor FastEffect: Effect {
    let delay: UInt64
    private(set) var callCount: Int = 0

    init(delay: UInt64 = 10_000_000) { self.delay = delay }

    func process(state: CounterState, with action: AppAction) async -> AppAction? {
        callCount += 1
        try? await Task.sleep(nanoseconds: delay)
        guard !Task.isCancelled else { return nil }
        return .setCount(state.count + 1)
    }
}

/// Analytics effect — always returns nil, records events internally.
actor AnalyticsEffect: Effect {
    private(set) var trackedEvents: [String] = []

    func process(state: AnalyticsState, with action: AppAction) async -> AppAction? {
        if case .trackEvent(let event) = action { trackedEvents.append(event) }
        return nil
    }
}

/// Emits N actions with a delay between each — simulates timer/WebSocket.
actor MultiEmitEffect: Effect {
    let emitCount: Int
    let delayBetween: UInt64

    init(emitCount: Int = 3, delayBetween: UInt64 = 5_000_000) {
        self.emitCount = emitCount
        self.delayBetween = delayBetween
    }

    func process(state: TimerState, with action: AppAction) async -> AsyncStream<AppAction> {
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

/// Slow effect for cancellation tests — tracks start/complete counts.
actor SlowEffect: Effect {
    let delay: UInt64
    private(set) var startedCount: Int = 0
    private(set) var completedCount: Int = 0

    init(delay: UInt64 = 2_000_000_000) { self.delay = delay }

    func process(state: CounterState, with action: AppAction) async -> AppAction? {
        startedCount += 1
        try? await Task.sleep(nanoseconds: delay)
        guard !Task.isCancelled else { return nil }
        completedCount += 1
        return .setCount(99)
    }
}

/// Track without Cancel — only one payment processed at a time.
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

/// Track & Cancel — simulates a search bar.
/// Each new search cancels the previous one.
/// Tracks how many searches started and how many completed.
///
/// Key: checks `task.isCancelled` (the internal sleep handle),
/// NOT `Task.isCancelled` (the calling Task — that one is never cancelled).
actor SearchEffect: Effect {
    let searchDelay: UInt64
    private var currentTask: Task<Void, Never>?   // Track & Cancel handle
    private(set) var startedCount: Int = 0
    private(set) var completedCount: Int = 0
    private(set) var cancelledCount: Int = 0

    init(searchDelay: UInt64 = 200_000_000) { self.searchDelay = searchDelay } // 200ms

    func process(state: CounterState, with action: AppAction) async -> AppAction? {
        guard case .increment = action else { return nil }

        // Track & Cancel: cancel the previous search before starting a new one
        if let previous = currentTask {
            previous.cancel()
            cancelledCount += 1
        }

        startedCount += 1
        let delay = searchDelay
        let started = startedCount

        // Store the handle — this is what the next call will cancel
        let task = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: delay)
        }
        currentTask = task

        // Release the actor while sleeping
        await task.value

        // ✅ Check task.isCancelled (the internal sleep handle)
        // NOT Task.isCancelled (the Task calling process — that one is never cancelled)
        // When process2 calls previous.cancel() → task.isCancelled = true
        // → sleep returns immediately → we arrive here with task.isCancelled = true
        guard !task.isCancelled else { return nil }

        completedCount += 1
        return .setCount(started)
    }
}

/// Simulates the onAppear anti-pattern: launches Tasks that are never cancelled.
/// Each "view appearance" starts a fetch that always runs to completion.
actor FetchOnAppearEffect: Effect {
    let fetchDelay: UInt64
    private(set) var startedCount: Int = 0
    private(set) var completedCount: Int = 0
    // No Task? handle — no Track & Cancel — every fetch runs uncontrolled

    init(fetchDelay: UInt64 = 300_000_000) { self.fetchDelay = fetchDelay } // 300ms

    func process(state: CounterState, with action: AppAction) async -> AppAction? {
        guard case .increment = action else { return nil }

        startedCount += 1
        // No cooperative cancellation — fetch always completes
        try? await Task.sleep(nanoseconds: fetchDelay)
        // ⚠️ Does not check Task.isCancelled — always completes even if no one is listening
        completedCount += 1
        return .setCount(completedCount)
    }
}

// ============================================================
// MARK: - Helpers
// ============================================================

func collect(
    _ stream: AsyncStream<AppAction>,
    timeout: UInt64 = 2_000_000_000
) async -> [AppAction] {
    var collected: [AppAction] = []
    let timeoutTask = Task { try? await Task.sleep(nanoseconds: timeout) }
    for await action in stream {
        collected.append(action)
        if timeoutTask.isCancelled { break }
    }
    timeoutTask.cancel()
    return collected
}

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
//
// A single 50ms effect should complete in ~50ms.
// Verifies that withTaskGroup runs effects concurrently.
// ============================================================

@MainActor
func testParallelExecution() async {
    header("TEST 1 — Parallel execution")

    let builder = BuilderEffects<AppState, AppAction>()
    let e1 = FastEffect(delay: 50_000_000)

    builder.registerEffect(\.counter, e1)
    await waitForRegistration()

    let start = Date()
    let stream: AsyncStream<AppAction> = await builder.process(state: AppState(), with: .increment)
    let collected = await collect(stream)
    let elapsed = Date().timeIntervalSince(start)

    print("  ⏱  elapsed: \(String(format: "%.0f", elapsed * 1000))ms")
    print("  📦 actions received: \(collected.count)")
    check(elapsed < 0.120, "Completed in < 120ms")
    check(collected.count == 1, "1 action received")
}

// ============================================================
// MARK: - Test 2 — Analytics returns nil
//
// Analytics performs side effects but never emits actions to the Store.
// ============================================================

@MainActor
func testAnalyticsReturnsNoActions() async {
    header("TEST 2 — Analytics returns nil")

    let builder = BuilderEffects<AppState, AppAction>()
    let analytics = AnalyticsEffect()

    builder.registerEffect(\.analytics, analytics)
    await waitForRegistration()

    let stream: AsyncStream<AppAction> = await builder.process(
        state: AppState(), with: .trackEvent("home_viewed")
    )
    let collected = await collect(stream)
    let tracked = await analytics.trackedEvents

    print("  📦 actions received: \(collected.count)")
    print("  📋 tracked events: \(tracked)")
    check(collected.isEmpty, "0 actions — analytics does not emit")
    check(tracked == ["home_viewed"], "Event tracked correctly")
}

// ============================================================
// MARK: - Test 3 — MultiEmit: N actions per dispatch
//
// An effect can emit multiple actions from a single dispatch.
// Verifies count and order.
// ============================================================

@MainActor
func testMultiEmitEffect() async {
    header("TEST 3 — MultiEmit: N actions per dispatch")

    let builder = BuilderEffects<AppState, AppAction>()
    let multi = MultiEmitEffect(emitCount: 5, delayBetween: 10_000_000)

    builder.registerEffect(\.timer, multi)
    await waitForRegistration()

    let stream: AsyncStream<AppAction> = await builder.process(state: AppState(), with: .tick)
    let collected = await collect(stream)

    print("  📦 actions received: \(collected)")
    check(collected.count == 5, "5 actions received")
    check(collected == (1...5).map { .setCount($0) }, "Actions received in correct order")
}

// ============================================================
// MARK: - Test 4 — Duplicate registration is idempotent
//
// Registering the same effect 3 times must behave the same
// as registering it once.
// ============================================================

@MainActor
func testDuplicateRegistrationIsIdempotent() async {
    header("TEST 4 — Duplicate registration is idempotent")

    let builder = BuilderEffects<AppState, AppAction>()
    let effect = FastEffect(delay: 10_000_000)

    builder
        .registerEffect(\.counter, effect)
        .registerEffect(\.counter, effect)
        .registerEffect(\.counter, effect)

    await waitForRegistration()

    let stream: AsyncStream<AppAction> = await builder.process(state: AppState(), with: .increment)
    let collected = await collect(stream)

    print("  📦 actions received: \(collected.count) (registered 3 times)")
    check(collected.count == 1, "Only 1 action even though registered 3 times")
}

// ============================================================
// MARK: - Test 5 — Cancellation via onTermination
//
// When the stream consumer disappears, onTermination must
// cancel the internal Task. SlowEffect (2s) must NOT complete.
// ============================================================

@MainActor
func testCancellationViaOnTermination() async {
    header("TEST 5 — Cancellation via onTermination")

    let builder = BuilderEffects<AppState, AppAction>()
    let slow = SlowEffect(delay: 2_000_000_000) // 2 seconds

    builder.registerEffect(\.counter, slow)
    await waitForRegistration()

    let consumerTask = Task {
        let stream: AsyncStream<AppAction> = await builder.process(
            state: AppState(), with: .increment
        )
        for await _ in stream { break } // consume 0 items and exit
    }

    try? await Task.sleep(nanoseconds: 100_000_000) // let the effect start
    consumerTask.cancel()
    try? await Task.sleep(nanoseconds: 300_000_000) // let cancellation propagate

    let started = await slow.startedCount
    let completed = await slow.completedCount

    print("  🚀 startedCount:   \(started)")
    print("  ✋ completedCount: \(completed)")
    check(started >= 1,   "Effect started")
    check(completed == 0, "Effect cancelled before completing ← onTermination worked")
}

// ============================================================
// MARK: - Test 6 — Track without Cancel: duplicate payment ignored
//
// If the user taps "Pay" 3 times in a row, only 1 payment
// should be processed. The rest are ignored.
// ============================================================

@MainActor
func testTrackWithoutCancelPreventsDuplicates() async {
    header("TEST 6 — Track without Cancel: duplicate payment ignored")

    let builder = BuilderEffects<AppState, AppAction>()
    let payment = PaymentEffect()

    builder.registerEffect(\.payment, payment)
    await waitForRegistration()

    async let r1 = collect(await builder.process(state: AppState(), with: .pay))
    async let r2 = collect(await builder.process(state: AppState(), with: .pay))
    async let r3 = collect(await builder.process(state: AppState(), with: .pay))

    let (c1, c2, c3) = await (r1, r2, r3)
    let totalActions = c1.count + c2.count + c3.count
    let processed = await payment.processedCount

    print("  💳 payments processed: \(processed)")
    print("  📦 total actions:      \(totalActions)")
    check(processed == 1,    "Only 1 payment processed")
    check(totalActions == 1, "Only 1 action emitted in total")
}

// ============================================================
// MARK: - Test 7 — Fluent chaining registers all effects
//
// .registerEffect().registerEffect() must register both effects.
// ============================================================

@MainActor
func testFluentChainingRegistersAllEffects() async {
    header("TEST 7 — Fluent chaining registers all effects")

    let analytics = AnalyticsEffect()
    let counter = FastEffect(delay: 10_000_000)

    let builder = BuilderEffects<AppState, AppAction>()
        .registerEffect(\.analytics, analytics)
        .registerEffect(\.counter, counter)

    await waitForRegistration()

    let stream: AsyncStream<AppAction> = await builder.process(
        state: AppState(), with: .increment
    )
    let collected = await collect(stream)
    let tracked = await analytics.trackedEvents

    print("  📦 actions received: \(collected.count)")
    print("  📋 analytics events: \(tracked.count)")
    check(collected.count == 1, "Counter responded to .increment")
    check(tracked.isEmpty,      "Analytics did not respond to .increment")
}

// ============================================================
// MARK: - Test 8 — Empty builder returns finished stream
//
// With no effects registered, the stream finishes immediately.
// ============================================================

@MainActor
func testEmptyBuilderReturnsFinishedStream() async {
    header("TEST 8 — Empty builder returns finished stream")

    let builder = BuilderEffects<AppState, AppAction>()

    let start = Date()
    let stream: AsyncStream<AppAction> = await builder.process(
        state: AppState(), with: .increment
    )
    let collected = await collect(stream, timeout: 500_000_000)
    let elapsed = Date().timeIntervalSince(start)

    print("  ⏱  elapsed: \(String(format: "%.0f", elapsed * 1000))ms")
    print("  📦 actions received: \(collected.count)")
    check(collected.isEmpty, "0 actions — empty builder")
    check(elapsed < 0.100,   "Stream finished in < 100ms")
}

// ============================================================
// MARK: - Test 9 — Stress: 20 consecutive dispatches
//
// Verifies throughput under sustained load.
// ============================================================

@MainActor
func testStress20ConsecutiveDispatches() async {
    header("TEST 9 — Stress: 20 consecutive dispatches")

    let builder = BuilderEffects<AppState, AppAction>()
    let effect = FastEffect(delay: 20_000_000)

    builder.registerEffect(\.counter, effect)
    await waitForRegistration()

    let start = Date()
    var totalActions = 0

    for i in 1...20 {
        let stream: AsyncStream<AppAction> = await builder.process(
            state: AppState(), with: .increment
        )
        let collected = await collect(stream)
        totalActions += collected.count
        print("  dispatch \(String(format: "%02d", i)): \(collected.count) action(s)")
    }

    let elapsed = Date().timeIntervalSince(start)

    print("  ⏱  total: \(String(format: "%.0f", elapsed * 1000))ms")
    print("  📊 average per dispatch: \(String(format: "%.1f", elapsed * 1000 / 20))ms")
    check(totalActions == 20, "20 dispatches → 20 actions (got \(totalActions))")
    check(elapsed < 2.0,      "Completed in < 2s")
}

// ============================================================
// MARK: - Test 10 — Track & Cancel: search bar
//
// The user types quickly: "s", "sw", "swi", "swif", "swift".
// Each keystroke fires a new dispatch.
// Only the last search should complete — the previous ones must be cancelled.
//
// Key: each stream is consumed in an independent background Task
// so keystrokes overlap in time — just like in a real search bar.
//
// Without Track & Cancel: 5 searches run in parallel → race condition.
// With Track & Cancel: only 1 search completes → deterministic result.
//
// Expected result:
//   ✅ completedCount == 1  (only the last search completed)
//   ✅ cancelledCount == 4  (the previous 4 were cancelled)
// ============================================================

@MainActor
func testTrackAndCancelSearchBar() async {
    header("TEST 10 — Track & Cancel: search bar")

    let builder = BuilderEffects<AppState, AppAction>()
    let search = SearchEffect(searchDelay: 200_000_000) // 200ms per search

    builder.registerEffect(\.counter, search)
    await waitForRegistration()

    print("  ⌨️  Simulating 5 fast keystrokes (every 30ms)...")
    print("  ℹ️  Search: 200ms · Keystroke interval: 30ms → always overlapping")

    // Each stream is consumed in an independent background Task.
    // This allows the next keystroke to arrive WHILE the previous one
    // is still running — just like a real search bar.
    var backgroundTasks: [Task<[AppAction], Never>] = []

    for i in 1...5 {
        print("  keystroke \(i): dispatch .increment")
        let stream: AsyncStream<AppAction> = await builder.process(
            state: AppState(), with: .increment
        )
        // Consume in background — don't wait for it to finish before the next keystroke
        let t = Task { await collect(stream, timeout: 500_000_000) }
        backgroundTasks.append(t)
        try? await Task.sleep(nanoseconds: 30_000_000) // 30ms between keystrokes
    }

    // Wait for all background Tasks to finish
    var allCollected: [AppAction] = []
    for t in backgroundTasks {
        allCollected.append(contentsOf: await t.value)
    }

    let started   = await search.startedCount
    let completed = await search.completedCount
    let cancelled = await search.cancelledCount

    print("  🚀 searches started:    \(started)")
    print("  ✅ searches completed:  \(completed)")
    print("  ❌ searches cancelled:  \(cancelled)")
    print("  📦 actions received:    \(allCollected.count)")

    check(started == 5,   "5 searches started (one per keystroke)")
    check(completed == 1, "Only 1 search completed — the last one ✅")
    check(cancelled == 4, "4 searches cancelled — Track & Cancel worked ✅")
}

// ============================================================
// MARK: - Test 11 — onAppear vs .task(): zombie Tasks
//
// onAppear launches Tasks that stay alive even after the view disappears.
// If the user navigates away and back 3 times, 3 fetches run concurrently.
//
// Key: same as the previous test, each fetch is consumed in background
// to simulate the real overlap that happens in the app.
//
// Expected result (anti-pattern — onAppear):
//   ⚠️ completedCount == 3  (all 3 fetches completed — zombie Tasks)
//
// Expected result (correct — .task() with Track & Cancel):
//   ✅ completedCount == 1  (only the last fetch completed)
//   ✅ cancelledCount == 2  (the previous 2 were cancelled)
// ============================================================

@MainActor
func testOnAppearVsTaskModifier() async {
    header("TEST 11 — onAppear vs .task(): zombie Tasks")

    // ─── Case A: onAppear anti-pattern ───────────────────────
    // Simulates: the user enters the screen 3 times.
    // onAppear fires a fetch each time without cancelling the previous one.
    // In the real app: onAppear { Task { store.dispatch(.fetch) } }
    // Each fetch runs in parallel — none knows about the others.
    print("\n  ── Case A: onAppear anti-pattern (no Track & Cancel) ──")

    let fetchEffect = FetchOnAppearEffect(fetchDelay: 200_000_000) // 200ms

    print("  👁  View appears (1st time) → fetch started")
    let t1 = Task { await fetchEffect.process(state: CounterState(), with: .increment) }
    try? await Task.sleep(nanoseconds: 30_000_000) // user navigates away and back

    print("  👁  View appears (2nd time) → fetch started (1st still alive ⚠️)")
    let t2 = Task { await fetchEffect.process(state: CounterState(), with: .increment) }
    try? await Task.sleep(nanoseconds: 30_000_000)

    print("  👁  View appears (3rd time) → fetch started (previous 2 still alive ⚠️)")
    let t3 = Task { await fetchEffect.process(state: CounterState(), with: .increment) }

    _ = await (t1.value, t2.value, t3.value) // wait for all 3 to finish

    let fetchStarted   = await fetchEffect.startedCount
    let fetchCompleted = await fetchEffect.completedCount

    print("  🚀 fetches started:    \(fetchStarted)")
    print("  ✅ fetches completed:  \(fetchCompleted)")
    check(fetchCompleted == 3, "⚠️  3 fetches completed — ANTI-PATTERN: zombie Tasks")

    // ─── Case B: correct with Track & Cancel ─────────────────
    // Simulates: the user enters the screen 3 times.
    // .task() cancels the previous fetch when the view disappears.
    // SearchEffect cancels the previous Task when a new one arrives.
    print("\n  ── Case B: correct with Track & Cancel ──")

    let builder = BuilderEffects<AppState, AppAction>()
    let search = SearchEffect(searchDelay: 200_000_000) // same delay

    builder.registerEffect(\.counter, search)
    await waitForRegistration()

    print("  👁  View appears (1st time) → fetch started")
    let s1: AsyncStream<AppAction> = await builder.process(state: AppState(), with: .increment)
    let b1 = Task { await collect(s1, timeout: 500_000_000) }  // consume in background
    try? await Task.sleep(nanoseconds: 30_000_000)

    print("  👁  View appears (2nd time) → previous fetch cancelled, new one started ✅")
    let s2: AsyncStream<AppAction> = await builder.process(state: AppState(), with: .increment)
    let b2 = Task { await collect(s2, timeout: 500_000_000) }  // consume in background
    try? await Task.sleep(nanoseconds: 30_000_000)

    print("  👁  View appears (3rd time) → previous fetch cancelled, new one started ✅")
    let s3: AsyncStream<AppAction> = await builder.process(state: AppState(), with: .increment)
    let b3 = Task { await collect(s3, timeout: 500_000_000) }  // consume in background

    // Wait for all to finish
    _ = await (b1.value, b2.value, b3.value)

    let searchStarted   = await search.startedCount
    let searchCompleted = await search.completedCount
    let searchCancelled = await search.cancelledCount

    print("  🚀 fetches started:    \(searchStarted)")
    print("  ✅ fetches completed:  \(searchCompleted)")
    print("  ❌ fetches cancelled:  \(searchCancelled)")

    check(searchCompleted == 1, "Only 1 fetch completed — Track & Cancel correct ✅")
    check(searchCancelled == 2, "2 fetches cancelled — no zombie Tasks ✅")

    // ─── Summary ─────────────────────────────────────────────
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
await testDuplicateRegistrationIsIdempotent()
await testCancellationViaOnTermination()
await testTrackWithoutCancelPreventsDuplicates()
await testFluentChainingRegistersAllEffects()
await testEmptyBuilderReturnsFinishedStream()
await testStress20ConsecutiveDispatches()
await testTrackAndCancelSearchBar()
await testOnAppearVsTaskModifier()

print("\n" + String(repeating: "─", count: 50))
print("  DONE")
print(String(repeating: "─", count: 50))
