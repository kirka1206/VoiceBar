import Foundation

enum ModelStoreError: LocalizedError {
    case invalidResponse
    case incompleteDownload

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Сервер модели вернул некорректный ответ."
        case .incompleteDownload: "Загрузка модели завершилась без файла или файл оказался неполным."
        }
    }
}

struct ModelStore: Sendable {
    static let modelFileName = "ggml-large-v3-turbo.bin"
    static let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!

    init() {}

    func localModelURL(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support
            .appendingPathComponent("VoiceBar", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Self.modelFileName)
    }

    func ensureModel(
        forceDownload: Bool = false,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws -> URL {
        let destination = try localModelURL()
        let fileManager = FileManager.default
        if !forceDownload && isCompleteModel(at: destination, fileManager: fileManager) {
            return destination
        }

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let downloader = ModelDownloadDelegate(destination: destination, progress: progress)
        return try await downloader.download(from: Self.modelURL)
    }

    private func isCompleteModel(at url: URL, fileManager: FileManager) -> Bool {
        Self.isCompleteModelFile(at: url, fileManager: fileManager)
    }

    fileprivate static func isCompleteModelFile(at url: URL, fileManager: FileManager) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > minimumModelSizeBytes
    }

    // The unquantized large-v3-turbo model is about 1.5 GiB; reject partial downloads.
    private static let minimumModelSizeBytes: Int64 = 1_000_000_000
}

private final class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progressHandler: @Sendable (Double?) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var completedURL: URL?
    private var failure: Error?

    init(destination: URL, progress: @escaping @Sendable (Double?) -> Void) {
        self.destination = destination
        self.progressHandler = progress
    }

    func download(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = downloadTask.response?.expectedContentLength ?? totalBytesExpectedToWrite
        let fraction = expected > 0 ? min(1, Double(totalBytesWritten) / Double(expected)) : nil
        progressHandler(fraction)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            failure = ModelStoreError.invalidResponse
            return
        }

        do {
            let fileManager = FileManager.default
            let partial = destination.appendingPathExtension("partial")
            try? fileManager.removeItem(at: partial)
            try fileManager.moveItem(at: location, to: partial)
            guard ModelStore.isCompleteModelFile(at: partial, fileManager: fileManager) else {
                try? fileManager.removeItem(at: partial)
                throw ModelStoreError.incompleteDownload
            }
            if fileManager.fileExists(atPath: destination.path) {
                completedURL = try fileManager.replaceItemAt(destination, withItemAt: partial) ?? destination
            } else {
                try fileManager.moveItem(at: partial, to: destination)
                completedURL = destination
            }
        } catch {
            failure = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            failure = error
        }

        if let failure {
            continuation?.resume(throwing: failure)
        } else if let completedURL {
            progressHandler(1)
            continuation?.resume(returning: completedURL)
        } else {
            continuation?.resume(throwing: ModelStoreError.incompleteDownload)
        }
        continuation = nil
        self.session = nil
    }
}
