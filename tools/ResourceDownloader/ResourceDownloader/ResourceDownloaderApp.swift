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
    var progress: Double = 0.0
    var isDownloading = false
    var isCompleted = false
}

class DownloadManager: ObservableObject {
    @Published var items: [DownloadItem]
    @Published var currentDownloadItem: DownloadItem?
    @Published var completedItems = 0 {
        didSet {
            if completedItems == items.count {
                isFinished = true
            }
        }
    }
    @Published var isFinished: Bool
    
    private var cancellables = Set<AnyCancellable>()
    
    init(items: [Node]) {
        self.items = items.map { DownloadItem(item: $0) }
        self.isFinished = false
    }
    
    func startDownloads() {
        processNextDownload()
    }
    
    private func processNextDownload() {
        guard let nextItem = items.first(where: { !$0.isCompleted && !$0.isDownloading }) else {
            return
        }
        
        guard !nextItem.item.files.isEmpty else {
            if let index = items.firstIndex(where: { $0.id == nextItem.id }) {
                items[index].isCompleted = true
            }
            processNextDownload()
            return
        }
        
        var currentItem = nextItem
        currentItem.isDownloading = true
        if let index = items.firstIndex(where: { $0.id == currentItem.id }) {
            items[index] = currentItem
        }
        currentDownloadItem = currentItem
        
        for file in currentItem.item.files {
            let url = URL(string: file.url)!
            let request = URLRequest(url: url)
            let session = URLSession.shared
            let task = session.downloadTask(with: request) { [weak self] tempURL, response, error in
                guard let self = self, let tempURL = tempURL else { return }

                
                let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
                var destinationDir = homeDirectory.appendingPathComponent("Library/Application Support/audacity/openvino-models")

                destinationDir = destinationDir.appendingPathComponent(currentItem.item.dir, isDirectory: true)
                do {
                    // Create the directory if it doesn't exist
                    try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
                    print("Directory created or already exists at: \(destinationDir.path)")
                } catch {
                    print("Failed to create directory: \(error)")
                }

                do {
                    try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

                    let filename = url.lastPathComponent
                    let destinationPath = destinationDir.appendingPathComponent(filename)

                    // Move downloaded file to destination
                    try FileManager.default.moveItem(at: tempURL, to: destinationPath)

                    // Extract based on file extension
                    if filename.hasSuffix(".zip") {
                        let unzipTask = Process()
                        unzipTask.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                        unzipTask.arguments = ["-o", destinationPath.path, "-d", destinationDir.path]
                        try unzipTask.run()
                        unzipTask.waitUntilExit()
                        try FileManager.default.removeItem(at: destinationPath)
                    } else if filename.hasSuffix(".tar.gz") {
                        let tarTask = Process()
                        tarTask.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                        tarTask.arguments = ["-xzf", destinationPath.path, "-C", destinationDir.path]
                        try tarTask.run()
                        tarTask.waitUntilExit()
                        try FileManager.default.removeItem(at: destinationPath)
                    }

                } catch {
                    print("Error during file handling: \(error)")
                }

                DispatchQueue.main.async {
                    if let index = self.items.firstIndex(where: { $0.id == currentItem.id }) {
                        self.items[index].isDownloading = false
                        self.items[index].isCompleted = true
                        self.completedItems += 1
                        self.currentDownloadItem = nil
                        self.processNextDownload()
                    }
                }
            }
            
            let progressObserver = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                DispatchQueue.main.async {
                    if let index = self?.items.firstIndex(where: { $0.id == currentItem.id }) {
                        self?.items[index].progress = progress.fractionCompleted
                        self?.currentDownloadItem = self?.items[index]
                    }
                }
            }
            
            cancellables.insert(AnyCancellable {
                progressObserver.invalidate()
            })
            
            task.resume()
        }
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
            // Overall progress
            VStack {
                Text("Total Progress")
                    .font(.headline)
                ProgressView(value: Double(downloadManager.completedItems), total: Double(totalItems))
                Text("\(downloadManager.completedItems)/\(totalItems) items downloaded")
                    .font(.caption)
            }
            .padding()
            
            // Current item progress
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
