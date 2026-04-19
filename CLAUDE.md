# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Build
swift build
make build

# Test all targets
swift test
make test

# Run a single test by name
swift test --filter "StoreTests/dispatchTriggersReducerAndEffects"

# Lint (SwiftLint via SPM plugin)
make lint

# Format (SwiftFormat via SPM plugin)
make format

# Check formatting without modifying files
make format-check

# Full CI gate: format-check → lint → build → test
make ci

# Install git pre-commit hook (runs ci on every commit)
make install-hooks
```

SwiftLint and SwiftFormat run via `swift package plugin` — no Homebrew installation needed.

## Architecture

UDFKit is a Redux/TCA-inspired Unidirectional Data Flow (UDF) library. The dispatch cycle is:

```
View → store.dispatch(action)
         → Reducer.reduce(oldState:with:) → new state (synchronous)
         → Effect.process(state:with:dispatch:) → optional follow-up action (async, parallel)
```

### Core types (`Sources/UDFKit/Core/`)

- **`StoreState`** / **`StoreAction`** — marker protocols requiring `Equatable & Sendable`
- **`StoreActionWrapper`** — protocol for root action enums that wrap child action enums. Provides `unwrapAs<T>()` and `wrap(_:)` for routing actions through composite hierarchies
- **`Store<State, Action>`** — `ObservableObject` class. `dispatch` is `@MainActor`; state mutation is synchronous; effects run in a `withTaskGroup` and may re-dispatch. Marked `@unchecked Sendable` because all mutations are `@MainActor`-gated
- **`Effect`** protocol — two overloads: simple `process(state:with:)` and extended `process(state:with:dispatch:)` for effects that need to fire follow-up actions. Default implementations forward between them so conformers only implement one
- **`Reducer`** protocol — pure `reduce(oldState:with:) -> State`

### Builders (`Sources/UDFKit/Builders/`)

- **`BuilderReducer<State, Action>`** — value-type (struct) composable reducer. Registers child reducers via `registerReducer(_ keyPath: WritableKeyPath<State, R.State>, _ reducer: R) -> Self`. Returns a new instance (fluent chaining). Handles both direct actions and wrapped actions (`StoreActionWrapper`) transparently
- **`BuilderEffects<State, Action>`** — `actor`-based composable effect runner. Registers child effects via `registerEffect(_ keyPath:, _ effect:)`. Effects are deduplicated by `"\(type)_\(keyPath)"` identifier. All registered effects run in parallel per dispatch. The `BoxedEffect` struct is `@unchecked Sendable` — it's constructed before crossing the actor boundary so only `Sendable` values are captured

### Macro (`Sources/UDFKitMacros/`)

`@StoreActionWrapper` is an `ExtensionMacro` that generates a `StoreActionWrapper` conformance extension for a root action enum. Each enum case must have exactly one associated value (the child action type). Cases without associated values are skipped in `wrap`; all cases appear in `unwrapAs`.

### Action routing pattern

For apps with multiple sub-features, the standard pattern is:

```swift
@StoreActionWrapper
enum RootAction {
    case counter(CounterAction)
    case profile(ProfileAction)
}

let reducer = BuilderReducer<AppState, RootAction>()
    .registerReducer(\.counter, CounterReducer())
    .registerReducer(\.profile, ProfileReducer())

let effects = BuilderEffects<AppState, RootAction>()
effects.registerEffect(\.counter, CounterEffect())
```

`BuilderReducer` and `BuilderEffects` both handle the unwrapping/rewrapping of `RootAction ↔ CounterAction` automatically via the `StoreActionWrapper` protocol.

## Package structure

Two SPM targets:
- `UDFKit` — main library, depends on `UDFKitMacros`
- `UDFKitMacros` — macro implementation, depends on `SwiftSyntaxMacros` + `SwiftCompilerPlugin`

Two test targets:
- `UDFKitTests` — Swift Testing (`@Suite`, `@Test`, `#expect`); no XCTest
- `UDFKitMacrosTests` — uses `SwiftSyntaxMacrosTestSupport.assertMacroExpansion`

SwiftLint and SwiftFormat are SPM dependencies used only as command plugins — they are not linked into any library or test target.

## Key constraints

- **No XCTest** — all tests use Swift Testing exclusively
- **Swift 6 strict concurrency** — the package compiles with `swift-tools-version: 6.0`. New code must satisfy `Sendable` requirements. Use `@unchecked Sendable` only when the safety invariant is documented inline
- **`BuilderEffects` is an actor** — `registerEffect` is `nonisolated` and fires a `Task` to cross the actor boundary; tests must `await Task.sleep` (≥100ms) after registration before dispatching
- **SwiftLint excludes `Tests/` and `Package.swift`** — lint rules apply to `Sources/` only
