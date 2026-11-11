import PianismCore
import SwiftUI

/// What Pro offers, its price and Buy, with Restore and Close (PRO-3). Opens only from a tap, never by itself. It lists
/// only what's in the app: each Pro feature adds its own line.
struct PaywallView: View {
    let pro: ProModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text("Piano sessions start, pause and save themselves while Pianism is open.", bundle: .module)
                    } icon: {
                        Image(systemName: "pianokeys")
                    }
                    Label(
                        LocalizedStringResource(
                            "Time per piece and skill, in all and over the last 30 days.", bundle: .module),
                        systemImage: "chart.bar")
                    Label(
                        LocalizedStringResource("Export every session as a spreadsheet file (CSV).", bundle: .module),
                        systemImage: "square.and.arrow.up")
                } header: {
                    Text("Included", bundle: .module)
                } footer: {
                    Text("One purchase, no subscription.", bundle: .module)
                }
                Section {
                    if pro.isPro {
                        Text("Pro is unlocked", bundle: .module)
                            .accessibilityIdentifier(AccessibilityID.paywallUnlocked)
                    } else {
                        buy
                    }
                } footer: {
                    if !pro.isPro, let notice = pro.purchaseNotice {
                        Text(notice.message)
                            .accessibilityIdentifier(AccessibilityID.paywallNotice)
                    }
                }
                if !pro.isPro {
                    Section {
                        Button {
                            Task { await pro.restore() }
                        } label: {
                            Text("Restore Purchases", bundle: .module)
                        }
                        .disabled(pro.isRestoring || pro.isBuying)
                        .accessibilityIdentifier(AccessibilityID.paywallRestore)
                    } footer: {
                        if let notice = pro.restoreNotice {
                            Text(notice.message)
                        }
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Pianism Pro"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.paywallClose)
                }
            }
            .task { await pro.loadOffer() }
        }
    }

    @ViewBuilder private var buy: some View {
        if let offer = pro.offer {
            Button {
                Task { await pro.buy() }
            } label: {
                Text("Unlock Pro for \(offer.displayPrice)", bundle: .module)
            }
            .disabled(pro.isBuying || pro.isRestoring)
            .accessibilityIdentifier(AccessibilityID.paywallBuy)
        } else if pro.isOfferUnavailable {
            VStack(alignment: .leading, spacing: 8) {
                Text("The price isn't available right now.", bundle: .module)
                Button {
                    Task { await pro.loadOffer() }
                } label: {
                    Text("Try Again", bundle: .module)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier(AccessibilityID.paywallRetry)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }
}

#Preview("Offer") {
    PaywallView(pro: .preview())
}

#Preview("No App Store, dark, AX5") {
    PaywallView(pro: .preview(offer: nil))
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Unlocked") {
    PaywallView(pro: .preview(unlocked: true))
}
