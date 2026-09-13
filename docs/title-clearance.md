# Title clearance: "Roboteer"

Research date: 13 September 2026. Answers brief v3 §16.6 (title clearance) and §16.5 (cellular download threshold).

This is a factual search record, not legal advice. Nothing here is a legal opinion and none of it substitutes for a trade mark attorney's clearance search if you want certainty.

Method note: this was done entirely with public APIs and plain HTTP fetches. No browser was used. Three sources refused automated access and are recorded as such below.

---

## Question 1: is "Roboteer" clear as an App Store title?

### (a) App Store

Searched via the public iTunes Search API (no auth required), 13 Sep 2026. Twelve queries: three terms (`roboteer`, `roboteers`, `robo teer`) x two storefronts (`us`, `gb`) x two entities (`software`, `iPadSoftware`), `limit=25` each.

Query form used:

- https://itunes.apple.com/search?term=roboteer&entity=software&country=us&limit=25
- https://itunes.apple.com/search?term=roboteer&entity=software&country=gb&limit=25
- https://itunes.apple.com/search?term=roboteer&entity=iPadSoftware&country=us&limit=25
- https://itunes.apple.com/search?term=roboteer&entity=iPadSoftware&country=gb&limit=25
- same four again with `term=roboteers`
- same four again with `term=robo%20teer`

**Result: zero apps whose name contains the string "roboteer" on either storefront, for any of the three terms.** Result counts were 19 to 22 per query, but every hit was a fuzzy keyword match on "robot" and none carried the literal word. A case-insensitive grep for "roboteer" across all 12 result sets returned no match in any `trackName`, `sellerName` or `bundleId`.

Representative hits returned instead (US storefront, `term=roboteer`, `entity=software`), listed to show what the fuzzy matcher surfaced, since the honest answer to "list every hit" is that none of them are the name:

- War Robots Multiplayer Battles | MYGAMES MENA FZ LLC | com.pixonic.wwr | Games | 2014-04-15 | https://apps.apple.com/us/app/war-robots-multiplayer-battles/id806077016
- Dino Game & Robots Simulator | Awon Haider Naqvi | com.hn.horse.simulator.robot.game | Games | 2022-01-20 | https://apps.apple.com/us/app/dino-game-robots-simulator/id1605161769
- Make Your Robot! | Rollic Games Oyun Yazilim ve Pazarlama Anonim Sirketi | com.marula.makemyexdoll | Games | 2022-02-11 | https://apps.apple.com/us/app/make-your-robot/id1584128916
- Robotek | David Peroutka | net.hexage.robotek.hd | Games | 2011-06-09 | https://apps.apple.com/us/app/robotek/id437602797
- Mechangelion - Robot Fighting | MOONEE PUBLISHING LTD | com.TsyaTsya.Mechangelion | Games | 2023-02-02 | https://apps.apple.com/us/app/mechangelion-robot-fighting/id1668157669
- Robot Warfare: Mech Battle | AZUR INTERACTIVE GAMES LIMITED | ru.azurinteractive.robotwarfare | Games | 2018-12-16 | https://apps.apple.com/us/app/robot-warfare-mech-battle/id1434052677
- Robot Fighting: Mech Arena | KVIKEN KOD, OSOO | mobi.teengames.RobotFighting2MinibotBattle3D | Entertainment | 2015-12-21 | https://apps.apple.com/us/app/robot-fighting-mech-arena/id1067180549
- Robot Breaker | Gentlemens sro | com.chargedmonkey.robotbreaker | Games | 2025-05-29 | https://apps.apple.com/us/app/robot-breaker/id6742655817
- Rogue Robot Simulator Extreme | EXTREMESOFT BILISIM REKLAMCILIK TICARET LIMITED SIRKETI | com.extremesoft.roguerobot | Games | 2021-02-03 | https://apps.apple.com/us/app/rogue-robot-simulator-extreme/id1551321183
- Mech Gladiator2 | keijiro iwase | act1.mechgladiator2 | Games | 2011-12-11 | https://apps.apple.com/us/app/mech-gladiator2/id474439445
- Vector Companion Robot | Digital Dream Labs LLC | com.anki.vector | Lifestyle | 2018-10-10 | https://apps.apple.com/us/app/vector-companion-robot/id1433999065
- Jimu | UBTECH ROBOTICS CORP | com.ubtechinc.jimu | Education | 2016-01-22 | https://apps.apple.com/us/app/jimu/id1070681102
- Robot Era Evolution | Amir Ali | com.aa.robot.evolution.era.game | Games | 2026-07-30 | https://apps.apple.com/us/app/robot-era-evolution/id6793934366
- World Of Robots | AI GAMES FZ LLC | com.sgs.war.robots | Games | 2021-04-02 | https://apps.apple.com/us/app/world-of-robots/id1559637955

The GB storefront returned an overlapping but slightly different set (21 and 20 hits), also with no "roboteer" string. Notable GB-only hits: Bee Robot Transform Game 3D, Truck Wars - Mech arena, and the same Mechangelion and Robotek titles under localised names.

Limitation to be honest about: the iTunes Search API is a fuzzy keyword index, not the App Store front-end "Search" tab, and it does not expose apps that are unlisted or removed. It is the best auth-free proxy available, and a twelve-query sweep finding zero literal matches is strong evidence, but it is not identical to typing the word into the App Store app on a device. The brief's own task of typing it into the App Store Search tab on two storefronts is still worth thirty seconds on the phone as a confirmation.

Also relevant: `com.roboteer.*` style bundle IDs did not appear in any result, so the reverse-DNS namespace looks unclaimed by any shipping app.

### (b) UK IPO trade marks

**Could not fetch the UK IPO site directly.** Both https://trademarks.ipo.gov.uk/ipo-tmtext and https://trademarks.ipo.gov.uk/ipo-tmtext/page/Results return HTTP 403 to any non-browser client; the body is a JavaScript captcha interception page ("Captcha", "Enable JavaScript"). This was tried twice with full browser-style headers. Since the task rules out driving a browser, the UK register was searched through its official aggregator instead.

Fallback used: **TMview** (https://www.tmdn.org/tmview/), the EUIPO-run common search portal, which indexes the UK IPO register (office code GB) alongside EUIPO, USPTO, WIPO and national registers. Queried through its JSON endpoint `POST https://www.tmdn.org/tmview/api/search/results` with `criteria: "C"` (contains) so that ROBOTEER, ROBOTEERS and any compound such as X-ROBOTEER would all be caught.

Search 1, all offices, all classes, mark text contains "roboteer". **Three results worldwide:**

- **ROBOTEER**, Korea (KIPO), application 4120010008884, filed 14 May 2001, Nice class **35**, applicant 주식회사 로보티어 (Roboteer Co Ltd). Class 35 is advertising and business services. Not games, not software.
- **ROBOTEER**, United States, registration **1020159**, registered 9 Sep 1975, owner **MB Associates** (San Ramon, California). TMview maps it to Nice classes 7, 9, 10, 11, 12, 15, 16, 28. See (c) for its status.
- **M-ROBOTEER**, China (CNIPA), application 14002049, filed 30 Jan 2014, registered 14 Apr 2015, Nice class **12** (vehicles), applicant 常州路博特科技有限公司.

Search 2, offices filtered to GB, EM (EUTM), US and WO (WIPO international register), all classes, contains "roboteer". **One result: the dead US 1975 registration only.**

**So: no UK IPO mark, no EU trade mark, and no WIPO international registration containing the word ROBOTEER, live or otherwise, in any class.** No class 9 mark and no class 41 mark anywhere in TMview's coverage except the 1975 US one, which is dead.

Because the search was a "contains" search on "roboteer", it necessarily also covers "roboteers": any ROBOTEERS mark would have appeared. A separate explicit "roboteers" query was attempted twice and was refused by TMview's rate limiter (connection reset), so it is recorded as not completed; the contains logic makes it redundant rather than missing.

Not attempted successfully: **WIPO Global Brand Database** (https://branddb.wipo.int) sits behind an Altcha captcha and returns no data to a fetch. **Justia Trademarks** is behind Cloudflare and returns 403. Both are recorded as blocked, not as clear.

### (c) USPTO

**The USPTO's own search front end could not be queried directly.** https://tmsearch.uspto.gov serves a JavaScript application from S3; the API paths it uses are not reachable without the app's own session, and probing returned S3 `MethodNotAllowed` / `NoSuchKey` errors rather than data. The USPTO Open Data trademark API requires an API key.

What did work: **TSDR**, the USPTO's public Trademark Status and Document Retrieval system, on the one record TMview surfaced.

- https://tsdr.uspto.gov/statusview/rn1020159

Record, as returned 13 Sep 2026:

- Mark: **ROBOTEER** (typeset word, standard character claim)
- Serial number 81020159, registration number **1020159**
- Registered **9 September 1975**
- Owner: **MB Associates**, San Ramon, California, United States
- Class: US class 021 (the pre-Nice US classification, electrical apparatus). No Nice class assigned; TMview's 7/9/10/11/12/15/16/28 mapping is a modern back-conversion, not what the certificate said.
- Goods and services: "No Description Entered" in the electronic record
- **Status: DEAD.** "Registration cancelled because registrant did not file an acceptable declaration under Section 8." Status date and cancellation date both **2 February 1982**.
- Paper file destroyed 7 September 1985.

**There is no live USPTO registration or pending application for ROBOTEER in class 9, class 41, or any other class** that appears in TMview's USPTO feed. The only US mark that ever existed has been dead for forty-four years, was in a hardware class, and its owner's file no longer exists.

Caveat: TMview's USPTO coverage is normally complete for live and recent records, but because the USPTO's own search could not be queried directly, a very recent application (filed in the last few weeks and not yet propagated) would not necessarily show. That is a small residual gap.

### (d) General web: existing games, products, companies

- **Novel: "Roboteer" by Alex Lamb** (Gollancz, 2015), first book of the Roboteer trilogy. This is the single most prominent commercial use of the exact word. It is a science fiction novel, Nice class 16 / 9 territory for publishing, with no games connection.
  - https://www.hachette.com.au/alex-lamb/roboteer
  - https://www.amazon.com/Roboteer-Alex-Lamb/dp/147320609X
  - https://www.sffworld.com/2016/04/roboteer-by-alex-lamb/
  - Closeness to a robot-combat game: low. Different medium, different audience, no trade mark registration found in any register searched above.

- **Steam: nothing.** Steam's store search API returned `{"total":0,"items":[]}` for both "roboteer" and "roboteers".
  - https://store.steampowered.com/api/storesearch/?term=roboteer&l=en&cc=us
  - https://store.steampowered.com/api/storesearch/?term=roboteers&l=en&cc=us

- **itch.io: nothing.** https://itch.io/search?q=roboteer returns 38 fuzzy projects, none titled Roboteer. The near-misses are Roboter-prefixed German titles (Roboter Alarm, Roboterritter, Roboter! Kannst du Fühlen?), Robotherapy, RobotBeerBoy, and one Portuguese "Roboteiro - Delivery". None is a robot-combat builder.

- **Google Play: no app named Roboteer found.** Searches surfaced only generic robot-builder titles (Robot Builder Games for Kids, Robot Factory Toy Maker Game, Robotics!, RoboMaker, Robot Factory). The closest in concept is ZeptoLab's **Robotics!** (https://play.google.com/store/apps/details?id=com.zeptolab.robotics), which is genuinely a build-a-battle-robot physics game, but it is not called Roboteer.

- **BoardGameGeek: could not complete.** BGG's XML API returns "Unauthorized" to unauthenticated clients and its web search returns 403. No BGG check was made. Given Steam, itch, both app stores and three trade mark registers came back clean, a board game of this name is unlikely but unverified.

- **UK Companies House: three companies, none in games.** https://find-and-update.company-information.service.gov.uk/search?q=roboteer
  - **ROBOTEER LTD** (12702569), dissolved 20 September 2022. Guisborough.
  - **ROBOTEER AUTOMATION LIMITED** (15185702), **active**,, incorporated 4 October 2023, Telford. SIC code **62012, business and domestic software development**. https://find-and-update.company-information.service.gov.uk/company/15185702
  - **ROBOTEERS LIMITED** (07291856), dissolved 1 October 2013. Witham, Essex.
  - A company name is not a trade mark and confers no right to stop anyone using the word. The one worth noting is Roboteer Automation Limited, because its SIC code is software development, so it is nominally in the same broad field. It is an automation firm, not a games publisher, and it holds no registered mark.

- **The word itself is generic English.** Wiktionary records "roboteer" as `robot` + `-eer`, meaning "one who operates a robot" and "one who takes an interest in robotics", with printed citations from **1984** (Orville Schell, *Modern Meat*) and **1994** (David Clarke Burks, *Place of the Wild*), both predating the TV show.
  - https://en.wiktionary.org/wiki/roboteer
  - Note: search engines index an `en.wikipedia.org/wiki/Roboteer` page describing 1930s usage, but the live MediaWiki API reports that title as missing, so that page no longer exists and should not be cited.

- **"Roboteers, stand by"** is the plural-form catchphrase from the BBC/Channel 5 series *Robot Wars*, announced by director Stuart McDonald. The show's own vocabulary uses the plural in that phrase; the singular noun predates the show.
  - https://en.wikipedia.org/wiki/Robot_Wars_(TV_series)
  - https://robotwars.fandom.com/wiki/Stuart_McDonald

### (e) Risk read

**Low.** The two strongest facts behind that: first, a contains-search of TMview across every register it covers, including the UK IPO and EUIPO, returned only three ROBOTEER-family marks worldwide, none of them British, none of them European, none in class 9 or class 41, and the only one in a goods class anywhere near software is a US registration from 1975 that TSDR confirms was cancelled in February 1982 and whose file was destroyed in 1985. Second, twelve App Store queries across the US and UK storefronts, on both iPhone and iPad entities, found no shipping app carrying the string at all, while the word is an ordinary descriptive English noun with print citations going back to 1984, which makes it both hard for anyone else to monopolise and easy to defend as the plain word for the thing the game is about. The residual exposure is small and of two kinds: the UK IPO's own front end and the WIPO and USPTO front ends could not be queried directly, so a very recently filed application is theoretically invisible to this search; and there is one live UK company, Roboteer Automation Limited, registered under a software SIC code, which owns no trade mark but does use the word commercially in Britain. Neither changes the shape of the answer. Use the singular "Roboteer" and not the plural "Roboteers", keep well clear of the *Robot Wars* catchphrase, house robot names, arena livery and the show's marks, and this is about as clean as a one-word title gets. **This is not legal advice.**

---

## Question 2: App Store cellular download threshold and maximum app size

### The cellular threshold

**200 MB**, and it is a user-configurable prompt, not a hard block.

- Settings path: **Settings > Apps > App Store > Cellular Data > App Downloads** on current iOS. Older writeups say Settings > App Store, or on much older iOS, Settings > iTunes & App Store.
- The three options are **Always Allow**, **Ask If Over 200 MB** (the default), and **Always Ask**.
- Behaviour: under 200 MB the download starts on cellular without a prompt. Over 200 MB, iOS shows a confirmation sheet offering to proceed or to wait for Wi-Fi. **The user can turn the limit off** by choosing Always Allow, in which case any size downloads over cellular with no prompt.
- History: the cap was 50 MB, then 100 MB, then 150 MB from September 2017, then 200 MB from May 2019. In **iOS 13 (2019)** Apple changed it from a hard block into the three-way user setting it still is. There is no evidence of any change since.

Sources:

- Apple, iPhone User Guide (iOS 26 edition), "Change settings and restrictions" for the App Store: https://support.apple.com/guide/iphone/change-settings-and-restrictions-iph3dfd91de/ios . This page documents the setting's existence ("Cellular Data: To allow App Store to use cellular, turn on Cellular Data. Adjust other settings for cellular data such as automatic downloads.") but **does not state the 200 MB number**. Be honest about that: Apple's current first-party documentation describes the control without publishing the threshold. The number appears in the on-device UI string itself, "Ask If Over 200 MB".
- MacRumors, "How to Download Large Apps Over Cellular on iPhone and iPad", dated 3 February 2020: https://www.macrumors.com/how-to/download-large-apps-over-cellular-iphone-ipad/ . Gives 200 MB, the Settings path, and the three exact option names.
- iDownloadBlog, "How to allow cellular app downloads over 200 MB on iPhone and iPad", 25 October 2019: https://www.idownloadblog.com/2019/10/25/about-app-store-cellular-download-limit/ . Confirms 200 MB as the default and notes that permission is always required when roaming, regardless of size.
- 9to5Mac, "iOS 13 removes 200 MB file size limit for app downloads over cellular", 3 June 2019: https://9to5mac.com/2019/06/03/ios-13-removes-200-mb-file-size-limit-for-app-downloads-over-cellular/ . The change from hard cap to user choice.
- TechCrunch, 20 September 2017, on the earlier rise to 150 MB: https://techcrunch.com/2017/09/20/apple-bumps-up-the-the-over-the-air-download-limit-for-apps-to-150-mb/

Searches run for any 2025 or 2026 change to the number returned nothing newer than the iOS 13 change. Treat 200 MB as current as of September 2026, sourced from the iOS setting label rather than from a dated Apple document.

### Apple's maximum app size

From Apple's own developer documentation, App Store Connect Help, **Reference > App uploads > Maximum build file sizes**: https://developer.apple.com/help/app-store-connect/reference/maximum-build-file-sizes/ (fetched 13 September 2026; the page carries no visible "last updated" date).

Verbatim table content for iOS and iPadOS:

| Minimum deployment target | Maximum uncompressed app size | Maximum executable file size |
| --- | --- | --- |
| iOS 9.0 and later | **4 GB** | **80 MB** (1) |
| iOS 7.X through iOS 8.X | 500 MB (1) | 60 MB (2) |
| Earlier than iOS 7.0 | 60 MB | |

Footnotes as printed: (1) "For the total of all `__TEXT` sections in the binary." (2) "For the `__TEXT` sections in each architecture slice. An architecture slice is a part of the fat binary layout that targets a specific architecture."

Other platforms on the same page for context: macOS 200 GB, tvOS 4 GB, visionOS 4 GB, watchOS 75 MB.

**Correction to the brief's §16.5 assumption.** The brief refers to "the 4 GB executable / 2 GB-per-uncompressed-slice rules". That is not what the current page says. The current rules are: **4 GB maximum uncompressed app size** for iOS 9.0 and later, and **80 MB maximum for the total of all `__TEXT` sections in the Mach-O executable**. There is no 2 GB per-slice rule on the page. The per-slice language survives only in footnote 2, which applies to the long-obsolete iOS 7 and 8 tier at 60 MB. The 4 GB figure is the whole app, not the executable.

The same page also notes that **Background Assets** can host large assets separately from the build (https://developer.apple.com/documentation/backgroundassets), and that the size shown on an App Store product page is the thinned installation size for the specific device viewing it, not the universal archive size.

### Verdict for Roboteer

A **60 to 120 MB** app is comfortably under the 200 MB cellular threshold. It downloads over cellular with **no confirmation prompt** for a user on the default "Ask If Over 200 MB" setting, and it is nowhere near any Apple size limit: 4 GB uncompressed and, separately, 80 MB of `__TEXT` in the executable, which a Godot-embedded binary should be checked against but which asset weight does not count towards.

One thing to watch, since the brief budgets roughly 30 MB for Godot alone: the 80 MB `__TEXT` ceiling is about **compiled code**, not models, textures or audio. A Godot engine library plus a SwiftUI shell is not close to 80 MB of `__TEXT`, but it is the only one of the two limits that a 3D game with a large embedded engine could plausibly approach, so measure it once a real archive exists rather than assuming. The headroom to stay under is the 200 MB prompt, and at 120 MB there is 80 MB of it. If asset growth ever threatens 200 MB, Background Assets moves the bulk out of the build without touching the download decision.

---

## Searches that could not be completed

Recorded honestly, so nobody treats a blocked fetch as a clean result:

- **UK IPO trade mark search** (https://trademarks.ipo.gov.uk/ipo-tmtext): HTTP 403, JavaScript captcha, not fetchable without a browser. Covered instead via TMview, which indexes the GB register.
- **WIPO Global Brand Database** (https://branddb.wipo.int): Altcha captcha, no data returned. Covered instead via TMview's WO office filter.
- **USPTO tmsearch** (https://tmsearch.uspto.gov): JavaScript application, no reachable public API without a key. Covered via TMview plus a direct TSDR lookup on the one record found.
- **Justia Trademarks**: Cloudflare 403.
- **BoardGameGeek**: XML API unauthorised, web search 403. No board game check was performed.
- **TMview explicit "roboteers" and "robo teer" queries**: refused by rate limiting after several successful calls. Logically redundant, since the successful "contains roboteer" search would have caught any ROBOTEERS mark.
- **TMview query filtered to Nice classes 9 and 41**: also refused by rate limiting (connection reset), after repeated retries with backoff. Not completed as a standalone query. It is redundant rather than missing: the two searches that did succeed were unfiltered by class and returned only three ROBOTEER-family marks in the entire TMview corpus (Korea class 35, the dead US 1975 registration, China class 12), so there is nothing in class 9 or class 41 for a filtered query to have found. TMview's rate limiter allowed roughly three calls before blocking this address for the rest of the session.
- **App Store front-end Search tab**: not used, since that needs a device or a browser. The iTunes Search API was used as the auth-free equivalent.
