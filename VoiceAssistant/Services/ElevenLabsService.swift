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
    private var connectionConfirmed = false
    private var audioProcessingCounter = 0
    private var consecutiveQuietBuffers = 0
    private var lastAudioSendTime: TimeInterval = 0
    private var audioBufferCount = 0
    private var messageCount = 0 // Track total messages received
    
    // MARK: - Initialization
    init(audioPlaybackService: AudioPlaybackService) {
        self.audioPlaybackService = audioPlaybackService
        super.init()
        // Don't setup audio engine immediately - wait until connect() is called
        // This prevents crashes in iOS Simulator which has no microphone
    }
    
    // MARK: - Audio Engine Setup
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
        
        // Get the hardware's native format instead of forcing our own
        let hwFormat = inputNode.inputFormat(forBus: 0)
        print("Hardware format: \(hwFormat)")
        
        // Try to install tap using hardware format - this will prevent the crash
        do {
            inputNode.installTap(onBus: 0, bufferSize: Config.audioBufferSize, format: hwFormat) { [weak self] buffer, _ in
                Task { @MainActor in
                    await self?.sendAudioData(buffer: buffer)
                }
            }
            print("Audio engine setup successful with hardware format: \(hwFormat)")
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
        
        // Try to get a signed URL first, fallback to direct connection
        if let signedURL = await getSignedURL() {
            print("🔐 Using signed URL for connection")
            await connectWithURL(signedURL)
        } else {
            print("⚠️ Signed URL failed, trying direct connection")
            await connectDirectly()
        }
    }
    
    private func getSignedURL() async -> URL? {
        guard let url = URL(string: "https://api.elevenlabs.io/v1/convai/conversation/get-signed-url?agent_id=\(agentId)") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let signedURLString = json["signed_url"] as? String,
               let signedURL = URL(string: signedURLString) {
                return signedURL
            }
        } catch {
            print("❌ Failed to get signed URL: \(error)")
        }
        
        return nil
    }
    
    private func connectWithURL(_ url: URL) async {
        print("🔗 Connecting to: \(url)")
        
        var request = URLRequest(url: url)
        // Don't add Authorization header for signed URL - it's already included
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        await establishConnection()
    }
    
    private func connectDirectly() async {
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("🔗 Connecting to: \(url)")
        print("🔑 Using agent ID: \(agentId)")
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        await establishConnection()
    }
    
    private func establishConnection() async {
        webSocketTask?.resume()
        
        // Reset connection confirmation
        connectionConfirmed = false
        
        // Start listening for messages in background
        Task {
            await listenForMessages()
        }
        
        // Send initial conversation config
        await sendInitialConfig()
        
        // Wait for connection confirmation (max 5 seconds)
        var attempts = 0
        while !connectionConfirmed && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            attempts += 1
        }
        
        if connectionConfirmed {
            isConnected = true
            await startRecording()
            print("✅ WebSocket connection confirmed, recording started")
            
            // Test agent responsiveness with a simple text message
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
                await testAgentResponsiveness()
            }
        } else {
            errorMessage = "Connection timeout - could not establish connection to ElevenLabs"
            webSocketTask?.cancel()
            webSocketTask = nil
        }
    }
    
    private func testAgentResponsiveness() async {
        print("🧪 Testing agent responsiveness...")
        
        // Send a simple text message to test if the agent responds
        let testMessage: [String: Any] = [
            "user_message": "Hello, can you hear me?"
        ]
        
        await sendJSON(testMessage)
        print("📤 Sent test message to agent")
        
        // Wait a few seconds to see if we get any response
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        if messageCount <= 1 {
            print("⚠️ Agent appears unresponsive - only received \(messageCount) message(s)")
            print("💡 This suggests the agent may not be properly configured or active")
        } else {
            print("✅ Agent is responsive - received \(messageCount) messages")
        }
    }
    
    func disconnect() async {
        print("🔌 Disconnecting from ElevenLabs...")
        
        // Stop recording first
        await stopRecording()
        
        // Stop audio playback
        audioPlaybackService.stopPlayback()
        
        // Clean up WebSocket connection gracefully
        if let webSocketTask = webSocketTask {
            print("🔌 Closing WebSocket connection")
            webSocketTask.cancel(with: .goingAway, reason: "User ended call".data(using: .utf8))
        }
        
        // Reset state
        webSocketTask = nil
        isConnected = false
        connectionConfirmed = false
        audioProcessingCounter = 0
        
        print("✅ Disconnected successfully")
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
            
            // Continue listening only if still connected
            if isConnected {
                await listenForMessages()
            }
        } catch {
            // Only show error if we're still supposed to be connected
            if isConnected {
                print("❌ WebSocket receive error: \(error)")
                errorMessage = "Connection lost"
                isConnected = false
            } else {
                print("🔌 WebSocket closed (expected during disconnect)")
            }
        }
    }
    
    private func handleTextMessage(_ text: String) async {
        messageCount += 1
        print("📥 Received text message #\(messageCount): \(text)")
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            // Log all message types we receive for debugging
            if let type = json?["type"] as? String {
                print("📋 Message type: \(type)")
            } else {
                print("📋 No 'type' field found, checking for other message structures...")
                print("🔍 Available keys: \(json?.keys.sorted() ?? [])")
            }
            
            if let type = json?["type"] as? String {
                switch type {
                case "conversation_initiation_metadata":
                    print("✅ Conversation initiated")
                    if let metadata = json?["conversation_initiation_metadata_event"] as? [String: Any] {
                        if let conversationId = metadata["conversation_id"] as? String {
                            print("📋 Conversation ID: \(conversationId)")
                        }
                        if let agentFormat = metadata["agent_output_audio_format"] as? String {
                            print("🔊 Agent audio format: \(agentFormat)")
                        }
                        if let userFormat = metadata["user_input_audio_format"] as? String {
                            print("🎤 User audio format: \(userFormat)")
                        }
                    }
                    connectionConfirmed = true // Confirm connection is working
                case "user_transcript":
                    if let transcript = json?["user_transcript"] as? String {
                        print("👤 User said: \(transcript)")
                    } else if let transcriptEvent = json?["user_transcript_event"] as? [String: Any],
                              let transcript = transcriptEvent["user_transcript"] as? String {
                        print("👤 User said: \(transcript)")
                    } else {
                        print("👤 User transcript received but no text found")
                        print("🔍 Full transcript message: \(json ?? [:])")
                    }
                case "agent_response":
                    print("🤖 Agent is responding")
                case "agent_response_stream":
                    print("🤖 Agent is streaming response")
                case "interruption":
                    print("⚠️ Conversation interrupted")
                case "audio":
                    print("🔊 Received audio message in text format")
                    print("🔍 Full audio message: \(json ?? [:])")
                    
                    // Try the actual ElevenLabs format first: audio_event.audio_base_64
                    if let audioEvent = json?["audio_event"] as? [String: Any],
                       let audioData = audioEvent["audio_base_64"] as? String {
                        print("🔍 Audio data length: \(audioData.count) characters")
                        if let decodedData = Data(base64Encoded: audioData) {
                            print("🎵 Playing decoded audio data (\(decodedData.count) bytes)")
                            audioPlaybackService.playAudio(from: decodedData)
                        } else {
                            print("❌ Failed to decode base64 audio data")
                        }
                    }
                    // Fallback to the simple format: data
                    else if let audioData = json?["data"] as? String {
                        print("🔍 Audio data length: \(audioData.count) characters")
                        if let decodedData = Data(base64Encoded: audioData) {
                            print("🎵 Playing decoded audio data (\(decodedData.count) bytes)")
                            audioPlaybackService.playAudio(from: decodedData)
                        } else {
                            print("❌ Failed to decode base64 audio data")
                        }
                    } else {
                        print("❌ No audio data found in message (checked both audio_event.audio_base_64 and data)")
                    }
                case "ping":
                    print("🏓 Received ping from server")
                    if let pingEvent = json?["ping_event"] as? [String: Any],
                       let eventId = pingEvent["event_id"] as? Int {
                        // Send pong response
                        let pongMessage: [String: Any] = [
                            "type": "pong",
                            "event_id": eventId
                        ]
                        await sendJSON(pongMessage)
                        print("🏓 Sent pong response for event \(eventId)")
                    }
                default:
                    print("❓ Unknown message type: \(type)")
                    print("🔍 Full unknown message: \(json ?? [:])")
                }
            } else {
                // Handle messages without a 'type' field
                print("🔍 Message without 'type' field: \(json ?? [:])")
            }
        } catch {
            print("❌ Failed to parse JSON message: \(error)")
            print("🔍 Raw message: \(text)")
        }
    }
    
    private func handleBinaryMessage(_ data: Data) async {
        // This is audio data from the AI - play it
        print("🎵 Received binary audio data (\(data.count) bytes)")
        audioPlaybackService.playAudio(from: data)
    }
    
    // MARK: - Audio Recording
    private func startRecording() async {
        guard let audioEngine = audioEngine else { 
            print("❌ No audio engine available for recording")
            return 
        }
        
        do {
            try audioEngine.start()
            isRecording = true
            print("✅ Recording started successfully")
        } catch {
            print("❌ Failed to start recording: \(error)")
            errorMessage = "Failed to start recording"
        }
    }
    
    private func stopRecording() async {
        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)
        isRecording = false
        print("🛑 Recording stopped")
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
        guard isConnected, let pcmBuffer = buffer as? AVAudioPCMBuffer else { 
            if !isConnected {
                print("🚫 Not connected, skipping audio data")
            }
            return 
        }
        
        // Add rate limiting to prevent overwhelming the API
        let currentTime = Date().timeIntervalSince1970
        let timeSinceLastSend = currentTime - lastAudioSendTime
        if timeSinceLastSend < 0.05 { // Minimum 50ms between sends
            return
        }
        
        // Convert the hardware format audio to the format expected by ElevenLabs (16kHz, Int16, mono)
        let convertedData = convertAudioBuffer(pcmBuffer, shouldLog: false)
        
        // Check audio level to decide whether to send
        let audioLevel = calculateAudioLevel(data: convertedData)
        let levelValue = getAudioLevelValue(audioLevel)
        
        // Only send audio if it's above a certain threshold or if we recently had loud audio
        let shouldSendAudio = levelValue >= 1000 || consecutiveQuietBuffers < 5
        
        if levelValue < 1000 {
            consecutiveQuietBuffers += 1
        } else {
            consecutiveQuietBuffers = 0
        }
        
        audioProcessingCounter += 1
        let shouldLog = audioProcessingCounter % 20 == 1 // Reduced logging frequency
        
        if shouldLog {
            print("🎤 Processing audio buffer: \(pcmBuffer.frameLength) frames, level: \(audioLevel), sending: \(shouldSendAudio)")
        }
        
        // Only send if we have meaningful audio
        if shouldSendAudio {
            lastAudioSendTime = currentTime
            
            if shouldLog {
                print("📤 Sending \(convertedData.count) bytes of audio data (buffer #\(audioProcessingCounter))")
                // Log a sample of the base64 data to verify encoding
                let base64Sample = convertedData.base64EncodedString().prefix(50)
                print("🔍 Audio sample (first 50 chars): \(base64Sample)...")
            }
            
            // Use the correct format for ElevenLabs Conversational AI API
            let message: [String: Any] = [
                "user_audio_chunk": convertedData.base64EncodedString()
            ]
            
            await sendJSON(message)
        } else if shouldLog {
            print("🔇 Skipping quiet audio buffer #\(audioProcessingCounter)")
        }
    }
    
    private func calculateAudioLevel(data: Data) -> String {
        let samples = data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Int16.self))
        }
        
        let maxSample = samples.map { Int(abs($0)) }.max() ?? 0
        let avgSample = samples.map { Int(abs($0)) }.reduce(0, +) / samples.count
        
        if maxSample == 0 {
            return "SILENCE"
        } else if maxSample < 1000 {
            return "QUIET"
        } else if maxSample < 5000 {
            return "MEDIUM"
        } else {
            return "LOUD"
        }
    }
    
    private func getAudioLevelValue(_ level: String) -> Int {
        switch level {
        case "SILENCE": return 0
        case "QUIET": return 500
        case "MEDIUM": return 2500
        case "LOUD": return 10000
        default: return 0
        }
    }
    
    private func convertAudioBuffer(_ buffer: AVAudioPCMBuffer, shouldLog: Bool) -> Data {
        // If the buffer is already in the expected format, use it directly
        if buffer.format.sampleRate == Config.audioSampleRate && 
           buffer.format.channelCount == Config.audioChannels &&
           buffer.format.commonFormat == .pcmFormatInt16 {
            if shouldLog {
                print("✅ Audio already in target format, using directly")
            }
            return extractPCMData(from: buffer)
        }
        
        if shouldLog {
            print("🔄 Converting audio from \(buffer.format) to 16kHz Int16 mono")
        }
        
        // Create target format (16kHz, Int16, mono)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Config.audioSampleRate,
            channels: Config.audioChannels,
            interleaved: false
        ) else {
            print("❌ Failed to create target format, using original")
            return extractPCMData(from: buffer)
        }
        
        // Create converter
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            print("❌ Failed to create audio converter, using original")
            return extractPCMData(from: buffer)
        }
        
        // Calculate output buffer capacity more safely
        let inputFrames = buffer.frameLength
        let outputFrames = UInt32(Double(inputFrames) * targetFormat.sampleRate / buffer.format.sampleRate)
        
        // Add some extra capacity to handle rounding and ensure we have enough space
        let safeOutputFrames = max(outputFrames + 1024, inputFrames)
        
        if shouldLog {
            print("📊 Input: \(inputFrames) frames → Output: \(outputFrames) frames (safe: \(safeOutputFrames))")
        }
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: safeOutputFrames) else {
            print("❌ Failed to create output buffer, using original")
            return extractPCMData(from: buffer)
        }
        
        // Perform conversion
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if status == .error {
            print("❌ Audio conversion failed with error: \(error?.localizedDescription ?? "Unknown"), using original")
            return extractPCMData(from: buffer)
        }
        
        if shouldLog {
            print("✅ Audio conversion successful: \(outputBuffer.frameLength) frames converted")
        }
        
        return extractPCMData(from: outputBuffer)
    }
    
    private func extractPCMData(from buffer: AVAudioPCMBuffer) -> Data {
        guard let channelData = buffer.int16ChannelData else {
            // Fallback to the old method if int16ChannelData is not available
            let audioBuffer = buffer.audioBufferList.pointee.mBuffers
            return Data(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
        }
        
        let frameCount = Int(buffer.frameLength)
        let data = Data(bytes: channelData[0], count: frameCount * MemoryLayout<Int16>.size)
        return data
    }
    
    private func sendJSON(_ object: [String: Any]) async {
        guard let webSocketTask = webSocketTask, isConnected else { 
            print("❌ No WebSocket task available or not connected")
            return 
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            let jsonString = String(data: data, encoding: .utf8) ?? ""
            let message = URLSessionWebSocketTask.Message.string(jsonString)
            
            // Don't log audio messages (too verbose), but log others
            if let type = object["type"] as? String, type != "audio" {
                print("📤 Sending JSON message: \(type)")
            } else if object["user_audio_chunk"] != nil {
                // This is an audio chunk message
            } else {
                print("📤 Sending JSON message: unknown type")
            }
            
            try await webSocketTask.send(message)
        } catch {
            print("❌ Failed to send JSON: \(error)")
            
            // If we get a connection error, mark as disconnected to stop further attempts
            if let posixError = error as? POSIXError, posixError.code == .ENOTCONN {
                print("🔌 WebSocket connection lost, marking as disconnected")
                isConnected = false
            }
            
            errorMessage = "Failed to send data: \(error.localizedDescription)"
        }
    }
} 