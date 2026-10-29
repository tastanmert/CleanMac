import Charts
import SwiftUI
import CleanMacCore

/// What CleanMac has freed so far, day by day, plus the items the user asked it to leave alone.
struct ActivityView: View {
    @State private var entries: [ActivityLog.Entry] = []
    @State private var ignored: [String] = []

    private var monthStart: Date { Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now }
    private var thisMonth: Int64 { entries.filter { $0.date >= monthStart }.reduce(0) { $0 + $1.bytes } }
    private var total: Int64 { entries.reduce(0) { $0 + $1.bytes } }

    private var chartStart: Date { Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: .now)) ?? .now }

    private var daily: [(day: Date, bytes: Int64)] {
        let grouped = Dictionary(grouping: entries.filter { $0.date >= chartStart }) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.map { ($0.key, $0.value.reduce(0) { $0 + $1.bytes }) }.sorted { $0.day < $1.day }
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: String(localized: "Etkinlik"), subtitle: String(localized: "CleanMac'in bu Mac'te yaptıkları. Kayıtlar yalnız bu Mac'te tutulur.")) {
                Button(String(localized: "Temizlik günlükleri")) {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/CleanMac"))
                }
                .buttonStyle(.borderless).foregroundStyle(Theme.secondary)
            }
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        stat("Bu ay", thisMonth.bytes)
                        stat(String(localized: "Toplam"), total.bytes)
                        stat(String(localized: "Temizlik"), String(localized: "\(entries.count) kez"))
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(String(localized: "Son 30 gün")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                            if daily.isEmpty {
                                Text(String(localized: "Henüz temizlik yapılmadı.")).font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                                    .frame(maxWidth: .infinity, minHeight: 120)
                            } else {
                                let scale: (unit: String, divisor: Double) = (daily.map(\.bytes).max() ?? 0) >= 1_000_000_000
                                    ? ("GB", 1_000_000_000) : ("MB", 1_000_000)
                                Chart(daily, id: \.day) { point in
                                    BarMark(x: .value(String(localized: "Gün"), point.day, unit: .day), y: .value(scale.unit, Double(point.bytes) / scale.divisor))
                                        .foregroundStyle(LinearGradient(colors: [Theme.glowDeep, Theme.glow], startPoint: .bottom, endPoint: .top))
                                        .cornerRadius(4)
                                }
                                .chartXScale(domain: chartStart...Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!)
                                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                                .chartYAxisLabel(scale.unit)
                                .frame(height: 160)
                            }
                        }
                        .padding(16)
                    }
                    if !entries.isEmpty {
                        Card {
                            ForEach(entries.suffix(30).reversed()) { entry in
                                HStack {
                                    Text(entry.source).font(.system(size: 12, weight: .medium))
                                    Text(String(localized: "\(entry.count) öğe")).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                                    Spacer()
                                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.tertiary)
                                    Text(entry.bytes.bytes).font(.system(size: 12).monospacedDigit()).frame(width: 80, alignment: .trailing)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 7)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Yoksayılanlar")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tertiary)
                        Card {
                            if ignored.isEmpty {
                                Text(String(localized: "Hiçbir şey yoksayılmadı. Bir öğeye sağ tıklayıp \"Bunu yoksay\" dersen taramalarda bir daha çıkmaz."))
                                    .font(.system(size: 12)).foregroundStyle(Theme.tertiary).padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(ignored, id: \.self) { path in
                                HStack {
                                    Text(path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                                        .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Button(String(localized: "Kaldır")) {
                                        IgnoreList.remove(path)
                                        load()
                                    }
                                    .controlSize(.small)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 7)
                            }
                        }
                    }
                }
                .padding(.horizontal, 32).padding(.bottom, 20)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        entries = ActivityLog.entries()
        ignored = IgnoreList.paths().sorted()
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Text(value).font(.system(size: 24, weight: .semibold).monospacedDigit())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.05)))
    }
}
