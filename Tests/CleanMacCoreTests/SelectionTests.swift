import Foundation
import Testing
@testable import CleanMacCore

struct SelectionTests {
    func item(_ name: String, selected: Bool, open: Bool = false) -> CleanItem {
        CleanItem(title: name, size: 1, action: .trash(URL(filePath: "/x/\(name)")), isSelected: selected, appIsOpen: open)
    }

    @Test func `review findings never arrive ticked, even when the strategy suggested it`() {
        let review = CleanRule.catalog.first { $0.risk == .review }!
        let result = CategoryResult(rule: review, items: [item("a", selected: true)])
        #expect(result.items.allSatisfy { !$0.isSelected })
    }

    @Test func `bulk select ticks only what the scanner recommended`() {
        let safe = CleanRule.catalog.first { $0.risk == .safe }!
        var result = CategoryResult(rule: safe, items: [item("ok", selected: true),
                                                        item("desktop.dmg", selected: false),
                                                        item("open", selected: true, open: true)])
        result.select(false)
        result.select(true)
        #expect(result.items.map(\.isSelected) == [true, false, false])
    }

    @Test func `bulk select on a review rule ticks nothing`() {
        let review = CleanRule.catalog.first { $0.risk == .review }!
        var result = CategoryResult(rule: review, items: [item("a", selected: false), item("b", selected: true)])
        result.select(true)
        #expect(result.items.allSatisfy { !$0.isSelected })
    }
}

struct KeepOneTests {
    func items(_ ticks: [Bool]) -> [CleanItem] {
        ticks.enumerated().map { CleanItem(title: "\($0.offset)", size: 1, action: .trash(URL(filePath: "/x/\($0.offset)")), isSelected: $0.element) }
    }

    @Test func `a fully ticked group still keeps one copy`() {
        #expect(items([true, true, true]).selectedLeavingOne().map(\.title) == ["1", "2"])
        #expect(items([true, true, true]).selectedLeavingOne(keep: 2).map(\.title) == ["0", "1"])
    }

    @Test func `a partly ticked group is taken as ticked`() {
        #expect(items([false, true, true]).selectedLeavingOne().map(\.title) == ["1", "2"])
    }
}
