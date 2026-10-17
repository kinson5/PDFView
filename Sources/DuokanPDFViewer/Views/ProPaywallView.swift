import SwiftUI

/// Premium Apple-style Pro paywall sheet offering a lifetime unlock for unlimited reading reflow and advanced features
public struct ProPaywallView: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    @ObservedObject private var proStore = ProStoreService.shared
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: PDFReaderViewModel) {
        self.viewModel = viewModel
    }

    private var lang: AppLanguage { viewModel.appLanguage }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 1. Pro Crown & App Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.82, blue: 0.35), Color(red: 0.98, green: 0.58, blue: 0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 76, height: 76)
                                .shadow(color: Color.orange.opacity(0.35), radius: 10, x: 0, y: 5)

                            Image(systemName: "crown.fill")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.top, 16)

                        Text("PDFview Pro")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(.primary)

                        Text(subtitleText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // 2. Pro Core Feature Highlights
                    VStack(spacing: 14) {
                        featureRow(
                            icon: "doc.text.image.fill",
                            color: .red,
                            title: feature1Title,
                            subtitle: feature1Subtitle
                        )
                        featureRow(
                            icon: "character.book.closed.fill",
                            color: .blue,
                            title: feature2Title,
                            subtitle: feature2Subtitle
                        )
                        featureRow(
                            icon: "wand.and.stars",
                            color: .purple,
                            title: feature3Title,
                            subtitle: feature3Subtitle
                        )
                        featureRow(
                            icon: "icloud.fill",
                            color: .cyan,
                            title: feature4Title,
                            subtitle: feature4Subtitle
                        )
                        featureRow(
                            icon: "person.2.fill",
                            color: .green,
                            title: feature5Title,
                            subtitle: feature5Subtitle
                        )
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.secondary.opacity(0.06))
                    )
                    .padding(.horizontal, 20)

                    // 3. Purchase & Action Section
                    VStack(spacing: 12) {
                        if proStore.isProUnlocked {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                                Text(alreadyUnlockedText)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            }
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.green.opacity(0.12))
                            )
                        } else {
                            Button(action: {
                                Task {
                                    await proStore.purchasePro()
                                }
                            }) {
                                HStack(spacing: 8) {
                                    if proStore.isPurchasing {
                                        ProgressView()
                                            .tint(.white)
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "sparkles")
                                            .font(.headline)
                                        Text(proStore.formattedPriceText)
                                            .font(.headline.weight(.bold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(
                                    LinearGradient(
                                        colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .shadow(color: Color.accentColor.opacity(0.35), radius: 8, x: 0, y: 4)
                            }
                            .disabled(proStore.isPurchasing)

                            // Restore Purchases Button
                            Button(action: {
                                Task {
                                    await proStore.restorePurchases()
                                }
                            }) {
                                Text(restorePurchasesText)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }

                        // Legal & Lifetime Note
                        Text(legalNoteText)
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.secondary)
                            .font(.title3)
                    }
                }
            }
            .alert(isPresented: Binding(
                get: { proStore.errorMessage != nil },
                set: { if !$0 { proStore.errorMessage = nil } }
            )) {
                Alert(
                    title: Text(alertNoticeTitle),
                    message: Text(proStore.errorMessage ?? ""),
                    dismissButton: .default(Text(okText))
                )
            }
            .onChange(of: proStore.isProUnlocked) { _, unlocked in
                if unlocked {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 580)
        #endif
    }

    @ViewBuilder
    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Localized Copy

    private var subtitleText: String {
        switch lang {
        case .zhHans: return "一次性买断 · 永久解锁全本智能重排与全部高级功能"
        case .zhHant: return "一次性買斷 · 永久解鎖全本智慧重排與全部高級功能"
        case .en: return "One-Time Purchase · Lifetime Pro Reflow & Full Features"
        case .de: return "Einmalkauf · Unbegrenzter Umfluss & Pro-Funktionen"
        case .ja: return "買い切り版 · 全ページのリフロー＆Pro全機能を永久解放"
        }
    }

    private var feature1Title: String {
        switch lang {
        case .zhHans: return "全书无限页数智能重排"
        case .zhHant: return "全書無限頁數智慧重排"
        case .en: return "Unlimited Pages Smart Reflow"
        case .de: return "Unbegrenzter Textumfluss"
        case .ja: return "全ページ無制限のスマートリフロー"
        }
    }

    private var feature1Subtitle: String {
        switch lang {
        case .zhHans: return "突破前 20 页免费试读限制，大部头书籍与扫描论文从容精读"
        case .zhHant: return "突破前 20 頁免費試讀限制，大部頭書籍與掃描論文從容精讀"
        case .en: return "Unlock beyond the first 20 preview pages for complete books and dense papers."
        case .de: return "Mehr als 20 Vorschauseiten für vollständige Bücher und Dokumente lesen."
        case .ja: return "最初の20ページ試読制限を解除し、長編書や論文も全編快適に閲覧。"
        }
    }

    private var feature2Title: String {
        switch lang {
        case .zhHans: return "Apple 原生双语对照翻译"
        case .zhHant: return "Apple 原生雙語對照翻譯"
        case .en: return "Apple Native Bilingual Translation"
        case .de: return "Apple Native Übersetzung"
        case .ja: return "Apple純正バイリンガル対訳"
        }
    }

    private var feature2Subtitle: String {
        switch lang {
        case .zhHans: return "内置系统级高精度神经翻译引擎，外文原著与论文无缝对照"
        case .zhHant: return "內建系統級高精度神經翻譯引擎，外文原著與論文無縫對照"
        case .en: return "System-integrated translation engine for effortless bilingual side-by-side reading."
        case .de: return "Nahtlose Übersetzung für fremdsprachige Literatur und Arbeiten."
        case .ja: return "高精度なシステム翻訳エンジンにより、外国語の文献も対訳で快適読書。"
        }
    }

    private var feature3Title: String {
        switch lang {
        case .zhHans: return "智能画质增强与多档浓墨"
        case .zhHant: return "智慧畫質增強與多檔濃墨"
        case .en: return "Smart Scan Enhancement & Deep Ink"
        case .de: return "Bildoptimierung & Tintenstärke"
        case .ja: return "スマート画質補正・濃墨モード"
        }
    }

    private var feature3Subtitle: String {
        switch lang {
        case .zhHans: return "智能去黑边、自动透视纠偏、对比度提升，拯救泛黄与模糊老旧扫描件"
        case .zhHant: return "智慧去黑邊、自動透視糾偏、對比度提升，拯救泛黃與模糊老舊掃描件"
        case .en: return "Auto deskew, border cleaning, and heavy ink for crisp readability on aged scans."
        case .de: return "Automatische Entzerrung und Ränderbereinigung für historische Scans."
        case .ja: return "黒枠除去・傾き補正・コントラスト向上で、古いスキャン書籍も鮮明に。"
        }
    }

    private var feature4Title: String {
        switch lang {
        case .zhHans: return "iCloud 跨设备阅读进度同步"
        case .zhHant: return "iCloud 跨設備閱讀進度同步"
        case .en: return "iCloud Reading Progress Sync"
        case .de: return "iCloud Lesefortschritt-Sync"
        case .ja: return "iCloud 読書進捗の自動同期"
        }
    }

    private var feature4Subtitle: String {
        switch lang {
        case .zhHans: return "在 iPhone、iPad 和 Mac 上通过文件名自动匹配，随时无缝续读"
        case .zhHant: return "在 iPhone、iPad 和 Mac 上透過檔名自動匹配，隨時無縫續讀"
        case .en: return "Auto-matches reading progress across your iPhone, iPad, and Mac seamlessly."
        case .de: return "Automatischer Abgleich des Lesestands auf iPhone, iPad und Mac."
        case .ja: return "iPhone・iPad・Macの間でファイル名から進捗を自動一致。"
        }
    }

    private var feature5Title: String {
        switch lang {
        case .zhHans: return "支持苹果家人共享 (Family Sharing)"
        case .zhHant: return "支援 Apple 家人共享 (Family Sharing)"
        case .en: return "Apple Family Sharing Included"
        case .de: return "Apple Familienfreigabe inklusive"
        case .ja: return "ファミリー共有に対応"
        }
    }

    private var feature5Subtitle: String {
        switch lang {
        case .zhHans: return "一次购买，家庭群组内的所有成员多台设备均可共同享受 Pro 权益"
        case .zhHant: return "一次購買，家庭群組內的所有成員多台設備均可共同享受 Pro 權益"
        case .en: return "One purchase shares with up to 5 family members across all their Apple devices."
        case .de: return "Ein Kauf für bis zu 5 Familienmitglieder auf allen Apple-Geräten."
        case .ja: return "1回のご購入で、ご家族最大5名のすべてのAppleデバイスでProを利用可能。"
        }
    }

    private var alreadyUnlockedText: String {
        switch lang {
        case .zhHans: return "已成功激活 PDFview Pro"
        case .zhHant: return "已成功啟用 PDFview Pro"
        case .en: return "PDFview Pro Activated"
        case .de: return "PDFview Pro aktiviert"
        case .ja: return "PDFview Pro 有効化済み"
        }
    }

    private var restorePurchasesText: String {
        switch lang {
        case .zhHans: return "恢复已购项目 (Restore Purchases)"
        case .zhHant: return "恢復已購項目 (Restore Purchases)"
        case .en: return "Restore Purchases"
        case .de: return "Käufe wiederherstellen"
        case .ja: return "購入を復元"
        }
    }

    private var legalNoteText: String {
        switch lang {
        case .zhHans: return "非订阅型项目 · 一次购买永久有效 · 支持同一 Apple ID 或家人共享在您的全部 iPhone、iPad 与 Mac 上使用。"
        case .zhHant: return "非訂閱型項目 · 一次購買永久有效 · 支援同一 Apple ID 或家人共享在您的全部 iPhone、iPad 與 Mac 上使用。"
        case .en: return "Non-consumable purchase · Lifetime access · Family Sharing enabled across iPhone, iPad, and Mac."
        case .de: return "Kein Abonnement · Lebenslanger Zugriff · Gültig für alle Geräte über die gleiche Apple-ID."
        case .ja: return "サブスクリプションではありません · 永久買い切り · 同一Apple IDおよびファミリー共有で利用可能。"
        }
    }

    private var alertNoticeTitle: String {
        switch lang {
        case .zhHans: return "提示"
        case .zhHant: return "提示"
        case .en: return "Notice"
        case .de: return "Hinweis"
        case .ja: return "お知らせ"
        }
    }

    private var okText: String {
        switch lang {
        case .zhHans: return "确定"
        case .zhHant: return "確定"
        case .en: return "OK"
        case .de: return "OK"
        case .ja: return "OK"
        }
    }
}
