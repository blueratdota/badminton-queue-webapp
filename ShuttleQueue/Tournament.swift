import SwiftUI

/// Where a tournament game gets each side from.
enum Slot: Codable, Equatable {
    case entrant(Int)   // index into Tournament.entrants
    case seed(Int)      // 0-based round-robin finishing place
    case winnerOf(Int)  // match id
    case loserOf(Int)
}

enum Stage: String, Codable {
    case roundRobin, upper, lower, final
}

struct TMatch: Codable, Equatable, Identifiable {
    var id: Int
    var stage: Stage
    var label: String
    var a: Slot
    var b: Slot
    var winner: Int? // 0 = side a, 1 = side b
}

/// Round robin, then the top finishers play double elimination: upper bracket, lower bracket, Grand Final.
struct Tournament: Codable, Equatable {
    var format: Format
    var entrants: [[UUID]] // one player for singles, a pair for doubles
    var advance: Int       // 4 or 8 go through to the bracket
    var matches: [TMatch] = []
    var seeds: [Int]?      // entrant indices in round-robin finishing order, fixed when the round robin ends

    init(format: Format, entrants: [[UUID]], advance: Int) {
        self.format = format
        self.entrants = entrants
        self.advance = advance
        buildRoundRobin()
        buildBracket()
    }

    // MARK: Schedule

    private mutating func add(_ stage: Stage, _ label: String, _ a: Slot, _ b: Slot) -> Int {
        matches.append(TMatch(id: matches.count, stage: stage, label: label, a: a, b: b))
        return matches.count - 1
    }

    private func numbered(_ base: String, _ i: Int, of count: Int) -> String { count > 1 ? "\(base) \(i + 1)" : base }

    /// Circle method: everyone meets everyone once, nobody is booked twice in a round.
    private mutating func buildRoundRobin() {
        var ring = Array(entrants.indices)
        if ring.count % 2 == 1 { ring.append(-1) } // -1 = bye
        let n = ring.count
        guard n >= 2 else { return }
        // Games are played best-rested first, not strictly in this order, so they aren't labelled by round.
        for _ in 1..<n {
            for i in 0..<(n / 2) where ring[i] >= 0 && ring[n - 1 - i] >= 0 {
                _ = add(.roundRobin, "Round Robin", .entrant(ring[i]), .entrant(ring[n - 1 - i]))
            }
            ring.insert(ring.removeLast(), at: 1)
        }
    }

    private mutating func buildBracket() {
        // Standard seeding so the top two can only meet in the upper final.
        let order = advance == 8 ? [0, 7, 3, 4, 1, 6, 2, 5] : [0, 3, 1, 2]
        var upper: [[Int]] = []
        var slots = order.map { Slot.seed($0) }
        while slots.count > 1 {
            let name = slots.count == 2 ? "Upper Final" : slots.count == 4 ? "Upper Semifinal" : "Upper Quarterfinal"
            var ids: [Int] = []
            for i in stride(from: 0, to: slots.count, by: 2) {
                ids.append(add(.upper, numbered(name, i / 2, of: slots.count / 2), slots[i], slots[i + 1]))
            }
            upper.append(ids)
            slots = ids.map { .winnerOf($0) }
        }

        // Lower bracket: upper round 1 losers pair off, then each later upper round's losers drop in.
        var round = 1
        var cur: [Int] = []
        for i in stride(from: 0, to: upper[0].count, by: 2) {
            cur.append(add(.lower, numbered("Lower Round 1", i / 2, of: upper[0].count / 2), .loserOf(upper[0][i]), .loserOf(upper[0][i + 1])))
        }
        for r in 1..<upper.count {
            round += 1
            let isLast = r == upper.count - 1
            let drops = r % 2 == 1 ? Array(upper[r].reversed()) : upper[r] // cross over to avoid instant rematches
            var next: [Int] = []
            for (i, (w, l)) in zip(cur, drops).enumerated() {
                next.append(add(.lower, isLast ? "Lower Final" : numbered("Lower Round \(round)", i, of: drops.count), .winnerOf(w), .loserOf(l)))
            }
            cur = next
            if !isLast {
                round += 1
                next = []
                for i in stride(from: 0, to: cur.count, by: 2) {
                    next.append(add(.lower, numbered("Lower Round \(round)", i / 2, of: cur.count / 2), .winnerOf(cur[i]), .winnerOf(cur[i + 1])))
                }
                cur = next
            }
        }
        // ponytail: single Grand Final, no bracket reset if the lower-bracket side wins it
        _ = add(.final, "Grand Final", .winnerOf(upper[upper.count - 1][0]), .winnerOf(cur[0]))
    }

    // MARK: State

    func entrant(_ slot: Slot) -> Int? {
        switch slot {
        case .entrant(let i): return i
        case .seed(let k): return seeds.flatMap { k < $0.count ? $0[k] : nil }
        case .winnerOf(let m): return matches[m].winner.flatMap { entrant($0 == 0 ? matches[m].a : matches[m].b) }
        case .loserOf(let m): return matches[m].winner.flatMap { entrant($0 == 0 ? matches[m].b : matches[m].a) }
        }
    }

    /// Both sides of a game not played yet, once they're known.
    func sidesIfReady(_ m: TMatch) -> (Int, Int)? {
        guard m.winner == nil, let x = entrant(m.a), let y = entrant(m.b) else { return nil }
        return (x, y)
    }

    var roundRobin: [TMatch] { matches.filter { $0.stage == .roundRobin } }

    var champion: Int? {
        matches.last.flatMap { $0.stage == .final ? entrant(.winnerOf($0.id)) : nil }
    }

    /// Round-robin table: most wins first; ties go to the higher-rated side.
    // ponytail: rating tiebreak; add head-to-head if ties get argued about
    func table(rating: (Int) -> Double) -> [(entrant: Int, won: Int, lost: Int)] {
        entrants.indices.map { e in
            var won = 0, lost = 0
            for m in roundRobin {
                guard let w = m.winner, let x = entrant(m.a), let y = entrant(m.b), e == x || e == y else { continue }
                if (w == 0) == (e == x) { won += 1 } else { lost += 1 }
            }
            return (e, won, lost)
        }
        .sorted { ($0.won, rating($0.entrant)) > ($1.won, rating($1.entrant)) }
    }

    mutating func record(_ id: Int, winner: Int, rating: (Int) -> Double) {
        matches[id].winner = winner
        if seeds == nil, roundRobin.allSatisfy({ $0.winner != nil }) {
            let order = table(rating: rating).map(\.entrant)
            seeds = order
        }
    }

    #if DEBUG
    static func selfCheck() {
        for (n, advance, games) in [(4, 4, 6 + 6), (5, 4, 10 + 6), (8, 8, 28 + 14)] {
            var t = Tournament(format: .singles, entrants: (0..<n).map { _ in [UUID()] }, advance: advance)
            assert(t.matches.count == games, "wrong number of tournament games")
            var pairs = Set<[Int]>()
            for m in t.roundRobin { pairs.insert([t.entrant(m.a)!, t.entrant(m.b)!].sorted()) }
            assert(pairs.count == n * (n - 1) / 2, "round robin must meet everyone once")
            // Play it out with side a always winning: every game gets played and seed 1 wins.
            while let m = t.matches.first(where: { t.sidesIfReady($0) != nil }) {
                t.record(m.id, winner: 0) { _ in 0 }
            }
            assert(t.matches.allSatisfy { $0.winner != nil } && t.champion == t.seeds?[0], "tournament should finish")
        }
    }
    #endif
}

// MARK: - Session integration

extension SessionState {
    func players(_ ids: [UUID]) -> [Player] { ids.compactMap(player) }

    func entrantName(_ e: Int) -> String {
        tournament.map { t in t.entrants[e].map { player($0)?.name ?? "Removed player" }.joined(separator: " & ") } ?? ""
    }

    /// Sides for a new tournament from everyone not sitting out. Doubles pairs strongest with newest; an odd player sits out.
    func tournamentEntrants(_ format: Format) -> (entrants: [[UUID]], sittingOut: [Player]) {
        var out = players.filter { $0.paused || $0.away == true } // sitting out or not here
        let active = players.filter { !$0.paused && $0.away != true }
        guard format == .doubles else { return (active.map { [$0.id] }, out) }
        var sorted = active.sorted { $0.skill > $1.skill }
        if sorted.count % 2 == 1 { out.append(sorted.remove(at: sorted.count / 2)) }
        return ((0..<sorted.count / 2).map { [sorted[$0].id, sorted[sorted.count - 1 - $0].id] }, out)
    }

    mutating func startTournament(_ format: Format, advance: Int) {
        tournament = Tournament(format: format, entrants: tournamentEntrants(format).entrants, advance: advance)
    }

    /// Tournament games that can start now, nobody booked twice.
    /// Round robin goes to the best-rested sides first; the bracket plays in order.
    var tournamentUpNext: [Pairing] {
        guard let t = tournament else { return [] }
        func lastOff(_ ids: [UUID]) -> Date { ids.compactMap { player($0)?.readyAt }.max() ?? .distantPast }
        let ready = t.matches.compactMap { m -> (m: TMatch, a: [UUID], b: [UUID])? in
            guard let s = t.sidesIfReady(m) else { return nil }
            return (m, t.entrants[s.0], t.entrants[s.1])
        }
        .sorted { x, y in
            func key(_ r: (m: TMatch, a: [UUID], b: [UUID])) -> (Int, Date, Int) {
                r.m.stage == .roundRobin ? (0, lastOff(r.a + r.b), r.m.id) : (1, .distantPast, r.m.id)
            }
            return key(x) < key(y)
        }
        var taken = onCourt
        var out: [Pairing] = []
        for r in ready where taken.isDisjoint(with: r.a + r.b) {
            out.append(Pairing(format: t.format, a: players(r.a), b: players(r.b), match: r.m.id))
            taken.formUnion(r.a + r.b)
        }
        return out
    }

    mutating func recordTournament(_ id: Int, winner: Int) {
        guard let t = tournament else { return }
        let ratings = t.entrants.map { averageSkill($0) }
        tournament?.record(id, winner: winner) { ratings[$0] }
    }
}

// MARK: - Views

/// The right-hand panel in tournament mode: round-robin table and the bracket.
struct TournamentSections: View {
    let s: SessionState

    var body: some View {
        if let t = s.tournament {
            if let champ = t.champion {
                Section {
                    Label("\(s.entrantName(champ)) won the tournament", systemImage: "trophy.fill")
                        .font(.headline).foregroundStyle(Color.singles)
                }
            }

            let rr = t.roundRobin
            let table = t.table { s.averageSkill(t.entrants[$0]) }
            Section {
                ForEach(Array(table.enumerated()), id: \.element.entrant) { place, row in
                    HStack {
                        Text("\(place + 1)").font(.headline).monospacedDigit()
                            .foregroundStyle(place < t.advance ? Color.court : .secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(s.entrantName(row.entrant)).font(.body.weight(place < t.advance ? .semibold : .regular))
                        Spacer()
                        Text("\(row.won)–\(row.lost)").font(.headline).monospacedDigit()
                    }
                }
            } header: {
                Text("Round Robin · \(rr.filter { $0.winner != nil }.count) of \(rr.count) played")
            } footer: {
                Text("Top \(t.advance) (green) go to the bracket. Ties go to the higher-rated side.")
            }

            bracket(t, .upper, "Upper Bracket")
            bracket(t, .lower, "Lower Bracket")
            bracket(t, .final, "Final")
        }
    }

    private func bracket(_ t: Tournament, _ stage: Stage, _ title: String) -> some View {
        Section(title) {
            ForEach(t.matches.filter { $0.stage == stage }) { m in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(m.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text(status(t, m)).font(.caption.weight(.semibold)).foregroundStyle(Color.court)
                    }
                    HStack(spacing: 6) {
                        side(t, m.a, won: m.winner == 0)
                        Text("vs").font(.caption).foregroundStyle(.secondary)
                        side(t, m.b, won: m.winner == 1)
                    }
                }
            }
        }
    }

    private func side(_ t: Tournament, _ slot: Slot, won: Bool) -> some View {
        HStack(spacing: 3) {
            if won { Image(systemName: "trophy.fill").foregroundStyle(Color.singles).accessibilityLabel("Winner") }
            if let e = t.entrant(slot) {
                Text(s.entrantName(e)).font(.subheadline.weight(won ? .bold : .regular))
            } else {
                Text(placeholder(t, slot)).font(.subheadline).italic().foregroundStyle(.secondary)
            }
        }
    }

    private func placeholder(_ t: Tournament, _ slot: Slot) -> String {
        switch slot {
        case .entrant: return ""
        case .seed(let k): return "Seed \(k + 1)"
        case .winnerOf(let m): return "Winner, \(t.matches[m].label)"
        case .loserOf(let m): return "Loser, \(t.matches[m].label)"
        }
    }

    private func status(_ t: Tournament, _ m: TMatch) -> String {
        if let c = s.courts.first(where: { $0.match?.tournamentMatch == m.id }) { return "On \(c.name)" }
        return m.winner == nil && t.sidesIfReady(m) != nil ? "Ready" : ""
    }
}

struct TournamentSetup: View {
    @Binding var s: SessionState
    @Environment(\.dismiss) private var dismiss
    @State private var format = Format.doubles
    @State private var advance = 4

    var body: some View {
        let (entrants, out) = s.tournamentEntrants(format)
        let n = entrants.count
        let bracketSize = n >= 8 ? advance : 4
        NavigationStack {
            Form {
                Section {
                    Picker("Format", selection: $format) {
                        ForEach(Format.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(format == .doubles ? "Teams pair the strongest player with the newest, so teams are even." : "Every player plays every other player once.")
                }

                Section {
                    Picker("Go to the bracket", selection: $advance) {
                        Text("Top 4").tag(4)
                        Text("Top 8").tag(8)
                    }
                    .pickerStyle(.segmented)
                    .disabled(n < 8)
                } header: {
                    Text("Bracket")
                } footer: {
                    Text("Double elimination: a side is out after two losses. The upper-bracket winner meets the lower-bracket winner in the Grand Final.")
                }

                Section {
                    ForEach(Array(entrants.enumerated()), id: \.offset) { _, ids in
                        HStack {
                            Text(s.players(ids).map(\.name).joined(separator: " & ")).font(.body.weight(.semibold))
                            Spacer()
                            SkillDots(skill: s.averageSkill(ids))
                        }
                    }
                } header: {
                    Text("\(n) \(format == .doubles ? "teams" : "players") · \(n * (n - 1) / 2) round-robin games + \(bracketSize == 8 ? 14 : 6) bracket games")
                } footer: {
                    if n < 4 {
                        Text("A tournament needs at least 4 \(format == .doubles ? "teams" : "players").")
                    } else if !out.isEmpty {
                        Text("Sitting out: \(out.map(\.name).joined(separator: ", "))")
                    }
                }
            }
            .navigationTitle("New Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { s.startTournament(format, advance: bracketSize); dismiss() }
                        .disabled(n < 4)
                }
            }
        }
    }
}
