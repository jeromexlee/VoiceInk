import SwiftUI
import SwiftData

struct DebugLogPopup: View {
    @ObservedObject var whisperState: WhisperState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "ladybug.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                
                Text("Debug Logs")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    whisperState.showDebugPopup = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            
            Divider()
            
            // Debug logs content
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if whisperState.debugLogs.isEmpty {
                        Text("No debug logs available")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(Array(whisperState.debugLogs.enumerated()), id: \.offset) { index, log in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                                    .frame(minWidth: 25, alignment: .trailing)
                                
                                Text(log)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
            }
            .frame(maxHeight: 400)
            .background(Color(.textBackgroundColor))
            .border(Color.gray.opacity(0.3))
            
            // Action buttons
            HStack {
                Button("Copy Logs") {
                    let allLogs = whisperState.debugLogs.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(allLogs, forType: .string)
                }
                .help("Copy all debug logs to clipboard")
                
                Button("Clear Logs") {
                    whisperState.debugLogs.removeAll()
                }
                .help("Clear all debug logs")
                
                Spacer()
                
                Button("Close") {
                    whisperState.showDebugPopup = false
                }
                .keyboardShortcut(.escape)
            }
            
            // Summary info
            Text("\(whisperState.debugLogs.count) log entries")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 600, height: 500)
        .background(Color(.windowBackgroundColor))
    }
}

// Debug popup window
struct DebugLogWindow: View {
    @ObservedObject var whisperState: WhisperState
    
    var body: some View {
        DebugLogPopup(whisperState: whisperState)
            .onAppear {
                // Auto-scroll to bottom when popup opens
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Scroll logic if needed
                }
            }
    }
}

#Preview {
    @Previewable @State var mockWhisperState: WhisperState = {
        let container = try! ModelContainer(for: Transcription.self)
        let context = ModelContext(container)
        let state = WhisperState(modelContext: context)
        state.debugLogs = [
            "[12:34:56.789] 🎬 Starting transcription process",
            "[12:34:57.123] 🤖 Using transcription model: Large v3 Turbo (Provider: Local)",
            "[12:34:58.456] ✅ Transcription completed successfully, length: 42 characters",
            "[12:34:58.500] 🔍 Starting enhancement service checks...",
            "[12:34:58.501] ✅ Enhancement service exists",
            "[12:34:58.502] ❌ ENHANCEMENT SKIPPED - Conditions not met:",
            "[12:34:58.503] 🎉 Transcription process completed successfully!"
        ]
        return state
    }()
    
    DebugLogPopup(whisperState: mockWhisperState)
        .frame(width: 600, height: 500)
}
