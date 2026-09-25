import Foundation

enum BotchPaths {
    static let support = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    ).first!.appendingPathComponent("Botch", isDirectory: true)
}
