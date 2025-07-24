//
//  AudioPlaybackService.swift
//  VoiceAssistant
//
//  Created by Lemur Mini 1 on 7/21/25.
//

import AVFoundation
import Foundation

@MainActor
class AudioPlaybackService: NSObject, ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    @Published var isPlaying = false
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    func playAudio(from data: Data) {
        print("🔊 AudioPlaybackService: Attempting to play audio (\(data.count) bytes)")
        
        // Convert raw PCM to WAV format with proper headers
        let wavData = convertPCMToWAV(pcmData: data, sampleRate: 16000, channels: 1, bitsPerSample: 16)
        print("🔧 AudioPlaybackService: Converted to WAV format (\(wavData.count) bytes)")
        
        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.delegate = self
            
            guard let player = audioPlayer else {
                print("❌ AudioPlaybackService: Failed to create audio player")
                return
            }
            
            print("✅ AudioPlaybackService: Audio player created successfully")
            print("📊 AudioPlaybackService: Duration: \(player.duration)s, Format: \(player.format.description)")
            
            let success = player.play()
            if success {
                isPlaying = true
                print("🎵 AudioPlaybackService: Audio playback started successfully")
            } else {
                print("❌ AudioPlaybackService: Failed to start audio playback")
            }
        } catch {
            print("❌ AudioPlaybackService: Failed to create audio player: \(error)")
        }
    }
    
    func stopPlayback() {
        print("🛑 AudioPlaybackService: Stopping playback")
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }
    
    private func convertPCMToWAV(pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        var wavData = Data()
        
        let bytesPerSample = bitsPerSample / 8
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample
        let dataSize = pcmData.count
        let fileSize = 36 + dataSize
        
        // WAV Header
        wavData.append("RIFF".data(using: .ascii)!) // ChunkID
        wavData.append(Data(from: UInt32(fileSize).littleEndian)) // ChunkSize
        wavData.append("WAVE".data(using: .ascii)!) // Format
        
        // fmt subchunk
        wavData.append("fmt ".data(using: .ascii)!) // Subchunk1ID
        wavData.append(Data(from: UInt32(16).littleEndian)) // Subchunk1Size (16 for PCM)
        wavData.append(Data(from: UInt16(1).littleEndian)) // AudioFormat (1 for PCM)
        wavData.append(Data(from: UInt16(channels).littleEndian)) // NumChannels
        wavData.append(Data(from: UInt32(sampleRate).littleEndian)) // SampleRate
        wavData.append(Data(from: UInt32(byteRate).littleEndian)) // ByteRate
        wavData.append(Data(from: UInt16(blockAlign).littleEndian)) // BlockAlign
        wavData.append(Data(from: UInt16(bitsPerSample).littleEndian)) // BitsPerSample
        
        // data subchunk
        wavData.append("data".data(using: .ascii)!) // Subchunk2ID
        wavData.append(Data(from: UInt32(dataSize).littleEndian)) // Subchunk2Size
        wavData.append(pcmData) // The actual audio data
        
        return wavData
    }
}

extension AudioPlaybackService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("🎵 AudioPlaybackService: Playback finished successfully: \(flag)")
        isPlaying = false
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("❌ AudioPlaybackService: Audio decode error: \(error?.localizedDescription ?? "Unknown error")")
        isPlaying = false
    }
}

// MARK: - Data Extension for WAV Header
extension Data {
    init<T>(from value: T) {
        self = withUnsafePointer(to: value) { pointer in
            Data(buffer: UnsafeBufferPointer(start: pointer, count: 1))
        }
    }
} 