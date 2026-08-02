//
//  AppSettings.swift
//  Grabbit
//

import Foundation
import CoreGraphics

enum AppSettings {
    private static let destinationFolderKey = "destinationFolderPath"

    static let spotlightDimOpacityNotches: [CGFloat] = [0, 0.05, 0.15, 0.30, 0.60]
    static let spotlightBlurRadiusNotches: [CGFloat] = [0, 1, 2, 5, 10]
    static let spotlightDimOpacityDefault: CGFloat = 0.30
    static let spotlightBlurRadiusDefault: CGFloat = 5

    static func snapSpotlightDimOpacity(_ value: CGFloat) -> CGFloat {
        spotlightDimOpacityNotches.min(by: { abs($0 - value) < abs($1 - value) }) ?? spotlightDimOpacityDefault
    }

    static func snapSpotlightBlurRadius(_ value: CGFloat) -> CGFloat {
        spotlightBlurRadiusNotches.min(by: { abs($0 - value) < abs($1 - value) }) ?? spotlightBlurRadiusDefault
    }

    static func spotlightDimOpacityIndex(for value: CGFloat) -> Int {
        let snapped = snapSpotlightDimOpacity(value)
        return spotlightDimOpacityNotches.firstIndex(of: snapped) ?? 3
    }

    static func spotlightBlurRadiusIndex(for value: CGFloat) -> Int {
        let snapped = snapSpotlightBlurRadius(value)
        return spotlightBlurRadiusNotches.firstIndex(of: snapped) ?? 3
    }

    static var destinationFolderURL: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: destinationFolderKey) {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                    return URL(fileURLWithPath: path, isDirectory: true)
                }
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        }
        set {
            let path = newValue.standardizedFileURL.path
            let previous = UserDefaults.standard.string(forKey: destinationFolderKey)
            UserDefaults.standard.set(path, forKey: destinationFolderKey)
            if previous != path {
                // Library / menu scope to this folder — refresh when it changes.
                NotificationCenter.default.post(name: .captureHistoryDidChange, object: nil)
            }
        }
    }

    static var destinationFolderDisplayPath: String {
        let path = destinationFolderURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    static func ensureDestinationFolderExists() throws {
        try FileManager.default.createDirectory(
            at: destinationFolderURL,
            withIntermediateDirectories: true
        )
    }
}
