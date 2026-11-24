-- Standalone Lua 5.4 test harness for client/main.lua
local vecMeta = {}
function vector3(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, vecMeta)
end
vec3 = vector3
function vecMeta.__sub(a, b)
    return vector3(a.x - b.x, a.y - b.y, a.z - b.z)
end
function vecMeta.__len(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local playerCoords = vector3(0, 0, 0)
local playerDead = false
local playerCid = 'CID_ME'
local controlPressed = {}
local nuiMessages = {}
local nuiCallbacks = {}
local netEvents = {}
local handlers = {}
local serverEvents = {}
local exportedFns = {}
local points = {}
local entities = {}
local nextEntityId = 100
local nuiFocus = { false, false }
local textUiState = nil
local threads = {}
local callbackResponses = {}
local soundLog = {}
local throwNextRequestModel = false
local getPlayerDataCalls = 0

cache = { ped = 1, vehicle = false }
LocalPlayer = { state = { isDead = false, isLoggedIn = true } }

function joaat(s) return s end
function GetCurrentResourceName() return 'clay-busking' end
function GetEntityCoords() return playerCoords end
function GetEntityHeading() return 0.0 end
function GetOffsetFromEntityInWorldCoords(_, _, y, _)
    return vector3(playerCoords.x, playerCoords.y + y, playerCoords.z)
end
function GetGroundZFor_3dCoord(_, _, z) return true, z - 1.0 end
function IsEntityDead() return playerDead end
function IsPedFalling() return false end
function IsPedSwimming() return false end
function IsControlJustReleased(_, key)
    if controlPressed[key] then
        controlPressed[key] = nil
        return true
    end
    return false
end
function CreateObject()
    nextEntityId = nextEntityId + 1
    entities[nextEntityId] = true
    return nextEntityId
end
function DoesEntityExist(id) return entities[id] == true end
function DeleteEntity(id) entities[id] = nil end
function PlaceObjectOnGroundProperly() end
function FreezeEntityPosition() end
function SetEntityHeading() end
function SetEntityAsMissionEntity() end
function SetModelAsNoLongerNeeded() end
function PlaySoundFrontend(_, name, set)
    soundLog[#soundLog + 1] = { name = name, set = set }
end
function TaskPlayAnim() end
function SetNuiFocus(a, b) nuiFocus = { a, b } end
function SendNUIMessage(msg) nuiMessages[#nuiMessages + 1] = msg end
function RegisterNUICallback(name, fn) nuiCallbacks[name] = fn end
function RegisterNetEvent(name, fn) if fn then netEvents[name] = fn end end
function AddEventHandler(name, fn)
    handlers[name] = handlers[name] or {}
    handlers[name][#handlers[name] + 1] = fn
end
function TriggerServerEvent(name, ...)
    serverEvents[#serverEvents + 1] = { name = name, args = { ... } }
end
function CreateThread(fn)
    local co = coroutine.create(fn)
    threads[#threads + 1] = co
    coroutine.resume(co)
end
function Wait()
    coroutine.yield()
end

local function stepThreads()
    local active = {}
    for _, co in ipairs(threads) do
        if coroutine.status(co) == 'suspended' then
            local ok, err = coroutine.resume(co)
            assert(ok, err)
            if coroutine.status(co) == 'suspended' then
                active[#active + 1] = co
            end
        end
    end
    threads = active
end

exports = setmetatable({
    qbx_core = {
        GetPlayerData = function()
            getPlayerDataCalls = getPlayerDataCalls + 1
            return { citizenid = playerCid }
        end,
    },
}, {
    __call = function(_, name, fn)
        exportedFns[name] = fn
    end,
})

lib = {
    points = {
        new = function(opts)
            local pt = { coords = opts.coords, distance = opts.distance, removed = false, isClosest = true }
            function pt:remove() self.removed = true end
            points[#points + 1] = pt
            return pt
        end,
    },
    requestModel = function()
        if throwNextRequestModel then
            throwNextRequestModel = false
            error('failed to load model (timed out)')
        end
        return true
    end,
    requestAnimDict = function() return true end,
    showTextUI = function(text) textUiState = text end,
    hideTextUI = function() textUiState = nil end,
    progressCircle = function() return true end,
    notify = function() end,
    callback = {
        await = function(name, _, ...)
            local fn = callbackResponses[name]
            if fn then return fn(...) end
            return { ok = true }
        end,
    },
}

dofile('config.lua')
dofile('client/main.lua')

local function eq(a, b, msg)
    assert(a == b, ('%s: expected %s, got %s'):format(msg, tostring(b), tostring(a)))
end
local function lastMsg(action)
    for i = #nuiMessages, 1, -1 do
        if nuiMessages[i].action == action then return nuiMessages[i] end
    end
    return nil
end
local function tickNearby()
    -- Compute isClosest across live points
    local bestPt, bestDist = nil, math.huge
    for _, pt in ipairs(points) do
        if not pt.removed then
            local d = #(playerCoords - pt.coords)
            pt.currentDistance = d
            if d < bestDist then bestDist, bestPt = d, pt end
        end
    end
    for _, pt in ipairs(points) do
        if not pt.removed then
            pt.isClosest = (pt == bestPt)
            if pt.nearby and pt.currentDistance <= pt.distance then
                pt:nearby()
            end
        end
    end
end

-- 1. Overlapping HudRadius (10m) between two spots spaced 6m apart
playerCoords = vector3(2, 0, 0)
netEvents['clay-busking:syncSpot']({ id = 'busk_1', ownerCid = 'CID_OTHER', coords = { x = 0, y = 0, z = 0 }, heading = 0, total = 100, top3 = {} })
netEvents['clay-busking:syncSpot']({ id = 'busk_2', ownerCid = 'CID_OTHER', coords = { x = 6, y = 0, z = 0 }, heading = 0, total = 200, top3 = {} })
stepThreads()
eq(lastMsg('hud').spot.id, 'busk_1', 'closest spot busk_1 at x=2')

playerCoords = vector3(5, 0, 0)
stepThreads()
eq(lastMsg('hud').spot.id, 'busk_2', 'switches HUD to closer busk_2 at x=5')

-- Removing busk_2 seamlessly falls back to busk_1 (still 5m <= 10m)
netEvents['clay-busking:removeSpot']('busk_2')
eq(lastMsg('hud').spot.id, 'busk_1', 'fallback HUD to busk_1 when busk_2 removed')

-- Leaving HudRadius clears HUD
playerCoords = vector3(20, 0, 0)
stepThreads()
eq(lastMsg('hud').spot, nil, 'HUD hidden outside HudRadius')

-- 2. Role-aware modal on [E]: viewer -> tip, owner -> collect
playerCoords = vector3(1, 0, 0)
controlPressed[38] = true
tickNearby()
eq(lastMsg('openModal').mode, 'tip', 'non-owner opens tip modal')
eq(lastMsg('openModal').spot.id, 'busk_1', 'modal bound to busk_1')
eq(nuiFocus[1], true, 'NUI focus enabled for tip modal')

-- 4. Live syncSpot updates HUD + sends updateModal (never re-sends openModal)
local openCountBefore = 0
for _, m in ipairs(nuiMessages) do if m.action == 'openModal' then openCountBefore = openCountBefore + 1 end end
netEvents['clay-busking:syncSpot']({ id = 'busk_1', ownerCid = 'CID_OTHER', coords = { x = 0, y = 0, z = 0 }, heading = 0, total = 500, top3 = { { name = 'Bob', amount = 400 } } })
local openCountAfter = 0
for _, m in ipairs(nuiMessages) do if m.action == 'openModal' then openCountAfter = openCountAfter + 1 end end
eq(openCountAfter, openCountBefore, 'syncSpot does not re-send openModal')
eq(lastMsg('updateModal').spot.total, 500, 'updateModal pushes new total')
eq(lastMsg('hud').spot.total, 500, 'hud pushes new total')

-- 3a. removeSpot while modal open releases NUI focus and sends closeModal
netEvents['clay-busking:removeSpot']('busk_1')
eq(nuiFocus[1], false, 'removeSpot clears NUI focus')
eq(lastMsg('closeModal').action, 'closeModal', 'removeSpot sends closeModal')

-- 3b & 2b. Owner opens collect modal; walking away (> InteractDistance + 2.0) closes modal
netEvents['clay-busking:syncSpot']({ id = 'busk_own', ownerCid = 'CID_ME', coords = { x = 0, y = 0, z = 0 }, heading = 0, total = 300, top3 = {} })
playerCoords = vector3(1, 0, 0)
controlPressed[38] = true
tickNearby()
eq(lastMsg('openModal').mode, 'collect', 'owner opens collect modal')
eq(nuiFocus[1], true, 'NUI focus enabled for collect modal')

playerCoords = vector3(6, 0, 0) -- > 2.2 + 2.0
stepThreads()
eq(nuiFocus[1], false, 'walking away closes modal and clears focus')

-- 3c. Death closes modal
playerCoords = vector3(1, 0, 0)
controlPressed[38] = true
tickNearby()
eq(nuiFocus[1], true, 'modal re-opened')
LocalPlayer.state.isDead = true
stepThreads()
eq(nuiFocus[1], false, 'death closes modal')
LocalPlayer.state.isDead = false

-- 5. Owner walk-away monitor triggers clay-busking:ownerLeft
serverEvents = {}
playerCoords = vector3(20, 0, 0) -- > AutoEndRadius (14m)
stepThreads()
local foundOwnerLeft = false
for _, ev in ipairs(serverEvents) do
    if ev.name == 'clay-busking:ownerLeft' and ev.args[1] == 'busk_own' then
        foundOwnerLeft = true
    end
end
eq(foundOwnerLeft, true, 'ownerLeft emitted when owner exceeds AutoEndRadius')

-- 6. onResourceStop cleans up points, props, textUI, NUI focus
netEvents['clay-busking:syncSpot']({ id = 'busk_clean', ownerCid = 'CID_OTHER', coords = { x = 20, y = 0, z = 0 }, heading = 0, total = 0, top3 = {} })
stepThreads()
for _, fn in ipairs(handlers['onResourceStop'] or {}) do fn('clay-busking') end
local remainingEntities = 0
for _ in pairs(entities) do remainingEntities = remainingEntities + 1 end
eq(remainingEntities, 0, 'all props deleted on resource stop')
eq(textUiState, nil, 'textUI hidden on resource stop')
eq(nuiFocus[1], false, 'NUI focus cleared on resource stop')

-- 7. Important #2: lib.requestModel throwing must NOT wedge entry.spawning = true
playerCoords = vector3(0, 0, 0)
throwNextRequestModel = true
netEvents['clay-busking:syncSpot']({ id = 'busk_retry', ownerCid = 'CID_OTHER', coords = { x = 1, y = 0, z = 0 }, heading = 0, total = 0, top3 = {} })
-- Second syncSpot/onEnter should successfully spawn prop now that model loads
netEvents['clay-busking:syncSpot']({ id = 'busk_retry', ownerCid = 'CID_OTHER', coords = { x = 1, y = 0, z = 0 }, heading = 0, total = 50, top3 = {} })
local spawnedCount = 0
for _ in pairs(entities) do spawnedCount = spawnedCount + 1 end
eq(spawnedCount, 1, 'prop spawns on retry after requestModel error')

-- 8. Important #3: QBCore:Client:OnPlayerUnload clears HUD, modal, focus, props
controlPressed[38] = true
tickNearby()
eq(nuiFocus[1], true, 'modal open before client unload')
assert(netEvents['QBCore:Client:OnPlayerUnload'], 'QBCore:Client:OnPlayerUnload handler registered')
netEvents['QBCore:Client:OnPlayerUnload']()
eq(nuiFocus[1], false, 'unload clears NUI focus')
eq(lastMsg('hud').spot, nil, 'unload hides HUD')
spawnedCount = 0
for _ in pairs(entities) do spawnedCount = spawnedCount + 1 end
eq(spawnedCount, 0, 'unload deletes props')

-- 9. Important #4 + Re-graded #1: valid tip soundset & stale tip RPC does not close newer modal
playerCoords = vector3(0, 0, 0)
netEvents['clay-busking:syncSpot']({ id = 'busk_a', ownerCid = 'CID_OTHER', coords = { x = 0, y = 0, z = 0 }, heading = 0, total = 0, top3 = {} })
netEvents['clay-busking:syncSpot']({ id = 'busk_b', ownerCid = 'CID_OTHER', coords = { x = 6, y = 0, z = 0 }, heading = 0, total = 0, top3 = {} })
controlPressed[38] = true
tickNearby()
eq(lastMsg('openModal').spot.id, 'busk_a', 'opened busk_a')
soundLog = {}
callbackResponses['clay-busking:tip'] = function()
    -- Simulate player switching to busk_b while busk_a tip callback was in flight
    playerCoords = vector3(6, 0, 0)
    nuiCallbacks['close']({}, function() end)
    controlPressed[38] = true
    tickNearby()
    return { ok = true }
end
nuiCallbacks['tip']({ spotId = 'busk_a', amount = 100 }, function() end)
eq(nuiFocus[1], true, 'stale busk_a tip completion must not close busk_b modal')
eq(soundLog[1].name, 'LOCAL_PLYR_CASH_COUNTER_COMPLETE', 'valid GTA tip sound name')
eq(soundLog[1].set, 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', 'valid GTA tip soundset')
nuiCallbacks['close']({}, function() end)

-- 10. Re-graded #2: teleporting >60m away without point:onExit despawns prop and exits HUD loop
playerCoords = vector3(200, 0, 0)
stepThreads()
spawnedCount = 0
for _ in pairs(entities) do spawnedCount = spawnedCount + 1 end
eq(spawnedCount, 0, 'far teleport despawns orphaned props without onExit')
eq(lastMsg('hud').spot, nil, 'far teleport hides HUD')

-- 11. Candidate A: 60m spawn point has NO per-frame nearby() callback; zero GetPlayerData calls per frame / per syncSpot
netEvents['QBCore:Client:OnPlayerUnload']()
playerCid = 'CID_ME'
callbackResponses['clay-busking:getAll'] = function() return {} end
netEvents['QBCore:Client:OnPlayerLoaded']()
playerCoords = vector3(0.5, 0, 0)
points = {}
getPlayerDataCalls = 0
netEvents['clay-busking:syncSpot']({ id = 'busk_perf', ownerCid = 'CID_ME', coords = { x = 0, y = 0, z = 0 }, heading = 0, total = 0, top3 = {} })

local spawnPtFound, interactPtFound = false, false
for _, pt in ipairs(points) do
    if not pt.removed then
        if pt.distance >= 50.0 then
            spawnPtFound = true
            eq(pt.nearby, nil, '60m spawn point must NOT define per-frame nearby()')
        elseif pt.distance <= 3.0 then
            interactPtFound = true
            assert(type(pt.nearby) == 'function', 'short-range interact point must define nearby()')
        end
    end
end
eq(spawnPtFound, true, 'spawn point exists')
eq(interactPtFound, true, 'short-range interact point exists')

for i = 1, 60 do
    netEvents['clay-busking:syncSpot']({ id = 'busk_perf', ownerCid = 'CID_ME', coords = { x = 0, y = 0, z = 0 }, heading = 0, total = i * 10, top3 = {} })
    tickNearby()
end
eq(getPlayerDataCalls, 0, 'zero GetPlayerData export copies across 60 syncSpots + 60 nearby frames')

-- 12. Candidate A: multichar switch updates cachedCid cleanly
netEvents['QBCore:Client:OnPlayerUnload']()
playerCid = 'CID_CHAR2'
netEvents['QBCore:Client:OnPlayerLoaded']()
netEvents['clay-busking:syncSpot']({ id = 'busk_old_owner', ownerCid = 'CID_ME', coords = { x = 0, y = 0, z = 0 }, heading = 0, total = 50, top3 = {} })
playerCoords = vector3(0.5, 0, 0)
controlPressed[38] = true
tickNearby()
eq(lastMsg('openModal').mode, 'tip', 'after character switch, old char spot opens tip modal (not collect)')
nuiCallbacks['close']({}, function() end)

print('client_test OK')
