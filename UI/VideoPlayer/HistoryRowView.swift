import SwiftUI

struct HistoryRowView: View {
    let record: RecordingRecord
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: UIImage?
    @State private var offset: CGFloat = 0
    @State private var showDelete = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete background
            if showDelete {
                HStack {
                    Spacer()
                    Button(action: onDelete) {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                    }
                    .background(Color.red)
                    .cornerRadius(8)
                }
                .padding(.horizontal, 32)
            }

            // Main row
            HStack(spacing: 12) {
                thumbnailView
                    .frame(width: 64, height: 64)
                    .cornerRadius(8)
                    .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDate(record.date))
                        .font(.subheadline)
                    Text(formatDuration(record.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offset = value.translation.width
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3)) {
                            if value.translation.width < -60 {
                                offset = -70
                                showDelete = true
                            } else {
                                offset = 0
                                showDelete = false
                            }
                        }
                    }
            )
            .onTapGesture {
                if showDelete {
                    withAnimation(.spring(response: 0.3)) {
                        offset = 0
                        showDelete = false
                    }
                } else {
                    onTap()
                }
            }
        }
        .task {
            let service = PhotoLibraryService()
            thumbnail = await service.fetchThumbnail(assetIdentifier: record.assetIdentifier)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .overlay(
                    Image(systemName: "video.fill")
                        .foregroundColor(.secondary)
                )
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        guard duration > 0 else { return "时长未知" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "时长 %02d:%02d", minutes, seconds)
    }
}
