import SwiftUI
import Combine

struct DownloadItem: Identifiable {
    let id = UUID()
    let item: Node
    var fileProgress: [URL: Double] = [:]
    var isDownloading = false
    var isCompleted = false
    var completedFiles: Int = 0
    
    var progress: Double {
        item.files.reduce(0.0) {
            $0 + (fileProgress[URL(string: $1.url)!] ?? 0.0)
        } / Double(item.files.count)
    }
}

class DownloadManager: ObservableObject {
    @Published var items: [DownloadItem]
    @Published var currentDownloadItem: DownloadItem?
    @Published var completedItems = 0
    @Published var isFinished = false
    @Published var error: Error?
    
    private var cancellables = Set<AnyCancellable>()
    private var activeTasks: [URLSessionTask] = []
    private var retryCounts: [URL: Int] = [:]
    private let maxRetries = 3

    init(items: [Node]) {
        self.items = items.map { DownloadItem(item: $0) }
    }

    func startDownloads() {
        guard !items.isEmpty else { return }
        error = nil
        processNextDownload()
    }

    private func processNextDownload() {
        guard error == nil else { return }
        
        guard let nextItem = items.first(where: { !$0.isCompleted && !$0.isDownloading }) else {
            isFinished = completedItems == items.count
            return
        }
        
        guard !nextItem.item.files.isEmpty else {
            completeItem(nextItem)
            return
        }
        
        activateItem(nextItem)
        nextItem.item.files.forEach { startDownload(file: $0, for: nextItem) }
    }

    private func startDownload(file: FileInfo, for item: DownloadItem) {
        guard let url = URL(string: file.url) else {
            handleDownloadError(NSError(domain: "Invalid URL", code: -1), file: file, item: item)
            return
        }

        var task: URLSessionDownloadTask!
        task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            guard let self = self else { return }
            
            defer { DispatchQueue.main.async { self.activeTasks.removeAll { $0 == task } } }
            
            if let error = error {
                self.handleDownloadError(error, file: file, item: item)
                return
            }
            
            guard let tempURL = tempURL else {
                self.handleDownloadError(NSError(domain: "No Temp File", code: -2), file: file, item: item)
                return
            }
            
            self.processFile(tempURL, file: file, item: item)
        }
        
        trackProgress(task: task, file: file, item: item)
        task.resume()
        activeTasks.append(task)
    }

    private func processFile(_ tempURL: URL, file: FileInfo, item: DownloadItem) {
        do {
            let destinationDir = try createDestinationDirectory(for: item)
            let (destinationPath, filename) = try moveDownloadedFile(tempURL, file: file, to: destinationDir)
            try extractFileIfNeeded(at: destinationPath, filename: filename, in: destinationDir)
            
            DispatchQueue.main.async {
                self.handleDownloadSuccess(file: file, item: item)
            }
        } catch {
            DispatchQueue.main.async {
                self.handleDownloadError(error, file: file, item: item)
            }
        }
    }
    
    private func activateItem(_ item: DownloadItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isDownloading = true
        currentDownloadItem = items[index]
    }

    private func completeItem(_ item: DownloadItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isCompleted = true
        completedItems += 1
        processNextDownload()
    }

    private func trackProgress(task: URLSessionTask, file: FileInfo, item: DownloadItem) {
        let progressObserver = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                guard let self = self,
                      let index = self.items.firstIndex(where: { $0.id == item.id }),
                      let url = URL(string: file.url) else { return }
                
                self.items[index].fileProgress[url] = progress.fractionCompleted
                self.currentDownloadItem = self.items[index]
            }
        }
        cancellables.insert(AnyCancellable { progressObserver.invalidate() })
    }

    private func createDestinationDirectory(for item: DownloadItem) throws -> URL {
        let destinationDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/audacity/openvino-models")
            .appendingPathComponent(item.item.dir, isDirectory: true)
        
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        return destinationDir
    }

    private func moveDownloadedFile(_ tempURL: URL, file: FileInfo, to destinationDir: URL) throws -> (URL, String) {
        let filename = URL(string: file.url)!.lastPathComponent
        let destinationPath = destinationDir.appendingPathComponent(filename)
        try FileManager.default.moveItem(at: tempURL, to: destinationPath)
        return (destinationPath, filename)
    }

    private func extractFileIfNeeded(at path: URL, filename: String, in directory: URL) throws {
        if filename.hasSuffix(".zip") {
            try runProcess("/usr/bin/unzip", ["-o", path.path, "-d", directory.path])
            try FileManager.default.removeItem(at: path)
        } else if filename.hasSuffix(".tar.gz") {
            try runProcess("/usr/bin/tar", ["-xzf", path.path, "-C", directory.path])
            try FileManager.default.removeItem(at: path)
        }
    }

    private func runProcess(_ command: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
    }

    private func handleDownloadSuccess(file: FileInfo, item: DownloadItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              let fileURL = URL(string: file.url) else { return }
        
        items[index].fileProgress[fileURL] = 1.0
        items[index].completedFiles += 1
        
        if items[index].completedFiles == items[index].item.files.count {
            items[index].isCompleted = true
            items[index].isDownloading = false
            completedItems += 1
            currentDownloadItem = nil
            processNextDownload()
        }
    }

    private func handleDownloadError(_ error: Error, file: FileInfo, item: DownloadItem) {
        guard let fileURL = URL(string: file.url) else {
            fatalError("Invalid file URL in error handler")
        }

        let retries = retryCounts[fileURL, default: 0]
        
        if retries < maxRetries {
            retryCounts[fileURL] = retries + 1
            startDownload(file: file, for: item)
        } else {
            DispatchQueue.main.async {
                self.error = error
                self.cancelAllDownloads()
            }
        }
    }

    private func cancelAllDownloads() {
        activeTasks.forEach { $0.cancel() }
        activeTasks.removeAll()
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        
        items.indices.forEach { items[$0].isDownloading = false }
        currentDownloadItem = nil
    }
}
