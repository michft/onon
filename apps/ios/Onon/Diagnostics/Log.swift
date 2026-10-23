import os

/// Unified-logging channels. View in Console.app (filter subsystem `au.local.onon`) or collect after a walk with
/// `log collect --device`. `.notice` and above persist on the phone; `.debug` only appears while streaming.
enum Log {
    private static let subsystem = "au.local.onon"

    static let location = Logger(subsystem: subsystem, category: "location")
    static let recording = Logger(subsystem: subsystem, category: "recording")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let map = Logger(subsystem: subsystem, category: "map")
}
