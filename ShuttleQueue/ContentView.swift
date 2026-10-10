import SwiftUI

extension Color {
    static let court = Color(red: 0.18, green: 0.48, blue: 0.33)
    static let singles = Color.orange
    static let doubles = Color.court
}

struct ContentView: View {
    @Binding var s: SessionState
    @AppStorage("appearance") private var appearance = "system" // applied app-wide in ShuttleQueueApp
    @Binding var past: [SessionState]
    @State private var showSessions = false
    @State private var showStandings = ProcessInfo.processInfo.arguments.contains("-standings") // test launches open it directly
    @State private var showAllPlayers = false
    @State private var showSessionPlayers = false
    @State private var showPairing = false
    @State private var showAddPlayer = false
    @State private var removing: Player?
    @State private var finishing: Court?
    @State private var showTournamentSetup = false
    @State private var showReturning = false
    @State private var editing: Player?
    @State private var replacing: ReplaceTarget?
    @State private var confirmEndTournament = false

    var body: some View {
        // The matching runs once per screen update; every court card, the Fill button and Up Next read from it.
        let up = s.upNext
        let next = s.openCourtPairings(up)
        NavigationStack {
            HStack(spacing: 0) {
                courtsArea(next)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                Divider()
                queuePanel(up).frame(width: 312)
            }
            .navigationTitle("Shuttle Queue · \(s.date.formatted(.dateTime.weekday().day().month()))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu("Options", systemImage: "gearshape") {
                        Picker("Appearance", systemImage: "circle.lefthalf.filled", selection: $appearance) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .pickerStyle(.menu)
                        Button("Session Players", systemImage: "person.2") { showSessionPlayers = true }
                        Button("All Players", systemImage: "person.3") { showAllPlayers = true }
                        Button("Increase Pairing %", systemImage: "link") { showPairing = true }
                        if let expiry = InstallExpiry.date { // apps installed from Xcode stop opening when their profile runs out
                            Section("This iPad copy") { Label(InstallExpiry.label(expiry), systemImage: "clock.badge.exclamationmark") }
                        }
                    }
                    Menu("Add Player", systemImage: "person.badge.plus") {
                        Button("New Player", systemImage: "person.badge.plus") { showAddPlayer = true }
                        Button("From Earlier Sessions", systemImage: "clock.arrow.circlepath") { showReturning = true }
                    }
                    .disabled(s.tournament != nil)
                    Button("Sessions", systemImage: "calendar") { showSessions = true }
                    Button("Standings", systemImage: "trophy") { showStandings = true }
                    Button("Add Court", systemImage: "plus.rectangle") { s.addCourt() }
                    Button("Fill Open Courts") { s.fillAll() }
                        .buttonStyle(.borderedProminent)
                        .disabled(next.isEmpty)
                }
            }
            .sheet(isPresented: $showSessions) { SessionsSheet(s: $s, past: $past) }
            .fullScreenCover(isPresented: $showStandings) { StandingsSheet(s: $s) }
            .sheet(isPresented: $showAllPlayers) { AllPlayersSheet(sessions: [s] + past) }
            .sheet(isPresented: $showSessionPlayers) {
                SessionPlayersSheet(s: $s, past: past) { p, name, skill, pref, paused, present in save(p, name: name, skill: skill, pref: pref, paused: paused, present: present) }
            }
            .sheet(isPresented: $showPairing) { PairingSheet(s: $s) }
            .sheet(isPresented: $showTournamentSetup) { TournamentSetup(s: $s) }
            .sheet(isPresented: $showReturning) { ReturningPlayersSheet(s: $s, past: past) }
            .sheet(isPresented: $showAddPlayer) { AddPlayerSheet(s: $s) }
            .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible, presenting: removing) { p in
                Button("Remove \(p.name)", role: .destructive) { s.players.removeAll { $0.id == p.id } }
            } message: { _ in
                Text("They leave this session's queue. Games they played stay in the history.")
            }
            .sheet(item: $replacing) { r in ReplacePlayerSheet(s: $s, target: r) }
            .sheet(item: $editing) { p in
                EditPlayerSheet(player: p, played: s.played(p.id), won: s.wins(p.id),
                                takenNames: Set(s.players.filter { $0.id != p.id }.map { $0.name.lowercased() })) { name, skill, pref, paused, present in
                    save(p, name: name, skill: skill, pref: pref, paused: paused, present: present)
                }
            }
            .confirmationDialog("End the tournament and go back to the queue?", isPresented: $confirmEndTournament, titleVisibility: .visible) {
                Button("End Tournament", role: .destructive) { s.tournament = nil }
            } message: {
                Text("Games already played stay in Match History and Standings.")
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true } // courtside iPad stays awake
    }

    // MARK: Courts

    /// Courts at their true 2.2 : 1 shape, one column in portrait, two in landscape.
    private func courtsArea(_ next: [UUID: Pairing]) -> some View {
        ScrollView {
            // ponytail: 380 = the widest two landscape columns fit; portrait gets one 408-point court (20% over the old 340)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 12)], spacing: 12) {
                ForEach($s.courts) { $court in courtCard($court, next: next[court.id]) }
            }
            .padding(12)
        }
    }

    private func courtCard(_ court: Binding<Court>, next: Pairing?) -> some View {
        let c = court.wrappedValue
        let teams = c.match.map { m in (m.teamA.compactMap(s.player), m.teamB.compactMap(s.player)) } ?? next.map { ($0.a, $0.b) }
        let t = s.tournament
        let format = t?.format ?? c.format
        let gameLabel = (c.match?.tournamentMatch ?? next?.match).flatMap { id in t.map { $0.matches[id].label } }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(c.name).font(.title3.bold()).fixedSize()
                Spacer()
                if let t {
                    Text(t.format.rawValue.capitalized).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                } else {
                    Picker("Format", selection: court.format) {
                        ForEach(Format.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                    .disabled(c.match != nil)
                }
                Menu {
                    if c.match != nil {
                        Button("Undo Start", systemImage: "arrow.uturn.backward") { s.undoStart(c.id) }
                    }
                    Button("Remove \(c.name)", systemImage: "trash", role: .destructive) {
                        s.courts.removeAll { $0.id == c.id }
                    }
                    .disabled(c.match != nil)
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).padding(.leading, 4)
                }
                .accessibilityLabel("\(c.name) options")
            }
            .padding(.horizontal)

            // Edge to edge inside the card, so the court gets the full width
            CourtDrawing(format: format, teams: teams, isPreview: c.match == nil,
                         onTap: t == nil && next != nil ? { p in replacing = ReplaceTarget(courtID: c.id, courtName: c.name, out: p) } : nil,
                         locked: c.locked, onLock: t == nil && next != nil ? { side in s.lock(c.locked == side ? nil : side, on: c.id) } : nil)

            HStack {
                if let m = c.match {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text("\(gameLabel.map { "\($0) · " } ?? "")\(Int(ctx.date.timeIntervalSince(m.start) / 60)) min").monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Finish Game") { finishing = c }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue) // Start is green; Finish reads differently at a glance
                        .confirmationDialog("Who won on \(c.name)?", isPresented: Binding(get: { finishing?.id == c.id }, set: { if !$0 { finishing = nil } }),
                                            titleVisibility: .visible) {
                            Button(names(m.teamA)) { s.finish(c.id, winner: 0) }
                            Button(names(m.teamB)) { s.finish(c.id, winner: 1) }
                            Button("No result") { s.finish(c.id, winner: nil) }
                        }
                } else {
                    let short = format.needed - s.eligible(format).count
                    Text(next != nil ? "Next up\(gameLabel.map { " · \($0)" } ?? "")\(next?.note.map { " · \($0)" } ?? "")"
                         : t?.champion != nil ? "Tournament complete"
                         : t == nil && short > 0 ? "Need \(short) more for \(format.rawValue)" : "Waiting for players")
                        .foregroundStyle(.secondary)
                        // The note takes what's left and never pushes the buttons: at most two lines, then it shrinks or trims.
                        .lineLimit(2).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if t == nil, let next, next.options > 1 { shuffleButton(c, singles: next.format == .singles).fixedSize() }
                    Button("Start \(format.rawValue.capitalized)") { s.fill(c.id) }
                        .buttonStyle(.borderedProminent)
                        .fixedSize()
                        .disabled(next == nil)
                }
            }
            .font(.subheadline)
            .frame(minHeight: 44) // same height with or without a note, so the buttons stay put
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        // Courts with a game in progress glow softly orange.
        .overlay {
            if c.match != nil { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.5), lineWidth: 1.5) }
        }
        .shadow(color: c.match != nil ? Color.orange.opacity(0.4) : .clear, radius: 10)
    }

    private func shuffleButton(_ c: Court, singles: Bool) -> some View {
        Button(singles ? "Shuffle Opponent" : "Shuffle Teams", systemImage: "shuffle") { s.shuffle(c.id) }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .accessibilityLabel("\(singles ? "Try another opponent" : "Try other fair teams") on \(c.name)")
    }

    // MARK: Queue

    private func queuePanel(_ upNext: [Pairing]) -> some View {
        List {
            Section {
                Picker("Mode", selection: Binding(get: { s.tournament != nil },
                                                  set: { if $0 { showTournamentSetup = true } else { confirmEndTournament = true } })) {
                    Text("Queue").tag(false)
                    Text("Tournament").tag(true)
                }
                .pickerStyle(.segmented)
            }

            if let t = s.tournament {
                if !upNext.isEmpty {
                    Section("Up Next") {
                        ForEach(Array(upNext.enumerated()), id: \.offset) { _, p in
                            upNextRow(p.match.map { t.matches[$0].label.uppercased() } ?? "", format: p.format, pairing: p)
                        }
                    }
                }
            } else if !s.courts.isEmpty {
                Section("Up Next") {
                    ForEach(s.courts) { c in
                        upNextRow("\(c.name) · \(c.format.rawValue)\(c.match != nil ? " · after this game" : "")".uppercased(),
                                  format: c.format, pairing: upNext.first { $0.court == c.id })
                    }
                }
            }

            if s.tournament != nil {
                TournamentSections(s: s)
            } else {
            Section {
                let q = s.queue
                if q.isEmpty {
                    Text(s.players.contains { $0.away == true } ? "Tap Here as players arrive." : "Add players as they arrive.").foregroundStyle(.secondary)
                }
                ForEach(Array(q.enumerated()), id: \.element.id) { i, p in
                    queueRow(p, position: p.paused ? nil : q[..<i].filter { !$0.paused }.count + 1)
                }
            } header: {
                Text("Queue · \(s.queue.count) off court · \(s.onCourt.count) playing")
            } footer: {
                Text((s.balancedOnly && !s.courts.isEmpty ? "Balanced teams: fewer than \(8 * s.courts.count) players for \(s.courts.count) doubles court\(s.courts.count == 1 ? "" : "s"), so games mix levels with even teams instead of similar-skill groups. " : "")
                     + "Tap a player to edit. Press and hold to sit out, move to front, or remove. Fewest games played goes first (on a tie, whoever is hardest to match), then longest rested; similar skill is matched first.")
            }
            let away = s.players.filter { $0.away == true }
            if !away.isEmpty {
                Section {
                    ForEach(away) { p in
                        HStack(spacing: 10) {
                            Text(p.name).font(.body.weight(.semibold)).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = p }
                            SkillDots(skill: p.skill)
                            Button("Here") { s.arrive(p.id) }
                                .buttonStyle(.bordered).tint(Color.court)
                                .accessibilityLabel("\(p.name) is here")
                        }
                    }
                } header: {
                    Text("Not Here Yet · \(away.count)")
                } footer: {
                    Text("Tap Here when they arrive. Before the first game they line up in the order they arrive; after that, like a late arrival.")
                }
            }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func queueRow(_ p: Player, position: Int?) -> some View {
        HStack(spacing: 10) {
            // Tap the player to edit their name or rating.
            HStack(spacing: 10) {
                Group {
                    if let position { Text("\(position)") } else { Image(systemName: "pause.circle") }
                }
                .font(.headline).monospacedDigit().foregroundStyle(.secondary)
                .lineLimit(1).fixedSize()
                .frame(minWidth: 28, alignment: .trailing)
                .accessibilityLabel(position.map { "Number \($0)" } ?? "Sitting out")
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.body.weight(.semibold)).lineLimit(1)
                    Text("\(s.played(p.id)) played · \(s.wins(p.id)) won")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .onTapGesture { editing = p }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Edit name or rating")
            // Rating with what they play underneath, so the name and stats keep the row's width
            VStack(spacing: 4) {
                VStack(spacing: 1) {
                    SkillDots(skill: p.skill).padding(.vertical, -4)
                    Text(p.skill, format: .number.precision(.fractionLength(1)))
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
                .onTapGesture { editing = p }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Skill \(skillNames[p.level - 1]), rating \(p.skill.formatted(.number.precision(.fractionLength(1))))")
                prefMenu(p)
            }
            .fixedSize()
        }
        .opacity(p.paused ? 0.5 : 1)
        // Press and hold: a narrow column makes swipes easy to overshoot into Remove.
        .contextMenu {
            Button("Edit Name or Rating", systemImage: "pencil") { editing = p }
            Button(p.paused ? "Back In" : "Sit Out", systemImage: p.paused ? "play" : "pause") {
                s.update(p.id) { $0.paused.toggle() } // the wait clock keeps running while sitting out
            }
            Button("Move to Front", systemImage: "arrow.up.to.line") { s.moveToFront(p.id) }
            Button("Not Here", systemImage: "person.slash") { s.update(p.id) { $0.away = true } }
            Divider()
            Button("Remove from Session", systemImage: "trash", role: .destructive) { removing = p }
        }
    }

    /// One court's next game in Up Next: team on one line, a red VS, the other team underneath.
    private func upNextRow(_ label: String, format: Format, pairing p: Pairing?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(format == .singles ? Color.singles : Color.doubles)
            if let p {
                Text(names(p.a.map(\.id))).font(.subheadline.weight(.semibold))
                Text("VS").font(.caption.weight(.heavy)).foregroundStyle(.red)
                Text(names(p.b.map(\.id))).font(.subheadline.weight(.semibold))
            } else {
                Text("Waiting for available players").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// What a player plays (Any / Singles / Doubles); tap to change.
    private func prefMenu(_ p: Player) -> some View {
        Menu {
            Picker("Plays", selection: Binding(get: { p.pref }, set: { v in s.update(p.id) { $0.pref = v } })) {
                ForEach(Preference.allCases, id: \.self) { Text($0.rawValue.capitalized) }
            }
        } label: {
            Text(p.pref.rawValue.uppercased())
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .foregroundStyle(p.pref == .singles ? Color.singles : p.pref == .doubles ? Color.doubles : .secondary)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
        }
    }

    /// Saves an edit. A rename also applies to this person in earlier sessions, so they stay one person
    /// in "Add from Earlier Sessions".
    private func save(_ p: Player, name: String, skill: Double, pref: Preference, paused: Bool, present: Bool) {
        let old = p.name.lowercased()
        s.update(p.id) { $0.name = name; $0.skill = skill; $0.pref = pref; $0.paused = paused }
        if present { s.arrive(p.id) } else { s.update(p.id) { $0.away = true } }
        guard old != name.lowercased() else { return }
        for i in past.indices {
            for j in past[i].players.indices where past[i].players[j].name.lowercased() == old {
                past[i].players[j].name = name
            }
        }
    }

    private func names(_ ids: [UUID]) -> String {
        ids.compactMap { s.player($0)?.name }.joined(separator: " & ")
    }
}

struct ReplaceTarget: Identifiable {
    var id: UUID { out.id }
    var courtID: UUID
    var courtName: String
    var out: Player
}

/// Swap one player in a court's "Next up" game for someone else waiting.
struct ReplacePlayerSheet: View {
    @Binding var s: SessionState
    let target: ReplaceTarget
    @Environment(\.dismiss) private var dismiss
    @State private var unevenPick: Player?
    @State private var knockOn: SessionState.KnockOn?
    @State private var before: SessionState?

    var body: some View {
        let all = s.replacements(for: target.out.id, on: target.courtID)
        // Best fit: keeps the game even and is close to the replaced player's level. Everyone else, closest level first.
        let gap = { (p: Player) in abs(p.skill - target.out.skill) }
        let best = all.filter { $0.even && gap($0.player) <= 1 }
        let rest = all.filter { !($0.even && gap($0.player) <= 1) }.sorted { gap($0.player) < gap($1.player) }
        NavigationStack {
            List {
                if all.isEmpty {
                    Text("Nobody else is waiting who can play this game.").foregroundStyle(.secondary)
                }
                if !best.isEmpty {
                    Section {
                        ForEach(best, id: \.player.id) { c in row(c.player, from: c.from) { apply(c.player) } }
                    } header: {
                        Text("Best fit · similar level, keeps the game even")
                    } footer: {
                        Text("Fewest games first. Picking someone already lined up on another court moves them here; that court gets a replacement.")
                    }
                }
                if !rest.isEmpty {
                    Section("Less of a fit · closest level first") {
                        ForEach(rest, id: \.player.id) { c in
                            row(c.player, from: c.from, uneven: !c.even) { if c.even { apply(c.player) } else { unevenPick = c.player } }
                        }
                    }
                }
            }
            .navigationTitle("Replace \(target.out.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Uneven matchup", isPresented: Binding(get: { unevenPick != nil }, set: { if !$0 { unevenPick = nil } }), presenting: unevenPick) { p in
                Button("Use \(p.name)") { apply(p) }
                Button("Cancel", role: .cancel) {}
            } message: { p in
                Text("With \(p.name) instead of \(target.out.name), one side on \(target.courtName) is noticeably stronger.")
            }
            .alert("\(knockOn?.court ?? "") is now uneven", isPresented: Binding(get: { knockOn != nil }, set: { if !$0 { knockOn = nil } }), presenting: knockOn) { k in
                Button("Accept") { dismiss() }
                Button("Undo", role: .cancel) { if let before { s = before }; dismiss() }
            } message: { k in
                if let incoming = k.incoming {
                    Text("\(k.lost) moved to \(target.courtName), so \(incoming) joins \(k.court) instead. Nobody waiting keeps that game even.")
                } else {
                    Text("\(k.lost) moved to \(target.courtName). Nobody else is free for \(k.court), so it waits for players.")
                }
            }
        }
    }

    private func row(_ p: Player, from: String?, uneven: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text("\(s.played(p.id)) played\(uneven ? " · makes it uneven" : "")\(from.map { " · next up on \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(from == nil && !uneven ? Color.secondary : Color.singles)
                }
                Spacer()
                VStack(spacing: 1) {
                    SkillDots(skill: p.skill).padding(.vertical, -4)
                    Text(p.skill, format: .number.precision(.fractionLength(1)))
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }

    private func apply(_ p: Player) {
        before = s
        let k = s.replace(target.out.id, with: p.id, on: target.courtID)
        if let k, !k.even { knockOn = k } else { dismiss() }
    }
}

/// Change a player's name or rating. Ratings still move after every win or loss; this sets where they are now.
struct EditPlayerSheet: View {
    let player: Player
    let played: Int
    let won: Int
    let takenNames: Set<String>
    let onSave: (_ name: String, _ skill: Double, _ pref: Preference, _ paused: Bool, _ present: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var skill = 3.0
    @State private var pref = Preference.any
    @State private var paused = false
    @State private var present = true

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var duplicate: Bool { takenNames.contains(trimmed.lowercased()) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).font(.title3.weight(.semibold))
                } footer: {
                    if duplicate { Text("Another player in this session is already called \(trimmed).").foregroundStyle(.red) }
                }
                Section {
                    HStack {
                        SkillDots(skill: skill)
                        Text(skillNames[min(5, max(1, Int(skill.rounded()))) - 1])
                        Spacer()
                        Text(skill, format: .number.precision(.fractionLength(1)))
                            .font(.title3.weight(.bold)).monospacedDigit()
                    }
                    Slider(value: $skill, in: 1...5, step: 0.1) {
                        Text("Rating")
                    } minimumValueLabel: {
                        Text("1")
                    } maximumValueLabel: {
                        Text("5")
                    }
                    Picker("Set level", selection: Binding(get: { min(5, max(1, Int(skill.rounded()))) }, set: { skill = Double($0) })) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Rating")
                } footer: {
                    Text("Wins and losses keep adjusting this. \(played) played · \(won) won this session.")
                }
                Section {
                    Picker("Plays", selection: $pref) {
                        ForEach(Preference.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Sitting out", isOn: $paused)
                } header: {
                    Text("Plays")
                } footer: {
                    Text("Sitting out keeps their place in line; their wait clock keeps running.")
                }
                Section {
                    Toggle("Present", isOn: $present)
                } footer: {
                    Text("Off until they arrive. Turned on, they join the line like a late arrival, with their wait starting then.")
                }
            }
            .navigationTitle("Edit Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(trimmed, (skill * 10).rounded() / 10, pref, paused, present); dismiss() }
                        .disabled(trimmed.isEmpty || duplicate)
                }
            }
            .onAppear { name = player.name; skill = player.skill; pref = player.pref; paused = player.paused; present = player.away != true }
        }
    }
}

/// Pick people who played in earlier sessions and add them to this one.
struct ReturningPlayersSheet: View {
    @Binding var s: SessionState
    let past: [SessionState]
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [String] = [] // names, in the order tapped = their queue order
    @State private var search = ""

    var body: some View {
        let all = s.returningPlayers(from: past)
        let shown = search.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(search) }
        NavigationStack {
            List {
                if all.isEmpty {
                    Text(past.isEmpty ? "No earlier sessions yet. Players you add today will show up here next time."
                                      : "Everyone from earlier sessions is already in this one.")
                        .foregroundStyle(.secondary)
                }
                ForEach(shown, id: \.name) { p in
                    Button {
                        if let i = picked.firstIndex(of: p.name) { picked.remove(at: i) } else { picked.append(p.name) }
                    } label: {
                        HStack {
                            Image(systemName: picked.contains(p.name) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(picked.contains(p.name) ? Color.court : .secondary)
                                .font(.title3)
                            Text(p.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Spacer()
                            SkillDots(skill: p.skill)
                            Text(p.skill, format: .number.precision(.fractionLength(1)))
                                .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityAddTraits(picked.contains(p.name) ? .isSelected : [])
                }
            }
            .searchable(text: $search, prompt: "Search players")
            .navigationTitle("Earlier Players")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(picked.isEmpty ? "Add" : "Add \(picked.count)") {
                        s.addReturning(picked.compactMap { name in all.first { $0.name == name } })
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                }
                if !all.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button(picked.count == all.count ? "Clear All" : "Select All") {
                            picked = picked.count == all.count ? [] : all.map(\.name)
                        }
                    }
                }
            }
        }
    }
}

struct SessionsSheet: View {
    @Binding var s: SessionState
    @Binding var past: [SessionState]
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: SessionState?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("New Session with Same Players", systemImage: "person.2") { start(s.next(keepPlayers: true)) }
                    Button("New Empty Session", systemImage: "plus") { start(s.next(keepPlayers: false)) }
                }
                Section("Current") { row(s).swipeActions { deleteAction(s) } }
                if !past.isEmpty {
                    Section("Earlier") {
                        ForEach(past.sorted { $0.date > $1.date }) { old in
                            Button { open(old) } label: { row(old) }
                                .tint(.primary)
                                .swipeActions { deleteAction(old) }
                        }
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .confirmationDialog("Delete this session and its results?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { d in
                Button("Delete Session", role: .destructive) { delete(d) }
            } message: { d in
                Text("\(d.date.formatted(date: .abbreviated, time: .shortened)) · ^[\(d.results.count) game](inflect: true). This can't be undone.")
            }
        }
    }

    private func row(_ x: SessionState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(x.date.formatted(.dateTime.weekday(.wide).day().month().hour().minute())).font(.body.weight(.semibold))
            Text("\(x.tournament == nil ? "" : "Tournament · ")^[\(x.players.count) player](inflect: true) · ^[\(x.results.count) game](inflect: true)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func deleteAction(_ x: SessionState) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive) { deleting = x }
    }

    private func start(_ fresh: SessionState) {
        past.append(s)
        s = fresh
        dismiss()
    }

    private func open(_ old: SessionState) {
        past.removeAll { $0.id == old.id }
        past.append(s)
        s = old
        dismiss()
    }

    private func delete(_ d: SessionState) {
        if d.id == s.id {
            // Deleting the one on screen: fall back to the most recent earlier session, or a fresh one.
            let latest = past.max { $0.date < $1.date }
            past.removeAll { $0.id == latest?.id }
            s = latest ?? s.next(keepPlayers: false)
        } else {
            past.removeAll { $0.id == d.id }
        }
    }
}

struct StandingsSheet: View {
    @Binding var s: SessionState
    @Environment(\.dismiss) private var dismiss
    @State private var tab = "Standings"

    var body: some View {
        NavigationStack {
            List {
                if tab == "Standings" { standings } else { history }
            }
            .navigationTitle("^[\(s.results.count) game](inflect: true) played")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $tab) {
                        Text("Standings").tag("Standings")
                        Text("Match History").tag("Match History")
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder private var standings: some View {
        let rows = s.players
            .map { (p: $0, w: s.wins($0.id), n: s.played($0.id), score: s.score($0.id)) }
            .sorted { ($0.n > 0 ? 1 : 0, $0.score, $0.w) > ($1.n > 0 ? 1 : 0, $1.score, $1.w) } // anyone yet to play goes last
        if rows.isEmpty { Text("No players yet.").foregroundStyle(.secondary) }
        let top = Array(rows.filter { $0.w > 0 }.prefix(3))
        if !top.isEmpty {
            Section { podium(top) }.listRowBackground(Color.clear)
        }
        Section {
            ForEach(Array(rows.enumerated()), id: \.element.p.id) { i, r in
                HStack(spacing: 12) {
                    // Rank, in medal colours for the top three; anyone yet to play has no rank.
                    Text(r.n > 0 ? "\(i + 1)" : "–")
                        .font(.subheadline.weight(.heavy)).monospacedDigit()
                        .foregroundStyle(r.n > 0 && i < 3 ? .white : .secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(r.n > 0 && i < 3 ? PodiumPlace.medal(i + 1)[1] : Color(.tertiarySystemFill)))
                    Text(r.p.name).font(.body.weight(.semibold))
                    Spacer()
                    Grid(horizontalSpacing: 18) {
                        GridRow {
                            stat(r.w, "Won")
                            stat(r.n, "Played")
                            stat(r.n == 0 ? nil : Int((Double(r.w) * 100 / Double(r.n)).rounded()), "Win %")
                            stat(r.n == 0 ? nil : r.score, "Score")
                        }
                    }
                }
            }
        } header: {
            if !top.isEmpty { Text("All players") }
        } footer: {
            Text("Ranked by Score: wins and losses decide it, and game length nudges it: a quicker, more one-sided win counts a little more, and a close loss still counts a little. Score starts everyone at 50 so one or two lucky games can't top the table.")
        }
    }

    /// Top three with a win, laid out 2nd · 1st · 3rd on a court-green stage.
    private func podium(_ top: [(p: Player, w: Int, n: Int, score: Double)]) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach([1, 0, 2].filter { $0 < top.count }, id: \.self) { i in
                PodiumPlace(rank: i + 1, name: top[i].p.name, won: top[i].w, played: top[i].n, score: top[i].score)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .background { ArenaBackdrop().clipShape(RoundedRectangle(cornerRadius: 20)) }
        .listRowInsets(EdgeInsets())
    }

    /// Newest first. Swipe to delete a game entered by mistake; standings update with it.
    @ViewBuilder private var history: some View {
        if s.results.isEmpty { Text("Finished games show up here.").foregroundStyle(.secondary) }
        ForEach(s.results.indices.reversed(), id: \.self) { i in
            let r = s.results[i]
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(r.teamA.count == 1 ? "SINGLES" : "DOUBLES")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(r.teamA.count == 1 ? Color.singles : Color.doubles)
                    Text("\(r.court)\(r.tournamentLabel.map { " · \($0)" } ?? "") · \(r.end.formatted(date: .omitted, time: .shortened)) · \(Int(r.end.timeIntervalSince(r.start) / 60)) min")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Text("Game \(i + 1)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack(spacing: 10) {
                    team(r.teamA, won: r.winner == 0)
                    Text("vs").font(.caption).foregroundStyle(.secondary)
                    team(r.teamB, won: r.winner == 1)
                    if r.winner == nil {
                        Text("No result").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
            .swipeActions {
                Button("Delete", systemImage: "trash", role: .destructive) { s.deleteResult(at: i) }
            }
        }
    }

    private func team(_ ids: [UUID], won: Bool) -> some View {
        HStack(spacing: 4) {
            if won { Image(systemName: "trophy.fill").foregroundStyle(Color.singles).accessibilityLabel("Winner") }
            Text(ids.map { s.player($0)?.name ?? "Removed player" }.joined(separator: " & "))
                .font(.body.weight(won ? .bold : .regular))
                .foregroundStyle(won ? .primary : .secondary)
        }
    }

    private func stat(_ v: Int?, _ label: String) -> some View {
        stat(v.map(String.init), label)
    }

    private func stat(_ v: Double?, _ label: String) -> some View {
        stat(v?.formatted(.number.precision(.fractionLength(1))), label)
    }

    private func stat(_ v: String?, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(v ?? "–").font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 44)
    }
}

struct SkillDots: View {
    let skill: Double
    var tint: Color = .court

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle().fill(i <= Int(skill.rounded()) ? tint : tint.opacity(0.2)).frame(width: 7, height: 7)
            }
        }
        .padding(.vertical, 6)
    }
}

/// A court seen from above: net in the middle, singles sidelines bold when it's a singles court.
struct CourtDrawing: View {
    let format: Format
    let teams: ([Player], [Player])?
    let isPreview: Bool
    var onTap: ((Player) -> Void)? = nil // tap a name to replace that player (open courts only)
    var locked: Int? = nil
    var onLock: ((Int) -> Void)? = nil // lock a side so shuffle changes only the other one (open courts only)

    var body: some View {
        ZStack {
            Rectangle().fill(Color.court)
            GeometryReader { g in
                let w = g.size.width, h = g.size.height, inset = h * 0.08
                Path { p in
                    p.move(to: CGPoint(x: 0, y: inset)); p.addLine(to: CGPoint(x: w, y: inset))
                    p.move(to: CGPoint(x: 0, y: h - inset)); p.addLine(to: CGPoint(x: w, y: h - inset))
                }
                .stroke(.white.opacity(format == .singles ? 0.9 : 0.35), lineWidth: format == .singles ? 2 : 1)
                Path { p in
                    p.move(to: CGPoint(x: w / 2, y: -4)); p.addLine(to: CGPoint(x: w / 2, y: h + 4))
                }
                .stroke(.white, lineWidth: 3)
            }
            Rectangle().strokeBorder(.white.opacity(0.9), lineWidth: 2)

            HStack(spacing: 0) {
                side(teams?.0).opacity(isPreview ? 0.55 : 1).overlay(alignment: .topLeading) { lockButton(0) }
                side(teams?.1).opacity(isPreview ? 0.55 : 1).overlay(alignment: .topTrailing) { lockButton(1) }
            }
        }
        .aspectRatio(2.2, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder private func lockButton(_ side: Int) -> some View {
        if let onLock {
            let on = locked == side
            Button { onLock(side) } label: {
                Image(systemName: on ? "lock.fill" : "lock.open")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(on ? Color.court : .white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(on ? .white : .black.opacity(0.25)))
                    .frame(width: 44, height: 44) // full-size touch target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel(on ? "Unlock \(side == 0 ? "left" : "right") side" : "Lock \(side == 0 ? "left" : "right") side")
            .accessibilityHint("A locked side stays when you shuffle")
        }
    }

    private func side(_ players: [Player]?) -> some View {
        VStack(spacing: 8) {
            if let players {
                ForEach(players) { p in
                    let label = VStack(spacing: 2) {
                        Text(p.name).font(.title.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.5)
                        SkillDots(skill: p.skill, tint: .white).padding(.vertical, -4)
                    }
                    if let onTap {
                        Button { onTap(p) } label: { label.padding(.horizontal, 8).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Replace \(p.name)")
                    } else {
                        label
                    }
                }
            } else {
                Text(format == .singles ? "1 v 1" : "2 v 2").font(.subheadline).opacity(0.7)
            }
        }
        .foregroundStyle(.white)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView(s: .constant(SessionState()), past: .constant([]))
}

/// One place on the standings podium: a medal-colored badge with the player's initials, then a step that rises into view.
struct PodiumPlace: View {
    let rank: Int, name: String, won: Int, played: Int, score: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var risen = false

    static func medal(_ rank: Int) -> [Color] {
        switch rank {
        case 1: [Color(red: 1, green: 0.84, blue: 0.35), Color(red: 0.8, green: 0.56, blue: 0.05)]
        case 2: [Color(red: 0.9, green: 0.92, blue: 0.95), Color(red: 0.58, green: 0.62, blue: 0.67)]
        default: [Color(red: 0.93, green: 0.64, blue: 0.4), Color(red: 0.62, green: 0.35, blue: 0.16)]
        }
    }
    private var colors: [Color] { Self.medal(rank) }
    private var initials: String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }

    var body: some View {
        let medal = LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        VStack(spacing: 6) {
            // A gold shuttlecock above the winner; the others keep the space so all three badges share a baseline.
            ShuttlecockIcon(colors: colors)
                .frame(width: 28, height: 35)
                .shadow(color: colors[0].opacity(0.8), radius: 6)
                .opacity(rank == 1 ? 1 : 0)
            Text(initials)
                .font(.system(size: rank == 1 ? 26 : 21, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                .frame(width: rank == 1 ? 70 : 58, height: rank == 1 ? 70 : 58)
                .background(Circle().fill(medal))
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3))
                .shadow(color: colors[0].opacity(0.6), radius: rank == 1 ? 14 : 8)
            Text(name)
                .font(.headline).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 6) {
                Text("\(won)–\(played - won)")
                Text(score, format: .number.precision(.fractionLength(1)))
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Capsule().fill(.white.opacity(0.2)))
            }
            .font(.caption.weight(.semibold)).monospacedDigit()
            .foregroundStyle(.white.opacity(0.85))
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                // Lit top edge, like a polished block
                Capsule().fill(.white.opacity(0.45)).frame(height: 5).padding(.horizontal, 14).padding(.top, 6)
                Text("\(rank)")
                    .font(.system(size: rank == 1 ? 52 : 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
                    .padding(.top, 14)
            }
            .frame(height: [0, 130, 96, 74][rank])
            .scaleEffect(x: 1, y: risen ? 1 : 0.02, anchor: .bottom)
        }
        .frame(maxWidth: .infinity)
        .opacity(risen ? 1 : 0)
        .onAppear {
            guard !risen else { return }
            if reduceMotion { risen = true; return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay([0, 0.3, 0.15, 0][rank])) { risen = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Place \(rank): \(name), \(won) of \(played) won, score \(score.formatted(.number.precision(.fractionLength(1))))")
    }
}

/// A shuttlecock, cork down: a fanned skirt of feathers with ribs and a thread band, on a rounded cork.
struct ShuttlecockIcon: View {
    var colors: [Color]
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var skirt = Path()
            skirt.move(to: CGPoint(x: w * 0.36, y: h * 0.7))
            skirt.addLine(to: CGPoint(x: w * 0.02, y: h * 0.06))
            skirt.addQuadCurve(to: CGPoint(x: w * 0.98, y: h * 0.06), control: CGPoint(x: w * 0.5, y: h * 0.16))
            skirt.addLine(to: CGPoint(x: w * 0.64, y: h * 0.7))
            skirt.closeSubpath()
            ctx.fill(skirt, with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            var ribs = Path()
            for f in [0.2, 0.35, 0.5, 0.65, 0.8] {
                ribs.move(to: CGPoint(x: w * (0.4 + (f - 0.5) * 0.3), y: h * 0.68))
                ribs.addLine(to: CGPoint(x: w * f, y: h * (0.1 - abs(f - 0.5) * 0.08)))
            }
            ribs.move(to: CGPoint(x: w * 0.2, y: h * 0.38)); ribs.addQuadCurve(to: CGPoint(x: w * 0.8, y: h * 0.38), control: CGPoint(x: w * 0.5, y: h * 0.44))
            ctx.stroke(ribs, with: .color(.white.opacity(0.7)), lineWidth: 0.8)
            let cork = Path(ellipseIn: CGRect(x: w * 0.28, y: h * 0.64, width: w * 0.44, height: h * 0.34))
            ctx.fill(cork, with: .color(.white))
            ctx.stroke(cork, with: .color(colors[1]), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// The podium's stage: an arena at night. Floodlights from the top corners, a net with posts behind the podium, court lines
/// running in perspective across the floor, a shuttle's dashed flight over the net, and crossed rackets behind the champion.
struct ArenaBackdrop: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, horizon = h * 0.56
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.04, green: 0.13, blue: 0.1), Color(red: 0.08, green: 0.27, blue: 0.19), Color.court]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            // Floodlights
            for x in [0.1, 0.9] {
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.2), .clear]), center: CGPoint(x: w * x, y: -h * 0.05), startRadius: 0, endRadius: w * 0.42))
            }
            // Court floor: doubles and singles sidelines and the centre line meet towards a vanishing point; two service lines across.
            var floor = Path()
            let vanish = CGPoint(x: w / 2, y: horizon - h * 1.4)
            for fx in [-0.08, 0.06, 0.5, 0.94, 1.08] {
                let bottom = CGPoint(x: w * fx, y: h), t = (h - horizon) / (h - vanish.y)
                floor.move(to: bottom); floor.addLine(to: CGPoint(x: bottom.x + (vanish.x - bottom.x) * t, y: horizon))
            }
            for fy in [0.7, 0.86] { floor.move(to: CGPoint(x: 0, y: h * fy)); floor.addLine(to: CGPoint(x: w, y: h * fy)) }
            floor.move(to: CGPoint(x: 0, y: horizon)); floor.addLine(to: CGPoint(x: w, y: horizon))
            ctx.stroke(floor, with: .color(.white.opacity(0.16)), lineWidth: 1.5)
            // Crossed rackets, faint, behind the champion
            ctx.drawLayer { layer in
                layer.opacity = 0.13
                let c = CGPoint(x: w / 2, y: h * 0.3), size = min(w, h) * 0.34
                for angle in [-0.55, 0.55] {
                    layer.drawLayer { r in
                        r.translateBy(x: c.x, y: c.y); r.rotate(by: .radians(angle))
                        let head = CGRect(x: -size * 0.24, y: -size * 0.62, width: size * 0.48, height: size * 0.62)
                        r.stroke(Path(ellipseIn: head), with: .color(.white), lineWidth: 3)
                        r.drawLayer { strings in
                            strings.clip(to: Path(ellipseIn: head.insetBy(dx: 2, dy: 2)))
                            var grid = Path()
                            for x in stride(from: head.minX, through: head.maxX, by: size * 0.06) { grid.move(to: CGPoint(x: x, y: head.minY)); grid.addLine(to: CGPoint(x: x, y: head.maxY)) }
                            for y in stride(from: head.minY, through: head.maxY, by: size * 0.06) { grid.move(to: CGPoint(x: head.minX, y: y)); grid.addLine(to: CGPoint(x: head.maxX, y: y)) }
                            strings.stroke(grid, with: .color(.white), lineWidth: 0.7)
                        }
                        var shaft = Path()
                        shaft.move(to: CGPoint(x: 0, y: head.maxY)); shaft.addLine(to: CGPoint(x: 0, y: size * 0.3))
                        r.stroke(shaft, with: .color(.white), lineWidth: 2.5)
                        r.fill(Path(roundedRect: CGRect(x: -size * 0.035, y: size * 0.3, width: size * 0.07, height: size * 0.28), cornerRadius: 3), with: .color(.white))
                    }
                }
            }
            // The net: mesh, white tape along the top, a post at each end.
            let net = CGRect(x: w * 0.05, y: horizon - h * 0.2, width: w * 0.9, height: h * 0.2)
            var mesh = Path()
            for x in stride(from: net.minX, through: net.maxX, by: 7) { mesh.move(to: CGPoint(x: x, y: net.minY)); mesh.addLine(to: CGPoint(x: x, y: net.maxY)) }
            for y in stride(from: net.minY, through: net.maxY, by: 7) { mesh.move(to: CGPoint(x: net.minX, y: y)); mesh.addLine(to: CGPoint(x: net.maxX, y: y)) }
            ctx.stroke(mesh, with: .color(.white.opacity(0.09)), lineWidth: 0.6)
            ctx.fill(Path(CGRect(x: net.minX, y: net.minY, width: net.width, height: 3)), with: .color(.white.opacity(0.75)))
            for x in [net.minX - 3, net.maxX - 1] {
                ctx.fill(Path(roundedRect: CGRect(x: x, y: net.minY - 6, width: 4, height: net.height + 12), cornerRadius: 2), with: .color(.white.opacity(0.6)))
            }
            // A shuttle's flight over the net
            var flight = Path()
            flight.move(to: CGPoint(x: w * 0.1, y: net.minY - 10))
            flight.addQuadCurve(to: CGPoint(x: w * 0.88, y: h * 0.12), control: CGPoint(x: w * 0.4, y: -h * 0.06))
            ctx.stroke(flight, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 6]))
            var tip = Path()
            tip.addEllipse(in: CGRect(x: w * 0.88 - 3, y: h * 0.12 - 3, width: 6, height: 6))
            ctx.fill(tip, with: .color(.white.opacity(0.85)))
        }
        .accessibilityHidden(true)
    }
}

/// Everyone ever registered in the app, across all sessions, with their latest rating and totals.
struct AllPlayersSheet: View {
    let sessions: [SessionState]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        let all = SessionState.registry(sessions)
        let shown = search.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(search) }
        NavigationStack {
            List {
                if all.isEmpty { Text("No players yet.").foregroundStyle(.secondary) }
                ForEach(shown) { r in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(.body.weight(.semibold))
                            Text("\(r.sessions) session\(r.sessions == 1 ? "" : "s") · \(r.played) played · \(r.won) won · last \(r.lastSeen.formatted(.dateTime.month(.abbreviated).day()))")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer()
                        VStack(spacing: 1) {
                            SkillDots(skill: r.skill).padding(.vertical, -4)
                            Text(r.skill, format: .number.precision(.fractionLength(1)))
                                .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .searchable(text: $search, prompt: "Search players")
            .navigationTitle("All Players · \(all.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Everyone in this session at a glance: where they are, games, what they play and rating. Tap one to edit.
struct SessionPlayersSheet: View {
    @Binding var s: SessionState
    let past: [SessionState]
    let onSave: (Player, String, Double, Preference, Bool, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var editing: Player?
    @State private var addingNew = false
    @State private var addingReturning = false

    var body: some View {
        let line = s.queue.filter { !$0.paused }.map(\.id)
        let onCourt = Dictionary(s.courts.flatMap { c in (c.match.map { $0.teamA + $0.teamB } ?? []).map { ($0, c.name) } },
                                 uniquingKeysWith: { a, _ in a })
        let all = s.players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let shown = search.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(search) }
        let sitting = s.players.filter { $0.paused && $0.away != true && onCourt[$0.id] == nil }.count
        let away = s.players.filter { $0.away == true && onCourt[$0.id] == nil }.count
        NavigationStack {
            List {
                Section {
                    if all.isEmpty { Text("No players in this session yet.").foregroundStyle(.secondary) }
                    ForEach(shown) { p in
                        let status = onCourt[p.id].map { "On \($0)" }
                            ?? (p.away == true ? "Not here" : p.paused ? "Sitting out" : line.firstIndex(of: p.id).map { "Waiting · #\($0 + 1)" } ?? "Waiting")
                        Button { editing = p } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.body.weight(.semibold))
                                    Text("\(status) · \(s.played(p.id)) played · \(s.wins(p.id)) won")
                                        .font(.caption).foregroundStyle(onCourt[p.id] != nil ? Color.court : .secondary)
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                }
                                Spacer()
                                Text(p.pref.rawValue.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(p.pref == .singles ? Color.singles : p.pref == .doubles ? Color.doubles : .secondary)
                                VStack(spacing: 1) {
                                    SkillDots(skill: p.skill).padding(.vertical, -4)
                                    Text(p.skill, format: .number.precision(.fractionLength(1)))
                                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity((p.paused || p.away == true) && onCourt[p.id] == nil ? 0.6 : 1)
                        .accessibilityHint("Edit player")
                    }
                } header: {
                    Text("\(all.count) players · \(onCourt.count) playing · \(line.count) waiting · \(sitting) sitting out\(away > 0 ? " · \(away) not here" : "")")
                } footer: {
                    Text("Tap a player to edit their name, rating, what they play, sit them out, or mark them present.")
                }
            }
            .searchable(text: $search, prompt: "Search players")
            .navigationTitle("Session Players")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Add Player", systemImage: "person.badge.plus") {
                        Button("New Player", systemImage: "person.badge.plus") { addingNew = true }
                        Button("From Earlier Sessions", systemImage: "clock.arrow.circlepath") { addingReturning = true }
                    }
                    .disabled(s.tournament != nil)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $addingNew) { AddPlayerSheet(s: $s) }
            .sheet(isPresented: $addingReturning) { ReturningPlayersSheet(s: $s, past: past) }
            .sheet(item: $editing) { p in
                EditPlayerSheet(player: p, played: s.played(p.id), won: s.wins(p.id),
                                takenNames: Set(s.players.filter { $0.id != p.id }.map { $0.name.lowercased() })) { name, skill, pref, paused, present in
                    onSave(p, name, skill, pref, paused, present)
                }
            }
        }
    }
}

/// Partner requests, kept in Options so they don't show on the main screen: each pair is teamed up
/// about every other game when a fair game allows.
struct PairingSheet: View {
    @Binding var s: SessionState
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false

    /// Each two-way request once.
    private var pairs: [(Player, Player)] {
        s.players.compactMap { p in
            guard let q = p.partner.flatMap(s.player), q.partner == p.id, p.id.uuidString < q.id.uuidString else { return nil }
            return (p, q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !s.pairingActive {
                    Section {
                        Label("On hold until there are \(s.pairingMinimum) players for \(s.courts.count) court\(s.courts.count == 1 ? "" : "s"). There \(s.activePlayers == 1 ? "is" : "are") \(s.activePlayers) now, not counting anyone sitting out.",
                              systemImage: "pause.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    if pairs.isEmpty { Text("No pair requests.").foregroundStyle(.secondary) }
                    ForEach(pairs, id: \.0.id) { a, b in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(a.name) & \(b.name)")
                                Text(s.pairPlayed(a.id, b.id) ? "Played together" : "Waiting").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove", systemImage: "trash", role: .destructive) { s.setPartner(a.id, nil) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove pair request for \(a.name) and \(b.name)")
                        }
                    }
                    Button("Add Pair Request", systemImage: "plus") { adding = true }
                        .disabled(!s.pairingActive)
                } footer: {
                    Text("Each pair plays one game together this session, with even teams, one pair at a time. After that they're treated like everyone else. Needs at least twice the players the courts take, minus two.")
                }
            }
            .navigationTitle("Increase Pairing %")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(isPresented: $adding) { AddPairForm(s: $s) }
        }
    }
}

/// Picks two players without a request yet.
struct AddPairForm: View {
    @Binding var s: SessionState
    @Environment(\.dismiss) private var dismiss
    @State private var first: UUID?
    @State private var second: UUID?

    var body: some View {
        let free = s.players.filter { $0.pref != .singles && $0.partner.flatMap(s.player) == nil }
        Form {
            Picker("Player", selection: $first) {
                Text("Choose").tag(UUID?.none)
                ForEach(free.filter { $0.id != second }) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Partner", selection: $second) {
                Text("Choose").tag(UUID?.none)
                ForEach(free.filter { $0.id != first }) { Text($0.name).tag(Optional($0.id)) }
            }
        }
        .navigationTitle("Add Pair Request")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { if let first, let second { s.setPartner(first, second) }; dismiss() }
                    .disabled(first == nil || second == nil)
            }
        }
    }
}

/// Add players as they arrive. Stays open so several can be added in a row.
struct AddPlayerSheet: View {
    @Binding var s: SessionState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var skill = 3
    @State private var added: [String] = []
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var duplicate: Bool { s.players.contains { $0.name.lowercased() == trimmed.lowercased() } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Player name", text: $name)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Picker("Skill", selection: $skill) {
                        ForEach(1...5, id: \.self) { Text(skillNames[$0 - 1]) }
                    }
                } footer: {
                    if duplicate { Text("\(trimmed) is already in this session.").foregroundStyle(.red) }
                }
                if !added.isEmpty {
                    Section("Added") { Text(added.joined(separator: ", ")) }
                }
            }
            .navigationTitle("Add Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add).disabled(trimmed.isEmpty || duplicate)
                }
            }
            .onAppear { focused = true }
        }
    }

    private func add() {
        guard !trimmed.isEmpty, !duplicate else { return }
        s.addPlayer(trimmed, skill: Double(skill))
        added.append(trimmed)
        name = ""
        focused = true
    }
}
