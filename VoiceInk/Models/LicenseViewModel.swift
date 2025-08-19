import Foundation
import AppKit

@MainActor
class LicenseViewModel: ObservableObject {
    enum LicenseState: Equatable {
        case trial(daysRemaining: Int)
        case trialExpired
        case licensed
    }
    
    // Always return licensed state - all features are now free
    @Published private(set) var licenseState: LicenseState = .licensed
    @Published var licenseKey: String = ""
    @Published var isValidating = false
    @Published var validationMessage: String?
    @Published private(set) var activationsLimit: Int = 0
    
    private let trialPeriodDays = 7
    private let polarService = PolarService()
    private let userDefaults = UserDefaults.standard
    
    init() {
        loadLicenseState()
    }
    
    func startTrial() {
        // No longer needed - always licensed
        licenseState = .licensed
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
    }
    
    private func loadLicenseState() {
        // Always set to licensed - no more restrictions
        licenseState = .licensed
    }
    
    var canUseApp: Bool {
        // Always return true - all features are free
        return true
    }
    
    func openPurchaseLink() {
        if let url = URL(string: "https://tryvoiceink.com/buy") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func validateLicense() async {
        // Simplified - always succeed
        isValidating = true
        
        // Simulate a brief delay for UX
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        licenseState = .licensed
        validationMessage = "All features are now free!"
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
        
        isValidating = false
    }
    
    func removeLicense() {
        // Even after "removing" license, keep everything licensed
        licenseState = .licensed
        licenseKey = ""
        validationMessage = "All features remain free"
        NotificationCenter.default.post(name: .licenseStatusChanged, object: nil)
    }
}

extension Notification.Name {
    static let licenseStatusChanged = Notification.Name("licenseStatusChanged")
}

// Add UserDefaults extensions for storing activation ID
extension UserDefaults {
    var activationId: String? {
        get { string(forKey: "VoiceInkActivationId") }
        set { set(newValue, forKey: "VoiceInkActivationId") }
    }
}
