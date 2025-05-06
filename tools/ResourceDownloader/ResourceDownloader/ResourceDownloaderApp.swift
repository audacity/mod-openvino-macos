import SwiftUI
import Combine

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
