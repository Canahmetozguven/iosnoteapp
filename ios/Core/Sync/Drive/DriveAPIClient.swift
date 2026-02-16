import Foundation

struct DriveFile: Codable, Hashable {
    var id: String
    var name: String?
    var createdTime: String?
    var size: String?
    var mimeType: String?
}

enum DriveAPIError: Error {
    case notAuthenticated
    case badResponse
    case missingLocation
}

final class DriveAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func findFolderId(named name: String, accessToken: String) async throws -> String? {
        let q = "mimeType='application/vnd.google-apps.folder' and name='\(name)' and trashed=false and 'root' in parents"
        let fields = "files(id,name)"
        let url = URL(string: "https://www.googleapis.com/drive/v3/files?q=\(q.urlQueryEncoded())&fields=\(fields.urlQueryEncoded())")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw DriveAPIError.badResponse }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [[String: Any]]
        let first = files?.first
        return first?["id"] as? String
    }

    func createFolder(named name: String, accessToken: String) async throws -> String {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder",
            "parents": ["root"]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw DriveAPIError.badResponse }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = json?["id"] as? String else { throw DriveAPIError.badResponse }
        return id
    }

    func listBackups(inFolderId folderId: String, accessToken: String) async throws -> [DriveFile] {
        let q = "'\(folderId)' in parents and trashed=false and name contains 'synapsnotes-backup-'"
        let fields = "files(id,name,createdTime,size)"
        let url = URL(string: "https://www.googleapis.com/drive/v3/files?q=\(q.urlQueryEncoded())&orderBy=createdTime%20desc&fields=\(fields.urlQueryEncoded())")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw DriveAPIError.badResponse }
        struct Wrapper: Codable { var files: [DriveFile] }
        return try JSONDecoder().decode(Wrapper.self, from: data).files
    }

    func listFiles(inFolderId folderId: String, accessToken: String) async throws -> [DriveFile] {
        let q = "'\(folderId)' in parents and trashed=false and mimeType != 'application/vnd.google-apps.folder'"
        let fields = "files(id,name,createdTime,size,mimeType)"
        let url = URL(string: "https://www.googleapis.com/drive/v3/files?q=\(q.urlQueryEncoded())&orderBy=modifiedTime%20desc&fields=\(fields.urlQueryEncoded())")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DriveAPIError.badResponse
        }
        struct Wrapper: Codable { var files: [DriveFile] }
        return try JSONDecoder().decode(Wrapper.self, from: data).files
    }

    func uploadResumable(fileURL: URL, fileName: String, mimeType: String, folderId: String, accessToken: String) async throws -> DriveFile {
        let startURL = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable")!
        var startReq = URLRequest(url: startURL)
        startReq.httpMethod = "POST"
        startReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        startReq.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        startReq.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value
        if let fileSize {
            startReq.setValue("\(fileSize)", forHTTPHeaderField: "X-Upload-Content-Length")
        }
        let meta: [String: Any] = [
            "name": fileName,
            "parents": [folderId]
        ]
        startReq.httpBody = try JSONSerialization.data(withJSONObject: meta)

        let (_, startResp) = try await session.data(for: startReq)
        guard let http = startResp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw DriveAPIError.badResponse }
        guard let loc = http.value(forHTTPHeaderField: "Location"), let uploadURL = URL(string: loc) else {
            throw DriveAPIError.missingLocation
        }

        var putReq = URLRequest(url: uploadURL)
        putReq.httpMethod = "PUT"
        putReq.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let data = try Data(contentsOf: fileURL)
        let (respData, putResp) = try await session.upload(for: putReq, from: data)
        guard let http2 = putResp as? HTTPURLResponse, (200...299).contains(http2.statusCode) else { throw DriveAPIError.badResponse }
        return try JSONDecoder().decode(DriveFile.self, from: respData)
    }

    func downloadFile(fileId: String, to localURL: URL, accessToken: String) async throws {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (tmp, resp) = try await session.download(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw DriveAPIError.badResponse }
        try? FileManager.default.removeItem(at: localURL)
        try FileManager.default.moveItem(at: tmp, to: localURL)
    }
}

private extension String {
    func urlQueryEncoded() -> String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
