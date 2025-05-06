import SwiftUI
import Combine

struct Resource: Identifiable {
    var id: UUID = UUID()
    var name: String
    var urls: [String] = []
}

class ModelStore: ObservableObject {
    @Published var nodes: [Node] = []

    var selectedItems: [Node] {
        nodes.flatMap { $0.selectedItems }
    }
}

@main
struct TreeTableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var modelStore = ModelStore()
    @State private var currentView = CurrentScreen.welcome
    var body: some Scene {
        WindowGroup {
            switch currentView {
            case .welcome:
                WelcomeView(onContinue: {
                    modelStore.nodes = loadNodesFromJSON(named: "models")
                    currentView = .selection
                })
            case .selection:
                ContentView(
                    modelStore: modelStore,
                    onBack: {
                        currentView = .welcome
                    },
                    onContinue: {
                        currentView = .download
                    }
                )
                .frame(width: 500, height: 400)
                .onAppear() {
                    if let window = NSApplication.shared.windows.first {
                        window.center()
                    }
                }
            case .download:
                DownloadView(currentView: $currentView, items: modelStore.selectedItems)
                    .frame(width: 500, height: 400)
            case .conclusion:
                CompletionView()
                    .frame(width: 500, height: 400)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.delegate = self
            window.setContentSize(NSSize(width: 500, height: 400))
            window.center()
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

enum CurrentScreen {
    case welcome
    case selection
    case download
    case conclusion
}

struct WelcomeView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.accentColor)

            Text("Welcome to the Setup Wizard")
                .font(.title)
                .fontWeight(.bold)

            Text("This wizard will help you configure and launch OpenVINO in Audacity.")
                .multilineTextAlignment(.center)
                .padding()

            Button("Continue") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}

enum CheckState {
    case checked
    case unchecked
    case mixed
}

struct FileInfo: Codable {
    let url: String
    let sha256: String
    let dsize: Int
    let esize: Int
}

class Node: Identifiable, ObservableObject, Decodable {
    let id = UUID()
    let name: String
    let description: String
    let dir: String
    let files: [FileInfo]
    
    @Published var state: CheckState = .unchecked
    @Published var children: [Node]?
    weak var parent: Node?

    var downloadSizeRecursive: Int {
        let ownSize = files.map { $0.dsize }.reduce(0, +)
        let childSize = (children ?? [])
            .filter { $0.state == .checked }
            .map { $0.downloadSize }
            .reduce(0, +)
        return ownSize + childSize
    }

    var extractedSizeRecursive: Int {
        let ownSize = files.map { $0.esize }.reduce(0, +)
        let childSize = (children ?? [])
            .filter { $0.state == .checked }
            .map { $0.extractedSize }
            .reduce(0, +)
        return ownSize + childSize
    }
    
    var downloadSize: Int {
        return files.map { $0.dsize }.reduce(0, +)
    }

    var extractedSize: Int {
        return files.map { $0.esize }.reduce(0, +)
    }
    
    var selectedItems: [Node] {
        var results: [Node] = []

        if state != .unchecked {
            results.append(self)
        }

        for child in children ?? [] {
            results.append(contentsOf: child.selectedItems)
        }

        return results
    }

    enum CodingKeys: CodingKey {
        case name, description, dir, files, children
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decode(String.self, forKey: .description)
        self.dir = try container.decode(String.self, forKey: .dir)
        self.files = try container.decodeIfPresent([FileInfo].self, forKey: .files) ?? []
        self.children = try container.decodeIfPresent([Node].self, forKey: .children)

        self.children?.forEach { $0.parent = self }
    }
}

struct ContentView: View {
    @ObservedObject var modelStore: ModelStore
    @StateObject var viewModel = TreeViewModel()

    var onBack: () -> Void
    var onContinue: () -> Void
    
    init(modelStore: ModelStore, onBack: @escaping () -> Void, onContinue: @escaping () -> Void) {
        self.modelStore = modelStore
        self.onBack = onBack
        self.onContinue = onContinue
        _viewModel = StateObject(wrappedValue: TreeViewModel(nodes: modelStore.nodes))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                OutlineGroup(viewModel.nodes, id: \.id, children: \.children) { node in
                    CheckboxView(node: node)
                        .onTapGesture { viewModel.toggle(node: node) }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            
            Divider()
            
            HStack {
                SizeInfoView(
                    label: "Total Download Size:",
                    size: viewModel.totalDownloadSize
                )
                SizeInfoView(
                    label: "Total Extracted Size:",
                    size: viewModel.totalExtractedSize
                )
            }
            .padding()
            
            HStack {
                Spacer()
                Button("Download selected", systemImage: "arrow.down.to.line") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Download Wizard")
    }
}

struct CheckboxView: View {
    @ObservedObject var node: Node
    
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: systemImageName)
                        .foregroundColor(node.state == .checked ? .blue : .primary)
                    Text(node.name)
                        .font(.body)
                }
                HStack(spacing: 16) {
                    Text("Download: \(node.downloadSizeRecursive.formatted(.byteCount(style: .file)))")
                        .foregroundColor(.secondary)
                    Text("Extracted: \(node.extractedSizeRecursive.formatted(.byteCount(style: .file)))")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(.leading, node.children != nil ? 0 : 16)
    }
    
    private var systemImageName: String {
        switch node.state {
        case .checked: return "checkmark.square.fill"
        case .unchecked: return "square"
        case .mixed: return "minus.square.fill"
        }
    }
}

struct SizeInfoView: View {
    let label: String
    let size: Int
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(size.formatted(.byteCount(style: .file)))
                .font(.system(.body, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

class TreeViewModel: ObservableObject {

    @Published var nodes: [Node]

    @Published var totalDownloadSize = 0
    @Published var totalExtractedSize = 0
    
    init(nodes: [Node] = []) {
        self.nodes = nodes
        self.totalDownloadSize = totalDownloadSize
        self.totalExtractedSize = totalExtractedSize
    }
    
    func toggle(node: Node) {
        let newState: CheckState = node.state == .checked ? .unchecked : .checked
        node.state = newState
        updateChildren(node: node, state: newState)
        updateParentState(node.parent)
        calculateTotals()
    }
    
    private func calculateTotals() {
        totalDownloadSize = calculateTotal(for: \.downloadSizeRecursive)
        totalExtractedSize = calculateTotal(for: \.extractedSizeRecursive)
    }

    private func updateChildren(node: Node, state: CheckState) {
        node.children?.forEach {
            $0.state = state
            updateChildren(node: $0, state: state)
        }
    }
    
    private func updateParentState(_ parent: Node?) {
        guard let parent = parent else { return }
        
        let childrenStates = parent.children?.map { $0.state } ?? []
        let allChecked = childrenStates.allSatisfy { $0 == .checked }
        let allUnchecked = childrenStates.allSatisfy { $0 == .unchecked }
        
        parent.state = allChecked ? .checked :
                      allUnchecked ? .unchecked : .mixed
        
        updateParentState(parent.parent)
    }
    
    private func calculateTotal(for keyPath: KeyPath<Node, Int>) -> Int {
        var total = 0
        for node in nodes {
            if node.state != .unchecked {
                total += node[keyPath: keyPath]
            }
        }
        return total
    }
}

private func loadNodesFromJSON(named filename: String) -> [Node] {
    guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
        fatalError("Unable to find \(filename).json in bundle.")
    }
    
    do {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode([Node].self, from: data)
    } catch {
        print("Tried to load from: \(url)")
        print("Error: \(error)")
        fatalError("Failed to load or decode \(filename).json: \(error)")
    }
}

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

struct DownloadView: View {
    @Binding var currentView: CurrentScreen
    @StateObject private var downloadManager: DownloadManager
    private let totalItems: Int
    var buttonText: String {
        downloadManager.completedItems == totalItems ? "Finish" : "Cancel"
    }
    
    init(currentView: Binding<CurrentScreen>, items: [Node]) {
        _currentView = currentView
        _downloadManager = StateObject(wrappedValue: DownloadManager(items: items))
        totalItems = items.count
    }
    
    var body: some View {
        VStack(spacing: 20) {
            if let error = downloadManager.error {
                VStack(spacing: 24) {
                    Text("An error occurred")
                        .font(.title)
                        .bold()

                    Text(error.localizedDescription)
                        .font(.body)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    HStack(spacing: 20) {
                        Button("Retry") {
                            downloadManager.startDownloads()
                        }
                        .keyboardShortcut(.defaultAction)

                        Button("Cancel Installation") {
                            exit(-1)
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                }
            }
            else {
                VStack {
                    Text("Total Progress")
                        .font(.headline)
                    ProgressView(value: Double(downloadManager.completedItems), total: Double(totalItems))
                    Text("\(downloadManager.completedItems)/\(totalItems) items downloaded")
                        .font(.caption)
                }
                .padding()
                
                if let currentItem = downloadManager.currentDownloadItem {
                    VStack {
                        let itemName = currentItem.item
                        let label = itemName.parent != nil
                        ? "Downloading: \(itemName.parent!.name): \(itemName.name)"
                        : "Downloading: \(itemName.name)"
                        
                        Text(label)
                            .font(.headline)
                        ProgressView(value: currentItem.progress)
                        Text("\(Int(currentItem.progress * 100))% complete")
                            .font(.caption)
                    }
                    .padding()
                    .transition(.opacity)
                }
            }
        }
        .padding()
        .onAppear {
            downloadManager.startDownloads()
        }
        .onChange(of: downloadManager.isFinished) { finished in
            if (finished) {
                currentView = .conclusion
            }
        }
        
        .navigationTitle("Download Wizard")
    }
}

struct CompletionView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.green)
            
            Text("All Done!")
                .font(.title)
                .fontWeight(.bold)
            
            Text("All components were installed successfully. To start using OpenVINO features in Audacity, please restart the application.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Text("Once restarted, you'll be able to access enhanced AI-powered effects and tools powered by OpenVINO.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            Spacer()
            HStack {
                Spacer()
                Button("Finish") {
                    closeWindow()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .padding()
        .navigationTitle("Download Wizard")
    }
    func closeWindow() {
        NSApp.keyWindow?.close()
    }
}
