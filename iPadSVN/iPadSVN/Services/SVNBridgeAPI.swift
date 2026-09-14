import Foundation

enum SVNBridgeAPI {
    private static let errSize = 2048

    static func initialize() {
        svn_bridge_init()
    }

    static func checkout(
        url: String,
        localPath: String,
        username: String?,
        password: String?
    ) throws -> Int64 {
        var revision: Int64 = 0
        var errbuf = [CChar](repeating: 0, count: errSize)
        let code = url.withCString { urlPtr in
            localPath.withCString { pathPtr in
                username.withCStringOrEmpty { userPtr in
                    password.withCStringOrEmpty { passPtr in
                        svn_bridge_checkout(urlPtr, pathPtr, userPtr, passPtr, &revision, &errbuf, Int32(errSize))
                    }
                }
            }
        }
        try throwIfNeeded(code, errbuf: errbuf)
        return revision
    }

    static func update(wcPath: String, username: String?, password: String?) throws -> Int64 {
        var revision: Int64 = 0
        var errbuf = [CChar](repeating: 0, count: errSize)
        let code = wcPath.withCString { wcPtr in
            username.withCStringOrEmpty { userPtr in
                password.withCStringOrEmpty { passPtr in
                    svn_bridge_update(wcPtr, userPtr, passPtr, &revision, &errbuf, Int32(errSize))
                }
            }
        }
        try throwIfNeeded(code, errbuf: errbuf)
        return revision
    }

    static func wcRevision(wcPath: String) throws -> Int64 {
        var revision: Int64 = 0
        var errbuf = [CChar](repeating: 0, count: errSize)
        let code = wcPath.withCString { wcPtr in
            svn_bridge_wc_revision(wcPtr, &revision, &errbuf, Int32(errSize))
        }
        try throwIfNeeded(code, errbuf: errbuf)
        return revision
    }

    static func statusJSON(wcPath: String, username: String?, password: String?) throws -> String {
        var out: UnsafeMutablePointer<CChar>?
        var errbuf = [CChar](repeating: 0, count: errSize)
        let code = wcPath.withCString { wcPtr in
            username.withCStringOrEmpty { userPtr in
                password.withCStringOrEmpty { passPtr in
                    svn_bridge_status_json(wcPtr, userPtr, passPtr, &out, &errbuf, Int32(errSize))
                }
            }
        }
        defer { if let out { free(out) } }
        try throwIfNeeded(code, errbuf: errbuf)
        guard let out else { return "[]" }
        return String(cString: out)
    }

    static func logJSON(wcPath: String, username: String?, password: String?, limit: Int) throws -> String {
        var out: UnsafeMutablePointer<CChar>?
        var errbuf = [CChar](repeating: 0, count: errSize)
        let code = wcPath.withCString { wcPtr in
            username.withCStringOrEmpty { userPtr in
                password.withCStringOrEmpty { passPtr in
                    svn_bridge_log_json(wcPtr, userPtr, passPtr, Int32(limit), &out, &errbuf, Int32(errSize))
                }
            }
        }
        defer { if let out { free(out) } }
        try throwIfNeeded(code, errbuf: errbuf)
        guard let out else { return "[]" }
        return String(cString: out)
    }

    static func commit(
        wcPath: String,
        username: String?,
        password: String?,
        message: String,
        paths: [String]
    ) throws -> Int64 {
        var revision: Int64 = 0
        var errbuf = [CChar](repeating: 0, count: errSize)
        let pathsJSON = (try? String(data: JSONEncoder().encode(paths), encoding: .utf8)) ?? "[]"
        let code = wcPath.withCString { wcPtr in
            username.withCStringOrEmpty { userPtr in
                password.withCStringOrEmpty { passPtr in
                    message.withCString { msgPtr in
                        pathsJSON.withCString { pathsPtr in
                            svn_bridge_commit(wcPtr, userPtr, passPtr, msgPtr, pathsPtr, &revision, &errbuf, Int32(errSize))
                        }
                    }
                }
            }
        }
        try throwIfNeeded(code, errbuf: errbuf)
        return revision
    }

    static func revert(wcPath: String, username: String?, password: String?, relativePath: String) throws {
        var errbuf = [CChar](repeating: 0, count: errSize)
        let code = wcPath.withCString { wcPtr in
            username.withCStringOrEmpty { userPtr in
                password.withCStringOrEmpty { passPtr in
                    relativePath.withCString { relPtr in
                        svn_bridge_revert(wcPtr, userPtr, passPtr, relPtr, &errbuf, Int32(errSize))
                    }
                }
            }
        }
        try throwIfNeeded(code, errbuf: errbuf)
    }

    static func diffText(wcPath: String, username: String?, password: String?, relativePath: String) throws -> String {
        var out: UnsafeMutablePointer<CChar>?
        var errbuf = [CChar](repeating: 0, count: errSize)
        let code = wcPath.withCString { wcPtr in
            username.withCStringOrEmpty { userPtr in
                password.withCStringOrEmpty { passPtr in
                    relativePath.withCString { relPtr in
                        svn_bridge_diff_text(wcPtr, userPtr, passPtr, relPtr, &out, &errbuf, Int32(errSize))
                    }
                }
            }
        }
        defer { if let out { free(out) } }
        try throwIfNeeded(code, errbuf: errbuf)
        guard let out else { return "" }
        return String(cString: out)
    }

    private static func throwIfNeeded(_ code: Int32, errbuf: [CChar]) throws {
        guard code != 0 else { return }
        let message = String(cString: errbuf)
        throw SVNError.bridge(message.isEmpty ? "SVN 操作失败" : message)
    }
}

private extension Optional where Wrapped == String {
    func withCStringOrEmpty<R>(_ body: (UnsafePointer<CChar>?) -> R) -> R {
        switch self {
        case .some(let s):
            return s.withCString { body($0) }
        case .none:
            return body(nil)
        }
    }
}

extension SVNError {
    static func bridge(_ message: String) -> SVNError {
        .operationFailed(message)
    }
}
