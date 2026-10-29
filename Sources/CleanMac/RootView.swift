import SwiftUI
import CleanMacCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            SidebarView(compact: model.isFocused)
                .frame(width: model.isFocused ? 76 : 232)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            if isLanding { HealthPill().padding(.top, 12).padding(.trailing, 16).transition(.opacity) }
        }
        .environment(\.modulePalette, model.module.palette)
        .background { ModuleBackground(palette: model.module.palette) }
        .foregroundStyle(Theme.text)
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.45), value: model.isFocused)
        .overlay { GlassDialogHost() }
        .glassConfirm(isPresented: $model.showSwitchScanConfirm, symbol: "arrow.triangle.2.circlepath",
                      title: String(localized: "Devam eden tarama durdurulsun mu?"),
                      message: String(localized: "Önceki taramada şimdiye kadar bulunanlar atılır."),
                      confirm: String(localized: "Durdur ve yenisini başlat")) { model.stop(); model.scan() }
        .glassConfirm(isPresented: $model.showResetConfirm, symbol: "arrow.counterclockwise",
                      title: String(localized: "Mevcut tarama sonuçları sıfırlansın mı?"),
                      message: String(localized: "Sonuçlar kaydedilmez; öğeleri yeniden bulmak için yeni bir tarama gerekir."),
                      confirm: String(localized: "Baştan başla")) { model.reset() }
        .task {
            // Wait for the first-launch cards; a new version then opens its panel unless another one is up.
            try? await Task.sleep(for: .seconds(4))
            await model.selfUpdate.runAutomaticChecks {
                if model.panel == nil, model.dialog == nil, !model.showFDA, !model.isBusy { model.panel = .update }
            }
        }
        .task {
            // First launch: offer Full Disk Access once.
            if !UserDefaults.standard.bool(forKey: "fdaOnboardingShown") {
                UserDefaults.standard.set(true, forKey: "fdaOnboardingShown")
                try? await Task.sleep(for: .seconds(0.9))
                if !FullDiskAccess.isGranted { model.showFDA = true }
            }
            // Free space changes while the app sits open (builds, downloads, other cleaners).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                let fresh = DiskSpace.current()
                if fresh.available != model.disk.available { model.disk = fresh }
            }
        }
    }

    /// The pill lives on module front pages only; deeper screens use that corner for search and sorting.
    private var isLanding: Bool {
        if model.module.categories != nil {
            if case .idle = model.phaseForCurrentModule { return true }
            return false
        }
        return !model.openedTools.contains(model.module)
    }

    private var content: some View {
        ZStack {
            moduleContent
                .id(contentID)
                .transition(.blurFade)
        }
        .animation(.easeInOut(duration: 0.45), value: contentID)
    }

    /// Changes whenever the screen changes meaningfully, so the blur transition plays.
    private var contentID: String {
        let module = model.module
        if module.categories != nil {
            let phase: String = switch model.phaseForCurrentModule {
            case .idle: "idle"
            case .scanning, .cleaning: "working"
            case .results: "results"
            case .reviewing: "review"
            case .done: "done"
            }
            return "\(module.rawValue)-\(phase)"
        }
        return "\(module.rawValue)-\(model.openedTools.contains(module))"
    }

    @ViewBuilder private var moduleContent: some View {
        let module = model.module
        if module.categories != nil {
            switch model.phaseForCurrentModule {
            case .idle: ModuleLanding(module: module)
            case .scanning: WorkingView(mode: .scanning)
            case .cleaning: WorkingView(mode: .cleaning)
            case .results: ResultsSummaryView()
            case .reviewing: ReviewManagerView()
            case .done(let report): DoneView(report: report)
            }
        } else if !model.openedTools.contains(module) {
            ModuleLanding(module: module)
        } else {
            switch module {
            case .applications: ApplicationsView()
            case .performance: PerformanceView()
            case .clutter: ClutterView()
            case .spaceLens: SpaceMapView()
            case .trash: TrashView()
            case .activity: ActivityView()
            case .tools: ToolsView()
            default: EmptyView()
            }
        }
    }
}

/// The module's colour world: a gradient with a soft bloom, cross-faded when the module changes.
struct ModuleBackground: View {
    let palette: Palette

    var body: some View {
        ZStack {
            palette.background
            RadialGradient(colors: [palette.glow.opacity(0.35), .clear], center: UnitPoint(x: 0.42, y: 0.42),
                           startRadius: 20, endRadius: 520)
            RadialGradient(colors: [Color(hex: palette.orbB).opacity(0.18), .clear], center: .bottomTrailing,
                           startRadius: 10, endRadius: 600)
        }
        .id(palette)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.7), value: palette)
        .ignoresSafeArea()
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    let compact: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // No title bar text: the traffic lights sit on the glass, the list starts below them.
            Color.clear.frame(height: 58)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Module.allCases) { module in
                        if module == .protection || module == .applications || module == .trash { Spacer().frame(height: 10) }
                        SidebarRow(module: module, compact: compact, isActive: model.module == module,
                                   isWorking: model.isBusy && model.sessionModule == module) {
                            model.select(module)
                        }
                    }
                }
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)
            if !compact {
                DiskMeter(disk: model.disk).padding(20).transition(.opacity)
            }
        }
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    }
}

struct SidebarRow: View {
    let module: Module
    let compact: Bool
    let isActive: Bool
    let isWorking: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(module.palette.orb)
                        .opacity(isActive ? 1 : 0.5)
                        .shadow(color: module.palette.glow.opacity(isActive ? 0.6 : 0), radius: 6)
                    Image(systemName: module.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 26, height: 26)
                .overlay(alignment: .topTrailing) {
                    if isWorking {
                        Circle().fill(Theme.glow).frame(width: 7, height: 7).offset(x: 2, y: -2)
                    }
                }
                if !compact {
                    Text(module.title)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, compact ? 0 : 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? Color.white.opacity(0.11) : hovering ? Color.white.opacity(0.05) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(isActive ? 0.09 : 0), lineWidth: 1))
            )
            .animation(.smooth(duration: 0.25), value: isActive)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .onHover { hovering = $0 }
        .help(module.title)
        .accessibilityLabel(module.title)
    }
}

struct DiskMeter: View {
    let disk: DiskSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "internaldrive").foregroundStyle(Theme.secondary)
                Text(disk.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.glowDeep, Theme.glow], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * disk.fraction)
                }
            }
            .frame(height: 6)
            Text(String(localized: "\(disk.available.bytes) boş · \(disk.total.bytes)"))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
            if disk.purgeable > 1_000_000_000 {
                Text(String(localized: "\(disk.purgeable.bytes) silinebilir"))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
                    .help(String(localized: "macOS'un yer gerektiğinde kendiliğinden boşalttığı alan: iCloud'a yüklenmiş dosyaların yerel kopyaları, önbellekler ve yerel Time Machine anlık görüntüleri."))
            }
        }
        .animation(.smooth(duration: 0.8), value: disk.available)
    }
}
