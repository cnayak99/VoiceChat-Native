//
//  Config.swift
//  VoiceAssistant
//
//  Created by Lemur Mini 1 on 7/21/25.
//

import Foundation

struct Config {
    // MARK: - ElevenLabs Configuration
    // To get your API key and Agent ID:
    // 1. Sign up at https://elevenlabs.io
    // 2. Go to your profile to get your API key
    // 3. Create a conversational AI agent to get the Agent ID
    
    static let elevenLabsAPIKey = "sk_40f1398d2321176618f2cca7d6635dd1e74485d8c9968ba4"
    static let elevenLabsAgentID = "agent_7301k0wpv6g7ffhrf1fwv7chnz2y"
    
    // MARK: - Audio Configuration
    static let audioSampleRate: Double = 16000 // 16kHz for ElevenLabs
    static let audioChannels: UInt32 = 1 // Mono
    static let audioBufferSize: UInt32 = 1024
    
    // MARK: - Validation
    static var isConfigured: Bool {
        return !elevenLabsAPIKey.contains("YOUR_") && 
               !elevenLabsAgentID.contains("YOUR_") &&
               !elevenLabsAPIKey.isEmpty &&
               !elevenLabsAgentID.isEmpty
    }
    
    static var configurationError: String? {
        if elevenLabsAPIKey.contains("YOUR_") || elevenLabsAPIKey.isEmpty {
            return "Please set your ElevenLabs API key in Config.swift"
        }
        if elevenLabsAgentID.contains("YOUR_") || elevenLabsAgentID.isEmpty {
            return "Please set your ElevenLabs Agent ID in Config.swift"
        }
        return nil
    }
} 