//
//  ContentView.swift
//  VoiceAssistant
//
//  Created by Lemur Mini 1 on 7/21/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var conversationService = ElevenLabsConversationService()
    @State private var animationActive = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Title
            Text("Voice Assistant")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Status - only show when connecting or connected
            if isConnecting || isConnected {
                Text(statusText)
                    .font(.title3)
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
            }
            
            Spacer()
            
            // Call Button
            Button(action: {
                Task {
                    await toggleCall()
                }
            }) {
                Image(systemName: buttonIcon)
                    .font(.system(size: 50))
                    .foregroundColor(.white)
            }
            .frame(width: 120, height: 120)
            .background(buttonColor)
            .clipShape(Circle())
            .scaleEffect(buttonScale)
            .animation(.easeInOut(duration: 0.2), value: buttonScale)
            .animation(.easeInOut(duration: 0.3), value: buttonColor)
            .disabled(isButtonDisabled)
            .background(
                // Pulsing animation circle behind the button
                Group {
                    if isConnecting {
                        Circle()
                            .fill(buttonColor.opacity(0.2))
                            .frame(width: 120, height: 120)
                            .scaleEffect(animationActive ? 1.6 : 1.0)
                            .opacity(animationActive ? 0.0 : 0.4)
                            .animation(
                                .easeOut(duration: 1.0)
                                .repeatForever(autoreverses: false),
                                value: animationActive
                            )
                    }
                }
            )
            .onChange(of: isConnecting) { _, connecting in
                if connecting {
                    animationActive = true
                } else {
                    animationActive = false
                }
            }
            
            Spacer()
            
            // Button Status Text
            VStack(spacing: 8) {
                Text(buttonStatusText)
                    .font(.title3)
                    .foregroundColor(.primary)
                
                // Secondary instruction text for connected state
                if isConnected {
                    Text("Speak naturally — I'm listening")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    // MARK: - Computed Properties
    
    private var isConnecting: Bool {
        conversationService.status == "connecting"
    }
    
    private var isConnected: Bool {
        conversationService.isConnected
    }
    
    private var isButtonDisabled: Bool {
        false
    }
    
    private var buttonIcon: String {
        if isConnected {
            return "phone.down.fill"
        } else {
            return "phone.fill"
        }
    }
    
    private var buttonColor: Color {
        if isConnected {
            return .red
        } else if isConnecting {
            return .yellow
        } else {
            return .green
        }
    }
    
    private var buttonScale: CGFloat {
        isConnecting ? 0.95 : 1.0
    }
    
    private var buttonStatusText: String {
        if isConnected {
            return "Tap to end call"
        } else if isConnecting {
            return "Connecting..."
        } else {
            return "Tap to start call"
        }
    }
    
    private var statusColor: Color {
        switch conversationService.mode {
        case "listening":
            return .green
        case "speaking":
            return .blue
        default:
            return .secondary
        }
    }
    
    private var statusText: String {
        if isConnected {
            switch conversationService.mode {
            case "listening":
                return "Listening..."
            case "speaking":
                return "Speaking..."
            default:
                return "Connected"
            }
        } else if isConnecting {
            return "Connecting..."
        } else {
            return "Tap to start conversation"
        }
    }
    
    // MARK: - Actions
    
    private func toggleCall() async {
        if isConnected {
            // End the call and disconnect
            print("🔴 User tapped to end call")
            await conversationService.disconnect()
        } else if !isConnecting {
            // Start the call
            print("🟢 User tapped to start call")
            await conversationService.connect()
        }
        // Do nothing if already connecting
    }
}

#Preview {
    ContentView()
}


