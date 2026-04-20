import Darwin
import Foundation
import Testing
@testable import UDFKit

@Suite("LogsEffect", .serialized)
struct LogsEffectTests {
    private let sut = LogsEffect<StateMock, ActionMock>(isEnabled: false)

    @Test("process always returns nil regardless of action")
    func process_alwaysReturnsNil() async {
        let state = StateMock(someValue: true, asyncValue: [])
        let r1 = await sut.process(state: state, with: .changeSomeValue(false))
        let r2 = await sut.process(state: state, with: .fetchValue)
        let r3 = await sut.process(state: state, with: .fetchValueSuccess([]))
        let r4 = await sut.process(state: state, with: .fetchValueSuccess([false]))
        #expect(r1 == nil)
        #expect(r2 == nil)
        #expect(r3 == nil)
        #expect(r4 == nil)
    }

    @Test("process does not mutate state")
    func process_doesNotMutateState() async {
        let state = StateMock(someValue: true, asyncValue: [])
        _ = await sut.process(state: state, with: .changeSomeValue(false))
        #expect(state.someValue == true)
    }

    @Test("isEnabled true produces output containing action name")
    func enabledLogging_producesOutputWithActionName() async {
        let enabledSUT = LogsEffect<StateMock, ActionMock>(isEnabled: true)
        let state = StateMock(someValue: true, asyncValue: [])

        let pipe = Pipe()
        let originalFd = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        _ = await enabledSUT.process(state: state, with: .changeSomeValue(false))

        fflush(stdout)
        dup2(originalFd, STDOUT_FILENO)
        close(originalFd)
        pipe.fileHandleForWriting.closeFile()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        #expect(output.contains("changeSomeValue"))
    }

    @Test("isEnabled false produces no output")
    func disabledLogging_producesNoOutput() async {
        let disabledSUT = LogsEffect<StateMock, ActionMock>(isEnabled: false)
        let state = StateMock(someValue: true, asyncValue: [])

        let pipe = Pipe()
        let originalFd = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        _ = await disabledSUT.process(state: state, with: .changeSomeValue(false))

        fflush(stdout)
        dup2(originalFd, STDOUT_FILENO)
        close(originalFd)
        pipe.fileHandleForWriting.closeFile()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        #expect(output.isEmpty)
    }
}
