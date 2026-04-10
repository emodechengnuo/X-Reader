//
//  StatusBarView.swift
//  X-Reader
//
//  Bottom status bar
//


import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var l10n = L10n.shared
    
    private func t(_ key: L10nKey) -> String { l10n.string(key) }
    
    var body: some View {
        HStack(spacing: 16) {
            // Left: Page info
            HStack(spacing: 6) {
                Image(systemName: "doc")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if appState.document != nil {
                    Text(String(format: t(.pageInfo), appState.currentPage + 1, appState.totalPages))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                } else {
                    Text(t(.noFile))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Center: TTS status
            if appState.isSpeaking {
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text(t(.speaking))
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }

            // Kokoro TTS model download progress
            if !appState.ttsService.isKokoroReady && appState.ttsService.isKokoroLoading {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(appState.ttsService.kokoroStatus)
                        .font(.caption)
                        .foregroundColor(.orange)
                    ProgressView(value: appState.ttsService.kokoroProgress)
                        .frame(width: 60)
                }
            }
            
            // OCR progress
            if appState.isOCRRunning {
                HStack(spacing: 6) {
                    ProgressView(value: appState.ocrProgress)
                        .frame(width: 80)
                    Text("OCR \(Int(appState.ocrProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            
            Spacer()
            
            // Right: Info
            HStack(spacing: 6) {
                if appState.showAnalysis {
                    Image(systemName: "sidebar.trailing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(t(.analysisOn))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
