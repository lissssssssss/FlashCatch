import StoreKit
import SwiftUI

struct PaywallView: View {
    @ObservedObject var purchaseService: PurchaseService
    @ObservedObject var trialManager: TrialManager
    let onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "lock.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("免费试用已到期")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("您已免费使用瞬拾 90 天\n支付一次，永久使用所有功能")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                featureItem(icon: "checkmark.circle.fill", text: "永久解锁所有功能")
                featureItem(icon: "checkmark.circle.fill", text: "一次付费，无订阅")
                featureItem(icon: "checkmark.circle.fill", text: "后续更新免费享用")
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        await purchaseService.purchaseLifetime()
                    }
                }) {
                    Group {
                        if purchaseService.purchaseState == .purchasing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text(priceText)
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .background(Color.red)
                .cornerRadius(12)
                .disabled(purchaseService.purchaseState == .purchasing)

                Button(action: {
                    Task {
                        await purchaseService.restorePurchases()
                    }
                }) {
                    Text("恢复购买")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if case .failed(let message) = purchaseService.purchaseState {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .onChange(of: purchaseService.purchaseState) { newState in
            if newState == .purchased {
                onDismiss?()
            }
        }
    }

    private var priceText: String {
        if let product = purchaseService.product {
            return "永久解锁 — \(product.displayPrice)"
        }
        return "永久解锁 — $0.99"
    }

    private func featureItem(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
            Text(text)
                .font(.body)
            Spacer()
        }
    }
}
