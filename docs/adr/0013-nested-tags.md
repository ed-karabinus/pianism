# 13. A tag can sit inside one other tag, through one plain field read one level deep

- Status: proposed (draft for the owner, 2026-11-09, revised the same day after an independent
  review); amends [ADR 0004](0004-synced-data-model.md), [ADR 0006](0006-schema-v1-before-deploy.md)
  and [ADR 0008](0008-icloud-sync-environments-and-deploy.md)
- Date: 2026-11-09
- Plan: [plan-nested-tags.md](../plans/plan-nested-tags.md)

## Context and problem statement

The owner decided on 2026-11-09 that a piece can sit inside a piece and a skill inside a skill, one
level deep (TAG-5): "Scales › D minor", "Études, Op. 10 › No. 3". A session tagged with the child
counts toward the parent too. Built-in skills can be parents, never children. Two devices that give
a tag different parents: the last change wins. Names are unique within each list.

Tags are `TagRecord`s in the SwiftData store that CloudKit mirrors (ADR 0004). Schema v1 has been
in Production since 2026-10-21, so it can only gain fields, and a field's name, type and encryption
can never change (ADR 0006, 0008). There is no public build yet, and the owner's development data
can be wiped, but Production can't shrink, so whatever carries the link is permanent.

So: where does the link live, is it encrypted, and how is "one level" kept when two devices write
links that only make sense apart? Validation on write can't be enough: devices write offline and
sync later. And whether `NSPersistentCloudKitContainer` exports only the keys a save changed or every
attribute is undocumented; ADR 0006 assumed whole records, and the device check that would tell
(checklist row 5, "whether two edits' fields can mix") has never run.

## Considered options

Where the link lives:

1. **A `parentID` field on the child's `TagRecord`,** the parent's ID or empty, like `mergedInto`.
2. **A list of children on the parent,** a JSON array like `tagIDs`.
3. **A separate link record,** `TagLinkRecord(child, parent)`.
4. **A SwiftData relationship.**

Encryption: plain, or `.allowsCloudEncryption` like `name`.

Keeping one level:

- **A. On write only:** the picker refuses a second level; whatever sync delivers is shown as stored.
- **B. On read:** the core resolves every link to at most one level, deterministically, as it
  resolves merge chains and cycles today (ADR 0004); writes are still checked, so only sync can
  make a rule-breaking record.

## Decision

Option 1, plain, with B.

**Schema.** `TagRecord` gains `parentID: String = ""`, empty for the top level. It's the second
schema deploy; SwiftData gets `HistorySchemaV2`, `Schema.Version(2, 0, 0)`, v1 plus this field,
with one lightweight stage, and a `history-v2.store` fixture with the field set (ADR 0006's fixture
rule). That version number is SwiftData's, for migrating the local store; the record field
`version` of ADR 0006 is a different thing and stays 1 (below). The fields file,
`docs/cloudkit/schema-v1-fields.txt`, keeps its name and gains `CD_TagRecord.CD_parentID STRING` and
its `_ckAsset` line, and the Production export after the deploy is kept as
`docs/cloudkit/schema-v2.ckdb`. The classes nested in `HistorySchemaV2` are named exactly
`TagRecord` and `SessionRecord`: CloudKit names a record type after the class, so any other name
would deploy a new record type, frozen forever. The core's `Tag` gains `parentID: Tag.ID?`, and
`TagLibrary` gains `setParent(id:to:)` and `add(name:kind:inside:)`, so a tag added inside another
is one record and one export.

Why option 1: one field is one write, and it holds one parent whichever way CloudKit merges two
devices' saves. Option 2 breaks under sync: two devices each adding a child to the same parent write
two whole lists, and the later one drops the other's child. Option 3 is a third record type with
its own ID, duplicates, `deletedAt` and out-of-order arrival (a link before either tag), for a
one-to-one fact. Option 4 was rejected in ADR 0004: CloudKit makes every relationship optional, so
it adds no integrity, and it would be the first relationship in the store.

Why plain: the field holds an ID, as `mergedInto` does, not the user's words. ADR 0006 keeps IDs,
kinds and dates plain so CloudKit Console can show what synced; encryption can't be changed later
either way, and encrypting an ID protects nothing, as the names it points at are already encrypted.

**"The last change wins" is the owner's decision; how CloudKit gets there is unknown until the
deploy's step 5 observes it.** If CloudKit merges by changed keys, two devices' edits to one tag mix,
and a rename on one survives a move on the other. If it merges by whole record, the later save wins
every field, and a rename made offline after a move elsewhere quietly undoes the move; the person
moves the tag again, and nothing else is lost. The read rules below hold either way, and neither
outcome changes the schema. The observation goes into this record as an amendment.

**Resolution, in `TagIndex`, after merges.** Every ID first stands for the tag its merges lead to,
as today. Then one non-recursive step, `link(t)`: the tag `t`'s stored parent stands for, or `nil`
when:

1. the link names a tag this device doesn't know yet: `t` shows at the top level until it arrives,
   as an unsynced merge target does;
2. the parent resolves, through merges, to `t` itself;
3. the parent is of the other kind.

Then `parent(of: t)` looks one link further and no more:

4. `t` is inside `p` when `link(t) == p` and `link(p) == nil`. When `link(p)` is some third tag, `t`
   is at the top level. One level is enforced here: a grandchild shows at the top level until its
   parent is moved out, and its stored link stays, so that move puts it back inside without a write.
5. When `link(p) == t`, the two name each other: the one created first is the parent, ties broken
   by ID, as for opposite merges, so every device agrees without coordinating.

Rule 4 is deliberately not "`parent(of: p)` is nil". That recursive form doesn't terminate on a ring
three devices can make (T inside P, P inside G, G inside T), which `link` once reads as three
top-level tags. And applying rules 1 to 3 to `p` itself is what keeps a shape the review found from
sticking: P, with children, is moved inside Q on one device while Q is merged into P on another; P's
link resolves to P, rule 2 makes it nil, and P's children stay inside it, where the earlier wording
would have lifted them with no Move able to put them back. The index is built from the built-in
skills and the stored tags together, or a skill inside `skill.scales` would read as top level.

A merged child stands for the tag it was merged into and takes that tag's parent and label. A
parent merged away passes its children to the kept tag through `link`, and rule 4 lifts them if the
kept tag is itself a child. An archived parent with an unarchived child reads as unarchived, as the
kept tag of a merge cycle does: the invariant behind D1, that an archived tag has nothing live inside
it, then holds on every device, and no screen needs an "archived parent" state. It's a read, not a
write: once that child is archived too, the parent reads archived again, as it's stored.

After a mutual nesting the loser keeps a latent link to the winner, so moving the loser out would
make the winner jump inside it. Move therefore clears the former parent's link when it names the
moved tag: two writes, no surprise.

Counting is `counted(for:)`: a session's resolved tags plus their parents, each once. Labels use
`name(of:)`: "Parent › child". Nothing rewrites sessions, as with merges.

Why B over A: with A, a grandchild made by two offline devices would show as a second level on every
device, and each screen would need a rule for it anyway; with B the rule is written once, tested on
Linux with the merge rules, and the record is left as it is, so no device "repairs" another's data
and the user's intent survives for a Move to restore.

**Validation on write stays in the picker's model,** as merge validation does: eligible parents are
the same kind, top level, not archived or merged away, built-ins included for skills; a tag with
children isn't moved; a parent with live children isn't archived (D1) and a parent isn't merged
(D2); names are unique within a list, and a Move that would put two of one name in the same list is
refused with a reason, in both directions. Two devices un-nesting one name at once still make two
top-level duplicates, which D2 lets them merge. The adapters don't check, so the only rule-breaking
records are the sync shapes above.

**The deploy** follows ADR 0008, from the PR's branch once CI is green, after the owner has approved
this record and after the reviews, and before the merge, so main is never ahead of Production: a
Release build whose model has a field Production lacks can't export the tags it writes, so no
Release build of the branch goes on any device before the deploy. Development is reset first
(`cktool reset-schema`), which wipes the owner's Debug data, and the Debug app or its data is deleted
on both devices before the schema is created again. Step 5 is required: a nested tag from the
Showcase seed syncs to the second device with the field set; a device on main's build (schema v1)
renames that tag and the parent survives, and adds a tag that the new build imports without the
key; and two offline edits to one tag's different fields show how CloudKit merges saves. The
Console's deploy diff must list exactly `CD_TagRecord.CD_parentID` and its `_ckAsset`, and
Production's export must equal Development's. This amends ADR 0008's step 1 for any later deploy:
"green on the branch that deploys, before it merges".

**`version` stays 1.** The record field is raised when an older app would lose a value by saving
(ADR 0006). A 1.0 app that carries the field without using it doesn't lose it, which is why ADR 0004
shipped `mergedInto` ahead of any merge screen. A build without the field, which no public build
will be if the deploy comes before the first TestFlight build that syncs, drops it only when (a) the
server copy is gone, say the person deleted their iCloud data, and that build re-uploads a local
store whose rows have no such column, or (b) a record is deleted and inserted again, which this app
never does (ADR 0006). A 1.0 build can't see parents, so it may archive or merge one; the read rules
absorb that. If the field lands after that build instead, the tag record's version becomes 2, and
`HistoryStore.recordVersion` splits into one constant per record type, so sessions aren't made
read-only on older builds for a change to tags.

## Consequences

- Good: one field, deployed once, carries the whole feature; the rest is core rules and screens, with
  no further schema work for Move, archive, merge or the stats.
- Good: every sync shape (opposite nestings, a ring, a grandchild, a parent archived, merged or moved
  elsewhere, an unsynced parent) shows the same on every device, with the user's stored intent kept,
  and the resolution can't loop.
- Good: sessions are never rewritten; a Move changes one record, two after a mutual nesting, and the
  counts follow.
- Bad: a second irreversible deploy, about two hours of the owner's time with two devices, and the
  Debug data reset.
- Bad: a grandchild, the loser of a loop or every tag of a ring appears at the top level with no
  explanation on screen. The cases need two or three devices offline at once; a Move fixes each in
  one or two steps.
- Bad: until step 5 runs, nobody knows whether a rename on one device can undo a move on another.
  If it can, the cost is one repeated Move, and this record says so.
- Bad: `HistorySchemaV2` copies `SessionRecord` unchanged (about 70 lines) unless SwiftData accepts
  v1's class in v2's model list, which PR 1 tries first; either way the nested class keeps its name.
- Bad: an older build, should one exist when the field lands, makes a child top-level by saving it,
  which is what the `version` rule guards against; hence the deadline on PR 1.
- To verify on devices (device checklist, with the PRs): the deploy's step 5 (N1), repeated with
  Move and Rename once PR 5 exists; two devices nesting opposite ways agree (N2); a parent archived
  on one device while the other adds a child inside comes back on both, and goes again when the
  child is archived (N3); after the first update that follows a public build, a parent set on
  another device shows (N4).
