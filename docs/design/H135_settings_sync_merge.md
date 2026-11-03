# H135: settings cloud sync deletes keys a stale device lacks

## 1. What the code does today

Verified at hopnbop `602a5bfd` unless a line says inferred.
The bug is live in 0.57.0. `project.godot:18` says so.

Settings live in two Nakama storage rows per account. The
`global` row holds `locale` and the four keys in
`LocalSettings.GLOBAL_OVERRIDABLE_KEYS`. The
`game/{game_id}` row holds the other nine keys in
`LocalSettings.OVERRIDABLE_KEYS`. The split and the legacy
one-shot migration from the old `user` row are at the top
of `src/core/settings_cloud_sync.gd:3-14`. There are 13
overridable keys in `src/core/local_settings.gd:40-54`.

Saves replace a whole row. `save_to_cloud()` at
`settings_cloud_sync.gd:56-65` sends both scopes at once.
Each serializer, `_serialize_global()` at `:264-280` and
`_serialize_per_game()` at `:283-296`, sends every local
override it finds, plus a `_key_times` map holding the
change time of each override it sends. Nothing else goes.
A key this device has no override for is simply not in
the blob, whatever other devices did.

Fetches happen once per sign-in. The only fetch call site
is `src/core/global.gd:381`, and the only save call site
is closing the settings panel at
`src/ui/settings_panel/side_panel_manager.gd:101`.
`fetch_and_merge_from_cloud()` at
`settings_cloud_sync.gd:71-90` first pushes any scope a
failed save left dirty (`:80-82`), then fetches. The two
requests are independent. Which one lands first is not
controlled (inferred).

The merge in `_apply_scope()` at `:299-359` is per key
for values. A cloud key applies unless this device holds
a newer change time for it (`:321-335`). The loss is in
the block at `:339-358`. When a fetched row carries
`_key_times` and the row `update_time` is newer than
this device's change time for a key, a key the row does
not carry is read as cleared on another device.
`clear_override()` runs for it. Absence means deletion.

The loss, step by step, with one account and two devices
that both run this client:

1. Device A signs in at 9:00 and fetches both rows.
2. At 9:30 the player changes a setting on device B. B
   saves its row with the new key and its 9:30 time.
3. At 10:00 the player opens and closes settings on A.
   A is still running its 9:00 session, so A's save has
   no trace of B's key. The cloud row loses the key and
   gains a 10:00 `update_time`.
4. At B's next sign-in, B fetches that row. The key is
   absent, the row is newer than B's 9:30 change, and
   `:354-358` clears the override on B.
5. B's next save writes a row without the key. The
   setting is now gone on every device, and no device
   ever showed an error.

Three more paths reach the same end. A dirty push at
sign-in (`:80-82`) can write A's stale blob over B's row
before A's own fetch runs. An override set before change
times existed has time 0 (`local_settings.gd:145-149`),
so the first timed row a device sees clears every local
override that row lacks. The deletion test at `:354`
compares the server row time with this device's clock,
so clock skew moves the cutoff (inferred from the two
time sources).

`locale` is worse off than the 13 keys. It rides in the
global row with no change time at all
(`settings_cloud_sync.gd:273-275`), and choosing the
default `en` removes it from the blob. It has no
timestamp to merge on and no way to say it was reset.

## 2. The storage contract

Verified in `third_party/snoringcat-platform/` and in
the client addon copy at
`addons/snoringcat_platform_client/`. Both are read only
for this item.

The addon writes Nakama storage objects in collection
`settings`, under the scope as the key, with read and
write permission 1, so a row is owner only
(`settings_api_client.gd:55-64`). A write replaces the
object value. The runtime gate in
`runtime/storage_allowlist.go:83-102` allows only the
`settings` collection, only the keys `global`,
`game/unknown` and `game/{registered game id}` (`:104-119`),
at most 16 objects per request and 32 KiB per value.
Settings blobs hold at most 13 keys plus their times, so
the cap is not near (verified by counting the keys).

A write can carry a version precondition, but this code
never does. `save()` builds its object with an empty
version string (`settings_api_client.gd:62-64`), which
the Nakama API treats as unconditional. The Godot Nakama
API documents the write version as one of an empty
string, `*` or a version hash
(`addons/nakama/api/NakamaAPI.gd:3511`), and a read
object exposes its version hash. The settings addon
throws both halves away. `fetch()` reads value and
`update_time` only (`settings_api_client.gd:36-52`), and
`settings_received` carries no version. `save()` also
returns no version, so even a conditional writer could
not chain its next write without reading again.

What a failed conditional write returns is not recorded
anywhere in this repo (open check, below). The addon's
`request_failed(scope, error)` carries a described
exception with a status (`settings_api_client.gd:82-85`),
and hopnbop sorts save failures into permanent and
retryable by substring at
`settings_cloud_sync.gd:128-134`. One of those
substrings, `exceeds`, matches no message the runtime
sends. The runtime texts are at
`runtime/storage_allowlist.go:91-99`.

### Before deciding

One check must run before the concurrency option below
can be chosen, and only a local stack can run it. No
production request is needed or allowed.

- Against a local Nakama, read a settings row, note its
  version hash, change the row, then write with the old
  hash. Record the exception status and message the
  addon surfaces, whether `settings_saved` stays unsent,
  and what `*` and an empty version each do. The
  implementer runs this, in the compliance stack or a
  small GUT case against the fake in section 6. Until
  then, every claim about the conflict response in this
  doc is inferred.

## 3. Options

### 3.1 Per-key merge with a timestamp per key and tombstones

Keep whole-row saves. Change what a save says and what
absence means. The serializer writes `_key_times` for
every key this device has a recorded time for, set or
cleared, and a `_tombstones` map naming each cleared key
and when it was cleared. `clear_override()` and a reset
to default already stamp a time
(`local_settings.gd:159-162` and `:210-215`), so the
data exists. The merge then has three rules. A present
key applies when its cloud time is newer. An absent key
with a tombstone applies as a clear when the tombstone
time is newer. An absent key with no tombstone was
never known to the writer, so it stays. The row-time
rule at `:339-358` goes away, and a cloud time of 0
counts as older than any recorded local time.

Effect on the bug: fixed between clients that write
tombstones. In the scenario above, A's 10:00 save lists
times only for keys A knows. B's key is absent with no
tombstone, so B keeps it, and B's next save puts it back
in the row. A real reset still travels, by tombstone.

Cost: one hopnbop file, plus `locale`. Locale needs a
stored change time of its own before it can tombstone.
The weakness stays that a stale save still overwrites
the row itself. A third device that installs fresh
between A's save and B's next save reads a row without
B's key and starts at defaults for it. The value is not
lost, but it is missing until a device that holds it
saves again.

### 3.2 Optimistic concurrency on the stored version, with retry-merge

Have the addon surface the version it already reads.
`fetch` emits it, `save` accepts an expected version and
passes it to Nakama instead of the empty string
(`settings_api_client.gd:62-64`). Hopnbop remembers the
version per scope. A save sends the version its merge
was based on. If another device saved first, Nakama
rejects the write (inferred; see the open check). The
client then fetches, merges per key, and saves the
merged blob against the fresh version, a bounded number
of times.

Effect on the bug: the stale write never lands, so the
row never loses B's key, and a fresh third device reads
the right row throughout. On its own it does not settle
intent. If A cleared a key on purpose and the retry
merge just unions both blobs, the fetched row puts the
key back. Timestamps still decide each key, so this
option wants section 3.1's times even without its
tombstones.

Cost: the most moving parts. The addon lives in the
platform repo, so that change lands there first and
hopnbop bumps its copy. The client needs a distinct
conflict signal, because today one `request_failed`
serves both fetches and saves (H90-2). A save can also
happen long after the fetch that set the version, at
settings panel close, so conflicts will be common
enough that the retry has to be quiet and bounded.

### 3.3 Both together

Tombstones decide what each key means. The version
precondition stops a stale writer from replacing the
row before the merge can run. Each covers the other's
hole. Tombstones alone leave the row itself wrong for a
while. Concurrency alone cannot tell a reset from a
stale omission once two blobs meet.

Cost: both costs above, in one client release. No
runtime change and no new storage key (section 4).

### 3.4 Never delete remotely

Delete the block at `settings_cloud_sync.gd:339-358`.
Absence means unknown, always. Values still merge per
key by time.

Effect on the bug: fixed, with the smallest change
there is. No stale save can clear anything anywhere.

Cost: a reset stops being a sync event. A player who
turns a setting back to its default on one device keeps
the old value on every other device until they reset it
there too. Whether that is a defect or the right
behavior is a product call, which is why it is a
question in section 7 and not a footnote here. This is
also the safe fallback if the section 2 check fails.

## 4. Coexistence with released 0.57.0 clients

Released clients keep writing whole blobs and keep
reading absence with `_key_times` as deletion. Nothing
shipped later changes what 0.57.0 does with a row.

An old client's save drops every field it does not
write. Its serializers rebuild the blob from local
overrides only, so a `_tombstones` map, a format marker,
and any setting key a future client adds all vanish
from the row on its next save. Its own merge then treats
the next timed row it fetches as authority to clear
local keys the row lacks. Old clients keep the bug
among themselves until they upgrade. No format change
on our side can fix a client already shipped.

A new client reading an old client's row is safe under
every option above, as long as one rule holds without
exception: deletion travels only in an explicit
tombstone, never in absence, whatever else the row
carries. An old row has no tombstones, so it deletes
nothing. An old save that overwrites a new row removes
the tombstones and any new keys from storage, but new
devices that hold those keys keep them locally and put
them back on their next save. A fresh install in that
window starts at defaults for the missing keys.

That is why the format stays in the same rows. A new
storage key buys a clean break and charges for it. The
allowlist accepts only `global` and
`game/{registered id}` (`storage_allowlist.go:104-119`),
so a `global_v2` key is rejected until the runtime
allowlist changes and deploys, and a dual-key client
then has to read both rows and decide which wins while
old clients keep writing the old one. An in-blob
`_format` marker costs nothing, needs no allowlist
change, and old clients ignore it on read and drop it
on save, which the absence rule already survives. Add
the marker so a future reader can tell a tombstone-era
row from an older one at a glance. Do not gate behavior
on it.

Release order follows from that. Ship the new client
first, against the rows that exist. No server deploy,
no row migration, no flag day. If the concurrency half
is in, the platform addon change lands in the platform
repo first and hopnbop bumps the copied addon before
the client release, and it still needs no runtime
deploy, because the version check is Nakama's own
(inferred until the section 2 check runs). Players who
stay on 0.57.0 keep the old behavior on their devices
and keep overwriting the shared row. New devices on the
same account are protected locally from the moment they
upgrade, and the row heals on their next save.

## 5. Recommendation

Build both halves of section 3.3 in one client release,
in this order inside the work. First the tombstone
merge and the absence rule, which fix the loss on their
own. Then the version precondition with a bounded
retry-merge, gated on the section 2 check. If that
check shows a conflict cannot be told apart from other
failures, ship the tombstone half alone and file the
concurrency half as its own item. Section 3.4 is the
fallback if Levi answers the reset question with no.

Fold-ins, each with its reason:

- H90-2, yes, as a prerequisite. One `request_failed`
  cannot drive both a fetch merge and a save retry, and
  the concurrency retry needs to know a save failed, and
  why. Give saves their own failure route in the addon,
  or track pending saves apart from pending fetches on
  the hopnbop side.
- H90-3, yes. A tombstone that clears an override
  through `clear_override()` at
  `local_settings.gd:210-215` leaves the live `Settings`
  value and its signal untouched, so a propagated reset
  would apply only after a restart. A reset that syncs
  has to take effect when it arrives. Route the clear
  through the same live update as `set_override()`.
- H90-4, in part. Untimed keys, yes: a cloud time of 0
  must count as older than any local time, or old values
  keep winning with fresh stamps. The dead `exceeds`
  substring, yes, while the failure routing is open:
  match the status alone. The test path, yes, as part of
  section 6. The per-device dirty flag, no: local
  settings are device-wide already, so the harm is one
  account's settings saving under another after a switch
  mid-retry. Note it as a follow-up instead of widening
  this fix. The backslash continuation at
  `settings_cloud_sync.gd:354-355` goes away with the
  block it sits in.

## 6. How it would be tested

The merge needs two simulated devices and a fake store,
none of which the current tests have. Today's
`test/unit/platform/test_settings_cloud_sync.gd` reaches
the real `user://local_settings.cfg` through
`save_settings()` (H90-4), so the first step is a test
path on `LocalSettings`: a path a test can point at a
throwaway file, with the production default unchanged.
Each simulated device then gets its own `LocalSettings`
over its own file, and its own `SettingsCloudSync`. The
test swaps `G.local_settings` between device turns, as
`test/unit/platform/test_settings_echo.gd` already does,
and drives change times by setting override times
directly instead of waiting on a clock.

The fake store stands in for `Platform.settings`. It
holds one blob and one version per scope, emits the
addon's three signals, applies a write only when the
expected version matches, and can fail a chosen call.
That one fake covers the unit matrix:

- The section 1 scenario. B's key survives A's stale
  save, and survives B's next sign-in.
- A tombstone newer than the local change clears the
  key here, live, without a restart (H90-3). An older
  tombstone does not.
- A key absent with no tombstone is kept, from a
  tombstone-era row and from a 0.57.0-shaped row alike.
- A pre-H90 override at time 0 is kept.
- A conditional save against a stale version fails,
  fetches, merges and lands, with both devices' keys in
  the final row. A retry that keeps conflicting stops at
  its bound and keeps local settings.
- A save that fails while its fetch is in flight is
  taken for a save failure, and the fetch still merges
  (H90-2).
- A dirty scope at sign-in is pushed after the fetch
  merges, not before.
- An old client's save over a new row removes the
  tombstones from storage and deletes nothing on a new
  device.
- The locale cases, if Levi says a reset must travel:
  a language change syncs, and a reset to English
  syncs as a tombstone instead of vanishing.

The section 2 check becomes a compliance case against
the local Nakama stack, so the real conflict response
is pinned before the retry depends on it. The existing
compliance settings case keeps passing. No agent
harness run is needed: nothing here is visible except
the settings panel keeping values it already shows.

## 7. Size and the questions for Levi

Size: M. The tombstone half is one file and its tests.
The concurrency half is a small addon change, its
hopnbop wiring, and the fake store the tests need.

Ship the tombstone merge and the version precondition
together in the next client release?

Must resetting a setting to its default on one device
reset it on the player's other devices too?

If a reset must travel, must resetting the language to
English on one device also reset it on the others?
