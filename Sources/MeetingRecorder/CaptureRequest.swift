import Foundation
import MeetingCore

enum CaptureRequestError: LocalizedError {
    case timedOut(String)
    case stopTimedOut

    var errorDescription: String? {
        switch self {
        case .timedOut(let stage):
            return AppLocalization.format("macOS no respondió a tiempo al %@. La preparación se canceló; revisa los permisos y vuelve a intentarlo.", AppLocalization.text(stage))
        case .stopTimedOut:
            return AppLocalization.text("macOS no confirmó la detención del audio. Sal completamente de Mantis antes de volver a grabar. El audio temporal disponible se conserva.")
        }
    }
}

/// Callback bridge that does not wait forever for an uncooperative framework.
/// Resolve exactly once; a late successful start must be stopped, never adopted.
@MainActor
final class CaptureRequest<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var completed = false
    private var completedResult: Result<Value, Error>?
    private var discardLateSuccess = false
    private var timer: Task<Void, Never>?
    private let abort: () -> Void
    private let lateSuccess: (Value) -> Void

    private init(abort: @escaping () -> Void, lateSuccess: @escaping (Value) -> Void) {
        self.abort = abort
        self.lateSuccess = lateSuccess
    }

    static func perform(timeout: TimeInterval? = 15,
                        timeoutError: Error = CaptureRequestError.timedOut("iniciar la captura de audio"),
                        abort: @escaping () -> Void = {},
                        lateSuccess: @escaping (Value) -> Void = { _ in },
                        begin: (@escaping (Result<Value, Error>) -> Void) -> Void) async throws -> Value {
        let request = CaptureRequest(abort: abort, lateSuccess: lateSuccess)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request.continuation = continuation
                if let result = request.completedResult {
                    request.continuation = nil
                    continuation.resume(with: result)
                    return
                }
                if Task.isCancelled {
                    request.resolve(.failure(CancellationError()))
                    return
                }
                if let timeout {
                    request.timer = Task {
                        do { try await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000)) }
                        catch { return }
                        request.resolve(.failure(timeoutError))
                    }
                }
                begin { result in
                    Task { @MainActor in request.resolve(result) }
                }
            }
        } onCancel: {
            Task { @MainActor in request.resolve(.failure(CancellationError())) }
        }
    }

    private func resolve(_ result: Result<Value, Error>) {
        guard !completed else {
            if discardLateSuccess, case .success(let value) = result { lateSuccess(value) }
            return
        }
        completed = true
        completedResult = result
        timer?.cancel()
        timer = nil
        if case .failure = result { discardLateSuccess = true; abort() }
        continuation?.resume(with: result)
        continuation = nil
    }
}
