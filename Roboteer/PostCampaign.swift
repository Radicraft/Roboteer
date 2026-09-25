//
//  PostCampaign.swift
//  What there is to do once the twenty matches are won (owner decision 8, 2026-09-24, and
//  docs/wave-b-progression-notes.md item 6): the Championship Defence and the daily seeded
//  exhibition.
//
//  Championship Defence: the Series card turns into "Title defence n". Challenger n is
//  `progression.defence.challengers[(n - 1) % 8]` at Masters strength, the arena cycles
//  `defence.arenas`, the house bot is the Masters pairing for that floor and gets a step faster
//  every full cycle of challengers (capped). A win pays `pay_scale` of the Series 5 scrap rules and
//  no Level points; a loss ends the reign; the best reign is kept.
//
//  Daily exhibition: one seeded match per UTC day, the same for everyone (the seed is the date), with
//  an arena, a rival and a twist drawn from it. It banks nothing into the career and the machine
//  fights as built (pristine, and it comes home as it went). The score is the published formula of
//  `progression.daily.score`; the best per day is kept on `CareerState`, the last `days_kept` days
//  are playable, and today's best goes to the Game Center leaderboard `daily_exhibition` (a
//  recurring leaderboard the OWNER has to create in App Store Connect; until then the report is
//  silently dropped, which `GameCenterService.report` already allows for).
//
//  The rules are pure (the self test drives them). The one screen at the bottom is a functional
//  hook in the existing style only: the owner has not chosen the post-campaign screen yet
//  (docs/look/progression-screens-v1.html), so this is deliberately plain.
//

import Foundation
import SwiftUI
import SwiftData

enum PostCampaign {

    static var progression: CareerCatalogue.Progression { CareerCatalogue.shared.progression }

    /// The Series whose rules the defence is paid and fought at: the last one, Masters.
    static let mastersIndex = SeriesProgress.seriesCount - 1

    // MARK: - Championship Defence

    /// The defence the career is on now: one more than the reign so far.
    static func defenceNumber(state: CareerState) -> Int { max(0, state.defenceStreak) + 1 }

    /// Which rival challenges defence `number` (1 based).
    static func challengerID(_ number: Int) -> String {
        let list = progression.defence.challengers
        guard !list.isEmpty else { return CareerCatalogue.shared.rivals.first?.id ?? "" }
        return list[(max(1, number) - 1) % list.count]
    }

    static func defenceArena(_ number: Int) -> String {
        let list = progression.defence.arenas
        guard !list.isEmpty else { return "coliseum" }
        return list[(max(1, number) - 1) % list.count]
    }

    /// The house bot's speed for defence `number`: the Masters pace plus one step for every full
    /// cycle of challengers already beaten, never above the cap.
    static func defenceHouseSpeed(_ number: Int, base: Double) -> Double {
        let rules = progression.defence
        let cycles = (max(1, number) - 1) / max(1, rules.challengers.count)
        return min(rules.houseSpeedMax, base + Double(cycles) * rules.houseSpeedStep)
    }

    /// `pay_scale` of the Series 5 scrap rules.
    static func defenceScrapRules() -> ScrapRules {
        let scale = progression.defence.payScale
        var rules = ProgressionEngine.scrapRules(seriesIndex: mastersIndex)
        rules.base = Int((Double(rules.base) * scale).rounded())
        rules.damageFull = Int((Double(rules.damageFull) * scale).rounded())
        rules.survivor = Int((Double(rules.survivor) * scale).rounded())
        rules.flawless = Int((Double(rules.flawless) * scale).rounded())
        return rules
    }

    /// The title defence card, or nil when the campaign is not won or the whole game is not open
    /// (the defence is fought at Masters, which is behind the wall).
    static func defenceMatch(state: CareerState, playerBot: BotBuild? = nil,
                             gates: Gates = Gates.snapshot) -> NextMatch? {
        guard state.campaignComplete else { return nil }
        guard !gates.entitlementSettled || gates.tierAvailable(.masters) else { return nil }
        let number = defenceNumber(state: state)
        let catalogue = CareerCatalogue.shared
        guard let rival = catalogue.rival(challengerID(number)) ?? catalogue.rivals.first else { return nil }

        let tier = CareerTier.masters
        let arena = defenceArena(number)
        let house = CareerEngine.houseBot(tier: tier, arena: arena)
        let speed = defenceHouseSpeed(number, base: house.speed)
        let round = progression.round
        let opponent = CareerEntrant(
            id: rival.id, name: rival.name, roboteer: rival.roboteer, liveryHex: rival.liveryHex,
            kind: .rival, spec: CareerEngine.rivalSpec(rival, at: tier), rivalID: rival.id
        )
        let repairs = playerBot.map { CareerEngine.repairBill(for: $0.spec, damage: $0.currentDamage).total } ?? 0
        let houseName = CareerEngine.houseBotName(house.id)
        let pace = speed > 1.001 ? " a step faster than ever" : ""

        return NextMatch(
            tier: tier,
            seriesIndex: mastersIndex,
            matchIndex: SeriesProgress.matchesPerSeries - 1,
            isFinal: false,
            isReplay: false,
            // Every defence is fought on its own seed: the career's fight count moves on each time.
            attempts: state.fightsPlayed,
            opponent: opponent,
            arena: arena,
            arenaName: Catalogue.shared.arena(arena)?.name ?? arena.capitalizedFirst,
            houseBotID: house.id,
            houseBotName: houseName,
            houseBotSpeed: speed,
            houseBotLine: "\(houseName) guards the corner zone\(pace) and comes out hunting at \(CareerEngine.clockWords(round.endgameAtS)).",
            scoutingLine: ProgressionEngine.scoutingLine(for: opponent),
            grudgeLine: "",
            aiSkill: CareerEngine.aiSkill(for: tier),
            temperament: CareerEngine.temperament(for: opponent, seasonSeed: state.currentSeasonSeed),
            scrapRules: defenceScrapRules(),
            winPoints: 0,
            repairsDue: repairs,
            mode: .defence(number),
            durationS: round.durationS,
            endgameAtS: round.endgameAtS
        )
    }

    /// One settled title defence, as a value.
    struct DefenceSettled: Equatable {
        var result: MatchReport.Result = .loss
        var scrap = ScrapBreakdown()
        var streakAfter = 0
        var bestAfter = 0
        var rewards: Rewards?
        var banked: Int { result == .win ? scrap.total : 0 }
    }

    /// A win extends the reign and banks the scrap (no points); a loss ends the reign; a draw
    /// leaves it standing and the same challenger comes back.
    static func settleDefence(number: Int, streak: Int, best: Int, points: Int, result: MatchReport.Result,
                              breakdown: ScrapBreakdown?, medals: [MedalKind] = [],
                              series: SeriesProgress = SeriesProgress(seriesIndex: 4, matchIndex: 4,
                                                                       campaignComplete: true)) -> DefenceSettled {
        var out = DefenceSettled()
        out.result = result
        out.streakAfter = streak
        out.bestAfter = best
        switch result {
        case .loss:
            out.streakAfter = 0
            return out
        case .draw:
            return out
        case .win:
            break
        }
        out.scrap = breakdown ?? ScrapBreakdown()
        out.streakAfter = max(streak, number - 1) + 1
        out.bestAfter = max(best, out.streakAfter)
        let level = ProgressionEngine.level(points: points)
        out.rewards = Rewards(
            scrap: out.scrap, levelPoints: 0, levelBefore: level, levelAfter: level, series: series,
            newlyUnlocked: [], newPaintJobs: [], finishedSeries: false, finishedCampaign: false,
            hitTheWall: false, medals: medals, newMedals: [], medalTopUp: 0,
            headline: reignLine(streak: out.streakAfter, best: out.bestAfter)
        )
        return out
    }

    /// "Title defended. A reign of 3, your best."
    static func reignLine(streak: Int, best: Int) -> String {
        let reign = streak == 1 ? "The first defence of the title." : "Title defended. A reign of \(streak)."
        if streak >= best, streak > 1 { return "\(reign) Your best yet." }
        if best > streak { return "\(reign) Your best is \(best)." }
        return reign
    }

    // MARK: - The daily exhibition

    /// "2026-09-25", the UTC day. The same everywhere at the same moment.
    static func dayKey(_ date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
    }

    /// Today first, then the days before it, `days_kept` in all.
    static func playableDays(now: Date = Date()) -> [String] {
        (0..<max(1, progression.daily.daysKept)).map { dayKey(now.addingTimeInterval(Double(-$0) * 86_400)) }
    }

    /// FNV-1a over the key: stable across launches and devices, which `hashValue` is not.
    static func daySeed(_ key: String) -> Int {
        var value: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in "daily:\(key)".utf8 { value = (value ^ UInt64(byte)) &* 0x1000_0000_01B3 }
        return Int(value % 2_000_000_000)
    }

    /// Everything one day's exhibition is, drawn from its key alone.
    struct DailyCard: Equatable {
        var key: String
        var seed: Int
        var arena: String
        var twist: CareerCatalogue.TwistEntry
        var opponent: CareerEntrant
        var tier: CareerTier
        var houseBotID: String
        var houseBotSpeed: Double
        var durationS: Int
        var endgameAtS: Int

        var arenaName: String { Catalogue.shared.arena(arena)?.name ?? arena.capitalizedFirst }
    }

    static func dailyCard(_ key: String) -> DailyCard {
        let rules = progression.daily
        let seed = daySeed(key)
        var rng = SeededRandom(seed: seed)
        let arenas = rules.arenas.isEmpty ? ["yard"] : rules.arenas
        let arena = arenas[rng.index(arenas.count)]
        let twists = rules.twists.isEmpty
            ? [CareerCatalogue.TwistEntry(id: "standard", name: "Straight fight", line: "")]
            : rules.twists
        let twist = twists[rng.index(twists.count)]
        let rivals = CareerCatalogue.shared.rivals
        let tier: CareerTier = twist.id == "heavyweight" ? .masters : .championship
        let rival = rivals.isEmpty ? nil : rivals[rng.index(rivals.count)]
        let opponent: CareerEntrant
        if let rival {
            opponent = CareerEntrant(id: rival.id, name: rival.name, roboteer: rival.roboteer,
                                     liveryHex: rival.liveryHex, kind: .rival,
                                     spec: CareerEngine.rivalSpec(rival, at: tier), rivalID: rival.id)
        } else {
            var filler = SeededRandom(seed: seed &+ 1)
            opponent = CareerEngine.fillerEntrant(index: 0, tier: tier, rng: &filler)
        }

        let round = progression.round
        var duration = round.durationS
        var endgame = round.endgameAtS
        var house = CareerEngine.houseBot(tier: .masters, arena: arena)
        switch twist.id {
        case "sprint":
            duration = 90
            endgame = 60
        case "open_corner":
            house = ("", 0)
        case "house_hunts":
            house.speed *= 1.25
        default:
            break
        }
        return DailyCard(key: key, seed: seed, arena: arena, twist: twist, opponent: opponent, tier: tier,
                         houseBotID: house.id, houseBotSpeed: house.speed,
                         durationS: duration, endgameAtS: endgame)
    }

    /// The card as a `NextMatch`, so `CareerFightConfig` sends it like any career match: zero
    /// scrap rules (it banks nothing) and no points.
    static func dailyMatch(_ card: DailyCard, careerSeed: Int = 0) -> NextMatch {
        let name = card.houseBotID.isEmpty ? "" : CareerEngine.houseBotName(card.houseBotID)
        return NextMatch(
            tier: card.tier, seriesIndex: card.tier.index, matchIndex: 0, isFinal: false, isReplay: false,
            attempts: 0, opponent: card.opponent, arena: card.arena, arenaName: card.arenaName,
            houseBotID: card.houseBotID, houseBotName: name, houseBotSpeed: card.houseBotSpeed,
            houseBotLine: card.twist.line, scoutingLine: ProgressionEngine.scoutingLine(for: card.opponent),
            grudgeLine: "", aiSkill: CareerEngine.aiSkill(for: card.tier),
            temperament: CareerEngine.temperament(for: card.opponent, seasonSeed: card.seed),
            scrapRules: ScrapRules(), winPoints: 0, repairsDue: 0,
            mode: .daily(card.key), durationS: card.durationS, endgameAtS: card.endgameAtS
        )
    }

    /// What one exhibition scored, line by line, so the result can print the sum.
    struct DailyScore: Equatable {
        var win = 0
        var damage = 0
        var health = 0
        var time = 0
        var hits = 0
        var total: Int { win + damage + health + time + hits }
    }

    /// The published formula: win + damage x the share of the opponent removed + health x the
    /// share of your own machine left + time x seconds left on a win + hits x hits landed.
    static func dailyScore(won: Bool, opponentRemoved: Double, ownLeft: Double, secondsLeft: Double,
                           hitsLanded: Int) -> DailyScore {
        let rules = progression.daily
        func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
        return DailyScore(
            win: won ? rules.scoreWin : 0,
            damage: Int((Double(rules.scoreDamage) * clamp(opponentRemoved)).rounded()),
            health: Int((Double(rules.scoreHealth) * clamp(ownLeft)).rounded()),
            time: won ? Int((Double(rules.scoreTime) * max(0, secondsLeft)).rounded()) : 0,
            hits: rules.scoreHits * max(0, hitsLanded)
        )
    }

    /// The score of a fought exhibition, read off the arena's result.
    static func dailyScore(card: DailyCard, playerSpec: BuildSpec, result: FightResult?, resultJSON: String) -> DailyScore {
        guard let result else { return DailyScore() }
        let report = ProgressionEngine.matchReport(result: result, spec: playerSpec, startDamage: nil,
                                                   botName: "", opponentName: card.opponent.name,
                                                   resultJSON: resultJSON)
        let theirs = ProgressionEngine.partConditions(spec: card.opponent.spec,
                                                      damage: result.damage[CareerFightConfig.opponentID],
                                                      start: nil)
        let theirLeft = theirs.isEmpty ? 1 : theirs.map(\.condition).reduce(0, +) / Double(theirs.count)
        let mine = report.parts.isEmpty ? 1 : report.parts.map(\.condition).reduce(0, +) / Double(report.parts.count)
        return dailyScore(won: report.isWin, opponentRemoved: 1 - theirLeft, ownLeft: mine,
                          secondsLeft: Double(card.durationS) - report.durationSeconds,
                          hitsLanded: report.hitsLanded)
    }

    static func dailyBests(_ json: String) -> [String: Int] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object.compactMapValues { ($0 as? NSNumber)?.intValue }
    }

    /// Keep the best per day, and only the days that can still be played (plus the new one).
    static func recordingDaily(_ score: Int, key: String, in json: String, now: Date = Date()) -> (json: String, isBest: Bool) {
        var bests = dailyBests(json)
        let isBest = score > (bests[key] ?? -1)
        if isBest { bests[key] = score }
        let keep = Set(playableDays(now: now)).union([key])
        bests = bests.filter { keep.contains($0.key) }
        return (JSONText.string(from: bests), isBest)
    }

    /// Daily is open once the campaign is won (and, like the defence, only with the whole game).
    static func dailyAvailable(state: CareerState, gates: Gates = Gates.snapshot) -> Bool {
        state.campaignComplete && (!gates.entitlementSettled || gates.tierAvailable(.masters))
    }
}

// MARK: - The daily exhibition screen (functional hook, existing style)

/// The last seven days as rows, the chosen day's card, FIGHT, and the score after it. Fought
/// through `CareerFightView` with the machine pristine; nothing comes home.
struct DailyExhibitionView: View {

    @Bindable var host: ArenaHost
    let state: CareerState
    let bot: BotBuild?
    var onBack: () -> Void

    @Environment(\.modelContext) private var context

    private enum Phase: Equatable { case list, fight, result }

    @State private var phase: Phase = .list
    @State private var chosenKey = PostCampaign.dayKey()
    @State private var lastScore: PostCampaign.DailyScore?
    @State private var lastWasBest = false

    private var days: [String] { PostCampaign.playableDays() }
    private var card: PostCampaign.DailyCard { PostCampaign.dailyCard(chosenKey) }
    private var bests: [String: Int] { PostCampaign.dailyBests(state.dailyBestJSON) }
    private var canFight: Bool { bot?.isValid ?? false }

    var body: some View {
        Group {
            switch phase {
            case .fight:
                if let bot {
                    CareerFightView(
                        host: host,
                        playerConfig: bot.toBotConfig(id: CareerFightConfig.playerID, controller: "player", pristine: true),
                        opponentConfig: card.opponent.spec.toBotConfig(id: CareerFightConfig.opponentID, controller: "ai"),
                        arena: card.arena,
                        seed: card.seed,
                        next: PostCampaign.dailyMatch(card, careerSeed: state.currentSeasonSeed)
                    ) { result, json in
                        settle(bot: bot, result: result, json: json)
                    }
                } else {
                    list
                }
            case .list, .result:
                list
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private var list: some View {
        ZStack {
            StageBackdrop(host: host, still: .withBot, dim: 0.26)
            StageScrim()
            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            BackChevron(action: onBack)
                            Text("DAILY EXHIBITION")
                                .font(Stage.display(26))
                                .kerning(Stage.Tracking.display(26))
                                .foregroundStyle(Stage.type)
                                .lineLimit(1)
                                .minimumScaleFactor(BroadcastType.floorScale(.display, size: 26, wanted: 0.7))
                        }
                        Text("One match a day, the same for everyone. Your machine fights as built and nothing comes home: no scrap, no damage, just the score.")
                            .font(Stage.body(13))
                            .foregroundStyle(Stage.typeDim)
                            .fixedSize(horizontal: false, vertical: true)
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(days, id: \.self) { key in dayRow(key) }
                            }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    .frame(maxWidth: 300, alignment: .topLeading)
                    Spacer(minLength: 8)
                    cardPanel
                        .frame(width: StageLayout.columnWidth(proxy.size.width))
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
        }
        .onAppear { registerFocus() }
        .onChange(of: chosenKey) { _, _ in registerFocus() }
    }

    private func dayRow(_ key: String) -> some View {
        let chosen = key == chosenKey
        return Button { chosenKey = key; phase = .list } label: {
            HStack {
                Text(key == PostCampaign.dayKey() ? "Today" : key)
                    .font(Stage.body(13, weight: chosen ? .semibold : .regular))
                    .foregroundStyle(chosen ? Stage.type : Stage.typeDim)
                Spacer(minLength: 6)
                Text(bests[key].map { "Best \($0)" } ?? "Not played")
                    .font(Stage.body(13))
                    .foregroundStyle(bests[key] == nil ? Stage.textFaint : Stage.line)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(CutRect(6).fill(Stage.type.opacity(chosen ? 0.10 : 0.04)))
        }
        .buttonStyle(.plain)
    }

    private var cardPanel: some View {
        GlassPanel(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                PanelLabel("Daily ·", accent: card.twist.name)
                Text(card.opponent.name.uppercased())
                    .font(Stage.display(23))
                    .kerning(Stage.Tracking.display(23))
                    .foregroundStyle(Stage.type)
                    .lineLimit(1)
                    .minimumScaleFactor(BroadcastType.floorScale(.display, size: 23, wanted: 0.6))
                Text("\(card.opponent.roboteer) · \(card.arenaName)")
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.typeDim)
                Text(card.twist.line)
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.typeDim)
                    .fixedSize(horizontal: false, vertical: true)
                if phase == .result, let lastScore {
                    Text("Scored \(lastScore.total)\(lastWasBest ? ", your best for this day." : ".")")
                        .font(Stage.body(13, weight: .semibold))
                        .foregroundStyle(Stage.line)
                    Text("Win \(lastScore.win), damage \(lastScore.damage), health \(lastScore.health), time \(lastScore.time), hits \(lastScore.hits).")
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.typeDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                StageButton("Fight", kind: .primary, enabled: canFight, focusID: "daily.fight") { fight() }
                    .padding(.top, 2)
                if !canFight {
                    Text("Your machine is not legal. Fix it in the garage first.")
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.danger)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func registerFocus() {
        PadFocus.shared.set([PadItem("daily.fight", enabled: canFight) { fight() }], back: { onBack() })
    }

    private func fight() {
        guard canFight else { return }
        PadFocus.shared.clear()
        lastScore = nil
        phase = .fight
    }

    private func settle(bot: BotBuild, result: FightResult?, json: String) {
        let score = PostCampaign.dailyScore(card: card, playerSpec: bot.spec, result: result, resultJSON: json)
        let recorded = PostCampaign.recordingDaily(score.total, key: card.key, in: state.dailyBestJSON)
        state.dailyBestJSON = recorded.json

        let log = FightLog()
        log.date = Date()
        log.tier = card.tier
        log.round = -3
        log.opponentID = card.opponent.id
        log.opponentName = card.opponent.name
        log.botName = bot.name
        log.outcome = result?.outcome.type ?? "forfeit"
        log.didWin = result.map { $0.outcome.winner == CareerFightConfig.playerID } ?? false
        log.atSeconds = result?.outcome.atSeconds ?? 0
        log.arena = card.arena
        log.source = FightLog.Source.daily
        log.resultJSON = json
        log.configJSON = ArenaHost.shared.lastFightConfigJSON
        context.insert(log)
        try? context.save()

        if card.key == PostCampaign.dayKey() {
            GameCenterService.shared.report(leaderboard: PostCampaign.progression.daily.leaderboard,
                                            score: score.total)
        }
        lastScore = score
        lastWasBest = recorded.isBest
        host.showStage(bot: bot.toBotConfig(id: CareerFightConfig.playerID, controller: "player"))
        phase = .result
    }
}
