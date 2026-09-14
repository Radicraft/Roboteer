# App Store copy and listing answers

Everything App Store Connect asks for, written out so the owner can paste it in. Nothing here is
submitted by an agent. Brief §14 requires the wall to be stated plainly on the store page, and it is
stated three times below: in the promotional text, in the first paragraph of the description, and
again under its own heading in the description.

No em dashes anywhere in this file's user-facing strings, per the standing rule.

Field limits used: Name 30, Subtitle 30, Keywords 100 bytes, Promotional text 170, Description 4,000,
What's New 4,000. Keywords are kept pure ASCII so the byte count and the character count agree.

---

## 1. Primary language and storefronts

**Primary App Store language: English (UK), `en-GB`.**

en-GB is the default or an additional language in 172 of the 175 storefronts. The only three it cannot
reach are the United States, Canada and Japan. So en-GB carries the full weight of the listing, and if
a second locale is ever added it should be **en-US** first, because en-GB reaches the US storefront not
at all. en-AU buys nothing en-GB does not already cover.

The four English locales are not one shared keyword pool. Any head term missing from en-GB is missing
from 172 storefronts, so a second locale repeats the head terms and varies only the tail.

---

## 2. Name

```
Roboteer
```

8 characters of 30. Cleared in `docs/title-clearance.md`: zero apps on the US or GB storefront carry the
literal string, and the `com.roboteer.*` namespace looked unclaimed.

---

## 3. Subtitle (30 max)

```
Build robots. Fight. Rebuild.
```

29 characters. The subtitle is indexed by App Store search alongside the title, keywords and primary
category, so it is spent on real search terms rather than on a slogan: it buys "build", "robots",
"fight" and "rebuild". It is three short sentences, not a comma separated list of keywords, which is the
classic 2.3.7 metadata stuffing trigger.

---

## 4. Keywords (100 bytes max)

```
robot,fighting,combat,mech,arena,builder,physics,flipper,spinner,tournament,workshop,scrap,crusher
```

98 bytes. No spaces after the commas, because a space costs a byte and buys nothing.

Rules this list obeys:

- No repeat of the title. "Roboteer" is already indexed from the name field, so spending 8 bytes on it
  again would be waste.
- No word shorter than three characters, which App Store Connect rejects.
- No competitor app names and no television show names. In particular the words "wars", "battlebots",
  "robotica" and "techno games" are absent, and the bare word "battle" was dropped as well: combined with
  "robot" in the same field it reconstructs a well known show mark closely enough to be an argument nobody
  needs to have. Brief §3 governs.
- No named competitor robot, per brief §3.

Words deliberately left out and why: "wars" and "battle" for the reason above; "free" because the price
tier already communicates it and Apple discourages price language in metadata; "3D", "best" and "new"
because they are noise.

---

## 5. Promotional text (170 max)

```
Free to play the first two circuits. One purchase unlocks everything, forever. No other purchases, no ads, no subscription. Full support for MFi and console controllers.
```

169 characters.

Promotional text does not affect search ranking, so it carries no keywords. What it does have is the
ability to be edited with no new build and no review, which makes it the right home for the monetisation
sentence: if any part of that claim ever needs to change, it can be changed the same day.

---

## 6. Description (4,000 max)

```
You are a roboteer. You build fighting robots out of parts you have earned, you drive them into an arena full of saws and pits and flame jets, and you either take your opponent apart or watch your own wheels come off. Then you go back to the workshop and fix what broke.

Roboteer is free to play through its first two circuits. One purchase of £4.99 unlocks the rest of the game permanently. There are no other purchases, no ads and no subscription.

THE BUILD IS THE GAME

Six chassis archetypes, five drive options, ten primary weapons, two utility slots and armour chosen face by face. A wedge that cannot get under an opponent is a bad wedge. Thick front armour makes you slow. A heavy spinner needs a chassis that can carry it. Every choice you make in the workshop shows up in the arena, because the arena is running real physics rather than a damage table.

DAMAGE THAT MEANS SOMETHING

There is no health bar. Your robot is a set of components and every one of them can fail on its own. Lose a wheel and you drive in a curve. Lose a weapon mount and the weapon is just weight. Take a hit hard enough and the panel bends, the paint scorches and a shower of gold bolts goes across the floor for you to collect.

SIX ARENAS THAT FIGHT BACK

The Yard is walls and floor spikes. The Grinder puts an angle grinder on each flank. Drop Zone opens a pit in the middle of the floor partway through the fight. The Furnace times its flame jets. The Crush pins you against a wall and flattens you. The Coliseum has all of it at once. Every hazard works on you as well as on your opponent.

A STABLE, NOT A ROBOT

You keep several machines, each with its own build, its own damage and its own repair bill. A scouting report tells you what is waiting in the next round so that sending the right machine is a real decision. A robot can also be destroyed beyond economical repair, which is survivable only because you have others. Rival roboteers upgrade their machines in step with yours and remember what happened last time you met.

FIVE ARENA BOSSES

THRESHER pins and squeezes. GRUDGE cooks your electronics. BANDSAW herds you into a wall and holds you there. ANVIL is a wall with wheels. CINDER does not try to damage you at all. It tries to throw you into whatever hazard is nearest.

MORE THAN THE LADDER

Side events are physics challenges with their own rewards: Sumo, Gauntlet, Pinball, Football and Wall Smash. Rumble is a three robot free for all. The workshop test arena lets you try a build against a dummy before you pay an entry fee. Every fight is recorded and can be replayed with a free camera and slow motion, and clips can be shared. An asynchronous ladder pits you against other players' builds, driven by the game, so there is nothing to wait for.

WHAT IT COSTS

Free to play the first two circuits, the Scrapyard and the Regional. That free portion includes the workshop and its test arena, two arenas, one arena boss, room for two robots in the garage and an accelerated blueprint drip so you have real choices to make.

One purchase of £4.99 unlocks everything else forever: the National, Championship and Masters circuits, the remaining four arenas, four more bosses, the full part library, a garage of up to five robots, the side events, replays and sharing, and the ladder. All of your progress carries across the purchase. Nothing resets.

No other purchases. No ads. No subscription. Nothing inside the game is ever sold for money. Every weapon and chassis is earned by playing, and the unlock is offered in two places only: once after you win the Regional final, and permanently in Settings. It is a door charge, not a shop. The purchase is restorable and is enabled for Family Sharing.

ALSO

Full support for MFi and console controllers. Landscape on iPhone and iPad. Game Center leaderboards.

Roboteer is an original game. It is not connected to, endorsed by or based on any television programme, and every robot, arena and name in it was made for this game.
```

3,988 characters, inside the 4,000 limit with twelve to spare. Recount in App Store Connect before pasting
if a word is changed, because the field counts the blank lines too.

Two notes on the wording:

- The £4.99 figure appears twice. If the price tier changes, both mentions and the promotional text change
  with it. The promotional text can be fixed without a new build; the description cannot, so the price is
  stated in the description only because brief §14 asks for the wall to be plain, and the honesty is worth
  the maintenance.
- The final paragraph is there on purpose. It is cheap insurance on the point brief §3 cares about, and it
  reads as confidence rather than as a disclaimer.

---

## 7. What's New for 1.0

```
First release.

Roboteer is a robot combat game with a builder deep enough to matter. Six chassis, five drives, ten weapons, armour chosen face by face, six arenas with hazards that work on you as well as on your opponent, five arena bosses, a stable of robots with individual damage and repair bills, rival roboteers who upgrade alongside you, side events, replays, and an asynchronous ladder against other players' builds.

Free to play the first two circuits. One purchase unlocks everything forever. No other purchases, no ads and no subscription.

Full support for MFi and console controllers.
```

---

## 8. App Review notes

```
Roboteer is a single player robot combat game. There is no account, no login and no user generated content that is visible to other players.

IN APP PURCHASE

There is exactly one in app purchase in the whole app: a non-consumable shown as "The full game", product identifier com.radicraft.roboteer.unlock. There are no consumables, no subscriptions, no advertising and no second transaction of any kind. Nothing inside the game is purchasable with money. All parts, robots and materials are earned by playing.

The purchase is restorable. "Restore purchases" is in Settings and calls AppStore.sync(), and entitlements are also re-checked from Transaction.currentEntitlements at every launch. The product is enabled for Family Sharing in App Store Connect.

HOW TO REACH THE PURCHASE

Two routes, and the reviewer does not need to play through anything:

1. Settings. From the main menu tap Settings. The row labelled "The full game" shows the price and opens the unlock screen, and the row below it is "Restore purchases". Both are available from a fresh install with no play required.

2. In the normal flow. The unlock screen is also shown once, automatically, after the player wins the Regional circuit final. It is never shown during a fight, never on a timer and never at a discount.

WHAT THE PURCHASE UNLOCKS

Free without purchase: the Scrapyard and Regional circuits, two arenas (The Yard and The Grinder), one arena boss (CINDER), the workshop and its test arena, a garage holding two robots, and an accelerated blueprint drip. Unlocked by the purchase: the National, Championship and Masters circuits, four more arenas, four more bosses, the full part library, a garage of up to five robots, the side events, replays and sharing, and the asynchronous ladder. Player progress is unaffected by the purchase in either direction and nothing is reset.

CONTROLLERS

The game supports MFi and console controllers through GameController. It is fully playable with a DualSense, a Xbox Wireless Controller or an MFi controller, and it is also fully playable with touch alone, so no controller is needed to review it. If a controller is connected, the on screen driving controls hide and a controller glyph legend is shown instead. Controllers are supported on every screen, not only in the arena.

NETWORK

The asynchronous ladder uses CloudKit to exchange robot builds. It is never real time and there is no matchmaking wait. If iCloud is unavailable the ladder falls back to locally generated opponents, so the mode works with no network at all. Game Center is used for identity and two leaderboards and degrades to a local guest name if it is unavailable.

CONTENT

Combat is between machines. There are no people, no characters and no blood. Damage is bent metal, sparks, scorch marks and detached wheels.

ORIGINAL WORK

Every robot, arena, boss and name in the game is original to it. The game is not connected to, endorsed by or based on any television programme, and it uses no third party marks, logos or typefaces.
```

---

## 9. Age rating answers

Target rating: **4+**, with the one violence question answered honestly. App Store Connect asks these as a
questionnaire; answer every other question "None".

| Question | Answer |
|---|---|
| Cartoon or Fantasy Violence | **Infrequent/Mild** |
| Realistic Violence | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Profanity or Crude Humour | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Medical/Treatment Information | None |
| Alcohol, Tobacco, or Drug Use or References | None |
| Simulated Gambling | None |
| Sexual Content or Nudity | None |
| Graphic Sexual Content and Nudity | None |
| Contests | None |
| Unrestricted Web Access | No |
| Gambling | No |
| Made for Kids | **No** |
| In app purchases | **Yes** |
| Age Assurance / age verification | Not used |

Cartoon or Fantasy Violence is answered Infrequent/Mild rather than None because machines are visibly
destroyed, with sparks, flame hazards and detached parts. Nothing is living, nothing bleeds and no person
appears, so nothing above Mild applies. Answering None here and shipping flame jets and saws is the kind
of mismatch that gets a rating raised by Apple after the fact.

---

## 10. Categories and store settings

| Setting | Value |
|---|---|
| Primary category | **Games** with subcategory **Action** |
| Secondary category | **Games** with subcategory **Simulation** |
| Price | Free |
| In app purchase | "The full game", non-consumable, `com.radicraft.roboteer.unlock`, **£4.99** tier, **Family Sharing enabled**. Reference name "Roboteer full game unlock", matching `Roboteer/Store/Roboteer.storekit` |
| Primary language | English (UK) |
| Device family | iPhone and iPad, landscape |
| Game Center | Enabled, two leaderboards (`ladder_rating`, `career_wins`) |
| Content rights | Contains no third party content |

The primary category is the one that is indexed alongside the title, subtitle and keywords, so Action is
the right primary: it is where the audience for this game browses. Simulation as the secondary picks up the
builder and workshop half of the game without costing anything.

---

## 11. Screenshots and the caption band

Required sets are **iPhone 6.9 inch** and, if the iPad listing is kept, **iPad 13 inch**. Apple scales every
other size from those, so no other set needs shooting. Maximum 10 per size per localisation, PNG or JPEG,
**no alpha channel**.

The app is landscape, so the 6.9 inch frames are **2868 x 1320**.

Screenshot text is indexed by App Store search, so the captions are written as real words rather than as
slogans. `Art/store/frame-template.py` lays the caption band on, in the locked chrome style: bold condensed
white capitals with tight tracking on translucent dark glass with a thin light top edge, and gold `#f2c14e`
used only for scrap words. `Art/store/example-frame.png` proves the template against a stand-in.

```
python3 Art/store/frame-template.py SHOT.png OUT.png "One good flip ends it" --sub "Every hit costs you scrap" --check
```

Planned order, which is also the order of importance because most people never swipe past the third:

| # | Screen | Caption | Sub |
|---|---|---|---|
| 1 | Arena mid throw, bolt shower | One good flip ends it | Real physics, not a damage table |
| 2 | Builder with a chassis on the turntable | Build it wrong and you will know | Six chassis, ten weapons, armour by face |
| 3 | Damage assessment after a loss | Lose a wheel and you drive in a curve | Every component fails on its own |
| 4 | The Grinder with hazards live | Six arenas that fight back | Hazards work on you as well |
| 5 | Bracket screen | Win the circuit, earn the blueprint | Scrapyard to Masters |
| 6 | Garage with a stable of robots | A stable, not a robot | Send the right machine |
| 7 | Boss encounter, CINDER | Five arena bosses | Each one needs a different build |
| 8 | Replay with the free camera | Watch it again from anywhere | Replays and shareable clips |

Rules for shooting them, from the App Store asset notes:

- Never shoot against live or half built data. Curate the state first.
- No device frames in previews. Frames are fine in screenshots and risky in previews.
- The caption band sits inside the frame, so the output is still exactly 2868 x 1320 and still a valid
  screenshot. The script refuses em dashes.

**App preview**, optional, 15 to 30 seconds, captured with `simctl io recordVideo` from a real fight.
**886 x 1920 is accepted for every modern iPhone**, so one master file covers the range. A silent audio
track still counts as a track and a missing one is a known rejection, so mux one in even if the fight is
played muted. Screen capture only, no hands and no prices, per 2.3.4.

---

## 12. App icon

`Roboteer/Assets.xcassets/AppIcon.appiconset/` holds `AppIcon.png`, `AppIcon-Dark.png` and
`AppIcon-Tinted.png`, all 1024 x 1024, 8 bit RGB, no alpha, with a `Contents.json` carrying the three
`luminosity` appearances. The candidates are kept in `Art/store/icon-candidates/`; the chosen one is
`icon-e-pro-PICKED.png`.

The icon is the wedge nose and the raised flipper plate of the player's robot, three quarter from low
front, under one amber stage light with dry ice at the base. Blue livery and bare steel, per the art
direction, and deliberately not a white and black full width flipper, which is the livery read brief §3
rules out. No text and no logo, which is also the only way an icon survives being 60 points wide.
