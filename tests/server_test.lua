-- Standalone Lua 5.4 test harness for server/main.lua
local vecMeta = {}
function vector3(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, vecMeta)
end
function vecMeta.__sub(a, b)
    return vector3(a.x - b.x, a.y - b.y, a.z - b.z)
end
function vecMeta.__len(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local callbacks = {}
local netEvents = {}
local handlers = {}
local emitted = {}
local moneyLog = {}
local notifyLog = {}
local errorLog = {}
local threads = {}

local players = {}
local playerStates = {}
local peds = {}
local items = {}
local onAddMoneyHook = nil
local failNextAddMoney = false
local getPlayerCalls = 0

local function makePlayer(src, cid, first, last, cash, bank, extra)
    extra = extra or {}
    players[src] = {
        PlayerData = {
            source = src,
            citizenid = cid,
            charinfo = { firstname = first, lastname = last },
            money = { cash = cash, bank = bank or 0 },
            metadata = { isdead = extra.isdead or false, inlaststand = extra.inlaststand or false },
        },
    }
    playerStates[src] = { isDead = (extra.isdead or extra.inlaststand) or false }
    peds[src] = {
        id = src * 10,
        coords = extra.coords or vector3(0.0, 0.0, 0.0),
        vehicle = extra.vehicle or 0,
        health = extra.health or 200,
    }
    items[src] = extra.items or {}
end

local function findPlayerByPed(pedId)
    for src, p in pairs(peds) do
        if p.id == pedId then return src, p end
    end
    return nil, nil
end

function GetPlayerPed(src)
    return peds[src] and peds[src].id or 0
end
function GetEntityCoords(pedId)
    local _, p = findPlayerByPed(pedId)
    return p and p.coords or vector3(0, 0, 0)
end
function GetVehiclePedIsIn(pedId)
    local _, p = findPlayerByPed(pedId)
    return p and p.vehicle or 0
end
function GetEntityHealth(pedId)
    local _, p = findPlayerByPed(pedId)
    return p and p.health or 0
end
function Player(src)
    playerStates[src] = playerStates[src] or { isDead = false }
    return { state = playerStates[src] }
end
function GetPlayerName(src)
    return 'Steam' .. tostring(src)
end
function GetCurrentResourceName()
    return 'clay-busking'
end
function TriggerClientEvent(name, target, ...)
    emitted[#emitted + 1] = { name = name, target = target, args = { ... } }
end
function RegisterNetEvent(name, fn)
    if fn then netEvents[name] = fn end
end
function AddEventHandler(name, fn)
    handlers[name] = handlers[name] or {}
    handlers[name][#handlers[name] + 1] = fn
end
function CreateThread(fn)
    threads[#threads + 1] = fn
end
function Wait()
    coroutine.yield()
end

lib = {
    callback = {
        register = function(name, fn) callbacks[name] = fn end,
    },
    print = {
        error = function(...) errorLog[#errorLog + 1] = table.concat({ ... }, ' ') end,
    },
}

exports = {
    ox_inventory = {
        GetItemCount = function(_, src, name)
            return (items[src] and items[src][name]) or 0
        end,
        RemoveItem = function()
            error('busking_hat must not be removed from inventory (consume = 0)')
        end,
    },
    qbx_core = {
        GetPlayer = function(_, src)
            getPlayerCalls = getPlayerCalls + 1
            local p = players[src]
            if not p then return nil end
            -- Return a shallow copy of money table like QBox export copy behavior
            return {
                PlayerData = {
                    source = p.PlayerData.source,
                    citizenid = p.PlayerData.citizenid,
                    charinfo = p.PlayerData.charinfo,
                    money = { cash = p.PlayerData.money.cash, bank = p.PlayerData.money.bank },
                    metadata = p.PlayerData.metadata,
                },
            }
        end,
        RemoveMoney = function(_, src, account, amount, reason)
            local p = players[src]
            if not p or (p.PlayerData.money[account] or 0) < amount then return false end
            p.PlayerData.money[account] = p.PlayerData.money[account] - amount
            moneyLog[#moneyLog + 1] = { op = 'remove', id = src, account = account, amount = amount, reason = reason }
            return true
        end,
        AddMoney = function(_, idOrCid, account, amount, reason)
            if onAddMoneyHook then
                local hook = onAddMoneyHook
                onAddMoneyHook = nil
                hook(idOrCid, account, amount, reason)
            end
            if failNextAddMoney then
                failNextAddMoney = false
                return false
            end
            moneyLog[#moneyLog + 1] = { op = 'add', id = idOrCid, account = account, amount = amount, reason = reason }
            if type(idOrCid) == 'number' and players[idOrCid] then
                players[idOrCid].PlayerData.money[account] = (players[idOrCid].PlayerData.money[account] or 0) + amount
            end
            return true
        end,
        Notify = function(_, src, msg, kind)
            notifyLog[#notifyLog + 1] = { src = src, msg = msg, kind = kind }
        end,
    },
}

dofile('config.lua')
dofile('shared/rules.lua')
dofile('server/main.lua')

local function eq(a, b, msg)
    assert(a == b, ('%s: expected %s, got %s'):format(msg, tostring(b), tostring(a)))
end
local function fireHandler(name, src, ...)
    source = src
    for _, fn in ipairs(handlers[name] or {}) do
        fn(...)
    end
    source = nil
end
local function fireNetEvent(name, src, ...)
    source = src
    netEvents[name](...)
    source = nil
end

-- 1. start validation
makePlayer(1, 'CID1', 'Alice', 'Singer', 500, 1000, { coords = vector3(0, 0, 0), items = {} })
local r = callbacks['clay-busking:start'](1, { x = 1, y = 0, z = 0 }, 90)
eq(r.ok, false, 'reject missing item')
eq(r.reason, 'no_item', 'reason no_item')

items[1].busking_hat = 1
peds[1].vehicle = 99
r = callbacks['clay-busking:start'](1, { x = 1, y = 0, z = 0 }, 90)
eq(r.ok, false, 'reject in vehicle')
peds[1].vehicle = 0

players[1].PlayerData.metadata.isdead = true
r = callbacks['clay-busking:start'](1, { x = 1, y = 0, z = 0 }, 90)
eq(r.ok, false, 'reject dead')
players[1].PlayerData.metadata.isdead = false

r = callbacks['clay-busking:start'](1, { x = 10, y = 0, z = 0 }, 90)
eq(r.ok, false, 'reject far placement coords')

-- 2. start success (item kept, snapshot lean)
emitted = {}
r = callbacks['clay-busking:start'](1, { x = 1, y = 0, z = 0 }, 90)
eq(r.ok, true, 'start ok')
eq(r.spot.total, 0, 'initial total 0')
eq(#r.spot.top3, 0, 'initial top3 empty')
eq(r.spot.donors, nil, 'snapshot omits raw donors')
eq(items[1].busking_hat, 1, 'item not removed')
eq(emitted[1].name, 'clay-busking:syncSpot', 'broadcast syncSpot')
local spot1Id = r.spot.id

-- duplicate spot by same player rejected
local dup = callbacks['clay-busking:start'](1, { x = 1, y = 0, z = 0 }, 90)
eq(dup.ok, false, 'reject second spot by same owner')
eq(dup.reason, 'already_active', 'reason already_active')

-- spacing check for another player
makePlayer(2, 'CID2', 'Bob', 'Tipper', 2000, 0, { coords = vector3(3, 0, 0), items = { busking_hat = 1 } })
local tooClose = callbacks['clay-busking:start'](2, { x = 4, y = 0, z = 0 }, 0)
eq(tooClose.ok, false, 'reject spot too close')
eq(tooClose.reason, 'too_close', 'reason too_close')

-- 3. tip validation + valid tip (whole float from JSON)
local selfTip = callbacks['clay-busking:tip'](1, spot1Id, 100)
eq(selfTip.ok, false, 'reject self tip')
eq(selfTip.reason, 'self_tip', 'reason self_tip')

peds[2].coords = vector3(20, 0, 0)
local farTip = callbacks['clay-busking:tip'](2, spot1Id, 100)
eq(farTip.ok, false, 'reject far tip')

peds[2].coords = vector3(1.5, 0, 0)
eq(callbacks['clay-busking:tip'](2, spot1Id, 0).ok, false, 'reject 0 tip')
eq(callbacks['clay-busking:tip'](2, spot1Id, 10.5).ok, false, 'reject decimal tip')
eq(callbacks['clay-busking:tip'](2, spot1Id, 5000).reason, 'no_money', 'reject insufficient cash')

emitted = {}
moneyLog = {}
local okTip = callbacks['clay-busking:tip'](2, spot1Id, 500.0)
eq(okTip.ok, true, 'whole float tip accepted')
eq(okTip.spot.total, 500, 'spot total 500')
eq(okTip.spot.top3[1].name, 'Bob Tipper', 'server charinfo name')
eq(okTip.spot.top3[1].amount, 500, 'top3 amount 500')
eq(okTip.spot.donors, nil, 'no donors table in broadcast')
eq(players[2].PlayerData.money.cash, 1500, 'tipper cash deducted')
eq(moneyLog[1].reason, 'clay-busking-tip', 'tip money reason')
eq(emitted[1].name, 'clay-busking:syncSpot', 'broadcast syncSpot on tip')

-- 4. collect: non-owner rejected, owner collect atomic before AddMoney (race check!)
eq(callbacks['clay-busking:collect'](2, spot1Id).reason, 'not_owner', 'reject non-owner collect')
peds[1].coords = vector3(20, 0, 0)
eq(callbacks['clay-busking:collect'](1, spot1Id).reason, 'too_far', 'reject far collect')
peds[1].coords = vector3(1, 0, 0)

callbacks['clay-busking:tip'](2, spot1Id, 1000) -- total now 1500
local reenterCollect, reenterTip
onAddMoneyHook = function()
    reenterCollect = callbacks['clay-busking:collect'](1, spot1Id)
    reenterTip = callbacks['clay-busking:tip'](2, spot1Id, 100)
end
emitted = {}
moneyLog = {}
local col = callbacks['clay-busking:collect'](1, spot1Id)
eq(col.ok, true, 'collect ok')
eq(col.total, 1500, 'collect total 1500')
eq(reenterCollect.ok, false, 're-entrant collect blocked')
eq(reenterTip.ok, false, 're-entrant tip blocked')
eq(players[2].PlayerData.money.cash, 500, 're-entrant tip did not deduct cash')
eq(#moneyLog, 1, 'paid exactly once')
eq(moneyLog[1].account, 'cash', 'online collect paid to cash')
eq(moneyLog[1].reason, 'clay-busking-collect', 'collect reason')
eq(emitted[1].name, 'clay-busking:removeSpot', 'broadcast removeSpot')

-- 5. collect with total == 0 does not call AddMoney
moneyLog = {}
local sZero = callbacks['clay-busking:start'](1, { x = 1, y = 0, z = 0 }, 0).spot.id
local col0 = callbacks['clay-busking:collect'](1, sZero)
eq(col0.ok, true, 'zero collect ok')
eq(col0.total, 0, 'zero total')
eq(#moneyLog, 0, 'no AddMoney for 0 total')

-- 6. ownerLeft spoof ignored when near+alive; succeeds when beyond AutoEndRadius
local s2 = callbacks['clay-busking:start'](1, { x = 1, y = 0, z = 0 }, 0).spot.id
callbacks['clay-busking:tip'](2, s2, 200)
moneyLog = {}
fireNetEvent('clay-busking:ownerLeft', 1, s2)
eq(#callbacks['clay-busking:getAll'](), 1, 'spoofed ownerLeft ignored when near')

peds[1].coords = vector3(30, 0, 0)
fireNetEvent('clay-busking:ownerLeft', 1, s2)
eq(#callbacks['clay-busking:getAll'](), 0, 'spot closed when beyond AutoEndRadius')
eq(moneyLog[1].account, 'cash', 'walk-away pays online cash')
eq(moneyLog[1].amount, 200, 'walk-away pays 200')
eq(moneyLog[1].reason, 'clay-busking-auto', 'walk-away reason')

-- 7. Critical #1: Logout saves BEFORE OnPlayerUnload, then clears QBX.Players[src] and fires playerLoggedOut
peds[1].coords = vector3(1, 0, 0)
local s3 = callbacks['clay-busking:start'](1, { x = 1, y = 0, z = 0 }, 0).spot.id
callbacks['clay-busking:tip'](2, s3, 100)
moneyLog = {}
emitted = {}
fireHandler('QBCore:Server:OnPlayerUnload', nil, 1)
eq(#callbacks['clay-busking:getAll'](), 0, 'OnPlayerUnload closes spot immediately')
eq(emitted[1].name, 'clay-busking:removeSpot', 'OnPlayerUnload broadcasts removeSpot')
eq(#moneyLog, 0, 'OnPlayerUnload defers payout until player is unregistered (avoids lost RAM cash)')
players[1] = nil -- Logout clears QBX.Players[src] after Wait(200)
fireHandler('qbx_core:server:playerLoggedOut', nil, 1)
eq(#moneyLog, 1, 'playerLoggedOut pays offline once')
eq(moneyLog[1].id, 'CID1', 'playerLoggedOut targets citizenid')
eq(moneyLog[1].account, 'bank', 'playerLoggedOut uses bank fallback so ox_inventory does not overwrite cash')
eq(moneyLog[1].reason, 'clay-busking-offline', 'playerLoggedOut offline reason')
fireHandler('playerDropped', 1)
eq(#moneyLog, 1, 'subsequent playerDropped does not double pay')

-- 7b. Important #1: collect AddMoney failure restores spot and reports payout_failed without removeSpot
makePlayer(1, 'CID1', 'Alice', 'Singer', 500, 1000, { coords = vector3(1, 0, 0), items = { busking_hat = 1 } })
local sFail = callbacks['clay-busking:start'](1, { x = 1, y = 0, z = 0 }, 0).spot.id
callbacks['clay-busking:tip'](2, sFail, 100)
failNextAddMoney = true
emitted = {}
local colFail = callbacks['clay-busking:collect'](1, sFail)
eq(colFail.ok, false, 'collect fails when AddMoney returns false')
eq(colFail.reason, 'payout_failed', 'reason payout_failed')
eq(#callbacks['clay-busking:getAll'](), 1, 'spot restored when AddMoney fails')
eq(#emitted, 0, 'removeSpot not broadcast when AddMoney fails')
-- Retry collect succeeds cleanly once AddMoney works
local colRetry = callbacks['clay-busking:collect'](1, sFail)
eq(colRetry.ok, true, 'retry collect succeeds')
eq(colRetry.total, 100, 'retry pays full 100')

-- 8. Abrupt playerDropped with GetPlayer == nil pays offline bank fallback
makePlayer(1, 'CID1', 'Alice', 'Singer', 500, 1000, { coords = vector3(1, 0, 0), items = { busking_hat = 1 } })
players[2].PlayerData.money.cash = 1000
local s4 = callbacks['clay-busking:start'](1, { x = 1, y = 0, z = 0 }, 0).spot.id
eq(callbacks['clay-busking:tip'](2, s4, 150).ok, true, 'tip 150 for abrupt drop test')
moneyLog = {}
players[1] = nil -- simulate player already unloaded before playerDropped fires
fireHandler('playerDropped', 1)
eq(#moneyLog, 1, 'abrupt drop paid once')
eq(moneyLog[1].id, 'CID1', 'offline payout targets citizenid')
eq(moneyLog[1].account, 'bank', 'offline payout uses bank fallback')
eq(moneyLog[1].amount, 150, 'offline payout amount')
eq(moneyLog[1].reason, 'clay-busking-offline', 'offline payout reason')

-- 9. onResourceStop pays active spots (ignores other resources)
makePlayer(1, 'CID1', 'Alice', 'Singer', 500, 1000, { coords = vector3(1, 0, 0), items = { busking_hat = 1 } })
local s5 = callbacks['clay-busking:start'](1, { x = 1, y = 0, z = 0 }, 0).spot.id
callbacks['clay-busking:tip'](2, s5, 50)
moneyLog = {}
fireHandler('onResourceStop', nil, 'other-resource')
eq(#callbacks['clay-busking:getAll'](), 1, 'other resource stop ignored')
fireHandler('onResourceStop', nil, 'clay-busking')
eq(#callbacks['clay-busking:getAll'](), 0, 'current resource stop clears spots')
eq(moneyLog[1].amount, 50, 'resource stop paid 50')

-- 10. Server watchdog closes spot when owner moves beyond AutoEndRadius + 2.0 or dies
players[2].PlayerData.money.cash = 1000
local s6 = callbacks['clay-busking:start'](1, { x = 1, y = 0, z = 0 }, 0).spot.id
callbacks['clay-busking:tip'](2, s6, 75)
moneyLog = {}
peds[1].coords = vector3(50, 0, 0) -- > AutoEndRadius + 2.0 without client sending ownerLeft
assert(#threads >= 1, 'watchdog thread registered')
local watchdogCo = coroutine.create(threads[1])
assert(coroutine.resume(watchdogCo)) -- hits first Wait
assert(coroutine.resume(watchdogCo)) -- executes one scan cycle
eq(#callbacks['clay-busking:getAll'](), 0, 'watchdog closed far spot')
eq(moneyLog[1].amount, 75, 'watchdog paid 75')

-- 11. Candidate A: server watchdog makes ZERO qbx:GetPlayer export copies while owners are alive+in-range,
--     and detects LAST_STAND/DEAD via Player(src).state.isDead
peds[1].coords = vector3(1, 0, 0)
local s7 = callbacks['clay-busking:start'](1, { x = 1, y = 0, z = 0 }, 0).spot.id
eq(callbacks['clay-busking:tip'](2, s7, 60).ok, true, 'tip 60 for watchdog state test')
getPlayerCalls = 0
assert(coroutine.resume(watchdogCo)) -- healthy scan cycle
eq(getPlayerCalls, 0, 'watchdog must not call qbx:GetPlayer for healthy active spots')
eq(#callbacks['clay-busking:getAll'](), 1, 'healthy spot stays open')

-- Now mark owner dead via qbx_medical server statebag (even with health > 0 like LAST_STAND)
moneyLog = {}
playerStates[1].isDead = true
assert(coroutine.resume(watchdogCo))
eq(#callbacks['clay-busking:getAll'](), 0, 'watchdog closes spot when Player(src).state.isDead is true')
eq(moneyLog[1].amount, 60, 'watchdog pays 60 on state.isDead')
playerStates[1].isDead = false

print('server_test OK')
