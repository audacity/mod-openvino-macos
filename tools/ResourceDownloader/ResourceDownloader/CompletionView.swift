import SwiftUI

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
        .navigationTitle("Model Downloader")
    }
    func closeWindow() {
        NSApp.keyWindow?.close()
    }
}
