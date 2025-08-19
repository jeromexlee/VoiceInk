import Foundation
import os

struct WhisperHallucinationFilter {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WhisperHallucinationFilter")
    
    // Pattern-based approach for detecting hallucinations - focusing on format indicators
    private static let hallucinationPatterns = [
        // Text in various types of brackets - but NOT our timestamp format
        #"\[(?!\d{1,2}:\d{2}\.\d{2}\s*-->\s*\d{1,2}:\d{2}\.\d{2}\]).*?\]"#,  // [Text] but not [mm:ss.ss --> mm:ss.ss]
        #"\(.*?\)"#,                  // (Text in parentheses)
        #"\{.*?\}"#,                  // {Text in curly braces}
        #"<.*?>"#,                    // <Text in angle brackets>
        
        // Text with special formatting
        #"\*.*?\*"#,                  // *Text with asterisks*
        #"_.*?_"#,                    // _Text with underscores_
        
        // Legacy time indicators (but not our new format)
        #"(?i)(?<!\[)\d{1,2}:\d{2}(:\d{2})?\s*-\s*\d{1,2}:\d{2}(:\d{2})?"#  // 00:00 - 00:00 format but not preceded by [
    ]
    
    /// Removes hallucinations from transcription text using pattern matching
    /// - Parameter text: Original transcription text from Whisper
    /// - Returns: Filtered text with hallucinations removed
    static func filter(_ text: String) -> String {
        logger.notice("🧹 Applying pattern-based hallucination filter to transcription")
        
        var filteredText = text
        
        // Remove pattern-based hallucinations
        for pattern in hallucinationPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(filteredText.startIndex..., in: filteredText)
                filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: range, withTemplate: "")
            }
        }
        
        // Clean up extra whitespace but preserve intentional newlines
        // Only replace multiple spaces/tabs with single space, but preserve newlines
        filteredText = filteredText.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        // Remove excessive blank lines (more than 2 consecutive newlines)
        filteredText = filteredText.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        filteredText = filteredText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add logging to track effectiveness
        if filteredText != text {
            logger.notice("✅ Removed hallucinations using pattern matching")
        } else {
            logger.notice("✅ No hallucinations detected with pattern matching")
        }
        
        return filteredText
    }
} 