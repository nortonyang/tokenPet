import Foundation
import SQLite3

enum AntigravityStateStore {
    static let oauthTokenKey = "antigravityUnifiedStateSync.oauthToken"
    static let userStatusKey = "antigravityUnifiedStateSync.userStatus"
    
    static var stateDBURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Antigravity/User/globalStorage/state.vscdb")
    }
    
    static func oauthAccessToken() -> String? {
        readValue(forKey: oauthTokenKey)
    }
    
    static func userStatusIdentity() -> String? {
        guard let value = readValue(forKey: userStatusKey) else { return nil }
        let lower = value.lowercased()
        guard lower != "null", lower != "undefined", lower != "false" else { return nil }
        return value
    }
    
    static func readValue(forKey key: String) -> String? {
        let url = stateDBURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(db) }
        
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let cStr = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        
        let value = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
