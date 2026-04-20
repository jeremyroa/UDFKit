# UDFKit v2 Improvement Plan

## Context

UDFKit v1 delivered a self-contained Swift Package with DDD folder structure, Swift Testing, and SPM-native linting. This plan addresses correctness issues, modernization to iOS 17/Swift 6, and quality improvements discovered after shipping v1. No new user-facing features are included here — see `features-roadmap.md` for those.

---

## Task 1 — Fix Version Claims in README and Config

**Problem:** `README.md` states "Swift 5.9+" and "Xcode 15+". `Package.swift` uses `swift-tools-version: 6.0`, which requires Swift 6.0 and Xcode 16+. `.swiftformat` has `--swiftversion 5.9`, so SwiftFormat applies Swift 5.9 syntax rules to a Swift 6 codebase.

**Changes:**
- `README.md`: Update requirements section to "Swift 6.0+, Xcode 16+"
- `.swiftformat`: Change `--swiftversion 5.9` → `--swiftversion 6.0`
- `README.md`: Clarify that the package uses strict concurrency (`Sendable`, `@MainActor`) and requires a Swift 6-compatible toolchain

**Files:**
- `README.md`
- `.swiftformat`

**Verification:** `make format-check` passes; README requirements section is accurate.

---

## Task 2 — iOS 17 / macOS 14 Minimum Target Migration

**Problem:** The library uses `ObservableObject` + `@Published` (UIKit/Combine bridging pattern) and `EnvironmentValues` extension with a custom key. iOS 17 introduces `@Observable` (Observation framework), which is simpler, has no Combine dependency, and enables compile-time observation tracking instead of runtime KVO.

**Changes:**

### 2.1 — Bump platform targets in `Package.swift`

```swift
platforms: [.iOS(.v17), .macOS(.v14)]
```

### 2.2 — Rewrite `Store` with `@Observable`

`Sources/UDFKit/Core/Store.swift`

- Remove `ObservableObject` conformance and `@Published` on `state`
- Add `@Observable` macro annotation on `Store`
- Remove `extension Store: @unchecked Sendable {}` — `@Observable` classes are `Sendable` by design when all mutations are `@MainActor`-isolated
- Mark `Store` with `@MainActor` explicitly to satisfy Swift 6 concurrency (all `dispatch` calls are already `@MainActor`)

```swift
@Observable
@MainActor
public final class Store<State: StoreState, Action: StoreAction> {
    public private(set) var state: State
    // ...
}
```

### 2.3 — Replace `Store.environment()` with `@Entry`-based environment injection

`Sources/UDFKit/Core/Store.swift`

The current `Store.environment()` returns `Binding<Store>` as a workaround for `ObservableObject`. With `@Observable`, `Store` can be passed directly as an environment value without a `Binding` wrapper.

Remove `Store.environment()` (breaking change — document in CHANGELOG). Consumers declare their own typed key using the iOS 17 `@Entry` macro:

```swift
// Declared once in the consumer app — not in UDFKit, because Store is generic
extension EnvironmentValues {
    @Entry var appStore: Store<AppState, AppAction>? = nil
}

// Root view injects
ContentView()
    .environment(\.appStore, store)

// Any descendant reads
@Environment(\.appStore) private var store
```

The dispatch/reducer/effect pipeline is unchanged. Document the `@Entry` pattern in README.

### 2.4 — Preserve `Store.binding(_:set:)` through the `@Observable` migration

`Store.binding(_:set:)` is the single canonical way to create dispatch-backed bindings and must be preserved unchanged. With `@Observable`, the `Binding(get:set:)` construction continues to work — the `get` closure is automatically tracked by the observation system, so bindings remain reactive without `@Published`.

The only internal change is that `state` loses its `@Published` annotation. The call site is identical in v1 and v2:

```swift
// v1 and v2 — same call site, no migration required
TextField("Name", text: store.binding(\.name, set: { .setName($0) }))
```

Relax the key path constraint from `WritableKeyPath` to `KeyPath` — the getter only reads state; the setter dispatches an action, never writes to the key path directly:

```swift
public func binding<Value>(
    _ keyPath: KeyPath<State, Value>,   // KeyPath, not WritableKeyPath
    set: @escaping (Value) -> Action
) -> Binding<Value>
```

This is a non-breaking change: `WritableKeyPath` is a subtype of `KeyPath`, so all existing call sites continue to compile.

Add a test confirming the binding routes through the full dispatch pipeline after the `@Observable` migration:

```swift
@Test("binding dispatches action through full pipeline")
func binding_routes_through_dispatch_pipeline() async throws {
    let store = Store(initialState: StateMock(someValue: false, asyncValue: []), reducer: MockReducer())
    let binding = store.binding(\.someValue, set: { .changeSomeValue($0) })
    binding.wrappedValue = true
    try await Task.sleep(for: .milliseconds(50))
    #expect(store.state.someValue == true)
}
```

**Files:**
- `Package.swift`
- `Sources/UDFKit/Core/Store.swift`
- `Tests/UDFKitTests/Core/StoreTests.swift`
- `README.md` (update Quick Start and Store API sections; document `@Entry` pattern and `store.binding` as the single binding style)

**Verification:** `swift build` succeeds. All existing `binding_*` tests pass. `@MainActor` isolation may require `await MainActor.run { }` in tests after the `@Observable` migration.

---

## Task 3 — Swift 6 Concurrency Audit

**Problem:** The codebase compiles with strict concurrency but uses `@unchecked Sendable` escape hatches in two places. These are correct but should be documented and reduced where possible after the iOS 17 migration.

### 3.1 — Audit `@unchecked Sendable` usages

**`Store: @unchecked Sendable`** (`Sources/UDFKit/Core/Store.swift`)
- Safe invariant: all `state` mutations go through `@MainActor dispatch`
- After Task 2, `@Observable @MainActor Store` no longer needs `@unchecked Sendable` — remove it

**`BuilderEffects.BoxedEffect: @unchecked Sendable`** (`Sources/UDFKit/Builders/BuilderEffects.swift`)
- Safe invariant: `BoxedEffect` is created in a `nonisolated` context before crossing the actor boundary via `Task`; the `process` closure captures only `Sendable` values after boxing
- This escape hatch is still necessary — add an inline comment explaining the invariant so future contributors don't accidentally break it

### 3.2 — Audit fire-and-forget `Task` in `BuilderEffects.registerEffect`

`Sources/UDFKit/Builders/BuilderEffects.swift`

```swift
Task { [weak self] in
    await self?.storeEffect(boxed)
}
```

- This `Task` has no handle — it cannot be cancelled
- If `registerEffect` is called many times before the actor processes them, effects registered concurrently could be lost if `self` deallocates between scheduling and execution
- **Action:** Wrap the `Task` handle in an `@unchecked Sendable` wrapper or switch to `Task.detached` with explicit capture. At minimum, add a comment explaining the trade-off.
- **Consider:** Making `registerEffect` `async` and calling `await storeEffect(boxed)` directly, eliminating the unstructured Task entirely. This is a breaking API change — evaluate for v2.

### 3.3 — Verify `Store.intercept` capture safety

`Sources/UDFKit/Core/Store.swift`

```swift
group.addTask { [weak self] in
    let dispatcher: @Sendable (Action) async -> Void = { [weak self] in
        await self?.dispatch($0)
    }
    return await effect.wrapped.process(state: currentState, with: action, dispatch: dispatcher)
}
```

- `currentState` is captured by value (struct copy) — safe
- `[weak self]` in TaskGroup: if `Store` deallocates mid-task, the dispatcher silently no-ops — this is intentional but should be tested
- Add test case: dispatch action, deallocate store mid-effect, verify no crash

### 3.4 — Verify all `@Sendable` closures in tests

`Tests/UDFKitTests/Builders/BuilderEffectsTests.swift`

The dispatch closure test was simplified away in v1 because `var dispatched: [RootActions]` could not be mutated from a `@Sendable` closure. In v2, replace with an `actor`-based or `AsyncStream`-based collector (see Task 5.2).

**Files:**
- `Sources/UDFKit/Core/Store.swift`
- `Sources/UDFKit/Builders/BuilderEffects.swift`

**Verification:** `swift build` with no new warnings. `swift test` passes.

---

## Task 4 — Performance Testing

**Problem:** No benchmarks exist. `BuilderEffects.process` runs all registered effects in a `withTaskGroup` — the overhead of spawning N tasks for N effects is unknown. `BuilderReducer.reduce` is O(n) in the number of registered reducers.

### 4.1 — Add `Benchmarks` executable target

`Package.swift` — add an executable target excluded from `swift test`:

```swift
.executableTarget(
    name: "UDFKitBenchmarks",
    dependencies: ["UDFKit"],
    path: "Benchmarks"
)
```

### 4.2 — Benchmark scenarios to implement

`Benchmarks/main.swift`

Use `ContinuousClock` and `measure` helper:

```swift
func measure(_ label: String, iterations: Int = 1000, _ work: () async -> Void) async {
    let clock = ContinuousClock()
    let elapsed = await clock.measure {
        for _ in 0..<iterations { await work() }
    }
    print("\(label): \(elapsed.components.seconds)s \(elapsed.components.attoseconds / 1_000_000)ms total, \(elapsed / iterations) avg")
}
```

**Scenarios:**
1. Single reducer dispatch — 10,000 actions
2. `BuilderReducer` with 1, 10, 50 registered reducers — 1,000 actions each
3. `BuilderEffects` with 1, 10, 50 registered effects — 1,000 dispatches each
4. `Store` dispatch latency — 1,000 sequential dispatches, measure wall time
5. `Store` dispatch under concurrency — 100 concurrent dispatchers × 10 actions each

### 4.3 — Document complexity

Add complexity annotations to `BuilderReducer.swift` and `BuilderEffects.swift`:

- `BuilderReducer.reduce` — O(n) where n = registered reducer count; suitable for ≤ 50 sub-reducers
- `BuilderEffects.process` — O(n) task spawning overhead; `withTaskGroup` adds ~microseconds per effect; suitable for ≤ 20 concurrent effects

**Files:**
- `Package.swift`
- `Benchmarks/main.swift` (new)
- `Sources/UDFKit/Builders/BuilderReducer.swift` (complexity comments)
- `Sources/UDFKit/Builders/BuilderEffects.swift` (complexity comments)

**Verification:** `swift run UDFKitBenchmarks` prints benchmark results without crashing.

---

## Task 5 — Improved Test Coverage

**Problem:** Several important test scenarios are missing or were simplified away in v1.

### 5.1 — Restore dispatch closure test in `BuilderEffectsTests`

`Tests/UDFKitTests/Builders/BuilderEffectsTests.swift`

Use an `actor`-based collector instead of a mutable `var`:

```swift
actor ActionCollector {
    var collected: [RootActions] = []
    func collect(_ action: RootActions) { collected.append(action) }
}
```

Write test verifying that an effect's `dispatch` closure re-enters the main dispatch pipeline.

### 5.2 — Concurrent dispatch stress test

`Tests/UDFKitTests/Core/StoreTests.swift`

```swift
@Test("concurrent dispatch converges to correct final state")
func concurrentDispatch() async {
    let store = Store(state: CounterState(count: 0), reducer: CounterReducer(), effects: [])
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<100 {
            group.addTask { await store.dispatch(.increment) }
        }
    }
    #expect(store.state.count == 100)
}
```

### 5.3 — Parameterized `BuilderReducerTests`

`Tests/UDFKitTests/Builders/BuilderReducerTests.swift`

Use `@Test(arguments:)` for the action-wrapping variants:

```swift
@Test("reducer handles wrapped action", arguments: [
    (RootAction.counter(.increment), 1),
    (RootAction.counter(.decrement), -1),
    (RootAction.counter(.reset), 0),
])
func wrappedActionReducer(action: RootAction, expectedCount: Int) { ... }
```

### 5.4 — `LogsEffect` stdout capture test

`Tests/UDFKitTests/GenericEffects/LogsEffectTests.swift`

Redirect stdout via `Pipe` + `FileHandle` to verify:
- `isEnabled: false` produces no output
- `isEnabled: true` produces output containing the action name

### 5.5 — Store deallocation safety test

`Tests/UDFKitTests/Core/StoreTests.swift`

```swift
@Test("dispatching to deallocated store does not crash")
func deallocatedStoreDispatch() async {
    var store: Store<CounterState, CounterAction>? = Store(...)
    let effect = LongRunningEffect() // completes after 50ms
    store?.addEffect(effect)
    await store?.dispatch(.increment)
    store = nil  // deallocate mid-effect
    try? await Task.sleep(for: .milliseconds(100))
    // test passes if no crash
}
```

**Files:**
- `Tests/UDFKitTests/Core/StoreTests.swift`
- `Tests/UDFKitTests/Builders/BuilderReducerTests.swift`
- `Tests/UDFKitTests/Builders/BuilderEffectsTests.swift`
- `Tests/UDFKitTests/GenericEffects/LogsEffectTests.swift`
- `Tests/UDFKitTests/Mocks/` (add any new mocks needed)

**Verification:** `swift test` — all tests pass, coverage visibly higher in `BuilderEffects` and `Store` paths.

---

## Task 6 — Code Quality

### 6.1 — Remove stale root files

Delete `example.md` and `how_to_use.md` from the project root. Their content belongs in `README.md` or `specs/`. Having extra markdown files at root creates confusion about the canonical documentation source.

### 6.2 — Evaluate removing `AnyEffect.createEffect`

`Sources/UDFKit/Core/Effect.swift`

```swift
public static func createEffect(_ wrapped: any Effect<State, Action>) -> Self {
    .init(wrapped: wrapped)
}
```

This factory is identical to `AnyEffect(wrapped: someEffect)` — it adds no value. **Action:** Remove it. Callers can use the memberwise initializer directly. This is a breaking change — document in CHANGELOG.

### 6.3 — Make `BuilderEffects.registerEffect` chainable

`Sources/UDFKit/Builders/BuilderEffects.swift`

`BuilderReducer.registerReducer` returns `Self` for fluent chaining. `BuilderEffects.registerEffect` returns `Void`. This inconsistency confuses callers who expect the same pattern.

Since `BuilderEffects` is an `actor`, `nonisolated func registerEffect` returning `Self` requires careful design — the actor's mutable state isn't accessible nonisolated, so returning `self` is fine:

```swift
@discardableResult
public nonisolated func registerEffect<E: Effect>(
    _ keyPath: KeyPath<State, E.State>,
    _ effect: E
) -> Self where E.Action: StoreAction {
    // existing implementation
    return self
}
```

### 6.4 — SwiftLint coverage in `Tests/`

`.swiftlint.yml` currently excludes `Tests/` entirely. Enable a minimal subset for test files:

```yaml
included:
  - Sources
  - Tests
excluded:
  - .build
  - Package.swift
# per-file overrides
custom_rules: {}
# relax length rules for tests
function_body_length:
  warning: 80
  error: 120
```

**Files:**
- `example.md` (delete)
- `how_to_use.md` (delete)
- `Sources/UDFKit/Core/Effect.swift`
- `Sources/UDFKit/Builders/BuilderEffects.swift`
- `.swiftlint.yml`

**Verification:** `swift build` passes, `make lint` passes, `make test` passes.

---

## Task 7 — SwiftUI Integration Tests

**Problem:** The existing test suite validates the Store, Reducer, and Effect types in isolation. There are no tests that verify the library works correctly from a SwiftUI consumer's perspective — environment injection, binding-driven dispatch, and observation-triggered re-renders are untested.

### 7.1 — Add `UDFKitExample` executable target

`Package.swift` — add a SwiftUI app target excluded from `swift test`:

```swift
.executableTarget(
    name: "UDFKitExample",
    dependencies: ["UDFKit"],
    path: "Example"
)
```

`Example/` — a minimal SwiftUI app demonstrating all consumer-facing patterns:

- `@Observable @MainActor Store` declared as `@State` at the root view
- Environment injection via an `@Entry`-declared key
- `store.binding(\.field, set: { .action($0) })` in a `TextField`
- `Button` that calls `store.dispatch(.action)` directly
- A child view that reads the store from `@Environment` and creates its own binding

This serves as a living reference implementation and manual smoke test. Run with `swift run UDFKitExample` on macOS or open in Xcode for iOS simulator.

**Add mocks** needed for the example: `FormState` with at least one `String` field and one `Int` field, `FormAction`, `FormReducer`.

### 7.2 — Add `SwiftUIIntegrationTests` suite

`Tests/UDFKitTests/SwiftUI/SwiftUIIntegrationTests.swift` (new file)

These tests exercise the library's public SwiftUI-facing API as a consumer would. No view rendering is required — the tests drive the store directly and verify state, which is the same data flow SwiftUI observes.

**Test cases:**

```swift
@Suite("SwiftUI integration")
struct SwiftUIIntegrationTests {

    // binding: set triggers apply + intercept, state is readable via same keyPath
    @Test("binding set dispatches through full pipeline")
    @MainActor
    func binding_set_dispatches_through_full_pipeline() async throws {
        let store = Store(initialState: FormState(name: ""), reducer: FormReducer())
        let binding = store.binding(\.name, set: { .setName($0) })
        binding.wrappedValue = "Alice"
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.state.name == "Alice")
    }

    // multiple bindings on the same store do not interfere with each other
    @Test("two bindings on same store update independently")
    @MainActor
    func two_bindings_update_independently() async throws {
        let store = Store(initialState: FormState(name: "", count: 0), reducer: FormReducer())
        let nameBinding = store.binding(\.name, set: { .setName($0) })
        let countBinding = store.binding(\.count, set: { .setCount($0) })
        nameBinding.wrappedValue = "Bob"
        countBinding.wrappedValue = 42
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.state.name == "Bob")
        #expect(store.state.count == 42)
    }

    // environment pattern: a reference passed as environment is the same instance
    @Test("environment-injected store is the same instance as the root store")
    @MainActor
    func environment_store_is_same_instance() async {
        let store = Store(initialState: FormState(name: ""), reducer: FormReducer())
        // Simulate environment injection: child view receives the store reference
        let environmentStore = store
        await environmentStore.dispatch(.setName("Charlie"))
        #expect(store.state.name == "Charlie")
    }

    // binding from a deallocated store silently no-ops, no crash
    @Test("binding set on deallocated store does not crash")
    @MainActor
    func binding_set_on_deallocated_store_does_not_crash() async throws {
        var store: Store<FormState, FormAction>? = Store(
            initialState: FormState(name: ""),
            reducer: FormReducer()
        )
        let binding = store!.binding(\.name, set: { .setName($0) })
        store = nil
        binding.wrappedValue = "Ghost"   // [weak self] guard exits silently
        try await Task.sleep(for: .milliseconds(50))
        // test passes if no crash
    }
}
```

**Add mocks** to `Tests/UDFKitTests/Mocks/`:
- `FormState: StoreState` — `var name: String`, `var count: Int`
- `FormAction: StoreAction` — `.setName(String)`, `.setCount(Int)`
- `FormReducer: Reducer` — applies both actions

**Files:**
- `Package.swift`
- `Example/` (new directory with SwiftUI app source)
- `Tests/UDFKitTests/SwiftUI/SwiftUIIntegrationTests.swift` (new)
- `Tests/UDFKitTests/Mocks/FormMocks.swift` (new)

**Verification:** `swift test` — all SwiftUI integration tests pass. `swift run UDFKitExample` launches on macOS without errors.

---

## Verification Checklist

Run after completing all tasks:

```bash
swift build                          # zero errors, zero warnings
swift test                           # all tests pass
make lint                            # zero SwiftLint violations
make format-check                    # zero SwiftFormat violations
swift run UDFKitBenchmarks           # prints benchmark results
swift run UDFKitExample              # launches example app without errors
```

Manual check: README requirements section accurately states Swift 6.0 and Xcode 16 as minimums.

---

## Estimated Effort

| Task | Effort |
|------|--------|
| 1 — Fix version claims | 30 min |
| 2 — iOS 17 migration | 3–4 h |
| 3 — Concurrency audit | 2 h |
| 4 — Performance testing | 2 h |
| 5 — Improved tests | 3 h |
| 6 — Code quality | 1 h |
| 7 — SwiftUI integration tests | 2 h |
| **Total** | **~14 h** |
