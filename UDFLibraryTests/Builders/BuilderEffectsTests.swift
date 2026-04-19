import XCTest
@testable import UDFLibrary

final class BuilderEffectsTests: XCTestCase {
    var sut: BuilderEffects<RootState, RootActions>!
    
    
    override func setUp() async throws {
        try? await super.setUp()
        sut = BuilderEffects()
    }
    
    override func tearDown() async throws {
        sut = nil
        try? await super.tearDown()
    }
    
    func test_CounterEffectRegistration() async {
        // Given
        let counterEffect = CounterEffect()
        let state = RootState()
        let action = RootActions.counter(.increment)
        
        // When
         sut.registerEffect(\.counterState, counterEffect)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let result = await sut.process(state: state, with: action)
        
        // Then
        XCTAssertNil(result, "Effect should return nil when count is less than 10")
    }
    
    func test_CounterEffect_With_High_Count() async {
        // Given
        let counterEffect = CounterEffect()
        var state = RootState()
        state.counterState.count = 10
        let action = RootActions.counter(.increment)
        
        // When
        sut.registerEffect(\.counterState, counterEffect)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let result = await sut.process(state: state, with: action)
        
        // Then
        XCTAssertEqual(result, .counter(.increment), "Effect should return increment action when count is >= 10")
    }
    
    func test_TextEffect_With_Empty_String() async {
        // Given
        let textEffect = TextEffect()
        let state = RootState()
        let action = RootActions.text(.append("Test"))
        
        // When
        sut.registerEffect(\.textState, textEffect)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let result = await sut.process(state: state, with: action)
        
        // Then
        XCTAssertEqual(result, .text(.append("Hello!!")), "Effect should append Hello!! when text is empty")
    }
    
    func test_TextEffect_With_Non_EmptyString() async {
        // Given
        let textEffect = TextEffect()
        var state = RootState()
        state.textState.text = "Not empty"
        let action = RootActions.text(.append("Test"))
        
        // When
        sut.registerEffect(\.textState, textEffect)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let result = await sut.process(state: state, with: action)
        
        // Then
        XCTAssertNil(result, "Effect should return nil when text is not empty")
    }
    
    func test_Multiple_Effects_Registration() async {
        // Given
        let counterEffect = CounterEffect()
        let textEffect = TextEffect()
        let state = RootState()
        let action = RootActions.counter(.increment)
        
        // When
        sut.registerEffect(\.counterState, counterEffect)
        try? await Task.sleep(nanoseconds: 100_000_000)
        sut.registerEffect(\.textState, textEffect)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let result = await sut.process(state: state, with: action)
        
        // Then
        XCTAssertNil(result, "Both effects should process but return nil for this case")
    }
    
    func test_Effect_Cancellation() async {
        // Given
        let counterEffect = CounterEffect()
        var state = RootState()
        state.counterState.count = 10
        
        // When
        sut.registerEffect(\.counterState, counterEffect)
        try? await Task.sleep(nanoseconds: 100_000_000)
        // Register the same effect again to trigger cancellation of the first one
        sut.registerEffect(\.counterState, counterEffect)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let result = await sut.process(state: state, with: RootActions.counter(.increment))
        
        // Then
        XCTAssertEqual(result, .counter(.increment), "Effect should still work after re-registration")
    }
    
    func test_Processing_NonMatchingAction() async {
        // Given
        let counterEffect = CounterEffect()
        let state = RootState()
        // Non-matching action type
        let action = RootActions.text(.append("Test"))
        
        // When
        sut.registerEffect(\.counterState, counterEffect)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let result = await sut.process(state: state, with: action)
        
        // Then
        XCTAssertNil(result, "Effect should return nil for non-matching action type")
    }
        
    func test_Direct_CounterEffect_Registration() async {
        // Given
        let counterEffect = CounterEffect()
        var state = RootState()
        state.counterState.count = 10
        let action = RootActions.counter(.increment)
        
        // When
        sut.registerEffect(\.counterState, counterEffect)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let result = await sut.process(state: state, with: action)
        
        // Then
        XCTAssertEqual(result, .counter(.increment), "Effect should handle direct CounterActions")
    }
    
    func test_NestedAction_Processing() async {
        // Given
        let counterEffect = CounterEffect()
        var state = RootState()
        state.counterState.count = 10
        let nestedAction = RootActions.counter(.increment)
        
        // When
        sut.registerEffect(\.counterState, counterEffect)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let result = await sut.process(state: state, with: nestedAction)
        
        // Then
        XCTAssertEqual(result, .counter(.increment), "Effect should handle nested actions")
    }
    
    func test_DirectAndNestedEffects_Combination() async {
   
        let rootEffect = RootEffect()
        let counterEffect = CounterEffect()
        var state = RootState()
        state.counterState.count = 10
        let action = RootActions.counter(.increment)
        
        // When
        sut.registerEffect(\.self, rootEffect)
        try? await Task.sleep(nanoseconds: 100_000_000)
        sut.registerEffect(\.counterState, counterEffect)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let result = await sut.process(state: state, with: action)
        
        // Then
        // The first effect that returns a non-nil action will be the result
        // due to the processEffectsInParallel implementation
        XCTAssertNotNil(result, "One of the effects should return an action")
    }
    
    func test_DirectRegistration_With_Self_KeyPath() async {
        // Given
        let sut = BuilderEffects<TextState,TextActions>()
        let textEffect = TextEffect()
        let state = TextState()
        let action = TextActions.append("Test")
        
        // When
        sut.registerEffect(\.self, textEffect)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let result = await sut.process(state: state, with: action)
        
        // Then
        XCTAssertEqual(result, .append("Hello!!"),
                           #"Text effect registered with \.self should process TextState directly"#)
    }

    func test_Effect_With_Dispatch() async {
        // Given
        let counterEffect = CounterEffect()
        var state = RootState()
        state.counterState.count = 10
        let action = RootActions.counter(.increment)

        var dispatchedActions: [RootActions] = []
        let testDispatch: (RootActions) async -> Void = { action in
            dispatchedActions.append(action)
        }

        // When
        sut.registerEffect(\.counterState, counterEffect)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let result = await sut.process(state: state, with: action, dispatch: testDispatch)

        // Then
        XCTAssertEqual(result, .counter(.increment), "Effect should process with dispatch parameter")
    }
}
