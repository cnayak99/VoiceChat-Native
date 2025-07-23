//
//  ElevenLabsService.swift
//  VoiceAssistant
//
//  Created by Lemur Mini 1 on 7/21/25.
//

import Foundation
import AVFoundation

@MainActor
class ElevenLabsService: NSObject, ObservableObject {
    // MARK: - Configuration
    private let apiKey = Config.elevenLabsAPIKey
    private let agentId = Config.elevenLabsAgentID
    private let baseURL = "wss://api.elevenlabs.io/v1/convai/conversation"
    
    // MARK: - Properties
    @Published var isConnected = false
    @Published var isRecording = false
    @Published var errorMessage: String?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioPlaybackService: AudioPlaybackService
    
    // MARK: - Initialization
    init(audioPlaybackService: AudioPlaybackService) {
        self.audioPlaybackService = audioPlaybackService
        super.init()
        // Don't setup audio engine immediately - wait until connect() is called
        // This prevents crashes in iOS Simulator which has no microphone
    }
    
    // MARK: - Audio Engine Setup
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine?.inputNode
        
        guard let _ = audioEngine, let inputNode = inputNode else {
            print("Failed to setup audio engine")
            return
        }
        
        // Configure audio format (16kHz, 16-bit, mono for ElevenLabs)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Config.audioSampleRate, channels: Config.audioChannels, interleaved: false)
        
        guard let format = format else {
            print("Failed to create audio format")
            return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: Config.audioBufferSize, format: format) { [weak self] buffer, _ in
            Task { @MainActor in
                await self?.sendAudioData(buffer: buffer)
            }
        }
    }
    
    private func setupAudioEngineAsync() async {
        // Check if running in simulator
        #if targetEnvironment(simulator)
        errorMessage = "Voice recording not available in iOS Simulator. Please test on a physical device."
        print("Skipping audio engine setup - running in simulator")
        return
        #endif
        
        audioEngine = AVAudioEngine()
        inputNode = audioEngine?.inputNode
        
        guard let _ = audioEngine, let inputNode = inputNode else {
            errorMessage = "Failed to setup audio engine - no input device available"
            return
        }
        
        // Configure audio format (16kHz, 16-bit, mono for ElevenLabs)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Config.audioSampleRate, channels: Config.audioChannels, interleaved: false)
        
        guard let format = format else {
            errorMessage = "Failed to create audio format"
            return
        }
        
        // Try to install tap - this will fail gracefully if no microphone
        do {
            inputNode.installTap(onBus: 0, bufferSize: Config.audioBufferSize, format: format) { [weak self] buffer, _ in
                Task { @MainActor in
                    await self?.sendAudioData(buffer: buffer)
                }
            }
            print("Audio engine setup successful")
        } catch {
            errorMessage = "Microphone not available: \(error.localizedDescription)"
            print("Audio engine setup failed: \(error)")
            return
        }
    }
    
    // MARK: - WebSocket Connection
    func connect() async {
        guard Config.isConfigured else {
            errorMessage = Config.configurationError ?? "Configuration error"
            return
        }
        
        // Setup audio engine when actually connecting (not during init)
        await setupAudioEngineAsync()
        
        var urlComponents = URLComponents(string: baseURL)
        urlComponents?.queryItems = [
            URLQueryItem(name: "agent_id", value: agentId)
        ]
        
        guard let url = urlComponents?.url else {
            errorMessage = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Start listening for messages
        await listenForMessages()
        
        // Send initial conversation config
        await sendInitialConfig()
        
        isConnected = true
        await startRecording()
    }
    
    func disconnect() async {
        await stopRecording()
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        audioPlaybackService.stopPlayback()
    }
    
    // MARK: - Message Handling
    private func listenForMessages() async {
        guard let webSocketTask = webSocketTask else { return }
        
        do {
            let message = try await webSocketTask.receive()
            
            switch message {
            case .string(let text):
                await handleTextMessage(text)
            case .data(let data):
                await handleBinaryMessage(data)
            @unknown default:
                break
            }
            
            // Continue listening
            await listenForMessages()
        } catch {
            print("WebSocket receive error: \(error)")
            errorMessage = "Connection lost"
            isConnected = false
        }
    }
    
    private func handleTextMessage(_ text: String) async {
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let type = json?["type"] as? String {
                switch type {
                case "conversation_initiation_metadata":
                    print("Conversation initiated")
                case "agent_response":
                    print("Agent is responding")
                case "user_transcript":
                    if let transcript = json?["user_transcript"] as? String {
                        print("User said: \(transcript)")
                    }
                case "interruption":
                    print("Conversation interrupted")
                default:
                    print("Unknown message type: \(type)")
                }
            }
        } catch {
            print("Failed to parse JSON: \(error)")
        }
    }
    
    private func handleBinaryMessage(_ data: Data) async {
        // This is audio data from the AI - play it
        audioPlaybackService.playAudio(from: data)
    }
    
    // MARK: - Audio Recording
    private func startRecording() async {
        guard let audioEngine = audioEngine else { return }
        
        do {
            try audioEngine.start()
            isRecording = true
            print("Recording started")
        } catch {
            print("Failed to start recording: \(error)")
            errorMessage = "Failed to start recording"
        }
    }
    
    private func stopRecording() async {
        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)
        isRecording = false
        print("Recording stopped")
    }
    
    // MARK: - Data Sending
    private func sendInitialConfig() async {
        let config: [String: Any] = [
            "type": "conversation_initiation_client_data",
            "conversation_config": [
                "agent_id": agentId
            ]
        ]
        
        await sendJSON(config)
    }
    
    private func sendAudioData(buffer: AVAudioBuffer) async {
        guard isConnected, let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }
        
        let audioData = pcmBuffer.toData()
        
        let message: [String: Any] = [
            "type": "audio",
            "data": audioData.base64EncodedString()
        ]
        
        await sendJSON(message)
    }
    
    private func sendJSON(_ object: [String: Any]) async {
        guard let webSocketTask = webSocketTask else { return }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            let message = URLSessionWebSocketTask.Message.string(String(data: data, encoding: .utf8) ?? "")
            try await webSocketTask.send(message)
        } catch {
            print("Failed to send JSON: \(error)")
        }
    }
}

// MARK: - AVAudioPCMBuffer Extension
extension AVAudioPCMBuffer {
    func toData() -> Data {
        let audioBuffer = audioBufferList.pointee.mBuffers
        let data = Data(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
        return data
    }
} 