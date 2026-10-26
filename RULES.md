# Shuttle Queue: how the app works

The rules the iPad app and the web version follow, as of Oct 23, 2026. Both are kept in sync.

---

## 1. Sessions, courts and players

- **Main menu:** the app opens on **Create New Session**, **All Players**, the **Live Sessions** (several can run at once) and **Past Sessions** (ended ones). Tap a session to open its dashboard (courts, Up Next and the queue); its back button returns to the menu. Long-press a session (or use its buttons on the web) to delete it, or to reopen a past one.
- **Create New Session:** a name (blank shows the date), the number of courts (all doubles, changeable per court), the planned length in hours, and the players: **Copy Players from a Session** checks everyone from that session, and anyone can be checked or unchecked from the list of all players. Everyone starts as not here. Locked teammates carry over when both partners come from the copied session. Game counts start at zero, ratings carry over (latest rating).
- **Dashboard layout:** The iPad dashboard adapts to both available width and text size. At standard text sizes, iPad mini portrait keeps courts beside the queue and landscape fits two court columns when there is room. At larger text sizes, portrait switches to **Courts / Queue** tabs; wider layouts retain a larger queue panel and fewer, wider court columns as needed. Player names wrap at full text size, arrival rows put ratings below names and keep **Here** on one line, and queue guidance expands under **Queue rules**. The toolbar uses **Start All** at larger text sizes. The web app also works on phones and laptops: narrow screens use **Courts / Queue** tabs, and wider screens show both together. Court cards show **Playing**, **Ready** or **Waiting** (ended sessions show **Ended**), with full-contrast player names. Courts in play have a deep red surface; ready courts stay green. The text label and game timer also distinguish active games. **Start Ready Courts** starts the displayed lineups. The sidebar's **After this game · projected** lineups are estimates for busy courts; ready lineups appear on their court cards. Tournament Up Next remains in the sidebar.
- **Shuttle animation:** playing courts keep the animated shuttlecock, its shadow and flight arc. Each court has its own rally speed (0.9–1.55 seconds per shot) with varied landing positions and arc heights on each shot. Redrawing keeps its flight continuous. Reduce Motion hides the animation.
- **Inside a session:** Standings (trophy), Session Players (person-plus menu) and **Session Settings** (⚙︎) belong to that session only.
- **Session Settings:** name, length, **End Session** (or **Reopen Session** when ended), **Delete Session**, Mode (Queue or Tournament), Courts (count and Add Court), Locked Teammates, Appearance, and This iPad copy.
- **Export for Webapp** (home toolbar or Session Settings → Data): saves a JSON snapshot of all sessions, players, ratings, results, locked teammates, courts, tournaments and scheduled matches. Save it to Files and use **Import Data** in the webapp. Dates and team fields are converted for the webapp; the iPad’s data stays unchanged. Importing replaces web sessions with matching IDs and keeps other sessions. This is a one-way snapshot, not automatic sync.
- **Session:** one night of play. It keeps its own players, courts, results and (optionally) a tournament.
  - **Length:** once the first game starts, the queue panel shows "until 9:30 PM · 1 hr, 20 min left" (on the menu too). It's a reminder only; nothing stops at the end.
  - **End Session** closes it: games still on court are cancelled (the confirmation says how many, so they can be finished first), and it moves to Past Sessions marked "Ended" with the time. An ended session can be opened to see its standings and history; Start and Fill are off until it's reopened.
  - Deleting a session asks for confirmation and can't be undone.
  - An empty session takes the date its first player is added.
  - Data saved before live sessions existed: the session that was open stays live, and every earlier one counts as ended.
- **Courts:** a new app starts with Court 1 (doubles) and Court 2 (singles).
  - Each court is set to Singles or Doubles (the one-person / two-people switch) and can be changed while it isn't playing.
  - Add Court (Settings) adds a doubles court. A court can be removed from its ⋯ menu when it isn't playing; it asks first, and its games stay in Match History.
- **Players:** each has a name, a rating from 1.0 to 5.0 (shown as dots), and what they play: Any, Singles or Doubles.
  - The level buttons (Add Player, Edit Player's "Set level") set **New 1.0, Beginner 1.75, Intermediate 2.5, Advanced 3.5, Strong 4.5**. The level name and dots follow the rounded rating (2.5–3.4 is Intermediate, 3 dots).
  - Names are unique within a session (ignoring upper/lower case).
  - Add players from the person-plus button on the Dashboard: **New Player**, or **From Earlier Sessions** (brings back their latest rating).
  - **Session Players** (Home, or the Dashboard's person-plus menu): everyone in this session with where they are (on a court, waiting and their place in line, or sitting out), games, what they play and rating. Tap a player to edit them; add players from the top of the list (New Player or From Earlier Sessions).
- **All Players** (main menu) lists everyone across all sessions, with their latest rating, sessions, games and wins. Tap someone to change their name or rating: it changes in every session they're in, past ones included (games already played keep the rating changes they recorded).
- **Minutes waited:** each queue row shows how long that player has been waiting ("7 played · 12 min"), on the wait rule's clock: since their last game or arrival, never before the session's first game, and sitting out doesn't restart it. It turns orange at 20 minutes, when the wait rule puts them in the next game.
- **Queue actions:** queue rows prioritize name, games played and minutes waited. Tap a player to edit their name, rating, what they play, or sit them out. Tap **⋯** or press and hold for:
  - Edit Name or Rating
  - Sit Out / Back In
  - Move to Front
  - Remove from Session (asks for confirmation)
- **Appearance** (Settings): System, Light or Dark.
- **This iPad copy** (Settings, iPad only): how many days are left before the installed copy must be reinstalled from Xcode, read from its signing profile (7 days on a free developer account).

## 2. The queue: who plays next

Everyone off court is in line in this order:

1. **Moved to Front**, by hand. This lasts until their next game ends.
2. **Just came off court:** the four from the most recently finished game go behind everyone rested, even if they're behind on games, so nobody is called straight back on court. (A late arrival's credit can leave them the fewest games after their first game; this keeps them from going straight back.)
3. **Fewest games counted.** That's games played this session plus any arrival credit (see §3).
4. **Longest rested:** earliest to come off court or arrive.

**Ties on fewest games (doubles):** when several people are tied on the fewest games, whoever is hardest to match (fewest similar-level players waiting, within 1 level) starts the next game, instead of the longest rested. Nobody with more games jumps ahead, and it doesn't apply to anyone moved to the front, while someone has waited 20+ minutes, or in balanced-only mode. Without it, the strongest players got about 0.5 fewer games a night than mid-rated players, because they're rarely picked to fill someone else's game. In a simulation of 27 players on 3 courts, the strongest four went from 6.5 to 7.0 games a night, nights ending within 1 game from 36% to 63%, and games within 1 level from 64% to 61%.

Other queue rules:
- **Sitting out** players keep their place in the list but aren't picked. When they come back in, their game count stays the same and their wait clock keeps running from before they sat out.
- **What they play:** a player set to "Singles" or "Doubles" is only picked for that format.
- **Undo Start** returns a started game's players to exactly where they were in line. Starting a game doesn't change anyone's place.

## 3. Present, and late arrivals

- **Present:** players in a new session, and anyone added before the first game, start as **not here**. They're listed under **Not Here Yet** below the queue and aren't picked. Tap **Here** when they arrive (or turn on Present in Edit Player). Before the first game, they line up in the order they arrive.
- **Not Here** (press and hold a player in the queue) takes someone out of the line, for example if they were marked present by mistake. They aren't included in tournaments.
- **Don't use Sit Out for someone who hasn't arrived.** Sitting out keeps the wait clock running and the game count at 0, so they'd jump the line and catch up on games when they come back.

A player marked present, or added, after the session has started:
1. **Goes first once, while it's a trickle.** They go behind anyone still on 0 games (including earlier late arrivals who haven't played yet), then ahead of everyone who has played. If nobody is on 0 games, they go straight to the front. Once **4 late arrivals** are already waiting for their first game, anyone arriving after that joins **at par, in arrival order** (behind people already waiting) instead, so a wave of arrivals doesn't take over the courts.
   - **At most 2 late arrivals on their first game in one game**, mixed with players already in the rotation (unless nobody else can make the game). On Oct 11, about 12 players arrived within 15 minutes and filled three courts in a row, while the players who had started at 6:09 waited 27–30 minutes for their second game; a replay of that night with these rules cut courts taken over by late arrivals from 2.4 to 0.0 a night, and late arrivals waited about 2.5 minutes longer for their first game (8.8 instead of 6.4).
2. **Gets an arrival credit:** they count as having played as many games as the least-played player who has played, so they have no missed games to catch up on. Players still on 0 games don't lower this.
   - **Only from 30 minutes after the first game.** Anyone arriving before then counts as on time: no credit, so they're on 0 games and play next, ahead of everyone who has played. (On Oct 17 the organiser put such arrivals in by hand; the app now does it.)
3. **Joins the normal order after their first game.** Fewest games counted, then longest rested.
4. **Their wait clock** (§6) starts when they arrive.

Credit only affects queue order. Standings and game counts show games actually played.

## 4. Up Next

- **Up Next lists every court.** Each shows its name and format, plus "after this game" if it's still playing.
- **Each game is on three lines:** Team 1, a red **VS**, then Team 2.
- **A court that can't be filled** shows "Waiting for available players".
- **Open courts show their actual next game.** It's the same one the court preview shows and Start uses.
- **Busy courts show a best guess** from who's waiting now. Players coming off other courts can change it.
- **Every open court gets its own game,** and nobody is picked for two courts.

## 5. Doubles matching

For each open doubles court, the **first player in line always plays**. The other three are chosen in this order of preference:

1. **Similar skill:** all four within **1.0 level** of each other.
2. **Wider range:** all four within **1.5 levels**. Used only when every similar group would repeat recent partners or opponents, or would call someone straight back on court.
3. **Balanced teams from the nearest ratings:** mixed levels, choosing the four whose ratings are closest together, with team averages within 0.75 of each other. Used when no similar or wider group works.
4. **Any fair four from the front of the line,** as a last resort.

**Even games:** nobody plays again while someone with fewer games is left waiting. The four in a game all have no more games than the fewest among everyone else waiting (counting a late arrival's credit, so late arrivals count at par). Steps 1–4 then run among those players, so similar groups still form whenever counts allow, and near the end of each round games mix levels instead of leaving someone behind. Exception: if the even game would bring back four who all met lately (6+ repeat points), the usual pick is used if it repeats less. If no game passes, the rule is dropped for that game.
- **In a simulation** of 21 real players on 3 courts, 2 hours, 100 nights: someone ended 2+ games behind on 3% of nights (63% for similar groups without this rule), with all four within 1 level in 36% of games (37%) and the same four again 0.19 times a night (0.11). Waits were unchanged (longest 27 minutes).

**Too few players for similar groups:** when every court is doubles and fewer than **6.25 players per court** are here (13 for 2 courts, 19 for 3, 25 for 4; anyone sitting out or not here yet doesn't count), steps 1–2 are skipped. Each game is the first in line plus the next players in line (fewest games, then longest rested) who make even teams (averages within 0.75), avoiding heavy repeats, with no preference for similar ratings. The queue footer says when this is on, and it switches back automatically once enough players are here.
- **Why 6.25:** with the even-games rule, similar groups beat balanced teams from 18–19 players on 3 courts. In the simulation of the same 21 players, all four within 1 level went from 16% of games (balanced) to 36%, games spread over 2 levels from 15.3 to 5.6 a night, and nights with someone 2+ games behind from 19% to 3%. The same four met again 0.19 times a night (0.06). On 2 courts at 13–14 players and on 4 courts at 25–26, similar groups also gave more games within 1 level (33–49% against 25–31%) with game counts as even or more even. Below about 17 players on 3 courts, similar groups don't help.

Within those steps:
- **Rest first.** Nobody who just came off court (the four from the most recently finished game) is called straight back while four rested players are waiting. This beats skill match and even teams: if the rested players can't make teams within 0.75, the evenest four of them play anyway, strongest teamed with weakest ("uneven teams so nobody goes straight back"). The first in line and anyone overdue still always play.
- **Avoiding repeats.** "Recent" means each player's last 3 doubles games. Each pair of the four who shared a recent game costs 1 point. Each team that partnered recently costs 2 more.
  - At **3 or more points** (a rematch of the same four always is), the app tries the next step up.
  - Below that, repeats only break ties (see below).
- **Fewest games first.** Among groups that call nobody straight back and don't repeat too much, the other three are the ones with the fewest games (counting a late arrival's credit), then fewer repeat points, then whoever has waited longest. Without this, mid-rated players got pulled into far more games than the strongest and weakest (about 7.6 against 6.6 a night); now everyone gets about 6.9–7.4. In the balanced-teams step, the nearest ratings (in quarter levels) come first, then fewest games.
- **Team split:** the fairest way to split the four into two teams, with team averages within 0.75. The two strongest are never put together when a fair split exists.
- **Pair requests:** the old Increase Pairing % feature has been removed. Old requests no longer affect matching. Use Locked Teammates for players who should stay together.
- **Locked teammates** (Settings, Locked Teammates): two players who always play doubles as a team. The queue row shows "with" their teammate; the sheet lists each pair with its status and average, **Add Locked Pair** picks two doubles players who aren't locked yet.
  - **Opponents:** a team whose average (real ratings) is at least theirs, within 0.05. The app searches the full waiting line. Normal rest protection still applies, and no player in a locked-team game can be more than **1 counted game ahead** of the fewest among those waiting. If no suitable match is available once either partner has waited **20 minutes**, the lock temporarily relaxes and they can be selected independently; this starts early to help meet the 30-minute wait target. If an unmatchable pair falls **2 games behind** another waiting player, the lock relaxes sooner so they can catch up. Other players can fill the court while they wait. **Idle-court safeguard:** an open automatic court first tries all legal games with those locks intact. Only if none can start may it temporarily split unmatchable pairs immediately. Busy-court forecasts retain the usual waiting rule; the three-win cooldown still applies.
  - **After 3 wins in a row together**, each must play one game without the other as teammate. They are selected independently and do not wait for each other’s court to finish. They may naturally face each other, but the app does not require that; the lock resumes after both have played.
  - **In line:** the pair stands side by side. If nothing fair keeps the lock, a pair at the front (or overdue) gets a game built around them with two others; otherwise they wait for the next game. A locked pair is overdue together, and at most one locked pair has to play in a game.
  - **One missing:** while one is sitting out or not here, the other plays like anyone else. While one is still on court, the other waits for them, up to 20 minutes, except during a three-win cooldown.
  - New sessions copied from this one keep the locks when both come along.
- **Court notes** say why when it isn't a plain similar-skill game:
  - "wider skill range for new partners"
  - "wider skill range so nobody goes straight back"
  - "mixed teams for new partners"
  - "mixed teams so nobody goes straight back"
  - "uneven teams so nobody goes straight back"
  - "mixed teams, no similar group free"

## 6. Keeping waits near 30 minutes

- **The limit:** nobody should wait more than **30 minutes** between games. Waiting counts from when they last finished a game or arrived; sitting out doesn't restart it. Nothing counts before the session's first game starts, so leaving the app open before play begins doesn't make everyone overdue (which used to lock the lineup and stop Shuffle from changing it).
- **Locked-pair exception:** if no equal-or-higher-rated match passes the queue protections at 20 minutes, locked teammates become eligible independently. A court still has to free up, so 30 minutes is a target, not a guaranteed maximum.
- **How:** anyone who has waited **20 minutes or more** plays in the next game of their format, up to a full court. If more than a court's worth are overdue, **fewest games first**, then longest wait, until someone reaches 30 minutes. At **30+ minutes**, longest waiting takes priority over game counts so catching others up cannot leave someone waiting indefinitely. A late arrival counts at par here (the games they missed don't put them ahead). It starts at 20, not 30, because a court still has to free up.
- **Worst case for that game:** the usual skill steps first (within 1 level, then 1.5); if those don't work, balanced teams with all four **within 2 levels**. Only if nobody at all is free within 2 levels does it go wider, so the waiting player still plays.
- **The rest of the game** is chosen by the normal rules around them. The court names them only once they've waited **25+ minutes**, for example "Next up · Gino waited 25+ min" (at 20 it showed on about half of all games).
- **If the overdue players can't make even teams together,** as many of them play as even teams allow, longest waiting first; the rest go in the next game. The court note names only the overdue players actually in the game.
- **In a simulation** (2 courts, 3 hours, 30 nights): with 18 players the longest wait was 27 minutes (38 when this rule started at 40), with no loss of skill match. With 22 players the longest was 31 minutes (51 before), and games within 1 level dropped from 62% to 53%: on a crowded night, keeping waits short costs some skill match.

## 7. Singles matching

- **The first player in line plays.**
- **Opponents** are chosen from the whole queue, in this order:
  1. Within **1.0 level**.
  2. Rested about as long: waiting since before any later game finished.
  3. Closest rating.
  4. Longest wait.
- **If nobody is within 1 level,** the closest available player plays.
- **Shuffle** cycles through up to 3 opponent options.

## 8. Shuffle and replacing a player

- **Shuffle (🔀)** tries another fair lineup on that court's next game only. Every other court keeps its lineup.
  - While more players haven't played yet than a game needs, each shuffle draws a fresh random group from them.
  - It's hidden on courts that are already playing and in tournament mode.
- **Lock a side (🔒)** on a court's next game to keep those players. Shuffle then changes only the other side:
  - It steps through fair options from the front 8 waiting players, rested players first, in line order.
  - If no option is fair, it steps through all of them.
  - Tap the lock again to unlock. Starting the game clears it.
- **Tap a name** on a court's next game to replace that player. The list has two groups:
  - **Best fit:** similar level and keeps the game even, fewest games first.
  - **Less of a fit:** everyone else, closest level first, with "makes it uneven" where it applies.
- **Uneven picks ask for confirmation.**
- **Picking someone lined up on another court** moves them. That court gets the best replacement, and if it becomes uneven the app offers Accept or Undo.
- **Hand-set lineups stay** until the game starts, the court is shuffled, or a player in it is no longer available.

## 9. Games and results

- **Start** begins the court's next game: exactly the four on screen, while they're all still free. (The screen updates when something changes; someone who reaches 20 minutes in between plays in the following game instead of swapping in on Start.) A court with a game in progress glows softly orange, shows the names a little smaller, and a shuttle rallies between them (off with Reduce Motion). **Fill Open Courts** starts every open court.
- **Undo Start** (⋯ menu) cancels a started game as if it never began.
- **Manual mode** (⋯ menu → **Choose Players**): pick every player for a court's next game yourself, slot by slot (Team A, Team B), from the players waiting, in queue order. The court never shuffles them and the automatic picks for other courts leave them alone; Start is available once every slot is filled. When that game finishes (with a winner) the court goes back to automatic. A cancelled game or Undo Start keeps the chosen players. **Back to Automatic** (⋯ menu or the sheet) ends it early. Not in tournaments.
- **Finish Game** asks who won, or **Cancel Game (no result)**. A cancelled game shows as "Cancelled" in Match History but isn't a game: it doesn't count towards anyone's games (queue order, Played, Standings), partners, repeats, streaks or ratings, and its four players go back exactly where they were in line, wait clocks still running, as with Undo Start. In a tournament, a cancelled game is replayed.
- **Editing a game** in Match History (tap it): change who won, mark it cancelled, or delete it. A corrected result undoes the rating change the game made and applies the right one, worked out as when a game finishes; deleting exactly undoes it. Places in line don't change. A tournament game can only be deleted, since its winner already moved the bracket on.

## 10. Ratings

- **Range:** 1.0 to 5.0. Ratings change after every game with a winner.
- **Expected result:** each side's chance of winning comes from the rating gap (team averages in doubles). A 2-level gap makes the stronger side about a 90% favourite.
- **Change per game:** winners gain and losers lose the same amount. The size depends on how surprising the result was, at most **0.3**:

  | Matchup | Favourite wins | Upset |
  |---|---|---|
  | Even | ±0.15 | ±0.15 |
  | 1 level apart | ±0.07 | ±0.23 |
  | 2 levels apart | ±0.03 | ±0.27 |

- **How fast ratings settle:** a **new player's first 8 rated games** move **1.5×** as much, so they find their level quickly; **regulars** move **0.75×**, so one good or bad night doesn't swing them far. "New" means added with New Player; everyone already in the app counts as a regular. In a 4-night simulation, new players ended closer to their true level (0.40 off instead of 0.46) and regulars changed 0.21 a night instead of 0.28.
- **Doubles partners** get the same change, scaled by each one's speed.
- **Game length doesn't count**: a win moves ratings the same whether it took 6 minutes or 20 (games to 11 and to 21 points differ that much).
- **Limits:** ratings stop at 1.0 and 5.0. The change actually applied is stored, so deleting a game undoes it exactly.
- **Streaks (matching only):** a player on **3 wins in a row** is matched as if rated **0.5 higher**, **+0.5 more for each further win**, up to **+1.5**; losing streaks the same, lower. Everything that matches players treats the boosted number as their rating: the automatic games, hot/cold teaming, Lock + Shuffle, and Replace ("best fit" and "makes it uneven"). Their real rating, the dots on screen and rating changes are untouched; a cancelled game is skipped. **Shown on the rating dots** (queue, courts, Session Players, Replace): an **on-fire player (temporary buff)** has all filled dots colored **vibrant red**, including all five dots at 5.0. A **cold player (temporary debuff)** has **vibrant blue** dots. The boost still fills the next empty dots by half a dot per 0.5; when a win streak runs beyond the five dots (for example a 5.0 player on a win streak), **🔥 appears after the dots** instead of red rings. Rating rows reserve the same marker space and height for every player, keeping the dots centered and names evenly spaced whether or not fire is showing. If a losing streak runs beyond the filled dots, each filled dot keeps its blue ring. In Replace, someone on a win streak can be a best fit and is marked "on a win streak".
- **Hot/cold teaming:** when a player on a win streak (or a losing streak) is about to play, and a player on the opposite streak **within 1.0 level** (real ratings) is resting near the front of the line (first 8, then 12), they're **teammates**. The other two make teams **within 0.25** of each other, and all four stay within 2 levels. All of these are judged on boosted ratings, so most hot/cold teams are a weaker player on a win streak with a stronger player on a losing streak (about 1 a night in an Oct 11 replay; judging on real ratings gave about 4, with the same game quality). The first in line still plays, nobody is called straight back, and there's no court note. Shuffle offers it first, then the normal games.
  - **Chosen by simulation** with players' form drifting game to game (so streaks mean something): partners further apart than 1.0 level only made games wider; a flat ±1.5 boost made games less even and cut similar-skill games from 63% to 56%. A 3-game streak says little in doubles (four players decide each result), so the boost starts small. In a replay of the Oct 11 night: about 4 hot/cold games a night, similar-skill games 64% (69% with no streak rules), on-time players ending within 1 game of each other 77% of nights (88% with no streak rules).

## 11. Standings

- **Ranked by Score** (0–100, one decimal), **among players with enough games**: at least three quarters of the session's typical night (75% of the median games played, rounded up; today's Oct 19 night: median 9, so 7). Only ranked players can be on the podium. Players with fewer games (late arrivals, early leavers) are listed under **Not ranked · played under N**, then anyone who hasn't played. Without this, two players who won all 4 of their games and left topped a night where most played 9–11.
- **Score:**
  - The win rate, with 2 extra wins and 2 extra losses for everyone (a score of 50 to start), so one or two lucky games can't top the table: (wins + 2) ÷ (games + 4) × 100.
  - **Game length doesn't count**: games to 11 points and to 21 last very different times, so a quick win isn't worth more.
  - **Draws:** equal scores share a place, and the next score takes the next place (1, 1, 1, 2, 3, 3). On the podium, everyone sharing a place stands on that step together.
  - Cancelled games don't count.
- **Podium:** the top 3 places (with at least one win; a shared place puts everyone on the same step), shown 2nd · 1st · 3rd on an arena stage (floodlights, net and posts, court lines, a shuttle's flight, crossed rackets), with a gold shuttlecock above the winner and medal-coloured initials.
- **The list** shows each player's rank, in gold, silver and bronze for the top 3; anyone yet to play has no rank.
- **Columns:** Won, Played, Win % (rounded) and Score.
- **Match History** lists every game with court, time, length and winner. Tap a game to edit it (see Finish Game above).
- **Standings open full screen.**

## 12. Tournament mode

- **Switch** from Queue to Tournament in Settings (Mode) and choose singles or doubles, and Top 4 or Top 8 (Top 8 needs 8+ sides).
- **Doubles teams** pair the strongest player with the weakest, the second strongest with the second weakest, and so on. With an odd number, the middle-rated player sits out. Players sitting out aren't included.
- **Round robin:** everyone plays everyone once. Seeds are fixed when it ends, by wins; ties go to the higher-rated side.
- **Bracket:** double elimination with upper and lower brackets. A side is out after two losses, and the upper and lower winners meet in a single Grand Final with no reset.
- **Courts** take the next ready games in order, whatever each court's own format. Shuffle and replace are off.
- **Ending the tournament** returns to the queue. Games stay in history and standings.

## 13. Numbers you can tune (in the code)

| Rule | Value |
|---|---|
| Similar skill, doubles | within 1.0 level |
| Wider range, doubles | within 1.5 levels |
| Fair teams | team averages within 0.75 |
| Balanced-only mode | under 6.25 players per court, all courts doubles |
| Even games | nobody plays again while someone with fewer games waits; gives way to a 6+ point repeat |
| Singles opponent range | 1.0 level |
| Repeat memory | last 3 games per player |
| Repeat limit | 3 points |
| Standings ranking | at least 75% of the median games played (`rankShare`) |
| Scheduled match estimate | median of last 10 completed games of the same format; 12-minute fallback (`scheduledDefault`) |
| Scheduled reservation | one eligible request at a time; no expiry |
| Scheduled jump priority penalty | +2 counted games, reducing by 1 after each completed ordinary game; repeated jumps reset to 2 |
| Wait target | 30 minutes; priority from 20 minutes, longest waiting first at 30+, named on court at 25+ |
| Late arrivals | credit only from 30 minutes after the first game; first 4 waiting go first, the rest at par; at most 2 per game |
| Overdue game, worst case | within 2 levels, balanced teams |
| Locked teammates | opponents' average at least theirs (within 0.05); locked-game players at most 1 counted game ahead; unmatchable pairs released at 20 minutes, when 2 games behind, or to prevent an otherwise idle automatic court; no teaming until each plays once after 3 consecutive wins together |
| Rating: most one game moves | 0.3 (×1.5 for a new player's first 8 games, ×0.75 for regulars) |
| Streak boost (matching only) | ±0.5 after 3 wins or losses in a row, ±0.5 more each further one, at most ±1.5 |
| Hot/cold teaming | partners within 1.0 level, teams within 0.25, all four within 2 levels |
| Rating: gap for a ~90% favourite | 2 levels |
| Standings: win / loss value | 0.93–1.0 / 0–0.1 |
| Shuttle animation (visual only) | each court: 0.9–1.55 seconds per shot; varied landing points and arc height; hidden with Reduce Motion |


## 14. Scheduled matches

- **Settings → Scheduled Matches** lets the organizer choose exact singles or doubles teams, view requests, or cancel pending ones. Scheduling uses the session length chosen when creating the session (or adjusted in Session Settings); the match form does not ask for or change it. Older sessions without a length must have one set in Session Settings first. These are deliberate manual overrides of rating balance, locked teammates and cooldowns, not automatic team suggestions.
- Each requested participant must have completed one non-cancelled game in this session. Other players do not need to have played. Absent and sitting-out players cannot be reserved.
- Requests run in creation order, skipping blocked requests, including requests whose entire lineup is still playing. Only one request holds available participants at a time. They wait until their teammates and a compatible automatic court are free; there is no timeout or retry window. Other players continue ordinary rotation. Manual lineups and games underway are preserved.
- Exact scheduled teams may break locked partnerships, rating balance, ordinary rest protections and priority penalties. The organizer still presses **Start**; previews and Start use the same lineup and recheck remaining session time.
- **Immediate returners:** at Start, a participant qualifies if their latest completed game is also the latest completed game on that previous court. The started match records these players. After a completed scheduled game, they count as **two extra games ahead** in ordinary queue ordering. Their next completed ordinary game reduces this to one, and the following ordinary game removes it. Repeated qualifying scheduled returns reset to two rather than stacking. Actual games played and ratings are unchanged by this penalty; normal wait protections still apply. Queue rows show the remaining priority cooldown separately.
- A scheduled match requires enough remaining session time for the median duration of the last ten completed games of that format (**12 minutes** without history). Duration estimates cannot guarantee a finish before closing. Status distinguishes participants needing their first game, waiting for players/court, insufficient time, playing and completed.
- Completion fulfills a request once. Undo Start or cancelling returns it to pending and applies no penalty. Correcting or deleting results recalculates penalties from completed history. New sessions carry neither requests nor priority penalties. Old milestone and hold/retry fields are ignored. Scheduling updates while the app is active; it does not require background execution.

### Actual session end date

End Session still cancels unfinished games. Its date and time come from the latest **completed game with a winner**, not the End Session button or a cancellation. Sessions without completed games retain their existing end-time behavior. Older ended sessions are corrected on load; corrections/deletions recalculate the end when completed games remain. The start date stays unchanged, and the end display includes its date when it falls on a different day.
