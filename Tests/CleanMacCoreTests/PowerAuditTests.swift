import Foundation
import Testing
@testable import CleanMacCore

/// Fixtures are trimmed copies of real output from an M1 Pro on macOS 27.
struct PowerAuditTests {
    let custom = """
    Battery Power:
     Sleep On Power Button 1
     lowpowermode         0
     powernap             0
     womp                 1
    AC Power:
     lowpowermode         0
     womp                 1
     displaysleep         2
    """

    let assertions = """
    Listed by owning process:
       pid 4544(caffeinate): [0x0000049a00018622] 71:45:08 PreventUserIdleSystemSleep named: "caffeinate command-line tool"
    \tDetails: caffeinate asserting forever
       pid 4544(caffeinate): [0x0000049a00058623] 71:45:08 PreventUserIdleDisplaySleep named: "caffeinate command-line tool"
    \tDetails: caffeinate asserting forever
       pid 17887(Claude): [0x0002383100019c0f] 04:31:57 NoIdleSleepAssertion named: "Electron"
       pid 519(powerd): [0x00024f3e0001a2cb] 01:15:32 PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while display is on"
    """

    @Test func `custom settings split by power source`() {
        let (battery, ac) = PowerAudit.parseCustom(custom)
        #expect(battery["lowpowermode"] == "0")
        #expect(battery["Sleep On Power Button"] == "1")
        #expect(ac["displaysleep"] == "2")
        #expect(ac["powernap"] == nil)
    }

    @Test func `assertions keep process, type, age and forever`() {
        let list = PowerAudit.parseAssertions(assertions)
        #expect(list.count == 4)
        #expect(list[1].process == "caffeinate" && list[1].type == "PreventUserIdleDisplaySleep" && list[1].forever)
        #expect(list[1].age == 71 * 3600 + 45 * 60 + 8)
        #expect(list[2].process == "Claude" && !list[2].forever)
    }

    @Test func `battery reads percent, cycles and capacity`() {
        let b = PowerAudit.parseBattery(
            batt: "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1)\t100%; discharging; 3:52 remaining",
            profile: "Cycle Count: 163\n          Condition: Normal\n          Maximum Capacity: %93")
        #expect(b.onBattery && b.percent == 100 && b.cycles == 163 && b.maxCapacity == 93)
        #expect(PowerAudit.parseBattery(batt: "", profile: "Maximum Capacity: 85%").maxCapacity == 85)
    }

    @Test func `top uses only the last sample`() {
        let top = """
        PID    COMMAND          POWER
        575    WindowServer     0.0
        PID    COMMAND          POWER
        575    WindowServer     47.6
        10816  Hermes Helper (R 31.7
        """
        let usage = PowerAudit.parseTop(top)
        #expect(usage.count == 2)
        #expect(usage[1].command == "Hermes Helper (R" && usage[1].power == 31.7)
    }

    @Test func `dark wakes are counted within the window`() {
        let log = """
        2026-10-18 16:39:25 +0300 DarkWake            \tDarkWake from Deep Idle [CDN] : due to wifibt
        2026-10-18 16:40:02 +0300 DarkWake            \tDarkWake from Deep Idle [CDN] : due to wifibt
        2026-10-16 10:00:00 +0300 DarkWake            \tDarkWake from Deep Idle [CDN] : due to rtc
        """
        let since = ISO8601DateFormatter().date(from: "2026-10-17T16:00:00+03:00")!
        #expect(PowerAudit.countDarkWakes(log, since: since) == 2)
    }

    @Test func `swap is read in megabytes`() {
        #expect(PowerAudit.parseSwapUsed("total = 2048.00M  used = 627.69M  free = 1420.31M  (encrypted)") == 627)
        #expect(PowerAudit.parseSwapUsed("total = 4096.00M  used = 1.50G  free = 1.00G") == 1536)
    }

    @Test func `only ownerless MCP helpers can be killed`() {
        var r = PowerAudit.Readings()
        r.processes = PowerAudit.parseProcesses("""
          101     1  90000 npm exec @playwright/mcp@latest
          102   500  80000 npm exec @modelcontextprotocol/server-pdf --stdio
          103   102 120000 node /Users/x/.npm/_npx/abc/node_modules/.bin/mcp-pdf-server --stdio
          104     1  50000 /opt/homebrew/bin/ollama serve
        """)
        let orphans = PowerAudit.findings(r).first { $0.id == "mcp-orphans" }
        #expect(orphans?.fix == .kill(pids: [101]))
    }

    @Test func `helpers are counted per session, not per child`() {
        var r = PowerAudit.Readings()
        r.processes = PowerAudit.parseProcesses("""
          102   500 600000 npm exec @modelcontextprotocol/server-pdf --stdio
          103   102 600000 node /x/.bin/mcp-pdf-server --stdio
          104   600   9000 npm exec @playwright/mcp@latest
        """)
        let session = PowerAudit.findings(r).first { $0.id == "mcp-sessions" }
        #expect(session?.detail.contains("2 ayrı oturum") == true)
    }

    @Test func `rules flag today's real problems`() {
        var r = PowerAudit.Readings()
        (r.battery, r.ac) = PowerAudit.parseCustom(custom)
        r.assertions = PowerAudit.parseAssertions(assertions)
        r.darkWakes24h = 665
        r.power = .init(onBattery: false, percent: 100, cycles: 163, maxCapacity: 93)
        r.swapUsedMB = 600
        let ids = Set(PowerAudit.findings(r).map(\.id))
        #expect(ids.isSuperset(of: ["caffeinate-display", "lowpower-battery", "womp", "charge-limit", "blocker-Claude"]))
        #expect(!ids.contains("swap") && !ids.contains("powernap-battery") && !ids.contains("blocker-powerd"))
        #expect(PowerAudit.findings(r).first?.id == "womp")   // the only warning sorts first
    }

    @Test func `score drops with severity and never goes negative`() {
        let f = { (s: PowerAudit.Severity) in PowerAudit.Finding(id: UUID().uuidString, title: "", detail: "", severity: s, fix: nil) }
        #expect(PowerAudit.score([]) == 100)
        #expect(PowerAudit.score([f(.warning), f(.suggestion), f(.info)]) == 76)
        #expect(PowerAudit.score(Array(repeating: f(.warning), count: 10)) == 0)
    }

    @Test func `history round-trips newest first`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "power-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = PowerAudit.Snapshot(date: .now.addingTimeInterval(-7 * 86_400), score: 60, swapUsedMB: 600, darkWakes24h: 665, findingIDs: ["womp"])
        let new = PowerAudit.Snapshot(date: .now, score: 85, swapUsedMB: 100, darkWakes24h: 10, findingIDs: [])
        PowerAudit.save(old, in: folder)
        PowerAudit.save(new, in: folder)
        #expect(PowerAudit.history(in: folder).map(\.score) == [85, 60])
    }
}
