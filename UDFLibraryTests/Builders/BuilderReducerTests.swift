import XCTest
@testable import UDFLibrary

final class BuilderReducerTests: XCTestCase {
    var sut: BuilderReducer<RootState, RootActions>!
    
    override func setUp() {
        super.setUp()
        sut = BuilderReducer()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    func test_emptyBuilder_returnsOriginalState() {
        // Given
        let initialState = RootState()
        let action = RootActions.counter(.increment)
        
        // When
        let newState = sut.reduce(oldState: initialState, with: action)
        
        // Then
        XCTAssertEqual(newState.counterState.count, initialState.counterState.count)
        XCTAssertEqual(newState.textState.text, initialState.textState.text)
    }
    
    func test_registerCounterReducer_handlesCounterAction() {
        // Given
        let initialState = RootState()
        sut = sut.registerReducer(\.counterState, CounterReducer())
        
        // When
        let newState = sut.reduce(oldState: initialState, with: .counter(.increment))
        
        // Then
        XCTAssertEqual(newState.counterState.count, 1)
        XCTAssertEqual(newState.textState.text, "")
    }
    
    func test_wrappedCounterAction_handlesCorrectly() {
        // Given
        let initialState = RootState()
        sut = sut.registerReducer(\.counterState, CounterReducer())
        let counterAction = CounterActions.increment
        
        // When
        guard let wrappedAction = RootActions.wrap(counterAction) else {
            XCTFail("Failed to wrap CounterActions.increment")
            return
        }
        let newState = sut.reduce(oldState: initialState, with: wrappedAction)
        
        // Then
        XCTAssertEqual(newState.counterState.count, 1)
    }
    
    func test_wrappedTextAction_handlesCorrectly() {
        // Given
        let initialState = RootState()
        sut = sut.registerReducer(\.textState, TextReducer())
        let textAction = TextActions.append("Test")
        
        // When
        guard let wrappedAction = RootActions.wrap(textAction) else {
            XCTFail("Failed to wrap TextActions.append")
            return
        }
        let newState = sut.reduce(oldState: initialState, with: wrappedAction)
        
        // Then
        XCTAssertEqual(newState.textState.text, "Test")
    }
    
    func test_unwrapCounterAction_returnsCorrectType() {
        // Given
        let rootAction = RootActions.counter(.increment)
        
        // When
        let unwrappedAction: CounterActions? = rootAction.unwrapAs()
        
        // Then
        XCTAssertEqual(unwrappedAction, .increment)
    }
    
    func test_unwrapTextAction_returnsCorrectType() {
        // Given
        let rootAction = RootActions.text(.append("Test"))
        
        // When
        let unwrappedAction: TextActions? = rootAction.unwrapAs()
        
        // Then
        XCTAssertEqual(unwrappedAction, .append("Test"))
    }
    
    func test_unwrapToWrongType_returnsNil() {
        // Given
        let rootAction = RootActions.counter(.increment)
        
        // When
        let unwrappedAction: TextActions? = rootAction.unwrapAs()
        
        // Then
        XCTAssertNil(unwrappedAction)
    }
    
    func test_mixedActionsHandling() {
        // Given
        let initialState = RootState()
        sut = sut
            .registerReducer(\.counterState, CounterReducer())
            .registerReducer(\.textState, TextReducer())
            
        // When
        var state = initialState
        
        // Test wrapped counter action
        if let wrappedCounterAction = RootActions.wrap(CounterActions.increment) {
            state = sut.reduce(oldState: state, with: wrappedCounterAction)
        }
        
        // Test wrapped text action
        if let wrappedTextAction = RootActions.wrap(TextActions.append("Test")) {
            state = sut.reduce(oldState: state, with: wrappedTextAction)
        }
        
        // Then
        XCTAssertEqual(state.counterState.count, 1)
        XCTAssertEqual(state.textState.text, "Test")
    }
}
