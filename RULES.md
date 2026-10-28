# Shuttle Queue: how the app works

The rules the iPad app and the web version follow, as of Oct 27, 2026. Both are kept in sync.

---

## 1. Sessions, courts and players

- **Appearance:** both apps use the Hampashers logo with cyan accents, navy details and silver-neutral surfaces. Playing courts are deep red; ready courts are cyan. Red warnings and gold/orange singles and awards keep their meanings. Light, dark and system appearance remain available.
- **Main menu:** the app opens on **Create New Session**, **All Players**, the **Live Sessions** (several can run at once) and **Past Sessions** (ended ones). Tap a session to open its dashboard (courts, Up Next and the queue); its back button returns to the menu. Long-press a session (or use its buttons on the web) to delete it, or to reopen a past one.
- **Create New Session:** a name (blank shows the date), the number of courts (all doubles, changeable per court), the planned length in hours, and the players: **Copy Players from a Session** checks everyone from that session, and anyone can be checked or unchecked from the list of all players. Everyone starts as not here. Locked teammates carry over when both partners come from the copied session. Game counts start at zero, ratings carry over (latest rating).
- **Dashboard layout:** The iPad dashboard adapts to both available width and text size. At standard text sizes, iPad mini portrait keeps courts beside the queue and landscape fits two court columns when there is room. At larger text sizes, portrait switches to **Courts / Queue** tabs; wider layouts retain a larger queue panel and fewer, wider court columns as needed. Player names wrap at full text size, arrival rows put ratings below names and keep **Here** on one line, and queue guidance expands under **Queue rules**. The toolbar uses **Start All** at larger text sizes. The web app also works on phones and laptops: narrow screens use **Courts / Queue** tabs, and wider screens show both together. Court cards show **Playing**, **Ready** or **Waiting** (ended sessions show **Ended**), with full-contrast player names. Courts in play have a deep red surface; ready courts use cyan. The text label and game timer also distinguish active games. **Start Ready Courts** starts the displayed lineups. The sidebar's **After this game · projected** lineups are estimates for busy courts; ready lineups appear on their court cards. Tournament Up Next remains in the sidebar.
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
- **Minutes waited:** each queue row shows how long that player has been waiting ("7 played · 12 min"), on the wait rule's clock: since their last game or arrival, never before the session's first game, and sitting out doesn't restart it. Waiting time is informational; it does not trigger an overdue priority or color change.
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
3. **Fewest games counted.** Actual completed games plus arrival credit and any remaining scheduled-match priority penalty. Played and standings still show actual games.
4. **Longest rested:** earliest to come off court or arrive.

**Ties on fewest games:** keep normal waiting order, including in doubles. Hardest-to-match promotion is disabled. Search the similar-skill, wider-range and mixed-balanced stages with the queue head before trying another eligible head; manual Move to Front still takes precedence.

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
   - **After the 30-minute grace period, at most 2 late arrivals on their first game in one game**, mixed with players already in the rotation. Search the full eligible waiting line for a balanced mixed game, so a large arrival wave cannot hide the regulars beyond the normal search window. If equal counted games would prevent that mix, relax equal-game selection first while keeping the two-newcomer limit. Waive that limit only if no balanced mixed game can be made under the other matching rules. Arrival status comes from the arrival time, independently of arrival credit; older records without that time retain their credit-based status.
2. **Gets an arrival credit:** they count as having played as many games as the least-played player who has played, so they have no missed games to catch up on. Players still on 0 games don't lower this.
   - **Only from 30 minutes after the first game.** Anyone arriving before then counts as on time: no credit and no two-newcomer limit, so they're on 0 games and play next, ahead of everyone who has played. (On Oct 17 the organiser put such arrivals in by hand; the app now does it.)
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

### Queue matching mode

Choose **Queue matching** in Session Settings (queue mode only), on iPad or web. The choice is saved per session, included in exported data, and retained when copying a session. New sessions and older saves without a choice use **Auto**.

- **Auto:** the existing matching logic: prefer a 1.0-point streak-adjusted rating range, then 1.5, then mixed balanced teams. Fairness and rest protections take precedence over narrow groups.
- **Equal Skill:** every automatic singles or doubles game must have a lowest-to-highest **streak-adjusted** rating range of at most **1.0**, inclusive. Try eligible heads in queue order; if the first cannot form a legal game, try the next. If no legal group fits, the court waits. Locked teams, hot/cold pairings, shuffles and small-group rematch fallbacks cannot widen this range. There is no wait-time relaxation. **Losing-streak fallback:** if a losing player's adjusted rating cannot form any group of the required size within 1.0 point among the present, non-sitting-out players eligible for that format, use that player's **current saved rating** instead, without the loss penalty. Check the whole active roster, including players on court, so starting one court does not change the other previews' rating basis. Each player's eligibility is checked against the ordinary streak-adjusted ratings of the other active players. Keep the penalty when a compatible group exists; winning boosts remain capped at 5.0. Use the resulting ratings consistently for strict ranges, team balance, locks, shuffles and Start. Saved ratings, streak history and streak indicators are unchanged; rest, game counts and rematch rules still apply.
- **Balanced Skill:** prioritize players due next and form balanced teams, allowing mixed skill levels without preferring a narrow rating range. Rest and counted-game protections remain; if no balanced game is possible, use the existing fairest legal split. Intact locked teams retain their opponent-rating band.

All modes keep the existing rest, game-count, lock and rematch protections. Manual lineups, organiser replacements and exact scheduled matches retain their explicit overrides; tournament matching is unchanged. Switching modes immediately refreshes previews, clears automatic pinned lineups, side locks and shuffle counts, and keeps explicit organiser lineups and games already playing. Equal Skill can leave courts idle and increase waits; there is no guaranteed maximum wait.

The default Auto rules are described below; the selected mode changes skill-group preference as above.

- **Game counts first:** use the player due next, then try to give turns to players with the fewest counted games. An equal-count selection is preferred; if it cannot form a balanced game, try other legal selections. Normal waiting order breaks equal-count ties; hardest-to-match promotion is disabled. Manual Move to Front remains.
- **Auto uses the same method at every roster size:** with the player due next, search all three skill stages: four players within **1.0 streak-adjusted rating level**, then **1.5 levels**, then mixed balanced teams. Fairness and rest protection come first: a balanced rested group takes precedence over a narrower group requiring a recall. Roster-size switching remains paused.
- **Rested balanced games first:** prefer rested players. If rested players cannot make a balanced game, recalling someone from the most recently completed game is allowed before accepting uneven teams. Each recalled player normally has **no more counted games** than the least-played eligible waiting player. If fewer than four rested players are available, allow only the smallest counted-game lead needed to make a game, preferring the fewest recalls. This also lets an early fifth arrival on zero games join four players who have already played. Locked-team and hot/cold searches use the same recall threshold; the separate one-game lead limit for intact locked teams remains.
- **Balanced means** team averages within **0.75**, using streak-adjusted matching ratings. If no balanced game is possible within the restrictions, the players due next play the fairest legal split, even if the gap is wider. An intact locked team's explicit rating band below overrides the ordinary 0.75 limit.
- **Repeated foursomes are allowed, but consecutive exact-team rematches are not.** Before two exact doubles teams meet again automatically, both teams must each complete a non-cancelled game together against a different team. Separate games and games on unrelated courts do not clear this cooldown. Team identity ignores player order and court side. Cancelled games are ignored; correcting or deleting history recalculates eligibility. **Small-group fallback:** when the full eligible waiting line has at most **8 players** and no game can be made under this exact-team cooldown, retry without that cooldown. Continue rotating partnerships and applying all other matching rules, including locked-team cooldowns, locks, rest and game-count protections. The court shows “teams repeated to keep the court playing.” This fallback is checked again on Start, and is not applied to a partial line left after previewing another open court. Otherwise, if no legal split or lineup exists, the court waits. Manual lineups and exact scheduled matches retain overrides. Other repeat points, thresholds, and game-count exceptions remain paused.
- **Rotate teams within the selected four:** among balanced legal splits, prefer the one whose most recently used partnership was used longest ago; ties favor the smaller team gap, then stable order. Locked partnerships and hot/cold forced pairing take precedence over partnership rotation, but hot/cold cannot widen the selected skill stage or bypass matchup eligibility. Shuffle cycles only legal splits.
- **Pair requests:** old Increase Pairing % requests have no effect; use Locked Teammates.

### Locked teammates

- An intact pair faces opponents whose **streak-adjusted average rating** is between **0.50 lower and 1.25 higher**, inclusive. A 3.50 pair can face averages **3.00–4.75**. Apply win/loss streak buffs and debuffs to both teams before checking this band; saved ratings remain unchanged.
- Locked-game participants remain at most **one counted game ahead** of the least-played eligible waiting player. Recalled participants normally have the stricter limit: no counted-game lead over the least-played eligible waiting player. With fewer than four rested players, the recall threshold described above applies; the intact locked game still cannot pull anyone more than one counted game ahead.
- If no suitable game exists, the pair waits. Only after either partner has waited **30 minutes** may it temporarily play independently. Falling behind on games or leaving a court idle does not release it early. A free player also waits for a partner still playing elsewhere, up to this timeout.
- If a partner is absent or sitting out, the other plays independently. Exact scheduled teams may override locks.
- After **three consecutive wins together**, each partner must complete a game without the other as teammate. They need not face each other, and they do not wait for the other partner's separate court to finish during this cooldown. The lock resumes after both have played independently.
- **Locked-team rematch cooldown:** after two intact locked teams face each other, all four participants must each complete **two other non-cancelled games** before those teams can meet again automatically, in addition to both exact teams having faced a different opponent. Games on unrelated courts do not clear this cooldown. A result correction or deletion immediately changes eligibility. Manual lineups and exact scheduled matches retain their override behavior.
- New sessions copied from this one retain locks when both partners come along; new sessions have no previous-match cooldown history.

## 6. Waiting time

- Waits are displayed from the player's last completed game or arrival, never before the first game starts. Sitting out keeps that clock running.
- **General overdue protection is paused:** there is no 20-minute inclusion priority, 25-minute court note, or 30-minute game-count override. Time does not widen ordinary matching ranges. Longest rested remains the normal tie-break after counted games.
- The separate **30-minute locked-pair timeout** above remains active. There is no guaranteed maximum wait. Crowded courts, locked pairs, manual lineups and scheduled reservations can all extend waits.

## 7. Singles matching

- **The first player in line plays.**
- **Opponents** are chosen from the whole queue, in this order:
  1. Within **1.0 level**.
  2. Rested about as long: waiting since before any later game finished.
  3. Closest rating.
  4. Longest wait.
- **If nobody is within 1 level,** Auto and Balanced Skill use the closest available player. Equal Skill tries later eligible heads using streak-adjusted ratings, then waits if no pair fits.
- **Shuffle** cycles through up to 3 opponent options.

## 8. Shuffle and replacing a player

- A scheduled locked court must first be postponed or cancelled before its lineup or court can be edited.
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
- **Streaks (matching only):** a player on **3 wins in a row** is matched as if rated **0.5 higher**, **+0.5 more for each further win**, up to **+1.5**; losing streaks the same, lower. **The resulting matching rating is capped at 5.0**, including after streak boosts: a 5.0 player on a +0.5 streak still matches at 5.0. The streak indicator remains visible at the cap. In Equal Skill, the losing-streak fallback in §5 can restore the saved rating when the penalty prevents a skill group. Everything that matches players uses the resulting matching number: the automatic games, hot/cold teaming, Lock + Shuffle, and Replace ("best fit" and "makes it uneven"). Their real rating, the dots on screen and rating changes are untouched; a cancelled game is skipped. **Shown on the rating dots** (queue, courts, Session Players, Replace): an **on-fire player (temporary buff)** has all filled dots colored **vibrant red**, including all five dots at 5.0. A **cold player (temporary debuff)** has **vibrant blue** dots. The boost still fills the next empty dots by half a dot per 0.5; when a win streak runs beyond the five dots (for example a 5.0 player on a win streak), **🔥 appears after the dots** instead of red rings. Rating rows reserve the same marker space and height for every player, keeping the dots centered and names evenly spaced whether or not fire is showing. If a losing streak runs beyond the filled dots, each filled dot keeps its blue ring. In Replace, someone on a win streak can be a best fit and is marked "on a win streak".
- **Hot/cold teaming:** when a player on a win streak (or a losing streak) is about to play, and a player on the opposite streak **within 1.0 streak-adjusted rating level** is resting near the front of the line (first 8, then 12), they're **teammates**. The other two make teams **within 0.25** of each other, and all four stay within the already-selected skill stage (1.0 or 1.5 levels when available, at most 2 levels for mixed hot/cold games). Hot/cold cannot override game-count fairness, rest protection, or rematch eligibility. All of these are judged on boosted ratings, so most hot/cold teams are a weaker player on a win streak with a stronger player on a losing streak (about 1 a night in an Oct 11 replay; judging on real ratings gave about 4, with the same game quality). The first in line still plays, nobody is called straight back, and there's no court note. Shuffle offers it first, then the normal games.
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
| Queue matching mode | Auto by default; Equal Skill within 1.0 matching rating point, with saved-rating fallback for an unmatchable losing streak; Balanced Skill allows mixed ratings |
| Roster-size strategy switching | paused; selected mode applies at every roster size |
| Game-count fairness | equal-count games preferred; no repeat-based exception |
| Singles opponent range | 1.0 level |
| Team rotation | partnership recency within the already selected four only |
| Repeat-based player selection | paused |
| Standings ranking | at least 75% of the median games played (`rankShare`) |
| Scheduled match estimate | median of last 10 completed games of the same format; 12-minute fallback (`scheduledDefault`) |
| Scheduled reservation | one eligible request at a time; no expiry |
| Scheduled jump priority penalty | +2 counted games, reducing by 1 after each completed ordinary game; repeated jumps reset to 2 |
| Overdue priority and wait notes | paused; normal wait tie-break retained |
| Late arrivals | 30-minute grace period; afterward first 4 waiting go first, the rest at par; at most 2 first-game arrivals per balanced game when a legal mixed game exists; relax equal counts before this limit |
| Recall lead limit | normally zero; with fewer than four rested players, the smallest lead needed to fill four slots |
| Exact-team rematch cooldown | both exact doubles teams must complete one game against another team; fallback only when no game is possible and the full eligible waiting line has at most 8 players (`rematchFallbackPlayers`) |
| Locked-team rematch cooldown | two other completed games per participant; automatic games only |
| Locked teammates | opponents 0.50 lower through 1.25 higher, streak-adjusted averages; release after 30 minutes only; three-win cooldown retained |
| Rating: most one game moves | 0.3 (×1.5 for a new player's first 8 games, ×0.75 for regulars) |
| Streak boost (matching only) | ±0.5 after 3 wins or losses in a row, ±0.5 more each further one, at most ±1.5; resulting matching rating capped at 5.0 |
| Hot/cold teaming | adjusted partner gap ≤1.0; team gap ≤0.25; selected skill-stage cap, at most 2.0 |
| Rating: gap for a ~90% favourite | 2 levels |
| Standings: win / loss value | 0.93–1.0 / 0–0.1 |
| Shuttle animation (visual only) | each court: 0.9–1.55 seconds per shot; varied landing points and arc height; hidden with Reduce Motion |


## 14. Scheduled matches

- **Settings → Scheduled Matches** lets the organizer choose exact singles or doubles teams, view requests, or cancel pending ones. Scheduling uses the session length chosen when creating the session (or adjusted in Session Settings); the match form does not ask for or change it. Older sessions without a length must have one set in Session Settings first. These are deliberate manual overrides of rating balance, locked teammates and cooldowns, not automatic team suggestions.
- Each requested participant must have completed one non-cancelled game in this session. Other players do not need to have played. Absent and sitting-out players cannot be reserved.
- Requests run in creation order, skipping blocked requests, including requests whose entire lineup is still playing. Only one request holds available participants at a time. They wait until their teammates and a compatible automatic court are free; there is no timeout or retry window. Once a request holds players, a newly unblocked older request cannot take it over. If no ordinary game can otherwise fill an open automatic court, available held players may join one ordinary game per active request; the scheduled request remains active and waits for them to finish. A second release is blocked so filling courts cannot prevent the scheduled group from ever gathering; a brief court wait can be necessary with a small roster. Other players continue ordinary rotation. Manual lineups and games underway are preserved.
- **Locked court assignment:** when all participants are free and eligible, claim the next compatible automatic court and save that assignment. The badge is **Scheduled · Locked**. Existing manual lineups and games underway are preserved; automatic preview lineups may be replaced by the scheduled request. Redraws and court reordering do not move it.
- While assigned, player replacement, Shuffle, side locking, manual lineup selection, court format changes and court removal are unavailable. Exact teams may override rating balance, normal rest protections, locked partnerships and queue priority. The organizer still presses **Start**, which rechecks availability and remaining time.
- **Postpone 10 min** and **Cancel Request** appear on the assigned court and in the scheduled list before Start. Postpone releases players and court immediately, keeps the original creation order and retries after ten minutes. It cannot preempt another active reservation. Cancel removes the request. A match underway uses the existing game controls.
- If a participant becomes unavailable, clear the assigned court and retain the request with a waiting status. New assignment occurs once it is eligible again.
- **Immediate returners:** track participants playing while their request is active. When its last busy participants finish and everyone becomes available, only that final returning group qualifies; participants who were already free or waited through an earlier return do not. Organizer delay before Start does not change this snapshot. The started match records these players. After a completed scheduled game, they count as **two extra games ahead** in ordinary queue ordering. Their next completed ordinary game reduces this to one, and the following ordinary game removes it. Repeated qualifying scheduled returns reset to two rather than stacking. Actual games played and ratings are unchanged by this penalty; normal wait protections still apply. A penalized player must complete **one ordinary game** before their next scheduled match; a cancellation does not count. After that ordinary game, the remaining +1 penalty still applies to ordinary rotation, while another scheduled match may proceed. Queue rows show the remaining priority cooldown separately.
- A scheduled match requires enough remaining session time for the median duration of the last ten completed games of that format (**12 minutes** without history). Duration estimates cannot guarantee a finish before closing. Status distinguishes first-game eligibility, waiting, a locked court, postponement, insufficient time, playing and completion.
- Completion fulfills a request once. Undo Start or cancelling returns it to pending and applies no penalty. Correcting or deleting results recalculates penalties from completed history. New sessions carry neither requests nor priority penalties. Old milestone and hold/retry fields are ignored. Scheduling updates while the app is active; it does not require background execution.

### Actual session end date

End Session still cancels unfinished games. Its date and time come from the latest **completed game with a winner**, not the End Session button or a cancellation. Sessions without completed games retain their existing end-time behavior. Older ended sessions are corrected on load; corrections/deletions recalculate the end when completed games remain. The start date stays unchanged, and the end display includes its date when it falls on a different day.
