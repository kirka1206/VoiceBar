import Foundation
import VoiceBarCore
import TranscriptCorrectionEvaluationSupport

private struct OllamaTagResponse: Decodable {
    struct Model: Decodable {
        struct Details: Decodable {
            let parameterSize: String?
            let quantizationLevel: String?
        }

        let name: String
        let digest: String
        let details: Details?
    }

    let models: [Model]
}

private struct OllamaChatResponse: Decodable {
    struct Message: Decodable {
        let content: String
    }

    let message: Message
    let totalDuration: Int64?
    let loadDuration: Int64?
    let promptEvalDuration: Int64?
    let evalDuration: Int64?
    let promptEvalCount: Int?
    let evalCount: Int?
}

private struct ModelCall: Codable {
    let caseID: String
    let totalDurationMilliseconds: Double
    let loadDurationMilliseconds: Double?
    let promptEvaluationDurationMilliseconds: Double?
    let evaluationDurationMilliseconds: Double?
    let promptTokenCount: Int?
    let outputTokenCount: Int?
}

private struct MemoryMeasurement: Codable {
    let baselineOllamaRSSBytes: Int64?
    let peakOllamaRSSBytes: Int64?
    let peakIncreaseFromBaselineBytes: Int64?
    let sampleCount: Int
    let samplingIntervalMilliseconds: Int
    let method: String
}

private struct SystemMeasurement: Codable {
    let hostName: String
    let hardware: String
    let macOS: String
    let physicalMemoryBytes: UInt64
}

private struct EvaluationReport: Codable {
    let generatedAt: String
    let modelName: String
    let modelDigest: String
    let modelParameterSize: String?
    let modelQuantization: String?
    let system: SystemMeasurement
    let networkScope: String
    let thresholdsAgreedBeforeEvaluation: Bool
    let goNoGoRecommendation: String
    let metrics: TranscriptCorrectionMetrics
    let memory: MemoryMeasurement
    let calls: [ModelCall]
    let results: [TranscriptCorrectionCaseResult]
}

private actor RSSSampler {
    private var values: [Int64] = []
    private var task: Task<Void, Never>?
    private let intervalNanoseconds: UInt64 = 1_000_000_000

    func start() {
        values.append(Self.readOllamaRSSBytes() ?? 0)
        task = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.append(Self.readOllamaRSSBytes() ?? 0)
                try? await Task.sleep(nanoseconds: self.intervalNanoseconds)
            }
        }
    }

    func stop() async -> [Int64] {
        task?.cancel()
        await task?.value
        return values.filter { $0 > 0 }
    }

    private func append(_ value: Int64) {
        if value > 0 { values.append(value) }
    }

    private static func readOllamaRSSBytes() -> Int64? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "rss=,command="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let listing = String(data: data, encoding: .utf8) else { return nil }

            let processRSSKilobytes = listing.split(separator: "\n").compactMap { line -> Int64? in
                let fields = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count == 2,
                      let rss = Int64(fields[0]),
                      fields[1].localizedCaseInsensitiveContains("ollama") else { return nil }
                return rss
            }
            guard !processRSSKilobytes.isEmpty else { return nil }
            return processRSSKilobytes.reduce(0, +) * 1024
        } catch {
            return nil
        }
    }
}

@main
private enum TranscriptCorrectionEvaluation {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("Evaluation failed: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        let options = try parseArguments(Array(CommandLine.arguments.dropFirst()))
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixturesURL = root.appendingPathComponent("Experiments/TranscriptCorrection/cases.jsonl")
        let reportURL = URL(fileURLWithPath: options.outputPath)
        let model = try await requireInstalledModel(options.model)
        let cases = try loadCases(from: fixturesURL)
        guard !cases.isEmpty else { throw EvaluationError.noCases }

        let sampler = RSSSampler()
        await sampler.start()

        var results: [TranscriptCorrectionCaseResult] = []
        var calls: [ModelCall] = []
        for (index, testCase) in cases.enumerated() {
            let startedAt = ContinuousClock.now
            let keepAlive: Any = index == cases.count - 1 ? 0 : "10m"
            let response = try await correct(testCase, model: options.model, keepAlive: keepAlive)
            let elapsed = startedAt.duration(to: .now).components
            let elapsedMilliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
            let durationMilliseconds = Double(response.totalDuration ?? 0) / 1_000_000
            let measuredDuration = durationMilliseconds > 0 ? durationMilliseconds : elapsedMilliseconds
            let output = response.message.content.trimmingCharacters(in: .whitespacesAndNewlines)

            results.append(TranscriptCorrectionCaseResult(
                testCase: testCase,
                modelOutput: output,
                totalDurationMilliseconds: measuredDuration
            ))
            calls.append(ModelCall(
                caseID: testCase.id,
                totalDurationMilliseconds: measuredDuration,
                loadDurationMilliseconds: response.loadDuration.map { Double($0) / 1_000_000 },
                promptEvaluationDurationMilliseconds: response.promptEvalDuration.map { Double($0) / 1_000_000 },
                evaluationDurationMilliseconds: response.evalDuration.map { Double($0) / 1_000_000 },
                promptTokenCount: response.promptEvalCount,
                outputTokenCount: response.evalCount
            ))
            print("\(testCase.id): \(String(format: "%.0f", measuredDuration)) ms")
        }

        let memorySamples = await sampler.stop()
        let baseline = memorySamples.first
        let peak = memorySamples.max()
        let metrics = TranscriptCorrectionMetrics(results: results)
        let report = EvaluationReport(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            modelName: model.name,
            modelDigest: model.digest,
            modelParameterSize: model.details?.parameterSize,
            modelQuantization: model.details?.quantizationLevel,
            system: SystemMeasurement(
                hostName: ProcessInfo.processInfo.hostName,
                hardware: try shellOutput("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]).trimmingCharacters(in: .whitespacesAndNewlines),
                macOS: ProcessInfo.processInfo.operatingSystemVersionString,
                physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
            ),
            networkScope: "HTTP requests only to http://127.0.0.1:11434 (Ollama local API); no remote requests or model pulls",
            thresholdsAgreedBeforeEvaluation: false,
            goNoGoRecommendation: "Inconclusive: U2 quality, false-change, latency, and memory thresholds were not agreed before evaluation; measurements only.",
            metrics: metrics,
            memory: MemoryMeasurement(
                baselineOllamaRSSBytes: baseline,
                peakOllamaRSSBytes: peak,
                peakIncreaseFromBaselineBytes: baseline.flatMap { base in peak.map { max(0, $0 - base) } },
                sampleCount: memorySamples.count,
                samplingIntervalMilliseconds: 1_000,
                method: "Sum of resident-set-size values from matching Ollama process entries sampled once per second with ps; process RSS is an estimate and may count shared pages."
            ),
            calls: calls,
            results: results
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: reportURL, options: .atomic)
        print("\nReport: \(reportURL.path)")
        print("WER raw/deterministic/model: \(format(metrics.rawWordErrorRate)) / \(format(metrics.deterministicWordErrorRate)) / \(format(metrics.modelWordErrorRate))")
        print("Expected context corrections: \(metrics.successfulTermCorrections)/\(metrics.expectedTermCorrections)")
        print("False changes to correct cases: \(metrics.falseChangesToAlreadyCorrectCases)/\(metrics.alreadyCorrectCaseCount)")
        print("Peak sampled Ollama RSS: \(peak.map(formatBytes) ?? "not available")")
        print("Recommendation: no go/no-go recommendation (thresholds were not agreed)")
    }

    private static func parseArguments(_ arguments: [String]) throws -> (model: String, outputPath: String) {
        var model = "gemma4:latest"
        var outputPath = "/tmp/voicebar-transcript-correction-report.json"
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--model":
                guard index + 1 < arguments.count else { throw EvaluationError.invalidArguments }
                model = arguments[index + 1]
                index += 2
            case "--output":
                guard index + 1 < arguments.count else { throw EvaluationError.invalidArguments }
                outputPath = arguments[index + 1]
                index += 2
            default:
                throw EvaluationError.invalidArguments
            }
        }
        return (model, outputPath)
    }

    private static func requireInstalledModel(_ requestedName: String) async throws -> OllamaTagResponse.Model {
        let url = URL(string: "http://127.0.0.1:11434/api/tags")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw EvaluationError.localOllamaUnavailable
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let tags = try decoder.decode(OllamaTagResponse.self, from: data)
        guard let model = tags.models.first(where: { $0.name == requestedName }) else {
            throw EvaluationError.modelNotInstalled(requestedName)
        }
        return model
    }

    private static func loadCases(from url: URL) throws -> [TranscriptCorrectionCase] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try contents.split(whereSeparator: \.isNewline).map { line in
            try decoder.decode(TranscriptCorrectionCase.self, from: Data(line.utf8))
        }
    }

    private static func correct(_ testCase: TranscriptCorrectionCase, model: String, keepAlive: Any) async throws -> OllamaChatResponse {
        let vocabulary = testCase.vocabulary.map { "- \($0)" }.joined(separator: "\n")
        let prompt = """
        Исправь только очевидные ошибки распознавания технических терминов в русском тексте.
        Используй список ниже как правильное написание терминов. Контекст может помочь определить явную ошибку распознавания.
        Не переписывай стиль, не исправляй грамматику и пунктуацию, не добавляй и не удаляй факты.
        Обычные русские слова, включая «текстура», «текстурой» и «командир», сохраняй, если контекст однозначно не показывает ошибку распознавания.
        Верни только итоговый текст без кавычек и пояснений.

        Правильные термины:
        \(vocabulary)

        Распознанный текст:
        \(testCase.deterministic)
        """

        let url = URL(string: "http://127.0.0.1:11434/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "stream": false,
            "keep_alive": keepAlive,
            "think": false,
            "options": ["temperature": 0]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty response>"
            throw EvaluationError.modelRequestFailed(body)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OllamaChatResponse.self, from: data)
    }

    private static func shellOutput(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let value = String(data: data, encoding: .utf8) else {
            throw EvaluationError.systemInfoUnavailable
        }
        return value
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .memory)
    }
}

private enum EvaluationError: LocalizedError {
    case invalidArguments
    case noCases
    case localOllamaUnavailable
    case modelNotInstalled(String)
    case modelRequestFailed(String)
    case systemInfoUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Usage: swift run TranscriptCorrectionEvaluation [--model installed-name] [--output /absolute/path/report.json]"
        case .noCases:
            return "The evaluation fixture contains no cases."
        case .localOllamaUnavailable:
            return "Ollama's local API is unavailable at 127.0.0.1:11434. Start Ollama, then run this command again."
        case .modelNotInstalled(let name):
            return "Model '\(name)' is not installed locally. The runner does not download models."
        case .modelRequestFailed(let body):
            return "Ollama returned an error: \(body)"
        case .systemInfoUnavailable:
            return "Could not read local system information."
        }
    }
}
