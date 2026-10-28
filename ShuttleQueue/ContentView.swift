import SwiftUI
import UniformTypeIdentifiers

extension Color {
    static let court = Color(red: 0, green: 0.451, blue: 0.580)
    static let playingCourt = Color(red: 0.50, green: 0.20, blue: 0.22)
    static let singles = Color.orange
    static let doubles = Color.court
}

/// The main menu, where the app opens: create a session, the live sessions, past sessions, and everyone who's played.
struct HomeView: View {
    @Binding var sessions: [SessionState]
    @State private var open: UUID?
    @State private var creating = false
    @State private var showAllPlayers = false
    @State private var deleting: SessionState?

    var body: some View {
        let live = sessions.filter(\.isLive).sorted { $0.date > $1.date }
        let past = sessions.filter { !$0.isLive }.sorted { $0.date > $1.date }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Image("ClubLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .accessibilityLabel("Hampashers Badminton")
                    // Two columns with each row's tiles the same height, however the text wraps.
                    Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                        GridRow {
                            tile("Create New Session", "Name, courts, length and players", icon: "plus", tint: .court, prominent: true) { creating = true }
                            tile("All Players", "^[\(SessionState.registry(sessions).count) player](inflect: true) across all sessions",
                                 icon: "person.3", tint: .court) { showAllPlayers = true }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Live Sessions").font(.title2.bold())
                        if live.isEmpty {
                            Text("No live sessions. Create one to start.").foregroundStyle(.secondary)
                        }
                        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                            ForEach(Array(stride(from: 0, to: live.count, by: 2)), id: \.self) { i in
                                GridRow {
                                    liveCard(live[i])
                                    if i + 1 < live.count { liveCard(live[i + 1]) } else { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                                }
                            }
                        }
                    }
                    if !past.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Past Sessions").font(.title2.bold())
                            VStack(spacing: 0) {
                                ForEach(past) { x in
                                    pastRow(x)
                                    if x.id != past.last?.id { Divider().padding(.leading, 18) }
                                }
                            }
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Shuttle Queue")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ExportDataButton(sessions: sessions) } }
            .navigationDestination(item: $open) { id in
                ContentView(s: binding(id), others: sessions.filter { $0.id != id },
                            onRename: { old, new in SessionState.editEverywhere(name: old, to: new, in: &sessions, except: id) },
                            onLeave: { open = nil },
                            onDelete: {
                                open = nil
                                // ponytail: removed after the pop, so the dashboard doesn't flash empty on its way out
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { sessions.removeAll { $0.id == id } }
                            })
            }
            .sheet(isPresented: $creating) { NewSessionSheet(sessions: $sessions) { open = $0 }.capped() }
            .sheet(isPresented: $showAllPlayers) { AllPlayersSheet(sessions: $sessions).capped() }
            .confirmationDialog("Delete \(deleting?.title ?? "this session")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { d in
                Button("Delete Session", role: .destructive) { sessions.removeAll { $0.id == d.id } }
            } message: { d in
                Text("^[\(d.games.count) game](inflect: true) and its standings are deleted. This can't be undone.")
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-standings") { open = live.first?.id } // test launches open Standings directly
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true } // courtside iPad stays awake
    }

    /// A live session or the open one's data, looked up by id so other sessions can change around it.
    private func binding(_ id: UUID) -> Binding<SessionState> {
        Binding(get: { sessions.first { $0.id == id } ?? SessionState(id: id) },
                set: { v in if let i = sessions.firstIndex(where: { $0.id == id }) { sessions[i] = v } })
    }

    private func liveCard(_ x: SessionState) -> some View {
        let here = x.players.filter { $0.away != true }.count, playing = x.courts.filter { $0.match != nil }.count
        return Button { open = x.id } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(x.title).font(.title2.bold())
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.forward").font(.headline).foregroundStyle(.white.opacity(0.7))
                }
                Text("\(x.name == nil ? "" : x.date.formatted(.dateTime.weekday(.wide).day().month()) + " · ")\(here) of \(x.players.count) here · ^[\(x.courts.count) court](inflect: true)")
                    .font(.subheadline)
                Text(playing > 0 ? "^[\(playing) game](inflect: true) on court" : x.started == nil ? "Not started" : "No games on court")
                    .font(.subheadline.weight(.semibold))
                TimelineView(.periodic(from: .now, by: 60)) { ctx in
                    if let l = x.lengthLabel(now: ctx.date) { Text(l).font(.subheadline) }
                }
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.court.gradient, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .contextMenu { Button("Delete Session", systemImage: "trash", role: .destructive) { deleting = x } }
    }

    private func pastRow(_ x: SessionState) -> some View {
        Button { open = x.id } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(x.title).font(.headline)
                    Text("\(x.name == nil ? x.date.formatted(.dateTime.year()) : x.date.formatted(.dateTime.weekday().day().month().year())) · ^[\(x.players.count) player](inflect: true) · ^[\(x.games.count) game](inflect: true)\(x.ended.map { _ in " · Ended \(x.endedLabel)" } ?? "")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward").font(.subheadline.weight(.semibold)).foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reopen Session", systemImage: "arrow.uturn.backward") {
                if let i = sessions.firstIndex(where: { $0.id == x.id }) { sessions[i].reopen() }
            }
            Button("Delete Session", systemImage: "trash", role: .destructive) { deleting = x }
        }
    }

    private func tile(_ title: String, _ detail: LocalizedStringKey, icon: String, tint: Color, prominent: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2.weight(prominent ? .bold : .regular))
                    .foregroundStyle(prominent ? .white : tint)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(prominent ? .white.opacity(0.2) : tint.opacity(0.15)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.bold())
                    Text(detail).font(.subheadline).foregroundStyle(prominent ? .white.opacity(0.85) : .secondary)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(prominent ? .white : .primary)
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 100, maxHeight: .infinity, alignment: .leading)
            .background(prominent ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                        in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

extension SessionState {
    /// "2 h · until 9:30 PM · 1 hr, 20 min left", or "2 h · not started"; nil without a planned length.
    func lengthLabel(now: Date) -> String? {
        guard let h = hours else { return nil }
        let length = "\(h.formatted()) h"
        guard let end = endsAt else { return "\(length) · not started" }
        let at = end.formatted(date: .omitted, time: .shortened), left = end.timeIntervalSince(now)
        return left > 0 ? "\(length) · until \(at) · \(Duration.seconds(left).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) left"
                        : "\(length) · time's up (\(at))"
    }
}

/// A new live session: name, courts, planned length, and who's coming (copied from an earlier session and/or picked from everyone).
struct NewSessionSheet: View {
    @Binding var sessions: [SessionState]
    let onCreate: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var courts = 3
    @State private var hours = 2.0
    @State private var picked: [String] = [] // names, in order = their order in the new session
    @State private var source: UUID?
    @State private var search = ""

    var body: some View {
        let pool = SessionState().returningPlayers(from: sessions)
        let shown = search.isEmpty ? pool : pool.filter { $0.name.localizedCaseInsensitiveContains(search) }
        let earlier = sessions.filter { !$0.players.isEmpty }.sorted { $0.date > $1.date }
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Name", text: $name, prompt: Text(Date().formatted(.dateTime.weekday().day().month())))
                    Stepper("^[\(courts) court](inflect: true)", value: $courts, in: 1...8)
                    Stepper("Length: \(hours.formatted()) h", value: $hours, in: 1...6, step: 0.5)
                }
                Section {
                    Menu {
                        ForEach(earlier) { x in
                            Button("\(x.title) · ^[\(x.players.count) player](inflect: true)") { copy(from: x, pool: pool) }
                        }
                    } label: {
                        Label("Copy Players from a Session", systemImage: "doc.on.doc")
                    }
                    .disabled(earlier.isEmpty)
                    if pool.isEmpty { Text("No players yet. Add them inside the session.").foregroundStyle(.secondary) }
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
                        .tint(.primary)
                    }
                } header: {
                    HStack {
                        Text("Players · \(picked.count) picked")
                        Spacer()
                        if !pool.isEmpty {
                            Button(picked.count == pool.count ? "Clear All" : "Select All") {
                                picked = picked.count == pool.count ? [] : pool.map(\.name)
                            }
                            .font(.footnote.weight(.semibold))
                        }
                    }
                } footer: {
                    Text("Everyone starts as not here; mark them Here as they arrive. New players are added inside the session.")
                }
            }
            .searchable(text: $search, prompt: "Search players")
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create") { create(pool) } }
            }
            .onAppear {
                if let last = sessions.max(by: { $0.date < $1.date }) { courts = max(1, last.courts.count); hours = last.hours ?? 2 }
            }
        }
    }

    /// Checks everyone from that session, after anyone already picked.
    private func copy(from x: SessionState, pool: [Player]) {
        source = x.id
        for p in x.players {
            if let q = pool.first(where: { $0.name.lowercased() == p.name.lowercased() }), !picked.contains(q.name) { picked.append(q.name) }
        }
    }

    private func create(_ pool: [Player]) {
        var x = SessionState(courts: (1...courts).map { Court(name: "Court \($0)", format: .doubles) })
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        x.name = trimmed.isEmpty ? nil : trimmed
        x.hours = hours
        x.addReturning(picked.compactMap { n in pool.first { $0.name == n } })
        // Locked teammates carry over from the copied session when both partners come along.
        if let src = sessions.first(where: { $0.id == source }) {
            x.queueMatching = src.queueMatching
            let byName = { (n: String) in x.players.first { $0.name.lowercased() == n.lowercased() } }
            for p in src.players {
                guard let mate = p.lock.flatMap(src.player), let a = byName(p.name), let b = byName(mate.name) else { continue }
                x.setLock(a.id, b.id)
            }
        }
        sessions.append(x)
        dismiss()
        onCreate(x.id)
    }
}

/// Settings for this session (name, length, end or reopen, mode, courts, locked teammates) and the app's appearance.
struct SettingsSheet: View {
    @Binding var s: SessionState
    var others: [SessionState] = []
    var onEnd: () -> Void = {}
    var onDelete: () -> Void = {}
    @AppStorage("appearance") private var appearance = "system" // applied app-wide in ShuttleQueueApp
    @Environment(\.dismiss) private var dismiss
    @State private var showTournamentSetup = false
    @State private var confirmEndTournament = false
    @State private var showScheduled = false
    @State private var showLocks = false
    @State private var confirmEnd = false
    @State private var confirmDelete = false

    var body: some View {
        let playing = s.courts.filter { $0.match != nil }.count
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: Binding(get: { s.name ?? "" }, set: { s.name = $0.isEmpty ? nil : $0 }),
                              prompt: Text(s.date.formatted(.dateTime.weekday().day().month())))
                    Stepper("Length: \((s.hours ?? 2).formatted()) h", value: Binding(get: { s.hours ?? 2 }, set: { s.hours = $0 }), in: 1...6, step: 0.5)
                    if s.isLive, s.endsAt != nil, let l = s.lengthLabel(now: .now) { Text(l).foregroundStyle(.secondary) }
                    if s.isLive {
                        Button("End Session", systemImage: "flag.checkered", role: .destructive) { confirmEnd = true }
                            .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
                                Button("End Session", role: .destructive) { s.end(); dismiss(); onEnd() }
                            } message: {
                                if playing > 0 {
                                    Text("^[\(playing) game](inflect: true) still on court will be cancelled. Finish them first to record winners. The session moves to Past Sessions.")
                                } else {
                                    Text("The session moves to Past Sessions. It can be reopened.")
                                }
                            }
                    } else {
                        Button("Reopen Session", systemImage: "arrow.uturn.backward") { s.reopen() }
                    }
                    Button("Delete Session", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete Session", role: .destructive) { dismiss(); onDelete() }
                        } message: {
                            Text("^[\(s.games.count) game](inflect: true) and its standings are deleted. This can't be undone.")
                        }
                } header: { Text("Session") } footer: {
                    if s.ended != nil { Text("Ended \(s.endedLabel). Reopen it to play again.") }
                }
                Section {
                    ExportDataButton(sessions: others + [s], currentID: s.id)
                } header: { Text("Data") } footer: {
                    Text("Export all sessions, players and results. Save the file, then choose Import Data in the webapp. Importing replaces sessions with the same ID.")
                }
                Section { Button("Scheduled Matches", systemImage: "calendar") { showScheduled = true } }
                Section {
                    Picker("Mode", selection: Binding(get: { s.tournament != nil },
                                                      set: { if $0 { showTournamentSetup = true } else { confirmEndTournament = true } })) {
                        Text("Queue").tag(false)
                        Text("Tournament").tag(true)
                    }
                    .pickerStyle(.segmented)
                } header: { Text("Mode") } footer: {
                    Text("Queue rotates everyone through fair games. Tournament runs a round robin, then a double-elimination bracket.")
                }
                if s.tournament == nil {
                    Section {
                        Picker("Queue matching", selection: Binding(get: { s.matchingMode }, set: { s.setQueueMatching($0) })) {
                            ForEach(QueueMatching.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    } header: { Text("Queue matching") } footer: { Text(s.matchingHelp) }
                }
                Section("Courts") {
                    LabeledContent("Courts", value: "\(s.courts.count)")
                    Button("Add Court", systemImage: "plus.rectangle") { s.addCourt() }
                }
                Section {
                    Button("Locked Teammates", systemImage: "lock") { showLocks = true }
                }
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if let expiry = InstallExpiry.date { // apps installed from Xcode stop opening when their profile runs out
                    Section("This iPad copy") { Label(InstallExpiry.label(expiry), systemImage: "clock.badge.exclamationmark") }
                }
            }
            .navigationTitle("Session Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showTournamentSetup) { TournamentSetup(s: $s).capped() }
            .sheet(isPresented: $showScheduled) { ScheduledMatchesSheet(s: $s).capped() }
            .sheet(isPresented: $showLocks) { LockSheet(s: $s).capped() }
            .confirmationDialog("End the tournament and go back to the queue?", isPresented: $confirmEndTournament, titleVisibility: .visible) {
                Button("End Tournament", role: .destructive) { s.tournament = nil }
            } message: {
                Text("Games already played stay in Match History and Standings.")
            }
        }
    }
}

/// The dashboard: courts on the left, Up Next and the queue on the right. Opened from the Home menu.
struct ContentView: View {
    @Binding var s: SessionState
    let others: [SessionState] // every other session, for players from earlier sessions
    var onRename: (_ old: String, _ new: String) -> Void = { _, _ in } // keeps a renamed player one person across sessions
    var onLeave: () -> Void = {}
    var onDelete: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .body) private var queuePanelWidth = 280
    @ScaledMetric(relativeTo: .body) private var courtMinimumWidth = 300
    @State private var showQueue = false
    @State private var showSettings = false
    @State private var showStandings = ProcessInfo.processInfo.arguments.contains("-standings") // test launches open it directly
    @State private var showSessionPlayers = false
    @State private var showAddPlayer = false
    @State private var removing: Player?
    @State private var finishing: Court?
    @State private var showReturning = false
    @State private var editing: Player?
    @State private var replacing: ReplaceTarget?
    @State private var removingCourt: Court?
    @State private var scheduleTick = Date()
    @State private var choosing: Court? // manual mode: the court whose players are being picked

    var body: some View {
        let _ = scheduleTick
        // The matching runs once per screen update; every court card, the Fill button and Up Next read from it.
        let up = s.upNext
        let next = s.openCourtPairings(up)
        GeometryReader { geometry in
            let split = geometry.size.width >= max(650, courtMinimumWidth + queuePanelWidth + 48)
            VStack(spacing: 0) {
                if !split {
                    Picker("Session view", selection: $showQueue) {
                        Text("Courts").tag(false)
                        Text("Queue").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(12)
                }
                HStack(spacing: 0) {
                    if split || !showQueue {
                        courtsArea(next, width: geometry.size.width - (split ? queuePanelWidth + 1 : 0))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemGroupedBackground))
                    }
                    if split { Divider() }
                    if split || showQueue {
                        queuePanel(up)
                            .frame(width: split ? queuePanelWidth : nil)
                    }
                }
            }
        }
        .onAppear { s.refreshSchedule() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { tick in
                s.refreshSchedule()
                if (s.scheduled ?? []).contains(where: { !s.scheduledDone($0) && !s.scheduledPlaying($0) }) { scheduleTick = tick }
            }
        .navigationTitle(s.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Label("Menu", systemImage: "chevron.backward").labelStyle(.titleAndIcon) }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { showSettings = true }
                Menu("Players", systemImage: "person.badge.plus") {
                    Button("New Player", systemImage: "person.badge.plus") { showAddPlayer = true }.disabled(s.tournament != nil)
                    Button("From Earlier Sessions", systemImage: "clock.arrow.circlepath") { showReturning = true }.disabled(s.tournament != nil)
                    Button("Session Players", systemImage: "person.2") { showSessionPlayers = true }
                }
                Button("Standings", systemImage: "trophy") { showStandings = true }
                Button(textSize >= .xxLarge ? "Start All" : "Start Ready Courts") { s.fillAll(shown: next) }
                    .buttonStyle(.borderedProminent)
                    .disabled(next.isEmpty || !s.isLive)
                    .accessibilityLabel("Start all ready courts")
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet(s: $s, others: others, onEnd: onLeave, onDelete: onDelete).capped() }
        .fullScreenCover(isPresented: $showStandings) { StandingsSheet(s: $s).capped() }
        .sheet(isPresented: $showSessionPlayers) {
            SessionPlayersSheet(s: $s, past: others) { p, name, skill, pref, paused, present in save(p, name: name, skill: skill, pref: pref, paused: paused, present: present) }.capped()
        }
        .sheet(isPresented: $showReturning) { ReturningPlayersSheet(s: $s, past: others).capped() }
        .sheet(isPresented: $showAddPlayer) { AddPlayerSheet(s: $s).capped() }
        .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { p in
            Button("Remove \(p.name)", role: .destructive) { s.players.removeAll { $0.id == p.id } }
        } message: { _ in
            Text("They leave this session's queue. Games they played stay in the history.")
        }
        .sheet(item: $replacing) { r in ReplacePlayerSheet(s: $s, target: r).capped() }
        .sheet(item: $choosing) { c in ManualLineupSheet(s: $s, courtID: c.id).capped() }
        .sheet(item: $editing) { p in
            EditPlayerSheet(player: p, played: s.played(p.id), won: s.wins(p.id),
                            takenNames: Set(s.players.filter { $0.id != p.id }.map { $0.name.lowercased() })) { name, skill, pref, paused, present in
                save(p, name: name, skill: skill, pref: pref, paused: paused, present: present)
            }.capped()
        }
    }

    /// A rename also applies to this person in the other sessions, so they stay one person in All Players and
    /// "From Earlier Sessions".
    private func save(_ p: Player, name: String, skill: Double, pref: Preference, paused: Bool, present: Bool) {
        savePlayer(p, name: name, skill: skill, pref: pref, paused: paused, present: present, s: &s)
        if p.name.lowercased() != name.lowercased() { onRename(p.name, name) }
    }

    // MARK: Courts

    /// Court columns scale with text size and stay within the available panel width.
    private func courtsArea(_ next: [UUID: Pairing], width: CGFloat) -> some View {
        ScrollView {
            if s.ended != nil {
                Label("Ended \(s.endedLabel). Reopen it in Session Settings to play.", systemImage: "flag.checkered")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding([.horizontal, .top], 12)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: min(courtMinimumWidth, max(1, width - 24))), spacing: 12)], spacing: 12) {
                ForEach($s.courts) { $court in courtCard($court, next: next[court.id]) }
            }
            .padding(12)
        }
    }

    private func courtCard(_ court: Binding<Court>, next: Pairing?) -> some View {
        let c = court.wrappedValue
        let scheduled = s.scheduledOnCourt(c.id)
        let slots = s.manualSlots(c), half = c.format.needed / 2 // manual mode: the players picked so far
        let teams = c.match.map { m in (m.teamA.compactMap(s.player), m.teamB.compactMap(s.player)) }
            ?? slots.map { m in (m[..<half].compactMap { $0 }.compactMap(s.player), m[half...].compactMap { $0 }.compactMap(s.player)) }
            ?? next.map { ($0.a, $0.b) }
        let t = s.tournament
        let tap: ((Player) -> Void)? = slots != nil ? { _ in choosing = c }
            : t == nil && next != nil && next?.scheduled == nil ? { p in replacing = ReplaceTarget(courtID: c.id, courtName: c.name, out: p) } : nil
        let format = t?.format ?? c.format
        let gameLabel = (c.match?.tournamentMatch ?? next?.match).flatMap { id in t.map { $0.matches[id].label } }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(c.name).font(.headline).lineLimit(2)
                Text(c.match != nil ? "Playing" : !s.isLive ? "Ended" : next?.scheduled != nil ? "Scheduled · Locked" : next != nil ? "Ready" : "Waiting")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(c.match != nil ? Color.playingCourt : next != nil ? Color.court : .secondary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background((c.match != nil ? Color.playingCourt : Color.court).opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                Spacer()
                if let t {
                    Text(t.format.rawValue.capitalized).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                } else {
                    Picker("Format", selection: court.format) {
                        ForEach(Format.allCases, id: \.self) { f in
                            Image(systemName: f == .singles ? "person.fill" : "person.2.fill").accessibilityLabel(f.rawValue.capitalized)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                    .disabled(c.match != nil || scheduled != nil)
                }
                Menu {
                    if c.match != nil {
                        Button("Undo Start", systemImage: "arrow.uturn.backward") { s.undoStart(c.id) }
                    } else if let scheduled {
                        Button("Postpone 10 min", systemImage: "clock.arrow.circlepath") { s.postponeScheduled(scheduled.id) }
                        Button("Cancel Request", systemImage: "xmark", role: .destructive) { s.cancelScheduled(scheduled.id) }
                    } else if t == nil {
                        Button("Choose Players", systemImage: "hand.point.up.left") { if c.manual == nil { s.setManual(true, on: c.id) }; choosing = c }
                        if c.manual != nil { Button("Back to Automatic", systemImage: "wand.and.stars") { s.setManual(false, on: c.id) } }
                    }
                    Button("Remove \(c.name)", systemImage: "trash", role: .destructive) { removingCourt = c }
                    .disabled(c.match != nil || scheduled != nil)
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).padding(.leading, 4)
                }
                .accessibilityLabel("\(c.name) options")
                .confirmationDialog("Remove \(c.name)?", isPresented: Binding(get: { removingCourt?.id == c.id }, set: { if !$0 { removingCourt = nil } }),
                                    titleVisibility: .visible) {
                    Button("Remove \(c.name)", role: .destructive) { if s.scheduledOnCourt(c.id) == nil { s.courts.removeAll { $0.id == c.id } } }
                } message: {
                    Text("Its games stay in Match History.")
                }
            }
            .padding(.horizontal)

            // Edge to edge inside the card, so the court gets the full width
            CourtDrawing(format: format, teams: teams, isPreview: c.match == nil, rallyID: c.id.uuidString, rallySince: c.match?.start, boost: { s.streakBoost($0) },
                         onTap: tap,
                         locked: c.locked, onLock: t == nil && next != nil && slots == nil && next?.scheduled == nil ? { side in s.lock(c.locked == side ? nil : side, on: c.id) } : nil)

            HStack {
                if let m = c.match {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text("\(gameLabel.map { "\($0) · " } ?? "")\(Int(ctx.date.timeIntervalSince(m.start) / 60)) min").monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Finish Game") { finishing = c }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue) // Finish stays distinct from the cyan Start action
                        .confirmationDialog("Who won on \(c.name)?", isPresented: Binding(get: { finishing?.id == c.id }, set: { if !$0 { finishing = nil } }),
                                            titleVisibility: .visible) {
                            Button(names(m.teamA)) { s.finish(c.id, winner: 0) }
                            Button(names(m.teamB)) { s.finish(c.id, winner: 1) }
                            Button("Cancel Game (no result)") { s.finish(c.id, winner: nil) }
                        }
                } else {
                    let short = format.needed - s.eligible(format).count, missing = slots?.filter { $0 == nil }.count ?? 0
                    Text(slots != nil ? (missing > 0 ? "Choose \(missing) more" : "Next up · by hand")
                         : next != nil ? "Next up\(gameLabel.map { " · \($0)" } ?? "")\(next?.note.map { " · \($0)" } ?? "")"
                         : t?.champion != nil ? "Tournament complete"
                         : t == nil && short > 0 ? "Need \(short) more for \(format.rawValue)" : "Waiting for players")
                        .foregroundStyle(.secondary)
                        // The note takes what's left and never pushes the buttons: at most two lines, then it shrinks or trims.
                        .lineLimit(2).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if slots != nil {
                        Button("Choose Players", systemImage: "hand.point.up.left") { choosing = c }.labelStyle(.iconOnly).buttonStyle(.bordered).fixedSize()
                    } else if t == nil, let next, next.options > 1 { shuffleButton(c, singles: next.format == .singles).fixedSize() }
                    Button("Start \(format.rawValue.capitalized)") { s.fill(c.id, shown: next) }
                        .buttonStyle(.borderedProminent)
                        .fixedSize()
                        .disabled(next == nil || !s.isLive)
                }
            }
            .font(.subheadline)
            .frame(minHeight: 44) // same height with or without a note, so the buttons stay put
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(c.match != nil ? Color.playingCourt.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
        }
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
            if s.isLive, s.endsAt != nil {
                Section {
                    TimelineView(.periodic(from: .now, by: 60)) { ctx in
                        Label(s.lengthLabel(now: ctx.date) ?? "", systemImage: "clock").font(.subheadline.weight(.semibold))
                    }
                }
            }

            if let t = s.tournament {
                if !upNext.isEmpty {
                    Section("Up Next") {
                        ForEach(Array(upNext.enumerated()), id: \.offset) { _, p in
                            upNextRow(p.match.map { t.matches[$0].label.uppercased() } ?? "", format: p.format, pairing: p)
                        }
                    }
                }
            } else if s.courts.contains(where: { $0.match != nil }) {
                Section("After this game · projected") {
                    ForEach(s.courts.filter { $0.match != nil }) { c in
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
                DisclosureGroup("Queue rules") {
                    Text(s.matchingHelp + " Fewest counted games first, then longest rested. Recalls retain game-count protections. Both exact teams need another opponent before a rematch. There is no time-based overdue priority.")
                }
            }
            let away = s.players.filter { $0.away == true }
            if !away.isEmpty {
                Section {
                    ForEach(away) { p in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.name).font(.body.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                SkillDots(skill: p.skill, boost: s.streakBoost(p.id))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = p }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Edit player")
                            Button("Here") { s.arrive(p.id) }
                                .buttonStyle(.bordered).tint(Color.court)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minHeight: 44)
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
                    Text(p.name).font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    // Minutes waited, on the wait rule's clock; orange from 20, when the rule puts them in the next game.
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        let mins = s.started == nil || !s.isLive ? nil : Int(ctx.date.timeIntervalSince(s.waitStart(p)) / 60)
                        (Text("\(s.played(p.id)) played\(s.scheduledPenalties[p.id, default: 0] > 0 ? " · priority cooldown \(s.scheduledPenalties[p.id]!)" : "")\(s.isLocked(p) ? " · with \(s.player(p.lock!)?.name ?? "")" : "")")
                         + Text(mins.map { " · \($0) min" } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .onTapGesture { editing = p }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Edit name or rating")
            Menu { playerActions(p) } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(p.name)")
        }
        .opacity(p.paused ? 0.5 : 1)
        // Press and hold: a narrow column makes swipes easy to overshoot into Remove.
        .contextMenu { playerActions(p) }
    }

    @ViewBuilder private func playerActions(_ p: Player) -> some View {
        Button("Edit Name or Rating", systemImage: "pencil") { editing = p }
        Button(p.paused ? "Back In" : "Sit Out", systemImage: p.paused ? "play" : "pause") {
            s.update(p.id) { $0.paused.toggle() } // the wait clock keeps running while sitting out
        }
        Button("Move to Front", systemImage: "arrow.up.to.line") { s.moveToFront(p.id) }
        Button("Not Here", systemImage: "person.slash") { s.update(p.id) { $0.away = true } }
        Divider()
        Button("Remove from Session", systemImage: "trash", role: .destructive) { removing = p }
    }

    /// A busy court's projected next game.
    private func upNextRow(_ label: String, format: Format, pairing p: Pairing?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(format == .singles ? Color.singles : Color.doubles)
            if let p {
                Text(names(p.a.map(\.id))).font(.subheadline.weight(.semibold))
                Text("vs").font(.caption).foregroundStyle(.secondary)
                Text(names(p.b.map(\.id))).font(.subheadline.weight(.semibold))
            } else {
                Text(s.waitingMessage).font(.subheadline).foregroundStyle(.secondary)
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

    private func names(_ ids: [UUID]) -> String {
        ids.compactMap { s.player($0)?.name }.joined(separator: " & ")
    }
}

/// Saves a player edit in one session.
func savePlayer(_ p: Player, name: String, skill: Double, pref: Preference, paused: Bool, present: Bool, s: inout SessionState) {
    s.update(p.id) { $0.name = name; $0.skill = skill; $0.pref = pref; $0.paused = paused }
    if present { s.arrive(p.id) } else { s.update(p.id) { $0.away = true } }
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
        // Judged on ratings with streak boosts; the rows still show real ratings.
        let format = s.courts.first { $0.id == target.courtID }?.format ?? .doubles
        let gap = { (p: Player) in abs(s.matchSkill(p.id, format: format) - s.matchSkill(target.out.id, format: format)) }
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
                    Text("\(s.played(p.id)) played\(s.streakBoost(p.id) > 0 ? " · on a win streak" : "")\(uneven ? " · makes it uneven" : "")\(from.map { " · next up on \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(from == nil && !uneven ? Color.secondary : Color.singles)
                }
                Spacer()
                VStack(spacing: 1) {
                    SkillDots(skill: p.skill, boost: s.streakBoost(p.id)).padding(.vertical, -4)
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
    var sessionFields = true // false in All Players: name and rating only, applied to every session
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
                    if duplicate { Text("Another player\(sessionFields ? " in this session" : "") is already called \(trimmed).").foregroundStyle(.red) }
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
                    Picker("Set level", selection: Binding(get: { min(5, max(1, Int(skill.rounded()))) }, set: { skill = skillPresets[$0 - 1] })) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Rating")
                } footer: {
                    Text(sessionFields ? "Wins and losses keep adjusting this. \(played) played · \(won) won this session."
                                       : "Changes their name and rating in every session they're in. \(played) played · \(won) won in all.")
                }
                if sessionFields {
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

struct StandingsSheet: View {
    @Binding var s: SessionState
    @Environment(\.dismiss) private var dismiss
    @State private var tab = "Standings"
    @State private var editingGame: Int? // index into results

    var body: some View {
        NavigationStack {
            List {
                if tab == "Standings" { standings } else { history }
            }
            .navigationTitle("^[\(s.games.count) game](inflect: true) played")
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
        let all = s.players
            .map { (p: $0, w: s.wins($0.id), n: s.played($0.id), score: s.score($0.id)) }
            .sorted { ($0.score, $0.w, $1.p.name) > ($1.score, $1.w, $0.p.name) }
        // Ranked: enough games (75% of the median). Played fewer: listed, not ranked. Yet to play: last.
        let minimum = s.rankingMinimum
        let ranked = all.filter { $0.n >= minimum }, short = all.filter { $0.n > 0 && $0.n < minimum }, unplayed = all.filter { $0.n == 0 }
        if all.isEmpty { Text("No players yet.").foregroundStyle(.secondary) }
        let places = Self.places(ranked.map(\.score))
        let top = (1...3).map { k in ranked.indices.filter { places[$0] == k && ranked[$0].w > 0 }.map { ranked[$0] } }.prefix { !$0.isEmpty }
        if !top.isEmpty {
            Section { podium(Array(top)) }.listRowBackground(Color.clear)
        }
        Section {
            ForEach(Array(ranked.enumerated()), id: \.element.p.id) { i, r in standingRow(r, rank: places[i]) }
        } header: {
            if !top.isEmpty { Text("Ranked") }
        } footer: {
            Text("Ranked by Score: the win rate, starting everyone at 50 (two extra wins and two extra losses) so one or two lucky games can't top the table. Equal scores share a place. Ranking needs ^[\(minimum) game](inflect: true), three quarters of a typical night here.")
        }
        if !short.isEmpty || !unplayed.isEmpty {
            Section("Not ranked · played under \(minimum)") {
                ForEach(short + unplayed, id: \.p.id) { r in standingRow(r, rank: nil) }
            }
        }
    }

    /// Places for scores sorted high to low: equal scores (equal records) share a place, and the next score takes the
    /// next place: 1, 1, 1, 2, 3, 3.
    static func places(_ scores: [Double]) -> [Int] {
        var out: [Int] = []
        for (i, s) in scores.enumerated() { out.append(i > 0 && s == scores[i - 1] ? out[i - 1] : (out.last ?? 0) + 1) }
        return out
    }

    private func standingRow(_ r: (p: Player, w: Int, n: Int, score: Double), rank: Int?) -> some View {
        HStack(spacing: 12) {
            // Rank, in medal colours for the top three; anyone not ranked has a dash.
            Text(rank.map { "\($0)" } ?? "–")
                .font(.subheadline.weight(.heavy)).monospacedDigit()
                .foregroundStyle((rank ?? 4) <= 3 ? .white : .secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill((rank ?? 4) <= 3 ? PodiumPlace.medal(rank ?? 1)[1] : Color(.tertiarySystemFill)))
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

    /// The top three places (everyone tied for a place shares its step), laid out 2nd · 1st · 3rd on a navy stage.
    private func podium(_ top: [[(p: Player, w: Int, n: Int, score: Double)]]) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach([1, 0, 2].filter { $0 < top.count }, id: \.self) { i in
                let group = top[i], records = Set(group.map { "\($0.w)–\($0.n - $0.w)" })
                PodiumPlace(rank: i + 1, names: group.map(\.p.name), record: records.count == 1 ? records.first : nil, score: group[0].score)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .background { ArenaBackdrop().clipShape(RoundedRectangle(cornerRadius: 20)) }
        .listRowInsets(EdgeInsets())
    }

    /// Newest first. Tap a game to correct who won, cancel it or delete it; ratings and standings update with it.
    @ViewBuilder private var history: some View {
        if s.results.isEmpty { Text("Finished games show up here.").foregroundStyle(.secondary) }
        ForEach(s.results.indices.reversed(), id: \.self) { i in
            let r = s.results[i]
            Button { editingGame = i } label: {
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
                        Text("Cancelled").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit this game")
            .confirmationDialog("Game \(i + 1): \(names(r.teamA)) vs \(names(r.teamB))", isPresented: Binding(get: { editingGame == i }, set: { if !$0 { editingGame = nil } }),
                                titleVisibility: .visible) {
                // A tournament game's winner moved the bracket on, so only a queue game's result can change.
                if r.tournamentLabel == nil {
                    if r.winner != 0 { Button("\(names(r.teamA)) won") { s.setWinner(i, 0) } }
                    if r.winner != 1 { Button("\(names(r.teamB)) won") { s.setWinner(i, 1) } }
                    if r.winner != nil { Button("Cancelled (no result)") { s.setWinner(i, nil) } }
                }
                Button("Delete Game", role: .destructive) { s.deleteResult(at: i) }
            } message: {
                Text("Ratings are corrected to match.")
            }
            .swipeActions {
                Button("Delete", systemImage: "trash", role: .destructive) { s.deleteResult(at: i) }
            }
        }
    }

    private func names(_ ids: [UUID]) -> String { ids.map { s.player($0)?.name ?? "Removed player" }.joined(separator: " & ") }

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
    /// A streak's matching boost (`SessionState.streakBoost`): a win streak colors filled dots vibrant red and fills the next empty dots by the boost;
    /// a losing streak colors filled dots vibrant blue. Overflowing wins add 🔥; overflowing losses keep blue rings.
    var boost: Double = 0

    /// Each dot's streak share, plus the overflow marker for wins (fire) or losses (rings).
    static func streak(filled: Int, boost: Double) -> (parts: [Double], ring: Bool, fire: Bool) {
        let f = Double(filled), clamp = { (x: Double) in min(1, max(0, x)) }
        let parts = (1...5).map { i in
            let d = Double(i)
            return boost > 0 ? (i > filled ? clamp(f + boost - (d - 1)) : 0) : boost < 0 ? (i <= filled ? clamp(d - (f + boost)) : 0) : 0
        }
        return (parts, boost < 0 && -boost > f, boost > 0 && f + boost > 5)
    }

    var body: some View {
        let filled = Int(skill.rounded()), (parts, ring, fire) = Self.streak(filled: filled, boost: boost)
        let streakColor = boost > 0 ? Color(red: 1, green: 0.12, blue: 0.30) : Color(red: 0, green: 0.62, blue: 1)
        let dotColor = boost == 0 ? tint : streakColor
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle().fill(i <= filled ? dotColor : tint.opacity(0.2))
                    .overlay {
                        // Overflowing losses retain blue rings.
                        if ring && i <= filled { Circle().stroke(streakColor, lineWidth: 1.2).padding(-1.5) }
                        if parts[i - 1] > 0 {
                            // win: the leading part, the next level starting to fill; loss: the trailing part, the top taken away
                            Circle().fill(streakColor)
                                .mask(alignment: boost > 0 ? .leading : .trailing) { Rectangle().frame(width: 7 * parts[i - 1]) }
                        }
                    }
                    .frame(width: 7, height: 7)
            }
        }
        .frame(height: 14)
        .overlay(alignment: .trailing) {
            if fire {
                Text("🔥").font(.system(size: 12))
                    .frame(width: 14, height: 14).offset(x: 17)
                    .accessibilityHidden(true)
            }
        }
        // Reserve marker space on both sides so the dots stay centered and every rating has the same footprint.
        .padding(.horizontal, 17)
        .padding(.vertical, 6)
        .accessibilityElement()
        .accessibilityLabel(boost > 0 ? "On a win streak" : boost < 0 ? "On a losing streak" : "")
        .accessibilityHidden(boost == 0)
    }
}

/// A court seen from above: net in the middle, singles sidelines bold when it's a singles court.
struct CourtDrawing: View {
    let format: Format
    let teams: ([Player], [Player])?
    let isPreview: Bool
    var rallyID: String = "court"
    var rallySince: Date? = nil // a game in progress: a shuttle rallies between the names
    var boost: (UUID) -> Double = { _ in 0 } // streaks, shown on the dots
    var onTap: ((Player) -> Void)? = nil // tap a name to replace that player (open courts only)
    var locked: Int? = nil
    var onLock: ((Int) -> Void)? = nil // lock a side so shuffle changes only the other one (open courts only)

    private var courtColor: Color { isPreview ? .court : .playingCourt }

    var body: some View {
        ZStack {
            Rectangle().fill(courtColor)
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
            // Under the names, so a landing shuttle never hides one.
            if let rallySince, teams != nil { RallyShuttle(singles: format == .singles, since: rallySince, courtID: rallyID) }

            HStack(spacing: 0) {
                side(teams?.0).overlay(alignment: .topLeading) { lockButton(0) }
                side(teams?.1).overlay(alignment: .topTrailing) { lockButton(1) }
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
                    .foregroundStyle(on ? courtColor : .white)
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
                        Text(p.name).font((isPreview ? Font.title : .title2).weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
                        SkillDots(skill: p.skill, tint: .white, boost: boost(p.id)).padding(.vertical, -4)
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
    HomeView(sessions: .constant([SessionState()]))
}

/// One place on the standings podium: a medal-colored badge with the player's initials, then a step that rises into view.
struct PodiumPlace: View {
    let rank: Int, names: [String], record: String?, score: Double // record: nil when the tied players' records differ
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
    private func initials(_ name: String) -> String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }

    var body: some View {
        let medal = LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        VStack(spacing: 6) {
            // A gold shuttlecock above the winner; the others keep the space so all three badges share a baseline.
            ShuttlecockIcon(colors: colors)
                .frame(width: 28, height: 35)
                .shadow(color: colors[0].opacity(0.8), radius: 6)
                .opacity(rank == 1 ? 1 : 0)
            // One badge per player sharing the place (up to three, overlapping); smaller when shared.
            let size: CGFloat = (rank == 1 ? 70 : 58) * (names.count > 1 ? 0.75 : 1)
            HStack(spacing: -size * 0.28) {
                ForEach(Array(names.prefix(3).enumerated()), id: \.offset) { _, n in
                    Text(initials(n))
                        .font(.system(size: size * 0.37, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                        .frame(width: size, height: size)
                        .background(Circle().fill(medal))
                        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3))
                        .shadow(color: colors[0].opacity(0.6), radius: rank == 1 ? 14 : 8)
                }
            }
            Text(names.joined(separator: " · "))
                .font(.headline).foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.6)
            HStack(spacing: 6) {
                if let record { Text(record) }
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
        .accessibilityLabel("Place \(rank)\(names.count > 1 ? ", shared" : ""): \(names.formatted()), \(record.map { "\($0), " } ?? "")score \(score.formatted(.number.precision(.fractionLength(1))))")
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

/// A shuttle rallying between the players' names on a court with a game in progress, seen from above: it rises and grows
/// mid-flight over its shadow, cork first. Each court's rally starts with its game, so courts aren't in step. Off with Reduce Motion.
struct RallyShuttle: View {
    let singles: Bool, since: Date
    let courtID: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                Canvas { ctx, size in
                    let w = size.width, h = size.height, motion = RallyMotion(courtID)
                    func spot(_ k: Int) -> CGPoint {
                        CGPoint(x: w * (k % 2 == 0 ? 0.2 + motion.unit(k, 0) * 0.12 : 0.68 + motion.unit(k, 0) * 0.12),
                                y: h * (singles ? 0.4 + motion.unit(k, 1) * 0.2 : 0.3 + motion.unit(k, 1) * 0.4))
                    }
                    let t = max(0, tl.date.timeIntervalSince(since)) / (0.9 + motion.unit(0, 2) * 0.65)
                    let k = Int(t), f = t - Double(k), a = spot(k), b = spot(k + 1)
                    let lift = h * (0.12 + motion.unit(k, 3) * 0.12)
                    let ground = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
                    let up = sin(.pi * f)
                    ctx.fill(Path(ellipseIn: CGRect(x: ground.x - 6 + up * 2, y: ground.y - 2, width: 12 - up * 4, height: 4)),
                             with: .color(.black.opacity(0.25 - up * 0.1)))
                    guard let shuttle = ctx.resolveSymbol(id: 0) else { return }
                    // Cork first: point the cork (drawn at the bottom) along the direction of travel on screen.
                    let angle = atan2((b.y - a.y) - lift * .pi * cos(.pi * f), b.x - a.x) - .pi / 2
                    ctx.translateBy(x: ground.x, y: ground.y - lift * up)
                    ctx.rotate(by: .radians(angle))
                    ctx.scaleBy(x: 1 + up * 0.4, y: 1 + up * 0.4)
                    ctx.draw(shuttle, at: .zero)
                } symbols: {
                    ShuttlecockIcon(colors: [.white, Color(white: 0.8)]).frame(width: 14, height: 18).tag(0)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// The podium's stage: an arena at night. Floodlights from the top corners, a net with posts behind the podium, court lines
/// running in perspective across the floor, a shuttle's dashed flight over the net, and crossed rackets behind the champion.
struct ArenaBackdrop: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, horizon = h * 0.56
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.04, green: 0.07, blue: 0.11), Color(red: 0.08, green: 0.18, blue: 0.28), Color.court]),
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
    @Binding var sessions: [SessionState]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var editing: SessionState.Registered?

    var body: some View {
        let all = SessionState.registry(sessions)
        let shown = search.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(search) }
        NavigationStack {
            List {
                if all.isEmpty { Text("No players yet.").foregroundStyle(.secondary) }
                ForEach(shown) { r in
                    Button { editing = r } label: {
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
                    .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Edit name or rating")
                }
            }
            .searchable(text: $search, prompt: "Search players")
            .navigationTitle("All Players · \(all.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editing) { r in
                EditPlayerSheet(player: Player(name: r.name, skill: r.skill), played: r.played, won: r.won,
                                takenNames: Set(all.map(\.id)).subtracting([r.id]), sessionFields: false) { name, skill, _, _, _ in
                    SessionState.editEverywhere(name: r.name, to: name, skill: skill, in: &sessions)
                }.capped()
            }
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
                                    SkillDots(skill: p.skill, boost: s.streakBoost(p.id)).padding(.vertical, -4)
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
            .sheet(isPresented: $addingNew) { AddPlayerSheet(s: $s).capped() }
            .sheet(isPresented: $addingReturning) { ReturningPlayersSheet(s: $s, past: past).capped() }
            .sheet(item: $editing) { p in
                EditPlayerSheet(player: p, played: s.played(p.id), won: s.wins(p.id),
                                takenNames: Set(s.players.filter { $0.id != p.id }.map { $0.name.lowercased() })) { name, skill, pref, paused, present in
                    onSave(p, name, skill, pref, paused, present)
                }.capped()
            }
        }
    }
}

/// Locked teammates: pairs who always play doubles together (see SessionState's locked teammates).
struct LockSheet: View {
    @Binding var s: SessionState
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false

    private func status(_ a: Player, _ b: Player) -> String {
        if let out = [a, b].first(where: { $0.away == true || $0.paused }) { return "On hold: \(out.name) \(out.away == true ? "isn't here" : "is sitting out")" }
        if s.splitDue(a.id, b.id) { return "3 wins in a row together: not teammates until both play" }
        let n = s.lockStreak(a.id, b.id)
        return n > 0 ? "\(n) win\(n == 1 ? "" : "s") in a row together" : "Playing together"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let pairs = s.lockedPairs.compactMap { x, y in s.player(x).flatMap { a in s.player(y).map { (a, $0) } } }
                    if pairs.isEmpty { Text("No locked teammates.").foregroundStyle(.secondary) }
                    ForEach(pairs, id: \.0.id) { a, b in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(a.name) & \(b.name)")
                                Text("\(status(a, b)) · \(((a.skill + b.skill) / 2).formatted(.number.precision(.fractionLength(1)))) avg").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Unlock", systemImage: "trash", role: .destructive) { s.setLock(a.id, nil) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Unlock \(a.name) and \(b.name)")
                        }
                    }
                    Button("Add Locked Pair", systemImage: "plus") { adding = true }
                } footer: {
                    Text("Locked teams face opponents averaging up to 0.50 lower or 1.25 higher, using streak-adjusted ratings on both teams. If no suitable match exists, they wait 30 minutes before playing independently. They do not split early for game counts or an idle court. After 3 consecutive wins together, each plays once without the other as teammate. Before a rematch, both exact teams must play another opponent. When both teams are locked, all four players must also complete two other games. Scheduled matches can override locks.")
                }
            }
            .navigationTitle("Locked Teammates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(isPresented: $adding) { AddLockForm(s: $s) }
        }
    }
}

/// Picks two players to lock as teammates.
struct AddLockForm: View {
    @Binding var s: SessionState
    @Environment(\.dismiss) private var dismiss
    @State private var first: UUID?
    @State private var second: UUID?

    var body: some View {
        let free = s.players.filter { $0.pref != .singles && !s.isLocked($0) }
        let label = { (p: Player) in "\(p.name) · \(p.skill.formatted(.number.precision(.fractionLength(1))))" }
        Form {
            Section {
                Picker("Player", selection: $first) {
                    Text("Choose").tag(UUID?.none)
                    ForEach(free.filter { $0.id != second }) { Text(label($0)).tag(Optional($0.id)) }
                }
                Picker("Teammate", selection: $second) {
                    Text("Choose").tag(UUID?.none)
                    ForEach(free.filter { $0.id != first }) { Text(label($0)).tag(Optional($0.id)) }
                }
            } footer: {
                if free.count < 2 { Text("Everyone who plays doubles is already locked.") }
            }
        }
        .pickerStyle(.navigationLink)
        .navigationTitle("Add Locked Pair")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { if let first, let second { s.setLock(first, second) }; dismiss() }
                    .disabled(first == nil || second == nil)
            }
        }
    }
}

/// Manual mode: pick each player for a court's next game. The court keeps them (no shuffles) until that game finishes.
struct ManualLineupSheet: View {
    @Binding var s: SessionState
    let courtID: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let c = s.courts.first { $0.id == courtID }
        NavigationStack {
            Form {
                if let c, let slots = s.manualSlots(c) {
                    let half = slots.count / 2
                    let elsewhere = Set(s.courts.filter { $0.id != courtID }.flatMap { s.manualSlots($0)?.compactMap { $0 } ?? [] })
                    let pool = s.eligible(c.format).filter { !elsewhere.contains($0.id) && !s.scheduledLockedPlayers.contains($0.id) } // waiting, in queue order
                    ForEach(0..<2, id: \.self) { side in
                        Section(c.format == .singles ? (side == 0 ? "Player" : "Opponent") : "Team \(side == 0 ? "A" : "B")") {
                            ForEach(side * half..<(side + 1) * half, id: \.self) { k in
                                Picker(c.format == .singles ? "Player" : "Player \(k % half + 1)",
                                       selection: Binding(get: { slots[k] }, set: { s.setSlot(k, to: $0, on: courtID) })) {
                                    Text("Choose").tag(UUID?.none)
                                    ForEach(pool.filter { $0.id == slots[k] || !slots.contains($0.id) }) { p in
                                        Text("\(p.name) · \(s.played(p.id)) played").tag(Optional(p.id))
                                    }
                                }
                                .pickerStyle(.navigationLink) // a full list: easier to scan than a menu with many players at large text
                            }
                        }
                    }
                    Section {
                        Button("Back to Automatic", systemImage: "wand.and.stars") { s.setManual(false, on: courtID); dismiss() }
                    } footer: {
                        Text("Players waiting, in queue order. \(c.name) won't shuffle these players. It goes back to automatic when the game finishes.")
                    }
                }
            }
            .navigationTitle("Choose Players · \(c?.name ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
        s.addPlayer(trimmed, skill: skillPresets[skill - 1])
        added.append(trimmed)
        name = ""
        focused = true
    }
}

extension View {
    /// Follows the iPad's text size up to the largest standard size. Accessibility sizes overflow the courts in iPad mini portrait.
    /// Sheets don't inherit it, so every sheet applies it too.
    func capped() -> some View { dynamicTypeSize(...DynamicTypeSize.xxxLarge) }
}

struct ScheduledMatchesSheet: View {
    @Binding var s: SessionState
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var scheduleTick = Date()
    var body: some View {
        let _ = scheduleTick
        NavigationStack {
            List {
                Section {
                    ForEach(s.scheduled ?? []) { r in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(s.players(r.teamA).map(\.name).joined(separator: " & ")) vs \(s.players(r.teamB).map(\.name).joined(separator: " & "))").font(.headline)
                            Text("\(r.format.rawValue.capitalized) · \(s.scheduledStatus(r))").font(.subheadline).foregroundStyle(.secondary)
                            if !s.scheduledPlaying(r) && !s.scheduledDone(r) {
                                Button("Postpone 10 min") { s.postponeScheduled(r.id) }
                                Button("Cancel Request", role: .destructive) { s.cancelScheduled(r.id) }
                            }
                        }
                    }
                    if (s.scheduled ?? []).isEmpty { Text("No scheduled matches.").foregroundStyle(.secondary) }
                    Button("Schedule a Match", systemImage: "calendar.badge.plus") { adding = true }.disabled(!s.isLive || s.tournament != nil)
                } footer: { Text("Each participant must have completed one game. Available participants wait for the others. Exact teams override locks and matching rules. Start is manual. Immediate returners get a temporary two-game queue-priority penalty and need one ordinary game before another scheduled match. An idle court may use held players once per request.") }
            }
            .navigationTitle("Scheduled Matches").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $adding) { ScheduleMatchSheet(s: $s) }
            .onAppear { s.refreshSchedule() }
            .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { tick in
                s.refreshSchedule()
                if (s.scheduled ?? []).contains(where: { !s.scheduledDone($0) && !s.scheduledPlaying($0) }) { scheduleTick = tick }
            }
        }
    }
}
struct ScheduleMatchSheet: View {
    @Binding var s: SessionState
    @Environment(\.dismiss) private var dismiss
    @State private var format: Format = .doubles
    @State private var slots: [UUID?] = Array(repeating: nil, count: 4)
    private var hasSessionLength: Bool { s.hours.map { $0.isFinite && $0 > 0 } == true }
    private var valid: Bool { slots.prefix(format.needed).compactMap { $0 }.count == format.needed && Set(slots.prefix(format.needed).compactMap { $0 }).count == format.needed && hasSessionLength }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Format", selection: $format) { ForEach(Format.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                } footer: {
                    if !hasSessionLength { Text("Set the session length in Session Settings before scheduling a match.") }
                }
                ForEach(0..<2, id: \.self) { side in
                    Section(side == 0 ? "Team A" : "Team B") {
                        ForEach(0..<(format.needed/2), id: \.self) { n in
                            let k = side * (format.needed/2) + n
                            Picker("Player \(n+1)", selection: $slots[k]) {
                                Text("Choose").tag(UUID?.none)
                                ForEach(s.players.filter { slots[k] == $0.id || !slots.contains($0.id) }) { p in Text(p.name).tag(Optional(p.id)) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Schedule a Match").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    let ids = slots.prefix(format.needed).compactMap { $0 }, half = format.needed/2
                    if s.scheduleMatch(format, a: Array(ids.prefix(half)), b: Array(ids.suffix(half))) { dismiss() }
                }.disabled(!valid) }
            }
            .onChange(of: format) { slots = Array(repeating: nil, count: 4) }
        }
    }
}

/// A snapshot for the system Save to Files dialog; exporting never edits saved sessions.
private struct WebExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data = Data()
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct ExportDataButton: View {
    let sessions: [SessionState]
    var currentID: UUID?
    @State private var document = WebExportDocument()
    @State private var exporting = false
    @State private var error: String?

    var body: some View {
        Button("Export for Webapp", systemImage: "square.and.arrow.up") {
            do {
                document = WebExportDocument(data: try Store(sessions: sessions).webExportData(currentID: currentID))
                exporting = true
            } catch { self.error = error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "shuttle-queue-" + Date().ISO8601Format().prefix(10)) { result in
            if case .failure(let error) = result { self.error = error.localizedDescription }
        }
        .alert("Export Failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}
