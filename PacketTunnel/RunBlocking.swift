import Foundation

// libbox calls the platform interface synchronously from Go threads, while the
// NetworkExtension APIs are async. These helpers bridge the two.

func runBlocking<T>(_ block: @escaping () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<T>()
    Task.detached(priority: .userInitiated) {
        let value = await block()
        box.value = value
        semaphore.signal()
    }
    semaphore.wait()
    return box.value!
}

func runBlocking<T>(_ block: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = ResultBox<T>()
    Task.detached(priority: .userInitiated) {
        do {
            box.result = .success(try await block())
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.result!.get()
}

private final class ResultBox<T> {
    var value: T?
    var result: Result<T, Error>?
}
