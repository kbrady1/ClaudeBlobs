import Foundation

enum NtfyClient {
    static func send(
        endpoint: String,
        topic: String,
        message: String,
        title: String? = nil,
        priority: String? = nil,
        tags: String? = nil
    ) {
        let urlString = "\(endpoint)/\(topic)"
        guard let url = URL(string: urlString) else {
            DebugLog.shared.log("NtfyClient: invalid URL \(urlString)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = message.data(using: .utf8)

        if let title { request.setValue(title, forHTTPHeaderField: "Title") }
        if let priority { request.setValue(priority, forHTTPHeaderField: "Priority") }
        if let tags { request.setValue(tags, forHTTPHeaderField: "Tags") }

        DebugLog.shared.log("NtfyClient: POST \(urlString) title=\(title ?? "nil")")

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                DebugLog.shared.log("NtfyClient: error \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                DebugLog.shared.log("NtfyClient: unexpected status \(http.statusCode)")
                return
            }
            DebugLog.shared.log("NtfyClient: sent successfully")
        }.resume()
    }
}
