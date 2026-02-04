import SwiftUI
import SwiftData

struct ModelManagementView: View {
    @ObservedObject var whisperState: WhisperState
    @State private var modelToDelete: WhisperModel?
    @StateObject private var aiService = AIService()
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext
    @StateObject private var whisperPrompt = WhisperPrompt()
    
    // State for whisper parameters
    @AppStorage("WhisperMaxContext") private var maxContext: Int = 0  // Default is 0 tokens context
    @AppStorage("WhisperEntropyThreshold") private var entropyThreshold: Double = 2.4  // Using Double for UI, will convert to Float
    @AppStorage("WhisperIncludeTimestamps") private var includeTimestamps: Bool = true
    
    // State for debug settings
    @AppStorage("DebugLoggingEnabled") private var debugLoggingEnabled: Bool = false
    
    // Local state for text input validation
    @State private var contextWindowText: String = ""
    @State private var entropyThresholdText: String = ""
    @State private var contextWindowError: String? = nil
    @State private var entropyThresholdError: String? = nil
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                defaultModelSection
                languageSelectionSection
                whisperParametersSection
                debugSettingsSection
                availableModelsSection
            }
            .padding(40)
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.controlBackgroundColor))
        .alert(item: $modelToDelete) { model in
            Alert(
                title: Text("Delete Model"),
                message: Text("Are you sure you want to delete the model '\(model.name)'?"),
                primaryButton: .destructive(Text("Delete")) {
                    Task {
                        await whisperState.deleteModel(model)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private var defaultModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default Model")
                .font(.headline)
                .foregroundColor(.secondary)
            Text(whisperState.currentTranscriptionModel?.displayName ?? "No model selected")
                .font(.title2)
                .fontWeight(.bold)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.windowBackgroundColor).opacity(0.4))
        .cornerRadius(10)
    }
    
    private var languageSelectionSection: some View {
        LanguageSelectionView(whisperState: whisperState, displayMode: .full, whisperPrompt: whisperPrompt)
    }
    
    private var whisperParametersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Whisper Parameters")
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                // Context Window Setting
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Context Window")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                                                 TextField("Enter number (0 is default)", text: $contextWindowText)
                             .textFieldStyle(RoundedBorderTextFieldStyle())
                             .frame(maxWidth: 200)
                             .onChange(of: contextWindowText) { oldValue, newValue in
                                 validateContextWindow(newValue)
                             }
                             .onAppear {
                                 contextWindowText = String(maxContext)
                             }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Controls the maximum text context for transcription. Enter number of tokens (0 means no context, default is 0).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let error = contextWindowError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Divider()
                
                // Entropy Threshold Setting
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Entropy Threshold")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                                                 TextField("Enter number (1.0-5.0)", text: $entropyThresholdText)
                             .textFieldStyle(RoundedBorderTextFieldStyle())
                             .frame(maxWidth: 200)
                             .onChange(of: entropyThresholdText) { oldValue, newValue in
                                 validateEntropyThreshold(newValue)
                             }
                             .onAppear {
                                 entropyThresholdText = String(format: "%.1f", entropyThreshold)
                             }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Entropy threshold for detection of failed decoding (equivalent to -et parameter). Range: 1.0-5.0.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let error = entropyThresholdError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Divider()
                
                // Timestamps Setting
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Include Timestamps")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Toggle("", isOn: $includeTimestamps)
                            .toggleStyle(SwitchToggleStyle())
                    }
                    
                    Text("Show timestamps in transcription results. Format: [mm:ss.ss --> mm:ss.ss] text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.4))
        .cornerRadius(10)
    }
    
    private var availableModelsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Available Models")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("(\(whisperState.allAvailableModels.count))")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                
                Spacer()
            }
            
            VStack(spacing: 12) {
                ForEach(whisperState.allAvailableModels, id: \.id) { model in
                    ModelCardRowView(
                        model: model,
                        isDownloaded: whisperState.availableModels.contains { $0.name == model.name },
                        isCurrent: whisperState.currentTranscriptionModel?.name == model.name,
                        downloadProgress: whisperState.downloadProgress,
                        modelURL: whisperState.availableModels.first { $0.name == model.name }?.url,
                        deleteAction: {
                            if let downloadedModel = whisperState.availableModels.first(where: { $0.name == model.name }) {
                                modelToDelete = downloadedModel
                            }
                        },
                        setDefaultAction: {
                            Task {
                                await whisperState.setDefaultTranscriptionModel(model)
                            }
                        },
                        downloadAction: {
                            if let localModel = model as? LocalModel {
                                Task {
                                    await whisperState.downloadModel(localModel)
                                }
                            }
                        }
                    )
                }
            }
        }
        .padding()
    }
    
    // MARK: - Validation Functions
    
    private func validateContextWindow(_ input: String) {
        // Clear error first
        contextWindowError = nil
        
        // Allow empty input (use default of 0)
        if input.isEmpty {
            maxContext = 0
            return
        }
        
        // Try to parse as integer
        guard let value = Int(input) else {
            contextWindowError = "Please enter a valid integer"
            return
        }
        
        // Validate range (allow 0 or positive numbers)
        if value < 0 {
            contextWindowError = "Value must be 0 or positive"
            return
        }
        
        // Valid input
        maxContext = value
        contextWindowError = nil
    }
    
    private func validateEntropyThreshold(_ input: String) {
        // Clear error first
        entropyThresholdError = nil
        
        // Don't allow empty input for entropy threshold
        if input.isEmpty {
            entropyThresholdError = "Please enter a value"
            return
        }
        
        // Try to parse as double
        guard let value = Double(input) else {
            entropyThresholdError = "Please enter a valid number"
            return
        }
        
        // Validate range
        if value < 1.0 || value > 5.0 {
            entropyThresholdError = "Value must be between 1.0 and 5.0"
            return
        }
        
        // Valid input
        entropyThreshold = value
        entropyThresholdError = nil
    }
    
    private var debugSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Debug Settings")
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                // Debug Logging Toggle
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Enable Debug Logging")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Toggle("", isOn: $debugLoggingEnabled)
                            .toggleStyle(SwitchToggleStyle())
                    }
                    
                    Text("Show detailed debug logs and popup after each transcription. Useful for troubleshooting AI enhancement issues.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if debugLoggingEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            
                            Text("Debug mode is active. You'll see a detailed log popup after each recording.")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .fontWeight(.medium)
                        }
                    }
                    .padding(.leading, 16)
                }
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.4))
        .cornerRadius(10)
    }
}
