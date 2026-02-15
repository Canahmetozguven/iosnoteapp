import Foundation

@Observable
class ModelManager {
    var models: [String] = []
    
    init() {
        refreshModels()
    }
    
    func refreshModels() {
        let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsUrl, includingPropertiesForKeys: nil)
            self.models = fileURLs
                .filter { $0.pathExtension == "gguf" }
                .map { $0.lastPathComponent }
        } catch {
            print("ModelManager: Error listing files - \(error)")
            self.models = []
        }
    }
    
    func getModelPath(filename: String) -> String? {
        let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileUrl = documentsUrl.appendingPathComponent(filename)
        
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            return fileUrl.path
        }
        return nil
    }
}
