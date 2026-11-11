# Nested pieces and skills (TAG-5): implementation plan

Written 2026-11-09 by a Fable 5.1 plan agent (read-only), from the code on main, the open skill-stats PR (#223, branch `his-4-skill-stats`, assumed merged first) and the owner's decisions of 2026-11-09 (D1 to D7 below). Revised the same day for the owner's answers to its questions (§6) and an independent Fable review of the ADR and the deploy, whose verdict was to deploy with the changes now folded in. The owner approved the spec rows on 2026-11-09 (§7). The owner approved the plan and [ADR 0013](../adr/0013-nested-tags.md) by merging #224 on 2026-11-10.

**This plan has a CloudKit schema change and a second owner-run deploy.** Schema v1 went to Production on 2026-10-21 and can only grow (ADR 0006, 0008). A parent link is one new optional field on `TagRecord`. It's the only irreversible step here, and PR 1 is built around it.

Path key: `Core/`, `Features/` and `Persistence/` are `Sources/` of `Packages/PianismCore`, `PianismFeatures` and `PianismPersistence`.

## 1. What's settled (the owner, 2026-11-09)

- A tag can sit inside one other tag of its kind: a piece in a piece, a skill in a skill. One level: a tag with children can't go inside another, and a child can't have children. Built-in skills can be parents, never children.
- A session tagged with a child counts toward its parent too. Two children of one parent count once toward the parent and fully toward each child.
- Two devices giving a tag different parents: the last change wins. How CloudKit merges two devices' saves, by field or by whole record, is observed at the deploy's step 5 (§4, ADR 0013).
- **D1, archive:** Archive on a parent with unarchived children is blocked, with an alert such as "Archive the 3 pieces inside “Études, Op. 10” first."
- **D2, merge:** only within the same list. Two children of one parent can merge, and so can two top-level tags without children. A parent can't be merged, and nothing merges across parents.
- **D3, picker:** children fold under their parent behind a disclosure arrow, folded by default, open if a child is chosen. Search finds children directly, as "Scales › D minor". An open parent ends with a "+ Add inside Scales" row. Tapping the parent's name still tags the parent.
- **D4, nesting:** an "Add Inside" swipe action on top-level tags (how a tag becomes a parent), and a "Move" swipe action that puts a tag inside an eligible parent or back at the top level. Its sessions follow.
- **D5, labels:** a child reads "Parent › child" in History's rows, Practice's tag line, the session editor and the CSV export (EXP-1).
- **D6, Pro stats** (HIS-4's "Time per piece and skill", Pieces | Skills switch): top-level tags only, a parent's numbers including its children's, each session once. The parent's section ends with an "N inside ›" row opening the same kind of list for its children.
- **D7, the free week's "By piece and skill"** (`WeekView`): top-level tags only, a parent's children rolled into it, each session once. "Top-level tags", not "parents", or a childless tag's time would vanish from the week. The spec's HIS-2 line says so: "with nested tags rolled into their parent" (the owner's wording, 2026-11-10).
- **Names are unique within each list** (the owner's answer to Q1): "Scales › D minor" and "Arpeggios › D minor" can both exist, and the search label tells them apart.
- **Move refuses a name clash, in both directions, with a reason.** Moving "D minor" to the top level when a top-level "D minor" exists, or into a parent that already has a child of that name, shows something like "A skill named “D minor” is already at the top level. Rename one first." and doesn't move. Two devices un-nesting at once can still make two top-level duplicates. That's accepted: both are top-level without children, so D2 lets them merge.
- **The deploy** runs from PR 1's branch before the merge, with Development reset first. **`version` stays 1.** (Q2, Q3.)
- **The Showcase seed gets a nested skill,** "Scales › D minor", so the screenshots change (Q4).
- **"Add inside" takes the name through an alert with a text field,** like Rename, from both the row and the swipe (Q5).

## 2. PR order

| # | Title | Main files | Prod / test lines | Proves |
|---|---|---|---|---|
| 1 | `feat(TAG-5): Store which piece or skill a tag sits inside, and deploy the field to CloudKit` (Tier 2) | `Core/Tag.swift` (`parentID`), `Core/TagLibrary.swift` (`setParent`, `add(name:kind:inside:)`), `Core/InMemoryTagLibrary.swift`, `Persistence/HistorySchema.swift` (`HistorySchemaV2`, one lightweight stage), `Persistence/HistoryStore.swift` (opens with V2 at line 102, and the schema initializer), `Persistence/SwiftDataTagLibrary.swift`, `App/Showcase.swift` (the nested skill), `docs/cloudkit/schema-v1-fields.txt` (+2 lines, same file name), new fixture `Fixtures/history-v2.store`, `HistoryStoreFormatTests`, `SwiftDataTagLibraryTests`, ADR 0013 to accepted | 115 / 130 | The v1 fixture still opens (the migration), the field round-trips, the snapshot lists exactly one more field under the same record type, and nothing reads it yet. **The owner deploys from this branch before it merges** (§4), and the PR says the review checklist in §4 was walked |
| 2 | `feat(TAG-5): Resolve a tag's parent, count its time toward it, and name it "Parent › child"` (core only) | `Core/Tag.swift` (`TagIndex.link(_:)`, `parent(of:)`, `children(of:)`, `counted(for:)`, `name(of:)`), `Core/PracticeWeek.swift`, `Core/TagStats.swift`, `Core/PracticeLogCSV.swift` | 120 / 270 | Every shape sync can deliver reads one level deep, the same on every device, without recursion, and a session counts once toward a parent (§3). Mutation-tested |
| 3 | `feat(HIS-4): List pieces and skills with what's inside them rolled in, and open the ones inside` | `Features/History/TagStatsView.swift`, `HistoryModel`, `WeekView` (footer only) | 80 / 60 | D6 and D7: a parent's row carries its children's time, "N inside ›" opens the children, the week lists top-level tags only |
| 4 | `feat(TAG-5): Add a piece or skill inside another, and show it as "Parent › child"` | `Features/Tags/TagPickerModel.swift`, `TagPickerView.swift`, `Core/Tag.swift` (`existing(named:kind:inside:in:)`), `Text(names:)` at the four label sites (`HistoryView`, `PracticeView`, `SessionEditorView`, `WeekView`), `Localizable.xcstrings`, `RootView` (IDs), one UI test | 265 / 220 | D3, D4's Add Inside, D5, D1 and D2: folding, the add-inside row and swipe with their alert, names unique per list, the labels, the blocked archive with its count, and merge kept to one list |
| 5 | `feat(TAG-5): Move a piece or skill inside another, or back to the top level` | new `Features/Tags/MoveTagView.swift` (shaped like `MergeTagView`), `TagPickerModel` (`moveTargets`, `canMove`, `move`, the clash check, the latent-link clear), `Localizable.xcstrings`, one UI test | 140 / 160 | D4's Move: only eligible parents are offered, a parent with children can't move, built-ins are never offered as children, a name clash refuses the move in both directions with a reason, moving the loser of a mutual nesting out clears the winner's latent link, and the sessions follow without a write |

About 720 production lines and 840 test lines in all, plus two end-to-end tests. All five are features, so the 80/20 mix is untouched.

**Pace.** Five PRs is two and a half days at two a day, and more like four with the reviews and the deploy, which needs the owner's two devices and about two hours now that step 5 has the mixed-build pairing. App Review is 2026-12-12, 33 days away, but the queue (#179) also holds #223, the MIDI-2 reconnect, the listing text and website pages, the App Store Connect steps, and the code-complete audit, whose trigger is "the last M4 feature PR merges": TAG-5 is in M4, so that trigger moves back by about a week. It fits if this starts right after #223 merges and nothing else slips. If something does:

- **PR 1 and its deploy are the only part with a deadline.** They must land before the first TestFlight build that syncs, or a later build that adds the field has to raise `version` and make every tag it touches read-only on older builds (ADR 0006). PR 1 alone is a day's work and ships nothing visible. Do it now whatever happens to the rest.
- PRs 2 to 5 need no schema work and can ship in 1.0.1 without any penalty.
- Within them, cut D6's "N inside ›" drill-down first (about 50 lines; parents' rolled-in numbers still show), then fold PR 5's Move into a single "Move to top level" action (about 50 lines less; a wrong nesting can still be undone, and the clash check is only needed in one direction).

**Order.** PR 3 comes before PR 4 so that when "Add Inside" first exists, the stats and the week already know what a parent is. D1 and D2 travel with Add Inside in PR 4, so there's never a build where a parent can be archived or merged from the screen.

## 3. Design

### The field

`TagRecord.parentID: String = ""`, empty for the top level, a plain (not encrypted) field like `mergedInto`: it holds an ID, not the user's words, so CloudKit Console can still show what synced (ADR 0006). The core's `Tag` gains `parentID: Tag.ID?`. SwiftData gets `HistorySchemaV2`, `Schema.Version(2, 0, 0)`, a copy of v1 with the one field, and one lightweight stage; the v1 fixture store opening under v2 is the migration test, and a new `history-v2.store` fixture sets `parentID` to a non-default so a change to how it's stored fails a test (ADR 0006). Nothing is renamed or removed, and the fields file keeps its name.

That schema version is SwiftData's, for the local store's migration. It's a different thing from the record field `version` (ADR 0006), which every record carries and which stays 1 (§4).

Why a field on the tag and not a link record or a list of children on the parent is in ADR 0013. The short version: one field is one write, and whichever way CloudKit merges two devices' saves, the field holds one parent and the read rules below make sense of it.

Two port changes, both in PR 1 so the storage layer is complete when the deploy freezes it: `setParent(id:to:)` with `nil` for the top level, and `add(name:kind:inside:)`, so a tag added inside another is one record and one sync export, not an add and then a move.

### Resolution: what the core reads, in `TagIndex`

The adapters stay dumb stores, as they are for merges. Every rule below is a read-time rule in the core, tested on Linux, so a record that breaks a rule, whatever wrote it, shows the same on every device and no device "fixes" another's data.

Everything starts from merges resolved as today: `t` below is the tag an ID stands for. Then one non-recursive step, `link(t)`, the tag `t`'s stored parent stands for, or `nil` when:

1. the link names a tag this device doesn't know yet (not synced): `t` shows at the top level until the parent arrives, as a merge target does today;
2. the parent resolves, through merges, to `t` itself (a parent merged into its own child);
3. the parent is of the other kind (nothing in this build writes that; a later one might).

With `link` in hand, `parent(of: t)` is decided by looking exactly one link further and no more:

4. `t` is inside `p` when `link(t) == p` and `link(p) == nil`. If `link(p)` is some third tag, `t` is at the top level. That's how one level is enforced on read: a grandchild shows at the top level until its parent is moved out, and its stored link stays, so moving the parent out puts it back inside without a write.
5. When `link(p) == t`, the two name each other: the one created first is the parent, ties broken by ID, as for opposite merges (ADR 0004), so every device agrees without coordinating.

**PR 2 must not write rule 4 as `parent(of: p) != nil`.** That recursive form doesn't terminate when three devices make a ring, T inside P, P inside G, G inside T; `link` applied once to `p` does, and the ring reads as three top-level tags. It also matters for a shape the review found: device 1 moves P, which has children, inside Q, while device 2, offline, merges Q into P. P's link now resolves to P itself, so rule 2 makes `link(P)` nil and P's children stay inside it. An earlier wording of rule 4 ("the parent has a parent of its own") would have lifted them to the top level with no Move able to bring them back, because P's own link was invisible.

The index is built from `allTags()`, which prepends the built-in skills, so a skill inside `skill.scales` resolves; built from `tags()` alone, every child of a built-in would read as top level (rule 1).

A **merged child** stands for the tag it was merged into, as today, and takes that tag's parent and label. A **parent merged away** passes its children to the kept tag through `link`; if the kept tag is itself a child, rule 4 lifts them to the top level.

**An archived parent with an unarchived child** (archived on one device while the other added a child inside it) reads as unarchived, like the kept tag of a merge cycle does today. D1's invariant, that an archived tag has nothing live inside it, then holds everywhere, and no screen needs an "archived parent" state. The user who archived it sees it come back with the child inside, which is what D1 would have told them locally. It's a read, not a write: once that child is archived too, the parent reads archived again, as it's stored.

**The latent link.** After a mutual nesting, A older, A is B's parent and B's link to A is latent. If the user then moves B out, `link(B)` is nil, `link(A)` is still B, and A jumps inside B. So Move, when it takes a tag out of a parent whose own stored link names that tag, clears that link too (PR 5): two writes, and no surprise.

Counting: `counted(for: ids)` is `tags(for:)` plus each tag's parent, each once. `TagStats.of` and `PracticeWeek.timeByTag` use it; the labels and the CSV use `tags(for:)` and `name(of:)`, so a session tagged "Scales › D minor" exports that one label, not two tags.

### Validation: what the picker writes

The model checks before it writes, as it does for merges:

- **Eligible parents** for a tag: the same kind, at the top level, not archived, not merged away, not the tag itself, built-ins included for skills. A tag with children isn't moved anywhere (it would take them to a second level); a child isn't offered as a parent.
- **Add Inside** shows on top-level tags only, built-ins included, and asks for the name in an alert like Rename's.
- **Archive (D1):** blocked while `children(of:)` has an unarchived one, with the alert naming their count and kind. Archived children don't block.
- **Merge (D2):** `mergeTargets` are the tags of the same kind in the same list (same parent, or both top-level). A tag with anything inside it, archived or not, can't be merged.
- **Rename and add:** a name is unique within its list, through `Tag.existing(named:kind:inside:in:)`, with the same case- and accent-folding as today.
- **Move and names:** a move that would put two tags of one name in the same list is refused with a reason, in both directions. Out to the top level: "A skill named “D minor” is already at the top level. Rename one first." Into a parent: "A skill named “D minor” is already inside “Arpeggios”. Rename one first." Two devices un-nesting the same name at once still make two top-level duplicates, which D2 lets them merge.
- **Move and the latent link:** moving a tag out clears its former parent's link when that link names the moved tag (above).
- Validation stays out of the adapters, so the sync shapes below are the only way a rule-breaking record can exist, and the read rules cover them.

### What each screen does

| Screen | Rule | Decision |
|---|---|---|
| Tag picker | A parent is a `DisclosureGroup`, folded unless one of its children is selected when the sheet opens; its last row is "Add inside Scales", which asks for a name in an alert like Rename's. Searching lists hits flat, children as "Scales › D minor". Tapping the parent's name toggles the parent. Swipe: Add Inside on top-level tags; Move on tags without children, refusing a name clash with a reason; Archive and Merge as D1 and D2 | D1 to D4, Q1, Q5 |
| Practice's tag line, History's rows, the editor | `Text(names:)` with `name(of:)`, so a child reads "Parent › child" and a parent reads as itself | D5 |
| CSV export | The `tags` column uses the same names, `; ` separated | D5, EXP-1 |
| Time per piece and skill (Pro) | Sections for top-level tags only, numbers from `counted`, so a parent includes its children once. A parent with practiced children ends with "N inside ›", a link to the same view filtered to those children, each with its own numbers. A child with no practice isn't counted in N, as the screen lists only what's been practiced today | D6 |
| The week's "By piece and skill" (free) | `timeByTag` lists top-level tags only, a parent's children rolled into it, each session once. The footer about a session counting toward each tag stays | D7 |
| Widget, Live Activity | Nothing: they read no tags (checked `Widgets/`) | |

### Sync shapes, and what shows

| Two devices, before syncing | After sync, everywhere | The user can |
|---|---|---|
| Each gives C a different parent | The later save wins, by field or by record as step 5 observes | Move C |
| A puts B inside it; B puts A inside it | The older is the parent (rule 5) | Move the child out, which clears the winner's latent link, then move the other in |
| C goes inside P; elsewhere D goes inside C | C inside P; D at the top level (rule 4) | Move C out to see D inside it again |
| Three devices: T inside P, P inside G, G inside T | All three at the top level (rule 4, once each) | Move any one out: the next one's link then shows |
| P, with children, is moved inside Q; elsewhere Q, with none, is merged into P | P at the top level (its link resolves to itself, rule 2), its children still inside it | Nothing needed |
| P is archived (no children then); elsewhere C is added inside P | P reads as unarchived, C inside it | Archive C; P then reads archived again, as stored |
| P (no children) is merged into Q; elsewhere C is added inside P | C inside Q, or at the top level if Q is a child | Move C |
| P is merged into its own child C | C at the top level, P's sessions count toward C | Undo the merge |
| Both devices move a "D minor" from different parents to the top level | Two top-level "D minor" skills | Merge them (D2) |
| C's parent hasn't arrived yet | C at the top level | Wait |
| A 1.0 build, which has the field but no nesting screens, archives or merges a parent | The archived-parent and merged-parent rules above | As above |

## 4. The deploy

ADR 0008's steps, with changes for a second deploy, all required:

- **When:** the last step before PR 1 goes ready, after the owner has approved the field (ADR 0013) and after the reviews, from PR 1's branch once CI is green and before the merge, so main is never ahead of Production. **No Release build of the branch on any device before step 6:** a Release build whose model has a field Production lacks can't export the tags it writes.
- Development is reset first, which wipes the owner's Debug data (accepted).

1. `HistoryStoreFormatTests` is green on the branch; `schema-v1-fields.txt` has `CD_TagRecord.CD_parentID STRING` and its `_ckAsset` line.
2. `xcrun cktool reset-schema` on Development. Then clear Debug's data on both devices, so neither re-uploads a store made before the reset. Never delete the app on a device that also runs a Release build, as the owner's iPhone does: Debug and Release are one app there, and Release keeps the real history. Launch the branch's Debug build once with `PIANISM_CLEAR_DEBUG_DATA=1`: it deletes only Debug's folder, `Application Support/Debug` (ADR 0008), and keeps the settings and the running session, which both builds share (the owner chose this over `PIANISM_RESET=1`, which clears them, 2026-11-10).
3. A Debug build from the branch, `PIANISM_INIT_CLOUDKIT_SCHEMA=1`, on device A, signed into iCloud.
4. `export-schema` of Development through `scripts/cloudkit-fields.sh` equals the fields file. The one difference from the v1 export is the new field, signed off on the PR.
5. **Two devices, all of it required** (iCloud sync row 6 of the device checklist):
   1. Device A, the branch's Debug build, syncing, seeded with `PIANISM_SHOWCASE=1`, so its "D minor" skill has `skill.scales` as its parent. The seed also starts a running session, which a Release build on the same device shares, so stop it right away in this Debug build: it's then saved to Debug's history, never the real one. Device B, the same build, shows the tag, and CloudKit Console shows its record with `CD_parentID` set. The export is unchanged.
   2. **Mixed builds:** main's build can't open the v2 store B now holds (SwiftData refuses it, or drops the column), so first launch the branch's build on B once with `PIANISM_CLEAR_DEBUG_DATA=1 PIANISM_BREAK_HISTORY=1`, which removes Debug's folder and opens no store in its place. Then device B switches to main's Debug build (schema v1, no field). B renames the tag A nested; afterwards the Console, and A, still show its parent. B adds a tag; A imports it (a record with no `CD_parentID` key, the first import of a record missing one) and shows it at the top level.
   Before 5.3, B goes back to the branch's build launched once with `PIANISM_CLEAR_DEBUG_DATA=1`, so it fetches every record afresh; otherwise its copy of the nested tag, imported without the key, reads top-level and an edit there could export an empty parent.
   3. **How saves merge,** which nothing documents and device checklist row 5 hasn't run: both devices offline, A changes a piece's composer while B renames the same piece (the controls PR 1 has), then both sync. Record whether both changes survive (CloudKit merged by field) or only the later save (by whole record). After PR 5, repeat with Move on A and Rename on B. The answer goes in ADR 0013 and changes no schema.
   After each step, take `PIANISM_CLEAR_DEBUG_DATA`, `PIANISM_BREAK_HISTORY`, `PIANISM_SHOWCASE` and `PIANISM_INIT_CLOUDKIT_SCHEMA` off the scheme again: left on, every later launch from Xcode clears Debug's data or seeds the sample tags and sessions into Development again.
6. The owner deploys in CloudKit Console. The Console's deploy diff lists exactly `CD_TagRecord.CD_parentID` and its `_ckAsset`, nothing else. Production's export is compared with Development's before it's kept as `docs/cloudkit/schema-v2.ckdb`, beside v1's. Then the PR goes ready.

### PR 1 review checklist

- The classes nested in `HistorySchemaV2` are named exactly `TagRecord` and, if copied, `SessionRecord`. CloudKit names a record type after the class (`CD_TagRecord`), so a different name is a new record type, frozen forever by the deploy.
- `HistoryStore.container()`, `HistoryStore.initializeCloudKitSchema` and the snapshot test (`HistorySchemaV2.models`, with the expected lines still reading `TagRecord.…`) all switch to V2 in the same commit. The PR says all three were checked.
- `history-v1.store` opens under V2 and keeps its rows; `history-v2.store` sets `parentID` to a non-default.
- The Showcase seed's nested skill is there, so step 5 has a record with the field set.

### `version` stays 1

Settled. The record field `version` (ADR 0006) is raised when an older app would lose a value by saving, and a 1.0 app that carries the field without using it doesn't lose it, which is why ADR 0004 shipped `mergedInto` ahead of any merge screen. The exact conditions under which a build **without** the field, which no public build will be if PR 1 lands in time, drops it: (a) the server copy is gone, say the person deleted their iCloud data, and that build re-uploads its local store, whose rows have no such column; (b) a delete and re-insert of the record, which this app never does (ADR 0006 never purges). A 1.0 build can't see parents, so it may archive or merge one; the read rules absorb that (last row of the sync table). Device row row 9, for the first update after a public build: a parent set on another device shows after updating.

If PR 1 slips past the first TestFlight build that syncs, the tag record's version becomes 2 instead, and `HistoryStore.recordVersion` splits into one constant per record type so sessions aren't made read-only for nothing.

## 5. Coverage

| Rule | Automated test | Planted bugs it must catch | Device |
|---|---|---|---|
| The field survives, v1 data opens | Persistence: v1 fixture opens under v2; v2 fixture reads `parentID` set; round-trip through `setParent` and `add(inside:)`; the snapshot's new line under `TagRecord` | Parent not written; `""` read as a parent; V2 missing `SessionRecord`; stage left out; a V2 class renamed | row 6: the exports match, the mixed-build pairing, how saves merge |
| One level (rule 4) | Core: a grandchild reads at the top level, and returns inside when its parent moves out; the three-device ring reads as three top-level tags; P moved inside Q while Q is merged into P keeps P's children | The recursive form (hangs on the ring); `link` without rules 1 to 3 on `p`; returning the middle tag | |
| Each names the other (rule 5) | Core: the older is the parent on both orderings; ties by ID | `>` for `<`; the newer wins | row 7: nested opposite ways on two devices, both show the same |
| A built-in as a parent | Core: a skill inside `skill.scales` resolves from an index built from `allTags()` | Index built from `tags()` alone | |
| Parent merged away (rule 1) | Core: the child follows to the kept tag; lifted if the kept tag is a child | Raw `parentID` without the index | |
| Parent merged into its own child (rule 2) | Core: top level, no loop | Self check missing | |
| A merged child | Core: stands for its sibling, takes its parent and label | The merged tag's own link used | |
| Other kind (rule 3), unknown parent (rule 1) | Core | A crash or force unwrap on an unknown ID | |
| Archived parent, live child | Core: reads unarchived while any child is live, and archived again once none is | Only the first child checked; archived children count; the parent stays unarchived after the last child is archived | row 8: archive on one device, add inside on the other |
| Counts once toward a parent | Core: `TagStats` and `PracticeWeek` with two children of one parent in one session, and a child and its parent both tagged | Parent counted twice; child's time missing from the parent; the child listed in the week | |
| Labels (D5) | Features: `selectedNames`; core: the CSV column | Bare child name; a parent prefixed with itself | |
| D1 archive block | Features: the alert's count and kind; archived children don't block. UI: the alert shows | Plural wrong at 1; the archive goes through anyway | |
| D2 merge | Features: targets are one list; a parent can't merge; two top-level duplicates from a double un-nesting can | A cousin offered; a parent mergeable | |
| D3 folding and search | Features: folded by default, open with a chosen child, search finds a child by its own name with the full label; the add-inside row names the parent. UI: tap the parent's name, the parent is tagged | A chosen child leaves its parent folded; search hides children | |
| D4 Add Inside, names per list | Features: eligibility; built-ins are parents, never children; "D minor" can be added inside Scales and inside Arpeggios, not twice inside one; the sessions keep their IDs. UI: add inside, then "Scales › D minor" on Practice and in History | A child offered as a parent; a second level allowed; a built-in moved; names still unique per kind | |
| Move, name clash | Features: out to the top level with a top-level namesake, and into a parent with a child namesake, both refused with their reasons; the move goes through once one is renamed; the check folds case and accents. UI: one direction's alert | Only one direction checked; the move goes through with the alert; a case-sensitive compare | |
| Move, the latent link | Features: after a mutual nesting, moving the loser out leaves the winner at the top level | Only the mover written | |
| D6 | Features: top-level sections, N counts practiced children, the link filters to them | Children listed at the top; N counts unpracticed children | |
| D7 | Core: a childless top-level tag keeps its row; children aren't listed | Children listed in the week; childless tags dropped | |
| A parent set elsewhere shows after updating | None possible before a public build | | row 9, at the first update after one |

iCloud sync rows 6 to 9 go in `docs/device-checklist.md` with their PRs. Row 6 is part of the deploy (§4, step 5), with its Move-and-Rename repeat after PR 5; row 7 and row 8 need two devices on the same account and close with PR 5; row 9 waits for the first update after a public build.

## 6. Decisions

**Settled by the owner, 2026-11-09:** everything in §1, which now includes his answers to the plan's six questions:

| # | Was | Answer |
|---|---|---|
| Q1 | Names unique per list, or per kind | Per list, and Move refuses a clash in both directions with a reason |
| Q2 | `version` stays 1 | Yes |
| Q3 | Deploy from PR 1's branch, before the merge, Development reset first | Yes |
| Q4 | A nested skill in the Showcase seed | Yes; the screenshots change |
| Q5 | How "Add inside" takes the name | An alert with a text field, like Rename |
| Q6 | TAG-5's priority and milestone | Should, M4; the spec rows are in (§7) |

**Decided in this plan, for the owner to accept with it:** the read rules of §3 (one non-recursive link, the older tag wins a loop, an archived parent with a live child reads unarchived until the child is archived, Move clears a latent link), the field's name, type and plainness, and that "N inside" counts children with practice.

**Still to ask:** nothing.

## 7. The spec

Approved by the owner and edited into the spec on 2026-11-09, by the coordinating agent, not this plan:

- A new row after TAG-4: **TAG-5, Pieces and skills inside others, Should, M4**, with this plan's draft text plus "Names are unique within each list", "A tag can be moved inside another or back to the top level, taking its sessions with it", and "A tag can't be archived while anything inside it is unarchived, and only tags in the same list can be merged".
- HIS-4's acceptance criteria: "Total and last-30-days time per piece and per skill; a parent's time includes its children's, each session once, and its children are listed inside it; played vs. bench time where MIDI data exists".
- HIS-2's acceptance criteria: "a breakdown by tag, with nested tags rolled into their parent" (approved 2026-11-10, replacing the first wording, which read as dropping childless tags).

## 8. What in the code changed the picture

- `HistoryStore.recordVersion` is one constant for sessions and tags, so a version bump for tags alone would need it split; with `version` staying 1, it doesn't.
- `HistoryStore.container()` opens with `Schema(versionedSchema: HistorySchemaV1.self)` and the migration plan, and `initializeCloudKitSchema` builds the schema the same way, so both switch to V2 with the snapshot test.
- The widget and Live Activity read no tags, and the CSV already goes through `TagIndex`, so D5 is one helper used at five sites, not five changes.
- `TagIndex` already rewrites a tag on read for merge cycles (clears `mergedInto`, unarchives), which is the precedent for rules 4 and 5 and the archived-parent rule.
- `TagStats` (#223) replaces `PieceStats` and already takes the index; D6 adds a `parent` to each stat and a filter in the view, nothing in the sums.
- `Tag.existing(named:kind:in:)` is the one place names are made unique, used by add, rename and the picker; "per list" is a parameter there, and Move's clash check reuses it.
- `HistoryStoreFormatTests.schemaIsWhatTheDeployFreezes` lists every attribute as text with its entity name, so the schema can't gain a field, or a record type, by accident, and the fields file is checked in the same test.
- Nothing in the repo says whether `NSPersistentCloudKitContainer` exports changed keys or whole records; ADR 0006 assumed whole records for the `version` rule, and device checklist row 5 was never run. Step 5 of the deploy answers it.
