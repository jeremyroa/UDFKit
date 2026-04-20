# UDFKit

A lightweight, composable Unidirectional Data Flow (UDF) library for Swift — inspired by Redux and The Composable Architecture (TCA). Drop it into any iOS 17+ project via Swift Package Manager.

## Requirements

| Requirement | Minimum |
|-------------|---------|
| iOS | 17.0 |
| macOS | 14.0 |
| Swift | 6.0 |
| Xcode | 16.0 |

> UDFKit uses Swift 6 strict concurrency (`Sendable`, `@MainActor`, `@Observable`). A Swift 6-compatible toolchain (Xcode 16+) is required.

## Installation

Add UDFKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/UDFKit.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["UDFKit"]
    ),
]
```

Or add it in Xcode via **File → Add Package Dependencies**.

## Architecture

```
View
 │  dispatches Action
 ▼
Store ──► Reducer ──► State (published, drives View)
 │
 └──► Effects (async side-effects, return optional next Action)
```

Data flows in one direction: the View dispatches an `Action` → `Store` applies the `Reducer` → new `State` is published → the `View` re-renders. `Effect`s intercept actions and produce optional follow-up actions (API calls, analytics, etc.).

## Quick Start

```swift
import UDFKit

// 1. Define State
struct CounterState: StoreState {
    var count: Int = 0
}

// 2. Define Actions
enum CounterAction: StoreAction {
    case increment
    case decrement
}

// 3. Define Reducer (pure function)
struct CounterReducer: Reducer {
    func reduce(oldState: CounterState, with action: CounterAction) -> CounterState {
        var state = oldState
        switch action {
        case .increment: state.count += 1
        case .decrement: state.count -= 1
        }
        return state
    }
}

// 4. Create Store
let store = Store<CounterState, CounterAction>(
    initialState: CounterState(),
    reducer: CounterReducer()
)

// 5. Use in SwiftUI View
struct CounterView: View {
    var store: Store<CounterState, CounterAction>

    var body: some View {
        VStack {
            Text("\(store.count)")
            Button("Increment") { Task { await store.dispatch(.increment) } }
            Button("Decrement") { Task { await store.dispatch(.decrement) } }
        }
    }
}

// 6. Declare at root with @State, inject via environment
struct RootView: View {
    @State private var store = Store(
        initialState: CounterState(),
        reducer: CounterReducer()
    )

    var body: some View {
        CounterView(store: store)
    }
}
```

## API Reference

### Core Protocols

#### `StoreState`
```swift
public protocol StoreState: Equatable, Sendable {}
```
Conform your state struct to `StoreState`. Must be `Equatable` for diffing.

#### `StoreAction`
```swift
public protocol StoreAction: Equatable, Sendable {}
```
Conform your action enum to `StoreAction`.

#### `StoreActionWrapper`
```swift
public protocol StoreActionWrapper: StoreAction {
    func unwrapAs<T: StoreAction>() -> T?
    static func wrap(_ action: any StoreAction) -> Self?
}
```
Implement when composing child actions into a root action enum. Use with the `@StoreActionWrapper` macro to auto-generate the conformance.

#### `Reducer`
```swift
public protocol Reducer<State, Action> {
    func reduce(oldState: State, with action: Action) -> State
}
```
A pure function. Never trigger side-effects here — that's what `Effect` is for.

#### `Effect`
```swift
public protocol Effect<State, Action>: Sendable {
    func process(state: State, with action: Action) async -> Action?
    func process(state: State, with action: Action, dispatch: (@Sendable (Action) async -> Void)?) async -> Action?
}
```
Implement as an `actor` (recommended) for thread safety. Return the next `Action` to dispatch, or `nil` if no follow-up is needed.

---

### `Store`

```swift
@Observable @MainActor @dynamicMemberLookup
public final class Store<State: StoreState, Action: StoreAction>
```

The main state container. `@Observable` — use as `@State` at the root view; pass down by reference or via environment.

| Member | Description |
|--------|-------------|
| `init(initialState:reducer:_:)` | Creates a store with initial state, a reducer, and optional effects |
| `dispatch(_ action:) async` | Applies the reducer and runs effects (`@MainActor`-isolated) |
| `binding(_:set:) -> Binding<Value>` | Creates a two-way binding that dispatches an action on change |
| `store.someProperty` | Dynamic member lookup forwards to `State` properties |

**Sharing state via environment (recommended for deep view hierarchies):**
```swift
// Declare once in your app — not in UDFKit (Store is generic)
extension EnvironmentValues {
    @Entry var appStore: Store<AppState, AppAction>? = nil
}

// Root view:
@State private var store = Store(initialState: AppState(), reducer: AppReducer())
var body: some View {
    ContentView().environment(\.appStore, store)
}

// Any descendant:
@Environment(\.appStore) private var store
```

**Two-way bindings:**
```swift
// store.binding dispatches an action through the full reducer+effects pipeline
TextField("Name", text: store.binding(\.name, set: { .setName($0) }))
```

---

### `AnyEffect`

```swift
public struct AnyEffect<State: StoreState, Action: StoreAction>: Sendable {
    public static func createEffect(_ wrapped: any Effect<State, Action>) -> Self
}
```

Type-erased effect wrapper passed to `Store.init`. Example:

```swift
let store = Store(
    initialState: state,
    reducer: reducer,
    .createEffect(MyEffect())
)
```

---

### `BuilderReducer`

Compose multiple child reducers into one root reducer:

```swift
public struct BuilderReducer<State: StoreState, Action: StoreAction>: Reducer {
    public init()
    public func registerReducer<R: Reducer>(
        _ keyPath: WritableKeyPath<State, R.State>,
        _ reducer: R
    ) -> Self where R.Action: StoreAction
}
```

**Usage:**
```swift
let rootReducer = BuilderReducer<RootState, RootAction>()
    .registerReducer(\.counterState, CounterReducer())
    .registerReducer(\.textState, TextReducer())
```

Supports both direct actions (`CounterAction`) and wrapped actions (`RootAction.counter(.increment)` via `StoreActionWrapper`).

---

### `BuilderEffects`

Compose multiple child effects into one root effect (actor-based, runs effects in parallel):

```swift
public actor BuilderEffects<State: StoreState, Action: StoreAction>: Effect {
    public init()
    public nonisolated func registerEffect<E: Effect>(
        _ keyPath: KeyPath<State, E.State>,
        _ effect: E
    ) where E.Action: StoreAction
}
```

**Usage:**
```swift
let effects = BuilderEffects<RootState, RootAction>()
effects.registerEffect(\.counterState, CounterEffect())
effects.registerEffect(\.textState, TextEffect())

let store = Store(
    initialState: state,
    reducer: reducer,
    .createEffect(effects)
)
```

Duplicate registrations of the same effect type + keyPath are ignored.

---

### `@StoreActionWrapper` Macro

Auto-generates `StoreActionWrapper` conformance for a root action enum:

**Before:**
```swift
@StoreActionWrapper
enum RootAction {
    case counter(CounterAction)
    case text(TextAction)
}
```

**After (expanded):**
```swift
extension RootAction: StoreActionWrapper {
    public func unwrapAs<T>() -> T? where T: StoreAction {
        switch self {
        case let .counter(counter): return counter as? T
        case let .text(text): return text as? T
        }
    }

    public static func wrap(_ action: any StoreAction) -> RootAction? {
        switch action {
        case let counter as CounterAction: return .counter(counter)
        case let text as TextAction: return .text(text)
        default: return nil
        }
    }
}
```

Applying `@StoreActionWrapper` to a non-enum type produces a compile-time error.

---

### `LogsEffect`

Logs actions and state transitions to the console during development:

```swift
public struct LogsEffect<State: StoreState, Action: StoreAction>: Effect {
    public init(isEnabled: Bool = false)
}
```

**Usage:**
```swift
let store = Store(
    initialState: state,
    reducer: reducer,
    .createEffect(
        LogsEffect<MyState, MyAction>(
            isEnabled: ProcessInfo.processInfo.environment["APP_ENV"] == "dev"
        )
    )
)
```

Logs use `print()` — no external dependencies. Always returns `nil` (no side-action).

---

## Contributing

1. Clone the repo
2. Install the git hook: `make install-hooks`
3. Make changes with tests
4. The hook runs format check, lint, build, and tests before every commit

```bash
make install-hooks   # Install pre-commit hook
make build           # Build only
make test            # Run tests
make lint            # Run SwiftLint   (via: swift package plugin swiftlint)
make format          # Run SwiftFormat (via: swift package plugin swiftformat)
make format-check    # Check formatting without writing changes
make ci              # Full CI pipeline: format-check → lint → build → test
```

> **No external tools needed.** SwiftLint and SwiftFormat are resolved automatically via Swift Package Manager when you run `swift package resolve`. They are declared as package dependencies and invoked with `swift package plugin`.
