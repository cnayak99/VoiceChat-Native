//
//  ContentView.swift
//  VoiceAssistant
//
//  Created by Lemur Mini 1 on 7/21/25.
//

import SwiftUI

struct ContentView: View {
    @State private var callState: CallState = .disconnected
    @State private var isAnimating = false
    @State private var showingPermissionAlert = false
    @State private var showingErrorAlert = false
    
    @StateObject private var micPermissionService = MicPermissionService()
    @StateObject private var audioPlaybackService = AudioPlaybackService()
    @StateObject private var elevenLabsService: ElevenLabsService
    
    init() {
        let audioService = AudioPlaybackService()
        _audioPlaybackService = StateObject(wrappedValue: audioService)
        _elevenLabsService = StateObject(wrappedValue: ElevenLabsService(audioPlaybackService: audioService))
    }
    
    var body: some View {
        ZStack {
            // Background gradient for a modern look
            LinearGradient(
                gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Title
                VStack(spacing: 8) {
                    Text("Voice Assistant")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .animation(.easeInOut(duration: 0.3), value: callState)
                }
                
                Spacer()
                
                // Call Button
                Button(action: toggleCall) {
                    ZStack {
                        // Button background circle
                        Circle()
                            .fill(buttonColor)
                            .frame(width: 120, height: 120)
                            .shadow(color: buttonColor.opacity(0.3), radius: 20, x: 0, y: 8)
                            .scaleEffect(isAnimating ? 1.05 : 1.0)
                        
                        // Phone icon with recording indicator
                        VStack {
                            Image(systemName: phoneIconName)
                                .font(.system(size: 40, weight: .medium))
                                .foregroundColor(.white)
                                .rotationEffect(.degrees(isAnimating ? 5 : 0))
                            
                            if elevenLabsService.isRecording {
                                HStack(spacing: 3) {
                                    ForEach(0..<3) { index in
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 4, height: 4)
                                            .scaleEffect(recordingAnimationScale(for: index))
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }
                    }
                }
                .buttonStyle(CallButtonStyle())
                .disabled(callState == .connecting)
                
                Spacer()
                
                // Instructions
                VStack(spacing: 4) {
                    Text(instructionText)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .animation(.easeInOut(duration: 0.3), value: callState)
                    
                    if let errorMessage = elevenLabsService.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: callState)
        .alert("Microphone Permission Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Voice Assistant needs microphone access to work. Please enable it in Settings.")
        }
        .alert("Connection Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(elevenLabsService.errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: elevenLabsService.errorMessage) { _, newValue in
            if newValue != nil {
                showingErrorAlert = true
            }
        }
        .onChange(of: elevenLabsService.isConnected) { _, isConnected in
            if isConnected {
                callState = .connected
            } else if callState == .connected {
                callState = .disconnected
            }
        }
        .onAppear {
            micPermissionService.checkPermissionStatus()
        }
    }
    
    private var buttonColor: Color {
        switch callState {
        case .disconnected:
            return .green
        case .connecting:
            return .orange
        case .connected:
            return .red
        }
    }
    
    private var phoneIconName: String {
        switch callState {
        case .disconnected:
            return "phone.fill"
        case .connecting:
            return "phone.connection"
        case .connected:
            return "phone.fill"
        }
    }
    
    private var statusText: String {
        switch callState {
        case .disconnected:
            return elevenLabsService.errorMessage != nil ? "Error - Check configuration" : "Ready to talk"
        case .connecting:
            return "Connecting..."
        case .connected:
            return elevenLabsService.isRecording ? "Listening..." : "Connected"
        }
    }
    
    private var instructionText: String {
        switch callState {
        case .disconnected:
            return "Tap the button to start your conversation with AI"
        case .connecting:
            return "Please wait while we connect to ElevenLabs"
        case .connected:
            return "Speak now! Tap again to end the conversation"
        }
    }
    
    private func recordingAnimationScale(for index: Int) -> CGFloat {
        let baseScale: CGFloat = 0.5
        let maxScale: CGFloat = 1.5
        let animationOffset = Double(index) * 0.2
        
        return baseScale + (maxScale - baseScale) * CGFloat(abs(sin(Date().timeIntervalSince1970 * 3 + animationOffset)))
    }
    
    private func toggleCall() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            // Animate the button press
            isAnimating = true
        }
        
        // Reset animation after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isAnimating = false
            }
        }
        
        // Handle state changes
        Task {
            switch callState {
            case .disconnected:
                await startCall()
                
            case .connected:
                await endCall()
                
            case .connecting:
                // Prevent multiple taps during connection
                break
            }
        }
    }
    
    private func startCall() async {
        // Check microphone permission first
        let hasPermission = await micPermissionService.requestMicrophonePermission()
        
        guard hasPermission else {
            showingPermissionAlert = true
            return
        }
        
        // Start connecting
        callState = .connecting
        
        // Setup audio session
        do {
            try AudioUtils.setupAudioSession()
        } catch {
            print("Failed to setup audio session: \(error)")
            elevenLabsService.errorMessage = "Failed to setup audio session"
            callState = .disconnected
            return
        }
        
        // Connect to ElevenLabs
        await elevenLabsService.connect()
        
        // If connection failed, reset state
        if !elevenLabsService.isConnected {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                callState = .disconnected
            }
        }
    }
    
    private func endCall() async {
        // Disconnect from ElevenLabs
        await elevenLabsService.disconnect()
        
        // Deactivate audio session
        AudioUtils.deactivateAudioSession()
        
        // Update UI state
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            callState = .disconnected
        }
    }
}

// Custom button style for the call button
struct CallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}


