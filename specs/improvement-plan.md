# UDFKit Improvement Spec

## Context

UDFKit is a lightweight Swift state-management library (Redux / TCA-inspired) with Store, Reducer, Effect, Action, Macros, and Builder patterns. It is currently non-importable as a Swift package because:
- No `Package.swift` exists
- Sources are in a flat root directory (no DDD folder structure)
- `LogsEffect` depends on internal proprietary libraries (`AppEnvironmentUtilsLibrary`, `LogsUtilsLibrary`) that will not be available in external projects
- All tests use XCTest; the project must migrate to Swift Testing
- No SwiftLint / SwiftFormat tooling or git hooks
- No README or macro/builder documentation

The goal is a self-contained, importable Swift Package that can be dropped into any iOS 15+ project and follows DDD folder conventions, TDD with Swift Testing, and enforced code style.

---

## Target Package Structure (DDD)

```
UDFKit/
├── Package.swift
├── .swiftlint.yml
├── .swiftformat
├── Makefile
├── scripts/
│   └── pre-commit
├── specs/
│   └── improvement-plan.md
├── Sources/
│   ├── UDFKit/                      ← main library target
│   │   ├── Core/
│   │   │   ├── StoreDefinitions.swift
│   │   │   ├── Store.swift
│   │   │   ├── Reducer.swift
│   │   │   └── Effect.swift
│   │   ├── Builders/
│   │   │   ├── BuilderReducer.swift
│   │   │   └── BuilderEffects.swift
│   │   └── GenericEffects/
│   │       └── LogsEffect.swift     ← rewritten without proprietary deps
│   └── UDFKitMacros/                ← macro implementation target
│       ├── StoreActionMacro.swift
│       └── Plugin.swift             ← renamed (was "Pluging.swift")
├── Tests/
│   ├── UDFKitTests/
│   │   ├── Core/
│   │   │   └── StoreTests.swift
│   │   ├── Builders/
│   │   │   ├── BuilderReducerTests.swift
│   │   │   └── BuilderEffectsTests.swift
│   │   ├── GenericEffects/
│   │   │   └── LogsEffectTests.swift
│   │   └── Mocks/
│   │       ├── ActionMock.swift
│   │       ├── StateMock.swift
│   │       ├── MockReducer.swift
│   │       ├── MockActions.swift
│   │       ├── MockStates.swift
│   │       ├── MockReducers.swift
│   │       ├── MockEffects.swift
│   │       └── MockStoreActionWrapper.swift
│   └── UDFKitMacrosTests/
│       └── StoreActionWrapperMacrosTest.swift
└── README.md
```

---

## Action Plan

Each task is independently verifiable. Run `swift build` and `swift test` as the gate after each phase.

---

### Phase 1 — Scaffold Swift Package

#### Task 1.1 — Create `Package.swift`

- Swift tools version: `5.9` (minimum required for macro support)
- Platforms: `.iOS(.v15)`, `.macOS(.v12)`
- Dependencies:
  - `apple/swift-syntax` pinned to `600.0.1` (SwiftSyntax, SwiftSyntaxMacros, SwiftSyntaxMacrosTestSupport, SwiftCompilerPlugin)
- Targets:

  ```swift
  // Macro implementation — must be a separate executable-style target
  .macro(
      name: "UDFKitMacros",
      dependencies: [
          .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
          .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ]
  ),

  // Main library
  .target(
      name: "UDFKit",
      dependencies: ["UDFKitMacros"]
  ),

  // Library tests
  .testTarget(
      name: "UDFKitTests",
      dependencies: ["UDFKit"]
  ),

  // Macro expansion tests
  .testTarget(
      name: "UDFKitMacrosTests",
      dependencies: [
          "UDFKitMacros",
          .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
      ]
  ),
  ```

- **Validation:** `swift package resolve` + `swift build` succeed with zero errors.

---

#### Task 1.2 — Migrate source files into `Sources/` DDD layout

Move files (do not copy — delete originals after migration):

| From (current) | To (target) |
|----------------|------------|
| `StoreDefinitions.swift` | `Sources/UDFKit/Core/StoreDefinitions.swift` |
| `Store.swift` | `Sources/UDFKit/Core/Store.swift` |
| `Reducer.swift` | `Sources/UDFKit/Core/Reducer.swift` |
| `Effect.swift` | `Sources/UDFKit/Core/Effect.swift` |
| `Builders/BuilderReducer.swift` | `Sources/UDFKit/Builders/BuilderReducer.swift` |
| `Builders/BuilderEffects.swift` | `Sources/UDFKit/Builders/BuilderEffects.swift` |
| `UDFMacrosKit/StoreActionMacro.swift` | `Sources/UDFKitMacros/StoreActionMacro.swift` |
| `UDFMacrosKit/Pluging.swift` | `Sources/UDFKitMacros/Plugin.swift` ← fix typo |
| `GenericEffects/LogsEffect.swift` | `Sources/UDFKit/GenericEffects/LogsEffect.swift` ← see Task 1.3 |

Move test mocks (consolidate into one Mocks/ directory):

| From (current) | To (target) |
|----------------|------------|
| `UDFLibraryTests/Mock/ActionMock.swift` | `Tests/UDFKitTests/Mocks/ActionMock.swift` |
| `UDFLibraryTests/Mock/StateMock.swift` | `Tests/UDFKitTests/Mocks/StateMock.swift` |
| `UDFLibraryTests/Mock/MockReducer.swift` | `Tests/UDFKitTests/Mocks/MockReducer.swift` |
| `UDFLibraryTests/Builders/Mock/MockActions.swift` | `Tests/UDFKitTests/Mocks/MockActions.swift` |
| `UDFLibraryTests/Builders/Mock/MockStates.swift` | `Tests/UDFKitTests/Mocks/MockStates.swift` |
| `UDFLibraryTests/Builders/Mock/MockReducers.swift` | `Tests/UDFKitTests/Mocks/MockReducers.swift` |
| `UDFLibraryTests/Builders/Mock/MockEffects.swift` | `Tests/UDFKitTests/Mocks/MockEffects.swift` |
| `UDFLibraryTests/Builders/Mock/MockStoreActionWrapper.swift` | `Tests/UDFKitTests/Mocks/MockStoreActionWrapper.swift` |

- **Validation:** `swift build` — zero compile errors.

---

#### Task 1.3 — Remove proprietary dependencies from `LogsEffect`

Current issue: `LogsEffect` imports `AppEnvironmentUtilsLibrary` and `LogsUtilsLibrary` which are company-internal and unavailable in open contexts.

Replacement API:

```swift
public struct LogsEffect<GenericState: StoreState, GenericAction: StoreAction>: Effect {
    private let isEnabled: Bool

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
    // ...same Mirror-based pretty-print logic...
    // Replace Log.debug(...) with print(...)
}
```

- Callers pass `isEnabled: ProcessInfo.processInfo.environment["APP_ENV"] == "dev"` or equivalent.
- No imports beyond `Foundation` and `os` (use `os_log` for the print fallback if preferred).
- **Validation:** `swift build` with no unresolved symbols.

---

### Phase 2 — Migrate All Tests to Swift Testing

> Rule: zero `import XCTest` anywhere after this phase. Compiler will catch violations.

#### Task 2.1 — Rewrite `StoreTests`

File: `Tests/UDFKitTests/Core/StoreTests.swift`

```swift
import Testing
@testable import UDFKit

@Suite("Store")
struct StoreTests {
    // Each @Test is a standalone function — no shared setUp needed
    @Test func environment_propagates_state_bidirectionally() async { ... }
    @Test func binding_updates_state_and_calls_setter() async { ... }
    @Test func dispatch_applies_reducer_then_effects() async { ... }
}
```

- Replace `XCTestExpectation` with Swift concurrency (`await`, `Task`, `withCheckedContinuation` if needed)
- Replace `XCTAssert*` with `#expect(...)` / `#require(...)`

#### Task 2.2 — Rewrite `BuilderReducerTests`

File: `Tests/UDFKitTests/Builders/BuilderReducerTests.swift`

- All 9 existing test cases rewritten as `@Test` functions
- Use `@Test("description", arguments: [...])` for parametrized cases where two or more inputs share the same assertion

#### Task 2.3 — Rewrite `BuilderEffectsTests`

File: `Tests/UDFKitTests/Builders/BuilderEffectsTests.swift`

- All 11 async test cases rewritten
- `BuilderEffects` is an `actor` — all `await` calls remain; no changes to production code needed
- Replace `Task.sleep(nanoseconds:)` timing with `Clock` or structured concurrency where possible

#### Task 2.4 — Rewrite `LogsEffectTests`

File: `Tests/UDFKitTests/GenericEffects/LogsEffectTests.swift`

- Verify `process(state:with:)` returns `nil`
- Verify state value is unchanged after call

#### Task 2.5 — Rewrite `StoreActionWrapperMacrosTest`

File: `Tests/UDFKitMacrosTests/StoreActionWrapperMacrosTest.swift`

- `assertMacroExpansion` from `SwiftSyntaxMacrosTestSupport` is framework-agnostic — it does not require XCTest
- Wrap in `@Suite` / `@Test`
- Cover: basic enum expansion, empty enum, non-enum error diagnostic, multiple associated values

- **Validation:** `swift test` — all tests green, `grep -r "import XCTest" Tests/` returns nothing.

---

### Phase 3 — SwiftLint, SwiftFormat & Git Hooks

#### Task 3.1 — Add `.swiftlint.yml`

```yaml
disabled_rules:
  - todo
opt_in_rules:
  - force_unwrapping
  - explicit_acl
  - trailing_whitespace
  - vertical_whitespace
  - file_length
  - function_body_length
  - type_body_length
excluded:
  - .build
  - Tests
reporter: "xcode"
```

#### Task 3.2 — Add `.swiftformat`

```
--swiftversion 5.9
--indent 4
--allman false
--wraparguments before-first
--stripunusedargs closure-only
--exclude .build
```

#### Task 3.3 — Add `scripts/pre-commit`

```bash
#!/bin/bash
set -e

echo "▶ SwiftFormat lint..."
swiftformat --lint Sources/ Tests/ || { echo "❌ SwiftFormat violations. Run: make format"; exit 1; }

echo "▶ SwiftLint..."
swiftlint lint Sources/ Tests/ || { echo "❌ SwiftLint errors found."; exit 1; }

echo "▶ swift build..."
swift build || { echo "❌ Build failed."; exit 1; }

echo "▶ swift test..."
swift test || { echo "❌ Tests failed."; exit 1; }

echo "✅ Pre-commit checks passed."
```

#### Task 3.4 — Add `Makefile`

```makefile
.PHONY: build test lint format install-hooks ci

build:
	swift build

test:
	swift test

lint:
	swiftlint lint Sources/ Tests/

format:
	swiftformat Sources/ Tests/

install-hooks:
	cp scripts/pre-commit .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	@echo "✅ Pre-commit hook installed."

ci: format lint build test
```

- **Validation:** `make ci` passes end-to-end.

---

### Phase 4 — Documentation

#### Task 4.1 — `README.md`

Sections:
1. **What is UDFKit** — one-paragraph pitch
2. **Requirements** — iOS 15+, Swift 5.9+, Xcode 15+
3. **Installation** — SPM snippet
4. **Quick Start** — minimal Store + View example (no company types)
5. **Architecture** — Store → Action → Reducer → State → View diagram (text-art)
6. **API Reference**:
   - `StoreState`, `StoreAction`, `StoreActionWrapper`
   - `Reducer`, `Effect`, `AnyEffect`
   - `Store` (dispatch, binding, environment)
   - `BuilderReducer`, `BuilderEffects`
   - `@StoreActionWrapper` macro (before/after expansion)
   - `LogsEffect` (usage + `isEnabled` param)
7. **Contributing** — `make install-hooks` instruction

#### Task 4.2 — Inline doc comments

Add `///` doc comments to:
- `Store.swift` — `dispatch`, `binding`, `environment`
- `BuilderReducer.swift` — `registerReducer`
- `BuilderEffects.swift` — `registerEffect`
- `StoreActionMacro.swift` — `StoreActionWrapperMacro` struct
- `StoreDefinitions.swift` — `StoreActionWrapper` protocol

---

## Verification Checklist

```bash
# Phase 1
swift package resolve          # dependencies fetch correctly
swift build                    # zero compile errors

# Phase 2
swift test                     # all tests pass
grep -r "import XCTest" Tests/ # must return nothing

# Phase 3
make lint                      # zero SwiftLint errors
make format                    # no diff when run twice
make test                      # all green
git commit --allow-empty -m "test hooks"  # pre-commit hook runs without error

# Phase 4
# Manual: README renders on GitHub, all code samples compile
```

---

## Constraints & Notes

| Constraint | Detail |
|-----------|--------|
| iOS 15 min | Cannot use `@Observable` (iOS 17+). Keep `ObservableObject` + `@Published`. |
| Swift Tools 5.9 | Minimum for macro targets. |
| SwiftSyntax version | Pin to `600.0.1`; must match the Swift toolchain on the machine. |
| No proprietary deps | `LogsEffect` must only use `Foundation` / `os`. |
| XCTest ban | After Phase 2 no file may import XCTest. |
| `BuilderEffects` is actor | Tests must `await` all actor calls; no thread-safety workarounds. |
| git hooks not tracked | Document `make install-hooks` clearly — hooks live in `.git/hooks/` which is gitignored by default. |
