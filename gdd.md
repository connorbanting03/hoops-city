# HOOPS CITY — Game Design Document

A cozy basketball-and-city management sim. Build a team from the bottom of an 8-team league, and a town from a single street into a metropolis — each one fueling the other.

**Engine:** Godot 4.x · **Primary platform:** PC (Steam) first, console later · **Art target:** lightweight 2D / 2.5D isometric, runs on anything · **Business model:** premium one-time purchase (no microtransactions)

## 0. How to read this document

This is a living GDD. It's split into three layers:

1. **Vision & pillars** — what the game is and the bar every feature is judged against.
2. **Systems design** — the actual mechanics (basketball, city, economy) and how they interlock.
3. **Build plan & commercial reality** — how to make it in Godot, in what order, and a blunt section on what will and won't make money.

Throughout, anything flagged ⚠️ COMMERCIAL FLAG is something that could hurt sales or reviews on Steam / Switch / Xbox / PS5. They're the difference between a hobby project and a business.

## 1. Vision

You are the owner of a basketball team in a small, forgettable town. The team is the worst in its 8-team league. The town is barely a dot on the map. Over many seasons you build both — drafting and signing players who become local legends, and pouring revenue into hotels, businesses, and districts that turn the town into a thriving city. A winning team draws people to the city; a bigger city funds a better team. The two rise together, with no ceiling.

It's Animal Crossing's warmth and "always one more thing to build," NBA 2K MyGM's depth of roster construction and simulation, and The Sims FreePlay's sense of a small world growing under your care — minus the parts of those games that feel like chores or cash grabs.

**The fantasy:** take nothing and make it the greatest franchise and city of all time.

## 2. Design pillars

Every feature must serve at least one. If it serves none, cut it.

1. **Two intertwined empires.** The team and the city are one economy in two costumes. Neither wins alone. This interplay is the entire game — protect it above everything.
2. **Cozy, not crunchy.** Approachable and warm on the surface; deep underneath for those who want it. No punishing fail states, no anxiety timers. The tone is "tend your garden," not "survive the quarter."
3. **Every player has a story.** Generated players age, break out, decline, retire, and get their jersey hung in your arena. You should feel something when your 7-year point guard retires. Emergent narrative is the retention engine.
4. **Always something to build.** Growth is uncapped. There is always a next prospect, next banner, next building, next district. The player should never open the game and think "I'm done."
5. **Runs anywhere.** A grandma's laptop and a Switch should both run it at 60fps. This is a design constraint, not just an optimization goal — it shapes the art and the simulation architecture.

## 3. The core loop

The whole game is one flywheel. Understanding this diagram is understanding Hoops City:

```
            ┌──────────────────────────────────────────────┐
            │                                              │
            ▼                                              │
   ┌─────────────────┐     win games      ┌─────────────────┐
   │  BETTER ROSTER  │ ─────────────────▶ │   PRIZE MONEY   │
   │ (draft / sign / │                    │  + MILESTONE    │
   │    develop)     │                    │    BONUSES      │
   └─────────────────┘                    └─────────────────┘
            ▲                                      │
            │                                      ▼
   ┌─────────────────┐                    ┌─────────────────┐
   │  MORE SPENDING  │ ◀───── raises ──── │  TEAM BUDGET /  │
   │     POWER       │                    │  EFFECTIVE CAP  │
   └─────────────────┘                    └─────────────────┘
            ▲                                      │
            │                                      │ funds
   ┌─────────────────┐                            ▼
   │  BIGGER MARKET  │                    ┌─────────────────┐
   │  (city raises   │ ◀── population ─── │ CITY INVESTMENT │
   │  your cap room) │      growth        │ (build/upgrade) │
   └─────────────────┘                    └─────────────────┘
            ▲                                      │
            │                                      ▼
            │                  more       ┌─────────────────┐
            └──────────────── residents ──│  MORE FANS →    │
                              & fans       │  GATE REVENUE   │
                                          └─────────────────┘
```

Read it as two loops sharing a hub:

- **Basketball loop:** good roster → win → prize money + bonuses → afford a better roster.
- **City loop:** invest → population grows → more fans + building dividends → afford more investment.
- **The shared hub (the magic):** a winning team makes the town desirable, so winning grows the city; and a bigger city raises your effective salary cap (big-market teams can spend more), so building the city makes you better at basketball. Pull one lever and the other moves.

The strategic tension the player lives in every season: **roster vs. city — where does this dollar go?** Over-invest in players and your small-market revenue caps out. Over-invest in the city and you don't win (and winning is itself a growth engine). The fun is the balancing act.

## 4. Basketball systems

### 4.1 Players & attributes

A player is a bundle of numeric ratings plus identity and contract data. Keep the attribute set rich enough to be meaningful, small enough to be readable.

- **Physical:** Height · Speed · Strength · Vertical/Athleticism · Stamina · Durability (hidden-ish)
- **Offense:** Finishing (inside) · Mid-range · Three-point · Playmaking/Passing · Ball-handling
- **Defense:** Perimeter D · Interior D · Rebounding · Steal · Block
- **Intangibles:** Basketball IQ · Consistency · Potential (hidden) · Morale (dynamic)
- **Derived:** Overall (OVR) is a position-weighted roll-up of the above (a center's OVR weights rebounding/interior; a guard's weights handling/playmaking/shooting). Never store OVR as a base truth — always compute it, so the same player can be "better" at the right position.

**Height matters and creates trade-offs.** Taller biases toward rebounding, interior D, blocks, finishing — but pulls against speed, handling, and perimeter shooting during generation. A 5'9" blur of a playmaker and a 7'2" rim protector should feel like genuinely different tools. "Any reasonable height" is in (≈5'7"–7'4"), but height has consequences.

**Archetypes** are the "player type" mechanism — a generation + growth template that biases attributes into a recognizable shape: Sharpshooter · Slasher · Floor General (pass-first PG) · 3-and-D Wing · Two-Way Star · Rim Protector · Stretch Big · Bruiser (low-post) · Glue Guy · Project (raw, high-potential).

**Age & development curve.** Players have an age. Potential (hidden) plus age define a growth curve: rise into a peak around 26–29, plateau, then decline. Young = upside + risk; vets = known + declining. This single system drives draft strategy, free-agency value, and roster turnover that keeps the game fresh forever. Retirement clears space and creates legends.

**Generation.** Procedural: pick archetype → seed attributes from its template, modulated by height → assign age and a hidden potential ceiling → add variance. For draft prospects, the true numbers are hidden (see 4.5).

**Godot note:** model `PlayerData` as a custom `Resource`. Resources serialize cleanly (saves), are inspector-editable, and pass around without scene-tree overhead.

### 4.2 The simulation engine

This is the technical heart. The game must take two rosters and produce a believable result, a full box score, and a revenue report.

**Recommended fidelity: possession-based simulation** (not a single weighted dice roll). Each game is a sequence of ~95–105 possessions per team. Each possession resolves to an outcome — made 2, made 3, missed shot → rebound (off/def), turnover, or foul → free throws — with probabilities driven by the offensive players' relevant attributes vs. the defenders', plus controlled randomness.

Why possession-based: believable box scores and individual stat lines; emergent narrative for free (buzzer-beaters, blowouts, breakout games); it's cheap (one game is milliseconds).

**Architecture rule** (non-negotiable for performance): the simulation operates on pure data structures, not scene nodes. A game sim is a function: `simulate_game(home, away) -> GameResult`.

**Watching a game (the "juice"):** simulate once, log every event, then replay the log. Three presentation tiers, build in this order:

1. **Quick sim** — instant result + box score. (Ship this first.)
2. **Play-by-play ticker** — stream the event log as a live text feed (Football Manager style). Cheap, surprisingly gripping.
3. **2D court visualization** (post-launch / stretch) — a stylized top-down court with sprite players. A lot of work — don't gate launch on it.

⚠️ **COMMERCIAL FLAG — "it's just a spreadsheet."** The #1 risk for a management sim is feeling like Excel. The cozy aesthetic and city-builder are the hedge, but the presentation must have at least a satisfying box-score reveal and a play-by-play feed at launch.

### 4.3 Season structure

- **8 teams, 35-game regular season.** Every team plays the other 7 teams 5 times (7 × 5 = 35). Home/away split balanced.
- **Standings:** W-L, tiebreakers (head-to-head → point differential).
- **Playoffs:** top 4 of 8 seed into a bracket — 1v4, 2v3, then the final. Best-of-5 semifinals, best-of-7 final.
- **Milestone bonuses** (cash injections that feed the economy): making the playoffs · winning round 1 · winning the championship (escalating payouts); regular-season feats; player awards (MVP, DPOY, ROY, MIP) — each a bonus + permanent accolade; non-cash rewards (trophies, banners in your arena, landmarks in your city).

**Off-season phase flow** (gives the game its rhythm):

```
Regular Season → Playoffs → Awards → Draft Order set → DRAFT
   → FREE AGENCY (day-based) → Preseason → next Regular Season
```

Each phase is a distinct screen/mode with its own decisions, so the year has texture instead of being one long grind.

### 4.4 Free agency

- **Pool:** generated at game start (aging vets, undrafted players, AI cuts) and continuously refreshed — every time an AI team loses a bidding war or fills a need elsewhere, it may cut a player back into the pool.
- **Day-based bidding war.** The FA window runs over N in-game days. Each day, AI teams and you submit offers (salary × years). Each free agent weighs offers by preferences: money, projected team success, role/minutes, market/location. The best players draw multiple suitors → bidding wars → salary inflation.
- **AI behavior:** AI teams have position needs and cap room and pursue accordingly; when they can't land a target, they pivot or cut, which churns the pool.
- **Constraint:** every offer is bounded by your effective cap (§6.3) and your cash. A big market lets you win bidding wars the small-market dynasty-chasers can't.

### 4.5 The draft

- **Order:** reverse standings — worst team picks first (see tanking flag).
- **Prospect generation:** a fresh rookie class each off-season, with true stats hidden. The player sees a scouting profile: position, height, archetype, a projected draft range ("Lottery," "Late first"), and fuzzy ranges on key attributes rather than exact numbers.
- **Scouting** is a money + time sink with real strategic weight: spend scouting budget to narrow uncertainty and reveal more accurate ratings. Scout budget competes directly with roster and city spending.
- **Draft day:** standard order (worst-first), 1–2 rounds. Busts and steals create permanent franchise lore.

⚠️ **COMMERCIAL FLAG — tanking exploit.** "Worst team always picks #1" trains players to lose on purpose. Recommend a light draft lottery (worst team has the best odds but isn't guaranteed #1).

### 4.6 All-time history & "the dynasty to beat"

- **Pre-seeded league history.** At game start, generate a fictional past: each AI team has a championship count, all-time records, and retired legends. One franchise — the dynasty — owns the most titles and starts as the big-market juggernaut.
- **The soft win condition:** surpass the dynasty's championship count (and/or beat them head-to-head in finals). A milestone with a celebration, not a hard ending.
- **Hall of Fame / legends:** your players who hit accolade thresholds get enshrined; jerseys retired as banners in your arena, busts/landmarks in your city. The long-term emotional attachment engine.

## 5. The city

The city is what makes Hoops City not just another basketball manager — it's the differentiation.

### 5.1 Structure: districts → buildings → upgrades

The city is an isometric grid organized into districts (Residential, Commercial, Entertainment, Tourism, Civic). Each district holds building slots.

Building types:

- **Residential** (apartments, condos, towers): add housing capacity → population ceiling.
- **Commercial** (shops, offices, malls): pay dividends (passive income), scaling with population.
- **Hotels / Tourism** (motels → hotels → resorts): dividends that scale with city attractiveness and team success.
- **Entertainment** (restaurants, bars, theaters): boost attractiveness and concession/merch multipliers on game nights.
- **Civic / Landmarks** (parks, transit, monuments, arena expansions, a "Hall of Champions"): big city-wide multipliers and unlock gates.

Buildings upgrade through tiers, each level multiplying output and cost. Upgrade ceilings are raised by milestones.

### 5.2 How the city makes (and the team uses) money

Revenue sources per season:

- **Gate revenue** (the key team↔city link): per home game, `attendance × ticket price`, where `attendance = min(arena_capacity, fanbase × performance_modifier × opponent_draw × hype)`. Fanbase scales with city population.
- **Concessions & merch:** scale with attendance × entertainment amenities.
- **Building dividends:** each commercial/tourism building pays passive income, scaling with population. Baseline income that flows even in a rebuild year.
- **Sponsorships:** scale with team success + market size.
- **Milestone/prize money:** from §4.3.

Expenses: player salaries · building construction + maintenance · scouting budget · arena upgrades · optional staff.

Population is the master multiplier: nearly every revenue source scales with it, and it raises your salary cap room. The UI should make this legible: "Population → Fanbase → Gate Revenue → Budget" as a visible chain.

### 5.3 Population growth — and how to make it limitless

- `population_capacity` = sum of housing from residential buildings (and tiers).
- `fill_rate` = driven by attractiveness: jobs (commercial), amenities (entertainment), civic quality, team success.
- Population trends toward `capacity × attractiveness` over in-game time.

Making it endless and balanced: (1) escalating costs + scaling returns (costs scale slightly faster); (2) districts as the expansion unit (unlock new districts with prerequisites); (3) civic milestones as prestige layers (population thresholds unlock multipliers, building types, landmarks); (4) big-number scaling at the top end (K/M/B notation).

**Godot / performance note:** you cannot render a node per resident. Population is a number; the city is visualized abstractly. `TileMap` + `MultiMeshInstance2D` / batched sprites; abstract skyline that levels up at scale.

⚠️ **COMMERCIAL FLAG — endless growth can trivialize the late game.** Mitigations: (a) the AI dynasty and league cap also grow; (b) the challenge shifts from "afford players" to "optimize and chase records"; (c) escalating costs mean you're always reaching.

### 5.4 Time & pacing

In-game time progression (advance days/weeks/seasons at the player's own pace). Building construction and FA decisions consume in-game days, creating the cozy check-in rhythm.

⚠️ **COMMERCIAL FLAG — do NOT use real-world wait timers.** All timers are in-game time the player controls (click "advance day"), never real-world clocks. Non-negotiable for premium PC/console.

## 6. The economy & the salary cap system

### 6.1 The two ledgers

- **Cash on hand:** your bank. Spent on buildings, scouting, arena upgrades, one-time costs. Replenished by all revenue and bonuses.
- **Salary budget (the cap):** what you can commit to player contracts per year. Separate from cash — you can be cash-rich but cap-strapped, or vice versa.

### 6.2 League salary cap (rises YOY)

A league-wide cap grows every season as league revenue grows (a tuned upward curve). The baseline floor everyone gets; keeps salaries inflating over the decades.

### 6.3 Outpacing the cap — the system you wanted

```
Effective Team Budget = League Cap × (1 + Market_Factor + Success_Factor)

  Market_Factor  → grows with city population & development
                   (big-market teams can spend more)

  Success_Factor → grows with winning, deep playoff runs,
                   championships (revenue sharing / brand)
```

Growing your city literally raises your roster budget ceiling, and winning raises it too.

**Balance keeper:** the best players are genuinely expensive and contested by AI, and the AI dynasty starts as the big market. There's no "solved" state.

**Tuning warning:** the most delicate number-balancing in the game. Recommend a softening/diminishing curve on `Market_Factor` so a huge city helps a lot but doesn't make money meaningless.

## 7. Building it in Godot

### 7.1 The golden rule: separate simulation from presentation

```
DATA LAYER          →   pure GDScript / Resources, no scene tree.
(game state)            Serializable. Unit-testable. Fast on a Switch.

SIMULATION LAYER    →   functions/classes that mutate the data.
(systems)               GameSimulator, SeasonManager, EconomyManager,
                        CityManager, DraftManager, FreeAgencyManager.

PRESENTATION LAYER  →   scenes/nodes that READ the data and display it.
(scenes + UI)           Updated via signals. Never the source of truth.
```

The data layer is the source of truth; the UI is a view of it. Makes the sim testable, saves simple, the whole thing performant and easy to balance (run headless over 50 seasons).

### 7.2 Project structure

```
/data        custom Resources: PlayerData, TeamData, BuildingData, LeagueData
/sim         GameSimulator.gd, SeasonManager.gd, EconomyManager.gd,
             CityManager.gd, DraftManager.gd, FreeAgencyManager.gd
/autoload    GameState.gd (the savable world), EventBus.gd (signal hub)
/scenes      main_menu, hub_dashboard, city_view, match_view, panels/...
/ui          reusable Control scenes + theme (design for controller + TV)
/gen         name/player/prospect generators
/content     base league data, building catalog (data files → moddable)
```

Autoload singletons: `GameState` (the whole savable world), `EventBus` (a signal hub so systems and UI stay decoupled).

### 7.5 Saves

Serialize `GameState` to disk. Dictionary → JSON with a `version` field (recommended for a live, patched game) — robust, and lets you write save-migration code as the schema evolves.

### 7.6 Performance checklist (for "runs anywhere")

- Sim runs on pure data, zero nodes per player/possession.
- City uses `TileMap` + `MultiMeshInstance2D`; abstract skyline at scale.
- Object-pool frequently spawned visuals (play-by-play tickers, particles).
- Profile on Switch-class hardware. The sim is CPU-bound — keep it lean.

### 7.7 Localization & modding (do early — they're revenue)

- Localize from day one: no hardcoded strings, use Godot's translation/CSV system.
- Moddable data: keep base content (teams, names, building catalog) in external data files.

## 8. Build order — MVP first

Build the core loop vertically, prove the fun, then expand.

- **Phase 1 — Prove the fun (the vertical slice).** One league, one city, the dual economy. Generated players, possession sim with quick-sim + box score only, a 35-game season + playoffs, basic draft and free agency, a handful of building types, the cap/market system. No art polish. **Goal: is the roster↔city balancing act actually fun?**
- **Phase 2 — Depth & feel.** Play-by-play ticker, scouting depth, the draft lottery, awards & accolades, Hall of Fame/banners, the full district/upgrade tree, AI personalities, the pre-seeded league history and the dynasty rival. Save/load hardening with versioning.
- **Phase 3 — Polish & juice.** Cozy art pass, audio, UI/UX polish, the 2D court visualization (if it earns its keep), tutorial/onboarding, localization, accessibility, controller support.
- **Phase 4 — Ship & expand.** Steam launch. Then DLC/expansions — never microtransactions.

## 9. Commercial reality

### 9.1 Hard legal/financial flags

- ⚠️ **No real NBA IP — ever.** Real teams/players/logos/the NBA name are licensed to 2K. Fictional league, generated players, user-named team — a strength.
- ⚠️ **Premium one-time purchase.** No microtransactions, loot boxes, or pay-to-win. Suggested $20–30, then expansions/DLC.
- ⚠️ **No real-world wait timers.** In-game time only.
- ⚠️ **No always-online requirement, no intrusive DRM.** A single-player sim must work fully offline.

### 9.2 Platform flags

- ⚠️ **Godot → console is a real cost.** No official console export; Switch/Xbox/PS5 require porting through a third-party house. Ship Steam first, fund a console port from proceeds.
- ⚠️ **PC is the home of this genre.** Steam-first is the right commercial strategy.
- ⚠️ **The "10-foot UI" problem** if/when console. Design the UI for controller navigation and TV readability from the start.

### 9.3 Design flags

- ⚠️ "It's just a spreadsheet" (§4.2) — cozy art + city-builder + box-score reveal + play-by-play feed are the hedge.
- ⚠️ Tanking exploit (§4.5) — add a light lottery.
- ⚠️ Infinite growth trivializing late game (§5.3) — keep AI/cap scaling, shift challenge to records.
- ⚠️ Mild gambling perception — bidding wars, hidden-stat drafts, scouting odds are standard, no real money.
- ⚠️ Scope is enormous — MVP first, religiously.

### 9.4 The honest take

Basketball management is a genuine gap (polished football and baseball sims exist; no equivalent basketball sim). That gap + a cozy/city-builder twist is a strong concept. "Millionaire" at $20–30 after Steam's cut means ~50,000–100,000+ sales (top-decile indie). What moves the odds: (1) nail the core loop; (2) build a Steam wishlist/community months before launch; (3) localize and support modding; (4) support post-launch with expansions.

## 10. Open questions

1. **Court visualization at launch?** Lean: no — ship quick-sim + play-by-play; add 2D court post-launch.
2. **Trades between teams?** Lean: add in Phase 2.
3. **Staff/coaches?** Lean: Phase 2.
4. **How "cozy" vs. "deep"?** Worth a deliberate decision early — it's the brand.
5. **Single continuous save vs. scenarios?** Endless-world fits the vision; scenarios add replayability later.
