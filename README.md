# 🎙️ Voice Assistant with ElevenLabs AI

A SwiftUI iOS app that enables real-time voice conversations with AI using ElevenLabs' Conversational AI API.

## ✨ Features

- **One-touch voice activation** with animated green/red button
- **Real-time voice streaming** to ElevenLabs Conversational AI
- **Live AI voice responses** with seamless audio playback
- **Beautiful, minimalistic UI** following Apple Human Interface Guidelines
- **Automatic microphone permission handling**
- **Connection status indicators** with smooth animations

## 🚀 Quick Start

### 1. Prerequisites

- iOS 16.0+ device (required for real voice functionality)
- Xcode 15.0+
- Active ElevenLabs account with Conversational AI access

### 2. ElevenLabs Setup

1. **Create an ElevenLabs Account**
   - Visit [elevenlabs.io](https://elevenlabs.io) and sign up
   - Upgrade to a plan that includes Conversational AI access

2. **Get Your API Key**
   - Go to your profile settings in ElevenLabs
   - Copy your API key

3. **Create a Conversational Agent**
   - Navigate to the Conversational AI section
   - Create a new agent and configure its personality
   - Copy the Agent ID

### 3. App Configuration

1. **Clone and open the project in Xcode**

2. **Configure API credentials**
   - Open `VoiceAssistant/Config.swift`
   - Replace the placeholder values:
   ```swift
   static let elevenLabsAPIKey = "your_actual_api_key_here"
   static let elevenLabsAgentID = "your_actual_agent_id_here"
   ```

3. **Build and run** on a physical iOS device (simulator won't have microphone access)

## 🎯 How to Use

1. **Launch the app** - You'll see a green phone button
2. **Tap to start** - The button turns orange (connecting), then red (connected)
3. **Start talking** - The app streams your voice to ElevenLabs AI
4. **Listen to AI responses** - The AI's voice plays through your speakers
5. **Tap red button to end** - Disconnects and returns to green

## 🏗️ Project Structure

```
VoiceAssistant/
├── ContentView.swift              # Main UI with call button
├── Item.swift                     # CallState enum
├── VoiceAssistantApp.swift        # App entry point
├── Config.swift                   # API configuration
├── Info.plist                     # Permissions and settings
│
├── Services/
│   ├── ElevenLabsService.swift    # WebSocket API integration
│   ├── AudioPlaybackService.swift # AI voice playback
│   └── MicPermissionService.swift # Microphone permissions
│
└── Utils/
    └── AudioUtils.swift           # Audio session helpers
```

## 🔧 Technical Details

### Audio Configuration
- **Sample Rate**: 16kHz (optimized for ElevenLabs)
- **Format**: 16-bit PCM mono
- **Buffer Size**: 1024 samples
- **Latency**: Optimized for real-time conversation

### Permissions Required
- **Microphone**: For voice input
- **Audio Background**: For continuous conversation

### Network Requirements
- **WebSocket Connection**: To `wss://api.elevenlabs.io`
- **TLS 1.2+**: Secure communication
- **Stable Internet**: For real-time voice streaming

## 🎨 UI Features

### Button States
- **🟢 Green**: Ready to start conversation
- **🟠 Orange**: Connecting to ElevenLabs
- **🔴 Red**: Active conversation (tap to end)

### Animations
- **Spring animations** for smooth state transitions
- **Recording indicators** with pulsing dots
- **Touch feedback** with scale effects
- **Status text updates** with context-aware messaging

## 🛠️ Development

### Adding Features
The app is designed for easy extension:

1. **Custom AI Personalities**: Modify agent configuration in `ElevenLabsService`
2. **Audio Effects**: Extend `AudioPlaybackService` for voice processing
3. **UI Themes**: Add color schemes in `ContentView`
4. **Conversation History**: Implement message logging

### Error Handling
- **Connection failures**: Automatic retry with user feedback
- **Permission denials**: Guided settings navigation
- **API errors**: Clear error messages with actionable steps

## 📱 Testing

### Simulator Limitations
- ⚠️ **No microphone access** in iOS Simulator
- ✅ **UI testing** works perfectly
- ✅ **Button animations** can be tested

### Physical Device Testing
- ✅ **Full functionality** on real devices
- ✅ **Microphone permissions** work correctly
- ✅ **Real-time voice** streaming and playback

## 🔒 Privacy & Security

- **Microphone usage** clearly explained to users
- **Secure WebSocket** connection (TLS 1.2+)
- **No local audio storage** - streams directly to ElevenLabs
- **Permission-based access** with graceful handling of denials

## 🐛 Troubleshooting

### Common Issues

**"Please configure your ElevenLabs API key"**
- Check `Config.swift` has your actual credentials
- Verify API key is valid and has Conversational AI access

**"Microphone Permission Required"**
- Grant microphone access in iOS Settings
- Restart the app after granting permission

**"Connection lost"**
- Check internet connectivity
- Verify ElevenLabs service status
- Ensure API key has sufficient credits

**No audio playback**
- Check device volume settings
- Ensure speakers/headphones are working
- Try disconnecting and reconnecting

## 📄 License

This project is open source. Please ensure you comply with ElevenLabs' terms of service when using their API.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

---

**Ready to talk to AI? Configure your credentials and start your conversation!** 🚀 