import SwiftUI

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
        .navigationTitle("Model Downloader")
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
