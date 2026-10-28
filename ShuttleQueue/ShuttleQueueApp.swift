import SwiftUI

@main
struct ShuttleQueueApp: App {
    @State private var store = Store.load()

    init() {
        #if DEBUG
        SessionState.selfCheck()
        Simulation.selfCheck()
        print("DEBUG self-checks passed")
        if CommandLine.arguments.contains("-simulate") { Simulation.main() }
        if CommandLine.arguments.contains("-bench") { Simulation.bench() }
        if CommandLine.arguments.contains("-waitsweep") { Simulation.waitSweep() }
        if CommandLine.arguments.contains("-parity") { Simulation.parity() }
        #endif
    }

    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if CommandLine.arguments.contains("-schedule-ui"), !store.sessions.isEmpty {
                    ScheduledMatchesSheet(s: $store.sessions[store.sessions.count - 1])
                } else if CommandLine.arguments.contains("-schedule-new-ui"), !store.sessions.isEmpty {
                    ScheduleMatchSheet(s: $store.sessions[store.sessions.count - 1])
                } else {
                    HomeView(sessions: $store.sessions)
                }
                #else
                HomeView(sessions: $store.sessions)
                #endif
            }
                .onChange(of: store) { store.save() }
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .capped()
        }
    }
}

/// Stable visual randomness: independent courts without affecting matchmaking or saved data.
struct RallyMotion {
    let seed: UInt32
    init(_ courtID: String) {
        seed = courtID.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
    }
    func unit(_ shot: Int, _ channel: Int) -> Double {
        var x = seed ^ (UInt32(truncatingIfNeeded: shot + 1) &* 374761393)
            ^ (UInt32(truncatingIfNeeded: channel + 1) &* 668265263)
        x = (x ^ (x >> 13)) &* 1274126177
        return Double(x ^ (x >> 16)) / Double(UInt32.max)
    }
}

enum Format: String, Codable, CaseIterable {
    case singles, doubles
    var needed: Int { self == .singles ? 2 : 4 }
}

enum Preference: String, Codable, CaseIterable {
    case any, singles, doubles
}

let skillNames = ["New", "Beginner", "Intermediate", "Advanced", "Strong"]
/// What each level button sets (Add Player, Edit Player's "Set level"). Names still follow the rounded rating, and each preset rounds to its own level.
let skillPresets = [1.0, 1.75, 2.5, 3.5, 4.5]

struct Player: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var skill = 3.0 // rating: 1 = New … 5 = Strong, nudged after every win or loss
    var pref = Preference.any
    var paused = false
    var readyAt = Date()
    var first: Bool? // moved to front by hand; cleared after their next game
    var since: Date? // when they last became free to play (arrived, came back in, finished a game); nil = readyAt
    var credit: Int? // games counted for queue order on arrival: the least anyone present had played, so a late arrival joins at par
    var away: Bool? // true = not here (yet): out of the line until marked present; nil = present
    var rated: Int? // rated games before this session: 0 for a new player; nil = a regular from before this was counted
    var lock: UUID? // locked teammate (set on both): always play doubles as a team; see SessionState's locked teammates

    /// The whole-number level shown as dots and in the skill picker.
    var level: Int { min(5, max(1, Int(skill.rounded()))) }
}

struct Match: Codable, Equatable {
    var teamA: [UUID]
    var teamB: [UUID]
    var start = Date()
    var scheduled: UUID?
    var jumpers: [UUID]?
    var queueOverride: Bool? // explicit organiser replacement, retained when matching mode changes
    var tournamentMatch: Int? // TMatch id when this is a tournament game
}

struct Court: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var format: Format
    var match: Match?
    var shuffles: Int? // how many times the organiser tapped shuffle on the "Next up" preview
    var locked: Int?   // a side of "Next up" kept when shuffling (0 = team A, 1 = team B); cleared when the game starts
    var plan: Match?   // a "Next up" lineup the organiser set by hand (replacing a player); overrides the automatic pick
    var manual: [UUID?]? // manual mode: the players chosen slot by slot (team A, then team B); nil = automatic. Cleared when its game finishes
}

/// A finished game. `winner` is 0 for team A, 1 for team B, nil if no result was recorded.
struct GameResult: Codable, Equatable {
    var teamA: [UUID]
    var teamB: [UUID]
    var winner: Int?
    var court: String
    var start: Date
    var end = Date()
    var changes: [UUID: Double]? // rating change actually applied to each player (after the 1–5 cap)
    var scheduled: UUID?
    var jumpers: [UUID]?
    var tournamentLabel: String?  // e.g. "Round 2", "Upper Final"

    var length: TimeInterval { end.timeIntervalSince(start) }
}

struct Pairing {
    var format: Format
    var a: [Player]
    var b: [Player]
    var match: Int? // TMatch id in tournament mode
    var court: UUID? // the open court this game is lined up for (nil: a preview for a busy format)
    var rematchFallback = false
    var options = 1 // how many fair alternatives the shuffle button can cycle through
    var scheduled: UUID?
    var note: String? // why doubles teams are mixed rather than similar skill (nil when similar)
}

/// Repeatable random draws (SplitMix64): the same shuffle count always gives the same group,
/// so a court's preview doesn't change every time the screen redraws.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Everything saved on the iPad: the session being run plus earlier ones.
/// When this installed copy stops opening: its signing profile's expiry (7 days on a free developer account),
/// after which it has to be reinstalled from Xcode. nil in the simulator, which carries no profile.
enum InstallExpiry {
    static let date: Date? = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
        .flatMap { try? Data(contentsOf: $0) }.flatMap(expiration)

    /// The profile is a signed wrapper around an XML plist; reads ExpirationDate out of that plist.
    static func expiration(in profile: Data) -> Date? {
        guard let start = profile.range(of: Data("<?xml".utf8)), let end = profile.range(of: Data("</plist>".utf8)),
              start.lowerBound < end.upperBound,
              let plist = try? PropertyListSerialization.propertyList(from: profile[start.lowerBound..<end.upperBound], format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }

    /// What the Options menu shows, e.g. "Renew in 3 days · Sat, Oct 11, 1:43 PM".
    static func label(_ expiry: Date, now: Date = Date()) -> String {
        let when = expiry.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        if expiry <= now { return "Expired \(when). Reinstall from Xcode." }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: expiry)).day ?? 0
        return days == 0 ? "Renew today, by \(expiry.formatted(date: .omitted, time: .shortened))"
            : "Renew in \(days) day\(days == 1 ? "" : "s") · \(when)"
    }
}

struct Store: Codable, Equatable {
    /// Every session: live ones (not ended) and past ones.
    var sessions: [SessionState] = []

    /// The session simulations start from: the newest live one, else the newest.
    var current: SessionState {
        sessions.filter(\.isLive).max { $0.date < $1.date } ?? sessions.max { $0.date < $1.date } ?? SessionState()
    }

    init(sessions: [SessionState] = []) { self.sessions = sessions }

    private enum CodingKeys: String, CodingKey { case sessions, current, past }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let all = try c.decodeIfPresent([SessionState].self, forKey: .sessions) { sessions = all; for i in sessions.indices { sessions[i].normalizeEnd() }; return }
        // Saved before live sessions: one current session plus earlier ones, which count as ended.
        let past = try c.decodeIfPresent([SessionState].self, forKey: .past) ?? []
        sessions = past.map { var x = $0; if x.ended == nil { x.ended = x.results.map(\.end).max() ?? x.date }; return x }
        if let current = try c.decodeIfPresent(SessionState.self, forKey: .current) { sessions.append(current) }
        for i in sessions.indices { sessions[i].normalizeEnd() }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sessions, forKey: .sessions)
    }

    /// Match the webapp's export format without changing the iPad's saved-data format.
    func webExportData(currentID: UUID? = nil) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let encoded = try encoder.encode(self)
        var all = (try JSONSerialization.jsonObject(with: encoded) as! [String: Any])["sessions"] as! [[String: Any]]
        func teams(_ value: [String: Any]) -> [String: Any] {
            var value = value
            value["a"] = value.removeValue(forKey: "teamA")
            value["b"] = value.removeValue(forKey: "teamB")
            value["tm"] = value.removeValue(forKey: "tournamentMatch")
            value["label"] = value.removeValue(forKey: "tournamentLabel")
            return value
        }
        func slot(_ value: Slot) -> [Any] {
            switch value {
            case .entrant(let n): return ["e", n]
            case .seed(let n): return ["s", n]
            case .winnerOf(let n): return ["w", n]
            case .loserOf(let n): return ["l", n]
            }
        }
        for i in all.indices {
            all[i]["courts"] = (all[i]["courts"] as! [[String: Any]]).map { court in
                var court = court
                for key in ["match", "plan"] { if let match = court[key] as? [String: Any] { court[key] = teams(match) } }
                return court
            }
            all[i]["results"] = (all[i]["results"] as! [[String: Any]]).enumerated().map { j, result in
                var result = teams(result)
                if let changes = sessions[i].results[j].changes { result["changes"] = Dictionary(uniqueKeysWithValues: changes.map { ($0.key.uuidString, $0.value) }) }
                return result
            }
            if let requests = all[i]["scheduled"] as? [[String: Any]] { all[i]["scheduled"] = requests.map(teams) }
            if var tournament = all[i]["tournament"] as? [String: Any], let model = sessions[i].tournament {
                tournament["matches"] = (tournament["matches"] as! [[String: Any]]).enumerated().map { j, match in
                    var match = match
                    match["a"] = slot(model.matches[j].a); match["b"] = slot(model.matches[j].b)
                    return match
                }
                all[i]["tournament"] = tournament
            }
        }
        let selected = currentID.flatMap { id in sessions.first { $0.id == id } } ?? sessions.filter(\.isLive).max { $0.date < $1.date } ?? sessions.max { $0.date < $1.date }
        return try JSONSerialization.data(withJSONObject: ["currentId": selected.map { $0.id.uuidString } as Any? ?? NSNull(), "sessions": all], options: [.prettyPrinted, .sortedKeys])
    }

    #if DEBUG
    static func webExportSelfCheck() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var session = SessionState(players: (0..<4).map { Player(name: "Export \($0)", readyAt: date) })
        session.date = date; session.hours = 3; session.queueMatching = .equalSkill
        let ids = session.players.map(\.id), request = ScheduledMatch(format: .doubles, teamA: Array(ids.prefix(2)), teamB: Array(ids.suffix(2)))
        session.players[0].lock = ids[1]; session.players[1].lock = ids[0]
        session.players[0].since = date; session.players[0].credit = 2; session.players[0].rated = 7
        session.scheduled = [request]; session.scheduleUnlocked = true
        session.scheduledActive = request.id
        session.scheduled![0].activatedAt = date; session.scheduled![0].returning = [ids[0]]
        session.scheduled![0].readyJumpers = [ids[0]]; session.scheduled![0].idleReleased = true
        session.scheduled![0].assignedCourt = session.courts[0].id; session.scheduled![0].postponedUntil = date.addingTimeInterval(600)
        session.courts[0].match = Match(teamA: request.teamA, teamB: request.teamB, start: date, scheduled: request.id, jumpers: [ids[0]], tournamentMatch: 0)
        session.courts[1].plan = session.courts[0].match; session.courts[1].manual = [ids[0], nil]
        session.results = [GameResult(teamA: request.teamA, teamB: request.teamB, winner: 0, court: "Court 1", start: date, end: date.addingTimeInterval(720), changes: [ids[0]: 0.125], scheduled: request.id, jumpers: [ids[0]], tournamentLabel: "Round Robin")]
        session.tournament = Tournament(format: .doubles, entrants: [request.teamA, request.teamB], advance: 4)
        let store = Store(sessions: [session])
        let data = try! store.webExportData(currentID: session.id)
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let exported = (json["sessions"] as! [[String: Any]])[0]
        let result = (exported["results"] as! [[String: Any]])[0]
        assert(exported["date"] as? Double == 1_700_000_000_000 && result["a"] as? [String] == request.teamA.map(\.uuidString))
        assert((result["changes"] as? [String: Double])?[ids[0].uuidString] == 0.125 && result["label"] as? String == "Round Robin")
        assert((json["sessions"] as? [[String: Any]])?.first?["queueMatching"] as? String == "equalSkill")
        assert(json["currentId"] as? String == session.id.uuidString && session.date == date, "export preserves native data")
        if CommandLine.arguments.contains("-export-check") { try! data.write(to: URL.documentsDirectory.appending(path: "web-export-check.json")) }
    }
    #endif

    static let url = URL.documentsDirectory.appending(path: "sessions.json")

    static func load() -> Store {
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Store.self, from: d) { s.save(); return s }
        // Carry over the single session saved by the first version of the app.
        struct V1: Decodable { var players: [Player]; var courts: [Court] }
        if let d = try? Data(contentsOf: URL.documentsDirectory.appending(path: "session.json")),
           let v1 = try? JSONDecoder().decode(V1.self, from: d) {
            return Store(sessions: [SessionState(players: v1.players, courts: v1.courts)])
        }
        return Store()
    }

    func save() {
        do { try JSONEncoder().encode(self).write(to: Self.url, options: .atomic) }
        catch { print("Save failed:", error) }
    }
}

enum QueueMatching: String, Codable, CaseIterable {
    case auto, equalSkill, balancedSkill

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .equalSkill: return "Equal Skill"
        case .balancedSkill: return "Balanced Skill"
        }
    }
    var explanation: String {
        switch self {
        case .auto: return "Similar skill first: within 1.0, then 1.5, then mixed balanced teams."
        case .equalSkill: return "Automatic games stay within 1.0 matching rating point. Use saved ratings if a losing streak prevents a skill group; otherwise courts wait."
        case .balancedSkill: return "Players due next play with balanced teams, allowing mixed skill levels."
        }
    }
}

struct SessionState: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    var players: [Player] = []
    var courts: [Court] = [
        Court(name: "Court 1", format: .doubles),
        Court(name: "Court 2", format: .singles),
    ]
    var results: [GameResult] = []
    var tournament: Tournament? // nil = queue mode
    var ended: Date? // set by End Session; nil = live
    var name: String? // nil: shown by its date
    var hours: Double? // planned length
    var scheduled: [ScheduledMatch]?
    var queueMatching: QueueMatching? // nil keeps the original Auto matching
    var scheduleUnlocked: Bool?
    var scheduledActive: UUID?

    var matchingMode: QueueMatching { queueMatching ?? .auto }
    var matchingHelp: String { matchingMode.explanation }
    var waitingMessage: String { matchingMode == .equalSkill ? "Waiting for a legal group within 1.0 rating point" : "Waiting for available players" }

    func skillRangeAllowed(_ ids: [UUID]) -> Bool {
        guard matchingMode == .equalSkill else { return true }
        let format: Format = ids.count == 2 ? .singles : .doubles
        let skills = ids.map { matchSkill($0, format: format) }
        return (skills.max() ?? 0) - (skills.min() ?? 0) <= Self.similarSpread + 1e-9
    }

    mutating func setQueueMatching(_ mode: QueueMatching) {
        guard mode != matchingMode else { return }
        queueMatching = mode
        for i in courts.indices where courts[i].match == nil {
            if courts[i].plan?.queueOverride != true { courts[i].plan = nil }
            courts[i].locked = nil
            courts[i].shuffles = nil
        }
    }

    var title: String { name ?? date.formatted(.dateTime.weekday().day().month()) }
    var isLive: Bool { ended == nil }
    /// When play began: the first game's start.
    var started: Date? { (results.map(\.start) + courts.compactMap { $0.match?.start }).min() }
    /// When the planned length runs out, once play has begun.
    var endsAt: Date? { hours.flatMap { h in started.map { $0.addingTimeInterval(h * 3600) } } }
    /// When this player's wait began: their last game's end, or when they arrived. Sitting out doesn't restart it, and
    /// nothing counts before the session's first game (before then it's now, so nobody is overdue).
    func waitStart(_ p: Player) -> Date { max(p.since ?? p.readyAt, started ?? Self.now) }

    /// The games that count. A cancelled game ("no result") stays in the history but isn't a game: it doesn't count
    /// towards anyone's games, partners, repeats or ratings, and its players went back to where they were in line.
    var games: [GameResult] { results.filter { $0.winner != nil } }

    // MARK: Matchmaking

    // ponytail: singles opponents within 1 level count as a fair match; tune to the spread of your group
    static let singlesRange = 1.0

    /// Who the longest-rested player can face in singles, best first, searching the whole queue:
    /// within `singlesRange` beats out of range; then players who've rested as long (waiting since before any
    /// later game finished) beat anyone just off court; then closest skill, then longest wait.
    /// Out-of-range opponents are offered only when nobody in range is waiting.
    static func singlesRivals(_ q: [Player], finishes: [Date]) -> [Player] {
        guard let head = q.first, q.count >= 2 else { return [] }
        let nextFinish = finishes.filter { $0 > head.readyAt }.min() ?? .distantFuture
        let ranked = q.dropFirst().enumerated().map { i, p in
            let gap = abs(p.skill - head.skill)
            return (key: (gap <= singlesRange ? 0 : 1, p.readyAt < nextFinish ? 0 : 1, gap, i), p: p)
        }
        .sorted { $0.key < $1.key }
        let inRange = ranked.filter { $0.key.0 == 0 }.map(\.p)
        return inRange.isEmpty ? [ranked[0].p] : Array(inRange.prefix(3))
    }

    /// Singles: whoever has rested longest plays. `choice` is the shuffle count, cycling through `singlesRivals`.
    static func pickSingles(_ q: [Player], finishes: [Date] = [], choice: Int = 0) -> Pairing? {
        let rivals = singlesRivals(q, finishes: finishes)
        guard let head = q.first, !rivals.isEmpty else { return nil }
        return Pairing(format: .singles, a: [head], b: [rivals[choice % rivals.count]], options: rivals.count)
    }

    // ponytail: "fair" = team averages within 0.75 of a level; tune if shuffles feel too narrow or too lopsided
    static let fairGap = 0.75
    static var matchupHistory: [String: String]? // scoped to one automatic pick, like lockCtx
    static func teamKey(_ ids: [UUID]) -> String { ids.map(\.uuidString).sorted().joined(separator: ",") }
    var lastTeamOpponents: [String: String] {
        var out: [String: String] = [:]
        for r in games where r.teamA.count == 2 && r.teamB.count == 2 {
            let a = Self.teamKey(r.teamA), b = Self.teamKey(r.teamB)
            out[a] = b; out[b] = a
        }
        return out
    }
    static func rematchAllowed(_ a: [UUID], _ b: [UUID], history: [String: String]? = nil) -> Bool {
        guard a.count == 2 && b.count == 2 else { return true }
        let history = history ?? matchupHistory ?? [:], x = teamKey(a), y = teamKey(b)
        return history[x] != y && history[y] != x
    }
    func automaticMatchupAllowed(_ a: [UUID], _ b: [UUID]) -> Bool {
        guard a.count == 2 && b.count == 2 else { return true }
        if !Self.rematchAllowed(a,b,history:lastTeamOpponents) {
            let line = eligible(.doubles)
            guard line.count <= Self.rematchFallbackPlayers, pick(.doubles, from: line)?.rematchFallback == true else { return false }
        }
        let locked = [a,b].allSatisfy { team in player(team[0])?.lock == team[1] && player(team[1])?.lock == team[0] }
        return !locked || !lockedRematchBlocked(a,b)
    }
    static let rematchFallbackPlayers = 8
    static let lockRematchGames = 2
    static let lockGameLead = 1 // locked games cannot pull anyone further ahead of the waiting line

    static func recallLimit(_ line: [Player], games: [UUID: Int], justOff: Set<UUID>) -> Int {
        let low = line.map { games[$0.id, default: 0] }.min() ?? 0
        let needed = max(0, 4 - line.filter { !justOff.contains($0.id) }.count)
        let counts = line.filter { justOff.contains($0.id) }.map { games[$0.id, default: 0] }.sorted()
        return max(low, counts.prefix(needed).last ?? low)
    }

    /// Ways to split four players into two fair teams (strongest-with-newest first). A split that stacks one side
    /// is never offered; if no split is fair, the least uneven ones (ties included, so shuffle can still swap them).
    static func fairSplits(_ four: [Player]) -> [(a: [Player], b: [Player])] {
        let s = four.sorted { $0.skill > $1.skill }
        let all = [([s[0], s[3]], [s[1], s[2]]), ([s[0], s[2]], [s[1], s[3]]), ([s[0], s[1]], [s[2], s[3]])]
        func gap(_ t: ([Player], [Player])) -> Double {
            abs(t.0.map(\.skill).reduce(0, +) - t.1.map(\.skill).reduce(0, +)) / 2
        }
        let best = all.map(gap).min()!
        return all.filter { gap($0) <= max(fairGap, best + 0.001) }.map { (a: $0.0, b: $0.1) }
    }

    /// Last resort: the fairest split of these four.
    static func lastResortSplits(_ four: [Player]) -> [(a: [Player], b: [Player])] {
        let s = four.sorted { $0.skill > $1.skill }
        let all: [(a: [Player], b: [Player])] = [([s[0], s[3]], [s[1], s[2]]), ([s[0], s[2]], [s[1], s[3]]), ([s[0], s[1]], [s[2], s[3]])]
        func gap(_ t: (a: [Player], b: [Player])) -> Double { abs(t.a.map(\.skill).reduce(0, +) - t.b.map(\.skill).reduce(0, +)) }
        let valid = all.filter { t in
            guard rematchAllowed(t.a.map(\.id),t.b.map(\.id)) else { return false }
            guard let ctx = lockCtx else { return true }
            return keepsLocks(t.a.map(\.id), t.b.map(\.id), ctx.locks, strict: ctx.strict, real: ctx.real, opponents: ctx.opponents, rested: ctx.rested)
        }
        return valid.min { gap($0) < gap($1) }.map { [$0] } ?? []
    }

    /// The first in line (if rested) plus the three rested players, of the first 12, who make the evenest teams, however
    /// uneven; anyone overdue (the first `must`) included. nil if fewer than four are rested.
    static func restedFour(_ q: [Player], must: Int, justOff: Set<UUID>) -> [Player]? {
        // The first in line and anyone overdue must play.
        guard !q.isEmpty, !q.prefix(max(1, must)).contains(where: { justOff.contains($0.id) }) else { return nil }
        let rested = Array(q.filter { !justOff.contains($0.id) }.prefix(12))
        guard rested.count >= 4 else { return nil }
        var best: (gap: Double, four: [Player])?
        for k in 3..<rested.count {
            for j in 2..<k {
                for i in 1..<j where (1..<must).allSatisfy([i, j, k].contains) {
                    let four = [rested[0], rested[i], rested[j], rested[k]]
                    guard let t = lastResortSplits(four).first else { continue }
                    let gap = abs(t.a.map(\.skill).reduce(0, +) - t.b.map(\.skill).reduce(0, +))
                    if gap < (best?.gap ?? .infinity) - 1e-9 { best = (gap, four) }
                }
            }
        }
        return best?.four
    }

    /// The longest-rested player plus the earliest three after them who can make fair teams;
    /// the next four in line if no group can.
    // ponytail: searches the first 12 in line (165 groups); widen if big, uneven sessions still get lopsided games
    /// Keeps as many of the first `must` (anyone overdue, longest waiting first) as fair teams allow.
    static func fairFour(_ q: [Player], must: Int = 1) -> [Player] {
        let pool = Array(q.prefix(12))
        for keep in stride(from: max(1, must), through: 1, by: -1) {
            for k in 3..<pool.count {
                for j in 2..<k {
                    for i in 1..<j where (1..<keep).allSatisfy([i, j, k].contains) {
                        let four = [pool[0], pool[i], pool[j], pool[k]]
                        let best = fairSplits(four)[0]
                        if abs(best.a.map(\.skill).reduce(0, +) - best.b.map(\.skill).reduce(0, +)) / 2 <= fairGap { return four }
                    }
                }
            }
        }
        return Array(pool.prefix(4))
    }

    // ponytail: each pair of the four who shared a recent game costs 1, a repeated partnership 2 more;
    // at 3 or more (the same four again always is), balanced teams are tried instead
    static let repeatLimit = 3
    // Doubles rules, chosen by simulating this group's nights:
    static let similarSpread = 1.0 // "similar" = all four within 1 level of each other
    static let widerSpread = 1.5   // tried when every similar group would repeat recent partners or opponents
    // Nobody should wait longer than `waitCap`. Anyone who has waited `waitPriority` (a little less, since a court still has to
    // free up) plays in the next game, and that game may stretch to `overdueSpread` levels with balanced teams at worst.
    static let waitCap: TimeInterval = 30 * 60
    // ponytail: 20 minutes, chosen by simulating 18 and 22 players on 2 courts: the longest wait was 27 and 31 minutes,
    // against 38 and 39 when triggering at 30. Retune if courts or group size change a lot.
    static var waitPriority: TimeInterval = 20 * 60 // var only so the simulation can try other triggers
    static let overdueSpread = 2.0
    #if DEBUG
    static var simulatedNow: Date? // the simulation's clock
    static var now: Date { simulatedNow ?? Date() }
    #else
    static var now: Date { Date() }
    #endif

    /// Each player's partners and opponents from their last two doubles games.
    typealias Recent = [UUID: (partners: Set<UUID>, opponents: Set<UUID>)]

    /// How much a lineup repeats recent games: 1 for every pair of the four who shared a recent game,
    /// plus 2 for each team that partnered lately.
    static func repeats(_ a: [Player], _ b: [Player], _ recent: Recent) -> Int {
        func met(_ x: Player, _ y: Player) -> Bool {
            [(x, y), (y, x)].contains { p, q in recent[p.id].map { $0.partners.contains(q.id) || $0.opponents.contains(q.id) } ?? false }
        }
        func partnered(_ x: Player, _ y: Player) -> Bool {
            (recent[x.id]?.partners.contains(y.id) ?? false) || (recent[y.id]?.partners.contains(x.id) ?? false)
        }
        let four = a + b
        var n = 0
        for i in four.indices { for j in four.indices where j > i && met(four[i], four[j]) { n += 1 } }
        for t in [a, b] where t.count == 2 && partnered(t[0], t[1]) { n += 2 }
        return n
    }

    /// The longest-rested player plus three from `pool` (positions in `q`) that `allowed` accepts: fewest players
    /// straight off court first, then fewest repeats, then whoever has waited longest. Splits come back least repetitive first.
    typealias Pick = (splits: [(a: [Player], b: [Player])], penalty: Int, justOff: Int)

    static func bestFour(_ q: [Player], pool: [Int], recent: Recent, justOff: Set<UUID>, bySpread: Bool = false,
                         must: Int = 1, together: Set<UUID> = [], games: [UUID: Int] = [:], heavyFirst: Bool = false,
                         allowed: ([Player]) -> Bool) -> Pick? {
        guard pool.count >= 3 else { return nil }
        var best: (key: [Int], splits: [(a: [Player], b: [Player])], penalty: Int)?
        let lk = lockCtx.map { c in c.locks.filter { l in q.contains { $0.id == l.x } && q.contains { $0.id == l.y } } } ?? []
        let ids = { (t: [Player]) in t.map(\.id) }
        let limit = recallLimit(q, games: games, justOff: justOff)
        for k in 2..<pool.count {
            for j in 1..<k {
                for i in 0..<j {
                    let picked = [pool[i], pool[j], pool[k]], four = [q[0]] + picked.map { q[$0] }
                    guard (1..<must).allSatisfy(picked.contains), allowed(four), lk.isEmpty || lockMembers(ids(four), lk) else { continue }
                    let fair = fairSplits(four).filter { s in rematchAllowed(ids(s.a),ids(s.b)) && (together.isEmpty || [s.a, s.b].contains { together.isSubset(of: $0.map(\.id)) })
                        && (lk.isEmpty || keepsLocks(ids(s.a), ids(s.b), lk, strict: lockCtx!.strict, real: lockCtx!.real, opponents: lockCtx!.opponents, rested: lockCtx!.rested)) }
                    guard !fair.isEmpty else { continue }
                    guard !four.contains(where: { justOff.contains($0.id) && games[$0.id,default:0] > limit }) else { continue }
                    let splits = fair.enumerated().sorted {
                        let x = abs($0.element.a.map(\.skill).reduce(0,+) - $0.element.b.map(\.skill).reduce(0,+))
                        let y = abs($1.element.a.map(\.skill).reduce(0,+) - $1.element.b.map(\.skill).reduce(0,+))
                        return (x,$0.offset) < (y,$1.offset)
                    }.map(\.element)
                    let range = four.map(\.skill).max()! - four.map(\.skill).min()!
                    let off = four.filter { justOff.contains($0.id) }.count
                    let played = picked.reduce(0) { $0 + games[q[$1].id,default:0] }
                    let key = [off] + (bySpread ? [Int((range*4).rounded())] : []) + [played] + (bySpread ? [Int((range*100).rounded())] : []) + [pool[k],picked.reduce(0,+)]
                    if best.map({ key.lexicographicallyPrecedes($0.key) }) ?? true { best = (key, splits, 0) }
                }
            }
        }
        return best.map { ($0.splits, $0.penalty, $0.key[0]) }
    }

    /// Doubles. Similar skill first: the longest-rested player plus three within a level of each other, choosing the
    /// group and teams that repeat recent partners and opponents least. If that would call someone straight back on court
    /// or repeat too much (or no similar group is waiting), a wider range, then balanced teams from the nearest ratings.
    /// `choice` is the shuffle count, cycling through that group's fair splits.
    // ponytail: searches up to 12 candidates each way (165 groups); widen if big sessions still repeat a lot
    /// `together`: two players who must be teammates (hot/cold teaming); nil if no fair game has them together.
    /// `accept`: an extra test every four must pass (a hot/cold game's limits for the other players).
    static func pickDoubles(_ q: [Player], choice: Int = 0, recent: Recent = [:], must: Int = 1, justOff: Set<UUID> = [],
                            together: Set<UUID> = [], accept: ([Player]) -> Bool = { _ in true },
                            capSpread: Double? = nil, games: [UUID: Int] = [:], balancedOnly: Bool = false, searchLimit: Int = 12) -> Pairing? {
        guard q.count >= 4, let head = q.first else { return nil }
        // How far a pick falls short: players straight off court first (rest beats skill match), then repeats past the limit.
        func shortfall(_ g: Pick?) -> [Int] {
            guard let g else { return [.max, .max] }
            return [g.justOff, 0]
        }
        func reason(_ from: Pick?, _ to: Pick) -> String {
            (from?.justOff ?? 0) > to.justOff ? (to.justOff == 0 ? "so nobody goes straight back" : "so fewer go straight back") : "for balanced teams"
        }
        func similarGroup(_ spread: Double) -> Pick? {
            let near = Array(Set(1..<must).union(q.indices.dropFirst().filter { abs(q[$0].skill - head.skill) <= spread + 1e-9 }.prefix(searchLimit))).sorted()
            return bestFour(q, pool: near, recent: recent, justOff: justOff, must: must, together: together, games: games) { four in
                let s = four.map(\.skill); return s.max()! - s.min()! <= spread + 1e-9 && accept(four)
            }
        }
        let fine = [0, 0]
        // balancedOnly (too few players for similar groups): straight to even teams, in queue order, no rating-range preference.
        var best = balancedOnly ? nil : similarGroup(similarSpread), note: String?
        if !balancedOnly, shortfall(best) != fine, let w = similarGroup(widerSpread), shortfall(w).lexicographicallyPrecedes(shortfall(best)) {
            note = "wider skill range " + reason(best, w)
            best = w
        }
        // Balanced teams from the nearest ratings; with `capSpread` (an overdue game), only within that many levels unless
        // nothing at all is free, so the waiting player still plays.
        func balanced(_ cap: Double?) -> Pick? {
            bestFour(q, pool: Array(1..<min(searchLimit, q.count)), recent: recent, justOff: justOff, bySpread: !balancedOnly, must: must, together: together,
                     games: games, heavyFirst: balancedOnly) { four in
                let t = fairSplits(four)[0], s = four.map(\.skill)
                return abs(t.a.map(\.skill).reduce(0, +) - t.b.map(\.skill).reduce(0, +)) / 2 <= fairGap && accept(four)
                    && cap.map { s.max()! - s.min()! <= $0 + 1e-9 } ?? true
            }
        }
        if shortfall(best) != fine, let b = balanced(capSpread) ?? (best == nil && capSpread != nil ? balanced(nil) : nil),
           shortfall(b).lexicographicallyPrecedes(shortfall(best)) {
            note = balancedOnly ? nil : best == nil ? "mixed teams, no similar group free" : "mixed teams " + reason(best, b)
            best = b
        }
        if best == nil && !together.isEmpty { return nil }
        var splits = best?.splits
        if splits == nil {
            let limit = recallLimit(q, games: games, justOff: justOff), pool = Array(q.prefix(searchLimit))
            outer: for k in 3..<pool.count {
                for j in 2..<k {
                    for i in 1..<j {
                        let four = [pool[0],pool[i],pool[j],pool[k]]
                        if !accept(four) || four.contains(where: { justOff.contains($0.id) && games[$0.id,default:0] > limit }) { continue }
                        let legal = lastResortSplits(four)
                        if !legal.isEmpty { splits = legal; break outer }
                    }
                }
            }
            note = "fairest available teams"
        }
        guard let splits, !splits.isEmpty else { return nil }
        let split = splits[choice % splits.count]
        return Pairing(format: .doubles, a: split.a, b: split.b, options: splits.count, note: note)

    }

    /// Each player's partners and opponents over their last two doubles games this session.
    func recentPairs(games: Int = 3) -> Recent {
        var out: Recent = [:], seen: [UUID: Int] = [:]
        for r in self.games.reversed() where r.teamA.count == 2 {
            for (mine, theirs) in [(r.teamA, r.teamB), (r.teamB, r.teamA)] {
                for id in mine where seen[id, default: 0] < games {
                    seen[id, default: 0] += 1
                    out[id, default: ([], [])].partners.formUnion(mine.filter { $0 != id })
                    out[id, default: ([], [])].opponents.formUnion(theirs)
                }
            }
        }
        return out
    }

    /// `choice` is the court's shuffle count. Players who haven't played yet have no rest order worth keeping,
    /// so while there are more of them than a game needs, each shuffle draws a whole new random group from them
    /// (still within the skill rules; anyone who has played stays behind them in rest order).
    /// After that, shuffles only cycle the fair options at the front of the line.
    /// Locked teams use the normal queue protections. Unmatchable overdue pairs can play independently.
    func pick(_ format: Format, from line: [Player], choice: Int = 0, allowIdleRelease: Bool = false) -> Pairing? {
        let old = Self.matchupHistory
        Self.matchupHistory = lastTeamOpponents
        defer { Self.matchupHistory = old }
        if let p = pickAvailable(format, from: line, choice: choice) { return p }
        // A small waiting group can exhaust its exact-team opponents; keep every other protection on retry.
        guard format == .doubles, line.count <= Self.rematchFallbackPlayers, line.count == eligible(format).count else { return nil }
        Self.matchupHistory = [:]
        guard var p = pickAvailable(format, from: line, choice: choice) else { return nil }
        p.rematchFallback = true
        p.note = [p.note, "teams repeated to keep the court playing"].compactMap { $0 }.joined(separator: " · ")
        return p
    }
    private func pickAvailable(_ format: Format, from line: [Player], choice: Int = 0, allowIdleRelease: Bool = false, waitForBusyPartner: Bool = true) -> Pairing? {
        guard format == .doubles else { return pickCore(format, from: line, choice: choice) }
        let busy = onCourt, now = Self.now
        let line = line.filter { p in !(waitForBusyPartner && isLocked(p) && busy.contains(p.lock!) && !splitDue(p.id, p.lock!) && now.timeIntervalSince(waitStart(p)) < Self.lockWait) }
        var locks = lockContext(line)
        guard !locks.isEmpty else { return pickCore(format, from: line, choice: choice) }
        for i in locks.indices where !locks[i].apart {
            let l = locks[i]
            if [l.x,l.y].compactMap(player).contains(where: { now.timeIntervalSince(waitStart($0)) >= Self.lockWait }), lockedGame(line,l,locks:locks) == nil { locks[i].apart = true }
        }
        var order: [Player] = []
        for p in line where !order.contains(where: { $0.id == p.id }) {
            order.append(p)
            if let l = locks.first(where: { !$0.apart && ($0.x == p.id || $0.y == p.id) }), let mate = player(l.x == p.id ? l.y : l.x) { order.append(mate) }
        }
        let real = Dictionary(uniqueKeysWithValues: players.map { ($0.id, matchSkill($0.id)) }), protection = lockProtection(line)
        func core(_ candidates: [Player]) -> Pairing? {
            Self.lockCtx = LockCtx(locks: locks, strict: true, real: real, opponents: protection.opponents, rested: protection.rested)
            defer { Self.lockCtx = nil }
            guard let p = pickCore(format, from: candidates, choice: choice),
                  Self.keepsLocks(p.a.map(\.id), p.b.map(\.id), locks, strict: true, real: real, opponents: protection.opponents, rested: protection.rested) else { return nil }
            return lockNotes(p, locks)
        }
        if let p = core(order) { return p }
        // Search the full queue, preserving rest and game-count protections for the opponents too.
        for l in locks where !l.apart {
            if let p = lockedGame(order, l, locks: locks) { return p }
        }
        let held = Set(locks.filter { !$0.apart }.flatMap { [$0.x, $0.y] })
        return core(order.filter { !held.contains($0.id) })
    }

    func lockProtection(_ line: [Player]) -> (opponents: Set<UUID>, rested: Set<UUID>?) {
        let counts = gamesCounted, low = line.map { counts[$0.id, default: 0] }.min() ?? 0
        let off = Set(games.last.map { $0.teamA + $0.teamB } ?? [])
        let limit = Self.recallLimit(line, games: counts, justOff: off)
        return (Set(line.filter { counts[$0.id, default: 0] <= low + Self.lockGameLead && (!off.contains($0.id) || counts[$0.id, default: 0] <= limit) }.map(\.id)), nil)
    }

    /// Opponents within the streak-adjusted locked band from the whole queue; never spend an overplayed player's turn to keep a lock.
    func lockedGame(_ order: [Player], _ l: LockRule, locks: [LockRule]) -> Pairing? {
        guard !l.apart, let x = player(l.x), let y = player(l.y) else { return nil }
        let others = order.filter { $0.id != l.x && $0.id != l.y }, counts = gamesCounted, protection = lockProtection(order)
        let real = Dictionary(uniqueKeysWithValues: players.map { ($0.id, matchSkill($0.id)) }), history = Self.matchupHistory ?? lastTeamOpponents
        let off = Set(games.last.map { $0.teamA + $0.teamB } ?? [])
        var best: (key: [Int], b: [Player])?
        for j in others.indices.dropFirst() {
            for i in 0..<j {
                let a = [x, y], b = [others[i], others[j]]
                guard Self.rematchAllowed(a.map(\.id),b.map(\.id),history:history), Self.keepsLocks(a.map(\.id), b.map(\.id), locks, strict: true, real: real, opponents: protection.opponents, rested: protection.rested) else { continue }
                guard skillRangeAllowed((a+b).map(\.id)) else { continue }
                let gap = unevenness(a.map(\.id), b.map(\.id))
                let spread = (a+b).map { matchSkill($0.id) }; let range = spread.max()! - spread.min()!
                let stage = balancedOnly ? 0 : range <= Self.similarSpread + 1e-9 ? 0 : range <= Self.widerSpread + 1e-9 ? 1 : 2
                let key = [b.map { counts[$0.id, default: 0] }.reduce(0, +), (a+b).filter { off.contains($0.id) }.count, stage, Int((gap * 100).rounded()), i + j]
                if best.map({ key.lexicographicallyPrecedes($0.key) }) ?? true { best = (key, b) }
            }
        }
        return best.map { lockNotes(Pairing(format: .doubles, a: [x, y], b: $0.b), locks) }
    }

    /// Explain temporary releases without claiming that cooldown partners must face each other.
    func lockNotes(_ p: Pairing, _ locks: [LockRule]) -> Pairing {
        let ids = Set((p.a + p.b).map(\.id))
        let notes = locks.filter { $0.apart && (ids.contains($0.x) || ids.contains($0.y)) }.map { l in
            let names = "\(player(l.x)?.name ?? "") & \(player(l.y)?.name ?? "")"
            if splitDue(l.x, l.y) { return names + " cooldown after 3 wins together" }
            return names + " released after 30-minute wait"
        }
        var q = p
        if !notes.isEmpty { q.note = ([p.note].compactMap { $0 } + notes).joined(separator: " · ") }
        return q
    }

    private func pickCore(_ format: Format, from line: [Player], choice: Int = 0) -> Pairing? {
        guard matchingMode == .equalSkill else { return pickCoreHead(format, from: line, choice: choice) }
        for head in line {
            let order = [head] + line.filter { $0.id != head.id }
            if let p = pickCoreHead(format, from: order, choice: choice) { return p }
        }
        return nil
    }

    private func pickCoreHead(_ format: Format, from line: [Player], choice: Int = 0) -> Pairing? {
        // Streaks: matched at the boosted rating; the players handed back carry their real ratings.
        let line = line.map { p in var q = p; q.skill = matchSkill(p.id, format: format); return q }
        // Wait cap: everyone who has waited past it (up to a full court) plays in this game, even if they're behind in line on
        // games played. Fewest games counted first (a late arrival counts at par, so their missed games don't put them ahead), then longest wait.
        // Wait clocks run from the session's first game: time before play starts doesn't make anyone overdue.
        let waited = waitStart, n = gamesCounted
        let overdue: [Player] = []
        let late = Set(overdue.map(\.id))
        let q = line.filter { !late.contains($0.id) }
        let unplayed = q.filter { played($0.id) == 0 }
        let fresh = unplayed.count > format.needed
        var pool = q
        if fresh && choice > 0 {
            var rng = SeededRandom(seed: UInt64(choice * 2 + (format == .singles ? 1 : 0)))
            let ids = Set(unplayed.map(\.id))
            pool = unplayed.shuffled(using: &rng) + q.filter { !ids.contains($0.id) }
        }
        pool = overdue + pool
        let turn = fresh ? 0 : choice
        let off = Set(games.last.map { $0.teamA + $0.teamB } ?? [])
        let recent = format == .doubles ? recentPairs() : [:], must = max(1, overdue.count)
        let balanced = format == .doubles && balancedOnly
        let cap = overdue.isEmpty ? nil : Self.overdueSpread // an overdue game may stretch to 2 levels, balanced, at worst
        // At most 2 late arrivals on their first game in one game, so a wave of arrivals doesn't take over a court.
        let newIDs = Set(line.filter(isNewcomer).map(\.id))
        var limitNew = format == .doubles && newIDs.count > Self.latePerGame
        // Even games: nobody plays while someone with fewer games is left waiting (a late arrival counts at par), so similar-skill
        // groups don't leave anyone 2 games behind.
        var even = format == .doubles
        let finalPool = pool
        let fewNew = { (four: [Player]) -> Bool in
            if matchingMode == .equalSkill {
                let skills = four.map(\.skill)
                if skills.max()! - skills.min()! > Self.similarSpread + 1e-9 { return false }
            }
            if limitNew && four.filter({ newIDs.contains($0.id) }).count > Self.latePerGame { return false }
            guard even else { return true }
            let ids = Set(four.map(\.id))
            guard let low = finalPool.filter({ !ids.contains($0.id) }).map({ n[$0.id] ?? 0 }).min() else { return true }
            return four.allSatisfy { (n[$0.id] ?? 0) <= low }
        }
        func doubles(_ choice: Int) -> Pairing? {
            // Search the whole waiting line while mixing arrivals, so a wave cannot hide the regulars.
            Self.pickDoubles(pool, choice: choice, recent: recent, must: must, justOff: off, accept: fewNew, capSpread: cap,
                             games: n, balancedOnly: balanced, searchLimit: limitNew ? pool.count : 12)
        }
        let singlesPool = matchingMode == .equalSkill ? pool.filter { abs($0.skill - (pool.first?.skill ?? $0.skill)) <= Self.singlesRange + 1e-9 } : pool
        var p = format == .singles ? Self.pickSingles(singlesPool, finishes: results.map(\.end), choice: turn) : doubles(turn)
        if even && (p == nil || abs(p!.a.map(\.skill).reduce(0,+) - p!.b.map(\.skill).reduce(0,+))/2 > Self.fairGap) {
            even = false
            p = doubles(turn) ?? p
        }
        if limitNew && (p == nil || abs(p!.a.map(\.skill).reduce(0,+) - p!.b.map(\.skill).reduce(0,+))/2 > Self.fairGap) {
            limitNew = false
            p = doubles(turn) ?? p
        }
        var forcedHotCold = false
        // Hot/cold teaming: offered first; shuffle then steps through the normal games.
        if format == .doubles {
            let normal = turn == 0 ? p : doubles(0)
            let skills = normal.map { ($0.a + $0.b).map(\.skill) } ?? []
            let range = (skills.max() ?? 0) - (skills.min() ?? 0)
            let stage = normal == nil ? Self.hotColdRange : range <= Self.similarSpread + 1e-9 ? Self.similarSpread : range <= Self.widerSpread + 1e-9 ? Self.widerSpread : Self.hotColdRange
            if let hc = hotColdGame(pool, picked: (normal.map { $0.a + $0.b } ?? []) + pool.prefix(4), overdue: overdue, justOff: off, maxSpread: stage, accept: fewNew) {
                let total = 1 + (normal?.options ?? 0), k = turn % total
                forcedHotCold = k == 0
                p = k == 0 ? hc : doubles(k - 1)
                p?.options = total
            }
        }
        if let game = p, format == .doubles, !forcedHotCold { p = rotateTeams(game, choice: turn) }
        if fresh { p?.options = 99 } // keeps the shuffle button available
        // The note names only the overdue players actually in this game.
        let inGame = overdue.filter { o in Self.now.timeIntervalSince(waited(o)) >= Self.noteAfter && (p.map { ($0.a + $0.b).contains { $0.id == o.id } } ?? false) }
        if !inGame.isEmpty {
            let who = inGame.map(\.name).formatted(.list(type: .and))
            let earlier = p?.note
            p?.note = [earlier, "\(who) waited \(Int(Self.noteAfter / 60))+ min"].compactMap { $0 }.joined(separator: " · ")
        }
        if var g = p { g.a = g.a.map { player($0.id) ?? $0 }; g.b = g.b.map { player($0.id) ?? $0 }; p = g }
        return p
    }

    func rotateTeams(_ p: Pairing, choice: Int) -> Pairing {
        let all = Self.fairSplits(p.a + p.b).filter { t in
            guard abs(t.a.map(\.skill).reduce(0,+) - t.b.map(\.skill).reduce(0,+))/2 <= Self.fairGap + 1e-9 else { return false }
            guard Self.rematchAllowed(t.a.map(\.id),t.b.map(\.id)) else { return false }
            guard let c = Self.lockCtx else { return true }
            return Self.keepsLocks(t.a.map(\.id),t.b.map(\.id),c.locks,strict:true,real:c.real,opponents:c.opponents,rested:c.rested)
        }
        func last(_ team: [Player]) -> Int {
            games.lastIndex { r in [r.teamA,r.teamB].contains { side in team.allSatisfy { side.contains($0.id) } } } ?? -1
        }
        let sorted = all.enumerated().sorted { x,y in
            let a=x.element,b=y.element
            let gapA=abs(a.a.map(\.skill).reduce(0,+)-a.b.map(\.skill).reduce(0,+)),gapB=abs(b.a.map(\.skill).reduce(0,+)-b.b.map(\.skill).reduce(0,+))
            return (max(last(a.a),last(a.b)),gapA,x.offset) < (max(last(b.a),last(b.b)),gapB,y.offset)
        }
        guard !sorted.isEmpty else { return p }
        let t=sorted[choice % sorted.count].element
        var g=p;g.a=t.a;g.b=t.b;g.options=sorted.count;return g
    }

    var activePlayers: Int { players.filter { !$0.paused && $0.away != true }.count } // sitting out and not here don't count
    /// Explicit mixed-skill mode; Auto retains the original skill stages.
    var balancedOnly: Bool { matchingMode == .balancedSkill }

    /// What an open court would start right now: the game Up Next lined up for it.
    func nextPairing(for court: Court) -> Pairing? { openCourtPairings()[court.id] }

    /// Every open court's next game from one run of the matching (`up` defaults to a fresh `upNext`).
    /// Screens and multi-court actions use this once instead of asking court by court.
    func openCourtPairings(_ up: [Pairing]? = nil) -> [UUID: Pairing] {
        let up = up ?? upNext
        let open = courts.filter { $0.match == nil }
        // Tournament: open courts take the ready games in order, whatever the court's own format.
        if tournament != nil { return Dictionary(uniqueKeysWithValues: zip(open.map(\.id), up)) }
        let ids = Set(open.map(\.id))
        var out: [UUID: Pairing] = [:]
        for p in up { if let c = p.court, ids.contains(c), out[c] == nil { out[c] = p } } // already reflects shuffles (see queueUpNext)
        return out
    }

    /// Shuffle button: the next option for an open court's "Next up" game.
    mutating func shuffle(_ courtID: UUID) {
        guard scheduledOnCourt(courtID) == nil else { return }
        guard let i = courts.firstIndex(where: { $0.id == courtID }), courts[i].match == nil, courts[i].manual == nil else { return }
        // One run of the matching, only when there's another open court to pin or a locked side to keep.
        let next = courts[i].locked != nil || courts.contains(where: { $0.id != courtID && $0.match == nil }) ? openCourtPairings() : [:]
        // Keep every other court's next game as it is, so only this court changes.
        let keep = courts.indices.filter { $0 != i && courts[$0].manual == nil && scheduledOnCourt(courts[$0].id) == nil }.compactMap { j in
            next[courts[j].id].map { (j, Match(teamA: $0.a.map(\.id), teamB: $0.b.map(\.id), queueOverride: courts[j].plan?.queueOverride)) }
        }
        for (j, m) in keep { courts[j].plan = m }
        if let side = courts[i].locked, let here = next[courts[i].id] {
            // Locked side stays; the other side steps through fair options from the front of the line, rested players first.
            let kept = (side == 0 ? here.a : here.b).map(\.id), current = Set((side == 0 ? here.b : here.a).map(\.id))
            let busy = Set(kept + keep.flatMap { $0.1.teamA + $0.1.teamB }).union(scheduledLockedPlayers)
            let off = Set(games.last.map { $0.teamA + $0.teamB } ?? [])
            let pool = Array(eligible(courts[i].format).filter { !busy.contains($0.id) }.prefix(8).map(\.id)) // ponytail: front 8 only
            let allSides = kept.count == 1 ? pool.map { [$0] }
                : pool.indices.flatMap { x in pool.indices.filter { $0 > x }.map { [pool[x], pool[$0]] } }
            let sides = allSides.filter { skillRangeAllowed(kept + $0) }
            let fair = sides.filter { isEven(kept, $0) }
            let options = (fair.isEmpty ? sides : fair).enumerated()
                .sorted { ($0.element.filter(off.contains).count, $0.offset) < ($1.element.filter(off.contains).count, $1.offset) }.map(\.element)
            guard !options.isEmpty else { return }
            let other = options[((options.firstIndex { Set($0) == current }) ?? -1).advanced(by: 1) % options.count]
            courts[i].plan = side == 0 ? Match(teamA: kept, teamB: other) : Match(teamA: other, teamB: kept)
            return
        }
        courts[i].plan = nil // back to automatic picks
        courts[i].shuffles = (courts[i].shuffles ?? 0) + 1
    }

    /// Locks one side of an open court's "Next up" game (nil unlocks): those players stay, and shuffle changes only the other side.
    mutating func lock(_ side: Int?, on courtID: UUID) {
        guard scheduledOnCourt(courtID) == nil else { return }
        guard let i = courts.firstIndex(where: { $0.id == courtID }), courts[i].match == nil, courts[i].manual == nil else { return }
        if side != nil, let here = nextPairing(for: courts[i]) { courts[i].plan = Match(teamA: here.a.map(\.id), teamB: here.b.map(\.id)) }
        courts[i].locked = side
    }

    // MARK: Replacing a player in "Next up"

    // MARK: Manual mode

    /// A manual court's slots (team A, then team B), sized to its format, keeping only players still waiting. nil: automatic.
    func manualSlots(_ c: Court) -> [UUID?]? {
        guard tournament == nil, c.match == nil, let m = c.manual else { return nil }
        let waiting = Set(eligible(c.format).map(\.id))
        return (0..<c.format.needed).map { k in k < m.count ? m[k].flatMap { waiting.contains($0) ? $0 : nil } : nil }
    }

    /// Manual mode on (empty slots: the organiser picks every player) or off (back to automatic picks).
    mutating func setManual(_ on: Bool, on courtID: UUID) {
        guard scheduledOnCourt(courtID) == nil else { return }
        guard let i = courts.firstIndex(where: { $0.id == courtID }), courts[i].match == nil else { return }
        courts[i].manual = on ? Array(repeating: nil, count: courts[i].format.needed) : nil
        courts[i].plan = nil; courts[i].locked = nil; courts[i].shuffles = nil
    }

    /// Puts a player in a manual slot (nil empties it); they leave any other manual slot they were in.
    mutating func setSlot(_ slot: Int, to id: UUID?, on courtID: UUID) {
        guard scheduledOnCourt(courtID) == nil, id.map({ !scheduledLockedPlayers.contains($0) }) ?? true else { return }
        guard let i = courts.firstIndex(where: { $0.id == courtID }), manualSlots(courts[i]) != nil else { return }
        if let id { for j in courts.indices { courts[j].manual = courts[j].manual?.map { $0 == id ? nil : $0 } } }
        var m = manualSlots(courts[i])!
        guard m.indices.contains(slot) else { return }
        m[slot] = id
        courts[i].manual = m
    }

    /// A hand-set lineup that still stands: right size, everyone still waiting and able to play this format.
    func validPlan(_ c: Court) -> Match? {
        guard tournament == nil, c.match == nil, let p = c.plan, p.teamA.count + p.teamB.count == c.format.needed else { return nil }
        guard p.queueOverride == true || skillRangeAllowed(p.teamA + p.teamB) else { return nil }
        let waiting = Set(eligible(c.format).map(\.id))
        return (p.teamA + p.teamB).allSatisfy(waiting.contains) && automaticMatchupAllowed(p.teamA,p.teamB) ? p : nil
    }

    /// How uneven a lineup is: rating gap in singles, gap between team averages in doubles.
    func unevenness(_ a: [UUID], _ b: [UUID]) -> Double { abs(averageMatchSkill(a) - averageMatchSkill(b)) }

    /// Matching caps at 5.0; strict mode restores saved ratings when a loss penalty prevents a skill group.
    func matchSkill(_ id: UUID, format: Format = .doubles) -> Double {
        guard let p = player(id) else { return 3 }
        let boost = streakBoost(id), adjusted = min(5, p.skill + boost)
        guard matchingMode == .equalSkill, boost < 0 else { return adjusted }
        // Include players on court so starting a preview cannot change its rating basis.
        let peers = players.filter { $0.id != id && !$0.paused && $0.away != true && ($0.pref == .any || $0.pref.rawValue == format.rawValue) }
        let ratings = (peers.map { min(5, $0.skill + streakBoost($0.id)) } + [adjusted]).sorted()
        if ratings.count >= format.needed {
            for i in 0...(ratings.count - format.needed) {
                let low = ratings[i], high = ratings[i + format.needed - 1]
                if low <= adjusted + 1e-9 && high >= adjusted - 1e-9 && high - low <= Self.similarSpread + 1e-9 { return adjusted }
            }
        }
        return min(5, p.skill)
    }
    func averageMatchSkill(_ ids: [UUID]) -> Double {
        let format: Format = ids.count == 1 ? .singles : .doubles
        let skills = ids.filter { player($0) != nil }.map { matchSkill($0, format: format) }
        return skills.isEmpty ? 3 : skills.reduce(0, +) / Double(skills.count)
    }

    func isEven(_ a: [UUID], _ b: [UUID]) -> Bool {
        unevenness(a, b) <= (a.count == 1 ? Self.singlesRange : Self.fairGap) + 0.001
    }

    /// Doubles teams as given if they're even, otherwise the fairest way to split those four.
    func arranged(_ a: [UUID], _ b: [UUID]) -> (a: [UUID], b: [UUID]) {
        guard a.count == 2, !isEven(a, b) else { return (a, b) }
        let four = players(a + b).map { p in var q = p; q.skill = matchSkill(p.id); return q }
        guard four.count == 4 else { return (a, b) }
        let best = Self.fairSplits(four)[0]
        return (best.a.map(\.id), best.b.map(\.id))
    }

    /// The lineup with `out` swapped for `incoming`, re-split fairly if needed.
    func swapped(_ p: Pairing, _ out: UUID, _ incoming: UUID) -> (a: [UUID], b: [UUID]) {
        let sub = { (ids: [UUID]) in ids.map { $0 == out ? incoming : $0 } }
        return arranged(sub(p.a.map(\.id)), sub(p.b.map(\.id)))
    }

    /// Who could take `out`'s place in this court's next game, longest-rested first, and whether the game stays even.
    /// `from` names the court a candidate is currently lined up for, if any.
    func replacements(for out: UUID, on courtID: UUID) -> [(player: Player, even: Bool, from: String?)] {
        guard let c = courts.first(where: { $0.id == courtID }), let here = nextPairing(for: c) else { return [] }
        let inGame = Set((here.a + here.b).map(\.id))
        var linedUp: [UUID: String] = [:]
        for o in courts where o.id != courtID {
            for p in nextPairing(for: o).map({ $0.a + $0.b }) ?? [] { linedUp[p.id] = o.name }
        }
        return eligible(c.format).filter { !inGame.contains($0.id) && !scheduledLockedPlayers.contains($0.id) }.map { p in
            let l = swapped(here, out, p.id)
            return (p, isEven(l.a, l.b), linedUp[p.id])
        }
    }

    /// What happened to another court when its lined-up player was moved away.
    struct KnockOn {
        var court: String
        var lost: String
        var incoming: String? // nil: nobody free to fill in, that court waits for players
        var even: Bool
    }

    /// Puts `incoming` in `out`'s place on this court's next game. If `incoming` was lined up for another court,
    /// that court gets the longest-rested player who keeps it even (or the least uneven one if nobody does),
    /// and the result is returned so the organiser can accept or undo it.
    mutating func replace(_ out: UUID, with incoming: UUID, on courtID: UUID) -> KnockOn? {
        guard scheduledOnCourt(courtID) == nil, !scheduledLockedPlayers.contains(incoming) else { return nil }
        guard let i = courts.firstIndex(where: { $0.id == courtID }), let here = nextPairing(for: courts[i]) else { return nil }
        let other = courts.first { $0.id != courtID && (nextPairing(for: $0).map { ($0.a + $0.b).contains { $0.id == incoming } } ?? false) }
        let otherLineup = other.flatMap { nextPairing(for: $0) }
        let mine = swapped(here, out, incoming)
        courts[i].plan = Match(teamA: mine.a, teamB: mine.b, queueOverride: true)
        courts[i].shuffles = nil

        guard let o = other, let ol = otherLineup, let j = courts.firstIndex(where: { $0.id == o.id }) else { return nil }
        let busy = Set(mine.a + mine.b + (ol.a + ol.b).map(\.id))
        let options = eligible(o.format).filter { !busy.contains($0.id) }.map { p in (p, swapped(ol, incoming, p.id)) }
        let lost = player(incoming)?.name ?? ""
        guard let pick = options.first(where: { isEven($0.1.a, $0.1.b) })
                ?? options.min(by: { unevenness($0.1.a, $0.1.b) < unevenness($1.1.a, $1.1.b) }) else {
            courts[j].plan = nil
            return KnockOn(court: o.name, lost: lost, incoming: nil, even: false)
        }
        courts[j].plan = Match(teamA: pick.1.a, teamB: pick.1.b, queueOverride: true)
        courts[j].shuffles = nil
        return KnockOn(court: o.name, lost: lost, incoming: pick.0.name, even: isEven(pick.1.a, pick.1.b))
    }

    /// Takes a started game off court as if it never began: nothing is recorded and, since starting a game
    /// doesn't touch anyone's place in line, the players are back exactly where they were.
    mutating func undoStart(_ courtID: UUID) {
        if let i = courts.firstIndex(where: { $0.id == courtID }) { courts[i].match = nil }
    }

    /// Who plays next in each format this session has courts for, nobody booked twice.
    /// Formats with an open court go first (they can start now), then whoever has waited longest.
    // ponytail: guesses order among busy courts by wait time; the real order depends on which game finishes first
    var upNext: [Pairing] { tournament == nil ? queueUpNext : tournamentUpNext }

    var queueUpNext: [Pairing] {
        // Every open court gets a game; the format whose next player is furthest up the line picks first.
        let line = queue.map(\.id)
        let lines = Dictionary(uniqueKeysWithValues: Format.allCases.map { ($0, eligible($0)) }) // once, not per court or comparison
        let ranks = lines.mapValues { $0.first.flatMap { line.firstIndex(of: $0.id) } ?? .max }
        func rank(_ f: Format) -> Int { ranks[f]! }
        let open = courts.enumerated().filter { $0.element.match == nil }
            .sorted { (rank($0.element.format), $0.offset) < (rank($1.element.format), $1.offset) }
            .map(\.element)
        // Hand-set lineups and players chosen for manual courts come first; they're off limits to the automatic picks.
        var taken = Set(open.compactMap(validPlan).flatMap { $0.teamA + $0.teamB } + open.flatMap { manualSlots($0)?.compactMap { $0 } ?? [] })
        var booked = taken
        let reservation = scheduledReservation
        let reserved = Set(reservation.map { $0.teamA + $0.teamB } ?? [])
        var borrowed = reservation?.idleReleased == true
        let scheduledCourt = reservation.flatMap { r in reserved.isDisjoint(with: onCourt.union(taken)) ? open.first { $0.format == r.format && $0.manual == nil && validPlan($0) == nil && (r.assignedCourt == nil || $0.id == r.assignedCourt) } : nil }
        taken.formUnion(reserved)
        var out: [Pairing] = open.compactMap { c in
            if let m = manualSlots(c) { // manual: the chosen lineup once every slot is filled, never shuffled
                let ids = m.compactMap { $0 }
                guard ids.count == m.count else { return nil }
                return Pairing(format: c.format, a: players(Array(ids[..<(ids.count / 2)])), b: players(Array(ids[(ids.count / 2)...])), court: c.id)
            }
            if let plan = validPlan(c) {
                return Pairing(format: c.format, a: players(plan.teamA), b: players(plan.teamB), court: c.id, options: 2) // shuffle returns to automatic
            }
            if let r = reservation, c.id == scheduledCourt?.id {
                return Pairing(format: c.format, a: players(r.teamA), b: players(r.teamB), court: c.id, scheduled: r.id, note: "Scheduled")
            }
            var candidate = pick(c.format, from: lines[c.format]!.filter { !taken.contains($0.id) }, choice: c.shuffles ?? 0, allowIdleRelease: true)
            if candidate == nil, reservation != nil, scheduledCourt == nil, !borrowed {
                candidate = pick(c.format, from: lines[c.format]!.filter { !booked.contains($0.id) }, choice: c.shuffles ?? 0, allowIdleRelease: true)
                if var p = candidate { borrowed = true; p.note = ([p.note].compactMap { $0 } + ["scheduled hold relaxed to avoid an idle court"]).joined(separator: " · "); candidate = p }
            }
            guard var p = candidate else { return nil }
            p.court = c.id
            (p.a + p.b).forEach { taken.insert($0.id); booked.insert($0.id) }
            return p
        }
        // Busy courts: who's next there once the current game ends, earliest-started court first.
        // ponytail: a guess from who's waiting now; the players coming off other courts can change it
        for c in courts.filter({ $0.match != nil }).sorted(by: { $0.match!.start < $1.match!.start }) {
            guard var p = pick(c.format, from: lines[c.format]!.filter { !taken.contains($0.id) }, choice: 0) else { continue }
            p.court = c.id
            (p.a + p.b).forEach { taken.insert($0.id) }
            out.append(p)
        }
        return out
    }

    // MARK: Queue

    var onCourt: Set<UUID> {
        Set(courts.flatMap { ($0.match?.teamA ?? []) + ($0.match?.teamB ?? []) })
    }

    /// Everyone here and off court: anyone moved to the front, then the four who just came off behind everyone rested
    /// (so nobody behind on games goes straight back on court), then fewest games played, then longest rested.
    var queue: [Player] {
        let busy = onCourt
        let n = gamesCounted
        let off = Set(games.last.map { $0.teamA + $0.teamB } ?? [])
        let key = { (p: Player) in (p.first == true ? 0 : 1, off.contains(p.id) ? 1 : 0, n[p.id] ?? 0, p.readyAt) }
        return players.filter { !busy.contains($0.id) && $0.away != true }.sorted { key($0) < key($1) }
    }

    /// Games played plus any arrival credit: what "fewest games first" compares.
    var scheduledPenalties: [UUID: Int] {
        var n: [UUID: Int] = [:]
        for r in games {
            for id in r.teamA + r.teamB {
                if r.scheduled != nil && (r.jumpers ?? []).contains(id) { n[id] = 2 }
                else if r.scheduled == nil { n[id] = max(0, n[id, default: 0] - 1) }
            }
        }
        return n
    }
    func scheduledJumpers(_ ids: [UUID]) -> [UUID] {
        let ready = scheduledReservation?.readyJumpers ?? []
        return ids.filter { ready.contains($0) }
    }
    func scheduledNeedsOrdinary(_ id: UUID) -> Bool {
        let last = games.last { ($0.teamA + $0.teamB).contains(id) }
        return last?.scheduled != nil && scheduledPenalties[id, default: 0] > 0
    }

    var gamesCounted: [UUID: Int] {
        var n = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.credit ?? 0) })
        for r in games { for id in r.teamA + r.teamB where n[id] != nil { n[id]! += 1 } }
        for (id, penalty) in scheduledPenalties where n[id] != nil { n[id]! += penalty }
        return n
    }

    func eligible(_ format: Format) -> [Player] {
        queue.filter { !$0.paused && ($0.pref == .any || $0.pref.rawValue == format.rawValue) }
    }

    func player(_ id: UUID) -> Player? { players.first { $0.id == id } }

    // MARK: Stats

    func played(_ id: UUID) -> Int { games.filter { ($0.teamA + $0.teamB).contains(id) }.count }

    func wins(_ id: UUID) -> Int {
        results.filter { r in r.winner.map { ($0 == 0 ? r.teamA : r.teamB).contains(id) } ?? false }.count
    }

    // MARK: Actions

    mutating func update(_ id: UUID, _ change: (inout Player) -> Void) {
        if let i = players.firstIndex(where: { $0.id == id }) { change(&players[i]) }
    }

    /// Start: begins `shown` (the game the screen drew for this court) while all four are still free, so the lineup never
    /// changes on Start. The screen redraws only on a change, but who's overdue moves with the clock. Otherwise Up Next now.
    mutating func fill(_ courtID: UUID, shown: Pairing? = nil, at now: Date = Date()) {
        guard let i = courts.firstIndex(where: { $0.id == courtID }), courts[i].match == nil else { return }
        refreshSchedule()
        guard isLive else { return }
        let free = Set(queue.map(\.id))
        guard let p = shown.flatMap({ g in (g.a + g.b).allSatisfy { free.contains($0.id) } ? g : nil }) ?? nextPairing(for: courts[i]) else { return }
        if tournament == nil, p.scheduled == nil, courts[i].manual == nil, courts[i].plan?.queueOverride != true, !skillRangeAllowed((p.a+p.b).map(\.id)) { return }
        if tournament == nil, p.scheduled == nil, courts[i].manual == nil, !automaticMatchupAllowed(p.a.map(\.id),p.b.map(\.id)) { courts[i].plan = nil; courts[i].shuffles = nil; return }
        if let assigned = scheduledOnCourt(courtID), assigned.id != p.scheduled { return }
        if let id = p.scheduled {
            guard let current = queueUpNext.first(where: { $0.court == courtID && $0.scheduled == id }), current.a.map(\.id) == p.a.map(\.id), current.b.map(\.id) == p.b.map(\.id) else { return }
        } else if let r = scheduledReservation, (p.a + p.b).contains(where: { (r.teamA + r.teamB).contains($0.id) }) {
            guard let allowed = queueUpNext.first(where: { $0.court == courtID && $0.scheduled == nil }), allowed.a.map(\.id) == p.a.map(\.id), allowed.b.map(\.id) == p.b.map(\.id) else { return }
        }
        if p.scheduled == nil, let held = scheduledReservation, (p.a + p.b).contains(where: { (held.teamA + held.teamB).contains($0.id) }), let ri = scheduled?.firstIndex(where: { $0.id == held.id }) { scheduled![ri].idleReleased = true }
        courts[i].match = Match(teamA: p.a.map(\.id), teamB: p.b.map(\.id), start: now, scheduled: p.scheduled, jumpers: p.scheduled == nil ? nil : scheduledJumpers((p.a + p.b).map(\.id)), tournamentMatch: p.match)
        courts[i].shuffles = nil
        courts[i].plan = nil
        courts[i].locked = nil
        refreshSchedule()
    }

    mutating func fillAll(shown: [UUID: Pairing] = [:]) { courts.map(\.id).forEach { fill($0, shown: shown[$0]) } }

    /// End Session: games still on court are cancelled, then the session is marked ended.
    mutating func end(at now: Date = Date()) {
        for c in courts where c.match != nil { finish(c.id, winner: nil, at: now) }
        ended = now
        normalizeEnd(); refreshSchedule()
    }

    mutating func reopen() { ended = nil }

    /// All Players edits: renames and re-rates this person (matched by name, ignoring case) in every session but `except`.
    /// `skill` nil keeps their ratings. Games already played keep the rating changes they recorded.
    static func editEverywhere(name old: String, to new: String, skill: Double? = nil, in sessions: inout [SessionState], except: UUID? = nil) {
        for i in sessions.indices where sessions[i].id != except {
            for j in sessions[i].players.indices where sessions[i].players[j].name.lowercased() == old.lowercased() {
                sessions[i].players[j].name = new
                if let skill { sessions[i].players[j].skill = skill }
            }
        }
    }

    /// Ends the game on a court. With a winner (0 = team A, 1 = team B), moves both teams' ratings. Without one the game is
    /// cancelled: it's kept in the history, but like Undo Start the players are back exactly where they were in line.
    mutating func finish(_ courtID: UUID, winner: Int?, at now: Date = Date()) {
        guard let i = courts.firstIndex(where: { $0.id == courtID }), let m = courts[i].match else { return }
        var r = GameResult(teamA: m.teamA, teamB: m.teamB, winner: winner, court: courts[i].name, start: m.start, end: now)
        if let tm = m.tournamentMatch, let t = tournament {
            r.tournamentLabel = t.matches[tm].label
            if let winner { recordTournament(tm, winner: winner) } // "No result" leaves the game to be replayed
        }
        if let winner {
            // A win is a win: game length isn't counted (games to 11 and to 21 last very different times).
            let d = Self.ratingChange(teamA: averageSkill(m.teamA), teamB: averageSkill(m.teamB), aWon: winner == 0)
            r.changes = adjust(m.teamA, by: d).merging(adjust(m.teamB, by: -d)) { $1 }
        }
        r.scheduled = m.scheduled; r.jumpers = m.jumpers
        results.append(r)
        for (n, id) in (m.teamA + m.teamB).enumerated() where winner != nil {
            update(id) { $0.readyAt = now.addingTimeInterval(Double(n) * 0.001); $0.first = nil; $0.since = now }
        }
        courts[i].match = nil
        refreshSchedule()
        if winner != nil { courts[i].manual = nil } // a finished game ends manual mode; a cancelled one keeps the lineup, like Undo Start
    }

    /// Removes a game entered by mistake and undoes its rating change.
    mutating func deleteResult(at i: Int) {
        for (id, c) in results.remove(at: i).changes ?? [:] { update(id) { $0.skill -= c } }
        normalizeEnd(); refreshSchedule()
    }

    /// Corrects a finished game's result (0 = team A won, 1 = team B, nil = cancelled): undoes the rating change it made,
    /// then applies the corrected one, worked out as when a game finishes. Places in line aren't touched.
    mutating func setWinner(_ i: Int, _ winner: Int?) {
        guard results.indices.contains(i), results[i].winner != winner else { return }
        for (id, c) in results[i].changes ?? [:] { update(id) { $0.skill -= c } }
        results[i].changes = nil
        results[i].winner = winner
        normalizeEnd()
        guard let winner else { return }
        let r = results[i]
        let d = Self.ratingChange(teamA: averageSkill(r.teamA), teamB: averageSkill(r.teamB), aWon: winner == 0)
        results[i].changes = adjust(r.teamA, by: d).merging(adjust(r.teamB, by: -d)) { $1 }
    }

    // ponytail: 75% of the median games played; tune if late arrivals or early leavers are still ranked (or too many aren't)
    static let rankShare = 0.75
    /// Standings rank only players with at least this many games: 75% of the session's typical night (the median among
    /// those who played), so someone who played a few games and left can't top the table.
    var rankingMinimum: Int {
        let n = players.map { played($0.id) }.filter { $0 > 0 }.sorted()
        return n.isEmpty ? 1 : max(1, Int((Double(n[n.count / 2]) * Self.rankShare).rounded(.up)))
    }

    // MARK: Ratings

    // ponytail: Elo on the 1–5 scale, win/loss only. ratingK = most one game can move a rating; ratingSpread = the level gap
    // at which the stronger side is expected to win ~90%. Tune these two if ratings move too fast or too slow.
    static let ratingK = 0.3
    static let ratingSpread = 2.0
    // ponytail: how fast ratings settle (chosen by simulation): a new player's first `newGames` games move `newK` times as much,
    // a regular's `regK` times
    static let newGames = 8, newK = 1.5, regK = 0.75
    // Streaks (matching only): 3 wins in a row counts as 0.5 higher, each further win 0.5 more, at most 1.5; losses the same, lower.
    static let streakLength = 3, streakStart = 0.5, streakStep = 0.5, streakMax = 1.5
    // ponytail: hot/cold teaming, chosen by simulation: partners within 1.0 level, teams within 0.25, all four within 2 levels
    static let hotColdGap = 1.0, hotColdSlack = 0.25, hotColdRange = 2.0
    static let lateFirst = 4, latePerGame = 2 // late arrivals go first while fewer than 4 are waiting; at most 2 in a game
    static let noteAfter: TimeInterval = 25 * 60 // the court names someone overdue only once they've waited this long
    static let lateAfter: TimeInterval = 30 * 60 // arrivals in the first 30 minutes after the first game count as on time (no credit)
    static let lockWait: TimeInterval = 30 * 60
    static let lockLower = 0.5, lockHigher = 1.25
    static let lockEqual = 0.5 // locked teammates: opponents' average at least the pair's (within display rounding)
    // ponytail: chosen by simulation: similar-skill groups from 6.25 players per doubles court (13 for 2 courts, 19 for 3, 25 for 4);
    // fewer, balanced teams. evenRepeat: an even-games pick that repeats this much (all four met lately) gives way.
    static let balancedBelow = 6.25, evenRepeat = 6

    /// How much one game moves a rating: more over a new player's first games, less for regulars (anyone without a count).
    func kFactor(_ id: UUID) -> Double {
        guard let r = player(id)?.rated, r + played(id) < Self.newGames else { return Self.regK }
        return Self.newK
    }

    /// Matching only: +0.5 on 3 wins in a row, +0.5 more per further win, at most +1.5; losses the same, negative. A cancelled
    /// game doesn't count. Ratings don't change.
    func streakBoost(_ id: UUID) -> Double {
        var run = 0, sign = 0
        for r in games.reversed() where r.teamA.contains(id) || r.teamB.contains(id) {
            guard let w = r.winner else { continue }
            let s = (w == 0 ? r.teamA : r.teamB).contains(id) ? 1 : -1
            if sign != 0 && s != sign { break }
            sign = s; run += 1
        }
        return run >= Self.streakLength ? Double(sign) * min(Self.streakMax, Self.streakStart + Self.streakStep * Double(run - Self.streakLength)) : 0
    }

    /// Hot/cold teaming: when someone on a win streak (or losing streak) is about to play and someone on the opposite streak within
    /// 1.0 level is resting near the front (first 8, then 12), they're teammates, against even opponents (teams within 0.25, all four
    /// within 2 levels). The first in line still plays and nobody is called straight back. No court note.
    func hotColdGame(_ pool: [Player], picked: [Player], overdue: [Player], justOff: Set<UUID>, maxSpread: Double = Self.hotColdRange, accept: ([Player]) -> Bool = { _ in true }) -> Pairing? {
        guard overdue.count <= 2 else { return nil }
        let n = gamesCounted
        func sign(_ id: UUID) -> Int { let b = streakBoost(id); return b > 0 ? 1 : b < 0 ? -1 : 0 }
        func real(_ p: Player) -> Double { p.skill } // the line carries ratings with streak boosts
        for depth in [8, 12] {
            let near = Array(pool.prefix(depth))
            for x in picked {
                let sx = sign(x.id)
                guard sx != 0, !justOff.contains(x.id) else { continue }
                let ys = near.enumerated()
                    .filter { $0.element.id != x.id && sign($0.element.id) == -sx && !justOff.contains($0.element.id) && abs(real($0.element) - real(x)) <= Self.hotColdGap + 1e-9 }
                    .sorted { (abs(real($0.element) - real(x)), $0.offset) < (abs(real($1.element) - real(x)), $1.offset) }.map(\.element)
                for y in ys {
                    var front = overdue
                    for p in Array(pool.prefix(1)) + [x, y] where !front.contains(where: { $0.id == p.id }) { front.append(p) }
                    guard front.count <= 4 else { continue }
                    let ids = Set(front.map(\.id))
                    let ok = { (four: [Player]) -> Bool in
                        let others = four.filter { $0.id != x.id && $0.id != y.id }.map(\.skill).reduce(0, +), sk = four.map(real)
                        return accept(four) && abs(x.skill + y.skill - others) / 2 <= Self.hotColdSlack + 1e-9 && !four.contains { justOff.contains($0.id) }
                            && sk.max()! - sk.min()! <= maxSpread + 1e-9
                    }
                    if var g = Self.pickDoubles(front + near.filter { !ids.contains($0.id) }, choice: 0, recent: recentPairs(), must: front.count, justOff: justOff,
                                                together: [x.id, y.id], accept: ok, games: n) {
                        g.note = nil
                        return g
                    }
                }
            }
        }
        return nil
    }

    /// A late arrival who hasn't played since arriving.
    func isNewcomer(_ p: Player) -> Bool {
        guard played(p.id) == 0 else { return false }
        guard let arrival = p.since, let start = started else { return (p.credit ?? 0) > 0 }
        return arrival.timeIntervalSince(start) >= Self.lateAfter
    }

    /// Rating change for each team A player (team B gets the negative). Winners always gain;
    /// beating a stronger side moves ratings more than beating a weaker one.
    static func ratingChange(teamA: Double, teamB: Double, aWon: Bool) -> Double {
        let expectedA = 1 / (1 + pow(10, (teamB - teamA) / ratingSpread))
        return ratingK * ((aWon ? 1 : 0) - expectedA)
    }

    /// Standings score, 0–100: the win rate with two extra wins and two extra losses, so one or two lucky games can't top
    /// the table. Game length doesn't count. Equal records score exactly the same, a draw. A cancelled game doesn't count.
    func score(_ id: UUID) -> Double {
        let mine = games.filter { ($0.teamA + $0.teamB).contains(id) }
        let won = mine.filter { ($0.winner == 0 ? $0.teamA : $0.teamB).contains(id) }.count
        return Double(won + 2) / Double(mine.count + 4) * 100
    }

    func averageSkill(_ ids: [UUID]) -> Double {
        let skills = ids.compactMap { player($0)?.skill }
        return skills.isEmpty ? 3 : skills.reduce(0, +) / Double(skills.count)
    }

    /// Moves ratings within 1–5 and returns what each player actually moved.
    mutating func adjust(_ ids: [UUID], by d: Double) -> [UUID: Double] {
        var applied: [UUID: Double] = [:]
        for id in ids {
            let k = kFactor(id)
            update(id) { p in
                let old = p.skill
                p.skill = min(5, max(1, old + d * k))
                applied[id] = p.skill - old
            }
        }
        return applied
    }

    // MARK: Locked teammates
    // A lock preserves the team only while rating, rest and game-count protections allow it.
    // Overdue unmatchable pairs and three-win cooldown partners can be selected independently.

    struct LockRule { var x: UUID, y: UUID, apart: Bool; var idle = false; var blockedTeams: [Set<UUID>] = [] }
    struct LockCtx { var locks: [LockRule], strict: Bool, real: [UUID: Double]; var opponents: Set<UUID>? = nil; var rested: Set<UUID>? = nil }
    static var lockCtx: LockCtx? // during a doubles pick, read by bestFour and the overdue rule

    /// Every locked pair (two-way), once.
    var lockedPairs: [(UUID, UUID)] {
        players.compactMap { p in
            guard let q = p.lock, player(q)?.lock == p.id, p.id.uuidString < q.uuidString else { return nil }
            return (p.id, q)
        }
    }
    func isLocked(_ p: Player) -> Bool { p.lock.flatMap(player)?.lock == p.id }

    /// Wins in a row the pair has as teammates, counted back from their latest game.
    func lockStreak(_ x: UUID, _ y: UUID) -> Int {
        var n = 0
        for r in games.reversed() where (r.teamA + r.teamB).contains(x) {
            let team = r.teamA.contains(x) ? r.teamA : r.teamB
            guard team.contains(y), (r.winner == 0 ? r.teamA : r.teamB) == team else { break }
            n += 1
        }
        return n
    }
    func splitDue(_ x: UUID, _ y: UUID) -> Bool { max(lockStreak(x, y), lockStreak(y, x)) >= Self.streakLength }

    /// Sets (or clears, with nil) a lock, ending any lock either player had.
    mutating func setLock(_ id: UUID, _ other: UUID?) {
        for i in players.indices where [id, other].contains(players[i].id) || (players[i].lock != nil && [id, other].contains(players[i].lock)) {
            players[i].lock = nil
        }
        if let other, player(id) != nil, player(other) != nil {
            update(id) { $0.lock = other }; update(other) { $0.lock = id }
        }
    }

    /// The locked pairs with both partners in this line, each with whoever is first in line as `x` (same order as the web version).
    func lockedRematchBlocked(_ a: [UUID], _ b: [UUID]) -> Bool {
        let history = games, own = Set(a), opp = Set(b)
        guard let last = history.lastIndex(where: { r in
            (Set(r.teamA) == own && Set(r.teamB) == opp) || (Set(r.teamA) == opp && Set(r.teamB) == own)
        }) else { return false }
        let later = history.dropFirst(last + 1)
        return (a + b).contains { id in later.filter { ($0.teamA + $0.teamB).contains(id) }.count < Self.lockRematchGames }
    }

    func lockContext(_ line: [Player]) -> [LockRule] {
        let at = { (id: UUID) in line.firstIndex { $0.id == id } }
        return lockedPairs.compactMap { x, y in
            guard let ix = at(x), let iy = at(y) else { return nil }
            var rule = ix <= iy ? LockRule(x: x, y: y, apart: splitDue(x, y)) : LockRule(x: y, y: x, apart: splitDue(x, y))
            rule.blockedTeams = lockedPairs.compactMap { u, v in
                guard u != x && u != y && lockedRematchBlocked([x,y],[u,v]) else { return nil }
                return Set([u,v])
            }
            return rule
        }.sorted { at($0.x)! < at($1.x)! }
    }

    /// Both partners of a normal lock in the game, or neither; cooldown partners are selected independently.
    static func lockMembers(_ ids: [UUID], _ locks: [LockRule]) -> Bool { locks.allSatisfy { $0.apart || ids.contains($0.x) == ids.contains($0.y) } }

    /// A lineup keeps the locks: together, or individually during a cooldown (never as teammates), and when strict
    /// against a team within the locked band, using streak-adjusted ratings for both sides.
    static func keepsLocks(_ a: [UUID], _ b: [UUID], _ locks: [LockRule], strict: Bool, real: [UUID: Double], opponents: Set<UUID>? = nil, rested: Set<UUID>? = nil) -> Bool {
        let avg = { (t: [UUID]) in t.map { real[$0] ?? 3 }.reduce(0, +) / Double(max(1, t.count)) }
        if let rested, !(a + b).allSatisfy(rested.contains) { return false }
        for l in locks {
            let inA = [l.x, l.y].filter(a.contains).count, inB = [l.x, l.y].filter(b.contains).count
            if inA == 0 && inB == 0 { continue }
            if !l.apart && (inA + inB == 1 || inA == 1) { return false }
            if l.apart && (inA == 2 || inB == 2) { return false }
            if !l.apart {
                let (own, opp) = inA > 0 ? (a, b) : (b, a)
                if l.blockedTeams.contains(Set(opp)) { return false }
                if let opponents, !(own + opp).allSatisfy(opponents.contains) { return false }
                if strict && (avg(opp) < avg(own) - lockLower - 1e-9 || avg(opp) > avg(own) + lockHigher + 1e-9) { return false }
            }
        }
        return true
    }

    mutating func moveToFront(_ id: UUID) {
        let first = players.map(\.readyAt).min() ?? Date()
        update(id) { $0.readyAt = first.addingTimeInterval(-1); $0.first = true }
    }

    mutating func addCourt() {
        let n = (courts.compactMap { Int($0.name.filter(\.isNumber)) }.max() ?? 0) + 1
        courts.append(Court(name: "Court \(n)", format: .doubles))
    }

    /// People from earlier sessions who aren't in this one, matched by name, carrying their most recent rating.
    func returningPlayers(from past: [SessionState]) -> [Player] {
        let here = Set(players.map { $0.name.lowercased() })
        var latest: [String: Player] = [:]
        for session in past.sorted(by: { $0.date < $1.date }) {
            for p in session.players { var q = p; q.rated = p.rated.map { $0 + session.played(p.id) }; latest[p.name.lowercased()] = q }
        }
        return latest.filter { !here.contains($0.key) }.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Everyone ever registered, one row per person (matched by name, ignoring case), with their latest rating.
    struct Registered: Identifiable {
        var id: String { name.lowercased() }
        var name: String, skill: Double, sessions: Int, played: Int, won: Int, lastSeen: Date
    }

    static func registry(_ sessions: [SessionState]) -> [Registered] {
        var out: [String: Registered] = [:]
        for s in sessions.sorted(by: { $0.date < $1.date }) {
            for p in s.players {
                var r = out[p.name.lowercased()] ?? Registered(name: p.name, skill: p.skill, sessions: 0, played: 0, won: 0, lastSeen: s.date)
                r.name = p.name; r.skill = p.skill; r.lastSeen = s.date
                r.sessions += 1; r.played += s.played(p.id); r.won += s.wins(p.id)
                out[p.name.lowercased()] = r
            }
        }
        return out.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Adds returning players to the back of the queue, in the order given, with fresh stats.
    mutating func addReturning(_ returning: [Player]) {
        for p in returning { addPlayer(p.name, skill: p.skill, rated: p.rated) }
    }

    /// Adds someone who just arrived. They haven't played, so they go ahead of everyone waiting who has,
    /// but behind anyone who's been waiting since before them without a game yet.
    /// A newcomer goes just ahead of everyone who has played, once. They're counted as having played as many games as the
    /// least-played player who has played, so after their first game they're in the normal order instead of catching up.
    /// Before the first game, everyone added starts as not here yet; they're marked present as they arrive.
    /// `rated`: rated games before this session (0 for a new player, nil for a regular from before this was counted).
    mutating func addPlayer(_ name: String, skill: Double, rated: Int? = 0) {
        let p = Player(name: name, skill: skill, away: true, rated: rated)
        if players.isEmpty && results.isEmpty { date = Date() } // an empty session made at the end of last night is tonight's
        players.append(p)
        if !results.isEmpty || !onCourt.isEmpty { arrive(p.id) }
    }

    /// Marks someone present. They join the line like a late arrival: after anyone yet to play, counted at par
    /// (never below the games they've played), with their wait clock starting now.
    mutating func arrive(_ id: UUID) {
        guard let p = player(id), p.away == true else { return }
        let n = gamesCounted
        let par = players.filter { !$0.paused && $0.away != true && played($0.id) > 0 }.compactMap { n[$0.id] }.min() ?? 0
        // Once 4 late arrivals are already waiting for their first game, later ones join at par in arrival order instead of going first.
        let first = queue.filter(isNewcomer).count < Self.lateFirst
        // In the first 30 minutes after the first game an arrival counts as on time: no credit, so they're up next like anyone yet to play.
        let onTime = started.map { Self.now.timeIntervalSince($0) < Self.lateAfter } ?? true
        let at = first ? arrivalTime() : Self.now, credit = onTime ? 0 : max(p.credit ?? 0, par - played(id))
        update(id) { $0.away = nil; $0.readyAt = at; $0.since = Self.now; $0.credit = credit > 0 ? credit : nil }
    }

    /// The spot in line for a newcomer: just before the first waiting player who has already played.
    func arrivalTime() -> Date {
        let q = queue
        guard let pos = q.firstIndex(where: { played($0.id) > 0 }) else { return Self.now } // nobody waiting has played: back of the line
        let after = q[pos].readyAt.timeIntervalSinceReferenceDate
        // Just after the latest earlier arrival still ahead of them; 0-game players ahead may have later times.
        let before = q[..<pos].map(\.readyAt.timeIntervalSinceReferenceDate).filter { $0 < after }.max() ?? after - 2
        return Date(timeIntervalSinceReferenceDate: (before + after) / 2)
    }

    /// A fresh session with the same courts, optionally the same players (stats reset, everyone back to "any").
    func next(keepPlayers: Bool) -> SessionState {
        let now = Date(), ids = Dictionary(uniqueKeysWithValues: players.map { ($0.id, UUID()) })
        return SessionState(
            // marked present as they arrive; locked teammates carry over
            players: keepPlayers ? players.enumerated().map { n, p in
                Player(id: ids[p.id]!, name: p.name, skill: p.skill, readyAt: now.addingTimeInterval(Double(n) * 0.001),
                       away: true, rated: p.rated.map { $0 + played(p.id) }, lock: p.lock.flatMap { ids[$0] })
            } : [],
            courts: courts.map { Court(name: $0.name, format: $0.format) },
            queueMatching: queueMatching
        )
    }

    #if DEBUG
    static func queueMatchingSelfCheck() {
        func fixture(_ skills: [Double]) -> SessionState {
            SessionState(players: skills.enumerated().map { Player(name: "M\($0.offset)", skill: $0.element, readyAt: now.addingTimeInterval(Double($0.offset))) }, courts: [Court(name: "C1", format: .doubles), Court(name: "C2", format: .doubles)])
        }
        var capped = fixture([5, 4, 4, 4]); capped.setQueueMatching(.equalSkill)
        for _ in 0..<3 {
            capped.results.append(GameResult(teamA: [capped.players[0].id], teamB: [UUID()], winner: 0, court: "C1", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-60)))
        }
        assert(capped.streakBoost(capped.players[0].id) == 0.5 && capped.matchSkill(capped.players[0].id) == 5, "winning streaks cannot push matching above 5.0")
        assert(capped.skillRangeAllowed(capped.players.map(\.id)) && capped.pick(.doubles, from: capped.players) != nil, "a capped 5.0 player can match three 4.0 players")
        assert(capped.players[0].skill == 5, "matching cap leaves saved ratings unchanged")
        var cold = fixture([2.5, 3, 3, 3]); cold.setQueueMatching(.equalSkill)
        for _ in 0..<4 {
            cold.results.append(GameResult(teamA: [cold.players[0].id], teamB: [UUID()], winner: 1, court: "C1", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-60)))
        }
        let coldID = cold.players[0].id
        assert(cold.streakBoost(coldID) == -1 && cold.matchSkill(coldID) == 2.5, "an isolated losing player uses their saved rating in strict mode")
        assert(cold.pick(.doubles, from: cold.eligible(.doubles)) != nil && cold.skillRangeAllowed(cold.players.map(\.id)))
        cold.setQueueMatching(.auto)
        assert(cold.matchSkill(coldID) == 1.5, "Auto retains the losing-streak penalty")
        cold.setQueueMatching(.balancedSkill)
        assert(cold.matchSkill(coldID) == 1.5, "Balanced retains the losing-streak penalty")
        cold.setQueueMatching(.equalSkill)
        for (i, rating) in [1.8, 2.0, 2.2].enumerated() { cold.players[i+1].skill = rating }
        assert(cold.matchSkill(coldID) == 1.5, "keep a penalty that still permits a strict group")
        cold.players = Array(cold.players.prefix(2)); cold.players[1].skill = 3
        assert(cold.matchSkill(coldID, format: .singles) == 2.5 && cold.pick(.singles, from: cold.eligible(.singles)) != nil, "singles uses the same fallback")
        assert(cold.players[0].skill == 2.5 && cold.streakBoost(coldID) == -1, "fallback changes neither saved rating nor streak history")
        var s = fixture([2, 2, 3, 3])
        assert(s.matchingMode == .auto)
        let old = s.pick(.doubles, from: s.players)!
        s.queueMatching = .auto
        assert(s.pick(.doubles, from: s.players)!.a.map(\.id) == old.a.map(\.id))
        s.setQueueMatching(.equalSkill)
        assert(s.pick(.doubles, from: s.players) != nil, "strict boundary includes 1.0")
        s.players[3].skill = 3.01
        assert(s.pick(.doubles, from: s.players) == nil, "no fallback widens strict range")
        s.setQueueMatching(.balancedSkill)
        assert(s.pick(.doubles, from: s.players) != nil)
        s = fixture([1, 3, 3, 3, 3]); s.setQueueMatching(.equalSkill)
        let p = s.pick(.doubles, from: s.players)!
        assert(!(p.a+p.b).contains { $0.id == s.players[0].id }, "try later heads")
        assert(s.pick(.singles, from: Array(s.players.prefix(2))) == nil)
        for k in 0..<8 {
            let g = s.pick(.doubles, from: s.players, choice: k)!
            assert(s.skillRangeAllowed((g.a+g.b).map(\.id)))
        }
        s = fixture(Array(repeating: 3, count: 8)); s.setQueueMatching(.equalSkill)
        let up = s.queueUpNext
        assert(up.count == 2 && Set(up.flatMap { ($0.a+$0.b).map(\.id) }).count == 8)
        let c = s.courts[0].id, shown = s.nextPairing(for: s.courts[0])!
        s.fill(c, shown: shown)
        assert(s.courts[0].match?.teamA == shown.a.map(\.id))
        let playing = s.courts[0].match
        s.courts[1].plan = Match(teamA: [s.players[4].id,s.players[5].id], teamB: [s.players[6].id,s.players[7].id])
        s.courts[1].locked = 0; s.courts[1].shuffles = 4
        s.setQueueMatching(.balancedSkill)
        assert(s.courts[0].match == playing && s.courts[1].plan == nil && s.courts[1].locked == nil && s.courts[1].shuffles == nil)
        s.courts[1].plan = Match(teamA: [s.players[4].id,s.players[5].id], teamB: [s.players[6].id,s.players[7].id], queueOverride: true)
        s.setQueueMatching(.equalSkill)
        assert(s.courts[1].plan != nil)
        assert(s.next(keepPlayers: true).matchingMode == .equalSkill)
        let encoded = try! JSONEncoder().encode(s)
        assert(try! JSONDecoder().decode(SessionState.self, from: encoded).matchingMode == .equalSkill)
        var json = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        json.removeValue(forKey: "queueMatching")
        let legacy = try! JSONSerialization.data(withJSONObject: json)
        assert(try! JSONDecoder().decode(SessionState.self, from: legacy).matchingMode == .auto)
        s = fixture([3, 1, 5, 3, 3, 3])
        let narrow = s.pick(.doubles, from: s.players)!
        assert(Set((narrow.a+narrow.b).map(\.id)) == Set([0,3,4,5].map { s.players[$0].id }))
        s.setQueueMatching(.balancedSkill)
        let mixed = s.pick(.doubles, from: s.players)!
        assert(Set((mixed.a+mixed.b).map(\.id)) == Set(s.players.prefix(4).map(\.id)), "Balanced prefers queue turns over narrow range")
        s = fixture(Array(repeating: 3, count: 8)); s.setQueueMatching(.equalSkill)
        s.courts[1].plan = Match(teamA: [s.players[4].id,s.players[5].id], teamB: [s.players[6].id,s.players[7].id], queueOverride: true)
        s.shuffle(s.courts[0].id)
        s.setQueueMatching(.balancedSkill)
        assert(s.courts[1].plan?.queueOverride == true, "shuffling another court keeps explicit replacement provenance")
        s = fixture([1, 3, 3, 3]); s.setQueueMatching(.balancedSkill)
        let stale = s.pick(.doubles, from: s.players)!
        s.setQueueMatching(.equalSkill); s.fill(s.courts[0].id, shown: stale)
        assert(s.courts[0].match == nil, "Start rejects an outdated wide preview")
        s = fixture([2, 2, 3, 3]); s.setQueueMatching(.equalSkill)
        for _ in 0..<3 {
            s.results.append(GameResult(teamA: [s.players[2].id,s.players[3].id], teamB: [s.players[0].id,s.players[1].id], winner: 0, court: "C1", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-60)))
        }
        assert(!s.skillRangeAllowed(s.players.map(\.id)) && s.pick(.doubles, from: s.players) == nil, "streak boosts count toward strict spread")
        s = fixture([1, 1, 3, 3]); s.setQueueMatching(.equalSkill)
        s.players[0].lock = s.players[1].id; s.players[1].lock = s.players[0].id
        assert(s.pick(.doubles, from: s.players) == nil, "locked-team search cannot bypass strict spread")
    }

    static func selfCheck() {
        Store.webExportSelfCheck()
        Tournament.selfCheck()
        queueMatchingSelfCheck()
        queueSimplifiedSelfCheck()
        scheduledSelfCheck()
        let rally = RallyMotion("court-a")
        assert(rally.unit(5, 1) == RallyMotion("court-a").unit(5, 1), "rallies remain stable across redraws")
        assert(rally.unit(5, 1) != RallyMotion("court-b").unit(5, 1), "courts have independent rallies")
        assert(Set((0..<40).map { rally.unit($0, 1) }).count == 40, "rally targets vary by shot")
        assert((0..<100).allSatisfy { (0...1).contains(rally.unit($0, 0)) }, "rally targets stay in bounds")
        // Standings: 5 of 5 beats 6 of 7; game length doesn't count, so equal records draw.
        var table = SessionState(players: [Player(name: "A"), Player(name: "B"), Player(name: "X")])
        let (pa, pb, px) = (table.players[0].id, table.players[1].id, table.players[2].id)
        func game(_ w: UUID, _ l: UUID, won: Bool = true, minutes: Double = 10) -> GameResult {
            GameResult(teamA: [w], teamB: [l], winner: won ? 0 : 1, court: "", start: .distantPast, end: Date.distantPast.addingTimeInterval(minutes * 60))
        }
        table.results = Array(repeating: game(pa, px), count: 6) + [game(pa, px, won: false)] + Array(repeating: game(pb, px), count: 5)
        assert(table.score(pb) > table.score(pa), "5 of 5 should rank above 6 of 7")
        table.results = Array(repeating: game(pa, px, minutes: 4), count: 7) + [game(pa, px, won: false)]
            + Array(repeating: game(pb, px, minutes: 20), count: 7) + [game(pb, px, won: false, minutes: 20)]
        assert(table.score(pa) == table.score(pb), "game length doesn't count: equal records draw")
        assert(StandingsSheet.places([70, 70, 70, 64, 61, 61, 50]) == [1, 1, 1, 2, 3, 3, 4], "draws share a place; the next score takes the next place")
        // Sessions saved with the removed partner-request field still decode without losing their other data.
        let saved = Store(sessions: [table])
        var legacy = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
        var legacySessions = legacy["sessions"] as! [[String: Any]]
        var legacyPlayers = legacySessions[0]["players"] as! [[String: Any]]
        legacyPlayers[0]["partner"] = table.players[1].id.uuidString
        legacyPlayers[1]["partner"] = table.players[0].id.uuidString
        legacySessions[0]["players"] = legacyPlayers; legacy["sessions"] = legacySessions
        let decoded = try! JSONDecoder().decode(Store.self, from: JSONSerialization.data(withJSONObject: legacy))
        assert(decoded == saved, "legacy pair requests are ignored; players, ratings and results survive")
        // Fewer games goes first; moving to front beats that.
        var order = SessionState()
        order.players = [Player(name: "1", readyAt: .distantPast), Player(name: "2")]
        order.results = [GameResult(teamA: [order.players[0].id], teamB: [UUID()], winner: 0, court: "", start: Date())]
        assert(order.queue[0].name == "2", "fewer games goes first")
        order.moveToFront(order.players[0].id)
        assert(order.queue[0].name == "1", "moved to front beats fewer games")
        // Shuffle never offers a stacked doubles game, but offers every split when everyone is level.
        let mixed = fairSplits([3.9, 3.8, 2.0, 1.1].map { Player(name: "\($0)", skill: $0) })
        assert(mixed.count == 2 && !mixed.contains { Set($0.a.map(\.skill)) == [3.9, 3.8] || Set($0.b.map(\.skill)) == [3.9, 3.8] },
               "shuffle offered the two strongest together")
        assert(fairSplits((1...4).map { Player(name: "\($0)", skill: 3) }).count == 3)
        // No fair split (5,5,3,1): both equally uneven splits are offered, never the stacked 5+5 v 3+1.
        let uneven = fairSplits([5.0, 5, 3, 1].map { Player(name: "\($0)", skill: $0) })
        assert(uneven.count == 2 && uneven.allSatisfy { Set($0.a.map(\.skill)) != [5] && Set($0.b.map(\.skill)) != [5] }, "tied uneven splits")
        // Singles shuffle cycles opponents within range, closest skill first; out-of-range players aren't offered.
        let line = [5.0, 1, 4, 5, 4.5, 3].enumerated().map { Player(name: "\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSince1970: Double($0.offset))) }
        assert((0..<3).map { pickSingles(line, choice: $0)!.b[0].skill } == [5, 4.5, 4] && pickSingles(line)!.options == 3, "singles shuffle order")
        // A 3-star at the front finds the 3-star further back instead of the 5s and 1s in between.
        let mixed24 = [3.0, 5, 5, 1, 1, 5, 3].enumerated().map { Player(name: "\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSince1970: Double($0.offset))) }
        assert(pickSingles(mixed24)!.b[0].name == "6", "singles picked someone outside the skill range")
        // Fresh session: shuffles draw different random groups from everyone, each one still fair;
        // once someone has played, shuffling goes back to the front of the line.
        var fresh = SessionState(players: [5.0, 5, 5, 5, 5, 5, 1, 1, 1, 1, 1, 1].map { Player(name: "\($0)", skill: $0) })
        let draws = (1...8).compactMap { fresh.pick(.doubles, from: fresh.queue, choice: $0) }
        assert(Set(draws.map { Set(($0.a + $0.b).map(\.id)) }).count > 1, "fresh shuffle should draw new groups")
        assert(draws.allSatisfy { abs($0.a.map(\.skill).reduce(0, +) - $0.b.map(\.skill).reduce(0, +)) / 2 <= fairGap }, "fresh draws must stay fair")
        // After a game, the two who played aren't drawn while plenty of others haven't played yet.
        let (p0, p1) = (fresh.players[0].id, fresh.players[1].id)
        fresh.results.append(GameResult(teamA: [p0], teamB: [p1], winner: 0, court: "C", start: Date()))
        let after = (1...8).compactMap { fresh.pick(.doubles, from: fresh.queue, choice: $0) }
        assert(after.allSatisfy { $0.options == 99 && Set(($0.a + $0.b).map(\.id)).isDisjoint(with: [p0, p1]) }, "shuffle drew someone who already played")
        // Once too few unplayed players are left, shuffling goes back to the front of the line.
        for p in fresh.players.dropFirst(2).dropLast(3) {
            fresh.results.append(GameResult(teamA: [p.id], teamB: [p0], winner: 0, court: "C", start: Date()))
        }
        assert(fresh.pick(.doubles, from: fresh.queue, choice: 3)?.options != 99, "full shuffle should stop when few are unplayed")
        // Newcomers go ahead of players who've already played, behind others still waiting for a first game,
        // and several newcomers keep the order they arrived in.
        var late = SessionState(players: ["A", "B", "C"].enumerated().map { Player(name: $0.element, readyAt: Date(timeIntervalSince1970: Double($0.offset))) })
        late.results.append(GameResult(teamA: [late.players[2].id], teamB: [late.players[1].id], winner: 0, court: "C", start: Date(timeIntervalSinceNow: -3600)))
        late.update(late.players[1].id) { $0.readyAt = Date(timeIntervalSince1970: 100) }
        late.update(late.players[2].id) { $0.readyAt = Date(timeIntervalSince1970: 101) }
        late.addPlayer("New1", skill: 3)
        late.addPlayer("New2", skill: 3)
        assert(late.queue.map(\.name) == ["A", "New1", "New2", "B", "C"], "newcomers should queue ahead of players who've played")
        // A late arrival goes first once, then joins the normal order instead of catching up on games.
        var par = SessionState(players: ["X", "Y"].enumerated().map { Player(name: $0.element, readyAt: Date(timeIntervalSince1970: Double($0.offset))) })
        for _ in 0..<3 { par.results.append(GameResult(teamA: [par.players[0].id], teamB: [par.players[1].id], winner: 0, court: "C", start: Date(timeIntervalSinceNow: -3600))) }
        par.addPlayer("Late", skill: 3)
        assert(par.queue.first?.name == "Late", "a late arrival goes to the front on arrival")
        let lateID = par.players[2].id
        par.results.append(GameResult(teamA: [lateID], teamB: [UUID()], winner: 0, court: "C", start: Date()))
        par.update(lateID) { $0.readyAt = Date(timeIntervalSince1970: 100) }
        assert(par.queue.map(\.name) == ["X", "Y", "Late"], "after one game a late arrival waits their turn like everyone else")
        // Present: before the first game, players added are not here yet; marked present, they join in order of arrival.
        var start = SessionState()
        for name in ["P", "Q", "R"] { start.addPlayer(name, skill: 3) }
        assert(start.queue.isEmpty && start.activePlayers == 0, "at the start, players aren't here until marked present")
        start.arrive(start.players[2].id)
        start.arrive(start.players[0].id)
        assert(start.queue.map(\.name) == ["R", "P"], "they join the line in the order they arrive")
        // Marked present later, they come in like a late arrival: after 0-game players, at par.
        var mark = SessionState(players: ["X", "Y", "Z", "W"].enumerated().map { Player(name: $0.element, readyAt: Date(timeIntervalSince1970: Double($0.offset))) })
        mark.players[3].away = true
        for _ in 0..<3 { mark.results.append(GameResult(teamA: [mark.players[0].id], teamB: [mark.players[1].id], winner: 0, court: "C", start: Date(timeIntervalSinceNow: -3600))) }
        mark.update(mark.players[2].id) { $0.readyAt = Date(timeIntervalSince1970: 50) }
        assert(!mark.queue.contains { $0.name == "W" }, "not here: out of the line")
        mark.arrive(mark.players[3].id)
        assert(mark.queue.map(\.name) == ["Z", "W", "X", "Y"] && mark.players[3].credit == 3, "marked present: like a late arrival, at par")
        // Just off court: behind everyone rested even when behind on games (a late arrival's credit can leave them lowest).
        var backOn = SessionState(players: ["A", "B", "C", "D", "E"].enumerated().map { Player(name: $0.element, readyAt: Date(timeIntervalSince1970: Double($0.offset))) })
        for i in 1...4 { for _ in 0..<4 { backOn.results.append(GameResult(teamA: [backOn.players[i].id], teamB: [UUID()], winner: 0, court: "C", start: Date())) } }
        for _ in 0..<3 { backOn.results.append(GameResult(teamA: [backOn.players[0].id], teamB: [UUID()], winner: 0, court: "C", start: Date())) }
        assert(backOn.queue.map(\.name) == ["B", "C", "D", "E", "A"], "just off court waits behind everyone rested")
        // Install expiry: read from the profile's plist, counted in calendar days.
        let profile = Data("signed-junk<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>ExpirationDate</key><date>2026-10-11T05:43:26Z</date></dict></plist>more-junk".utf8)
        let expiry = InstallExpiry.expiration(in: profile)
        assert(expiry == Date(timeIntervalSince1970: 1791697406), "reads the profile's expiry")
        if let expiry {
            assert(InstallExpiry.label(expiry, now: expiry.addingTimeInterval(-3 * 86400)).hasPrefix("Renew in 3 days"), "counts days left")
            assert(InstallExpiry.label(expiry, now: expiry.addingTimeInterval(-60)).hasPrefix("Renew today"), "last day says today")
            assert(InstallExpiry.label(expiry, now: expiry.addingTimeInterval(60)).hasPrefix("Expired"), "past the date says expired")
        }
        // Arrivals in the first 30 minutes after the first game count as on time (no credit); later ones join at par.
        var lateS = SessionState(players: (0..<6).map { Player(name: "L\($0)", readyAt: Date(timeIntervalSinceNow: Double($0) - 60)) }
                                 + [Player(name: "Early", away: true), Player(name: "Late", away: true)])
        lateS.courts = [Court(name: "C1", format: .doubles)]
        let lx = UUID()
        for p in lateS.players.prefix(4) { lateS.results.append(GameResult(teamA: [p.id], teamB: [lx], winner: 0, court: "", start: Date(timeIntervalSinceNow: -20 * 60))) }
        lateS.arrive(lateS.players[6].id)
        SessionState.simulatedNow = Date(timeIntervalSinceNow: 20 * 60)
        lateS.arrive(lateS.players[7].id)
        SessionState.simulatedNow = nil
        assert(lateS.players[6].credit == nil && lateS.players[7].credit == 1, "late-arrival credit only from 30 minutes after the first game")
        // Manual mode: the chosen four are the court's game (none until every slot is filled), kept out of other courts' picks,
        // never shuffled; a finished game ends it.
        var man = SessionState(players: (0..<10).map { Player(name: "M\($0)", readyAt: Date(timeIntervalSinceNow: Double($0) - 60)) })
        man.courts = [Court(name: "C1", format: .doubles), Court(name: "C2", format: .doubles)]
        let mc = man.courts[0].id, mine = man.players.suffix(4).map(\.id) // the back of the line
        man.setManual(true, on: mc)
        for (k, id) in mine.prefix(3).enumerated() { man.setSlot(k, to: id, on: mc) }
        let manPartial = man.nextPairing(for: man.courts[0]) == nil
        man.setSlot(3, to: mine[3], on: mc)
        let manGame = man.nextPairing(for: man.courts[0])!, manOther = man.nextPairing(for: man.courts[1])!
        man.shuffle(mc)
        let manSame = man.nextPairing(for: man.courts[0]).map { ($0.a + $0.b).map(\.id) } == mine
        man.fill(mc); man.finish(mc, winner: 0)
        assert(manPartial && (manGame.a + manGame.b).map(\.id) == mine && manGame.options == 1 && !(manOther.a + manOther.b).contains { mine.contains($0.id) }
               && manSame && man.courts[0].manual == nil, "manual mode: chosen lineup, not shuffled, back to automatic after the game")
        // Locked teammates: if no equal-or-stronger opponents are available, they wait while others play.
        var lockS = SessionState(players: [3.0, 3.0, 3.2, 3.4, 2.6, 2.8, 3.1, 3.3, 2.9, 3.0, 3.5, 2.7].enumerated().map {
            Player(name: "K\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSinceNow: Double($0.offset) - 60)) })
        lockS.courts = [Court(name: "C1", format: .doubles)]
        let kid = lockS.players.map(\.id)
        lockS.setLock(kid[0], kid[1])
        let lg = lockS.pick(.doubles, from: lockS.queue)!
        let lgA = lg.a.contains { $0.id == kid[0] }, lt = lgA ? lg.a : lg.b, lo = lgA ? lg.b : lg.a
        assert(lt.contains { $0.id == kid[1] } && lockS.averageSkill(lo.map(\.id)) >= 3 - lockEqual, "locked teammates play together against an equal or stronger team")
        var lockRating = SessionState(players: ([4.0, 4.0] + Array(repeating: 2.0, count: 12) + [4.1, 4.1]).enumerated().map { Player(name: "R\($0.offset)", skill: $0.element) })
        let rid = lockRating.players.map(\.id), rule = LockRule(x: rid[0], y: rid[1], apart: false)
        lockRating.setLock(rid[0], rid[1])
        let fallback = lockRating.lockedGame(lockRating.players, rule, locks: [rule])!
        assert(fallback.b.map(\.id).contains(rid[14]) && fallback.b.map(\.id).contains(rid[15]), "locked fallback searches beyond the front of the line for equal-or-stronger opponents before rested weaker opponents")
        lockRating.results.append(GameResult(teamA: [rid[14]], teamB: [rid[15]], winner: 0, court: "", start: Date()))
        assert(lockRating.lockedGame(lockRating.players, rule, locks: [rule]) == nil, "locked games cannot recall opponents one counted game ahead")
        lockRating.results = []
        lockRating.update(rid[14]) { $0.credit = 3 }; lockRating.update(rid[15]) { $0.credit = 3 }
        assert(lockRating.lockedGame(lockRating.players, rule, locks: [rule]) == nil, "a lock cannot pull opponents more than one game ahead of the waiting line")
        var lockLastResort = SessionState(players: [4.0, 4.0, 2.0, 2.0].enumerated().map { Player(name: "L\($0.offset)", skill: $0.element) })
        let lid = lockLastResort.players.map(\.id)
        lockLastResort.setLock(lid[0], lid[1])
        assert(lockLastResort.pick(.doubles, from: lockLastResort.queue) == nil, "a locked pair waits when only weaker opponents are available")
        let idleGame = lockLastResort.pick(.doubles, from: lockLastResort.queue, allowIdleRelease: true)
        assert(idleGame == nil, "idle courts do not split locked pairs early")
        let fallbackPlayers = [5.0, 1.0, 4.0, 2.0].enumerated().map { Player(name: "F\($0.offset)", skill: $0.element) }
        let fallbackIDs = fallbackPlayers.map(\.id)
        lockCtx = LockCtx(locks: [LockRule(x: fallbackIDs[0], y: fallbackIDs[1], apart: true)], strict: true, real: Dictionary(uniqueKeysWithValues: fallbackPlayers.map { ($0.id, $0.skill) }), opponents: Set(fallbackIDs), rested: nil)
        let legalFallback = lastResortSplits(fallbackPlayers).first
        lockCtx = nil
        assert(legalFallback != nil && legalFallback!.a.contains { $0.id == fallbackIDs[0] } != legalFallback!.a.contains { $0.id == fallbackIDs[1] }, "fallback finds a legal split when the fairest raw split reunites released partners")
        var catchup = lockLastResort
        catchup.update(lid[2]) { $0.credit = 2 }; catchup.update(lid[3]) { $0.credit = 2 }
        let catchupGame = catchup.pick(.doubles, from: catchup.queue)
        assert(catchupGame == nil, "game-count deficit does not split locked pairs")
        for i in lockLastResort.players.indices { lockLastResort.players[i].readyAt = Date(timeIntervalSinceNow: -21 * 60) }
        lockLastResort.results.append(GameResult(teamA: [lid[2]], teamB: [lid[3]], winner: 0, court: "", start: Date(timeIntervalSinceNow: -21 * 60)))
        let splitAfterWait = lockLastResort.pick(.doubles, from: lockLastResort.queue)
        assert(splitAfterWait == nil, "21 minutes is too early to split an unmatchable pair")
        var lockWait = SessionState(players: [4.0, 4.0, 3.0, 3.0, 3.0, 3.0].enumerated().map { Player(name: "W\($0.offset)", skill: $0.element) })
        let wid = lockWait.players.map(\.id)
        lockWait.setLock(wid[0], wid[1])
        let otherGame = lockWait.pick(.doubles, from: lockWait.queue)
        assert(otherGame != nil && !(otherGame!.a + otherGame!.b).contains { [wid[0], wid[1]].contains($0.id) }, "unlocked players can fill the court while a locked pair waits")
        for k in 0..<3 { lockS.results.append(GameResult(teamA: [kid[0], kid[1]], teamB: [kid[2 + k], kid[5 + k]], winner: 0, court: "", start: Date(timeIntervalSinceNow: -600))) }
        lockS.results.append(GameResult(teamA: [kid[8], kid[9]], teamB: [kid[10], kid[11]], winner: 0, court: "", start: Date(timeIntervalSinceNow: -600)))
        lockS.update(kid[0]) { $0.first = true }; lockS.update(kid[1]) { $0.first = true }
        let sg = lockS.pick(.doubles, from: lockS.queue)!
        let cooldown = lockS.lockContext(lockS.queue), sgA = sg.a.map(\.id), sgB = sg.b.map(\.id)
        assert(lockS.splitDue(kid[0], kid[1]) && !(sgA.contains(kid[0]) && sgA.contains(kid[1])) && !(sgB.contains(kid[0]) && sgB.contains(kid[1]))
               && SessionState.lockMembers([kid[0], kid[2], kid[3], kid[4]], cooldown)
               && SessionState.keepsLocks([kid[0], kid[2]], [kid[3], kid[4]], cooldown, strict: true, real: Dictionary(uniqueKeysWithValues: lockS.players.map { ($0.id, $0.skill) }))
               && SessionState.keepsLocks([kid[0], kid[2]], [kid[1], kid[3]], cooldown, strict: true, real: Dictionary(uniqueKeysWithValues: lockS.players.map { ($0.id, $0.skill) })),
               "cooldown players can play independently or naturally meet as opponents, but cannot team")
        var busyCooldown = lockS
        busyCooldown.courts[0].match = Match(teamA: [kid[0], kid[2]], teamB: [kid[3], kid[4]])
        busyCooldown.update(kid[1]) { $0.first = true; $0.since = Date() }
        assert(busyCooldown.eligible(.doubles).contains { $0.id == kid[1] }, "cooldown players remain independently eligible while their mate plays")
        var fourCooldown = SessionState(players: (0..<4).map { Player(name: "C\($0)", skill: 3) })
        let fid = fourCooldown.players.map(\.id)
        fourCooldown.setLock(fid[0], fid[1])
        for _ in 0..<3 { fourCooldown.results.append(GameResult(teamA: [fid[0], fid[1]], teamB: [fid[2], fid[3]], winner: 0, court: "", start: Date())) }
        for first in [0, 2] {
            for i in fourCooldown.players.indices { fourCooldown.players[i].first = i == first }
            let game = fourCooldown.pick(.doubles, from: fourCooldown.queue)!
            assert(game.a.contains { $0.id == fid[0] } != game.a.contains { $0.id == fid[1] }, "four available players can play during cooldown regardless of queue order")
        }
        lockS.update(kid[0]) { $0.since = Date(timeIntervalSinceNow: -30 * 60) }; lockS.update(kid[1]) { $0.since = Date(timeIntervalSinceNow: -30 * 60) }
        let overdueSplit = lockS.pick(.doubles, from: lockS.queue)!
        assert(![overdueSplit.a, overdueSplit.b].contains { Set([kid[0], kid[1]]).isSubset(of: $0.map(\.id)) }, "overdue cooldown players do not become teammates")
        lockS.results.append(GameResult(teamA: [kid[0], kid[2]], teamB: [kid[3], kid[4]], winner: 0, court: "", start: Date(timeIntervalSinceNow: -600)))
        assert(lockS.splitDue(kid[0], kid[1]), "one player's separate game does not end the other's cooldown")
        lockS.results.append(GameResult(teamA: [kid[1], kid[2]], teamB: [kid[3], kid[4]], winner: 0, court: "", start: Date(timeIntervalSinceNow: -600)))
        assert(!lockS.splitDue(kid[0], kid[1]), "after both play a separate game, the lock resumes")
        lockS.courts[0].match = Match(teamA: [kid[1], kid[5]], teamB: [kid[6], kid[7]])
        let busyPick = lockS.pick(.doubles, from: lockS.eligible(.doubles))!
        assert(!(busyPick.a + busyPick.b).contains { $0.id == kid[0] }, "a locked player waits while their teammate is on court")
        // Two far-apart locked pairs both overdue: one of them plays (with two others), not the two pairs against each other.
        var lock2 = SessionState(players: [4.2, 2.1, 4.5, 4.3, 1.6, 1.4, 3.7, 3.3, 2.2, 1.1, 2.3, 1.7].enumerated().map {
            Player(name: "O\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSinceNow: Double($0.offset) - 60)) })
        lock2.courts = [Court(name: "C1", format: .doubles)]
        let oid = lock2.players.map(\.id)
        lock2.setLock(oid[0], oid[1]); lock2.setLock(oid[2], oid[3])
        for i in 0..<4 { lock2.update(oid[i]) { $0.since = Date(timeIntervalSinceNow: -30 * 60) } }
        lock2.results.append(GameResult(teamA: [oid[8], oid[9]], teamB: [oid[10], oid[11]], winner: 0, court: "", start: Date(timeIntervalSinceNow: -3600)))
        let od2 = lock2.pick(.doubles, from: lock2.queue)!, od2ids = (od2.a + od2.b).map(\.id)
        assert(od2ids.filter { oid.prefix(4).contains($0) }.count == 2
               && keepsLocks(od2.a.map(\.id), od2.b.map(\.id), lock2.lockContext(lock2.queue), strict: false, real: Dictionary(uniqueKeysWithValues: lock2.players.map { ($0.id, $0.skill) })),
               "two overdue locked pairs: one plays, still together")
        // Locking a side: shuffle keeps those players and changes only the other side, nobody on both.
        var lk = SessionState(players: [3.0, 3, 3, 3, 3, 3, 3, 3, 3, 3].enumerated().map { Player(name: "\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSinceNow: Double($0.offset) - 60)) })
        lk.courts = [Court(name: "C", format: .doubles)]
        let lc = lk.courts[0].id, lockedA = Set(lk.nextPairing(for: lk.courts[0])!.a.map(\.id))
        lk.lock(0, on: lc)
        var seenB = Set<Set<UUID>>()
        for _ in 0..<4 {
            lk.shuffle(lc)
            let g = lk.nextPairing(for: lk.courts[0])!
            assert(Set(g.a.map(\.id)) == lockedA && g.b.count == 2 && lockedA.isDisjoint(with: g.b.map(\.id)), "a locked side stays put")
            seenB.insert(Set(g.b.map(\.id)))
        }
        assert(seenB.count == 4, "shuffle with a lock should keep changing the other side")
        // Someone still on 0 games stays ahead of a late arrival, and doesn't cost the arrival their credit.
        var zero = SessionState(players: ["X", "Y", "Z"].enumerated().map { Player(name: $0.element, readyAt: Date(timeIntervalSince1970: Double($0.offset))) })
        for _ in 0..<3 { zero.results.append(GameResult(teamA: [zero.players[0].id], teamB: [zero.players[1].id], winner: 0, court: "C", start: Date(timeIntervalSinceNow: -3600))) }
        zero.update(zero.players[2].id) { $0.readyAt = Date(timeIntervalSince1970: 50) }
        zero.addPlayer("Late", skill: 3)
        assert(zero.queue.map(\.name) == ["Z", "Late", "X", "Y"] && zero.players[3].credit == 3, "a late arrival goes after 0-game players, at par")
        // Replacing a player with someone lined up on the other court refills that court, nobody double-booked.
        var rep = SessionState(players: [4.0, 4, 3, 3, 4, 3, 4, 3].enumerated().map { Player(name: "\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSince1970: Double($0.offset))) })
        let dubs = rep.courts[0], sing = rep.courts[1]
        let d0 = rep.nextPairing(for: dubs)!, s0 = rep.nextPairing(for: sing)!
        let out = d0.a[0].id, stolen = s0.a[0].id
        let knock = rep.replace(out, with: stolen, on: dubs.id)
        let d1 = rep.nextPairing(for: rep.courts[0])!, s1 = rep.nextPairing(for: rep.courts[1])!
        let ids1 = (d1.a + d1.b).map(\.id), ids2 = (s1.a + s1.b).map(\.id)
        assert(ids1.contains(stolen) && !ids1.contains(out) && !ids2.contains(stolen), "replace should move the player between courts")
        assert(Set(ids1).isDisjoint(with: ids2) && ids1.count == 4 && ids2.count == 2 && knock?.incoming != nil, "no double booking after replace")
        rep.shuffle(rep.courts[0].id)
        assert(rep.courts[0].plan == nil, "shuffle returns to automatic picks")
        assert(rep.nextPairing(for: rep.courts[1]).map { ($0.a + $0.b).map(\.id) } == ids2, "shuffling one court leaves the other alone")
        // Doubles skips a group that can't be split fairly (5,5,5,1) and takes the earliest one that can.
        let stacked = [5.0, 5, 5, 1, 3, 3].enumerated().map { Player(name: "\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSince1970: Double($0.offset))) }
        let g = pickDoubles(stacked)!
        assert(Set((g.a + g.b).map(\.name)) == ["0", "1", "4", "5"] && abs(g.a.map(\.skill).reduce(0, +) - g.b.map(\.skill).reduce(0, +)) < 0.01, "doubles group should be fair")
        let old = SessionState(date: Date(timeIntervalSince1970: 1), players: [Player(name: "Ana", skill: 2), Player(name: "Ben", skill: 3)])
        let newer = SessionState(date: Date(timeIntervalSince1970: 2), players: [Player(name: "ana", skill: 4)])
        let back = SessionState(players: [Player(name: "Ben")]).returningPlayers(from: [newer, old])
        assert(back.map(\.name) == ["ana"] && back[0].skill == 4, "returning players: latest rating, skip anyone already here")
        let d = pickDoubles([5, 1, 4, 2].map { Player(name: "\($0)", skill: Double($0)) })!
        assert(d.a.map(\.skill) == [5, 1] && d.b.map(\.skill) == [4, 2], "doubles should pair strong with new")
        assert(d.note != nil, "no similar-skill group waiting falls back to balanced teams")
        // Similar Skill: the head plus the earliest three within a level of each other, even further down the line.
        let simLine = [5, 1, 4.5, 2, 4.8, 1.5, 4.2, 3].enumerated().map { Player(name: "\($0.offset)", skill: $0.element) }
        let sim = pickDoubles(simLine)!
        assert(sim.note == nil && Set((sim.a + sim.b).map(\.skill)) == [5, 4.5, 4.8, 4.2], "similar skill groups comparable players")
        // Wait cap: everyone overdue plays next, even when behind in line on games played.
        var waitCheck = SessionState(players: (0..<8).map { Player(name: "\($0)", skill: 3, readyAt: Date(timeIntervalSinceNow: Double($0))) })
        for i in [6, 7] {
            waitCheck.players[i].since = Date(timeIntervalSinceNow: -50 * 60)
            waitCheck.results.append(GameResult(teamA: [waitCheck.players[i].id], teamB: [UUID()], winner: 0, court: "", start: Date(timeIntervalSinceNow: -3600)))
        }
        let overdueGame = waitCheck.pick(.doubles, from: waitCheck.queue)!
        assert(overdueGame.note?.contains("waited") != true, "overdue inclusion and notes are paused")
        // More overdue than a court takes: fewest games first, and a late arrival counts at par (not ahead for the games they missed).
        var fewer = SessionState(players: ["C", "D", "E", "F", "A", "Late", "G", "H"].enumerated().map { Player(name: $0.element, skill: 3, readyAt: Date(timeIntervalSinceNow: Double($0.offset))) })
        for (i, games, mins) in [(0, 2, 25), (1, 2, 25), (2, 2, 25), (3, 2, 25), (5, 0, 27), (4, 3, 28)] {
            fewer.players[i].since = Date(timeIntervalSinceNow: Double(-mins * 60))
            for _ in 0..<games { fewer.results.append(GameResult(teamA: [fewer.players[i].id], teamB: [UUID()], winner: 0, court: "", start: Date(timeIntervalSinceNow: -3600))) }
        }
        fewer.players[5].credit = 3
        let fewerGame = fewer.pick(.doubles, from: fewer.queue)!
        assert(!(fewerGame.a+fewerGame.b).contains { ["A","Late"].contains($0.name) }, "counted-game fairness retains arrival credit")
        fewer.players[4].since = Date(timeIntervalSinceNow: -50 * 60); fewer.players[5].since = Date(timeIntervalSinceNow: -40 * 60)
        let hardWait = fewer.pick(.doubles, from: fewer.queue)!
        assert(!(hardWait.a+hardWait.b).contains { ["A","Late"].contains($0.name) }, "30-minute waits do not override counted games")
        // An overdue strong player gets a balanced game within 2 levels rather than a lopsided one.
        var stretch = SessionState(players: [5.0, 4.5, 3.5, 3, 3, 3, 2, 1].enumerated().map { Player(name: "\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSinceNow: Double($0.offset))) })
        stretch.players[0].since = Date(timeIntervalSinceNow: -35 * 60)
        stretch.results.append(GameResult(teamA: [stretch.players[0].id], teamB: [UUID()], winner: 0, court: "", start: Date(timeIntervalSinceNow: -3600)))
        let stretchGame = stretch.pick(.doubles, from: stretch.queue)!, stretchSkills = (stretchGame.a + stretchGame.b).map(\.skill)
        assert(!stretchSkills.contains(5), "overdue players no longer force a wider game")
        // Rest first: rather than call three players straight back for a similar game, balanced teams from rested players.
        let resting = [5, 4.2, 3.8, 3.0, 5, 5, 4.8].enumerated().map { Player(name: "\($0.offset)", skill: $0.element) }
        let restGame = pickDoubles(resting, justOff: Set(resting[4...].map(\.id)))!
        assert(Set((restGame.a + restGame.b).map(\.name)) == ["0", "1", "2", "3"] && restGame.note == "mixed teams so nobody goes straight back",
               "nobody goes straight back while rested players can make a game")
        // Repeats: a similar group that just played together splits differently, or makes way for another similar group.
        let eight = [5, 4.8, 4.6, 4.4, 4.2, 4.1, 4, 3.9].enumerated().map { Player(name: "\($0.offset)", skill: $0.element) }
        func lastGame(_ a: [Int], _ b: [Int]) -> Recent {
            var r: Recent = [:]
            for (mine, theirs) in [(a, b), (b, a)] { for i in mine {
                r[eight[i].id] = (Set(mine.filter { $0 != i }.map { eight[$0].id }), Set(theirs.map { eight[$0].id }))
            } }
            return r
        }
        let again = pickDoubles(eight, recent: lastGame([0, 3], [1, 2]))!
        let firstTry = pickDoubles(eight)!
        assert(Set((again.a+again.b).map(\.id)) == Set((firstTry.a+firstTry.b).map(\.id)), "history cannot change the selected group")
        // Too few players for similar groups (under 6.25 per doubles court): balanced teams in queue order instead.
        let skills = [5.0, 2.6, 4.6, 3.0, 5.0, 4.8, 4.9, 2.8]
        func lineup(_ extra: Int) -> SessionState {
            var st = SessionState(players: (skills + Array(repeating: 3.0, count: extra)).enumerated().map { Player(name: "\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSinceNow: Double($0.offset) - 60)) })
            st.courts = [Court(name: "C1", format: .doubles), Court(name: "C2", format: .doubles)]
            return st
        }
        let few = lineup(0), many = lineup(8)
        assert(!few.balancedOnly && !many.balancedOnly, "roster-size strategy switching is paused")
        let smallGame = few.pick(.doubles,from:few.queue)!
        assert(abs(smallGame.a.map(\.skill).reduce(0,+)-smallGame.b.map(\.skill).reduce(0,+))/2 <= fairGap,"small rosters retain balanced matching without a separate strategy")
        let similar = many.pick(.doubles, from: many.queue)!
        assert(Set((similar.a + similar.b).map(\.name)) == ["0", "2", "4", "5"], "enough players: similar-skill groups")
        // Equal counts preserve the normal waiting order, even for easier-to-match players.
        var tie = SessionState(players: [3.0, 5.0, 4.9, 4.8, 4.7, 3, 3, 3, 3, 3, 3, 3].enumerated().map { Player(name: "\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSinceNow: Double($0.offset) - 60)) })
        tie.courts = [Court(name: "C1", format: .doubles), Court(name: "C2", format: .doubles)]
        tie.players.append(contentsOf: (0..<4).map { Player(name: "x\($0)", skill: 3, readyAt: Date(timeIntervalSinceNow: Double(20 + $0) - 60)) })
        for p in tie.players { tie.results.append(GameResult(teamA: [p.id], teamB: [UUID()], winner: 0, court: "C", start: Date())) }
        let tieGame = tie.pick(.doubles, from: tie.queue)!
        assert((tieGame.a + tieGame.b).contains { $0.name == "0" }, "on equal counts, the normal queue head goes first")
        // Before the first game, nobody is overdue however long they've been here, so shuffle keeps working.
        var idle = SessionState(players: (0..<12).map { Player(name: "\($0)", skill: Double(2 + $0 % 4), readyAt: Date(timeIntervalSinceNow: Double($0) - 1800)) })
        idle.courts = [Court(name: "C1", format: .doubles)]
        assert(idle.pick(.doubles, from: idle.queue)?.note?.contains("waited") != true, "no one is overdue before the first game")
        // Overdue players who can't make even teams together: as many as fair teams allow play, and the note names only them.
        var od4 = SessionState(players: [("A", 4.9), ("B", 3.0), ("C", 2.5), ("D", 2.5), ("E", 3.0), ("F", 3.0), ("G", 3.0), ("H", 3.0)].enumerated()
            .map { Player(name: $0.element.0, skill: $0.element.1, readyAt: Date(timeIntervalSinceNow: Double($0.offset) - 60)) })
        for i in 0..<4 {
            od4.players[i].since = Date(timeIntervalSinceNow: -50 * 60)
            od4.results.append(GameResult(teamA: [od4.players[i].id], teamB: [UUID()], winner: 0, court: "", start: Date(timeIntervalSinceNow: -3600)))
        }
        let odGame = od4.pick(.doubles, from: od4.queue)!, odNames = Set((odGame.a + odGame.b).map(\.name))
        assert(odGame.note?.contains("waited") != true && abs(odGame.a.map(\.skill).reduce(0,+)-odGame.b.map(\.skill).reduce(0,+))/2 <= fairGap, "overdue inclusion is paused while balance remains")
        // Streaks: matched 1.5 higher after 3 wins in a row, 1.5 lower after 3 losses; a no-result game ends a streak.
        func res(_ w: UUID, _ l: UUID, _ winner: Int? = 0) -> GameResult { GameResult(teamA: [w], teamB: [l], winner: winner, court: "", start: Date(timeIntervalSinceNow: -600)) }
        var stk = SessionState(players: [Player(name: "S0"), Player(name: "S1"), Player(name: "S2")])
        let (k0, k1, k2) = (stk.players[0].id, stk.players[1].id, stk.players[2].id)
        stk.results = [res(k0, k1), res(k0, k1), res(k0, k1)]
        assert(stk.streakBoost(k0) == 0.5 && stk.streakBoost(k1) == -0.5 && stk.streakBoost(k2) == 0, "3 in a row: 0.5 for matching")
        stk.results.append(res(k0, k1))
        assert(stk.streakBoost(k0) == 1 && stk.streakBoost(k1) == -1, "each further win or loss: 0.5 more")
        stk.results += [res(k0, k1), res(k0, k1)]
        assert(stk.streakBoost(k0) == 1.5 && stk.streakBoost(k1) == -1.5, "capped at 1.5")
        stk.results = [res(k0, k1), res(k0, k1), res(k0, k1)]
        stk.results.append(res(k0, k1, nil))
        assert(stk.streakBoost(k0) == 0.5, "a cancelled game doesn't break a streak")
        assert(skillPresets.enumerated().allSatisfy { Int($0.element.rounded()) == $0.offset + 1 }, "each level preset reads as its own level")
        // Standings: ranked from 75% of the median games played; a corrected winner moves ratings as if it had been entered right.
        var night = SessionState(players: (0..<6).map { Player(name: "\($0)", skill: 3) })
        let ids = night.players.map(\.id)
        for (i, games) in [9, 9, 9, 10, 4, 5].enumerated() {
            for _ in 0..<games { night.results.append(GameResult(teamA: [ids[i]], teamB: [UUID()], winner: 0, court: "", start: .distantPast)) }
        }
        assert(night.rankingMinimum == 7, "ranked from 75% of the median games played")
        var fix = SessionState(players: (0..<4).map { Player(name: "\($0)", skill: 3) })
        let f = fix.players.map(\.id)
        fix.results = [GameResult(teamA: [f[0], f[1]], teamB: [f[2], f[3]], winner: 0, court: "", start: Date(timeIntervalSinceNow: -600))]
        var right = fix
        right.results = []
        right.courts = [Court(name: "C", format: .doubles)]
        right.courts[0].match = Match(teamA: [f[0], f[1]], teamB: [f[2], f[3]], start: fix.results[0].start)
        right.finish(right.courts[0].id, winner: 1, at: fix.results[0].end)
        let wrongSkills = fix.players.map(\.skill)
        fix.results[0].changes = Dictionary(uniqueKeysWithValues: f.map { ($0, 0.0) }) // stand-in for the change the wrong result made
        fix.setWinner(0, 1)
        assert(fix.players.map(\.skill) == right.players.map(\.skill) && wrongSkills.allSatisfy { $0 == 3 }, "a corrected winner moves ratings as if entered right")
        fix.setWinner(0, nil)
        assert(fix.players.allSatisfy { $0.skill == 3 } && fix.games.isEmpty, "corrected to cancelled: no rating change, not a game")
        // Streaks on the rating dots: red into the empty dots, blue over the top filled ones, half a dot per 0.5; a ring past the dots.
        let dots = { (f: Int, b: Double) in SkillDots.streak(filled: f, boost: b) }
        assert(!dots(5, 0).fire && !dots(3, 1.5).fire && dots(4, 1.5).fire, "fire only when a win streak overflows the dots")
        assert(!dots(1, -1.5).fire, "losing streaks never show fire")
        assert(dots(3, 0.5).parts == [0, 0, 0, 0.5, 0] && !dots(3, 0.5).ring && dots(3, 1.5).parts == [0, 0, 0, 1, 0.5], "win streak dots")
        assert(dots(3, -1).parts == [0, 0, 1, 0, 0] && dots(3, -0.5).parts == [0, 0, 0.5, 0, 0], "losing streak dots")
        // Wait clock (the queue's minutes and the 20-minute rule): nothing before the first game, then from the last game or arrival.
        var wc = SessionState(players: [Player(name: "W", readyAt: Date(timeIntervalSinceNow: -3000))])
        assert(wc.waitStart(wc.players[0]).timeIntervalSinceNow > -1, "before the first game nobody's clock runs")
        wc.results = [GameResult(teamA: [UUID()], teamB: [UUID()], winner: 0, court: "", start: Date(timeIntervalSinceNow: -3600))]
        assert(abs(wc.waitStart(wc.players[0]).timeIntervalSinceNow + 3000) < 1, "a late arrival waits from arriving")
        wc.players[0].since = Date(timeIntervalSinceNow: -600)
        wc.players[0].paused = true
        assert(abs(wc.waitStart(wc.players[0]).timeIntervalSinceNow + 600) < 1, "from their last game; sitting out doesn't restart it")
        assert(dots(5, 0.5).fire && !dots(5, 0.5).ring && dots(1, -1.5).parts == [1, 0, 0, 0, 0] && dots(1, -1.5).ring && dots(3, 0).parts == [0, 0, 0, 0, 0], "fire for overflowing wins; blue rings for overflowing losses")
        // A cancelled game isn't a game: no count, no rating, nobody just off, and the four are back where they were in line.
        var cx = SessionState(players: (0..<8).map { Player(name: "\($0)", skill: 3, readyAt: Date(timeIntervalSinceNow: Double($0) - 60)) },
                              courts: [Court(name: "C", format: .doubles)])
        let lineBefore = cx.queue.map(\.id), ratingsBefore = cx.players.map(\.skill)
        cx.fill(cx.courts[0].id)
        let cancelled = cx.courts[0].match!
        cx.finish(cx.courts[0].id, winner: nil)
        assert(cx.queue.map(\.id) == lineBefore && cx.players.map(\.skill) == ratingsBefore, "a cancelled game leaves the line and ratings as they were")
        assert(cx.results.count == 1 && cx.games.isEmpty && cx.players.allSatisfy { cx.played($0.id) == 0 && cx.gamesCounted[$0.id] == 0 },
               "a cancelled game is kept in the history but counts for nobody")
        // End Session cancels whatever is on court and marks the session ended.
        cx.fill(cx.courts[0].id)
        cx.end()
        assert(cx.ended != nil && cx.onCourt.isEmpty && cx.results.count == 2 && cx.games.isEmpty, "End Session cancels games on court")
        // The first player added to an empty session dates it today.
        var later = SessionState(date: .distantPast)
        later.addPlayer("A", skill: 3)
        assert(Calendar.current.isDateInToday(later.date), "an empty session takes the date its first player is added")
        // Saved data from before live sessions: earlier sessions count as ended, the current one stays live.
        struct OldStore: Encodable { var current: SessionState, past: [SessionState] }
        let oldSave = try! JSONEncoder().encode(OldStore(current: SessionState(),
            past: [SessionState(results: [GameResult(teamA: [], teamB: [], winner: 0, court: "", start: .distantPast, end: .distantPast)])]))
        let migrated = try! JSONDecoder().decode(Store.self, from: oldSave)
        assert(migrated.sessions.count == 2 && migrated.sessions[0].ended == .distantPast && migrated.sessions[1].isLive, "old saves: past ended, current live")
        // Length: ends that many hours after the first game; reopen makes it live again.
        var timed = SessionState(results: [GameResult(teamA: [], teamB: [], winner: 0, court: "", start: .distantPast)])
        timed.hours = 2.5
        timed.end()
        timed.reopen()
        assert(timed.endsAt == Date.distantPast.addingTimeInterval(9000) && timed.isLive, "ends 2.5 h after the first game; reopen clears ended")
        // All Players edits apply in every session.
        var pool = [SessionState(players: [Player(name: "Ana", skill: 3)]), SessionState(players: [Player(name: "ana", skill: 2.5), Player(name: "Bo")])]
        SessionState.editEverywhere(name: "Ana", to: "Anna", skill: 4.2, in: &pool)
        assert(pool.allSatisfy { $0.players[0].name == "Anna" && $0.players[0].skill == 4.2 } && pool[1].players[1].name == "Bo", "an All Players edit applies everywhere")
        // A 5.0 can make a similar-skill game only if the 3.0 on a win streak counts as 4.5; the game hands back real players.
        var hot = SessionState(players: [5, 3, 4.2, 4.2, 3, 3, 3, 3, 3, 3, 3, 3].enumerated().map { Player(name: "\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSinceNow: Double($0.offset) - 60)) })
        hot.courts = [Court(name: "C1", format: .doubles)]
        let gx = UUID(), gy = UUID()
        for w in [0, 1, 0, 1] { hot.results.append(GameResult(teamA: [hot.players[0].id], teamB: [gx], winner: w, court: "", start: Date(timeIntervalSinceNow: -600))) }
        for _ in 0..<5 { hot.results.append(GameResult(teamA: [hot.players[1].id], teamB: [gx], winner: 0, court: "", start: Date(timeIntervalSinceNow: -600))) }
        for p in hot.players.dropFirst(2) {
            for w in [0, 1, 0, 1, 0] { hot.results.append(GameResult(teamA: [p.id], teamB: [gx], winner: w, court: "", start: Date(timeIntervalSinceNow: -600))) }
        }
        hot.results.append(GameResult(teamA: [gx], teamB: [gy], winner: 0, court: "", start: Date(timeIntervalSinceNow: -600)))
        let hotGame = hot.pick(.doubles, from: hot.queue)!
        assert(Set((hotGame.a + hotGame.b).map(\.name)) == ["0", "1", "2", "3"] && (hotGame.a + hotGame.b).first { $0.name == "1" }?.skill == 3,
               "a 5-win streak is matched 1.5 higher (3.0 plays as 4.5); real players and ratings handed back")
        // Lock + shuffle and Replace judge evenness on ratings with streak boosts: a 2.6 on 5 wins plays a 4.0 as an even singles game.
        var ev = SessionState(players: [Player(name: "Hot", skill: 2.6), Player(name: "Four", skill: 4.0)])
        for _ in 0..<5 { ev.results.append(GameResult(teamA: [ev.players[0].id], teamB: [gx], winner: 0, court: "", start: Date())) }
        assert(abs(ev.unevenness([ev.players[0].id], [ev.players[1].id]) - 0.1) < 1e-9 && ev.isEven([ev.players[0].id], [ev.players[1].id]), "evenness uses boosted ratings")
        // Hot/cold teaming: a 3-win and a 3-loss player within 1.0 level are teammates, against even opponents.
        var hc = SessionState(players: [3.2, 3.6, 3.0, 3.4, 3.1, 3.3, 3.5, 3.2, 3.0, 3.4].enumerated().map { Player(name: "\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSinceNow: Double($0.offset) - 60)) })
        hc.courts = [Court(name: "C1", format: .doubles)]
        func g1(_ id: UUID, _ won: Bool) -> GameResult { GameResult(teamA: [id], teamB: [gx], winner: won ? 0 : 1, court: "", start: Date(timeIntervalSinceNow: -600)) }
        for _ in 0..<3 { hc.results += [g1(hc.players[0].id, true), g1(hc.players[5].id, false)] }
        for p in hc.players where p.name != "0" && p.name != "5" { hc.results += [g1(p.id, true), g1(p.id, false), g1(p.id, true)] }
        hc.results.append(GameResult(teamA: [gx], teamB: [gy], winner: 0, court: "", start: Date(timeIntervalSinceNow: -600)))
        let hcGame = hc.pick(.doubles, from: hc.queue)!, hcTeam = [hcGame.a, hcGame.b].first { $0.contains { $0.name == "0" } }
        assert(hcTeam?.contains { $0.name == "5" } == true, "hot and cold teamed up")
        // Late arrivals: the first few go first, the rest join at par in arrival order; at most 2 on their first game in a game.
        var wave = SessionState(players: (0..<12).map { Player(name: "R\($0)", readyAt: Date(timeIntervalSinceNow: Double($0) - 60)) })
        wave.courts = [Court(name: "C1", format: .doubles), Court(name: "C2", format: .doubles)]
        for p in wave.players { wave.results.append(GameResult(teamA: [p.id], teamB: [gx], winner: 0, court: "", start: Date(timeIntervalSinceNow: -3600))) }
        for k in 0..<6 { wave.addPlayer("L\(k)", skill: 3, rated: nil) }
        let waveLine = wave.queue.map(\.name)
        assert(["L0", "L1", "L2", "L3"].allSatisfy { (waveLine.firstIndex(of: $0) ?? 99) < 4 } && waveLine.firstIndex(of: "L4")! > waveLine.firstIndex(of: "R0")!,
               "late arrivals: 4 go first, then at par")
        let waveGame = wave.pick(.doubles, from: wave.queue)!
        assert((waveGame.a + waveGame.b).filter { $0.name.hasPrefix("L") }.count <= latePerGame, "at most 2 late arrivals on their first game in one game")
        // Ratings settle faster for a new player's first games, slower for regulars.
        var rk = SessionState(players: [Player(name: "N", rated: 0), Player(name: "M", rated: newGames), Player(name: "O")])
        assert(rk.kFactor(rk.players[0].id) == newK && rk.kFactor(rk.players[1].id) == regK && rk.kFactor(rk.players[2].id) == regK, "rating speed by experience")
        rk.players[0].rated = newGames - 1
        rk.results.append(GameResult(teamA: [rk.players[0].id], teamB: [gx], winner: 0, court: "", start: Date()))
        assert(rk.kFactor(rk.players[0].id) == regK, "after 8 rated games a new player settles to the regular speed")
        // The court names someone overdue only after 25 minutes.
        var due = SessionState(players: (0..<8).map { Player(name: "W\($0)", readyAt: Date(timeIntervalSinceNow: Double($0) - 60)) })
        due.players[7].since = Date(timeIntervalSinceNow: -22 * 60)
        due.results.append(GameResult(teamA: [due.players[7].id], teamB: [gx], winner: 0, court: "", start: Date(timeIntervalSinceNow: -3600)))
        let dueGame = due.pick(.doubles, from: due.queue)!
        assert(!(dueGame.a+dueGame.b).contains { $0.name == "W7" } && dueGame.note?.contains("waited") != true, "20-minute waits do not override fewer games")
        // New session with the same players keeps locked teammates and rated-game counts.
        var carry = SessionState(players: [Player(name: "A", rated: 2), Player(name: "B"), Player(name: "C")])
        carry.results.append(GameResult(teamA: [carry.players[0].id], teamB: [carry.players[1].id], winner: 0, court: "", start: Date()))
        carry.setLock(carry.players[0].id, carry.players[1].id)
        let nxt = carry.next(keepPlayers: true)
        assert(nxt.players[0].lock == nxt.players[1].id && nxt.players[1].lock == nxt.players[0].id && nxt.players[0].rated == 3 && nxt.players[1].rated == nil,
               "next session keeps locks and rated counts")
        // Balanced-only below 6.25 players per court: 13 on 2 courts plays similar groups, 12 balanced.
        var bal = SessionState(players: (0..<13).map { Player(name: "B\($0)") })
        bal.courts = [Court(name: "C1", format: .doubles), Court(name: "C2", format: .doubles)]
        assert(!bal.balancedOnly, "13 players on 2 courts: similar groups")
        bal.players.removeLast()
        assert(!bal.balancedOnly, "small roster uses the same matching strategy")
        // Start begins the game on screen, even if someone became overdue (20 min) since the screen was drawn.
        var drift = SessionState(players: (0..<9).map { Player(name: "D\($0)", readyAt: Date(timeIntervalSinceNow: Double($0) - 60)) })
        drift.courts = [Court(name: "C1", format: .doubles)]
        let sx = UUID()
        for p in drift.players { drift.results.append(GameResult(teamA: [p.id], teamB: [sx], winner: 0, court: "", start: Date(timeIntervalSinceNow: -3600))) }
        drift.results.append(GameResult(teamA: [drift.players[8].id], teamB: [sx], winner: 0, court: "", start: Date(timeIntervalSinceNow: -3600)))
        drift.update(drift.players[8].id) { $0.since = Date(timeIntervalSinceNow: -19.5 * 60) }
        let drawn = drift.nextPairing(for: drift.courts[0])!
        SessionState.simulatedNow = Date(timeIntervalSinceNow: 120)
        let afterDrift = drift.nextPairing(for: drift.courts[0])!
        drift.fill(drift.courts[0].id, shown: drawn, at: SessionState.now)
        SessionState.simulatedNow = nil
        assert(Set((drawn.a+drawn.b).map(\.id)) == Set((afterDrift.a+afterDrift.b).map(\.id))
               && drift.courts[0].match.map { Set($0.teamA + $0.teamB) } == Set((drawn.a + drawn.b).map(\.id)), "Start begins the game on screen")
        // Even games: the four on 0 games play (a 5.0, 4.0 and two 3.0s, balanced) rather than the 4.8 on 1 game who'd make a closer
        // range, which would leave a 0-game player waiting while someone reaches 2.
        var evn = SessionState(players: [5.0, 4.0, 3.0, 3.0, 5.0, 4.9, 4.8].enumerated().map { Player(name: "\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSinceNow: Double($0.offset) - 60)) })
        evn.courts = [Court(name: "C1", format: .doubles)]
        let ex = UUID(), ey = UUID()
        for p in evn.players.dropFirst(4) { evn.results.append(GameResult(teamA: [p.id], teamB: [ex], winner: 0, court: "", start: Date(timeIntervalSinceNow: -600))) }
        evn.results.append(GameResult(teamA: [ex], teamB: [ey], winner: 0, court: "", start: Date(timeIntervalSinceNow: -600)))
        let evGame = evn.pick(.doubles, from: evn.queue)!
        assert(!evn.balancedOnly && Set((evGame.a + evGame.b).map(\.name)) == ["0", "1", "2", "3"], "even games: nobody plays again while someone with fewer games waits")
        // Four rested but no fair game among them: they play anyway, strongest with weakest, rather than call anyone back.
        let four = [5.0, 3.1, 3.3, 3.2, 4.5, 2.9, 3.0, 3.6].enumerated().map { Player(name: "\($0.offset)", skill: $0.element) }
        let rest4 = pickDoubles(four, justOff: Set(four[4...].map(\.id)))!
        assert(abs(rest4.a.map(\.skill).reduce(0,+)-rest4.b.map(\.skill).reduce(0,+))/2 <= fairGap, "balanced recall precedes an uneven rested game")
        // Fewest games before fewest repeats: A, B and C (1 game each) play although A and B met last game; D, E, F have 3.
        let fg = ["H", "A", "B", "C", "D", "E", "F"].map { Player(name: $0) }
        let fgGame = pickDoubles(fg, recent: [fg[1].id: ([], [fg[2].id]), fg[2].id: ([], [fg[1].id])],
                                 games: Dictionary(uniqueKeysWithValues: fg.dropFirst().map { ($0.id, ["A", "B", "C"].contains($0.name) ? 1 : 3) }))!
        assert(Set((fgGame.a + fgGame.b).map(\.name)) == ["H", "A", "B", "C"], "fewest games fill a game before fewest repeats")
        assert(Set((firstTry.a + firstTry.b).map(\.name)) == ["0", "1", "2", "3"], "no history: earliest similar group")
        // Only four strong players who all just played each other: balanced teams with new partners instead.
        let top = [5, 5, 5, 5, 3, 3, 3, 3].enumerated().map { Player(name: "\($0.offset)", skill: Double($0.element)) }
        var topRecent: Recent = [:]
        for i in 0..<4 { topRecent[top[i].id] = (Set([top[i ^ 1].id]), Set((0..<4).filter { $0 / 2 != i / 2 }.map { top[$0].id })) }
        let mixedUp = pickDoubles(top, recent: topRecent)!
        assert(Set((mixedUp.a+mixedUp.b).map(\.id)) == Set(top.prefix(4).map(\.id)), "repeated foursomes retain their turns")
        let reg = registry([newer, old])
        assert(reg.map(\.name) == ["ana", "Ben"] && reg[0].sessions == 2 && reg[0].skill == 4, "registry merges people by name")
        let s = pickSingles([5, 1, 4, 5].map { Player(name: "\($0)", skill: Double($0)) })!
        assert(s.b[0].skill == 5, "singles should pick closest skill")
        assert(pickSingles([Player(name: "x")]) == nil)

        var st = SessionState(players: (1...8).map { Player(name: "\($0)", skill: Double($0 % 3 + 2), readyAt: Date(timeIntervalSince1970: Double($0))) })
        let next = st.upNext
        assert(next.count == 2 && Set(next.flatMap { $0.a + $0.b }.map(\.id)).count == 6, "up next must not double-book")
        var twin = st
        twin.courts[1].format = .doubles
        let w0 = twin.nextPairing(for: twin.courts[0]), w1 = twin.nextPairing(for: twin.courts[1])
        assert(w0 != nil && w1 != nil && Set((w0!.a + w0!.b + w1!.a + w1!.b).map(\.id)).count == 8, "two doubles courts both get a game")
        var opening = SessionState(players: (1...10).map { Player(name: "\($0)", skill: 3, readyAt: Date(timeIntervalSince1970: Double($0))) })
        let court2 = opening.nextPairing(for: opening.courts[1]).map { ($0.a + $0.b).map(\.id) }
        for _ in 1...3 { opening.shuffle(opening.courts[0].id) }
        assert(opening.nextPairing(for: opening.courts[1]).map { ($0.a + $0.b).map(\.id) } == court2, "shuffling court 1 leaves court 2 alone")
        assert(opening.nextPairing(for: opening.courts[0]) != nil)
        let lineBeforeStart = st.queue.map(\.id)
        st.fill(st.courts[0].id)
        let winners = st.courts[0].match!.teamA
        st.undoStart(st.courts[0].id)
        assert(st.queue.map(\.id) == lineBeforeStart && st.results.isEmpty && st.onCourt.isEmpty, "undo start should put everyone back in place")
        st.fill(st.courts[0].id)
        let before = st.player(winners[0])!.skill
        st.finish(st.courts[0].id, winner: 0)
        assert(st.wins(winners[0]) == 1 && st.played(winners[0]) == 1 && st.onCourt.isEmpty)
        assert(st.player(winners[0])!.skill > before, "winners gain rating")
        st.deleteResult(at: 0)
        assert(abs(st.player(winners[0])!.skill - before) < 1e-9 && st.results.isEmpty, "deleting a game undoes its rating change")

        var capped = SessionState(players: [Player(name: "top", skill: 5)])
        let applied = capped.adjust([capped.players[0].id], by: 0.2)
        assert(capped.players[0].skill == 5 && applied.values.first == 0, "ratings stop at 5 and record the real change")

        let even = ratingChange(teamA: 3, teamB: 3, aWon: true)
        assert(even > 0 && ratingChange(teamA: 3, teamB: 3, aWon: false) < 0)
        assert(ratingChange(teamA: 2, teamB: 4, aWon: true) > even, "upsets move ratings more")
        assert(ratingChange(teamA: 4, teamB: 2, aWon: true) < even, "expected wins move ratings less")

        // Within range, a rested player beats someone just off court, even if the fresh player is a closer match.
        let t0 = Date(timeIntervalSince1970: 0), finished = Date(timeIntervalSince1970: 100)
        let lena = Player(name: "Lena", skill: 5, readyAt: t0)
        let dev = Player(name: "Dev", skill: 5, readyAt: finished.addingTimeInterval(1))
        let q = [lena, Player(name: "Ben", skill: 4.5, readyAt: t0.addingTimeInterval(1)), dev]
        assert(pickSingles(q, finishes: [finished])!.b[0].name == "Ben", "recently finished player jumped the queue")
        // But skill range comes first: a fresh in-range player beats a rested one far outside it.
        let far = [lena, Player(name: "Zoe", skill: 1, readyAt: t0.addingTimeInterval(1)), dev]
        assert(pickSingles(far, finishes: [finished])!.b[0].name == "Dev", "out-of-range rested player chosen over in-range")
        assert(pickSingles([lena, far[1]], finishes: [finished])!.b[0].name == "Zoe", "falls back when nobody in range")
    }
    #endif
}

#if DEBUG
/// Replays a night on a virtual clock through the real matching code. Launch with `-simulate`: reads
/// Documents/sim-input.json (or the saved sessions if absent), writes Documents/sim-report.md and prints it.
enum Simulation {
    typealias Side = [(name: String, skill: Double)]

    struct Game {
        var minute: Double, length: Double, court: String, a: Side, b: Side
        var initialA: Side = [], initialB: Side = []
        var aWon = false, note: String?, straightBack: [String]
        var spread: Double { let s = (a + b).map(\.skill); return s.max()! - s.min()! }
        var gap: Double { abs(Simulation.avg(a) - Simulation.avg(b)) }
    }

    /// A wait of 35 minutes or more: who, when, and how their games compared with everyone's when it began.
    struct LongWait { var name: String, skill: Double, minutes: Double, from: Double, to: Double, games: Int, groupAverage: Double }

    struct Night { var games: [Game] = []; var waits: [String: [Double]] = [:]; var long: [LongWait] = []; var unfinished: [String: Double] = [:]; var neverPlayed: [String] = [] }

    static func avg(_ side: Side) -> Double { side.map(\.skill).reduce(0, +) / Double(side.count) }

    static func selfCheck() {
        var fresh = SessionState(players: (0..<8).map { Player(name: "S\($0)", skill: 3) })
        fresh.courts = [Court(name: "C1", format: .doubles)]
        var saved = fresh
        for i in saved.players.indices { saved.players[i].since = Date(); saved.players[i].credit = i.isMultiple(of: 2) ? 7 : nil }
        let a = run(fresh, minutes: 30, length: 600...840, late: [], arrival: 3600, seed: 1)
        let b = run(saved, minutes: 30, length: 600...840, late: [], arrival: 3600, seed: 1)
        assert(a.games.map { ($0.a + $0.b).map(\.name) } == b.games.map { ($0.a + $0.b).map(\.name) } && a.waits == b.waits, "saved timestamps and arrival credits must not change a fresh simulated night")
        assert(a.games.contains { $0.a.map(\.skill) != $0.initialA.map(\.skill) || $0.b.map(\.skill) != $0.initialB.map(\.skill) }, "simulated match ratings update independently from starting strength")
        fresh.players = Array(fresh.players.prefix(5))
        let closing = run(fresh, minutes: 1, length: 600...840, late: [], arrival: 3600, seed: 1)
        assert(closing.neverPlayed.count == 1 && closing.unfinished.count == 1 && closing.unfinished.values.first == 1, "an unserved player is included in unfinished waits at closing")
    }

    /// Everyone present from the start; courts refill the moment they free up. Game lengths are drawn from
    /// `lengths`; winners are drawn from each side's starting rating (their "true" strength, which stays fixed).
    static func run(_ start: SessionState, minutes: Double, length: ClosedRange<TimeInterval>, late: Set<String>, arrival: TimeInterval,
                    seed: UInt64) -> Night {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var s = start
        s.results = []
        s.tournament = nil
        s.courts = s.courts.map { Court(id: $0.id, name: $0.name, format: $0.format) }
        s.players = s.players.enumerated().map { n, p in
            var q = p; q.readyAt = t0.addingTimeInterval(Double(n) * 0.001); q.first = nil; q.paused = false; q.away = nil; q.since = nil; q.credit = nil; return q
        }
        // Latecomers join `arrival` seconds in, added the way the app adds someone who turns up.
        let latecomers = s.players.filter { late.contains($0.name) }
        s.players.removeAll { late.contains($0.name) }
        var truth = Dictionary(uniqueKeysWithValues: s.players.map { ($0.id, $0.skill) })
        var arrived = latecomers.isEmpty
        let arriveAt = t0.addingTimeInterval(arrival)
        func strength(_ ids: [UUID]) -> Double { ids.map { truth[$0]! }.reduce(0, +) / Double(ids.count) }
        var rng = SeededRandom(seed: seed)
        var night = Night(), ends: [UUID: (end: Date, game: Int)] = [:], lastEnd: [UUID: Date] = [:], t = t0
        var waitingSince: [UUID: (games: Int, average: Double)] = Dictionary(uniqueKeysWithValues: s.players.map { ($0.id, (0, 0)) })
        while true {
            SessionState.simulatedNow = t
            if !arrived && t >= arriveAt {
                let average = Double(s.players.map { s.played($0.id) }.reduce(0, +)) / Double(s.players.count)
                for p in latecomers {
                    s.addPlayer(p.name, skill: p.skill)
                    let id = s.players.last!.id
                    truth[id] = p.skill
                    lastEnd[id] = t
                    waitingSince[id] = (0, average)
                }
                arrived = true
            }
            if t < t0.addingTimeInterval(minutes * 60) {
                for c in s.courts where c.match == nil {
                    guard let p = s.nextPairing(for: c) else { continue }
                    let ids = (p.a + p.b).map(\.id)
                    assert(Set(ids).count == ids.count && s.onCourt.isDisjoint(with: ids), "a player was booked twice")
                    let length = Double.random(in: length, using: &rng)
                    for q in p.a + p.b {
                        let wait = t.timeIntervalSince(lastEnd[q.id] ?? t0) / 60
                        night.waits[q.name, default: []].append(wait)
                        if wait >= 35, let w = waitingSince[q.id] {
                            night.long.append(LongWait(name: q.name, skill: truth[q.id]!, minutes: wait, from: (lastEnd[q.id] ?? t0).timeIntervalSince(t0) / 60,
                                                       to: t.timeIntervalSince(t0) / 60, games: w.games, groupAverage: w.average))
                        }
                    }
                    night.games.append(Game(minute: t.timeIntervalSince(t0) / 60, length: length / 60, court: c.name,
                                            a: p.a.map { ($0.name, $0.skill) }, b: p.b.map { ($0.name, $0.skill) },
                                            initialA: p.a.map { ($0.name, truth[$0.id]!) }, initialB: p.b.map { ($0.name, truth[$0.id]!) },
                                            note: p.note, straightBack: (p.a + p.b).filter { lastEnd[$0.id] == t }.map(\.name)))
                    s.fill(c.id, at: t)
                    ends[c.id] = (t.addingTimeInterval(length), night.games.count - 1)
                }
            }
            let soonest = ends.min(by: { $0.value.end < $1.value.end })
            if !arrived, soonest.map({ arriveAt <= $0.value.end }) ?? true { t = arriveAt; continue }
            guard let (cid, next) = soonest, let m = s.courts.first(where: { $0.id == cid })?.match else {
                if t < t0.addingTimeInterval(minutes*60), s.courts.contains(where: { s.eligible($0.format).count >= $0.format.needed }) { t=t.addingTimeInterval(30); continue }
                break
            }
            let pA = 1 / (1 + pow(10, (strength(m.teamB) - strength(m.teamA)) / SessionState.ratingSpread))
            let aWon = Double.random(in: 0..<1, using: &rng) < pA
            night.games[next.game].aWon = aWon
            s.finish(cid, winner: aWon ? 0 : 1, at: next.end)
            for id in m.teamA + m.teamB { lastEnd[id] = next.end }
            let average = Double(s.players.map { s.played($0.id) }.reduce(0, +)) / Double(s.players.count)
            for id in m.teamA + m.teamB { waitingSince[id] = (s.played(id), average) }
            ends[cid] = nil
            t = next.end
        }
        // Include players still waiting at closing; they never appear in a completed-wait sample.
        for p in s.players {
            let mine = night.games.filter { ($0.a + $0.b).contains { $0.name == p.name } }
            if mine.isEmpty { night.neverPlayed.append(p.name) }
            guard !mine.contains(where: { $0.minute < minutes && $0.minute + $0.length > minutes }) else { continue }
            let last = mine.map { $0.minute + $0.length }.filter { $0 <= minutes }.max() ?? (late.contains(p.name) ? arrival / 60 : 0)
            night.unfinished[p.name] = max(0, minutes - last)
        }
        SessionState.simulatedNow = nil
        return night
    }

    /// `-waitsweep`: the longest waits and game quality for several overdue triggers, 2 doubles courts, 3 hours.
    /// Writes Documents/sim-waitsweep.md.
    static func waitSweep() {
        guard let store = input() else { return }
        var base = store.current
        base.courts = (1...2).map { Court(name: "Court \($0)", format: .doubles) }
        let runs = 30, length: ClosedRange<TimeInterval> = 10 * 60...14 * 60, keep = SessionState.waitPriority
        func mean(_ x: [Double]) -> Double { x.isEmpty ? 0 : x.reduce(0, +) / Double(x.count) }
        func f(_ x: Double) -> String { String(format: "%.1f", x) }
        var out = "# Overdue trigger: \(base.players.count) players, 2 doubles courts, 3 hours, \(runs) nights per row\n\n"
        out += "| Overdue from | Longest wait | Waits over 30 min | Waits 25–30 min | Average wait | Overdue games | All four within 1 level | Over 2 levels | Team gap |\n|---|---|---|---|---|---|---|---|---|\n"
        for minutes in [40.0, 30, 25, 22, 20] {
            SessionState.waitPriority = minutes * 60
            let nights = (1...UInt64(runs)).map { run(base, minutes: 180, length: length, late: [], arrival: 0, seed: $0) }
            var longest: [Double] = [], over30: [Double] = [], near30: [Double] = [], avg: [Double] = [], overdue: [Double] = [],
                within1: [Double] = [], over2: [Double] = [], gap: [Double] = []
            for n in nights {
                var lastEnd: [String: Double] = [:], waits: [Double] = []
                for g in n.games.sorted(by: { $0.minute < $1.minute }) {
                    for p in g.a + g.b { waits.append(g.minute - (lastEnd[p.name] ?? 0)); lastEnd[p.name] = g.minute + g.length }
                }
                longest.append(waits.max() ?? 0); over30.append(Double(waits.filter { $0 > 30 }.count))
                near30.append(Double(waits.filter { $0 > 25 && $0 <= 30 }.count)); avg.append(mean(waits))
                overdue.append(Double(n.games.filter { $0.note?.contains("waited") == true }.count))
                within1.append(Double(n.games.filter { $0.spread <= 1 + 1e-9 }.count) / Double(max(1, n.games.count)))
                over2.append(Double(n.games.filter { $0.spread > 2 + 1e-9 }.count))
                gap.append(mean(n.games.map(\.gap)))
            }
            out += "| \(Int(minutes)) min | \(Int(longest.max() ?? 0)) min (night avg \(f(mean(longest)))) | \(f(mean(over30))) a night | \(f(mean(near30))) | \(f(mean(avg))) min | \(f(mean(overdue))) | \(Int((mean(within1) * 100).rounded()))% | \(f(mean(over2))) a night | \(String(format: "%.2f", mean(gap))) |\n"
        }
        SessionState.waitPriority = keep
        try? out.write(to: URL.documentsDirectory.appending(path: "sim-waitsweep.md"), atomically: true, encoding: .utf8)
        print(out)
    }

    /// `-parity` (with `-courts N`, optional `-locks "A,B;C,D"`): one night with nothing random (game k lasts 10 + k % 5 minutes,
    /// the side with the higher starting ratings wins), written to Documents/parity.txt as the lineups in order, to compare
    /// line by line with the web version playing the same night (tools/web-sim.js --parity).
    static func parity() {
        guard var s = input()?.current else { return }
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-queue-matching"), i + 1 < args.count, let mode = QueueMatching(rawValue: args[i+1]) { s.queueMatching = mode }
        let courts = args.firstIndex(of: "-courts").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 3
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        s.results = []; s.tournament = nil
        s.courts = (1...courts).map { Court(name: "Court \($0)", format: .doubles) }
        s.players = s.players.enumerated().map { n, p in
            var q = p; q.readyAt = t0.addingTimeInterval(Double(n) * 0.001); q.since = nil; q.first = nil; q.paused = false; q.away = nil; q.credit = nil; q.lock = nil; return q
        }
        if let i = args.firstIndex(of: "-locks"), i + 1 < args.count { // locked teammates
            for pair in args[i + 1].split(separator: ";") {
                let n = pair.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if n.count == 2, let a = s.players.first(where: { $0.name == n[0] }), let b = s.players.first(where: { $0.name == n[1] }) { s.setLock(a.id, b.id) }
            }
        }
        s.scheduled = nil; s.scheduleUnlocked = nil; s.ended = nil
        if let i = args.firstIndex(of: "-scheduled"), i + 1 < args.count {
            s.hours = 3; SessionState.simulatedNow = t0
            for item in args[i+1].split(separator: ";") {
                let sides = item.split(separator: "|").map { $0.split(separator: ",").compactMap { name in s.players.first { $0.name == name.trimmingCharacters(in: .whitespaces) }?.id } }
                if sides.count == 2 { _ = s.scheduleMatch(.doubles, a: sides[0], b: sides[1]) }
            }
        }
        let truth = Dictionary(uniqueKeysWithValues: s.players.map { ($0.id, $0.skill) })
        let draws = (try? Data(contentsOf: URL.documentsDirectory.appending(path: "draws.json"))).flatMap { try? JSONDecoder().decode([[Double]].self, from: $0) }
        var t = t0, ends: [Int: Date] = [:], lines: [String] = [], k = 0, winners: [Int: Bool] = [:]
        while true {
            SessionState.simulatedNow = t
            if t < t0.addingTimeInterval(180 * 60) {
                for (ci, c) in s.courts.enumerated() where c.match == nil {
                    let line = s.eligible(.doubles), locks = s.lockContext(line), held = Set(locks.flatMap { [$0.x, $0.y] })
                    for l in locks where !l.apart {
                        guard let x = s.player(l.x), let y = s.player(l.y) else { continue }
                        let others = line.filter { !held.contains($0.id) }
                        let best = others.indices.dropFirst().flatMap { j in (0..<j).map { i in [others[i], others[j]] } }
                            .max { s.averageSkill($0.map(\.id)) < s.averageSkill($1.map(\.id)) }
                        if let best, t.timeIntervalSince(s.waitStart(x)) < SessionState.waitCap,
                           s.averageSkill(best.map(\.id)) < (x.skill + y.skill) / 2 - SessionState.lockEqual {
                            lines.append("\(Int(t.timeIntervalSince(t0) / 60)) \(c.name): WAIT \(x.name)+\(y.name) avg \(String(format: "%.2f", (x.skill + y.skill) / 2)); strongest free pair \(best.map(\.name).joined(separator: "+")) avg \(String(format: "%.2f", s.averageSkill(best.map(\.id))))")
                        }
                    }
                    guard let p = s.nextPairing(for: c) else { continue }
                    lines.append("\(Int(t.timeIntervalSince(t0) / 60)) \(c.name): \(p.a.map(\.name).joined(separator: "+")) v \(p.b.map(\.name).joined(separator: "+"))" + (p.note.map { " [\($0)]" } ?? ""))
                    s.fill(c.id, at: t)
                    let d = draws.map { $0[k % $0.count] }
                    ends[ci] = t.addingTimeInterval((d?[0] ?? Double(10 + k % 5)) * 60)
                    if let u = d?[1] {
                        let strength = { (ids: [UUID]) in ids.map { truth[$0]! }.reduce(0, +) / Double(ids.count) }
                        winners[ci] = u < 1 / (1 + pow(10, (strength((p.b).map(\.id)) - strength((p.a).map(\.id))) / SessionState.ratingSpread))
                    }
                    k += 1
                }
            }
            guard let (ci, end) = ends.min(by: { ($0.value, $0.key) < ($1.value, $1.key) }) else {
                if t < t0.addingTimeInterval(180*60), s.courts.contains(where: { s.eligible($0.format).count >= $0.format.needed }) { t=t.addingTimeInterval(30); continue }
                break
            }
            t = end; ends[ci] = nil
            SessionState.simulatedNow = t
            let m = s.courts[ci].match!
            let a = m.teamA.map { truth[$0]! }.reduce(0, +), b = m.teamB.map { truth[$0]! }.reduce(0, +)
            s.finish(s.courts[ci].id, winner: winners[ci].map { $0 ? 0 : 1 } ?? (a >= b ? 0 : 1), at: t)
            winners[ci] = nil
            lines.append("  = " + (m.teamA + m.teamB).compactMap { id in s.player(id).map { "\($0.name) \(String(format: "%.4f", $0.skill))" } }.joined(separator: ", "))
        }
        SessionState.simulatedNow = nil
        try? lines.joined(separator: "\n").write(to: URL.documentsDirectory.appending(path: "parity.txt"), atomically: true, encoding: .utf8)
    }

    /// Documents/sim-input.json if present, else the saved sessions.
    static func input() -> Store? {
        let input = URL.documentsDirectory.appending(path: "sim-input.json")
        guard let d = try? Data(contentsOf: FileManager.default.fileExists(atPath: input.path) ? input : Store.url) else { return nil }
        return try? JSONDecoder().decode(Store.self, from: d)
    }

    /// `-bench`: what one screen update and one shuffle cost with the saved players on 2 courts after an hour of games.
    /// Writes Documents/bench.txt.
    static func bench() {
        guard var s = input()?.current else { return }
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        s.results = []; s.tournament = nil
        s.courts = (1...2).map { Court(name: "Court \($0)", format: .doubles) }
        s.players = s.players.enumerated().map { n, p in var q = p; q.readyAt = t0.addingTimeInterval(Double(n)); q.since = nil; q.paused = false; q.away = nil; return q }
        var t = t0
        for g in 0..<10 { // an hour of games, so repeat and rest rules have history to check
            SessionState.simulatedNow = t
            for c in s.courts where c.match == nil { s.fill(c.id, at: t) }
            t += 6 * 60
            s.finish(s.courts[g % 2].id, winner: g % 2, at: t)
        }
        SessionState.simulatedNow = t
        let clock = ContinuousClock(), runs = 20
        let screen = clock.measure { for _ in 0..<runs { _ = s.openCourtPairings(s.upNext) } } / runs // what one screen update computes
        let tap = clock.measure { for _ in 0..<runs { var x = s; x.shuffle(x.courts.first { $0.match == nil }!.id); _ = x.upNext } } / runs
        let out = "players \(s.players.count), games \(s.results.count)\nscreen update (every court's next game + Up Next): \(screen)\nshuffle tap: \(tap)\n"
        try? out.write(to: URL.documentsDirectory.appending(path: "bench.txt"), atomically: true, encoding: .utf8)
        print(out)
        SessionState.simulatedNow = nil
    }

    static func main() {
        let dir = URL.documentsDirectory
        guard let store = input() else { print("SIM: no saved sessions"); return }
        let real = store.current
        let runs = 30, length: ClosedRange<TimeInterval> = 10 * 60...14 * 60, arrival: TimeInterval = 60 * 60
        let args = ProcessInfo.processInfo.arguments
        // With -latecomers: four latecomers, one from each part of the ratings (2nd, 8th, 14th and 20th strongest).
        let ranked = real.players.sorted { $0.skill > $1.skill }
        let late = args.contains("-latecomers") ? Set([1, 7, 13, 19].filter { $0 < ranked.count }.map { ranked[$0].name }) : []
        let courts = args.firstIndex(of: "-courts").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 3
        let configs: [(name: String, courts: Int, minutes: Double)] = [("2 courts", 2, 180), ("\(courts) courts", courts, 180)]
        let results = configs.map { c -> [Night] in
            var start = real
            start.courts = (1...c.courts).map { Court(name: "Court \($0)", format: .doubles) }
            return (1...runs).map { run(start, minutes: c.minutes, length: length, late: late, arrival: arrival, seed: UInt64($0)) }
        }
        let (before, after) = (results[0], results[1])
        let shown = [0, 1]

        func mean(_ x: [Double]) -> Double { x.isEmpty ? 0 : x.reduce(0, +) / Double(x.count) }
        func f(_ x: Double, _ digits: Int = 1) -> String { String(format: "%.\(digits)f", x) }
        func clock(_ minute: Double) -> String { String(format: "%d:%02d", Int(minute) / 60, Int(minute.rounded(.down)) % 60) }
        func team(_ side: Side) -> String { side.map { "\($0.name) \(f($0.skill))" }.joined(separator: " + ") }
        func pair(_ x: String, _ y: String, _ sep: String) -> String { [x, y].sorted().joined(separator: sep) }
        let names = real.players.map(\.name), skill = Dictionary(uniqueKeysWithValues: real.players.map { ($0.name, $0.skill) })
        let fixedPartners = Set(real.lockedPairs.map { pair(real.player($0.0)!.name, real.player($0.1)!.name, " & ") })

        /// Per night: partner pairs and opponent pairs with counts, repeated partnerships, and rematches of the same four.
        func pairing(_ n: Night) -> (partners: [String: Int], opponents: [String: Int], repeatTeams: Int, rematches: Int) {
            var partners: [String: Int] = [:], opponents: [String: Int] = [:], fours = Set<String>(), repeatTeams = 0, rematches = 0
            for g in n.games where g.a.count == 2 {
                for side in [g.a, g.b] {
                    let k = pair(side[0].name, side[1].name, " & ")
                    if partners[k] != nil { repeatTeams += 1 }
                    partners[k, default: 0] += 1
                }
                for x in g.a { for y in g.b { opponents[pair(x.name, y.name, " vs "), default: 0] += 1 } }
                let four = (g.a + g.b).map(\.name).sorted().joined(separator: ",")
                if !fours.insert(four).inserted { rematches += 1 }
            }
            return (partners, opponents, repeatTeams, rematches)
        }
        func summary(_ nights: [Night]) -> [String] {
            let games = nights.flatMap(\.games), doubles = games.filter { $0.a.count == 2 }
            let counts = nights.map { n in names.map { name in n.games.filter { ($0.a + $0.b).contains { $0.name == name } }.count } }
            let waits = nights.flatMap { $0.waits.values.flatMap { $0 } }
            let p = nights.map(pairing)
            let share = { (x: Int) in f(100 * Double(x) / Double(max(1, doubles.count)), 0) + "%" }
            let firsts = nights.flatMap { n in late.compactMap { n.waits[$0]?.first } }
            let gamesOf = { (n: Night, name: String) in Double(n.games.filter { ($0.a + $0.b).contains { $0.name == name } }.count) }
            let lateGames = nights.flatMap { n in late.map { gamesOf(n, $0) } }
            let onTimeGames = nights.flatMap { n in names.filter { !late.contains($0) }.map { gamesOf(n, $0) } }
            return [
                f(Double(games.count) / Double(runs)),
                "\(f(mean(counts.map { Double($0.min() ?? 0) }))) to \(f(mean(counts.map { Double($0.max() ?? 0) })))",
                share(doubles.filter { $0.spread <= 1.0001 }.count),
                share(doubles.filter { $0.spread <= 1.5001 }.count),
                "avg \(f(mean(doubles.map(\.spread)), 2)), worst \(f(doubles.map(\.spread).max() ?? 0))",
                "avg \(f(mean(doubles.filter { $0.note?.contains("mixed teams") == true }.map(\.spread)), 2))",
                "avg \(f(mean(games.map(\.gap)), 2)), worst \(f(games.map(\.gap).max() ?? 0, 2))",
                share(doubles.filter { $0.note?.contains("wider skill range for new partners") == true }.count),
                share(doubles.filter { $0.note?.contains("wider skill range so nobody") == true }.count),
                share(doubles.filter { $0.note?.contains("mixed teams for new partners") == true }.count),
                share(doubles.filter { $0.note?.contains("mixed teams so nobody") == true }.count),
                share(doubles.filter { $0.note?.contains("no similar group free") == true }.count),
                share(doubles.filter { $0.note?.contains("waited") == true }.count),
                f(mean(p.map { Double($0.repeatTeams) })),
                f(mean(p.map { Double($0.rematches) })),
                f(mean(p.map { Double($0.opponents.values.max() ?? 0) })),
                f(mean(p.map { Double($0.partners.count) }), 0),
                "avg \(f(mean(waits))) min, longest \(f(waits.max() ?? 0, 0)) min",
                f(Double(waits.filter { $0 >= 35 }.count) / Double(runs)),
                f(Double(waits.filter { $0 >= 45 }.count) / Double(runs)),
                f(Double(games.map(\.straightBack.count).reduce(0, +)) / Double(runs)),
                "avg \(f(mean(firsts))) min, longest \(f(firsts.max() ?? 0, 0)) min",
                "\(f(mean(lateGames))) vs \(f(mean(onTimeGames)))",
                "\(f(nights.flatMap { $0.unfinished.values }.max() ?? 0, 0)) min",
                f(mean(nights.map { Double($0.neverPlayed.count) })),
                f(mean(p.map { Double($0.partners.filter { !fixedPartners.contains($0.key) }.values.map { max(0, $0 - 1) }.reduce(0, +)) })),
            ]
        }
        let rows = ["Games per night", "Average lowest–highest games per player", "All four within 1 level", "All four within 1.5 levels", "Rating range on a court",
                    "Rating range in mixed games", "Gap between the teams", "Widened to 1.5 for new partners",
                    "Widened so nobody goes straight back", "Mixed teams for new partners", "Mixed teams so nobody goes straight back",
                    "Mixed teams, no similar group free", "Games with a 25+ minute wait note", "Repeat partnerships including locked teams",
                    "Same four again per night", "Most-played opponent pair (times a night)", "Different partner pairs per night",
                    "Wait between games", "Waits of 35+ min per night", "Waits of 45+ min per night", "Straight back on court (times a night)",
                    "Latecomers' wait for their first game", "Games per latecomer vs on-time player", "Longest unfinished wait at closing", "Players never selected (per night)", "Repeat partnerships excluding locked teams"]
        let table = results.map(summary)

        var out = "# Simulated nights: \(names.count) players, doubles, " + configs.map { "\($0.courts) courts (\(Int($0.minutes / 60)) hours)" }.joined(separator: " vs ") + "\n\n"
        out += "Games last 10–14 min (evenly spread) · " + (late.isEmpty ? "everyone there from the start" : "\(late.sorted { (skill[$0] ?? 0) > (skill[$1] ?? 0) }.map { "\($0) \(f(skill[$0] ?? 0))" }.joined(separator: ", ")) arrive 60 minutes late")
        out += " · \(runs) nights each way, same random draws · winners drawn from ratings\n\n"
        out += "Rules as in the app: similar skill within 1 level, 1.5 for new partners, balanced teams from the nearest ratings; "
        out += "balanced recalls may be at most one counted game ahead; general overdue priority and repeat-driven group selection are paused. Fresh nights clear old wait timestamps and arrival credits. Match quality uses ratings at match time; fixed starting strength is used only to draw winners. Game-count ranges average each night’s minimum and maximum.\n\n"
        out += "## Summary (average of \(runs) nights)\n\n| | " + configs.map(\.name).joined(separator: " | ") + " |\n|---|" + String(repeating: "---|", count: configs.count) + "\n"
        for (i, r) in rows.enumerated() {
            if late.isEmpty && r.lowercased().contains("latecomer") { continue }
            out += "| \(r) | " + table.map { $0[i] }.joined(separator: " | ") + " |\n"
        }

        // How the latecomers fared
        if !late.isEmpty {
        for (c, nights) in shown.map({ (configs[$0], results[$0]) }) {
            out += "\n## Latecomers: \(c.name)\n\n| Player | Rating | First game after arriving | Longest first wait | Games | Straight onto a court |\n|---|---|---|---|---|---|\n"
            for name in late.sorted(by: { (skill[$0] ?? 0) > (skill[$1] ?? 0) }) {
                let firsts = nights.compactMap { $0.waits[name]?.first }
                let games = nights.map { n in Double(n.games.filter { ($0.a + $0.b).contains { $0.name == name } }.count) }
                out += "| \(name) | \(f(skill[name] ?? 0)) | avg \(f(mean(firsts))) min | \(f(firsts.max() ?? 0, 0)) min | \(f(mean(games))) | \(firsts.filter { $0 < 0.5 }.count) of \(runs) nights |\n"
            }
        }

        }

        // Who waited longest, and why
        for (v, nights) in shown.map({ (configs[$0], results[$0]) }) {
            let long = nights.enumerated().flatMap { n, night in night.long.map { (night: n + 1, w: $0) } }
            out += "\n## Longest waits: \(v.name)\n\n"
            out += "\(long.count) waits of 35+ minutes across \(runs) nights (\(f(Double(long.count) / Double(runs))) a night).\n\n"
            out += "| Player | Wait | Night | From–to |\n|---|---|---|---|\n"
            for x in long.sorted(by: { $0.w.minutes > $1.w.minutes }).prefix(8) {
                out += "| \(x.w.name) \(f(x.w.skill)) | \(f(x.w.minutes, 0)) min | \(x.night) | \(clock(x.w.from))–\(clock(x.w.to)) |\n"
            }
            let byPlayer = Dictionary(grouping: long, by: { $0.w.name }).mapValues(\.count).sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            out += "\nMost often (35+ min waits over \(runs) nights): " + byPlayer.prefix(8).map { "\($0.key) \(f(skill[$0.key] ?? 0)) ×\($0.value)" }.joined(separator: ", ") + "\n"
            let ahead = long.filter { Double($0.w.games) > $0.w.groupAverage + 0.3 }.count
            out += "\n\(long.isEmpty ? 0 : 100 * ahead / long.count)% of these began when the player had already played more games than the group average.\n"
        }

        let one = after[0]
        out += "\n## Night 1 (\(configs[1].name)): matches by court\n\nTeam averages below are the ratings used when the game started. **Bold teams won.**\n"
        for court in Set(one.games.map(\.court)).sorted() {
            out += "\n### \(court)\n\n| Start | Team A · average | Team B · average | Gap |\n|---|---|---|---|\n"
            for g in one.games where g.court == court {
                let a = g.a.map(\.name).joined(separator: " & ") + " · " + f(avg(g.a), 2)
                let b = g.b.map(\.name).joined(separator: " & ") + " · " + f(avg(g.b), 2)
                out += "| \(clock(g.minute)) | \(g.aWon ? "**" + a + "**" : a) | \(g.aWon ? b : "**" + b + "**") | \(f(g.gap, 2)) |\n"
            }
        }
        let explained = one.games.filter { $0.note != nil || !$0.straightBack.isEmpty }
        out += "\n### Queue decisions\n\n"
        for g in explained {
            let note = ([g.note].compactMap { $0 } + (g.straightBack.isEmpty ? [] : ["immediate return: " + g.straightBack.joined(separator: ", ")])).joined(separator: "; ")
            out += "- \(clock(g.minute)) · \(g.court): \(note)\n"
        }
        out += "\n## Night 1 (\(configs[1].name)): each player\n\n| Player · starting rating | Games | Won | Longest wait |\n|---|---|---|---|\n"
        for name in names.sorted(by: { (skill[$0] ?? 0, $1) > (skill[$1] ?? 0, $0) }) {
            let mine = one.games.filter { ($0.a + $0.b).contains { $0.name == name } }
            let won = mine.filter { g in (g.aWon ? g.a : g.b).contains { $0.name == name } }.count
            out += "| \(name) · \(f(skill[name] ?? 0)) | \(mine.count) | \(won) | \(f(max(one.waits[name]?.max() ?? 0, one.unfinished[name] ?? 0), 0)) min |\n"
        }

        func totals(_ nights: [Night], _ key: KeyPath<(partners: [String: Int], opponents: [String: Int], repeatTeams: Int, rematches: Int), [String: Int]>) -> [String: Int] {
            nights.map(pairing).map { $0[keyPath: key] }.reduce(into: [:]) { acc, m in for (k, v) in m { acc[k, default: 0] += v } }
        }
        func top(_ afterPairs: [String: Int], _ beforePairs: [String: Int]) -> String {
            afterPairs.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(10)
                .map { "| \($0.key) | \(f(Double(beforePairs[$0.key] ?? 0) / Double(runs))) | \(f(Double($0.value) / Double(runs))) |" }.joined(separator: "\n")
        }
        let (pa, pb, oa, ob) = (totals(after, \.partners), totals(before, \.partners), totals(after, \.opponents), totals(before, \.opponents))
        out += "\n## Most frequent partners (times per night)\n\n| Pair | \(configs[0].name) | \(configs[1].name) |\n|---|---|---|\n" + top(pa, pb) + "\n"
        out += "\n## Most frequent opponents (times per night)\n\n| Pair | \(configs[0].name) | \(configs[1].name) |\n|---|---|---|\n" + top(oa, ob) + "\n"
        let everyPair = names.count * (names.count - 1) / 2
        out += "\nOver \(runs) nights, \(pb.count) (\(configs[0].name)) and \(pa.count) (\(configs[1].name)) of the \(everyPair) possible partner pairs played together at least once.\n"

        try? out.write(to: dir.appending(path: "sim-report.md"), atomically: true, encoding: .utf8)
        print(out)
    }
}
#endif

struct ScheduledMatch: Codable, Equatable, Identifiable {
    var id = UUID()
    var format: Format
    var teamA: [UUID]
    var teamB: [UUID]
    var heldAt: Date?
    var retryAt: Date?
    var activatedAt: Date?
    var returning: [UUID]?
    var readyJumpers: [UUID]?
    var idleReleased: Bool?
    var assignedCourt: UUID?
    var postponedUntil: Date?
}

extension SessionState {
    static let scheduledDefault: TimeInterval = 12 * 60
    func scheduledDuration(_ format: Format) -> TimeInterval {
        let lens = games.filter { $0.teamA.count == format.needed / 2 && $0.length > 0 }.suffix(10).map(\.length).sorted()
        guard !lens.isEmpty else { return Self.scheduledDefault }
        let m = lens.count / 2
        return lens.count % 2 == 1 ? lens[m] : (lens[m-1] + lens[m]) / 2
    }
    mutating func normalizeEnd() { if ended != nil, let last = games.map(\.end).max() { ended = last } }
    var endedLabel: String {
        guard let ended else { return "" }
        return ended.formatted(date: Calendar.current.isDate(ended, inSameDayAs: date) ? .omitted : .abbreviated, time: .shortened)
    }
    @discardableResult mutating func scheduleMatch(_ format: Format, a: [UUID], b: [UUID]) -> Bool {
        let ids = a + b
        guard isLive, tournament == nil, hours?.isFinite == true, (hours ?? 0) > 0, a.count == format.needed/2, b.count == a.count,
              Set(ids).count == format.needed, ids.allSatisfy({ id in players.contains { $0.id == id } }) else { return false }
        if scheduled == nil { scheduled = [] }
        scheduled?.append(ScheduledMatch(format: format, teamA: a, teamB: b))
        refreshSchedule(); return true
    }
    func scheduledDone(_ r: ScheduledMatch) -> Bool { games.contains { $0.scheduled == r.id } }
    func scheduledPlaying(_ r: ScheduledMatch) -> Bool { courts.contains { $0.match?.scheduled == r.id } }
    func scheduleBlock(_ r: ScheduledMatch) -> String? {
        if !isLive { return "Session ended" }
        if tournament != nil { return "Waiting for queue mode" }
        if let until = r.postponedUntil, until > Self.now { return "Postponed · \(Int(ceil(until.timeIntervalSince(Self.now)/60))) min" }
        let ids = r.teamA + r.teamB
        if ids.contains(where: { played($0) == 0 }) { return "Waiting for participants’ first game" }
        guard let end = endsAt, Self.now.addingTimeInterval(scheduledDuration(r.format)) <= end else { return "Insufficient time" }
        if ids.contains(where: { id in !players.contains { $0.id == id && $0.away != true && !$0.paused } }) { return "Waiting for players" }
        if ids.contains(where: scheduledNeedsOrdinary) { return "Waiting for an ordinary game" }
        if r.id != scheduledActive && ids.allSatisfy({ onCourt.contains($0) }) { return "Waiting for players" }
        let pinned = courts.flatMap { c in c.manual?.compactMap { $0 } ?? validPlan(c).map { $0.teamA + $0.teamB } ?? [] }
        if ids.contains(where: { pinned.contains($0) }) { return "Waiting for manual lineup" }
        if !courts.contains(where: { $0.format == r.format && $0.manual == nil && validPlan($0) == nil }) { return "Waiting for court" }
        return nil
    }
    mutating func refreshSchedule() {
        guard scheduled != nil else { scheduledActive = nil; return }
        for i in scheduled!.indices {
            scheduled![i].heldAt = nil; scheduled![i].retryAt = nil
            let r=scheduled![i],c=courts.first { $0.id == r.assignedCourt }
            if scheduledDone(r) || scheduledPlaying(r) || scheduleBlock(r) != nil || (r.teamA+r.teamB).contains(where: { onCourt.contains($0) }) || c == nil || c!.match != nil || c!.format != r.format || c!.manual != nil || validPlan(c!) != nil { scheduled![i].assignedCourt = nil }
        }
        let chosen = scheduledReservation
        if scheduledActive != chosen?.id {
            scheduledActive = chosen?.id
            if let id = chosen?.id, let i = scheduled!.firstIndex(where: { $0.id == id }) {
                scheduled![i].activatedAt = Self.now; scheduled![i].returning = []; scheduled![i].idleReleased = false; scheduled![i].readyJumpers = nil
            }
        }
        guard let id = chosen?.id, let i = scheduled!.firstIndex(where: { $0.id == id }) else { return }
        for j in scheduled!.indices where j != i { scheduled![j].assignedCourt = nil }
        let r = scheduled![i], ids = r.teamA + r.teamB, busy = ids.filter { onCourt.contains($0) }
        var returning = r.returning ?? []
        for id in busy where !returning.contains(id) { returning.append(id) }
        scheduled![i].returning = returning
        if !busy.isEmpty { scheduled![i].readyJumpers = nil; scheduled![i].assignedCourt = nil; return }
        if r.readyJumpers == nil {
            let returned = returning.compactMap { id -> (UUID, Date)? in
                guard let end = games.last(where: { ($0.teamA + $0.teamB).contains(id) })?.end, let active = r.activatedAt, end >= active else { return nil }
                return (id, end)
            }
            let last = returned.map { $0.1 }.max()
            scheduled![i].readyJumpers = returned.filter { $0.1 == last }.map { $0.0 }
        }
        if scheduled![i].assignedCourt == nil { scheduled![i].assignedCourt = courts.first { $0.match == nil && $0.format == r.format && $0.manual == nil && validPlan($0) == nil }?.id }
    }
    var scheduledReservation: ScheduledMatch? {
        let eligible: (ScheduledMatch) -> Bool = { !scheduledDone($0) && !scheduledPlaying($0) && scheduleBlock($0) == nil }
        return (scheduled ?? []).first { $0.id == scheduledActive && eligible($0) } ?? (scheduled ?? []).first(where: eligible)
    }
    func scheduledStatus(_ r: ScheduledMatch) -> String {
        if scheduledDone(r) { return "Completed" }
        if scheduledPlaying(r) { return "Playing" }
        if let blocked = scheduleBlock(r) { return blocked }
        if (r.teamA + r.teamB).contains(where: { onCourt.contains($0) }) { return "Waiting for players" }
        return scheduledReservation?.id == r.id && r.assignedCourt.flatMap(scheduledOnCourt) != nil ? "Scheduled · Locked" : "Waiting for court"
    }
    func scheduledOnCourt(_ id: UUID) -> ScheduledMatch? {
        (scheduled ?? []).first { $0.assignedCourt == id && !scheduledDone($0) && !scheduledPlaying($0) && scheduleBlock($0) == nil && !($0.teamA+$0.teamB).contains(where: { onCourt.contains($0) }) }
    }
    var scheduledLockedPlayers: Set<UUID> {
        Set((scheduled ?? []).filter { $0.assignedCourt.flatMap(scheduledOnCourt) != nil }.flatMap { $0.teamA+$0.teamB })
    }
    mutating func postponeScheduled(_ id: UUID) {
        guard let i=scheduled?.firstIndex(where: { $0.id == id }), !scheduledDone(scheduled![i]), !scheduledPlaying(scheduled![i]) else { return }
        scheduled![i].postponedUntil = Self.now.addingTimeInterval(10*60); scheduled![i].assignedCourt = nil
        if scheduledActive == id { scheduledActive = nil }; refreshSchedule()
    }
    mutating func cancelScheduled(_ id: UUID) {
        guard !courts.contains(where: { $0.match?.scheduled == id }) else { return }
        scheduled?.removeAll { $0.id == id }; refreshSchedule()
    }
}

#if DEBUG
extension SessionState {
    static func scheduledSelfCheck() {
        let oldClock = simulatedNow
        let t0 = Date(timeIntervalSinceReferenceDate: 100000)
        simulatedNow = t0
        defer { simulatedNow = oldClock }
        func fixture() -> SessionState {
            var x = SessionState(players: (0..<8).map { Player(name: "P\($0)") }, courts: [Court(name: "C1", format: .doubles), Court(name: "C2", format: .doubles)])
            x.hours = 3
            return x
        }
        func round(_ x: inout SessionState) {
            for i in stride(from: 0, to: 8, by: 4) {
                x.results.append(GameResult(teamA: Array(x.players[i..<(i+2)]).map(\.id), teamB: Array(x.players[(i+2)..<(i+4)]).map(\.id), winner: 0, court: "C1", start: t0.addingTimeInterval(-3600), end: t0.addingTimeInterval(-2880)))
            }
            x.refreshSchedule()
        }
        var x = fixture()
        let a = Array(x.players.prefix(2)).map(\.id), b = Array(x.players[2..<4]).map(\.id)
        assert(!x.scheduleMatch(.doubles, a: [a[0],a[0]], b: b), "scheduled players are distinct")
        assert(x.scheduleMatch(.doubles, a: a, b: b))
        assert(x.hours == 3, "scheduling uses the existing session length without changing it")
        assert(x.scheduledReservation == nil, "first round must complete")
        round(&x)
        let request = x.scheduled![0]
        assert(x.scheduledReservation?.id == request.id)
        let g = x.queueUpNext.first { $0.scheduled == request.id }!
        assert(g.a.map(\.id) == a && g.b.map(\.id) == b, "scheduled teams stay exact")
        let others = x.queueUpNext.filter { $0.scheduled == nil }.flatMap { $0.a + $0.b }.map(\.id)
        assert(Set(others).isDisjoint(with: Set(a+b)), "reserved players cannot be double booked")
        x.players.append(Player(name: "Late")); x.refreshSchedule()
        assert(x.scheduledReservation != nil, "late arrival does not close first-round milestone")
        x.scheduled![0].heldAt = t0; x.scheduled![0].retryAt = t0.addingTimeInterval(5000)
        simulatedNow = t0.addingTimeInterval(1440); x.refreshSchedule()
        assert(x.scheduledReservation != nil && x.scheduled![0].retryAt == nil, "holds do not expire and legacy retries are ignored")
        x.players[0].paused = true; x.refreshSchedule(); assert(x.scheduledReservation == nil)
        x.players[0].paused = false; x.refreshSchedule()
        var ready = x.queueUpNext.first { $0.scheduled != nil }!
        var ci = x.courts.firstIndex { $0.id == ready.court! }!
        x.courts[ci].manual = Array(x.players[4..<8]).map { Optional($0.id) }
        x.fill(ready.court!, shown: ready, at: now)
        assert(x.courts[ci].match == nil, "stale Start cannot replace a manual lineup")
        x.courts[ci].manual = nil; x.courts[ci].plan = nil; x.refreshSchedule()
        ready = x.queueUpNext.first { $0.scheduled != nil }!; ci = x.courts.firstIndex { $0.id == ready.court! }!
        x.fill(ready.court!, at: now); assert(x.courts[ci].match?.scheduled == request.id)
        x.undoStart(ready.court!); x.refreshSchedule(); assert(x.scheduledReservation != nil)
        ready = x.queueUpNext.first { $0.scheduled != nil }!
        x.fill(ready.court!, at: now); x.finish(ready.court!, winner: nil, at: now)
        assert(!x.scheduledDone(request), "cancelled game does not fulfill request")
        ready = x.queueUpNext.first { $0.scheduled != nil }!
        x.fill(ready.court!, at: now); x.finish(ready.court!, winner: 0, at: now)
        assert(x.scheduledDone(request) && !x.queueUpNext.contains { $0.scheduled == request.id })
        x.results[x.results.count - 1].jumpers = a
        assert(x.scheduledPenalties[a[0]] == 2, "direct scheduled return gives two priority games")
        x.results.append(GameResult(teamA: [a[0]], teamB: [b[0]], winner: 0, court: "C1", start: now))
        assert(x.scheduledPenalties[a[0]] == 1)
        x.results.append(GameResult(teamA: [a[0]], teamB: [b[0]], winner: 0, court: "C1", start: now))
        assert(x.scheduledPenalties[a[0]] == 0)
        x.deleteResult(at: x.results.count - 1); assert(x.scheduledPenalties[a[0]] == 1)
        var returns = SessionState(players: (0..<12).map { Player(name: "R\($0)") }, courts: [Court(name: "C1", format: .doubles), Court(name: "C2", format: .doubles)])
        returns.hours = 3
        let returnIDs = returns.players.map(\.id)
        for k in stride(from: 0, to: 12, by: 4) { returns.results.append(GameResult(teamA: Array(returnIDs[k..<(k+2)]), teamB: Array(returnIDs[(k+2)..<(k+4)]), winner: 0, court: "C1", start: t0.addingTimeInterval(-720), end: t0)) }
        returns.courts[0].match = Match(teamA: [returnIDs[0],returnIDs[4]], teamB: [returnIDs[5],returnIDs[6]], start: now)
        returns.courts[1].match = Match(teamA: [returnIDs[1],returnIDs[7]], teamB: [returnIDs[8],returnIDs[9]], start: now)
        assert(returns.scheduleMatch(.doubles, a: Array(returnIDs[0..<2]), b: Array(returnIDs[2..<4])))
        simulatedNow = now.addingTimeInterval(600); returns.finish(returns.courts[0].id, winner: 0, at: now)
        simulatedNow = now.addingTimeInterval(600); returns.finish(returns.courts[1].id, winner: 0, at: now)
        assert(returns.scheduledJumpers(Array(returnIDs[0..<4])) == [returnIDs[1]], "only the last direct return is penalized, not someone resting ten minutes")
        let direct = returns.queueUpNext.first { $0.scheduled != nil }!
        returns.fill(direct.court!, shown: direct, at: now); returns.finish(direct.court!, winner: 0, at: now)
        assert(returns.scheduleMatch(.doubles, a: Array(returnIDs[0..<2]), b: Array(returnIDs[2..<4])))
        assert(returns.scheduleBlock(returns.scheduled!.last!) == "Waiting for an ordinary game")
        returns.results.append(GameResult(teamA: [returnIDs[1]], teamB: [returnIDs[4]], winner: 0, court: "C1", start: now)); returns.refreshSchedule()
        assert(returns.scheduledReservation != nil, "one ordinary game opens the next scheduled request")
        simulatedNow = t0.addingTimeInterval(1440)
        var stable = fixture(); round(&stable)
        let stableIDs = stable.players.map(\.id)
        stable.players[0].away = true
        assert(stable.scheduleMatch(.doubles, a: Array(stableIDs[0..<2]), b: Array(stableIDs[2..<4])))
        assert(stable.scheduleMatch(.doubles, a: Array(stableIDs[4..<6]), b: Array(stableIDs[6..<8])))
        let held = stable.scheduledReservation!.id
        stable.players[0].away = false; stable.refreshSchedule()
        assert(stable.scheduledReservation?.id == held, "returning older requests cannot preempt an active hold")
        stable.cancelScheduled(held)
        stable.courts[0].match = Match(teamA: [stableIDs[0],stableIDs[4]], teamB: [stableIDs[5],stableIDs[6]], start: now)
        stable.refreshSchedule()
        let idle = stable.queueUpNext.first { $0.court == stable.courts[1].id }!
        assert(idle.scheduled == nil && idle.note?.contains("hold relaxed") == true)
        stable.fill(idle.court!, shown: idle, at: now)
        assert(stable.courts[1].match != nil && stable.onCourt.count == 8, "held players can fill an idle court without duplicate booking")
        simulatedNow = now.addingTimeInterval(60); stable.finish(stable.courts[0].id, winner: 0, at: now)
        assert(!stable.queueUpNext.contains { $0.court == stable.courts[0].id }, "a second idle release cannot starve the scheduled request")
        simulatedNow = now.addingTimeInterval(60); stable.finish(stable.courts[1].id, winner: 0, at: now)
        assert(stable.queueUpNext.contains { $0.scheduled != nil })
        simulatedNow = t0.addingTimeInterval(1440)

        var participantOnly = fixture()
        participantOnly.results = [GameResult(teamA: a, teamB: b, winner: 0, court: "C1", start: now.addingTimeInterval(-720), end: now)]
        // Use this fixture's IDs, leaving its other four players unplayed.
        participantOnly.players = x.players
        participantOnly.scheduled = [ScheduledMatch(format: .doubles, teamA: a, teamB: b)]
        assert(participantOnly.scheduledReservation != nil, "only requested participants need a completed game")
        x = fixture(); round(&x)
        let firstA = Array(x.players[0..<2]).map(\.id), firstB = Array(x.players[2..<4]).map(\.id)
        let laterA = Array(x.players[4..<6]).map(\.id), laterB = Array(x.players[6..<8]).map(\.id)
        x.courts[0].match = Match(teamA: firstA, teamB: firstB, start: now)
        assert(x.scheduleMatch(.doubles, a: firstA, b: firstB)); assert(x.scheduleMatch(.doubles, a: laterA, b: laterB))
        assert(x.scheduledReservation?.id == x.scheduled![1].id, "all-busy request cannot block a ready later request")
        x.courts[0].match = nil; x.scheduled = nil
        assert(x.scheduleMatch(.doubles, a: firstA, b: firstB)); assert(x.scheduleMatch(.doubles, a: laterA, b: laterB))
        let g1 = x.queueUpNext.first { $0.scheduled == x.scheduled![0].id }!
        x.fill(g1.court!, shown: g1, at: now)
        let g2 = x.queueUpNext.first { $0.scheduled == x.scheduled![1].id }!
        x.fill(g2.court!, shown: g2, at: now)
        assert(x.courts.filter { $0.match?.scheduled != nil }.count == 2, "each Start advances reservations before the next preview")
        x = fixture(); round(&x)
        assert(x.scheduleMatch(.doubles, a: Array(x.players[0..<2]).map(\.id), b: Array(x.players[2..<4]).map(\.id)))
        let preview = x.queueUpNext.first { $0.scheduled != nil }!
        simulatedNow = x.endsAt!
        x.fill(preview.court!, shown: preview, at: now)
        assert(x.onCourt.isEmpty && x.scheduledStatus(x.scheduled![0]) == "Insufficient time")
        simulatedNow = t0; x = fixture(); round(&x)
        let last = x.games.map(\.end).max()!
        x.fill(x.courts[0].id, at: now)
        x.end(at: t0.addingTimeInterval(86400))
        assert(x.ended == last, "ending tomorrow ignores cancellation timestamp")
        let data = try! JSONEncoder().encode(Store(sessions: [x]))
        let decoded = try! JSONDecoder().decode(Store.self, from: data)
        assert(decoded.sessions[0].ended == last)
        x = fixture(); x.end(at: t0); assert(x.ended == t0, "empty session retains tap time")
        x = fixture(); assert(x.scheduledDuration(.doubles) == 720)
    }
}
extension SessionState {
    static func queueSimplifiedSelfCheck() {
        let old=simulatedNow; simulatedNow=Date(timeIntervalSinceReferenceDate:1000000);defer { simulatedNow=old }
        func fixture(_ skills:[Double]=Array(repeating:3,count:8)) -> SessionState {
            var x=SessionState(players:skills.enumerated().map { Player(name:"Q\($0.offset)",skill:$0.element,readyAt:now.addingTimeInterval(Double($0.offset))) },courts:[Court(name:"C1",format:.doubles),Court(name:"C2",format:.doubles)]);x.hours=3;return x
        }
        func complete(_ x:inout SessionState){for k in stride(from:0,to:x.players.count,by:4){x.results.append(GameResult(teamA:Array(x.players[k..<(k+2)]).map(\.id),teamB:Array(x.players[(k+2)..<(k+4)]).map(\.id),winner:0,court:"C1",start:now.addingTimeInterval(-600),end:now.addingTimeInterval(-60)))};x.refreshSchedule()}
        var x=fixture(Array(repeating:3,count:4));let first=x.pick(.doubles,from:x.queue)!
        x.results.append(GameResult(teamA:first.a.map(\.id),teamB:first.b.map(\.id),winner:0,court:"C1",start:now.addingTimeInterval(-600),end:now.addingTimeInterval(-60)))
        let second=x.pick(.doubles,from:x.queue)!
        assert(Set(first.a.map(\.id)) != Set(second.a.map(\.id)) && Set(first.a.map(\.id)) != Set(second.b.map(\.id)),"repeated foursomes rotate balanced partnerships")
        for count in 4...8 {
            x=fixture(Array(repeating:3,count:count));x.courts.removeLast()
            let court=x.courts[0].id
            for game in 0..<24 {
                guard let shown=x.nextPairing(for:x.courts[0]) else { assertionFailure("small roster must keep playing");return }
                if count == 4 && game == 3 { assert(shown.rematchFallback,"four-player cooldown cannot be cleared without a fallback") }
                x.fill(court,shown:shown,at:now)
                assert(x.courts[0].match.map { Set($0.teamA+$0.teamB) } == Set((shown.a+shown.b).map(\.id)),"Start accepts the fallback preview")
                simulatedNow=now.addingTimeInterval(12*60);x.finish(court,winner:game%2,at:now)
            }
            let counts=x.players.map { x.played($0.id) }
            assert(counts.min()! > 0 && counts.max()!-counts.min()! <= 1,"small-roster games remain even")
        }
        x=fixture(Array(repeating:3,count:4));x.courts.removeLast()
        let fallbackCourt=x.courts[0].id
        for game in 0..<3 {x.fill(fallbackCourt,at:now);simulatedNow=now.addingTimeInterval(12*60);x.finish(fallbackCourt,winner:game%2,at:now)}
        x.shuffle(fallbackCourt);x.fill(fallbackCourt,shown:x.nextPairing(for:x.courts[0]),at:now)
        assert(x.courts[0].match != nil,"shuffled fallback can start")
        x.finish(fallbackCourt,winner:nil,at:now)
        let fallback=x.nextPairing(for:x.courts[0])!
        x.addPlayer("Extra",skill:3)
        assert(!x.automaticMatchupAllowed(fallback.a.map(\.id),fallback.b.map(\.id)),"normal alternatives reject a stale rematch fallback")
        x=fixture(Array(repeating:3,count:5));x.courts.removeLast();x.players[4].away=true
        let earlyID=x.players[4].id,earlyCourt=x.courts[0].id
        for game in 0..<2 {x.fill(earlyCourt,at:now);simulatedNow=now.addingTimeInterval(12*60);x.finish(earlyCourt,winner:game%2,at:now)}
        x.arrive(earlyID);assert(x.players[4].credit == nil)
        let earlyGame=x.nextPairing(for:x.courts[0])
        assert(earlyGame.map { ($0.a+$0.b).contains { $0.id == earlyID } } == true,"recall two-game returners for an early fifth arrival")
        x.fill(earlyCourt,shown:earlyGame,at:now);assert(x.courts[0].match != nil)
        func arrivalWave(_ minute: Double = 60) -> SessionState {
            var s=fixture(Array(repeating:3,count:12));let start=now,ids=s.players.map(\.id)
            for r in 0..<3 {for i in stride(from:0,to:12,by:4) where r != 2 || i != 0 {
                s.results.append(GameResult(teamA:[ids[i],ids[i+1]],teamB:[ids[i+2],ids[i+3]],winner:r%2,court:"C1",start:start.addingTimeInterval(Double(r)*60),end:start.addingTimeInterval(Double(r+1)*60)))
            }}
            simulatedNow=start.addingTimeInterval(minute*60)
            s.courts[0].match=Match(teamA:Array(ids[0..<2]),teamB:Array(ids[2..<4]),start:now)
            for i in 0..<12 {s.addPlayer("Late\(i)",skill:3)}
            return s
        }
        x=arrivalWave();x.players[12].credit=nil;assert(x.isNewcomer(x.players[12]),"arrival status is independent of credit")
        for choice in 0..<4 {
            let mixed=x.pick(.doubles,from:x.eligible(.doubles),choice:choice)!
            assert((mixed.a+mixed.b).filter(x.isNewcomer).count <= latePerGame && x.isEven(mixed.a.map(\.id),mixed.b.map(\.id)),"find balanced regulars beyond the first twelve before waiving the newcomer cap")
        }
        let mixedCourt=x.courts[1].id;x.fill(mixedCourt,shown:x.nextPairing(for:x.courts[1]),at:now)
        assert(x.courts[1].match != nil,"mixed arrival preview starts");x.undoStart(mixedCourt)
        for i in 5..<12 {x.players[i].paused=true}
        let scarce=x.pick(.doubles,from:x.eligible(.doubles))!
        assert((scarce.a+scarce.b).filter(x.isNewcomer).count > latePerGame,"one available regular cannot satisfy the newcomer cap")
        x=arrivalWave(29.99);assert(x.players.dropFirst(12).allSatisfy { !x.isNewcomer($0) && $0.credit == nil },"keep the thirty-minute grace period")
        x.players[12].since=x.started!.addingTimeInterval(lateAfter)
        assert(x.isNewcomer(x.players[12]),"the grace period ends exactly at thirty minutes")
        x=fixture([3,3.2,3.4,3.6,1.8,4.2]);let skillIDs=x.players.map(\.id)
        let near=Self.pickDoubles(x.players)!
        assert(Set((near.a+near.b).map(\.id)) == Set(skillIDs.prefix(4)),"similar stage precedes widening")
        let rested=Self.pickDoubles(x.players,justOff:Set(skillIDs[2...3]))!
        assert(Set((rested.a+rested.b).map(\.id)) == Set([skillIDs[0],skillIDs[1],skillIDs[4],skillIDs[5]]),"balanced rested group precedes narrower recalled group")
        let line=fixture([5,1,1,1,3,3]).players,off=Set(line.suffix(2).map(\.id))
        let recalled=pickDoubles(line,justOff:off)!
        assert(abs(recalled.a.map(\.skill).reduce(0,+)-recalled.b.map(\.skill).reduce(0,+))/2 <= fairGap && !(Set((recalled.a+recalled.b).map(\.id)).isDisjoint(with:off)))
        let capped=pickDoubles(line,justOff:off,games:Dictionary(uniqueKeysWithValues:line.suffix(2).map { ($0.id,2) }))!
        assert(Set((capped.a+capped.b).map(\.id)).isDisjoint(with:off),"recalls cannot be two counted games ahead")
        for (rating,allowed) in [(3.0,true),(4.75,true),(2.99,false),(4.76,false)] {x=fixture([3.5,3.5,rating,rating]);x.setLock(x.players[0].id,x.players[1].id);assert((x.pick(.doubles,from:x.queue) != nil) == allowed,"matching-rating locked band boundaries")}
        for (opponent,allowed) in [(3.0,false),(5.0,true)] {
            x=fixture([3.5,3.5,opponent,opponent]);let ids=x.players.map(\.id);x.setLock(ids[0],ids[1])
            assert((x.lockedGame(x.players,x.lockContext(x.players)[0],locks:x.lockContext(x.players)) != nil) == !allowed)
            for _ in 0..<3 { for i in 0..<2 { x.results.append(GameResult(teamA:[ids[i]],teamB:[ids[i+2]],winner:0,court:"C1",start:now.addingTimeInterval(-600),end:now.addingTimeInterval(-60))) } }
            assert(x.streakBoost(ids[0]) == 0.5 && x.streakBoost(ids[2]) == -0.5)
            assert((x.lockedGame(x.players,x.lockContext(x.players)[0],locks:x.lockContext(x.players)) != nil) == allowed,"both locked sides use streak-adjusted eligibility")
            assert(x.players.map(\.skill) == [3.5,3.5,opponent,opponent],"matching boosts do not change saved ratings")
        }
        x=fixture([5,5,2,2]);x.setLock(x.players[0].id,x.players[1].id)
        x.results=[GameResult(teamA:[x.players[0].id,x.players[2].id],teamB:[x.players[1].id,x.players[3].id],winner:0,court:"C1",start:now.addingTimeInterval(-3600),end:now.addingTimeInterval(-1800))]
        for i in x.players.indices {x.players[i].since=now.addingTimeInterval(-29*60)}
        assert(x.pick(.doubles,from:x.queue,allowIdleRelease:true) == nil);simulatedNow=now.addingTimeInterval(60);assert(x.pick(.doubles,from:x.queue) != nil)
        x=fixture();let rematchIDs=x.players.map(\.id)
        x.setLock(rematchIDs[0],rematchIDs[1]);x.setLock(rematchIDs[2],rematchIDs[3])
        func record(_ a:[Int],_ b:[Int],_ winner:Int?=0){x.results.append(GameResult(teamA:a.map { rematchIDs[$0] },teamB:b.map { rematchIDs[$0] },winner:winner,court:"C1",start:now.addingTimeInterval(-600),end:now.addingTimeInterval(-60)))}
        func rematchAllowed()->Bool { Self.keepsLocks(Array(rematchIDs[0..<2]),Array(rematchIDs[2..<4]),x.lockContext(x.players),strict:true,real:Dictionary(uniqueKeysWithValues:x.players.map { ($0.id,x.matchSkill($0.id)) })) }
        assert(rematchAllowed());record([0,1],[2,3]);assert(!rematchAllowed())
        record([4,5],[6,7]);record([4,6],[5,7]);assert(!rematchAllowed(),"unrelated games do not clear rematch cooldown")
        record([0,2],[1,3],1);record([0,3],[1,2],nil);assert(!rematchAllowed(),"one game and a cancellation do not clear cooldown")
        record([0,1],[2,4],1);assert(!rematchAllowed(),"every participant needs two other games")
        record([3],[5],1);assert(rematchAllowed(),"two completed games per participant clear cooldown")
        x.results.removeLast();assert(!rematchAllowed(),"deleting a result restores rematch cooldown")
        x=fixture();let teamIDs=x.players.map(\.id)
        func teamGame(_ a:[Int],_ b:[Int],_ winner:Int?=0){x.results.append(GameResult(teamA:a.map { teamIDs[$0] },teamB:b.map { teamIDs[$0] },winner:winner,court:"C1",start:now.addingTimeInterval(-600),end:now.addingTimeInterval(-60)))}
        func allowed()->Bool { x.automaticMatchupAllowed(Array(teamIDs[0..<2]),Array(teamIDs[2..<4])) }
        teamGame([0,1],[2,3]);assert(!allowed())
        teamGame([0,4],[2,5]);teamGame([1,6],[3,7]);assert(!allowed(),"separate games do not clear exact-team cooldown")
        teamGame([0,1],[4,5]);assert(!allowed(),"both teams need a different opponent")
        teamGame([2,3],[6,7],nil);assert(!allowed(),"cancelled games do not clear cooldown")
        teamGame([3,2],[7,6]);assert(allowed())
        x.results.removeLast();assert(!allowed(),"deleting the qualifying result restores cooldown")
        x.results[0].winner=nil;assert(allowed(),"cancelling original encounter removes its restriction")
        x=fixture();let preview=x.nextPairing(for:x.courts[0])!
        x.results.append(GameResult(teamA:preview.a.map(\.id),teamB:preview.b.map(\.id),winner:0,court:"C1",start:now.addingTimeInterval(-600),end:now.addingTimeInterval(-60)))
        x.courts[0].plan=Match(teamA:preview.a.map(\.id),teamB:preview.b.map(\.id));assert(x.validPlan(x.courts[0]) == nil)
        x.fill(x.courts[0].id,shown:preview,at:now);assert(x.courts[0].match == nil,"stale automatic rematch is rejected at Start")
        x.courts[0].manual=(preview.a+preview.b).map { Optional($0.id) };x.fill(x.courts[0].id,shown:preview,at:now);assert(x.courts[0].match != nil,"fully manual lineups retain override")
        x=fixture([2.5,3.5,4,2]);let hotIDs=x.players.map(\.id)
        for _ in 0..<3 { x.results.append(GameResult(teamA:[hotIDs[0]],teamB:[hotIDs[1]],winner:0,court:"C1",start:now.addingTimeInterval(-600),end:now.addingTimeInterval(-60))) }
        let boosted=x.players.map { p -> Player in var q=p;q.skill=x.matchSkill(p.id);return q }
        assert(x.hotColdGame(boosted,picked:boosted,overdue:[],justOff:[],maxSpread:2) != nil)
        assert(x.hotColdGame(boosted,picked:boosted,overdue:[],justOff:[],maxSpread:1) == nil,"hot/cold cannot widen the selected skill stage")
        x=fixture();complete(&x);let ids=x.players.map(\.id)
        assert(x.scheduleMatch(.doubles,a:Array(ids[0..<2]),b:Array(ids[2..<4])))
        let request=x.scheduled![0].id,court=x.scheduled![0].assignedCourt!
        x.courts.reverse();x.refreshSchedule();assert(x.scheduled![0].assignedCourt == court)
        x.shuffle(court);x.setManual(true,on:court);assert(x.courts.first { $0.id == court }!.manual == nil)
        let other=x.courts.first { $0.id != court }!.id
        x.shuffle(other);x.refreshSchedule();assert(x.scheduled![0].assignedCourt == court,"shuffling another court cannot unlock a scheduled assignment")
        let ordinary=x.nextPairing(for:x.courts.first { $0.id == other }!)!
        _=x.replace(ordinary.a[0].id,with:ids[0],on:other);assert(x.courts.first { $0.id == other }!.plan == nil)
        x.setManual(true,on:other);x.setSlot(0,to:ids[0],on:other);assert(x.courts.first { $0.id == other }!.manual![0] == nil);x.setManual(false,on:other)
        x.postponeScheduled(request);assert(x.scheduledReservation == nil && x.scheduledOnCourt(court) == nil)
        assert(x.scheduleMatch(.doubles,a:Array(ids[4..<6]),b:Array(ids[6..<8])))
        let active=x.scheduledReservation!.id;simulatedNow=now.addingTimeInterval(600);x.refreshSchedule();assert(x.scheduledReservation?.id == active)
        x.cancelScheduled(active);assert(x.scheduledReservation?.id == request && x.scheduled![0].assignedCourt != nil)
        x.players[0].paused=true;x.refreshSchedule();assert(x.scheduled![0].assignedCourt == nil)
        x.players[0].paused=false;x.refreshSchedule();let restored=try! JSONDecoder().decode(SessionState.self,from:JSONEncoder().encode(x));assert(restored.scheduled![0].assignedCourt == x.scheduled![0].assignedCourt)
    }
}

#endif
