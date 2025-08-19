import Foundation
#if canImport(whisper)
import whisper
#else
#error("Unable to import whisper module. Please check your project configuration.")
#endif
import os

enum WhisperError: Error {
    case couldNotInitializeContext
}

// MARK: - Progress and Realtime Callback Support
class WhisperProgressHandler {
    private let onProgress: (Double) -> Void
    
    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }
    
    func handleProgress(_ progress: Int32) {
        let progressPercentage = Double(progress) / 100.0
        onProgress(progressPercentage)
    }
}

class WhisperSegmentHandler {
    private let onNewSegment: (String) -> Void
    private var lastSegmentCount: Int32 = 0
    
    init(onNewSegment: @escaping (String) -> Void) {
        self.onNewSegment = onNewSegment
    }
    
    func handleNewSegment(_ ctx: OpaquePointer?) {
        guard let ctx = ctx else { return }
        let segmentCount = whisper_full_n_segments(ctx)
        
        // Only process new segments
        if segmentCount > lastSegmentCount {
            for i in lastSegmentCount..<segmentCount {
                let segmentText = String(cString: whisper_full_get_segment_text(ctx, i))
                
                // Check if timestamps should be included
                let includeTimestamps = UserDefaults.standard.bool(forKey: "WhisperIncludeTimestamps")
                
                var formattedText = ""
                if includeTimestamps {
                    let t0 = whisper_full_get_segment_t0(ctx, i)
                    let t1 = whisper_full_get_segment_t1(ctx, i)
                    let startTime = formatTimestamp(Int64(t0))
                    let endTime = formatTimestamp(Int64(t1))
                    formattedText = "[\(startTime) --> \(endTime)] \(segmentText)"
                } else {
                    formattedText = segmentText
                }
                
                onNewSegment(formattedText)
            }
            lastSegmentCount = segmentCount
        }
    }
    
    func reset() {
        lastSegmentCount = 0
    }
    
    private func formatTimestamp(_ centiseconds: Int64) -> String {
        let totalSeconds = Double(centiseconds) / 100.0
        let minutes = Int(totalSeconds) / 60
        let seconds = totalSeconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%02d:%05.2f", minutes, seconds)
    }
}

// Global handlers to be used in C callbacks
private var globalProgressHandler: WhisperProgressHandler?
private var globalSegmentHandler: WhisperSegmentHandler?

// C callback function for progress updates
private let whisperProgressCallback: @convention(c) (OpaquePointer?, OpaquePointer?, Int32, UnsafeMutableRawPointer?) -> Void = { ctx, state, progress, userData in
    globalProgressHandler?.handleProgress(progress)
}

// C callback function for new segment updates
private let whisperNewSegmentCallback: @convention(c) (OpaquePointer?, OpaquePointer?, Int32, UnsafeMutableRawPointer?) -> Void = { ctx, state, nNew, userData in
    globalSegmentHandler?.handleNewSegment(ctx)
}

// Meet Whisper C++ constraint: Don't access from more than one thread at a time.
@MainActor
final class WhisperContext {
    private var context: OpaquePointer?
    private var languageCString: [CChar]?
    private var prompt: String?
    private var promptCString: [CChar]?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WhisperContext")
    
    private var progressHandler: WhisperProgressHandler?
    private var segmentHandler: WhisperSegmentHandler?

    private init() {
        logger.debug("WhisperContext initialized")
    }

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        // Synchronously release resources - don't use async Task in deinit
        if let context = context {
            whisper_free(context)
            self.context = nil
        }
        languageCString = nil
        promptCString = nil
        
        // Clean up global handlers if they point to our handlers
        if globalProgressHandler === progressHandler {
            globalProgressHandler = nil
        }
        if globalSegmentHandler === segmentHandler {
            globalSegmentHandler = nil
        }
        
        logger.debug("WhisperContext deinitialized")
    }

    func fullTranscribe(samples: [Float], onProgress: ((Double) -> Void)? = nil, onNewSegment: ((String) -> Void)? = nil) {
        guard let context = context else {
            logger.error("❌ Context is not initialized")
            return
        }
        
        // Set up progress handler if provided
        if let onProgress = onProgress {
            progressHandler = WhisperProgressHandler(onProgress: onProgress)
            globalProgressHandler = progressHandler
        }
        
        // Set up segment handler if provided
        if let onNewSegment = onNewSegment {
            segmentHandler = WhisperSegmentHandler(onNewSegment: onNewSegment)
            segmentHandler?.reset()  // Reset segment counter
            globalSegmentHandler = segmentHandler
        }

        let maxThreads = max(1, min(8, cpuCount() - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        
        // Read language directly from UserDefaults
        let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        if selectedLanguage != "auto" {
            languageCString = Array(selectedLanguage.utf8CString)
            params.language = languageCString?.withUnsafeBufferPointer { ptr in
                ptr.baseAddress
            }
            logger.notice("🌐 Using language: \(selectedLanguage)")
        } else {
            languageCString = nil
            params.language = nil
            logger.notice("🌐 Using auto language detection")
        }
        
        if prompt != nil {
            promptCString = Array(prompt!.utf8CString)
            params.initial_prompt = promptCString?.withUnsafeBufferPointer { ptr in
                ptr.baseAddress
            }
            logger.notice("💬 Using prompt for transcription in language: \(selectedLanguage)")
        } else {
            promptCString = nil
            params.initial_prompt = nil
        }
        
        // Configure max context parameter (equivalent to --max-context)
        let maxContext = UserDefaults.standard.integer(forKey: "WhisperMaxContext")
        if UserDefaults.standard.object(forKey: "WhisperMaxContext") != nil {
            // Only apply if explicitly set (not -1 default)
            if maxContext == -1 {
                // Use whisper default, don't modify params.n_max_text_ctx
                logger.notice("📝 Using default context window")
            } else if maxContext == 0 {
                params.n_max_text_ctx = 0  // Disable context
                logger.notice("📝 Disabled context window (max-context = 0)")
            } else {
                params.n_max_text_ctx = Int32(maxContext)
                logger.notice("📝 Using max context: \(maxContext)")
            }
        }
        
        // Configure entropy threshold parameter (equivalent to -et)
        let entropyThreshold = UserDefaults.standard.double(forKey: "WhisperEntropyThreshold")
        if UserDefaults.standard.object(forKey: "WhisperEntropyThreshold") != nil {
            params.entropy_thold = Float(entropyThreshold)
            logger.notice("🎯 Using entropy threshold: \(entropyThreshold)")
        }
        
        params.print_realtime   = true
        params.print_progress   = onProgress != nil  // Only enable if we have a progress handler
        params.print_timestamps = true
        params.print_special    = false
        params.translate        = false
        params.n_threads        = Int32(maxThreads)
        params.offset_ms        = 0
        params.no_context       = true
        params.single_segment   = false

        // Set up callbacks if handlers are available
        if onProgress != nil {
            params.progress_callback = whisperProgressCallback
            params.progress_callback_user_data = nil
        }
        
        if onNewSegment != nil {
            params.new_segment_callback = whisperNewSegmentCallback
            params.new_segment_callback_user_data = nil
        }

        whisper_reset_timings(context)
        logger.notice("⚙️ Starting whisper transcription")
        samples.withUnsafeBufferPointer { samples in
            if (whisper_full(context, params, samples.baseAddress, Int32(samples.count)) != 0) {
                logger.error("❌ Failed to run whisper model")
            } else {
                // Print detected language info before timings
                let langId = whisper_full_lang_id(context)
                let detectedLang = String(cString: whisper_lang_str(langId))
                logger.notice("✅ Transcription completed - Language: \(detectedLang)")
                
            }
        }
        
        // Clean up handlers
        globalProgressHandler = nil
        globalSegmentHandler = nil
        progressHandler = nil
        segmentHandler = nil
        
        languageCString = nil
        promptCString = nil
    }

    func getTranscription() -> String {
        guard let context = context else { return "" }
        var transcription = ""
        
        // Check if timestamps should be included
        let includeTimestamps = UserDefaults.standard.bool(forKey: "WhisperIncludeTimestamps")
        
        for i in 0..<whisper_full_n_segments(context) {
            let segmentText = String(cString: whisper_full_get_segment_text(context, i))
            
            if includeTimestamps {
                // Get timestamp information
                let t0 = whisper_full_get_segment_t0(context, i)
                let t1 = whisper_full_get_segment_t1(context, i)
                
                // Convert to seconds and format
                let startTime = formatTimestamp(Int64(t0))
                let endTime = formatTimestamp(Int64(t1))
                
                // Add timestamp prefix to each segment
                transcription += "[\(startTime) --> \(endTime)] \(segmentText)\n"
            } else {
                // Add newline between segments for better readability
                transcription += segmentText
                if i < whisper_full_n_segments(context) - 1 {
                    transcription += "\n"
                }
            }
        }
        
        // Apply hallucination filtering
        let filteredTranscription = WhisperHallucinationFilter.filter(transcription)
        return filteredTranscription
    }
    
    /// Format timestamp from centiseconds to mm:ss.ss format
    private func formatTimestamp(_ centiseconds: Int64) -> String {
        let totalSeconds = Double(centiseconds) / 100.0
        let minutes = Int(totalSeconds) / 60
        let seconds = totalSeconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%02d:%05.2f", minutes, seconds)
    }

    static func createContext(path: String) async throws -> WhisperContext {
        // Create empty context first
        let whisperContext = WhisperContext()
        
        // Initialize the context within the actor's isolated context
        try whisperContext.initializeModel(path: path)
        
        return whisperContext
    }
    
    private func initializeModel(path: String) throws {
        var params = whisper_context_default_params()
        #if targetEnvironment(simulator)
        params.use_gpu = false
        logger.notice("🖥️ Running on simulator, using CPU")
        #endif
        
        let context = whisper_init_from_file_with_params(path, params)
        if let context {
            self.context = context
        } else {
            logger.error("❌ Couldn't load model at \(path)")
            throw WhisperError.couldNotInitializeContext
        }
    }

    func releaseResources() {
        // Only release if context still exists
        if let context = context {
            whisper_free(context)
            self.context = nil
            logger.debug("WhisperContext resources released")
        }
        languageCString = nil
        promptCString = nil
        
        // Clean up handlers
        progressHandler = nil
        segmentHandler = nil
    }

    func setPrompt(_ prompt: String?) {
        self.prompt = prompt
        logger.debug("💬 Prompt set: \(prompt ?? "none")")
    }
}

fileprivate func cpuCount() -> Int {
    ProcessInfo.processInfo.processorCount
}

// MARK: - Whisper Configuration Helpers
extension WhisperContext {
    /// Configure whisper parameters equivalent to command line arguments
    /// - Parameters:
    ///   - maxContext: Equivalent to --max-context parameter. Set to 0 to disable context, nil to use default
    ///   - entropyThreshold: Equivalent to -et parameter. Set to nil to use default (2.4)
    ///   - includeTimestamps: Whether to include timestamps in transcription results
    static func configureWhisperParameters(maxContext: Int? = nil, entropyThreshold: Float? = nil, includeTimestamps: Bool? = nil) {
        if let maxContext = maxContext {
            UserDefaults.standard.set(maxContext, forKey: "WhisperMaxContext")
            print("🔧 Set WhisperMaxContext to: \(maxContext)")
        }
        
        if let entropyThreshold = entropyThreshold {
            UserDefaults.standard.set(entropyThreshold, forKey: "WhisperEntropyThreshold")
            print("🔧 Set WhisperEntropyThreshold to: \(entropyThreshold)")
        }
        
        if let includeTimestamps = includeTimestamps {
            UserDefaults.standard.set(includeTimestamps, forKey: "WhisperIncludeTimestamps")
            print("🔧 Set WhisperIncludeTimestamps to: \(includeTimestamps)")
        }
    }
    
    /// Reset whisper parameters to defaults
    static func resetWhisperParameters() {
        UserDefaults.standard.removeObject(forKey: "WhisperMaxContext")
        UserDefaults.standard.removeObject(forKey: "WhisperEntropyThreshold")
        UserDefaults.standard.removeObject(forKey: "WhisperIncludeTimestamps")
        print("🔧 Reset whisper parameters to defaults")
    }
    
    /// Get current whisper parameter values
    static func getCurrentWhisperParameters() -> (maxContext: Int?, entropyThreshold: Float?, includeTimestamps: Bool) {
        let maxContext = UserDefaults.standard.object(forKey: "WhisperMaxContext") as? Int
        let entropyThreshold = UserDefaults.standard.object(forKey: "WhisperEntropyThreshold") as? Float
        let includeTimestamps = UserDefaults.standard.bool(forKey: "WhisperIncludeTimestamps")
        return (maxContext, entropyThreshold, includeTimestamps)
    }
}

