import SwiftUI
import FFmpegAutoCore

@main
struct FFmpegAutoApp: App {
    var body: some Scene {
        WindowGroup {
            AppView(viewModel: AppViewModel(), filePicker: AppKitFilePicker())
                .frame(minWidth: 640, minHeight: 430)
        }
        .windowStyle(.titleBar)
    }
}
