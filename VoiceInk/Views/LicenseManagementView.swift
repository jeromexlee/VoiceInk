import SwiftUI

struct LicenseManagementView: View {
    @StateObject private var licenseViewModel = LicenseViewModel()
    @Environment(\.colorScheme) private var colorScheme
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero Section
                heroSection
                
                // Main Content
                VStack(spacing: 32) {
                    freeVersionContent
                }
                .padding(32)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var heroSection: some View {
        VStack(spacing: 24) {
            // App Icon
            AppIconView()
            
            // Title Section
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)
                    
                    HStack(alignment: .lastTextBaseline, spacing: 8) { 
                        Text("VoiceInk Free")
                            .font(.system(size: 32, weight: .bold))
                        
                        Text("v\(appVersion)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)
                    }
                }
                
                Text("All features are now free for everyone!")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("Enjoy unlimited voice transcription with all premium features included")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.green.opacity(0.15),
                    Color.blue.opacity(0.1),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    private var freeVersionContent: some View {
        VStack(spacing: 40) {
            // Free Features Card
            VStack(spacing: 24) {
                // Free Badge
                HStack {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                    Text("Free Forever")
                        .font(.headline)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                
                Text("All Features Included")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                // Features Grid
                VStack(spacing: 20) {
                    HStack(spacing: 40) {
                        featureItem(icon: "waveform", title: "Voice Transcription", color: .blue)
                        featureItem(icon: "sparkles", title: "AI Enhancement", color: .purple)
                    }
                    HStack(spacing: 40) {
                        featureItem(icon: "bolt.fill", title: "Power Modes", color: .orange)
                        featureItem(icon: "keyboard", title: "Hotkeys", color: .green)
                    }
                    HStack(spacing: 40) {
                        featureItem(icon: "clock.fill", title: "Timestamps", color: .blue)
                        featureItem(icon: "doc.text", title: "Export Options", color: .purple)
                    }
                }
            }
            .padding(32)
            .background(Color(.windowBackgroundColor).opacity(0.4))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 10)

            // About Section
            VStack(spacing: 20) {
                Text("About This Version")
                    .font(.headline)
                
                Text("This version of VoiceInk has been modified to provide all features for free. No trial periods, no licensing restrictions - just full-featured voice transcription for everyone.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(32)
            .background(Color(.windowBackgroundColor).opacity(0.4))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 10)
        }
    }
    
    private func featureItem(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
            
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}


