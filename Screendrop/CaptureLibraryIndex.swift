//
//  CaptureLibraryIndex.swift
//  Screendrop
//

import AppKit
import CryptoKit
import Observation
import Vision

/// Keeps an analysis for every capture: the text inside it, a category and
/// a feature print for similarity. Work runs one capture at a time at
/// background priority, newest first, and pauses while recording, in Low
/// Power Mode, or when the Mac runs hot. Results land in small batches so
/// the Library re-filters a few times a second at most, not per capture.
@MainActor
@Observable
final class CaptureLibraryIndex {
    static let shared = CaptureLibraryIndex()

    private(set) var analyses: [String: CaptureAnalysis] = [:]
    /// Bumped once per published batch.
    private(set) var revision = 0
    /// Captures waiting to be read, for the status bar.
    private(set) var pendingCount = 0

    @ObservationIgnored private let store = CaptureLibraryIndexStore(
        directory: ScreenshotHistoryStore.applicationSupportDirectory.appendingPathComponent("Library Index", isDirectory: true)
    )
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var latestItems: [CaptureLibraryItem]?
    @ObservationIgnored private var queue: [CaptureLibraryItem] = []
    /// The capture being read right now, kept out of re-syncs meanwhile.
    @ObservationIgnored private var inFlight: CaptureLibraryItem?
    /// Fingerprints that couldn't be read this session, so an unreadable
    /// file isn't retried on every refresh.
    @ObservationIgnored private var unreadable: Set<String> = []
    @ObservationIgnored private var runner: Task<Void, Never>?
    @ObservationIgnored private var unpublished: [String: CaptureAnalysis] = [:]
    @ObservationIgnored private var publishTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    private init() {}

    /// Loads the saved index and keeps it in step with History from then on,
    /// whether or not the Library window is open.
    func start() {
        guard !started else { return }
        started = true
        observeHistory()
        Task {
            let loaded = await store.loadAll()
            analyses = loaded
            isLoaded = true
            revision &+= 1
            CaptureLibraryModel.shared.indexDidChange(changed: Set(loaded.keys))
            if let latestItems { sync(latestItems) } else { CaptureLibraryModel.shared.refresh() }
        }
    }

    /// Queues every capture whose analysis is missing or stale, and forgets
    /// captures that are gone.
    func sync(_ items: [CaptureLibraryItem]) {
        latestItems = items
        guard isLoaded else { return }
        let modelAvailable = CaptureLibraryAnalyzer.isModelAvailable
        let live = Set(items.lazy.map(\.id))
        // An empty scan more likely means History failed to load than that
        // every capture was deleted; keep the index rather than wipe it.
        if !items.isEmpty {
            let gone = analyses.keys.filter { !live.contains($0) }
            if !gone.isEmpty {
                for id in gone { analyses[id] = nil }
                revision &+= 1
                Task { await store.remove(ids: gone) }
            }
        }
        queue = items
            .filter { item in
                guard item != inFlight, !unreadable.contains(item.thumbnailKey) else { return false }
                guard let analysis = analyses[item.id] ?? unpublished[item.id] else { return true }
                return analysis.version < CaptureAnalysis.currentVersion
                    || analysis.fingerprint != item.thumbnailKey
                    || (modelAvailable && analysis.classifier != .model && !analysis.modelDeclined)
            }
            .sorted { $0.createdAt > $1.createdAt }
        pendingCount = queue.count
        if !queue.isEmpty, runner == nil { runner = Task { await drain() } }
    }

    /// Captures that look most like `id`, nearest first.
    func similar(to id: String, among candidates: [String], limit: Int) async -> [String] {
        guard analyses[id]?.hasFeaturePrint == true else { return [] }
        let withPrints = candidates.filter { $0 != id && analyses[$0]?.hasFeaturePrint == true }
        return await store.nearest(to: id, among: withPrints, limit: limit)
    }

    // MARK: Work queue

    private func drain() async {
        defer { runner = nil }
        while let item = queue.first {
            if shouldPause {
                try? await Task.sleep(for: .seconds(10))
                continue
            }
            queue.removeFirst()
            inFlight = item
            defer { inFlight = nil }
            // A current reading only needs the model's second look.
            let existing = (analyses[item.id] ?? unpublished[item.id]).flatMap {
                $0.version == CaptureAnalysis.currentVersion && $0.fingerprint == item.thumbnailKey ? $0 : nil
            }
            let work = Task.detached(priority: .background) { () -> CaptureLibraryAnalyzer.Result? in
                if let existing {
                    return .init(analysis: await CaptureLibraryAnalyzer.reclassify(existing, item: item), featurePrint: nil)
                }
                return await CaptureLibraryAnalyzer.analyze(item)
            }
            if let result = await work.value {
                await store.save(result.analysis, featurePrint: result.featurePrint)
                unpublished[item.id] = result.analysis
                schedulePublish()
            } else {
                unreadable.insert(item.thumbnailKey)
            }
            pendingCount = queue.count
        }
        publish()
    }

    /// Recording, Low Power Mode and a hot Mac all come before indexing.
    private var shouldPause: Bool {
        ScreenRecordingManager.shared.isActive
            || ProcessInfo.processInfo.isLowPowerModeEnabled
            || ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }

    private func schedulePublish() {
        guard publishTask == nil else { return }
        publishTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            publish()
        }
    }

    private func publish() {
        publishTask?.cancel()
        publishTask = nil
        guard !unpublished.isEmpty else { return }
        let changed = Set(unpublished.keys)
        analyses.merge(unpublished) { _, new in new }
        unpublished = [:]
        revision &+= 1
        CaptureLibraryModel.shared.indexDidChange(changed: changed)
    }

    /// Refreshes the Library model when History or the project list changes,
    /// so new captures are read even while the window is closed.
    private func observeHistory() {
        withObservationTracking {
            _ = ScreenshotHistoryStore.shared.items
            _ = RecordingProjectStore.shared.projects
        } onChange: {
            Task { @MainActor in
                CaptureLibraryModel.shared.refresh()
                CaptureLibraryIndex.shared.observeHistory()
            }
        }
    }
}

/// The index on disk: one JSON file per capture, plus its feature print, in
/// Application Support. Feature prints stay out of memory until the first
/// similarity lookup needs them.
actor CaptureLibraryIndexStore {
    private let directory: URL
    private var prints: [String: VNFeaturePrintObservation] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    func loadAll() -> [String: CaptureAnalysis] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        var result: [String: CaptureAnalysis] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let analysis = try? decoder.decode(CaptureAnalysis.self, from: data) else { continue }
            result[analysis.id] = analysis
        }
        return result
    }

    func save(_ analysis: CaptureAnalysis, featurePrint: Data?) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(analysis).write(to: url(analysis.id, "json"), options: .atomic)
            if let featurePrint {
                try featurePrint.write(to: url(analysis.id, "print"), options: .atomic)
                prints[analysis.id] = nil
            }
        } catch {
            NSLog("[Screendrop] Failed to save Library index entry: \(error)")
        }
    }

    func remove(ids: [String]) {
        for id in ids {
            prints[id] = nil
            try? FileManager.default.removeItem(at: url(id, "json"))
            try? FileManager.default.removeItem(at: url(id, "print"))
        }
    }

    func nearest(to id: String, among candidates: [String], limit: Int) -> [String] {
        guard let target = featurePrint(id) else { return [] }
        var scored: [(id: String, distance: Float)] = []
        scored.reserveCapacity(candidates.count)
        for candidate in candidates {
            var distance: Float = 0
            guard let other = featurePrint(candidate),
                  (try? target.computeDistance(&distance, to: other)) != nil else { continue }
            scored.append((candidate, distance))
        }
        return scored.sorted { $0.distance < $1.distance }.prefix(limit).map(\.id)
    }

    private func featurePrint(_ id: String) -> VNFeaturePrintObservation? {
        if let cached = prints[id] { return cached }
        guard let data = try? Data(contentsOf: url(id, "print")),
              let observation = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
        else { return nil }
        prints[id] = observation
        return observation
    }

    /// Item IDs include file paths, so files are named by a hash of the ID.
    private func url(_ id: String, _ pathExtension: String) -> URL {
        let digest = SHA256.hash(data: Data(id.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension(pathExtension)
    }
}
