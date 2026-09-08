import Foundation

@MainActor
final class ReadButtonModel: ObservableObject {
    private static let defaultHost = "192.168.31.227"

    enum SetupStep { case address, pin, ready }

    @Published var host: String
    @Published var pin = ""
    @Published var step: SetupStep
    @Published var documents: [DPTDocument] = []
    @Published var selectedDocument: DPTDocument?
    @Published var sortByRecent = true
    @Published var isWorking = false
    @Published var message = ""

    private let client = DPTClient()
    private let defaults = UserDefaults.standard
    private var clientID: String?

    init() {
        let savedHost = UserDefaults.standard.string(forKey: "dptHost")
        host = savedHost == "digitalpaper.local" || savedHost == nil ? Self.defaultHost : savedHost!
        clientID = UserDefaults.standard.string(forKey: "dptClientID")
        sortByRecent = defaults.object(forKey: "sortByRecent") as? Bool ?? true
        step = clientID == nil ? .address : .ready
        if let id = defaults.string(forKey: "documentID"),
           let path = defaults.string(forKey: "documentPath") {
            selectedDocument = DPTDocument(
                id: id,
                path: path,
                currentPage: max(defaults.integer(forKey: "currentPage"), 1),
                totalPages: max(defaults.integer(forKey: "totalPages"), 1),
                modifiedDate: nil
            )
        }
    }

    func beginPairing() async {
        await perform("请查看 DPT 屏幕上的 PIN") {
            _ = try await client.checkConnection(host: host)
            try await client.beginRegistration(host: host)
            step = .pin
        }
    }

    func testConnection() async {
        await perform("") {
            message = try await client.checkConnection(host: host)
            defaults.set(host, forKey: "dptHost")
        }
    }

    func finishPairing() async {
        await perform("配对成功") {
            let id = try await client.finishRegistration(pin: pin)
            clientID = id
            defaults.set(host, forKey: "dptHost")
            defaults.set(id, forKey: "dptClientID")
            pin = ""
            step = .ready
            try await loadDocuments()
        }
    }

    func loadDocuments() async throws {
        guard let clientID else { return }
        let loadedDocuments = try await client.documents(host: host, clientID: clientID)
        let previousPages = savedPageSnapshot()
        let changedDocuments = loadedDocuments.filter { document in
            guard let previousPage = previousPages[document.id] else { return false }
            return previousPage != document.currentPage
        }

        documents = sortDocuments(loadedDocuments)
        if changedDocuments.count == 1, let changedDocument = changedDocuments.first {
            selectedDocument = changedDocument
            save(changedDocument)
            markRecent(changedDocument)
            documents = sortDocuments(loadedDocuments)
        } else if let selectedDocument,
                  let refreshed = loadedDocuments.first(where: { $0.path == selectedDocument.path }) {
            self.selectedDocument = refreshed
            save(refreshed)
        }
        savePageSnapshot(loadedDocuments)
    }

    func refreshDocuments() async {
        await perform("已刷新") { try await loadDocuments() }
    }

    func select(_ document: DPTDocument) async -> Bool {
        guard let clientID else { return false }
        isWorking = true
        message = ""
        defer { isWorking = false }
        do {
            try await client.open(
                documentID: document.id,
                page: document.currentPage,
                host: host,
                clientID: clientID
            )
            selectedDocument = document
            save(document)
            markRecent(document)
            documents = sortDocuments(documents)
            message = "已切换文档"
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func syncCurrentPage() async {
        guard let selectedDocument, let clientID else { return }
        await perform("") {
            let refreshed = try await client.refresh(documentPath: selectedDocument.path, host: host, clientID: clientID)
            self.selectedDocument = refreshed
            save(refreshed)
            markRecent(refreshed)
        }
    }

    func loadOnStart() async {
        await perform("") {
            try await loadDocuments()
            if selectedDocument != nil {
                await syncCurrentPage()
            }
        }
    }

    func changePage(by offset: Int) async {
        guard let document = selectedDocument, let clientID else {
            message = DPTError.noDocument.localizedDescription
            return
        }
        let page = min(max(document.currentPage + offset, 1), document.totalPages)
        guard page != document.currentPage else { return }
        let updated = DPTDocument(
            id: document.id,
            path: document.path,
            currentPage: page,
            totalPages: document.totalPages,
            modifiedDate: Date()
        )
        selectedDocument = updated
        save(updated)
        isWorking = true
        message = ""
        defer { isWorking = false }
        do {
            try await client.open(documentID: document.id, page: page, host: host, clientID: clientID)
            markRecent(updated)
        } catch {
            selectedDocument = document
            save(document)
            message = error.localizedDescription
        }
    }

    func jumpToPage(_ requestedPage: Int) async {
        guard let document = selectedDocument, let clientID else {
            message = DPTError.noDocument.localizedDescription
            return
        }
        await perform("") {
            let current = try await client.refresh(
                documentPath: document.path,
                host: host,
                clientID: clientID
            )
            let page = min(max(requestedPage, 1), current.totalPages)
            guard page != current.currentPage else {
                selectedDocument = current
                save(current)
                return
            }
            try await client.open(documentID: current.id, page: page, host: host, clientID: clientID)
            let updated = DPTDocument(
                id: current.id,
                path: current.path,
                currentPage: page,
                totalPages: current.totalPages,
                modifiedDate: Date()
            )
            selectedDocument = updated
            save(updated)
            markRecent(updated)
        }
    }

    func setSortByRecent(_ enabled: Bool) {
        sortByRecent = enabled
        defaults.set(enabled, forKey: "sortByRecent")
        documents = sortDocuments(documents)
    }

    func reset() {
        for key in ["dptClientID", "documentID", "documentPath", "currentPage", "totalPages"] {
            defaults.removeObject(forKey: key)
        }
        clientID = nil
        selectedDocument = nil
        documents = []
        step = .address
        message = ""
    }

    private func perform(_ success: String, operation: () async throws -> Void) async {
        isWorking = true
        message = ""
        defer { isWorking = false }
        do {
            try await operation()
            message = success
        } catch {
            message = error.localizedDescription
        }
    }

    private func save(_ document: DPTDocument) {
        defaults.set(document.id, forKey: "documentID")
        defaults.set(document.path, forKey: "documentPath")
        defaults.set(document.currentPage, forKey: "currentPage")
        defaults.set(document.totalPages, forKey: "totalPages")
    }

    private func markRecent(_ document: DPTDocument) {
        var values = recentDocuments()
        values[document.id] = Date().timeIntervalSince1970
        defaults.set(values, forKey: "recentDocuments")
    }

    private func recentDocuments() -> [String: Double] {
        let values = defaults.dictionary(forKey: "recentDocuments") ?? [:]
        return values.reduce(into: [:]) { result, item in
            if let timestamp = item.value as? Double {
                result[item.key] = timestamp
            } else if let timestamp = item.value as? NSNumber {
                result[item.key] = timestamp.doubleValue
            }
        }
    }

    private func sortDocuments(_ documents: [DPTDocument]) -> [DPTDocument] {
        guard sortByRecent else {
            return documents.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        let recent = recentDocuments()
        return documents.sorted { left, right in
            let leftTime = recent[left.id] ?? 0
            let rightTime = recent[right.id] ?? 0
            if leftTime != rightTime { return leftTime > rightTime }
            let leftModified = left.modifiedDate?.timeIntervalSince1970 ?? 0
            let rightModified = right.modifiedDate?.timeIntervalSince1970 ?? 0
            if leftModified != rightModified { return leftModified > rightModified }
            if left.currentPage != right.currentPage { return left.currentPage > right.currentPage }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    private func savedPageSnapshot() -> [String: Int] {
        let values = defaults.dictionary(forKey: "documentPages") ?? [:]
        return values.reduce(into: [:]) { result, item in
            if let page = item.value as? Int {
                result[item.key] = page
            } else if let page = item.value as? NSNumber {
                result[item.key] = page.intValue
            }
        }
    }

    private func savePageSnapshot(_ documents: [DPTDocument]) {
        defaults.set(
            Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0.currentPage) }),
            forKey: "documentPages"
        )
    }
}
