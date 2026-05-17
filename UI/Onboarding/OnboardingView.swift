import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)

            VStack(spacing: 12) {
                Text("瞬拾")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("一键回溯直播高光瞬间")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 20) {
                featureRow(
                    icon: "memorychip",
                    title: "内存预缓存",
                    desc: "自动缓存最近 20 秒画面，不占存储"
                )
                featureRow(
                    icon: "hand.tap",
                    title: "一键捕获",
                    desc: "点击左上角按钮，瞬间保存高光片段"
                )
                featureRow(
                    icon: "photo.on.rectangle",
                    title: "自动保存",
                    desc: "视频直接存入相册，无水印"
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            Button(action: {
                viewModel.requestPermissions()
            }) {
                if viewModel.isRequesting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                } else {
                    Text(viewModel.buttonTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
            }
            .background(Color.red)
            .cornerRadius(12)
            .padding(.horizontal, 32)
            .disabled(viewModel.isRequesting)

            if viewModel.permissionGranted {
                Color.clear
                    .onAppear { onComplete() }
            }
        }
        .padding(.bottom, 48)
    }

    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.red)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}
