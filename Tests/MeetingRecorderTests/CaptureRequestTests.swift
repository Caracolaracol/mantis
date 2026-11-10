import XCTest
@testable import MeetingRecorder

@MainActor
final class CaptureRequestTests: XCTestCase {
    func testSuccessResumesOnceAndCancelsDeadline() async throws {
        var aborts = 0
        var lateStops = 0
        let value = try await CaptureRequest<Int>.perform(timeout: 0.01, abort: { aborts += 1 }, lateSuccess: { _ in lateStops += 1 }) { finish in
            finish(.success(42))
            finish(.success(42))
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(value, 42)
        XCTAssertEqual(aborts, 0)
        XCTAssertEqual(lateStops, 0)
    }

    func testFrameworkErrorResumesAndAborts() async {
        var aborts = 0
        do {
            _ = try await CaptureRequest<Int>.perform(abort: { aborts += 1 }) { finish in
                finish(.failure(NSError(domain: "synthetic", code: 17)))
            }
            XCTFail("Expected framework error")
        } catch { XCTAssertEqual((error as NSError).code, 17) }
        XCTAssertEqual(aborts, 1)
    }

    func testMissingCallbackTimesOutAndLateSuccessfulStartIsStopped() async {
        var completion: ((Result<Int, Error>) -> Void)?
        var aborts = 0
        let stopped = expectation(description: "Late start stopped")
        do {
            _ = try await CaptureRequest<Int>.perform(timeout: 0.01, abort: { aborts += 1 }, lateSuccess: { _ in stopped.fulfill() }) {
                completion = $0
            }
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error is CaptureRequestError) }
        XCTAssertEqual(aborts, 1)
        completion?(.success(7))
        await fulfillment(of: [stopped], timeout: 1)
    }

    func testCancellationReturnsWithoutWaitingForPermissionCallback() async {
        var completion: ((Result<Bool, Error>) -> Void)?
        let began = expectation(description: "Permission requested")
        let late = expectation(description: "Late permission ignored")
        var advancedToRecording = false
        let task = Task {
            do {
                _ = try await CaptureRequest<Bool>.perform(timeout: nil, lateSuccess: { _ in late.fulfill() }) {
                    completion = $0
                    began.fulfill()
                }
                advancedToRecording = true
                XCTFail("Should be canceled")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        await fulfillment(of: [began], timeout: 1)
        task.cancel()
        await task.value
        completion?(.success(true))
        await fulfillment(of: [late], timeout: 1)
        XCTAssertFalse(advancedToRecording)
    }

    func testAlreadyCanceledRequestDoesNotBeginHardwareOperation() async {
        var began = false
        let task = Task {
            do {
                _ = try await CaptureRequest<Int>.perform { finish in
                    began = true
                    finish(.success(1))
                }
                XCTFail("Should be canceled")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        task.cancel()
        await task.value
        XCTAssertFalse(began)
    }
}
