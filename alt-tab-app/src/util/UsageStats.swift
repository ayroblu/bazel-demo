/// Usage counters, stored as a list of unix-second timestamps per key.
///
/// The timestamps are the storage format, not an implementation detail: `count(_:since:)` slices them
/// by a date window, so nothing here may round, bucket or de-duplicate them.
///
/// The arrays live in memory and are written back on a debounce: reading the whole array out of `UserDefaults`
/// (an `as? [Int]` conditional cast, per element) and writing it back on every summon showed up on a 51s
/// Instruments trace, against an array that grows all year. The cache is owned by `writeQueue`; reads hop onto it.
struct UsageStats {
    private static let defaults = UserDefaults(suiteName: "\(App.bundleIdentifier).usage")!
    private static let writeQueue = DispatchQueue(label: "UsageStats.writeQueue", qos: .utility)
    private static let maxAge: TimeInterval = 365 * 24 * 3600
    private static let allKeys = ["triggers"]
    /// A summon burst (hold-to-cycle) records repeatedly; coalescing costs at most this much unflushed data
    /// if the app is killed rather than quit, which for usage counters is a better trade than one full array
    /// write per summon. `flushNow` covers the normal quit.
    private static let flushDelay: TimeInterval = 2

    /// `writeQueue`-owned. Nil value = not loaded from `UserDefaults` yet.
    private static var cache = [String: [Int]]()
    private static var dirty = Set<String>()
    private static var flushScheduled = false
    #if DEBUG
    /// Set by `QaSurfaces`, so the counts the About window quotes are the same on every run.
    /// Read in place of what is stored; recording still goes to the real arrays.
    static var qaPinned: [String: [Int]]?
    #endif

    static func recordTrigger() {
        record("triggers")
    }

    static func count(_ key: String, since date: Date) -> Int {
        let threshold = Int(date.timeIntervalSince1970)
        return getTimestamps(key).count { $0 >= threshold }
    }

    static func formatCount(_ n: Int) -> String { UsageStatsTestable.formatCount(n) }

    static func prune() {
        let cutoff = Int(Date().timeIntervalSince1970 - maxAge)
        writeQueue.async {
            for key in allKeys {
                let timestamps = loadOnQueue(key)
                guard !timestamps.isEmpty else { continue }
                let pruned = timestamps.filter { $0 >= cutoff }
                guard pruned.count != timestamps.count else { continue }
                cache[key] = pruned
                dirty.insert(key)
            }
            flushOnQueue()
        }
    }

    /// Write any pending appends synchronously. Called from `applicationWillTerminate`; a SIGTERM/crash skips
    /// it and loses at most `flushDelay` worth of counters.
    static func flushNow() {
        writeQueue.sync { flushOnQueue() }
    }

    private static func record(_ key: String, at timestamp: Int = Int(Date().timeIntervalSince1970)) {
        writeQueue.async {
            ensureLoadedOnQueue(key)
            // `subscript(_:default:)` mutates in place; appending with array concatenation would copy the
            // whole year of timestamps on every summon.
            cache[key, default: []].append(timestamp)
            dirty.insert(key)
            scheduleFlushOnQueue()
        }
    }

    private static func getTimestamps(_ key: String) -> [Int] {
        writeQueue.sync { loadOnQueue(key) }
    }

    // MARK: - writeQueue-only

    private static func ensureLoadedOnQueue(_ key: String) {
        guard cache[key] == nil else { return }
        cache[key] = defaults.object(forKey: key) as? [Int] ?? []
    }

    private static func loadOnQueue(_ key: String) -> [Int] {
        #if DEBUG
        if let qaPinned { return qaPinned[key] ?? [] }
        #endif
        ensureLoadedOnQueue(key)
        return cache[key]!
    }

    private static func scheduleFlushOnQueue() {
        guard !flushScheduled else { return }
        flushScheduled = true
        writeQueue.asyncAfter(deadline: .now() + flushDelay) { flushOnQueue() }
    }

    private static func flushOnQueue() {
        flushScheduled = false
        guard !dirty.isEmpty else { return }
        for key in dirty {
            guard let timestamps = cache[key] else { continue }
            defaults.set(timestamps, forKey: key)
        }
        dirty.removeAll()
    }
}
