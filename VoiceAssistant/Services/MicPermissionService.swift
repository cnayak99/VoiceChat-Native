//
//  MicPermissionService.swift
//  VoiceAssistant
//
//  Created by Lemur Mini 1 on 7/21/25.
//

import AVFoundation
import Foundation

@MainActor
class MicPermissionService: ObservableObject {
    @Published var permissionStatus: AVAudioSession.RecordPermission = .undetermined
    	
    init() {
        permissionStatus = AVAudioSession.sharedInstance().recordPermission
    }
    
    func requestMicrophonePermission() async -> Bool {
        switch permissionStatus {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        self.permissionStatus = granted ? .granted : .denied
                        continuation.resume(returning: granted)
                    }
                }
            }
            return granted
        @unknown default:
            return false
        }
    }
    
    func checkPermissionStatus() {
        permissionStatus = AVAudioSession.sharedInstance().recordPermission
    }
} 
