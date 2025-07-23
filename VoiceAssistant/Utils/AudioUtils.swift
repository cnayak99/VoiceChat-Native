//
//  AudioUtils.swift
//  VoiceAssistant
//
//  Created by Lemur Mini 1 on 7/21/25.
//

import AVFoundation
import Foundation

class AudioUtils {
    
    static func setupAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        
        try audioSession.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
        )
        
        try audioSession.setActive(true)
    }
    
    static func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }
    
    static func checkMicrophonePermission() -> AVAudioSession.RecordPermission {
        return AVAudioSession.sharedInstance().recordPermission
    }
    
    static func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
} 