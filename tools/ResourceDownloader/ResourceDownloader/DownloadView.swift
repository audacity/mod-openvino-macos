import SwiftUI

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
        
        .navigationTitle("Model Downloader")
    }
}
