import Foundation
import SwiftData

@Model
public final class SessionMetadata {
    @Attribute(.unique) public var sessionID: String
    public var workspaceBookmark: Data?
    public var workspacePath: String?
    public var lastReadEventID: UInt64
    public var unreadTerminalEvents: Int

    public init(sessionID: String, workspaceURL: URL? = nil) {
        self.sessionID = sessionID
        workspacePath = workspaceURL?.path
        workspaceBookmark = try? workspaceURL?.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        lastReadEventID = 0
        unreadTerminalEvents = 0
    }

    public var workspaceURL: URL? {
        var stale = false
        if let workspaceBookmark, let url = try? URL(resolvingBookmarkData: workspaceBookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) { return url }
        return workspacePath.map(URL.init(fileURLWithPath:))
    }
}
