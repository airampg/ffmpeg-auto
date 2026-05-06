import SwiftUI
import FFmpegAutoCore
import FFmpegAutoCoreMac

struct AppView: View {
    @StateObject var viewModel: AppViewModel
    let filePicker: FilePicking
    @State private var isShowingLogs = false
    @State private var isShowingAdvancedConfiguration = false
    @State private var activeAlert: ActiveAlert?
    @FocusState private var focusedField: Field?

    enum Field { case segmentMinutes, bitrate, filenamePrefix, extraArguments, ffmpegPath }

    enum ActiveAlert: Identifiable {
        case success(URL, Int?)
        case trashPrompt
        case error(String)

        var id: String {
            switch self {
            case .success: "success"
            case .trashPrompt: "trashPrompt"
            case .error: "error"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                sectionCard { form }
                sectionCard { advancedConfiguration }
                controls
                statusArea
                sectionCard { detailsArea }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .background(appBackground)
        .onChange(of: viewModel.postRunPromptState) { _, promptState in
            switch promptState {
            case .completion(let folder, let count):
                activeAlert = .success(folder, count)
            case .trashPrompt:
                activeAlert = .trashPrompt
            case .error(let message):
                activeAlert = .error(message)
            case .none:
                break
            }
        }
        .onChange(of: viewModel.segmentMinutesDraft) { _, newValue in
            viewModel.segmentMinutesDraftChanged(newValue)
        }
        .onChange(of: viewModel.settings) { _, _ in
            viewModel.advancedSettingsChanged()
        }
        .alert(item: $activeAlert, content: alert)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [.blue.opacity(0.95), .teal.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .blue.opacity(0.18), radius: 12, y: 6)
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 31, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 62, height: 62)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Meeting Audio Chunker")
                    .font(.largeTitle.weight(.semibold))
                Text("Turn a recording into small audio chunks that are easy to send to transcription tools.")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var appBackground: some View {
        LinearGradient(
            colors: [Color(nsColor: .windowBackgroundColor), Color.accentColor.opacity(0.06)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.08))
            }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    Text("Input file")
                    HStack {
                        Text(viewModel.inputFile?.path ?? "No file selected")
                            .foregroundStyle(viewModel.inputFile == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Browse...") {
                            Task { viewModel.inputFile = await filePicker.pickInputFile() }
                        }
                        .disabled(viewModel.isProcessing)
                        .accessibilityLabel("Browse for input media file")
                    }
                }

                GridRow {
                    Text("Output folder")
                    HStack {
                        Text(viewModel.outputFolder?.path ?? "No folder selected")
                            .foregroundStyle(viewModel.outputFolder == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose...") {
                            Task { viewModel.outputFolder = await filePicker.pickOutputFolder() }
                        }
                        .disabled(viewModel.isProcessing)
                        .accessibilityLabel("Choose output folder")
                    }
                }

                GridRow {
                    Text("Segment length")
                    HStack(spacing: 8) {
                        TextField("15", text: $viewModel.segmentMinutesDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 76)
                            .focused($focusedField, equals: .segmentMinutes)
                            .onSubmit { viewModel.commitSegmentMinutesDraft() }
                            .disabled(viewModel.isProcessing)
                            .accessibilityLabel("Segment length in minutes")
                        Stepper("", value: Binding(
                            get: { viewModel.segmentMinutes },
                            set: { viewModel.setSegmentMinutes($0) }
                        ), in: 1...180)
                        .labelsHidden()
                        .disabled(viewModel.isProcessing)
                        Text("minutes")
                            .foregroundStyle(.secondary)
                        Text("1 to 180")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: focusedField) { oldValue, newValue in
                if oldValue == .segmentMinutes && newValue != .segmentMinutes {
                    viewModel.commitSegmentMinutesDraft()
                }
                if oldValue != nil && newValue != oldValue {
                    viewModel.advancedSettingsChanged()
                }
            }
            Text(viewModel.segmentDurationMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Segment duration validation message")
        }
    }

    private var advancedConfiguration: some View {
        DisclosureGroup(isExpanded: $isShowingAdvancedConfiguration) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Defaults are tuned for meeting transcription. Change these only when you need a different audio format or compatibility target.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GroupBox("Encoding") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 12) {
                        GridRow {
                            Text("Audio codec")
                            Picker("Audio codec", selection: $viewModel.settings.codec) {
                                ForEach(AudioCodec.allCases) { codec in
                                    Text(codec.displayName).tag(codec)
                                }
                            }
                            .help("AAC/M4A is the default for compact transcription-friendly chunks.")
                            .disabled(viewModel.isProcessing)
                        }

                        GridRow {
                            Text("Output container")
                            Picker("Output container", selection: $viewModel.settings.container) {
                                ForEach(OutputContainer.allCases) { container in
                                    Text(container.displayName).tag(container)
                                }
                            }
                            .help("Choose the file extension/container that matches the selected codec.")
                            .disabled(viewModel.isProcessing)
                        }

                        GridRow {
                            Text("Audio bitrate")
                            TextField("48k", text: $viewModel.settings.bitrate)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                                .focused($focusedField, equals: .bitrate)
                                .help("Use values such as 48k, 64k, 96k, or 128k. Ignored for WAV/PCM.")
                                .disabled(viewModel.isProcessing)
                        }

                        GridRow {
                            Text("Sample rate")
                            Picker("Sample rate", selection: $viewModel.settings.sampleRate) {
                                ForEach([8000, 12000, 16000, 22050, 24000, 32000, 44100, 48000], id: \.self) { rate in
                                    Text("\(rate) Hz").tag(rate)
                                }
                            }
                            .help("16000 Hz is a good default for speech transcription.")
                            .disabled(viewModel.isProcessing)
                        }

                        GridRow {
                            Text("Channels")
                            Picker("Channels", selection: $viewModel.settings.channelCount) {
                                ForEach(AudioChannelCount.allCases) { channelCount in
                                    Text(channelCount.displayName).tag(channelCount)
                                }
                            }
                            .help("Mono keeps files small and works well for meeting speech.")
                            .disabled(viewModel.isProcessing)
                        }
                    }
                }

                GroupBox("Output Naming") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 12) {
                        GridRow {
                            Text("Filename prefix")
                            TextField("meeting", text: $viewModel.settings.filenamePrefix)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                                .focused($focusedField, equals: .filenamePrefix)
                                .help("Generated files use this prefix plus the selected input filename stem.")
                                .disabled(viewModel.isProcessing)
                        }

                        GridRow {
                            Text("Collision policy")
                            Picker("Output collision policy", selection: $viewModel.settings.collisionPolicy) {
                                ForEach(OutputCollisionPolicy.allCases) { policy in
                                    Text(policy.displayName).tag(policy)
                                }
                            }
                            .help("Safe default stops before overwriting matching output chunks.")
                            .disabled(viewModel.isProcessing)
                        }
                    }
                    .padding(.top, 2)
                }

                GroupBox("Processing") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Reset timestamps for each segment", isOn: $viewModel.settings.resetTimestamps)
                            .help("Keeps each chunk timestamped from the start of that chunk.")
                            .disabled(viewModel.isProcessing)

                        Toggle("Normalise speech loudness with loudnorm", isOn: $viewModel.settings.loudnessNormalizationEnabled)
                            .help("Useful when meeting participants have uneven volume. Adds ffmpeg loudnorm filtering.")
                            .disabled(viewModel.isProcessing)

                        Toggle("Audio only", isOn: $viewModel.settings.audioOnly)
                            .help("Default is on. Disable only if you know you need video streams preserved.")
                            .disabled(viewModel.isProcessing)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("FFmpeg Overrides") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Custom extra FFmpeg arguments")
                            TextField("Power-user only, for example: -map_metadata -1", text: $viewModel.settings.extraFFmpegArgumentsText)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .extraArguments)
                                .help("Arguments are split safely and inserted before the segmenting options. Invalid quotes fail validation.")
                                .disabled(viewModel.isProcessing)
                            Text("Advanced/power-user only. These are not shell commands and are passed directly to ffmpeg.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("ffmpeg path override")
                            TextField("Optional, for example /opt/homebrew/bin/ffmpeg", text: $viewModel.settings.ffmpegPathOverride)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .ffmpegPath)
                                .help("Leave blank to probe Homebrew, MacPorts, then PATH.")
                                .disabled(viewModel.isProcessing)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Label(viewModel.advancedValidationMessage, systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Advanced configuration validation message")
            }
            .padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("Advanced Configuration")
                    .font(.headline)
                Text(viewModel.settingsSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack {
            Spacer()
            Button {
                Task { await viewModel.start() }
            } label: {
                HStack(spacing: 7) {
                    if viewModel.isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(viewModel.isProcessing ? "Processing..." : "Create Chunks")
                }
                .frame(minWidth: 132)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canStart)
            .accessibilityLabel("Create audio chunks")
        }
    }

    private var statusArea: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.title3)
                .foregroundStyle(statusTint)
                .frame(width: 24)
            if viewModel.isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Processing")
            }
            Text(viewModel.statusText)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(14)
        .background(statusTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(statusTint.opacity(0.22))
        }
        .accessibilityElement(children: .combine)
    }

    private var detailsArea: some View {
        DisclosureGroup("Details", isExpanded: $isShowingLogs) {
            ScrollView {
                Text(viewModel.logs.isEmpty ? "ffmpeg logs will appear here while processing." : viewModel.logs)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(minHeight: 110, maxHeight: 180)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08))
            }
            .padding(.top, 8)
        }
    }

    private var statusTint: Color {
        switch viewModel.state {
        case .failure: .red
        case .success: .green
        case .running: .blue
        case .idle: .secondary
        }
    }

    private var statusSymbol: String {
        switch viewModel.state {
        case .failure: "xmark.octagon.fill"
        case .success: "checkmark.circle.fill"
        case .running: "waveform"
        case .idle: "clock"
        }
    }

    private func alert(_ alert: ActiveAlert) -> Alert {
        switch alert {
        case .success(let folder, let count):
            let countText = count.map { "\nOutput files created: \($0)" } ?? ""
            return Alert(
                title: Text("Processing Complete"),
                message: Text("Output files were saved to:\n\(folder.path)\(countText)"),
                primaryButton: .default(Text("Open Output Folder")) {
                    do { try viewModel.acknowledgeSuccess(openOutputFolder: true) }
                    catch { activeAlert = .error(error.localizedDescription); return }
                },
                secondaryButton: .default(Text("OK")) {
                    do { try viewModel.acknowledgeSuccess(openOutputFolder: false) }
                    catch { activeAlert = .error(error.localizedDescription) }
                }
            )
        case .trashPrompt:
            return Alert(
                title: Text("Move original file to Trash?"),
                message: Text("The conversion succeeded. You can keep the original recording or move it to the macOS Trash."),
                primaryButton: .destructive(Text("Move to Trash")) {
                    do { try viewModel.dismissTrashPrompt(shouldTrashOriginal: true) }
                    catch { activeAlert = .error(error.localizedDescription) }
                },
                secondaryButton: .cancel(Text("Keep Original")) {
                    do { try viewModel.dismissTrashPrompt(shouldTrashOriginal: false) }
                    catch { activeAlert = .error(error.localizedDescription) }
                }
            )
        case .error(let message):
            return Alert(
                title: Text("Processing Error"),
                message: Text(message),
                dismissButton: .default(Text("OK")) {
                    viewModel.resetAfterFailureAcknowledged()
                }
            )
        }
    }
}
