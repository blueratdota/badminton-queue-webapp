import SwiftUI

@main
struct ShuttleQueueApp: App {
    @State private var store = Store.load()

    init() {
        #if DEBUG
        SessionState.selfCheck()
        if CommandLine.arguments.contains("-simulate") { Simulation.main() }
        if CommandLine.arguments.contains("-bench") { Simulation.bench() }
        if CommandLine.arguments.contains("-pairsweep") { Simulation.pairSweep() }
        if CommandLine.arguments.contains("-waitsweep") { Simulation.waitSweep() }
        if CommandLine.arguments.contains("-parity") { Simulation.parity() }
        #endif
    }

    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            ContentView(s: $store.current, past: $store.past)
                .onChange(of: store) { store.save() }
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
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

struct Player: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var skill = 3.0 // rating: 1 = New … 5 = Strong, nudged after every win or loss
    var pref = Preference.any
    var paused = false
    var readyAt = Date()
    var first: Bool? // moved to front by hand; cleared after their next game
    var since: Date? // when they last became free to play (arrived, came back in, finished a game); nil = readyAt
    var partner: UUID? // partner request (set on both): teamed up about every other game when a fair game allows
    var credit: Int? // games counted for queue order on arrival: the least anyone present had played, so a late arrival joins at par
    var away: Bool? // true = not here (yet): out of the line until marked present; nil = present

    /// The whole-number level shown as dots and in the skill picker.
    var level: Int { min(5, max(1, Int(skill.rounded()))) }
}

struct Match: Codable, Equatable {
    var teamA: [UUID]
    var teamB: [UUID]
    var start = Date()
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
    var tournamentLabel: String?  // e.g. "Round 2", "Upper Final"

    var length: TimeInterval { end.timeIntervalSince(start) }
}

struct Pairing {
    var format: Format
    var a: [Player]
    var b: [Player]
    var match: Int? // TMatch id in tournament mode
    var court: UUID? // the open court this game is lined up for (nil: a preview for a busy format)
    var options = 1 // how many fair alternatives the shuffle button can cycle through
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
    var current = SessionState()
    var past: [SessionState] = []

    static let url = URL.documentsDirectory.appending(path: "sessions.json")

    static func load() -> Store {
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Store.self, from: d) { return s }
        // Carry over the single session saved by the first version of the app.
        struct V1: Decodable { var players: [Player]; var courts: [Court] }
        if let d = try? Data(contentsOf: URL.documentsDirectory.appending(path: "session.json")),
           let v1 = try? JSONDecoder().decode(V1.self, from: d) {
            return Store(current: SessionState(players: v1.players, courts: v1.courts))
        }
        return Store()
    }

    func save() {
        do { try JSONEncoder().encode(self).write(to: Self.url, options: .atomic) }
        catch { print("Save failed:", error) }
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

    /// Last resort: the fairest split of these four that doesn't team up a pair waiting for its planned game.
    static func lastResortSplits(_ four: [Player], apart: [Set<UUID>]) -> [(a: [Player], b: [Player])] {
        let s = four.sorted { $0.skill > $1.skill }
        let all: [(a: [Player], b: [Player])] = [([s[0], s[3]], [s[1], s[2]]), ([s[0], s[2]], [s[1], s[3]]), ([s[0], s[1]], [s[2], s[3]])]
        func gap(_ t: (a: [Player], b: [Player])) -> Double { abs(t.a.map(\.skill).reduce(0, +) - t.b.map(\.skill).reduce(0, +)) }
        func keepsApart(_ t: (a: [Player], b: [Player])) -> Bool {
            !apart.contains { pair in pair.isSubset(of: t.a.map(\.id)) || pair.isSubset(of: t.b.map(\.id)) }
        }
        let ok = all.filter(keepsApart).sorted { gap($0) < gap($1) }
        return ok.isEmpty ? fairSplits(four) : [ok[0]]
    }

    /// The first in line (if rested) plus the three rested players, of the first 12, who make the evenest teams, however
    /// uneven; anyone overdue (the first `must`) included. nil if fewer than four are rested.
    static func restedFour(_ q: [Player], must: Int, justOff: Set<UUID>, apart: [Set<UUID>]) -> [Player]? {
        // The first in line and anyone overdue must play.
        guard !q.isEmpty, !q.prefix(max(1, must)).contains(where: { justOff.contains($0.id) }) else { return nil }
        let rested = Array(q.filter { !justOff.contains($0.id) }.prefix(12))
        guard rested.count >= 4 else { return nil }
        var best: (gap: Double, four: [Player])?
        for k in 3..<rested.count {
            for j in 2..<k {
                for i in 1..<j where (1..<must).allSatisfy([i, j, k].contains) {
                    let four = [rested[0], rested[i], rested[j], rested[k]], t = lastResortSplits(four, apart: apart)[0]
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
    static func fairFour(_ q: [Player]) -> [Player] {
        let pool = Array(q.prefix(12))
        for k in 3..<pool.count {
            for j in 2..<k {
                for i in 1..<j {
                    let four = [pool[0], pool[i], pool[j], pool[k]]
                    let best = fairSplits(four)[0]
                    if abs(best.a.map(\.skill).reduce(0, +) - best.b.map(\.skill).reduce(0, +)) / 2 <= fairGap { return four }
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
    // ponytail: a pair game's team averages may differ by at most this much; raise it if far-apart pairs miss their game
    static let pairSlack = 0.25
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
                         must: Int = 1, together: Set<UUID> = [], apart: [Set<UUID>] = [], games: [UUID: Int] = [:], heavyFirst: Bool = false,
                         allowed: ([Player]) -> Bool) -> Pick? {
        guard pool.count >= 3 else { return nil }
        var best: (key: [Int], splits: [(a: [Player], b: [Player])], penalty: Int)?
        for k in 2..<pool.count {
            for j in 1..<k {
                for i in 0..<j {
                    let picked = [pool[i], pool[j], pool[k]], four = [q[0]] + picked.map { q[$0] }
                    guard (1..<must).allSatisfy(picked.contains), allowed(four) else { continue }
                    let fair = fairSplits(four).filter { s in (together.isEmpty || [s.a, s.b].contains { together.isSubset(of: $0.map(\.id)) })
                        && !apart.contains { pair in [s.a, s.b].contains { pair.isSubset(of: $0.map(\.id)) } } }
                    guard !fair.isEmpty else { continue }
                    let splits = fair.enumerated()
                        .map { (split: $0.element, penalty: repeats($0.element.a, $0.element.b, recent), order: $0.offset) }
                        .sorted { ($0.penalty, $0.order) < ($1.penalty, $1.order) }
                    let range = four.map(\.skill).max()! - four.map(\.skill).min()!
                    // Fewest games among the other three before fewest repeats, so players at either end of the ratings
                    // aren't left behind while mid-rated players fill every game. bySpread (balanced teams): repeats past the
                    // limit, then nearest ratings in quarter levels, come before that.
                    let penalty = splits[0].penalty, off = four.filter { justOff.contains($0.id) }.count
                    let played: Int = picked.reduce(0) { $0 + (games[q[$1].id] ?? 0) }
                    let heavy: [Int] = bySpread || heavyFirst ? [penalty >= repeatLimit ? penalty : 0] : [] // heavyFirst: balanced-only mode
                    let nearest: [Int] = heavy + (bySpread ? [Int((range * 4).rounded())] : [])
                    let spreadKey: [Int] = bySpread ? [Int((range * 100).rounded())] : []
                    let key: [Int] = [off] + nearest + [played, penalty] + spreadKey + [pool[k], picked.reduce(0, +)]
                    if best.map({ key.lexicographicallyPrecedes($0.key) }) ?? true { best = (key, splits.map(\.split), splits[0].penalty) }
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
    /// `together`: two players who must be teammates (a partner request); nil if no fair game has them together.
    /// `accept`: an extra test every four must pass (a pair game's limits for the other players).
    static func pickDoubles(_ q: [Player], choice: Int = 0, recent: Recent = [:], must: Int = 1, justOff: Set<UUID> = [],
                            together: Set<UUID> = [], apart: [Set<UUID>] = [], accept: ([Player]) -> Bool = { _ in true },
                            capSpread: Double? = nil, games: [UUID: Int] = [:], balancedOnly: Bool = false) -> Pairing? {
        guard q.count >= 4, let head = q.first else { return nil }
        // How far a pick falls short: players straight off court first (rest beats skill match), then repeats past the limit.
        func shortfall(_ g: Pick?) -> [Int] {
            guard let g else { return [.max, .max] }
            return [g.justOff, g.penalty >= repeatLimit ? g.penalty : 0]
        }
        func reason(_ from: Pick?, _ to: Pick) -> String {
            (from?.justOff ?? 0) > to.justOff ? (to.justOff == 0 ? "so nobody goes straight back" : "so fewer go straight back") : "for new partners"
        }
        func similarGroup(_ spread: Double) -> Pick? {
            let near = Array(Set(1..<must).union(q.indices.dropFirst().filter { abs(q[$0].skill - head.skill) <= spread + 1e-9 }.prefix(12))).sorted()
            return bestFour(q, pool: near, recent: recent, justOff: justOff, must: must, together: together, apart: apart, games: games) { four in
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
            bestFour(q, pool: Array(1..<min(12, q.count)), recent: recent, justOff: justOff, bySpread: !balancedOnly, must: must, together: together,
                     apart: apart, games: games, heavyFirst: balancedOnly) { four in
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
        // Nobody straight back while four rested players can play: the evenest four of them, uneven teams if it must be.
        let fallback = best == nil ? fairFour(q) : []
        if together.isEmpty, (best?.justOff ?? fallback.filter { justOff.contains($0.id) }.count) > 0,
           let four = restedFour(q, must: must, justOff: justOff, apart: apart) {
            let split = lastResortSplits(four, apart: apart)[0]
            return Pairing(format: .doubles, a: split.a, b: split.b, options: 1, note: "uneven teams so nobody goes straight back")
        }
        let splits = best?.splits ?? lastResortSplits(fallback, apart: apart)
        if best == nil { note = "mixed teams, no similar group free" }
        let split = splits[choice % splits.count]
        return Pairing(format: .doubles, a: split.a, b: split.b, options: splits.count, note: note)
    }

    /// Each player's partners and opponents over their last two doubles games this session.
    func recentPairs(games: Int = 2) -> Recent {
        var out: Recent = [:], seen: [UUID: Int] = [:]
        for r in results.reversed() where r.teamA.count == 2 {
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
    /// `allowPairGame`: false when another court already has a pair game lined up (one pair game at a time).
    func pick(_ format: Format, from line: [Player], choice: Int = 0, allowPairGame: Bool = true) -> Pairing? {
        // Wait cap: everyone who has waited past it (up to a full court) plays in this game, even if they're behind in line on
        // games played. Fewest games counted first (a late arrival counts at par, so their missed games don't put them ahead), then longest wait.
        let waited = { (p: Player) in p.since ?? p.readyAt }
        let n = gamesCounted
        let overdue = Array(line.filter { Self.now.timeIntervalSince(waited($0)) >= Self.waitPriority }
            .sorted { (n[$0.id] ?? 0, waited($0)) < (n[$1.id] ?? 0, waited($1)) }.prefix(format.needed))
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
        // Ties on fewest games: whoever is hardest to match (fewest similar-level players waiting) heads the game, so the
        // strongest and weakest aren't left waiting while mid-rated players fill every game. Nobody with more games jumps ahead.
        if format == .doubles, !fresh, overdue.isEmpty, !balancedOnly, pool.count > 4, pool[0].first != true {
            let off0 = Set(results.last.map { $0.teamA + $0.teamB } ?? []), low = n[pool[0].id] ?? 0
            let tier = pool.filter { (n[$0.id] ?? 0) == low && !off0.contains($0.id) && $0.first != true }
            func similar(_ p: Player) -> Int { pool.filter { $0.id != p.id && abs($0.skill - p.skill) <= Self.similarSpread + 1e-9 }.count }
            if tier.count > 1, let h = tier.min(by: { similar($0) < similar($1) }) { pool = [h] + pool.filter { $0.id != h.id } }
        }
        pool = overdue + pool
        let turn = fresh ? 0 : choice
        let off = Set(results.last.map { $0.teamA + $0.teamB } ?? [])
        let recent = format == .doubles ? recentPairs() : [:], apart = format == .doubles ? pairsKeptApart() : [], must = max(1, overdue.count)
        let balanced = format == .doubles && balancedOnly
        let cap = overdue.isEmpty ? nil : Self.overdueSpread // an overdue game may stretch to 2 levels, balanced, at worst
        var p = format == .singles ? Self.pickSingles(pool, finishes: results.map(\.end), choice: turn)
            : Self.pickDoubles(pool, choice: turn, recent: recent, must: must, justOff: off, apart: apart, capSpread: cap, games: n, balancedOnly: balanced)
        if format == .doubles, allowPairGame, !pairGameOnCourt {
            // A waiting pair is offered first; shuffle steps through their other options, then on to the normal games.
            let normal = turn == 0 ? p : Self.pickDoubles(pool, choice: 0, recent: recent, must: must, justOff: off, apart: apart, capSpread: cap, games: n, balancedOnly: balanced)
            let pairGames = partnerGames(pool, picked: (normal.map { $0.a + $0.b } ?? []) + pool.prefix(4), overdue: overdue, justOff: off)
            if !pairGames.isEmpty {
                let total = pairGames.count + (normal?.options ?? 0), k = turn % total
                p = k < pairGames.count ? pairGames[k] : Self.pickDoubles(pool, choice: k - pairGames.count, recent: recent, must: must, justOff: off, apart: apart, capSpread: cap, games: n, balancedOnly: balanced)
                p?.options = total
            }
        }
        if fresh { p?.options = 99 } // keeps the shuffle button available
        if !overdue.isEmpty {
            let who = overdue.map(\.name).formatted(.list(type: .and))
            let earlier = p?.note
            p?.note = [earlier, "\(who) waited \(Int(Self.waitPriority / 60))+ min"].compactMap { $0 }.joined(separator: " · ")
        }
        return p
    }

    /// Partner requests: each requested pair plays one game together per session; after that they're like anyone else.
    /// When one of a waiting pair is about to play (picked anyway, or in the front four) and the other is rested and nearest the
    /// front (first 8 in line, then 12, then anyone waiting if no even game can be made), they're offered as teammates alongside whoever is
    /// first in line: up to 3 games with different other players, each with team averages within `pairSlack`. The rating
    /// range may be wider than usual so far-apart pairs still get their game. Rest first and the overdue rule come first.
    func partnerGames(_ pool: [Player], picked: [Player], overdue: [Player], justOff: Set<UUID>) -> [Pairing] {
        guard pairingActive, overdue.count <= 2 else { return [] }
        let n = gamesCounted
        for depth in [8, 12, pool.count] { // ponytail: whole line as the last try, once per pair per night
            let near = pool.prefix(depth)
            for x in picked where !justOff.contains(x.id) {
                guard let y = near.first(where: { $0.id == x.partner && $0.partner == x.id }), !justOff.contains(y.id),
                      pairWaiting(x.id, y.id) else { continue }
                var recent = recentPairs()
                for (a, b) in [(x.id, y.id), (y.id, x.id)] { recent[a]?.partners.remove(b); recent[a]?.opponents.remove(b) }
                // Whoever is first in line plays, as in any game, so nobody is skipped to fit the pair in.
                var front = overdue
                for p in pool.prefix(1) + [x, y] where !front.contains(where: { $0.id == p.id }) { front.append(p) }
                guard front.count <= 4 else { continue }
                let ids = Set(front.map(\.id))
                let even = { (four: [Player]) in // and nobody called straight back to fit the pair in
                    abs(x.skill + y.skill - four.filter { $0.id != x.id && $0.id != y.id }.map(\.skill).reduce(0, +)) / 2 <= Self.pairSlack + 1e-9
                        && !four.contains { justOff.contains($0.id) }
                }
                let otherPairs = requestedPairs.filter { $0 != [x.id, y.id] } // never another requested pair as their opponents
                var games: [Pairing] = [], used = Set<UUID>()
                while games.count < 3,
                      var g = Self.pickDoubles(front + near.filter { !ids.contains($0.id) && !used.contains($0.id) }, choice: 0, recent: recent,
                                               must: front.count, justOff: justOff, together: [x.id, y.id], apart: otherPairs, accept: even, games: n) {
                    g.note = nil // kept quiet on screen
                    games.append(g)
                    used.formUnion((g.a + g.b).map(\.id).filter { !ids.contains($0) })
                }
                if !games.isEmpty { return games }
            }
        }
        return []
    }

    /// Whether x and y have been teammates in a doubles game this session (on purpose or by chance).
    func pairPlayed(_ x: UUID, _ y: UUID) -> Bool {
        results.contains { r in r.teamA.count == 2 && [r.teamA, r.teamB].contains { $0.contains(x) && $0.contains(y) } }
    }

    /// A requested pair is waiting for its game: not played together yet, and each has played one doubles game this
    /// session (so never in their first game of the night).
    func pairWaiting(_ x: UUID, _ y: UUID) -> Bool {
        let playedDoubles = { (id: UUID) in results.contains { $0.teamA.count == 2 && ($0.teamA + $0.teamB).contains(id) } }
        return !pairPlayed(x, y) && playedDoubles(x) && playedDoubles(y)
    }

    /// One team is a requested pair that hadn't played together yet: their pair game.
    func isPairGame(_ a: [UUID], _ b: [UUID]) -> Bool {
        [a, b].contains { t in t.count == 2 && player(t[0])?.partner == t[1] && player(t[1])?.partner == t[0] && !pairPlayed(t[0], t[1]) }
    }

    /// Only one pair game at a time: is one being played now?
    var pairGameOnCourt: Bool { courts.contains { $0.match.map { isPairGame($0.teamA, $0.teamB) } ?? false } }

    /// Pair requests need enough people: twice the players one full round of courts takes, minus two
    /// (14 for 2 doubles courts, 22 for 3, 30 for 4; a singles court counts 2). Below that they're kept but on hold.
    var pairingMinimum: Int { 2 * courts.map(\.format.needed).reduce(0, +) - 2 }
    var activePlayers: Int { players.filter { !$0.paused && $0.away != true }.count } // sitting out and not here don't count
    var pairingActive: Bool { activePlayers >= pairingMinimum }
    /// All courts doubles and fewer than 8 players per court here: balanced teams instead of similar-skill groups.
    var balancedOnly: Bool { courts.allSatisfy { $0.format == .doubles } && activePlayers < 8 * courts.count }

    /// Every requested pair (two-way), whether or not they've played together.
    var requestedPairs: [Set<UUID>] {
        players.compactMap { p in
            guard let q = p.partner, player(q)?.partner == p.id, p.id.uuidString < q.uuidString else { return nil }
            return [p.id, q]
        }
    }

    /// Requested pairs that haven't played together yet: the normal matching won't make them teammates, so their game
    /// happens only as a planned, even pair game. They can still meet as opponents. After their game they're not listed.
    func pairsKeptApart() -> [Set<UUID>] {
        guard pairingActive else { return [] }
        return requestedPairs.filter { pair in let ids = Array(pair); return !pairPlayed(ids[0], ids[1]) }
    }

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
        guard let i = courts.firstIndex(where: { $0.id == courtID }), courts[i].match == nil else { return }
        // One run of the matching, only when there's another open court to pin or a locked side to keep.
        let next = courts[i].locked != nil || courts.contains(where: { $0.id != courtID && $0.match == nil }) ? openCourtPairings() : [:]
        // Keep every other court's next game as it is, so only this court changes.
        let keep = courts.indices.filter { $0 != i }.compactMap { j in
            next[courts[j].id].map { (j, Match(teamA: $0.a.map(\.id), teamB: $0.b.map(\.id))) }
        }
        for (j, m) in keep { courts[j].plan = m }
        if let side = courts[i].locked, let here = next[courts[i].id] {
            // Locked side stays; the other side steps through fair options from the front of the line, rested players first.
            let kept = (side == 0 ? here.a : here.b).map(\.id), current = Set((side == 0 ? here.b : here.a).map(\.id))
            let busy = Set(kept + keep.flatMap { $0.1.teamA + $0.1.teamB })
            let off = Set(results.last.map { $0.teamA + $0.teamB } ?? [])
            let pool = Array(eligible(courts[i].format).filter { !busy.contains($0.id) }.prefix(8).map(\.id)) // ponytail: front 8 only
            let sides = kept.count == 1 ? pool.map { [$0] }
                : pool.indices.flatMap { x in pool.indices.filter { $0 > x }.map { [pool[x], pool[$0]] } }
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
        guard let i = courts.firstIndex(where: { $0.id == courtID }), courts[i].match == nil else { return }
        if side != nil, let here = nextPairing(for: courts[i]) { courts[i].plan = Match(teamA: here.a.map(\.id), teamB: here.b.map(\.id)) }
        courts[i].locked = side
    }

    // MARK: Replacing a player in "Next up"

    /// A hand-set lineup that still stands: right size, everyone still waiting and able to play this format.
    func validPlan(_ c: Court) -> Match? {
        guard tournament == nil, c.match == nil, let p = c.plan, p.teamA.count + p.teamB.count == c.format.needed else { return nil }
        let waiting = Set(eligible(c.format).map(\.id))
        return (p.teamA + p.teamB).allSatisfy(waiting.contains) ? p : nil
    }

    /// How uneven a lineup is: rating gap in singles, gap between team averages in doubles.
    func unevenness(_ a: [UUID], _ b: [UUID]) -> Double { abs(averageSkill(a) - averageSkill(b)) }

    func isEven(_ a: [UUID], _ b: [UUID]) -> Bool {
        unevenness(a, b) <= (a.count == 1 ? Self.singlesRange : Self.fairGap) + 0.001
    }

    /// Doubles teams as given if they're even, otherwise the fairest way to split those four.
    func arranged(_ a: [UUID], _ b: [UUID]) -> (a: [UUID], b: [UUID]) {
        guard a.count == 2, !isEven(a, b) else { return (a, b) }
        let four = players(a + b)
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
        return eligible(c.format).filter { !inGame.contains($0.id) }.map { p in
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
        guard let i = courts.firstIndex(where: { $0.id == courtID }), let here = nextPairing(for: courts[i]) else { return nil }
        let other = courts.first { $0.id != courtID && (nextPairing(for: $0).map { ($0.a + $0.b).contains { $0.id == incoming } } ?? false) }
        let otherLineup = other.flatMap { nextPairing(for: $0) }
        let mine = swapped(here, out, incoming)
        courts[i].plan = Match(teamA: mine.a, teamB: mine.b)
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
        courts[j].plan = Match(teamA: pick.1.a, teamB: pick.1.b)
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
        // Hand-set lineups come first and their players are off limits to the automatic picks.
        var taken = Set(open.compactMap(validPlan).flatMap { $0.teamA + $0.teamB })
        // One pair game at a time: once one is lined up (or set by hand), the other courts get normal games.
        var pairLined = open.compactMap(validPlan).contains { isPairGame($0.teamA, $0.teamB) }
        var out: [Pairing] = open.compactMap { c in
            if let plan = validPlan(c) {
                return Pairing(format: c.format, a: players(plan.teamA), b: players(plan.teamB), court: c.id, options: 2) // shuffle returns to automatic
            }
            guard var p = pick(c.format, from: lines[c.format]!.filter { !taken.contains($0.id) }, choice: c.shuffles ?? 0,
                               allowPairGame: !pairLined) else { return nil }
            p.court = c.id
            (p.a + p.b).forEach { taken.insert($0.id) }
            if isPairGame(p.a.map(\.id), p.b.map(\.id)) { pairLined = true }
            return p
        }
        // Busy courts: who's next there once the current game ends, earliest-started court first.
        // ponytail: a guess from who's waiting now; the players coming off other courts can change it
        for c in courts.filter({ $0.match != nil }).sorted(by: { $0.match!.start < $1.match!.start }) {
            guard var p = pick(c.format, from: lines[c.format]!.filter { !taken.contains($0.id) }, choice: 0, allowPairGame: !pairLined) else { continue }
            p.court = c.id
            (p.a + p.b).forEach { taken.insert($0.id) }
            if isPairGame(p.a.map(\.id), p.b.map(\.id)) { pairLined = true }
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
        let off = Set(results.last.map { $0.teamA + $0.teamB } ?? [])
        let key = { (p: Player) in (p.first == true ? 0 : 1, off.contains(p.id) ? 1 : 0, n[p.id] ?? 0, p.readyAt) }
        return players.filter { !busy.contains($0.id) && $0.away != true }.sorted { key($0) < key($1) }
    }

    /// Games played plus any arrival credit: what "fewest games first" compares.
    var gamesCounted: [UUID: Int] {
        var n = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.credit ?? 0) })
        for r in results { for id in r.teamA + r.teamB where n[id] != nil { n[id]! += 1 } }
        return n
    }

    func eligible(_ format: Format) -> [Player] {
        queue.filter { !$0.paused && ($0.pref == .any || $0.pref.rawValue == format.rawValue) }
    }

    func player(_ id: UUID) -> Player? { players.first { $0.id == id } }

    // MARK: Stats

    func played(_ id: UUID) -> Int { results.filter { ($0.teamA + $0.teamB).contains(id) }.count }

    func wins(_ id: UUID) -> Int {
        results.filter { r in r.winner.map { ($0 == 0 ? r.teamA : r.teamB).contains(id) } ?? false }.count
    }

    // MARK: Actions

    mutating func update(_ id: UUID, _ change: (inout Player) -> Void) {
        if let i = players.firstIndex(where: { $0.id == id }) { change(&players[i]) }
    }

    mutating func fill(_ courtID: UUID, at now: Date = Date()) {
        guard let i = courts.firstIndex(where: { $0.id == courtID }),
              let p = nextPairing(for: courts[i]) else { return }
        courts[i].match = Match(teamA: p.a.map(\.id), teamB: p.b.map(\.id), start: now, tournamentMatch: p.match)
        courts[i].shuffles = nil
        courts[i].plan = nil
        courts[i].locked = nil
    }

    mutating func fillAll() { courts.map(\.id).forEach { fill($0) } }

    /// Ends the game on a court. With a winner (0 = team A, 1 = team B), moves both teams' ratings.
    mutating func finish(_ courtID: UUID, winner: Int?, at now: Date = Date()) {
        guard let i = courts.firstIndex(where: { $0.id == courtID }), let m = courts[i].match else { return }
        var r = GameResult(teamA: m.teamA, teamB: m.teamB, winner: winner, court: courts[i].name, start: m.start, end: now)
        if let tm = m.tournamentMatch, let t = tournament {
            r.tournamentLabel = t.matches[tm].label
            if let winner { recordTournament(tm, winner: winner) } // "No result" leaves the game to be replayed
        }
        if let winner {
            // Game length is a nudge: a quick (one-sided) game moves ratings up to 5% more, a long, close one up to 5% less.
            let lengths = results.filter { $0.teamA.count == m.teamA.count }.map(\.length) + [r.length]
            let s = Self.speed(r.length, among: lengths)
            let d = Self.ratingChange(teamA: averageSkill(m.teamA), teamB: averageSkill(m.teamB), aWon: winner == 0) * (1 + 0.05 * s)
            r.changes = adjust(m.teamA, by: d).merging(adjust(m.teamB, by: -d)) { $1 }
        }
        results.append(r)
        for (n, id) in (m.teamA + m.teamB).enumerated() {
            update(id) { $0.readyAt = now.addingTimeInterval(Double(n) * 0.001); $0.first = nil; $0.since = now }
        }
        courts[i].match = nil
    }

    /// Removes a game entered by mistake and undoes its rating change.
    mutating func deleteResult(at i: Int) {
        for (id, c) in results.remove(at: i).changes ?? [:] { update(id) { $0.skill -= c } }
    }

    // MARK: Ratings

    // ponytail: Elo on the 1–5 scale, win/loss only. ratingK = most one game can move a rating; ratingSpread = the level gap
    // at which the stronger side is expected to win ~90%. Tune these two if ratings move too fast or too slow.
    static let ratingK = 0.3
    static let ratingSpread = 2.0

    /// Rating change for each team A player (team B gets the negative). Winners always gain;
    /// beating a stronger side moves ratings more than beating a weaker one.
    static func ratingChange(teamA: Double, teamB: Double, aWon: Bool) -> Double {
        let expectedA = 1 / (1 + pow(10, (teamB - teamA) / ratingSpread))
        return ratingK * ((aWon ? 1 : 0) - expectedA)
    }

    /// How one-sided a game looked from its length: +1 for half the usual time or less, 0 for the usual time,
    /// −1 for half again the usual time or more. Usual is the median length of `lengths`.
    static func speed(_ length: TimeInterval, among lengths: [TimeInterval]) -> Double {
        let median = lengths.sorted()[lengths.count / 2]
        return median > 0 ? min(1, max(-1, (median - length) / (median / 2))) : 0
    }

    /// `speed` for a finished game, against this session's games of the same format.
    func speed(of r: GameResult) -> Double {
        Self.speed(r.length, among: results.filter { $0.teamA.count == r.teamA.count }.map(\.length))
    }

    /// Standings score, 0–100. A win counts 0.93–1.0 and a loss 0–0.1, more for a quicker (more one-sided) game,
    /// so records decide it and game length mostly breaks near-ties. Everyone starts with two extra wins and two extra
    /// losses so one or two lucky games can't top the table. "No result" doesn't count.
    func score(_ id: UUID) -> Double {
        var credit = 2.0, games = 4.0
        for r in results where r.winner != nil && (r.teamA + r.teamB).contains(id) {
            let s = speed(of: r)
            credit += (r.winner == 0 ? r.teamA : r.teamB).contains(id) ? 0.965 + 0.035 * s : 0.05 - 0.05 * s
            games += 1
        }
        return credit / games * 100
    }

    func averageSkill(_ ids: [UUID]) -> Double {
        let skills = ids.compactMap { player($0)?.skill }
        return skills.isEmpty ? 3 : skills.reduce(0, +) / Double(skills.count)
    }

    /// Moves ratings within 1–5 and returns what each player actually moved.
    mutating func adjust(_ ids: [UUID], by d: Double) -> [UUID: Double] {
        var applied: [UUID: Double] = [:]
        for id in ids {
            update(id) { p in
                let old = p.skill
                p.skill = min(5, max(1, old + d))
                applied[id] = p.skill - old
            }
        }
        return applied
    }

    /// Sets (or clears, with nil) a two-way partner request, ending any request either player had with someone else.
    mutating func setPartner(_ id: UUID, _ other: UUID?) {
        for i in players.indices where [id, other].contains(players[i].id) || [id, other].contains(players[i].partner) {
            players[i].partner = nil
        }
        if let other { update(id) { $0.partner = other }; update(other) { $0.partner = id } }
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
            for p in session.players { latest[p.name.lowercased()] = p }
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
        for p in returning { addPlayer(p.name, skill: p.skill) }
    }

    /// Adds someone who just arrived. They haven't played, so they go ahead of everyone waiting who has,
    /// but behind anyone who's been waiting since before them without a game yet.
    /// A newcomer goes just ahead of everyone who has played, once. They're counted as having played as many games as the
    /// least-played player who has played, so after their first game they're in the normal order instead of catching up.
    /// Before the first game, everyone added starts as not here yet; they're marked present as they arrive.
    mutating func addPlayer(_ name: String, skill: Double) {
        let p = Player(name: name, skill: skill, away: true)
        players.append(p)
        if !results.isEmpty || !onCourt.isEmpty { arrive(p.id) }
    }

    /// Marks someone present. They join the line like a late arrival: after anyone yet to play, counted at par
    /// (never below the games they've played), with their wait clock starting now.
    mutating func arrive(_ id: UUID) {
        guard let p = player(id), p.away == true else { return }
        let n = gamesCounted
        let par = players.filter { !$0.paused && $0.away != true && played($0.id) > 0 }.compactMap { n[$0.id] }.min() ?? 0
        let at = arrivalTime(), credit = max(p.credit ?? 0, par - played(id))
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
        let now = Date()
        return SessionState(
            players: keepPlayers ? players.enumerated().map { n, p in
                Player(name: p.name, skill: p.skill, readyAt: now.addingTimeInterval(Double(n) * 0.001), away: true) // marked present as they arrive
            } : [],
            courts: courts.map { Court(name: $0.name, format: $0.format) }
        )
    }

    #if DEBUG
    static func selfCheck() {
        Tournament.selfCheck()
        // Standings: 5 of 5 beats 6 of 7 at the same pace; a quick game counts as one-sided.
        var table = SessionState(players: [Player(name: "A"), Player(name: "B"), Player(name: "X")])
        let (pa, pb, px) = (table.players[0].id, table.players[1].id, table.players[2].id)
        func game(_ w: UUID, _ l: UUID, won: Bool = true, minutes: Double = 10) -> GameResult {
            GameResult(teamA: [w], teamB: [l], winner: won ? 0 : 1, court: "", start: .distantPast, end: Date.distantPast.addingTimeInterval(minutes * 60))
        }
        table.results = Array(repeating: game(pa, px), count: 6) + [game(pa, px, won: false)] + Array(repeating: game(pb, px), count: 5)
        assert(table.score(pb) > table.score(pa), "5 of 5 should rank above 6 of 7")
        table.results.append(game(pa, px, minutes: 4))
        assert(table.speed(of: table.results.last!) == 1 && table.speed(of: table.results[0]) == 0, "quick game is one-sided, usual game is neutral")
        let fastWin = table.score(pa)
        table.results[table.results.count - 1] = game(pa, px, minutes: 20)
        assert(table.score(pa) < fastWin, "a quick win should count more than a close one")
        table.results = Array(repeating: game(pb, px, minutes: 18), count: 5) + [game(pa, px)] + (0..<5).map { _ in game(UUID(), UUID()) }
        assert(table.score(pb) > table.score(pa), "5 close wins should still beat 1 win")
        table.results = Array(repeating: game(pa, px, minutes: 18), count: 4) + Array(repeating: game(pb, px, minutes: 4), count: 3)
            + [game(pb, px, won: false, minutes: 4)] + (0..<5).map { _ in game(UUID(), UUID()) }
        assert(table.score(pa) > table.score(pb), "an extra win outweighs any game length")
        // Fewer games goes first; moving to front beats that.
        var order = SessionState()
        order.players = [Player(name: "1", readyAt: .distantPast), Player(name: "2")]
        order.results = [GameResult(teamA: [order.players[0].id], teamB: [UUID()], winner: nil, court: "", start: Date())]
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
        late.results.append(GameResult(teamA: [late.players[2].id], teamB: [late.players[1].id], winner: 0, court: "C", start: Date()))
        late.update(late.players[1].id) { $0.readyAt = Date(timeIntervalSince1970: 100) }
        late.update(late.players[2].id) { $0.readyAt = Date(timeIntervalSince1970: 101) }
        late.addPlayer("New1", skill: 3)
        late.addPlayer("New2", skill: 3)
        assert(late.queue.map(\.name) == ["A", "New1", "New2", "B", "C"], "newcomers should queue ahead of players who've played")
        // A late arrival goes first once, then joins the normal order instead of catching up on games.
        var par = SessionState(players: ["X", "Y"].enumerated().map { Player(name: $0.element, readyAt: Date(timeIntervalSince1970: Double($0.offset))) })
        for _ in 0..<3 { par.results.append(GameResult(teamA: [par.players[0].id], teamB: [par.players[1].id], winner: 0, court: "C", start: Date())) }
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
        for _ in 0..<3 { mark.results.append(GameResult(teamA: [mark.players[0].id], teamB: [mark.players[1].id], winner: 0, court: "C", start: Date())) }
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
        // Partner requests: one even game together per session, never in the first game, then like anyone else.
        var duo = SessionState(players: [3.5, 3, 3, 3, 3, 3, 3, 2.5].enumerated().map { Player(name: "\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSinceNow: Double($0.offset) - 60)) })
        duo.courts = [Court(name: "C", format: .doubles)] // 8 players clear the minimum of 6 for one court
        let (dx, dy) = (duo.players[0].id, duo.players[7].id)
        duo.setPartner(dx, dy)
        assert(!duo.pairWaiting(dx, dy) && duo.pairsKeptApart() == [[dx, dy]], "start of the night: kept apart until each has played")
        for id in [dx, dy] { duo.results.append(GameResult(teamA: [id, duo.players[3].id], teamB: [duo.players[4].id, duo.players[5].id], winner: 0, court: "C", start: Date())) }
        duo.results.append(GameResult(teamA: [duo.players[1].id, duo.players[2].id], teamB: [duo.players[6].id, duo.players[4].id], winner: 0, court: "C", start: Date()))
        let duoGame = duo.pick(.doubles, from: duo.eligible(.doubles))!
        let duoGap = abs(duoGame.a.map(\.skill).reduce(0, +) - duoGame.b.map(\.skill).reduce(0, +)) / 2
        assert([duoGame.a, duoGame.b].contains { Set($0.map(\.id)) == [dx, dy] } && duoGap <= pairSlack + 1e-9, "a waiting pair gets an even game")
        assert(duoGame.options >= 2, "shuffle stays available on a pair's game")
        var hold = SessionState(players: duo.players, results: duo.results) // before their game, for the on-hold check below
        duo.results.append(GameResult(teamA: [dx, dy], teamB: [duo.players[1].id, duo.players[2].id], winner: 0, court: "C", start: Date()))
        assert(!duo.pairWaiting(dx, dy) && duo.pairsKeptApart().isEmpty
               && duo.partnerGames(duo.queue, picked: duo.queue, overdue: [], justOff: []).isEmpty, "after their game the pair is like anyone else")
        // A far-apart pair (4.9 & 3.0) still gets an even game; the range may be wider than usual.
        var wide = SessionState(players: [4.9, 4.0, 3.9, 3.5, 3.2, 3.1, 3.0, 2.8].enumerated().map { Player(name: "\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSinceNow: Double($0.offset) - 60)) })
        wide.courts = [Court(name: "C", format: .doubles)]
        let (wx, wy) = (wide.players[0].id, wide.players[6].id), w = wide.players.map(\.id)
        wide.setPartner(wx, wy)
        wide.results += [GameResult(teamA: [wx, w[7]], teamB: [w[5], w[4]], winner: 0, court: "C", start: Date()),
                         GameResult(teamA: [wy, w[7]], teamB: [w[5], w[4]], winner: 0, court: "C", start: Date())]
        let wideGames = wide.partnerGames(wide.queue, picked: wide.queue, overdue: [], justOff: [])
        assert(!wideGames.isEmpty && wideGames.allSatisfy { abs($0.a.map(\.skill).reduce(0, +) - $0.b.map(\.skill).reduce(0, +)) / 2 <= pairSlack + 1e-9 },
               "a far-apart pair still gets an even game")
        let rested = wide.partnerGames(wide.queue, picked: wide.queue, overdue: [], justOff: [wide.players[2].id])
        assert(!rested.isEmpty && !rested.contains { ($0.a + $0.b).contains { $0.id == wide.players[2].id } }, "a pair game calls nobody straight back")
        // One pair game at a time, and never two pairs in one game.
        var two = SessionState(players: (0..<16).map { Player(name: "\($0)", skill: 3, readyAt: Date(timeIntervalSinceNow: Double($0) - 60)) })
        two.courts = (1...2).map { Court(name: "C\($0)", format: .doubles) }
        let t = two.players.map(\.id)
        two.setPartner(t[0], t[1]); two.setPartner(t[2], t[3])
        two.results += [([t[0], t[4]], [t[5], t[6]]), ([t[1], t[7]], [t[8], t[9]]), ([t[2], t[10]], [t[11], t[12]]),
                        ([t[3], t[13]], [t[14], t[15]]), ([t[4], t[5]], [t[6], t[7]])].map { GameResult(teamA: $0.0, teamB: $0.1, winner: 0, court: "C", start: Date()) }
        assert(two.queueUpNext.filter { two.isPairGame($0.a.map(\.id), $0.b.map(\.id)) }.count == 1, "exactly one pair game lined up at a time")
        assert(!two.queueUpNext.contains { g in [g.a, g.b].allSatisfy { team in two.pairsKeptApart().contains(Set(team.map(\.id))) } }, "never two pairs in one game")
        two.fill(two.courts.first { two.nextPairing(for: $0).map { two.isPairGame($0.a.map(\.id), $0.b.map(\.id)) } ?? false }!.id)
        assert(two.pairGameOnCourt && !two.queueUpNext.contains { two.isPairGame($0.a.map(\.id), $0.b.map(\.id)) }, "no second pair game while one is playing")
        // Too few players for the courts: requests are kept but on hold.
        hold.courts = (1...2).map { Court(name: "C\($0)", format: .doubles) }
        assert(hold.pairingMinimum == 14 && !hold.pairingActive && hold.partnerGames(hold.queue, picked: hold.queue, overdue: [], justOff: []).isEmpty
               && hold.pairsKeptApart().isEmpty, "pair requests wait for 14 players on 2 courts")
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
        for _ in 0..<3 { zero.results.append(GameResult(teamA: [zero.players[0].id], teamB: [zero.players[1].id], winner: 0, court: "C", start: Date())) }
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
            waitCheck.results.append(GameResult(teamA: [waitCheck.players[i].id], teamB: [UUID()], winner: 0, court: "", start: Date()))
        }
        let overdueGame = waitCheck.pick(.doubles, from: waitCheck.queue)!
        assert(Set([waitCheck.players[6].id, waitCheck.players[7].id]).isSubset(of: (overdueGame.a + overdueGame.b).map(\.id))
               && overdueGame.note?.contains("waited") == true, "everyone overdue plays next")
        // More overdue than a court takes: fewest games first, and a late arrival counts at par (not ahead for the games they missed).
        var fewer = SessionState(players: ["C", "D", "E", "F", "A", "Late", "G", "H"].enumerated().map { Player(name: $0.element, skill: 3, readyAt: Date(timeIntervalSinceNow: Double($0.offset))) })
        for (i, games, mins) in [(0, 2, 25), (1, 2, 25), (2, 2, 25), (3, 2, 25), (5, 0, 40), (4, 3, 50)] {
            fewer.players[i].since = Date(timeIntervalSinceNow: Double(-mins * 60))
            for _ in 0..<games { fewer.results.append(GameResult(teamA: [fewer.players[i].id], teamB: [UUID()], winner: 0, court: "", start: Date())) }
        }
        fewer.players[5].credit = 3
        let fewerGame = fewer.pick(.doubles, from: fewer.queue)!
        assert(Set((fewerGame.a + fewerGame.b).map(\.name)) == ["C", "D", "E", "F"], "overdue: fewest games first, a late arrival at par")
        // An overdue strong player gets a balanced game within 2 levels rather than a lopsided one.
        var stretch = SessionState(players: [5.0, 4.5, 3.5, 3, 3, 3, 2, 1].enumerated().map { Player(name: "\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSinceNow: Double($0.offset))) })
        stretch.players[0].since = Date(timeIntervalSinceNow: -35 * 60)
        stretch.results.append(GameResult(teamA: [stretch.players[0].id], teamB: [UUID()], winner: 0, court: "", start: Date()))
        let stretchGame = stretch.pick(.doubles, from: stretch.queue)!, stretchSkills = (stretchGame.a + stretchGame.b).map(\.skill)
        assert(stretchSkills.contains(5) && stretchSkills.max()! - stretchSkills.min()! <= overdueSpread + 1e-9, "an overdue game stays within 2 levels")
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
        assert(repeats(again.a, again.b, lastGame([0, 3], [1, 2])) == 0 && again.note == nil, "avoid repeating last game's partners and opponents")
        // Too few players for similar groups (under 8 per doubles court): balanced teams in queue order instead.
        let skills = [5.0, 2.6, 4.6, 3.0, 5.0, 4.8, 4.9, 2.8]
        func lineup(_ extra: Int) -> SessionState {
            var st = SessionState(players: (skills + Array(repeating: 3.0, count: extra)).enumerated().map { Player(name: "\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSinceNow: Double($0.offset) - 60)) })
            st.courts = [Court(name: "C1", format: .doubles), Court(name: "C2", format: .doubles)]
            return st
        }
        let few = lineup(0), many = lineup(8)
        assert(few.balancedOnly && !many.balancedOnly, "balanced-only below 8 players per doubles court")
        assert(Set(few.pick(.doubles, from: few.queue)!.a.map(\.name) + few.pick(.doubles, from: few.queue)!.b.map(\.name)) == ["0", "1", "2", "3"],
               "too few players: the first in line with the next who make even teams")
        let similar = many.pick(.doubles, from: many.queue)!
        assert(Set((similar.a + similar.b).map(\.name)) == ["0", "2", "4", "5"], "enough players: similar-skill groups")
        // Ties on fewest games: the hardest to match heads the game (four strong players rather than mid-rated ones first in line).
        var tie = SessionState(players: [3.0, 5.0, 4.9, 4.8, 4.7, 3, 3, 3, 3, 3, 3, 3].enumerated().map { Player(name: "\($0.offset)", skill: $0.element, readyAt: Date(timeIntervalSinceNow: Double($0.offset) - 60)) })
        tie.courts = [Court(name: "C1", format: .doubles), Court(name: "C2", format: .doubles)]
        tie.players.append(contentsOf: (0..<4).map { Player(name: "x\($0)", skill: 3, readyAt: Date(timeIntervalSinceNow: Double(20 + $0) - 60)) })
        for p in tie.players { tie.results.append(GameResult(teamA: [p.id], teamB: [UUID()], winner: 0, court: "C", start: Date())) }
        let tieGame = tie.pick(.doubles, from: tie.queue)!
        assert(Set((tieGame.a + tieGame.b).map(\.name)) == ["1", "2", "3", "4"], "on ties, the hardest to match goes first")
        // Four rested but no fair game among them: they play anyway, strongest with weakest, rather than call anyone back.
        let four = [5.0, 3.1, 3.3, 3.2, 4.5, 2.9, 3.0, 3.6].enumerated().map { Player(name: "\($0.offset)", skill: $0.element) }
        let rest4 = pickDoubles(four, justOff: Set(four[4...].map(\.id)))!
        assert(Set((rest4.a + rest4.b).map(\.name)) == ["0", "1", "2", "3"] && [rest4.a, rest4.b].contains { Set($0.map(\.name)) == ["0", "1"] }
               && rest4.note?.contains("straight back") == true, "four rested play, strongest with weakest, nobody called back")
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
        assert(mixedUp.note == "mixed teams for new partners" && repeats(mixedUp.a, mixedUp.b, topRecent) < repeatLimit, "balanced teams break up a repeat")
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
        var aWon = false, note: String?, straightBack: [String]
        var spread: Double { let s = (a + b).map(\.skill); return s.max()! - s.min()! }
        var gap: Double { abs(Simulation.avg(a) - Simulation.avg(b)) }
    }

    /// A wait of 35 minutes or more: who, when, and how their games compared with everyone's when it began.
    struct LongWait { var name: String, skill: Double, minutes: Double, from: Double, to: Double, games: Int, groupAverage: Double }

    struct Night { var games: [Game] = []; var waits: [String: [Double]] = [:]; var long: [LongWait] = []; var pairGameGaps: [Double] = []; var plannedPairGames: [Int] = [] }

    static func avg(_ side: Side) -> Double { side.map(\.skill).reduce(0, +) / Double(side.count) }

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
            var q = p; q.readyAt = t0.addingTimeInterval(Double(n) * 0.001); q.first = nil; q.paused = false; q.away = nil; return q
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
                                            a: p.a.map { ($0.name, truth[$0.id]!) }, b: p.b.map { ($0.name, truth[$0.id]!) },
                                            note: p.note, straightBack: (p.a + p.b).filter { lastEnd[$0.id] == t }.map(\.name)))
                    if s.isPairGame(p.a.map(\.id), p.b.map(\.id)) { // evenness by the ratings the app used at the time
                        night.pairGameGaps.append(abs(p.a.map(\.skill).reduce(0, +) - p.b.map(\.skill).reduce(0, +)) / 2)
                        night.plannedPairGames.append(night.games.count - 1)
                    }
                    s.fill(c.id, at: t)
                    ends[c.id] = (t.addingTimeInterval(length), night.games.count - 1)
                }
            }
            let soonest = ends.min(by: { $0.value.end < $1.value.end })
            if !arrived, soonest.map({ arriveAt <= $0.value.end }) ?? true { t = arriveAt; continue }
            guard let (cid, next) = soonest, let m = s.courts.first(where: { $0.id == cid })?.match else { break }
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
        SessionState.simulatedNow = nil
        return night
    }

    /// `-pairsweep` with `-pairs "A,B;C,D;E,F"` (and `-courts N`): pair requests against none. Did each pair get its game,
    /// how even was it, did pair games ever overlap or share a game, and what did it cost everyone else?
    /// Writes Documents/sim-pairsweep.md.
    static func pairSweep() {
        guard let store = input() else { return }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-pairs"), i + 1 < args.count else { return }
        let pairs = args[i + 1].split(separator: ";").compactMap { p -> (String, String)? in
            let n = p.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }; return n.count == 2 ? (n[0], n[1]) : nil }
        var base = store.current
        let courts = args.firstIndex(of: "-courts").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 2
        base.courts = (1...courts).map { Court(name: "Court \($0)", format: .doubles) }
        base.players = base.players.map { var p = $0; p.partner = nil; return p } // requests come only from -pairs
        let skill = Dictionary(base.players.map { ($0.name, $0.skill) }, uniquingKeysWith: { a, _ in a })
        let runs = 30, length: ClosedRange<TimeInterval> = 10 * 60...14 * 60
        func mean(_ x: [Double]) -> Double { x.isEmpty ? 0 : x.reduce(0, +) / Double(x.count) }
        func f(_ x: Double) -> String { String(format: "%.1f", x) }
        func has(_ g: Game, _ n: String) -> Bool { (g.a + g.b).contains { $0.name == n } }
        func together(_ g: Game, _ x: String, _ y: String) -> Bool { [g.a, g.b].contains { s in s.contains { $0.name == x } && s.contains { $0.name == y } } }
        func clock(_ m: Double) -> String { String(format: "%d:%02d", Int(m) / 60, Int(m) % 60) }
        let paired = Set(pairs.flatMap { [$0.0, $0.1] }), rest = Set(base.players.map(\.name)).subtracting(paired)
        var out = "# \(pairs.count) pair requests against none\n\n\(base.players.count) players · \(courts) doubles courts · 3 hours · games 10–14 min · \(runs) nights each · same random draws\n\nPairs: "
            + pairs.map { "\($0.0) \(f(skill[$0.0] ?? 0)) & \($0.1) \(f(skill[$0.1] ?? 0))" }.joined(separator: " · ") + "\n\n"
        var pairTable = "## Each pair's game together\n\n| Pair | Ratings | Nights they got it | Times together per night | First together at (avg) | Team gap in that game | Rating range in that game | Games each per night | Same with no request: together per night |\n|---|---|---|---|---|---|---|---|---|\n"
        var groupTable = "## Conflicts and everyone else, per night\n\n| | Pair games at the same time | Two pairs in one game | Paired players' games | Others' games | Average wait | Longest wait | Waits over 30 min (others) | All four within 1 level | Team gap |\n|---|---|---|---|---|---|---|---|---|---|\n"
        var withoutTogether: [String: Double] = [:], conflictDetail: String?
        for requests in [false, true] {
            var s0 = base
            if requests {
                for (x, y) in pairs {
                    if let a = s0.players.first(where: { $0.name == x }), let b = s0.players.first(where: { $0.name == y }) { s0.setPartner(a.id, b.id) }
                }
            }
            let nights = (1...UInt64(runs)).map { run(s0, minutes: 180, length: length, late: [], arrival: 0, seed: $0) }
            let name = requests ? "With requests" : "No requests"
            var firstGames: [[Game]] = Array(repeating: [], count: nights.count) // each night's pair games (first time together)
            for (x, y) in pairs {
                var games: [Double] = [], tog: [Double] = [], got = 0, at: [Double] = [], gap: [Double] = [], range: [Double] = []
                for (k, n) in nights.enumerated() {
                    games.append(Double(n.games.filter { has($0, x) }.count + n.games.filter { has($0, y) }.count) / 2)
                    let mine = n.games.filter { together($0, x, y) }.sorted { $0.minute < $1.minute }
                    tog.append(Double(mine.count))
                    if let g = mine.first { got += 1; at.append(g.minute); gap.append(g.gap); range.append(g.spread); firstGames[k].append(g) }
                }
                if !requests { withoutTogether["\(x)&\(y)"] = mean(tog); continue }
                pairTable += "| \(x) & \(y) | \(f(skill[x] ?? 0)) & \(f(skill[y] ?? 0)) | \(got) of \(runs) | \(f(mean(tog))) | \(at.isEmpty ? "–" : clock(mean(at))) | \(String(format: "%.2f", mean(gap))) (worst \(String(format: "%.2f", gap.max() ?? 0))) | \(f(mean(range))) (widest \(f(range.max() ?? 0))) | \(f(mean(games))) | \(f(withoutTogether["\(x)&\(y)"] ?? 0)) |\n"
            }
            let planned = nights.flatMap(\.pairGameGaps)
            if requests { out += "Pair games made: \(planned.count) over \(runs) nights · team gap by the ratings at the time: average \(String(format: "%.2f", mean(planned))), worst \(String(format: "%.2f", planned.max() ?? 0)) · over 0.25: \(planned.filter { $0 > SessionState.pairSlack + 1e-9 }.count)\n\n" }
            if requests {
                var lines: [String] = []
                for (k, n) in nights.enumerated() {
                    let pgs = firstGames[k]
                    for i in pgs.indices { for j in pgs.indices where j > i {
                        let a = pgs[i], b = pgs[j]
                        guard a.minute < b.minute + b.length - 1e-6 && b.minute < a.minute + a.length - 1e-6 else { continue }
                        let planned = { (g: Game) in n.games.firstIndex { $0.minute == g.minute && $0.court == g.court }.map { n.plannedPairGames.contains($0) } ?? false }
                        lines.append("- Night \(k + 1): \(a.court) \(clock(a.minute))–\(clock(a.minute + a.length)) \(a.a.map(\.name)) v \(a.b.map(\.name)) (planned: \(planned(a))) overlaps \(b.court) \(clock(b.minute))–\(clock(b.minute + b.length)) \(b.a.map(\.name)) v \(b.b.map(\.name)) (planned: \(planned(b)))")
                    } }
                    for g in n.games where pairs.filter({ together(g, $0.0, $0.1) }).count >= 2 {
                        lines.append("- Night \(k + 1): two pairs in one game: \(g.court) \(clock(g.minute)) \(g.a.map(\.name)) v \(g.b.map(\.name))")
                    }
                }
                conflictDetail = lines.isEmpty ? nil : lines.joined(separator: "\n") + "\n"
            }
            var overlap: [Double] = [], two: [Double] = [], pg: [Double] = [], og: [Double] = [], avgWait: [Double] = [], longest: [Double] = [],
                over30: [Double] = [], within1: [Double] = [], gaps: [Double] = []
            for (k, n) in nights.enumerated() {
                let pgs = firstGames[k]
                func overlaps(_ a: Game, _ b: Game) -> Bool { a.minute < b.minute + b.length - 1e-6 && b.minute < a.minute + a.length - 1e-6 }
                var count = 0
                for i in pgs.indices { for j in pgs.indices where j > i && overlaps(pgs[i], pgs[j]) { count += 1 } }
                overlap.append(Double(count))
                two.append(Double(n.games.filter { g in pairs.filter { together(g, $0.0, $0.1) }.count >= 2 }.count))
                let names = n.games.flatMap { ($0.a + $0.b).map(\.name) }
                pg.append(Double(names.filter(paired.contains).count) / Double(paired.count))
                og.append(Double(names.filter(rest.contains).count) / Double(rest.count))
                var lastEnd: [String: Double] = [:], waits: [Double] = [], who: [String] = []
                for g in n.games.sorted(by: { $0.minute < $1.minute }) {
                    for p in g.a + g.b { waits.append(g.minute - (lastEnd[p.name] ?? 0)); who.append(p.name); lastEnd[p.name] = g.minute + g.length }
                }
                avgWait.append(mean(waits)); longest.append(waits.max() ?? 0)
                over30.append(Double(zip(waits, who).filter { $0.0 > 30 && rest.contains($0.1) }.count))
                within1.append(Double(n.games.filter { $0.spread <= 1 + 1e-9 }.count) / Double(max(1, n.games.count)))
                gaps.append(mean(n.games.map(\.gap)))
            }
            groupTable += "| \(name) | \(requests ? f(mean(overlap)) : "–") | \(f(mean(two))) | \(f(mean(pg))) | \(f(mean(og))) | \(f(mean(avgWait))) min | \(Int(longest.max() ?? 0)) min | \(f(mean(over30))) | \(Int((mean(within1) * 100).rounded()))% | \(String(format: "%.2f", mean(gaps))) |\n"
        }
        out += pairTable + "\n" + groupTable
        if let detail = conflictDetail { out += "\n## Conflicts in detail\n\n" + detail }
        try? out.write(to: URL.documentsDirectory.appending(path: "sim-pairsweep.md"), atomically: true, encoding: .utf8)
        print(out)
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

    /// `-parity` (with `-courts N`, optional `-pairs "A,B;C,D"`): one night with nothing random (game k lasts 10 + k % 5 minutes,
    /// the side with the higher starting ratings wins), written to Documents/parity.txt as the lineups in order, to compare
    /// line by line with the web version playing the same night (tools/web-sim.js --parity).
    static func parity() {
        guard var s = input()?.current else { return }
        let args = ProcessInfo.processInfo.arguments
        let courts = args.firstIndex(of: "-courts").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 3
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        s.results = []; s.tournament = nil
        s.courts = (1...courts).map { Court(name: "Court \($0)", format: .doubles) }
        s.players = s.players.enumerated().map { n, p in
            var q = p; q.readyAt = t0.addingTimeInterval(Double(n) * 0.001); q.since = nil; q.first = nil; q.paused = false; q.away = nil; q.credit = nil; q.partner = nil; return q
        }
        if let i = args.firstIndex(of: "-pairs"), i + 1 < args.count {
            for pair in args[i + 1].split(separator: ";") {
                let n = pair.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if n.count == 2, let a = s.players.first(where: { $0.name == n[0] }), let b = s.players.first(where: { $0.name == n[1] }) { s.setPartner(a.id, b.id) }
            }
        }
        let truth = Dictionary(uniqueKeysWithValues: s.players.map { ($0.id, $0.skill) })
        let draws = (try? Data(contentsOf: URL.documentsDirectory.appending(path: "draws.json"))).flatMap { try? JSONDecoder().decode([[Double]].self, from: $0) }
        var t = t0, ends: [Int: Date] = [:], lines: [String] = [], k = 0, winners: [Int: Bool] = [:]
        while true {
            SessionState.simulatedNow = t
            if t < t0.addingTimeInterval(180 * 60) {
                for (ci, c) in s.courts.enumerated() where c.match == nil {
                    guard let p = s.nextPairing(for: c) else { continue }
                    lines.append("\(Int(t.timeIntervalSince(t0) / 60)) \(c.name): \(p.a.map(\.name).joined(separator: "+")) v \(p.b.map(\.name).joined(separator: "+"))")
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
            guard let (ci, end) = ends.min(by: { ($0.value, $0.key) < ($1.value, $1.key) }) else { break }
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
        // Same players and rules, two ways to spend six court-hours.
        // Partner requests from `-pairs "A,B;C,D"` (names stay out of the code), else close ratings, one level apart, two levels apart.
        let given = args.firstIndex(of: "-pairs").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        // `-nopairs`: no requests; compares 2 courts with `-courts N` instead.
        let noPairs = args.contains("-nopairs")
        let courts = args.firstIndex(of: "-courts").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 2
        let requests = noPairs ? [] : given.map { $0.split(separator: ";").compactMap { p -> (String, String)? in
            let n = p.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }; return n.count == 2 ? (n[0], n[1]) : nil } }
            ?? [(11, 12), (5, 10), (2, 17)].filter { $0.1 < ranked.count }.map { (ranked[$0.0].name, ranked[$0.1].name) }
        let configs: [(name: String, courts: Int, minutes: Double)] = noPairs ? [("2 courts", 2, 180), ("\(courts) courts", courts, 180)]
            : [("No requests", courts, 180), ("With pair request\(requests.count == 1 ? "" : "s")", courts, 180)]
        let results = configs.enumerated().map { i, c -> [Night] in
            var start = real
            start.courts = (1...c.courts).map { Court(name: "Court \($0)", format: .doubles) }
            for (x, y) in requests where i == 1 {
                if let a = start.players.first(where: { $0.name == x }), let b = start.players.first(where: { $0.name == y }) { start.setPartner(a.id, b.id) }
            }
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
            ]
        }
        let rows = ["Games per night", "Games per player", "All four within 1 level", "All four within 1.5 levels", "Rating range on a court",
                    "Rating range in mixed games", "Gap between the teams", "Widened to 1.5 for new partners",
                    "Widened so nobody goes straight back", "Mixed teams for new partners", "Mixed teams so nobody goes straight back",
                    "Mixed teams, no similar group free", "Games with an overdue player", "Repeat partnerships per night",
                    "Same four again per night", "Most-played opponent pair (times a night)", "Different partner pairs per night",
                    "Wait between games", "Waits of 35+ min per night", "Waits of 45+ min per night", "Straight back on court (times a night)",
                    "Latecomers' wait for their first game", "Games per latecomer vs on-time player"]
        let table = results.map(summary)

        var out = "# Simulated nights: \(names.count) players, doubles, " + configs.map { "\($0.name) (\($0.courts) courts, \(Int($0.minutes / 60)) hours)" }.joined(separator: " vs ") + "\n\n"
        out += "Games last 10–14 min (evenly spread) · " + (late.isEmpty ? "everyone there from the start" : "\(late.sorted { (skill[$0] ?? 0) > (skill[$1] ?? 0) }.map { "\($0) \(f(skill[$0] ?? 0))" }.joined(separator: ", ")) arrive 60 minutes late")
        out += " · \(runs) nights each way, same random draws · winners drawn from ratings\n\n"
        out += "Rules as in the app: similar skill within 1 level, 1.5 for new partners, balanced teams from the nearest ratings; "
        out += "nobody goes straight back on court while rested players can make a game; anyone overdue plays next.\n\n"
        out += "## Summary (average of \(runs) nights)\n\n| | " + configs.map(\.name).joined(separator: " | ") + " |\n|---|" + String(repeating: "---|", count: configs.count) + "\n"
        for (i, r) in rows.enumerated() { out += "| \(r) | " + table.map { $0[i] }.joined(separator: " | ") + " |\n" }

        // How the latecomers fared
        for (c, nights) in shown.map({ (configs[$0], results[$0]) }) {
            out += "\n## Latecomers: \(c.name)\n\n| Player | Rating | First game after arriving | Longest first wait | Games | Straight onto a court |\n|---|---|---|---|---|---|\n"
            for name in late.sorted(by: { (skill[$0] ?? 0) > (skill[$1] ?? 0) }) {
                let firsts = nights.compactMap { $0.waits[name]?.first }
                let games = nights.map { n in Double(n.games.filter { ($0.a + $0.b).contains { $0.name == name } }.count) }
                out += "| \(name) | \(f(skill[name] ?? 0)) | avg \(f(mean(firsts))) min | \(f(firsts.max() ?? 0, 0)) min | \(f(mean(games))) | \(firsts.filter { $0 < 0.5 }.count) of \(runs) nights |\n"
            }
        }

        // Who waited longest, and why
        for (v, nights) in shown.map({ (configs[$0], results[$0]) }) {
            let long = nights.enumerated().flatMap { n, night in night.long.map { (night: n + 1, w: $0) } }
            out += "\n## Longest waits: \(v.name)\n\n"
            out += "\(long.count) waits of 35+ minutes across \(runs) nights (\(f(Double(long.count) / Double(runs))) a night).\n\n"
            out += "| Player | Wait | Night | From–to | Games when the wait began | Everyone's average then |\n|---|---|---|---|---|---|\n"
            for x in long.sorted(by: { $0.w.minutes > $1.w.minutes }).prefix(8) {
                out += "| \(x.w.name) \(f(x.w.skill)) | \(f(x.w.minutes, 0)) min | \(x.night) | \(clock(x.w.from))–\(clock(x.w.to)) | \(x.w.games) | \(f(x.w.groupAverage)) |\n"
            }
            let byPlayer = Dictionary(grouping: long, by: { $0.w.name }).mapValues(\.count).sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            out += "\nMost often (35+ min waits over \(runs) nights): " + byPlayer.prefix(8).map { "\($0.key) \(f(skill[$0.key] ?? 0)) ×\($0.value)" }.joined(separator: ", ") + "\n"
            let ahead = long.filter { Double($0.w.games) > $0.w.groupAverage + 0.3 }.count
            out += "\n\(long.isEmpty ? 0 : 100 * ahead / long.count)% of these began when the player had already played more games than the group average.\n"
        }

        let one = after[0]
        out += "\n## Night 1 (\(configs[1].name)): every game\n\n| # | Start | Court | Team A | Team B | Avg | Gap | Winner | Length | Note |\n|---|---|---|---|---|---|---|---|---|---|\n"
        for (i, g) in one.games.enumerated() {
            let note = ([g.note].compactMap { $0 } + (g.straightBack.isEmpty ? [] : ["straight back: " + g.straightBack.joined(separator: ", ")])).joined(separator: "; ")
            out += "| \(i + 1) | \(clock(g.minute)) | \(g.court) | \(team(g.a)) | \(team(g.b)) | \(f(avg(g.a), 2)) v \(f(avg(g.b), 2)) | \(f(g.gap, 2)) | \(g.aWon ? "A" : "B") | \(f(g.length, 0)) min | \(note) |\n"
        }

        out += "\n## Night 1 (\(configs[1].name)): each player\n\n| Player | Rating | Games | Won | Partners | Opponents | Longest wait | Straight back |\n|---|---|---|---|---|---|---|---|\n"
        for name in names.sorted(by: { (skill[$0] ?? 0, $1) > (skill[$1] ?? 0, $0) }) {
            let mine = one.games.filter { ($0.a + $0.b).contains { $0.name == name } }
            let won = mine.filter { g in (g.aWon ? g.a : g.b).contains { $0.name == name } }.count
            let partners = Set(mine.flatMap { g in (g.a.contains { $0.name == name } ? g.a : g.b).map(\.name) }).subtracting([name])
            let opponents = Set(mine.flatMap { g in (g.a.contains { $0.name == name } ? g.b : g.a).map(\.name) })
            out += "| \(name) | \(f(skill[name] ?? 0)) | \(mine.count) | \(won) | \(partners.count) | \(opponents.count) | \(f(one.waits[name]?.max() ?? 0, 0)) min | \(mine.filter { $0.straightBack.contains(name) }.count) |\n"
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

        // How often each requested pair partnered, and their pattern on night 1 (T = together, a = apart).
        if !requests.isEmpty { out += "\n## Partner requests (\(configs[1].name), \(runs) nights)\n\n| Pair | Ratings | Games per night (each) | Together per night | Fewest–most together | Share together | Against each other | Without request | Night 1 |\n|---|---|---|---|---|---|---|---|---|\n"
        for (x, y) in requests {
            func together(_ n: Night) -> (gx: Double, gy: Double, with: Double, against: Double, pattern: String) {
                let mine = n.games.filter { ($0.a + $0.b).contains { $0.name == x } }
                let flags = mine.map { g in [g.a, g.b].contains { side in side.contains { $0.name == x } && side.contains { $0.name == y } } }
                let theirs = n.games.filter { ($0.a + $0.b).contains { $0.name == y } }.count
                let against = mine.filter { g in (g.a + g.b).contains { $0.name == y } }.count - flags.filter { $0 }.count
                return (Double(mine.count), Double(theirs), Double(flags.filter { $0 }.count), Double(against), flags.map { $0 ? "T" : "a" }.joined())
            }
            let w = after.map(together), wo = before.map(together)
            let share = mean(w.map(\.with)) / max(1, mean(w.map { ($0.gx + $0.gy) / 2 }))
            out += "| \(x) & \(y) | \(f(skill[x] ?? 0)) & \(f(skill[y] ?? 0)) | \(f(mean(w.map(\.gx)))) & \(f(mean(w.map(\.gy)))) | \(f(mean(w.map(\.with)))) | \(Int(w.map(\.with).min() ?? 0))–\(Int(w.map(\.with).max() ?? 0)) | \(Int((share * 100).rounded()))% | \(f(mean(w.map(\.against)))) | \(f(mean(wo.map(\.with)))) together, \(f(mean(wo.map(\.against)))) against | \(x): \(w[0].pattern) |\n"
        }
        }

        try? out.write(to: dir.appending(path: "sim-report.md"), atomically: true, encoding: .utf8)
        print(out)
    }
}
#endif
