import Foundation
import SwiftUI
import AVFoundation
import Combine

// Define a simple message structure since ConversationMessage might not be available
struct SimpleMessage: Identifiable {
    let id = UUID()
    let content: String
    let role: MessageRole
    let timestamp: Date = Date()
}

enum MessageRole: String, CaseIterable {
    case user = "user"
    case agent = "agent"
    case system = "system"
}

// Import the official ElevenLabs Swift SDK
import ElevenLabs

@MainActor
class ElevenLabsConversationService: ObservableObject {
    @Published var isConnected = false
    @Published var errorMessage: String?
    @Published var mode: String = "listening"
    @Published var status: String = "disconnected"
    @Published var audioLevel: Float = 0.0
    @Published var conversationId: String?
    @Published var messages: [SimpleMessage] = []
    @Published var conversation: Conversation?
    
    private let apiKey = Config.elevenLabsAPIKey
    private let agentId = Config.elevenLabsAgentID
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        print("✅ ElevenLabsConversationService initialized")
        print("🔑 Using agent ID: \(agentId)")
    }
    
    func connect() async {
        print("🔗 Starting conversation with ElevenLabs SDK...")
        
        // Clear any previous errors
        errorMessage = nil
        status = "connecting"
        
        do {
            // Use the official ElevenLabs SDK API from documentation
            let config = ConversationConfig(
                conversationOverrides: ConversationOverrides(textOnly: false)
            )
            
            conversation = try await ElevenLabs.startConversation(
                agentId: agentId,
                config: config
            )
            
            print("✅ Conversation started successfully")
            setupObservers()
            
        } catch {
            print("❌ Failed to start conversation: \(error)")
            errorMessage = "Failed to connect: \(error.localizedDescription)"
            status = "disconnected"
            isConnected = false
        }
    }
    
    private func setupObservers() {
        guard let conversation = conversation else { return }
        
        print("🔧 Setting up conversation observers...")
        
        // Monitor connection state
        conversation.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                print("📊 State: \(state)")
                self?.status = "\(state)"
                
                // Handle the specific ConversationState enum values from the SDK
                let stateString = "\(state)".lowercased()
                
                if stateString.contains("idle") {
                    self?.isConnected = false
                    self?.status = "disconnected"
                } else if stateString.contains("connecting") {
                    self?.isConnected = false
                    self?.status = "connecting"
                } else if stateString.contains("active") {
                    self?.isConnected = true
                    self?.status = "connected"
                    
                    // Extract conversation ID from active state if available
                    if stateString.contains("callinfo") {
                        // Try to extract the conversation/agent ID
                        self?.conversationId = self?.extractConversationId(from: state)
                    }
                } else if stateString.contains("ended") {
                    self?.isConnected = false
                    self?.status = "disconnected"
                    self?.conversationId = nil
                } else if stateString.contains("error") {
                    self?.isConnected = false
                    self?.status = "error"
                    self?.errorMessage = "Connection error occurred"
                }
            }
            .store(in: &cancellables)
        
        // Monitor messages - handle different message types gracefully
        conversation.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                print("💬 Messages: \(messages.count)")
                
                // Convert SDK messages to our simple format
                self?.messages = messages.compactMap { message in
                    // Handle different message types based on what's available
                    if let content = self?.extractMessageContent(from: message),
                       let role = self?.extractMessageRole(from: message) {
                        return SimpleMessage(content: content, role: role)
                    }
                    return nil
                }
            }
            .store(in: &cancellables)
        
        // Monitor agent state
        conversation.$agentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] agentState in
                print("🤖 Agent: \(agentState)")
                let agentStateString = "\(agentState)".lowercased()
                
                if agentStateString.contains("listening") {
                    self?.mode = "listening"
                } else if agentStateString.contains("speaking") {
                    self?.mode = "speaking"
                } else {
                    self?.mode = "\(agentState)"
                }
            }
            .store(in: &cancellables)
        
        // Note: Tool calls handling omitted for compatibility
        // The SDK may or may not have pendingToolCalls property
        
        print("✅ Observers setup complete")
    }
    
    // Helper method to extract conversation ID from active state
    private func extractConversationId(from state: Any) -> String? {
        let mirror = Mirror(reflecting: state)
        
        for child in mirror.children {
            if child.label == "callInfo" {
                let callInfoMirror = Mirror(reflecting: child.value)
                for callInfoChild in callInfoMirror.children {
                    if callInfoChild.label == "agentId" || callInfoChild.label == "conversationId" {
                        return callInfoChild.value as? String
                    }
                }
            }
        }
        
        return nil
    }
    
    // Helper method to extract content from SDK message
    private func extractMessageContent(from message: Any) -> String? {
        let mirror = Mirror(reflecting: message)
        
        // Try common content properties
        for child in mirror.children {
            if child.label == "content" || child.label == "text" || child.label == "message" {
                return child.value as? String
            }
        }
        
        // Fallback to string representation
        return String(describing: message)
    }
    
    // Helper method to extract role from SDK message
    private func extractMessageRole(from message: Any) -> MessageRole {
        let mirror = Mirror(reflecting: message)
        
        for child in mirror.children {
            if child.label == "role" {
                if let roleString = child.value as? String {
                    return MessageRole(rawValue: roleString.lowercased()) ?? .system
                }
                // Handle enum cases
                let roleDescription = String(describing: child.value).lowercased()
                if roleDescription.contains("user") {
                    return .user
                } else if roleDescription.contains("agent") || roleDescription.contains("assistant") {
                    return .agent
                }
            }
        }
        
        return .system
    }
    
    private func handleToolCall(_ toolCall: Any) async {
        print("🔧 Handling tool call: \(toolCall)")
        // Handle tool calls as needed for your specific use case
    }
    
    func disconnect() async {
        print("🔌 Disconnecting conversation...")
        
        // End the conversation using the official SDK method
        await conversation?.endConversation()
        conversation = nil
        cancellables.removeAll()
        
        // Update UI state
        isConnected = false
        status = "disconnected"
        mode = "listening"
        audioLevel = 0.0
        conversationId = nil
        errorMessage = nil
        messages.removeAll()
        
        print("✅ Disconnected successfully")
    }
    
    func sendMessage(_ message: String) async {
        guard let conversation = conversation else {
            print("⚠️ No conversation available to send message")
            return
        }
        
        do {
            try await conversation.sendMessage(message)
            print("📤 Sent message: \(message)")
        } catch {
            print("❌ Failed to send message: \(error)")
            errorMessage = "Failed to send message: \(error.localizedDescription)"
        }
    }
    
    func toggleMute() async {
        guard let conversation = conversation else {
            print("⚠️ No conversation available to toggle mute")
            return
        }
        
        do {
            try await conversation.toggleMute()
            print("🔇 Toggled mute")
        } catch {
            print("❌ Failed to toggle mute: \(error)")
        }
    }
} 
