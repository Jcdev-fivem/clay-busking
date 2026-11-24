# clay-busking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `clay-busking` FiveM/QBox resource (in-memory server-authoritative busking spots, `ox_inventory` reusable `busking_hat` item, client `lib.points` prop/HUD/interaction loop, and Svelte 5 NUI matching `xCore Busking`).

**Architecture:** Server holds active busking spots in memory with per-player and per-spot locks, validates all money/distance rules via pure functions in `shared/rules.lua`, and broadcasts lean snapshots (`total` + `top3` only) to clients. Clients stream local hat props and right-side HUD visibility through `lib.points` and drive a Svelte 5 + Vite NUI (`nui-src/` compiled to `ui/`). Lifecycle hooks (`OnPlayerUnload`, `playerDropped`, `onResourceStop`, and a 2-second server watchdog) guarantee payout with `'bank'` fallback whenever a player is already offline.

**Tech Stack:** Lua 5.4 (`qbx_core`, `ox_lib`, `ox_inventory`), Svelte 5 + Vite 8 (`@fontsource/kanit`, `@fontsource/chakra-petch`), Lua 5.4 CLI (`lua`, `luac`) and Node.js (`node --test`, `npm.cmd`) for automated tests and build.

**Spec:** `docs/superpowers/specs/2026-11-24-clay-busking-design.md`

## Global Constraints

- Resource path is `c:\Users\ClayStudio\Desktop\Fivem Server Project\qbox\resources\[clay]\clay-busking` (auto-loaded via `ensure [clay]` in `qbox\server.cfg`; folder is not a git repository, so skip git commits).
- Dependencies in `fxmanifest.lua`: `ox_lib`, `ox_inventory`, `qbx_core` only; zero `oxmysql` or database tables.
- Lua 5.4 (`lua54 'yes'`), `fx_version 'cerulean'`, `game 'gta5'`, `ui_page 'ui/index.html'`.
- Item `busking_hat` uses `consume = 0` (never removed from bag on placement); max `1` active spot per `citizenid`; minimum `6.0`m spacing between spots.
- Online payout goes to `Config.Account` (`'cash'`); offline fallback (when `qbx_core:GetPlayer(ownerSrc)` is `nil`) MUST go to `Config.OfflineFallbackAccount` (`'bank'`) so `ox_inventory` `server.syncInventory` never overwrites cash on next login.
- Owners cannot tip their own hat; Top 3 tie-breaking preserves the donor who tipped first (`order` ascending).
- `Config.Show3DText = false` and `Config.ShowZoneMarker = false` by default; 0.00ms client idle when no spot is within `60.0`m.
- On Windows PowerShell, invoke npm as `npm.cmd` (system execution policy blocks `npm.ps1`).
- UI copy uses the Thai strings fixed in spec section 9 (`Clay Busking`, `รายได้ทั้งหมด`, `กรุณาใส่จำนวนเงินที่ต้องการ`, `Close`, `Confirm`, `รับเงิน`) and `•••` when `top3` is empty.

## Review Focus

- **Whole floats from NUI JSON (`100.0` vs `100.5`)**: FiveM's NUI/msgpack bridge can pass JS integers as Lua floats (`100.0`); `Rules.validateAmount` must coerce exact whole floats to integer while rejecting fractional floats (`10.5`), `NaN`, `inf`, strings, `0`, negatives, and out-of-range amounts (pinned in Task 1).
- **Concurrent `tip` vs `collect` / double-collect**: `collect` must acquire the spot lock and set `spots[spotId] = nil` before calling `AddMoney` so a second `collect` or racing `tip` returns `not_found` without double-paying or deducting tipper cash (pinned in Task 2).
- **Online `OnPlayerUnload` followed by `playerDropped` (and abrupt `playerDropped` alone)**: Normal logout pays `'cash'` once and clears the spot so the subsequent `playerDropped` is a no-op; abrupt disconnect with `GetPlayer(ownerSrc) == nil` pays `'bank'` once with reason `'clay-busking-offline'` (pinned in Task 2).
- **Overlapping `HudRadius` (10m) between two spots spaced 6m apart**: Client must display the closest spot within `HudRadius` and seamlessly fall back to the other spot when walking out of or closing the closer one instead of blanking the HUD (pinned in Task 3).
- **Spot closing while `TipModal` is open & malformed NUI input**: Receiving `removeSpot` for `openSpotId` must release `SetNuiFocus(false, false)` and close the modal immediately; NUI `parseTipInput` must reject empty, non-digit, decimal, zero, and out-of-bounds input locally before sending RPC (pinned in Task 3 and Task 4).

---

## File Map

| File | Responsibility |
|---|---|
| `fxmanifest.lua` | Resource metadata, dependencies, load order, `ui_page` and `ui/**/*` |
| `config.lua` | All tunable constants, optional visual flags, and UI copy |
| `shared/rules.lua` | Pure validation, spacing check, donor accumulation, Top 3 sorting, full name helper |
| `server/selfcheck.lua` | In-server debug assertions for `shared/rules.lua` when `Config.Debug` is true |
| `server/main.lua` | In-memory spot registry, locks, `lib.callback` handlers, `ownerLeft`, watchdog, payout lifecycle |
| `client/main.lua` | `useBuskingHat` export, `lib.points` prop/HUD/`[E]` handling, animations/sound, owner walk-away monitor, NUI bridge |
| `../../[ox]/ox_inventory/data/items.lua` | Register `busking_hat` usable item pointing at `clay-busking.useBuskingHat` |
| `nui-src/` -> `ui/` | Svelte 5 + Vite NUI (`HudCard.svelte`, `TipModal.svelte`, `CollectModal.svelte`, `format.js`, `nui.js`, `preview.js`) |
| `tests/rules_test.lua`, `tests/server_test.lua`, `tests/client_test.lua`, `nui-src/tests/format.test.mjs` | Automated CLI test suites for pure rules, server state/money/lifecycle, client spatial/NUI bridge, and NUI parsing/formatting |

---

### Task 1: Manifest, Config, Pure Rules & Selfcheck

**Files:**
- Create: `fxmanifest.lua`
- Create: `config.lua`
- Create: `shared/rules.lua`
- Create: `server/selfcheck.lua`
- Test: `tests/rules_test.lua`

**Interfaces:**
- Consumes: none
- Produces:
  - Global `Config` table matching spec section 9
  - Global `BuskingRules` table:
    - `BuskingRules.validateAmount(raw: any, minAmount: integer, maxAmount: integer) -> integer?`
    - `BuskingRules.isTooClose(coords: { x: number, y: number, z: number }, spots: table<string, { coords: { x: number, y: number, z: number } }>, minSpacing: number) -> boolean`
    - `BuskingRules.computeTop3(donors: table<string, { name: string, amount: integer, order: integer }>) -> { name: string, amount: integer }[]`
    - `BuskingRules.applyTip(spot: { total: integer, donorSeq: integer, donors: table, top3: table }, cid: string, name: string, amount: integer) -> integer, table`
    - `BuskingRules.fullName(charinfo: table?, fallback: string?) -> string`

- [ ] **Step 1: Write failing unit tests in `tests/rules_test.lua`**

Create `tests/rules_test.lua` that loads `config.lua` and `shared/rules.lua` via `dofile` and asserts:

```lua
dofile('config.lua')
dofile('shared/rules.lua')

local R = BuskingRules
local function eq(a, b, msg)
    assert(a == b, ('%s: expected %s, got %s'):format(msg, tostring(b), tostring(a)))
end

-- validateAmount: bounds, whole floats from NUI JSON, malformed types
eq(R.validateAmount(1, 1, 100000), 1, 'min edge')
eq(R.validateAmount(100000, 1, 100000), 100000, 'max edge')
eq(R.validateAmount(100.0, 1, 100000), 100, 'whole float coerced to integer')
eq(math.type(R.validateAmount(100.0, 1, 100000)), 'integer', 'coerced math.type is integer')
eq(R.validateAmount(0, 1, 100000), nil, 'reject 0')
eq(R.validateAmount(-50, 1, 100000), nil, 'reject negative')
eq(R.validateAmount(100001, 1, 100000), nil, 'reject over max')
eq(R.validateAmount(10.5, 1, 100000), nil, 'reject decimal')
eq(R.validateAmount('100', 1, 100000), nil, 'reject string')
eq(R.validateAmount(0 / 0, 1, 100000), nil, 'reject NaN')
eq(R.validateAmount(math.huge, 1, 100000), nil, 'reject inf')
eq(R.validateAmount(nil, 1, 100000), nil, 'reject nil')

-- isTooClose: 3D spacing boundary
local existing = { busk_1 = { coords = { x = 10.0, y = 20.0, z = 30.0 } } }
eq(R.isTooClose({ x = 15.9, y = 20.0, z = 30.0 }, existing, 6.0), true, 'inside spacing')
eq(R.isTooClose({ x = 16.0, y = 20.0, z = 30.0 }, existing, 6.0), false, 'exact boundary allowed')
eq(R.isTooClose({ x = 10.0, y = 20.0, z = 37.0 }, existing, 6.0), false, 'vertical separation respected')

-- applyTip + computeTop3: accumulation, tie-break by earliest order, #4 overtaking #1
local spot = { total = 0, donorSeq = 0, donors = {}, top3 = {} }
R.applyTip(spot, 'A', 'PlayerA', 1000)
R.applyTip(spot, 'A', 'PlayerA', 1000)
R.applyTip(spot, 'B', 'PlayerB', 500)
R.applyTip(spot, 'C', 'PlayerC', 500)
eq(spot.total, 3000, 'total after A,A,B,C')
eq(#spot.top3, 3, 'top3 length')
eq(spot.top3[1].name, 'PlayerA', 'rank 1 A')
eq(spot.top3[1].amount, 2000, 'rank 1 amount')
eq(spot.top3[2].name, 'PlayerB', 'tie-break keeps earlier donor B above C')
eq(spot.top3[3].name, 'PlayerC', 'rank 3 C')

R.applyTip(spot, 'D', 'PlayerD', 360)
eq(spot.total, 3360, 'D counted in total')
eq(spot.top3[3].name, 'PlayerC', 'D not yet in top3')

R.applyTip(spot, 'D', 'PlayerD', 2000)
eq(spot.total, 5360, 'total after D overtakes')
eq(spot.top3[1].name, 'PlayerD', 'D overtakes to rank 1')
eq(spot.top3[1].amount, 2360, 'D cumulative amount')
eq(spot.top3[2].name, 'PlayerA', 'A shifts to rank 2')
eq(spot.top3[3].name, 'PlayerB', 'B shifts to rank 3')

-- fullName
eq(R.fullName({ firstname = '  Somchai ', lastname = ' Jai  ' }, 'Fallback'), 'Somchai Jai', 'trimmed full name')
eq(R.fullName({ firstname = 'Somchai' }, 'Fallback'), 'Somchai', 'first name only')
eq(R.fullName({}, 'Fallback'), 'Fallback', 'fallback when empty')
eq(R.fullName(nil, 'Fallback'), 'Fallback', 'fallback when nil')

print('rules_test OK')
```

- [ ] **Step 2: Run `tests/rules_test.lua` to verify it fails**

Run (from `clay-busking` directory): `lua tests/rules_test.lua`
Expected: FAIL (`cannot open config.lua: No such file or directory`).

- [ ] **Step 3: Create `fxmanifest.lua`, `config.lua`, `shared/rules.lua`, and `server/selfcheck.lua`**

- `fxmanifest.lua`: `fx_version 'cerulean'`, `game 'gta5'`, `lua54 'yes'`, `dependencies { 'ox_lib', 'ox_inventory', 'qbx_core' }`, `shared_scripts { '@ox_lib/init.lua', 'config.lua', 'shared/rules.lua' }`, `client_scripts { 'client/main.lua' }`, `server_scripts { 'server/selfcheck.lua', 'server/main.lua' }`, `ui_page 'ui/index.html'`, `files { 'ui/index.html', 'ui/**/*' }`.
- `config.lua`: Exact `Config` table from spec section 9 (`ItemName = 'busking_hat'`, `PropModel = 'prop_ld_hat_01'`, `Account = 'cash'`, `OfflineFallbackAccount = 'bank'`, `MaxSpotsPerPlayer = 1`, `MinSpotSpacing = 6.0`, `PlaceDistance = 1.0`, `PlaceDurationMs = 1000`, `PropSpawnDistance = 60.0`, `HudRadius = 10.0`, `InteractDistance = 2.2`, `AutoEndRadius = 14.0`, `ServerWatchdogMs = 2000`, `MinTip = 1`, `MaxTip = 100000`, `Show3DText = false`, `ShowZoneMarker = false`, `Ui` copy table).
- `shared/rules.lua`: Implement `BuskingRules` pure functions matching the interface above. In `validateAmount`, check `type(raw) == 'number'`, reject `raw ~= raw` (NaN) and `math.abs(raw) == math.huge`, require `math.floor(raw) == raw`, convert with `math.tointeger(raw)`, and check `minAmount <= n and n <= maxAmount`. In `applyTip`, preserve existing `donor.order` on repeat tips (increment `spot.donorSeq` only on first tip by `cid`), update `donor.name` to latest name, accumulate `amount`, increment `spot.total`, recompute `spot.top3`, and return `spot.total, spot.top3`.
- `server/selfcheck.lua`: Guard with `if not Config.Debug then return end`; run core assertions on `BuskingRules.validateAmount`, `isTooClose`, `applyTip`, `fullName` and print `^2[clay-busking] selfcheck ok^7`.

- [ ] **Step 4: Run tests and syntax check**

Run:
```powershell
lua tests/rules_test.lua
luac -p fxmanifest.lua config.lua shared/rules.lua server/selfcheck.lua
```
Expected: `rules_test OK` and exit code `0` from `luac -p`.

---

### Task 2: Authoritative Server State, Money Safety & Lifecycle Watchdog

**Files:**
- Create: `server/main.lua`
- Test: `tests/server_test.lua`

**Interfaces:**
- Consumes: `Config`, `BuskingRules.*`, `lib.callback.register`, `lib.print.error`, `exports.ox_inventory:GetItemCount(src, item)`, `exports.qbx_core:GetPlayer(src)`, `exports.qbx_core:RemoveMoney(src, account, amount, reason)`, `exports.qbx_core:AddMoney(idOrCid, account, amount, reason)`, `exports.qbx_core:Notify(src, msg, type)`
- Produces:
  - `lib.callback`:
    - `clay-busking:getAll() -> Snapshot[]`
    - `clay-busking:start(src, coords, heading) -> { ok: boolean, spot?: Snapshot, reason?: string, message?: string }`
    - `clay-busking:tip(src, spotId, amount) -> { ok: boolean, spot?: Snapshot, reason?: string, message?: string }`
    - `clay-busking:collect(src, spotId) -> { ok: boolean, total?: integer, reason?: string, message?: string }`
  - `RegisterNetEvent('clay-busking:ownerLeft', function(spotId) ... end)`
  - Broadcast events:
    - `TriggerClientEvent('clay-busking:syncSpot', -1, snapshot)` where `snapshot = { id, ownerCid, coords, heading, total, top3 }`
    - `TriggerClientEvent('clay-busking:removeSpot', -1, spotId)`
  - Lifecycle handlers: `QBCore:Server:OnPlayerUnload`, `playerDropped`, `onResourceStop`
  - Periodic watchdog thread checking `Config.AutoEndRadius + 2.0` and owner alive/missing every `Config.ServerWatchdogMs` (only iterates when `next(spots) ~= nil`).

- [ ] **Step 1: Write failing server harness tests in `tests/server_test.lua`**

Create `tests/server_test.lua` that mocks FiveM globals (`GetPlayerPed`, `GetEntityCoords`, `GetVehiclePedIsIn`, `GetEntityHealth`, `GetPlayerName`, `GetCurrentResourceName`, `TriggerClientEvent`, `RegisterNetEvent`, `AddEventHandler`, `CreateThread`, `Wait`, `vector3`), `lib`, `exports.qbx_core`, and `exports.ox_inventory`, loads `config.lua`, `shared/rules.lua`, `server/main.lua`, and verifies:

1. `start` rejects missing `busking_hat` item, in-vehicle, dead (`metadata.isdead`), placement coords `> 4.0`m away, duplicate active spot for same `citizenid`, and placement `< Config.MinSpotSpacing` from an existing spot.
2. `start` succeeds with `busking_hat >= 1`, does **not** remove the item, returns snapshot with `total = 0, top3 = {}`, and emits `clay-busking:syncSpot`.
3. `tip` rejects self-tip (`ownerCid == tipperCid`), out-of-range (`> InteractDistance + 2.0`), invalid amount (`0`, `-5`, `10.5`), and insufficient cash; on valid tip (including whole float `500.0`), calls `RemoveMoney(src, 'cash', 500, 'clay-busking-tip')`, updates `total`/`top3` using server `charinfo` full name, and emits `clay-busking:syncSpot` (snapshot must NOT contain raw `donors` map).
4. `collect` rejects non-owner and out-of-range; on owner collect with `total = 1500`, removes spot **before** `AddMoney` (verified by re-entering `collect` and `tip` inside the mocked `AddMoney` hook — both must fail with `reason = 'not_found'` and never remove tipper cash or double-pay!), emits `clay-busking:removeSpot`, pays `'cash'` with reason `'clay-busking-collect'`, and notifies owner.
5. `collect` with `total = 0` closes spot cleanly without calling `AddMoney`.
6. `ownerLeft` rejects spoofed call while owner is still within `AutoEndRadius` and alive; closes and pays `'cash'` (`'clay-busking-auto'`) once owner exceeds `AutoEndRadius` or dies.
7. `QBCore:Server:OnPlayerUnload` closes spot and pays online `'cash'` (`'clay-busking-auto'`); subsequent `playerDropped` for same `src` is a no-op (zero double payout).
8. Abrupt `playerDropped` when `GetPlayer(ownerSrc)` is already `nil` closes spot and calls `AddMoney(ownerCid, 'bank', total, 'clay-busking-offline')`.
9. `onResourceStop` for current resource pays every remaining active spot (online -> `'cash'`, offline -> `'bank'`) and ignores other resource names.
10. Server watchdog step (exposed via local captured `CreateThread` fn or test tick) auto-ends a spot when owner ped coords exceed `Config.AutoEndRadius + 2.0` or `GetEntityHealth(ped) <= 0`.

- [ ] **Step 2: Run `tests/server_test.lua` to verify it fails**

Run: `lua tests/server_test.lua`
Expected: FAIL (`cannot open server/main.lua: No such file or directory`).

- [ ] **Step 3: Implement `server/main.lua`**

Key design points to implement cleanly:
- Maintain `spots = {}`, `playerBusy = {}`, `spotBusy = {}`, `spotSeq = 0`.
- Helper `withPlayerLock(src, fn)` and `withSpotLock(spotId, fn)` using `pcall` so locks always release on error; clear `playerBusy[src]` on `playerDropped`.
- Helper `closeAndPayout(spotId, reasonTag, notifyMode)`:
  1. Look up `spot = spots[spotId]`; if nil return `nil`.
  2. Immediately set `spots[spotId] = nil` (atomic close before any yield).
  3. `TriggerClientEvent('clay-busking:removeSpot', -1, spotId)`.
  4. If `spot.total > 0`: check `online = exports.qbx_core:GetPlayer(spot.ownerSrc)`; if `online and online.PlayerData.citizenid == spot.ownerCid` pay `exports.qbx_core:AddMoney(spot.ownerSrc, Config.Account, spot.total, reasonTag)` and notify if `notifyMode`; else pay `exports.qbx_core:AddMoney(spot.ownerCid, Config.OfflineFallbackAccount, spot.total, 'clay-busking-offline')`. Log via `lib.print.error` if `AddMoney` returns `false`.
  5. Return `spot.total`.
- Check alive helper: ped exists (`ped ~= 0`), `GetEntityHealth(ped) > 0`, and `not (player.PlayerData.metadata and (player.PlayerData.metadata.isdead or player.PlayerData.metadata.inlaststand))`.
- Watchdog loop sleeps `Config.ServerWatchdogMs`, skips work when `next(spots) == nil`, otherwise collects spot IDs whose owner ped is missing, dead, or beyond `Config.AutoEndRadius + 2.0`, and closes each through `withSpotLock` + `closeAndPayout(id, 'clay-busking-auto', true)`.
- Register `QBCore:Server:OnPlayerUnload`, `playerDropped`, and `onResourceStop`.

- [ ] **Step 4: Run `tests/server_test.lua` and syntax check**

Run:
```powershell
lua tests/server_test.lua
luac -p server/main.lua
```
Expected: `server_test OK` and exit code `0`.

---

### Task 3: Client Spatial Engine, NUI Bridge & `ox_inventory` Item

**Files:**
- Create: `client/main.lua`
- Modify: `c:\Users\ClayStudio\Desktop\Fivem Server Project\qbox\resources\[ox]\ox_inventory\data\items.lua:799-809`
- Test: `tests/client_test.lua`

**Interfaces:**
- Consumes: `Config`, Task 2 callbacks/events (`clay-busking:getAll`, `clay-busking:start`, `clay-busking:tip`, `clay-busking:collect`, `clay-busking:ownerLeft`, `clay-busking:syncSpot`, `clay-busking:removeSpot`), `lib.points.new`, `lib.showTextUI`, `lib.hideTextUI`, `lib.progressCircle`, `lib.notify`, `lib.requestModel`, `lib.callback.await`, `exports.qbx_core:GetPlayerData`
- Produces:
  - `exports('useBuskingHat', function() ... end)`
  - NUI outbound messages (`SendNUIMessage`):
    - `{ action = 'hud', spot = { id, total, top3 } | nil, ui = Config.Ui }`
    - `{ action = 'openModal', mode = 'tip' | 'collect', spot = { id, total, top3 }, ui = Config.Ui, limits = { minTip, maxTip } }`
    - `{ action = 'updateModal', spot = { id, total, top3 } }`
    - `{ action = 'closeModal' }`
  - NUI inbound callbacks (`RegisterNUICallback`):
    - `ready` -> `{ ok = true }`
    - `close` -> `{ ok = true }`
    - `tip` (`{ spotId, amount }`) -> `{ ok, message? }`
    - `collect` (`{ spotId }`) -> `{ ok, message? }`
  - `ox_inventory` item `'busking_hat'` in `resources/[ox]/ox_inventory/data/items.lua`

- [ ] **Step 1: Write failing client tests in `tests/client_test.lua`**

Create `tests/client_test.lua` that stubs FiveM client natives (`CreateObject`, `DeleteEntity`, `DoesEntityExist`, `PlaceObjectOnGroundProperly`, `FreezeEntityPosition`, `SetEntityHeading`, `SetEntityAsMissionEntity`, `SetModelAsNoLongerNeeded`, `GetEntityCoords`, `GetEntityHeading`, `GetOffsetFromEntityInWorldCoords`, `GetGroundZFor_3dCoord`, `IsEntityDead`, `IsPedFalling`, `IsPedSwimming`, `IsControlJustReleased`, `PlaySoundFrontend`, `TaskPlayAnim`, `SetNuiFocus`, `SendNUIMessage`, `RegisterNUICallback`, `RegisterNetEvent`, `AddEventHandler`, `TriggerServerEvent`, `CreateThread`, `Wait`, `GetCurrentResourceName`, `joaat`, `vec3`, `vector3`), `cache`, `LocalPlayer`, `lib`, and `exports`, loads `config.lua` and `client/main.lua`, and verifies:

1. **Overlapping `HudRadius` selection**: Place `busk_1` at `(0, 0, 0)` and `busk_2` at `(6, 0, 0)`. With player at `(2, 0, 0)`, HUD shows `busk_1`; moving player to `(5, 0, 0)` switches HUD to `busk_2`; removing `busk_2` seamlessly switches HUD back to `busk_1` (still within `10.0`m) instead of hiding HUD; moving player to `(20, 0, 0)` sends `{ action = 'hud', spot = nil }`.
2. **Role-aware modal**: Pressing `[E]` on own spot (`ownerCid == player.citizenid`) opens `{ action = 'openModal', mode = 'collect', ... }` with `SetNuiFocus(true, true)`; pressing `[E]` on another player's spot opens `{ action = 'openModal', mode = 'tip', ... }`.
3. **Modal closed cleanly on `removeSpot`, walk-away, or death**: While `TipModal` is open for `busk_2`, firing `clay-busking:removeSpot` for `busk_2` (or moving `> Config.InteractDistance + 2.0` / setting `LocalPlayer.state.isDead = true`) calls `SetNuiFocus(false, false)` and sends `{ action = 'closeModal' }`.
4. **Live modal & HUD update on `syncSpot`**: Updating `busk_2` total/top3 while HUD is active pushes updated `{ action = 'hud', spot = ... }` and sends `{ action = 'updateModal', spot = ... }` (without reopening or wiping input) if `openSpotId == 'busk_2'`.
5. **Owner walk-away / death detection**: When own spot exists and player moves `> Config.AutoEndRadius` or `LocalPlayer.state.isDead = true`, client emits `clay-busking:ownerLeft` with own `spotId`.
6. **Cleanup on `onResourceStop`**: Removes all `lib.points`, deletes spawned props, hides TextUI, clears NUI focus.

- [ ] **Step 2: Run `tests/client_test.lua` to verify it fails**

Run: `lua tests/client_test.lua`
Expected: FAIL (`cannot open client/main.lua: No such file or directory`).

- [ ] **Step 3: Implement `client/main.lua` and register `busking_hat` in `ox_inventory/data/items.lua`**

- In `client/main.lua`:
  - Follow `clay-musicbox/client/main.lua` prop streaming pattern (`lib.points.new` at `Config.PropSpawnDistance`, guard `spots[spotId] ~= entry` for `ox_lib`'s 300ms teardown window, spawn/despawn local non-networked object with `PlaceObjectOnGroundProperly` + `FreezeEntityPosition`).
  - Maintain a helper `refreshHud()` that evaluates all spots in `spots` within `Config.HudRadius`, picks the nearest (tie-break by `id`), and only calls `SendNUIMessage({ action = 'hud', ... })` when spot ID or revision (`total` / `top3`) changed. Run `refreshHud()` on `syncSpot`, `removeSpot`, point `onEnter`/`onExit`, and inside a lightweight 250ms loop ONLY while at least one spot is inside `PropSpawnDistance`.
  - When inside `InteractDistance` of closest spot (`self.isClosest`, not placing, not open modal, not in vehicle, not dead), show `lib.showTextUI` (`[E] เก็บเงินเปิดหมวก` for owner, `[E] ให้ทิปเปิดหมวก` for viewer) and open modal on `KEY_E = 38`.
  - While a modal is open (`openSpotId ~= nil`), run a guard loop every 400ms (same as `clay-musicbox/client/main.lua`) that closes the modal and clears `SetNuiFocus(false, false)` if the spot disappears, player dies, or player moves beyond `Config.InteractDistance + 2.0`.
  - When `syncSpot` updates `openSpotId`, send `{ action = 'updateModal', spot = ... }` so `CollectModal` reflects new tips live without wiping user input in `TipModal`.
  - Optional visuals in `nearby`: only draw `DrawMarker` circle if `Config.ShowZoneMarker` is true; only draw 3D text if `Config.Show3DText` is true and within `HudRadius`.
  - `tip` NUI callback calls `lib.callback.await('clay-busking:tip', false, spotId, amount)`; on `ok`: close modal, run non-blocking short `pickup_object` / `pickup_low` anim (~700ms) + `PlaySoundFrontend(-1, 'PICK_UP_MONEY', 'HUD_FRONTEND_DEFAULT_SOUNDSET', false)`, notify tipper.
  - `collect` NUI callback calls `lib.callback.await('clay-busking:collect', false, spotId)`; on `ok`: close modal (server notifies owner).
  - `exports('useBuskingHat', ...)` checks not placing/modal/dead/in-vehicle/falling/swimming, runs `lib.progressCircle` (`Config.PlaceDurationMs`, `amb@medic@standing@kneel@base` / `base`), computes ground coords at `Config.PlaceDistance`, calls `clay-busking:start`, upserts spot, and starts owner walk-away monitor thread (ticks every 500ms while player owns an active spot, sending `clay-busking:ownerLeft` once when `dist > Config.AutoEndRadius` or dead).
  - Sync all spots on `QBCore:Client:OnPlayerLoaded` and `onClientResourceStart` (when `LocalPlayer.state.isLoggedIn`).
- In `c:\Users\ClayStudio\Desktop\Fivem Server Project\qbox\resources\[ox]\ox_inventory\data\items.lua`: add the `['busking_hat']` entry from spec section 4 right after `['musicbox']` (lines 799-809).

- [ ] **Step 4: Run `tests/client_test.lua` and syntax checks**

Run:
```powershell
lua tests/client_test.lua
luac -p client/main.lua
luac -p "c:\Users\ClayStudio\Desktop\Fivem Server Project\qbox\resources\[ox]\ox_inventory\data\items.lua"
```
Expected: `client_test OK` and exit code `0` for both `luac -p` commands.

---

### Task 4: Svelte 5 NUI (`HudCard`, `TipModal`, `CollectModal`), Preview Mode & Production Build

**Files:**
- Create: `nui-src/package.json`
- Create: `nui-src/vite.config.js`
- Create: `nui-src/index.html`
- Create: `nui-src/src/main.js`
- Create: `nui-src/src/style.css`
- Create: `nui-src/src/nui.js`
- Create: `nui-src/src/format.js`
- Create: `nui-src/src/preview.js`
- Create: `nui-src/src/HudCard.svelte`
- Create: `nui-src/src/TipModal.svelte`
- Create: `nui-src/src/CollectModal.svelte`
- Create: `nui-src/src/App.svelte`
- Test: `nui-src/tests/format.test.mjs`
- Build output: `ui/index.html`, `ui/assets/*`

**Interfaces:**
- Consumes: Task 3 NUI messages (`hud`, `openModal`, `updateModal`, `closeModal`) and NUI callbacks (`ready`, `close`, `tip`, `collect`)
- Produces:
  - `nui-src/src/format.js`:
    - `formatMoney(amount: number) -> string` (integer formatted with thousands commas, e.g. `5860` -> `'5,860'`, invalid/negative -> `'0'`)
    - `parseTipInput(raw: string | number, minTip: number, maxTip: number) -> { ok: true, value: number } | { ok: false, error: string }`
  - Compiled static bundle in `ui/` referenced by `fxmanifest.lua`

- [ ] **Step 1: Scaffold `nui-src/package.json`, `vite.config.js`, `index.html`, and install dependencies**

Match `clay-musicbox/nui-src/package.json` (`svelte`, `vite`, `@sveltejs/vite-plugin-svelte`, `@fontsource/kanit`, `@fontsource/chakra-petch`) and `vite.config.js` (`base: './'`, `outDir: '../ui'`, `emptyOutDir: true`, `target: 'chrome91'`).
Run inside `nui-src`: `npm.cmd install`
Expected: `node_modules` installed cleanly with exit code `0`.

- [ ] **Step 2: Write failing NUI unit tests in `nui-src/tests/format.test.mjs`**

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { formatMoney, parseTipInput } from '../src/format.js';

test('formatMoney formats non-negative integers with commas', () => {
  assert.equal(formatMoney(0), '0');
  assert.equal(formatMoney(5860), '5,860');
  assert.equal(formatMoney(100000), '100,000');
  assert.equal(formatMoney(-5), '0');
  assert.equal(formatMoney(NaN), '0');
});

test('parseTipInput accepts valid integer strings within bounds', () => {
  assert.deepEqual(parseTipInput('1000', 1, 100000), { ok: true, value: 1000 });
  assert.deepEqual(parseTipInput(' 1 ', 1, 100000), { ok: true, value: 1 });
  assert.deepEqual(parseTipInput('100000', 1, 100000), { ok: true, value: 100000 });
});

test('parseTipInput rejects empty, decimals, non-digits, zero, negative, and out-of-range', () => {
  for (const bad of ['', '   ', '0', '-10', '10.5', '100abc', '100001', '1e3']) {
    const res = parseTipInput(bad, 1, 100000);
    assert.equal(res.ok, false, `expected reject for ${JSON.stringify(bad)}`);
    assert.equal(typeof res.error, 'string');
    assert.ok(res.error.length > 0);
  }
});
```

- [ ] **Step 3: Run `format.test.mjs` to verify it fails**

Run (from `nui-src`): `node --test tests/format.test.mjs`
Expected: FAIL (`Cannot find module '../src/format.js'`).

- [ ] **Step 4: Implement `format.js`, `nui.js`, `preview.js`, Svelte components, and styles**

- `format.js`: `parseTipInput` trims string, tests `/^\d+$/`, converts via `Number`, checks `Number.isSafeInteger` and `minTip <= value <= maxTip`, returns Thai validation error messages on failure.
- `nui.js`: Same pattern as `clay-musicbox/nui-src/src/nui.js` (`inGame`, `isPreview`, `nui(action, data)`).
- `HudCard.svelte`: Fixed middle-right (`pointer-events: none`), dark semi-transparent glass card matching `xCore Busking` layout — header with hat/coin SVG icon + `ui.title`, thin divider, `ui.totalLabel` + `$ {formatMoney(spot.total)}`, either `•••` when `top3.length === 0` or 1–3 rows with rank-colored crown SVGs (rank 1 `#F5C542`, rank 2 `#E68A3E`, rank 3 `#4ADE80`), truncated donor name, and rounded amount pill.
- `TipModal.svelte`: Centered compact dark modal — header + `ui.tipPrompt`, autofocused numeric input (`inputmode="numeric"`, Enter submits), inline Thai error message when invalid or server rejects, `Close` (secondary) and `Confirm` (primary blue accent, disabled while `submitting`).
- `CollectModal.svelte`: Centered compact dark modal — header + `{ui.totalLabel} $ {formatMoney(spot.total)}`, `Close` and `รับเงิน` (primary blue accent, disabled while `submitting`).
- `App.svelte`: Listens to `window` `message` (`hud`, `openModal`, `updateModal`, `closeModal`) and `keydown` (`Escape` closes active modal via `nui('close')`), notifies client `{ ready }` on mount, resets `submitting` and `error` on `openModal`/`closeModal` (while `updateModal` updates only `modalSpot` without clearing input), and in `isPreview` renders a small bottom-left dev toolbar to toggle empty HUD / Top 3 / simulate tip overtake / open TipModal / open CollectModal.

- [ ] **Step 5: Run NUI tests, production build, and full cross-suite verification**

Run:
```powershell
# From nui-src/
node --test tests/format.test.mjs
npm.cmd run build

# From clay-busking/
lua tests/rules_test.lua
lua tests/server_test.lua
lua tests/client_test.lua
luac -p fxmanifest.lua config.lua shared/rules.lua server/selfcheck.lua server/main.lua client/main.lua
```
Expected:
- `format.test.mjs`: all tests PASS
- `npm.cmd run build`: builds `ui/index.html` and `ui/assets/*` with exit code `0`
- `rules_test OK`, `server_test OK`, `client_test OK`
- `luac -p`: exit code `0` on all Lua files.
