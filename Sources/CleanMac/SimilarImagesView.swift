import QuickLookThumbnailing
import SwiftUI
import CleanMacCore

@Observable
final class SimilarImagesModel {
    var groups: [SimilarImages.Group] = []
    var isScanning = false
    var isRemoving = false   // one removal at a time: a second tap would clean the same files again
    var hasScanned = false
    var progress = ""
    var report: CleanReport?
    var confirm = false

    var allItems: [CleanItem] { groups.flatMap(\.items) }
    /// What a removal takes: the ticked photos, always leaving one of each group (the best by default).
    var chosen: [CleanItem] { groups.flatMap { $0.items.selectedLeavingOne(keep: $0.best) } }

    func scan() {
        isScanning = true
        report = nil
        Task {
            groups = await SimilarImages().find { text in
                await MainActor.run { self.progress = text }
            }
            isScanning = false
            hasScanned = true
        }
    }

    /// Keep the best shot of each group (largest, then newest), select the rest.
    func smartSelect() {
        for g in groups.indices {
            for i in groups[g].items.indices { groups[g].items[i].isSelected = i != groups[g].best }
        }
    }

    func selectNone() {
        for g in groups.indices { groups[g].items.setAll(false) }
    }

    func toggle(_ item: CleanItem, in group: SimilarImages.Group) {
        guard let g = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[g].items.toggle(item)
    }

    func removeSelected() {
        let chosen = self.chosen
        guard !isRemoving, !chosen.isEmpty else { return }
        isRemoving = true
        Task {
            report = await Cleaner.live().clean(chosen, source: String(localized: "Benzer görseller"))
            isRemoving = false
            scan()
        }
    }
}

struct SimilarImagesView: View {
    @Environment(AppModel.self) private var app
    private var model: SimilarImagesModel { app.similarImages }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ToolHeader(title: String(localized: "Benzer görseller"),
                       subtitle: model.hasScanned
                           ? String(localized: "\(model.groups.count) grup. Her grupta en büyük çözünürlüklü kare ★ ile işaretli; Akıllı seçim onu bırakıp diğerlerini seçer.")
                           : String(localized: "Resimler, Masaüstü, İndirilenler ve Belgeler'deki birbirine çok benzeyen fotoğrafları bulur (seri çekimler, düzenlenmiş kopyalar). Tamamen bu Mac'te çalışır; Fotoğraflar arşivine dokunmaz.")) {
                Button(model.hasScanned ? String(localized: "Yeniden tara") : String(localized: "Tara")) { model.scan() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.secondary)
                    .disabled(model.isScanning)
            }
            if let report = model.report {
                ReportBanner(report: report) { model.report = nil }
            }
            if model.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(String(localized: "İnceleniyor: \(model.progress)")).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.secondary)
                }
                .frame(maxHeight: .infinity)
            } else if !model.hasScanned {
                VStack(spacing: 16) {
                    Image(systemName: "photo.stack").font(.system(size: 44)).foregroundStyle(Theme.secondary)
                    PrimaryButton(title: String(localized: "Benzerleri bul")) { model.scan() }
                }
                .frame(maxHeight: .infinity)
            } else if model.groups.isEmpty {
                EmptyStateView(title: String(localized: "Benzer görsel yok"), symbol: "photo.on.rectangle")
            } else {
                HStack(spacing: 14) {
                    SelectMenu(selected: model.allItems.selectedCount, total: model.allItems.count - model.groups.count,
                               onAll: { model.smartSelect() }, onNone: { model.selectNone() })
                        .help(String(localized: "Tümünü seç: her grubun en iyi karesi kalır"))
                    Spacer()
                }
                .padding(.horizontal, 32).padding(.bottom, 10)
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.groups) { group in
                            Card {
                                HStack {
                                    Text(String(localized: "\(group.items.count) benzer görsel")).font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                }
                                .padding(.horizontal, 16).padding(.top, 10)
                                ScrollView(.horizontal) {
                                    HStack(spacing: 10) {
                                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                            ImageTile(item: item, isBest: index == group.best) { model.toggle(item, in: group) }
                                        }
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                }
                                .scrollIndicators(.never)
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
                }
            }
            ToolActionBar(selectedSize: model.allItems.selectedSize, selectedCount: model.allItems.selectedCount,
                          actionTitle: String(localized: "Çöp'e taşı"), busy: model.isRemoving || model.isScanning) { model.confirm = true }
        }
        .glassConfirm(isPresented: $model.confirm, symbol: "photo.stack", title: String(localized: "\(model.chosen.count) görsel Çöp'e taşınsın mı?"),
                      message: String(localized: "Her gruptan en az bir görsel kalır. Çöp'ü boşaltana kadar geri alınabilir."), confirm: String(localized: "Çöp'e taşı")) { model.removeSelected() }
    }
}

/// A thumbnail with a checkbox; click toggles, double-click opens the image.
struct ImageTile: View {
    let item: CleanItem
    let isBest: Bool
    let onToggle: () -> Void
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFill()
                    } else {
                        Rectangle().fill(.white.opacity(0.06))
                    }
                }
                .frame(width: 150, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(item.isSelected ? Theme.glow : .white.opacity(0.1), lineWidth: item.isSelected ? 2 : 1))
                CheckBox(state: item.isSelected ? .on : .off, action: onToggle).padding(6)
                if isBest {
                    Image(systemName: "star.fill").font(.system(size: 10)).padding(5)
                        .background(Circle().fill(.black.opacity(0.5)))
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(6)
                }
            }
            Text(item.title).font(.system(size: 11)).lineLimit(1).truncationMode(.middle).frame(width: 150, alignment: .leading)
            Text(item.size.bytes).font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if let url = item.url { NSWorkspace.shared.open(url) } }
        .onTapGesture { onToggle() }
        .task {
            guard let url = item.url else { return }
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 300, height: 220), scale: 2,
                                                       representationTypes: .thumbnail)
            thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
    }
}
