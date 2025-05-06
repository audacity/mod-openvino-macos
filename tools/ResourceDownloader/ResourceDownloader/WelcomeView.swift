import SwiftUI

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
        
        .navigationTitle("Model Downloader")
    }
}
