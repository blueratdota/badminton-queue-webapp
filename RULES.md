# Shuttle Queue: how the app works

The rules the iPad app and the web app (`src/engine.js`) follow, as of Oct 10, 2026. Both are kept in sync.

---

## 1. Sessions, courts and players

- **Session:** one night of play. It keeps its own players, courts, results and (optionally) a tournament.
  - **New session with same players** copies the players and courts. Game counts start at zero, ratings carry over, and everyone plays "Any".
  - **New empty session** keeps the courts only.
  - Earlier sessions can be reopened or deleted (a delete asks for confirmation).
- **Courts:** a new app starts with Court 1 (doubles) and Court 2 (singles).
  - Each court is set to Singles or Doubles and can be changed while it isn't playing.
  - Add Court adds a doubles court. A court can be removed from its ⋯ menu when it isn't playing.
- **Players:** each has a name, a rating from 1.0 to 5.0 (shown as dots), and what they play: Any, Singles or Doubles.
  - Names are unique within a session (ignoring upper/lower case).
  - Add players from the person-plus button in the top bar: **New Player**, or **From Earlier Sessions** (brings back their latest rating).
  - **Session Players** (⚙︎ menu): everyone in this session with where they are (on a court, waiting and their place in line, or sitting out), games, what they play and rating. Tap a player to edit them; add players from the top of the list (New Player or From Earlier Sessions).
- **All Players** (⚙︎ menu) lists everyone ever registered, with their latest rating, sessions, games and wins.
- **Queue actions:** tap a player to edit their name, rating, what they play, or sit them out. Press and hold for:
  - Edit Name or Rating
  - Sit Out / Back In
  - Move to Front
  - Remove from Session (asks for confirmation)
- **Appearance** (⚙︎ menu): System, Light or Dark.
- **This iPad copy** (⚙︎ menu, iPad only): how many days are left before the installed copy must be reinstalled from Xcode, read from its signing profile (7 days on a free developer account).
- **Increase Pairing %** (⚙︎ menu): set partner requests (see §5). They're kept off the main screen.

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
- **Not Here** (press and hold a player in the queue) takes someone out of the line, for example if they were marked present by mistake. They don't count toward the pair-request player minimum or tournaments.
- **Don't use Sit Out for someone who hasn't arrived.** Sitting out keeps the wait clock running and the game count at 0, so they'd jump the line and catch up on games when they come back.

A player marked present, or added, after the session has started:
1. **Goes first once.** They go behind anyone still on 0 games (including earlier late arrivals who haven't played yet), then ahead of everyone who has played. If nobody is on 0 games, they go straight to the front.
2. **Gets an arrival credit:** they count as having played as many games as the least-played player who has played, so they have no missed games to catch up on. Players still on 0 games don't lower this.
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

**Too few players for similar groups:** when every court is doubles and fewer than **8 players per court** are here (16 for 2 courts, 24 for 3; anyone sitting out or not here yet doesn't count), steps 1–2 are skipped. Each game is the first in line plus the next players in line (fewest games, then longest rested) who make even teams (averages within 0.75), avoiding heavy repeats, with no preference for similar ratings. The queue footer says when this is on, and it switches back automatically once enough players are here.
- **In a simulation** of 14 players on 2 courts over 100 nights: most-minus-fewest games was 1 on 67% of nights (15% with similar groups) and never 3 (10%); the same four met again 0.5 times a night (2.3). The cost is skill range: all four within 1 level in 15% of games (41%), average team gap 0.37 (0.25). Waits were unchanged.

Within those steps:
- **Rest first.** Nobody who just came off court (the four from the most recently finished game) is called straight back while four rested players are waiting. This beats skill match and even teams: if the rested players can't make teams within 0.75, the evenest four of them play anyway, strongest teamed with weakest ("uneven teams so nobody goes straight back"). The first in line and anyone overdue still always play.
- **Avoiding repeats.** "Recent" means each player's last 2 doubles games. Each pair of the four who shared a recent game costs 1 point. Each team that partnered recently costs 2 more.
  - At **3 or more points** (a rematch of the same four always is), the app tries the next step up.
  - Below that, repeats only break ties (see below).
- **Fewest games first.** Among groups that call nobody straight back and don't repeat too much, the other three are the ones with the fewest games (counting a late arrival's credit), then fewer repeat points, then whoever has waited longest. Without this, mid-rated players got pulled into far more games than the strongest and weakest (about 7.6 against 6.6 a night); now everyone gets about 6.9–7.4. In the balanced-teams step, the nearest ratings (in quarter levels) come first, then fewest games.
- **Team split:** the fairest way to split the four into two teams, with team averages within 0.75. The two strongest are never put together when a fair split exists.
- **Partner requests** (⚙︎ menu, Increase Pairing %). The screen lists existing requests with their status ("Waiting" or "Played together"); tap **Add Pair Request** to pick a player and a partner who don't have one yet, or the trash button to remove one. It works both ways. Nothing on the main screen shows it.
  - **One game together per session, guaranteed.** After each has played one game, the pair is teamed up once, then they're treated exactly like any two players: no forcing, no keeping apart.
  - **Even teams:** their game has team averages within 0.25 of a level (by the ratings at the time). The rating range may be wider than usual, so far-apart pairs still get their game.
  - **One pair game at a time:** no pair game is lined up while another is playing or already lined up, and a pair never plays against another requested pair.
  - **When:** one of the pair is about to play (picked for the game, or in the front four of the line), and the other is rested. The partner and the other two players come from the first 8 in line, then the first 12, then anyone waiting if no even game can be made otherwise. The person first in line still plays, as in any game, and nobody is called straight back on court to fit the pair in.
  - **Until their game,** the normal matching won't make them teammates (they can still meet as opponents), so it only happens as the planned, even game.
  - **Shuffle** on a pair's game first tries up to 3 games with different other players, then the normal games.
  - **Enough players needed:** at least twice the players one round of courts takes, minus two: 14 for 2 doubles courts, 22 for 3, 30 for 4 (a singles court counts 2). People sitting out don't count. Below that, requests are kept but on hold and Add Pair Request is greyed out.
  - **In a simulation** of 26 players, 3 courts and 6 pairs over 100 nights, each pair got its game on 98–100 nights, about an hour in. No two pair games overlapped, waits were unchanged, and games within 1 level went from 67% to 63%.
- **Court notes** say why when it isn't a plain similar-skill game:
  - "wider skill range for new partners"
  - "wider skill range so nobody goes straight back"
  - "mixed teams for new partners"
  - "mixed teams so nobody goes straight back"
  - "uneven teams so nobody goes straight back"
  - "mixed teams, no similar group free"

## 6. Nobody waits over 30 minutes

- **The limit:** nobody should wait more than **30 minutes** between games. Waiting counts from when they last finished a game or arrived; sitting out doesn't restart it.
- **How:** anyone who has waited **20 minutes or more** plays in the next game of their format, up to a full court. If more than a court's worth are overdue, **fewest games first**, then longest wait. A late arrival counts at par here (the games they missed don't put them ahead). It starts at 20, not 30, because a court still has to free up.
- **Worst case for that game:** the usual skill steps first (within 1 level, then 1.5); if those don't work, balanced teams with all four **within 2 levels**. Only if nobody at all is free within 2 levels does it go wider, so the waiting player still plays.
- **The rest of the game** is chosen by the normal rules around them. The court shows it, for example "Next up · Gino waited 20+ min".
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

- **Start** begins the court's next game. A court with a game in progress glows softly orange. **Fill Open Courts** starts every open court.
- **Undo Start** (⋯ menu) cancels a started game as if it never began.
- **Finish Game** asks who won. **No result** counts as played for both teams but doesn't change ratings. In a tournament, a no-result game is replayed.
- **Deleting a game** in Match History removes it and exactly undoes its rating change.

## 10. Ratings

- **Range:** 1.0 to 5.0. Ratings change after every game with a winner.
- **Expected result:** each side's chance of winning comes from the rating gap (team averages in doubles). A 2-level gap makes the stronger side about a 90% favourite.
- **Change per game:** winners gain and losers lose the same amount. The size depends on how surprising the result was, at most **0.3**:

  | Matchup | Favourite wins | Upset |
  |---|---|---|
  | Even | ±0.15 | ±0.15 |
  | 1 level apart | ±0.07 | ±0.23 |
  | 2 levels apart | ±0.03 | ±0.27 |

- **Doubles partners** get the same change.
- **Game length** nudges it by up to ±5%. A quick game counts as one-sided, a long one as close. Lengths are compared with this session's median for that format.
- **Limits:** ratings stop at 1.0 and 5.0. The change actually applied is stored, so deleting a game undoes it exactly.

## 11. Standings

- **Ranked by Score** (0–100, one decimal), then wins. Players who haven't played are listed last.
- **Score:**
  - Each win counts 0.93 (long, close game) to 1.0 (quick, one-sided game).
  - Each loss counts 0.1 (close) down to 0 (one-sided).
  - Everyone starts with 2 extra wins and 2 extra losses (a score of 50), so one or two lucky games can't top the table.
  - "No result" games don't count.
- **Podium:** the top 3 who have at least one win, shown 2nd · 1st · 3rd on an arena stage (floodlights, net and posts, court lines, a shuttle's flight, crossed rackets), with a gold shuttlecock above the winner and medal-coloured initials.
- **The list** shows each player's rank, in gold, silver and bronze for the top 3; anyone yet to play has no rank.
- **Columns:** Won, Played, Win % (rounded) and Score.
- **Match History** lists every game with court, time, length and winner. It's where games are deleted.
- **Standings open full screen.**

## 12. Tournament mode

- **Switch** from Queue to Tournament and choose singles or doubles, and Top 4 or Top 8 (Top 8 needs 8+ sides).
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
| Balanced-only mode | under 8 players per court, all courts doubles |
| Singles opponent range | 1.0 level |
| Repeat memory | last 2 games per player |
| Repeat limit | 3 points |
| Longest wait | 30 minutes (players waiting 20+ minutes play next) |
| Overdue game, worst case | within 2 levels, balanced teams |
| Partner request | one game together per session; team averages within 0.25 |
| Rating: most one game moves | 0.3 |
| Rating: gap for a ~90% favourite | 2 levels |
| Game-length effect on ratings | ±5% |
| Standings: win / loss value | 0.93–1.0 / 0–0.1 |
