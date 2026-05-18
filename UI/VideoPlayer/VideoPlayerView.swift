import AVKit
import SwiftUI

struct VideoPlayerView: View {
    let assetIdentifier: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .overlay(alignment: .topLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))
                    .padding()
            }
        }
        .task {
            await loadVideo()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func loadVideo() async {
        let service = PhotoLibraryService()
        guard let url = await service.fetchVideoURL(assetIdentifier: assetIdentifier) else {
            errorMessage = "无法加载视频，可能已被删除"
            isLoading = false
            return
        }

        let avPlayer = AVPlayer(url: url)
        player = avPlayer
        isLoading = false
        avPlayer.play()
    }
}
