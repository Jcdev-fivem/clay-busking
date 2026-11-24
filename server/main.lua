local qbx = exports.qbx_core
local ox = exports.ox_inventory
local Rules = BuskingRules

---@type table<string, table>
local spots = {}
---@type table<integer, boolean>
local playerBusy = {}
---@type table<string, boolean>
local spotBusy = {}
---@type table<integer, { ownerCid: string, total: integer }[]>
local pendingUnloadPayouts = {}
local spotSeq = 0

local function isFinite(n)
    return type(n) == 'number' and n == n and math.abs(n) ~= math.huge
end

local function withPlayerLock(src, fn)
    if playerBusy[src] then
        return { ok = false, reason = 'busy', message = 'กรุณารอสักครู่' }
    end
    playerBusy[src] = true
    local ok, res = pcall(fn)
    playerBusy[src] = nil
    if not ok then
        lib.print.error(res)
        return { ok = false, reason = 'error', message = 'เกิดข้อผิดพลาดในระบบ' }
    end
    return res
end

local function withSpotLock(spotId, fn)
    if spotBusy[spotId] then
        return { ok = false, reason = 'busy', message = 'จุดเปิดหมวกกำลังประมวลผล กรุณาลองใหม่' }
    end
    spotBusy[spotId] = true
    local ok, res = pcall(fn)
    spotBusy[spotId] = nil
    if not ok then
        lib.print.error(res)
        return { ok = false, reason = 'error', message = 'เกิดข้อผิดพลาดในระบบ' }
    end
    return res
end

local function serializeSpot(spot)
    return {
        id = spot.id,
        ownerCid = spot.ownerCid,
        coords = spot.coords,
        heading = spot.heading,
        total = spot.total,
        top3 = spot.top3,
    }
end

local function countOwnedSpots(cid)
    local count = 0
    for _, spot in pairs(spots) do
        if spot.ownerCid == cid then count = count + 1 end
    end
    return count
end

local function isPlayerAlive(src, player)
    local ped = GetPlayerPed(src)
    if ped == 0 or GetEntityHealth(ped) <= 0 then return false end
    local md = player and player.PlayerData and player.PlayerData.metadata
    if md and (md.isdead or md.inlaststand) then return false end
    return true
end

local function distanceToSpot(src, spot)
    local ped = GetPlayerPed(src)
    if ped == 0 then return math.huge end
    return #(GetEntityCoords(ped) - spot.coordsVec)
end

local function formatMoney(n)
    local s = tostring(math.floor(n))
    while true do
        local nextStr, k = s:gsub('^(%-?%d+)(%d%d%d)', '%1,%2')
        s = nextStr
        if k == 0 then break end
    end
    return s
end

-- Pop spot atomically under spot lock; callers pay out after lock release so yields never hold spotBusy.
local function popSpot(spotId)
    local popped = nil
    withSpotLock(spotId, function()
        popped = spots[spotId]
        if popped then
            spots[spotId] = nil
        end
    end)
    return popped
end

---@param spot table
---@param reasonTag string
---@param notifyOwner boolean
---@param restoreOnFail? boolean
---@return boolean paidOk, integer paidAmount
local function payoutSpot(spot, reasonTag, notifyOwner, restoreOnFail)
    -- shortcut: no SQL pending-payout table; abrupt host crash before onResourceStop loses uncollected session tips.
    local total = spot.total or 0
    if total <= 0 then
        TriggerClientEvent('clay-busking:removeSpot', -1, spot.id)
        if notifyOwner and qbx:GetPlayer(spot.ownerSrc) then
            qbx:Notify(spot.ownerSrc, 'เก็บหมวกเปิดหมวกแล้ว', 'inform')
        end
        return true, 0
    end

    local online = qbx:GetPlayer(spot.ownerSrc)
    if online and online.PlayerData and online.PlayerData.citizenid == spot.ownerCid then
        local paid = qbx:AddMoney(spot.ownerSrc, Config.Account, total, reasonTag)
        if not paid then
            if restoreOnFail and not spots[spot.id] then
                spots[spot.id] = spot
            else
                TriggerClientEvent('clay-busking:removeSpot', -1, spot.id)
            end
            lib.print.error(('[clay-busking] failed online payout cid=%s amount=%d reason=%s'):format(spot.ownerCid, total, reasonTag))
            return false, 0
        end
        TriggerClientEvent('clay-busking:removeSpot', -1, spot.id)
        if notifyOwner then
            qbx:Notify(spot.ownerSrc, ('คุณได้รับเงินจำนวน $%s จากการเปิดหมวก'):format(formatMoney(total)), 'success')
        end
        return true, total
    end

    TriggerClientEvent('clay-busking:removeSpot', -1, spot.id)
    -- Offline fallback uses bank so ox_inventory syncInventory never overwrites cash on next login.
    local paidOffline = qbx:AddMoney(spot.ownerCid, Config.OfflineFallbackAccount, total, 'clay-busking-offline')
    if not paidOffline then
        lib.print.error(('[clay-busking] failed offline payout cid=%s amount=%d'):format(spot.ownerCid, total))
        return false, 0
    end
    return true, total
end

local function queueUnloadPayout(src)
    local ids = {}
    for id, spot in pairs(spots) do
        if spot.ownerSrc == src then
            ids[#ids + 1] = id
        end
    end
    for _, id in ipairs(ids) do
        local spot = popSpot(id)
        if spot then
            TriggerClientEvent('clay-busking:removeSpot', -1, spot.id)
            if (spot.total or 0) > 0 then
                pendingUnloadPayouts[src] = pendingUnloadPayouts[src] or {}
                pendingUnloadPayouts[src][#pendingUnloadPayouts[src] + 1] = {
                    ownerCid = spot.ownerCid,
                    total = spot.total,
                }
            end
        end
    end
end

local function flushPendingUnload(src)
    local list = pendingUnloadPayouts[src]
    if not list then return end
    pendingUnloadPayouts[src] = nil
    for _, item in ipairs(list) do
        local paid = qbx:AddMoney(item.ownerCid, Config.OfflineFallbackAccount, item.total, 'clay-busking-offline')
        if not paid then
            lib.print.error(('[clay-busking] failed deferred offline payout cid=%s amount=%d'):format(item.ownerCid, item.total))
        end
    end
end

local function closeOwnedSpotsBySrc(src, reasonTag, notifyOwner)
    local ids = {}
    for id, spot in pairs(spots) do
        if spot.ownerSrc == src then
            ids[#ids + 1] = id
        end
    end
    for _, id in ipairs(ids) do
        local spot = popSpot(id)
        if spot then
            payoutSpot(spot, reasonTag, notifyOwner, false)
        end
    end
end

lib.callback.register('clay-busking:getAll', function()
    local list = {}
    for _, spot in pairs(spots) do
        list[#list + 1] = serializeSpot(spot)
    end
    return list
end)

lib.callback.register('clay-busking:start', function(src, targetCoords, heading)
    return withPlayerLock(src, function()
        local player = qbx:GetPlayer(src)
        if not player or not player.PlayerData then
            return { ok = false, reason = 'error', message = 'ไม่พบข้อมูลผู้เล่น' }
        end

        local cid = player.PlayerData.citizenid
        if ox:GetItemCount(src, Config.ItemName) < 1 then
            return { ok = false, reason = 'no_item', message = 'คุณไม่มีหมวกเปิดหมวกในกระเป๋า' }
        end

        if not isPlayerAlive(src, player) then
            return { ok = false, reason = 'dead', message = 'ไม่สามารถเปิดหมวกได้ในขณะนี้' }
        end

        local ped = GetPlayerPed(src)
        if GetVehiclePedIsIn(ped, false) ~= 0 then
            return { ok = false, reason = 'in_vehicle', message = 'ไม่สามารถวางหมวกขณะอยู่ในรถได้' }
        end

        if countOwnedSpots(cid) >= (Config.MaxSpotsPerPlayer or 1) then
            return { ok = false, reason = 'already_active', message = 'คุณกำลังเปิดหมวกอยู่แล้ว' }
        end

        if type(targetCoords) ~= 'table' or not isFinite(targetCoords.x) or not isFinite(targetCoords.y) or not isFinite(targetCoords.z) then
            return { ok = false, reason = 'invalid_coords', message = 'ตำแหน่งวางไม่ถูกต้อง' }
        end

        local coords = { x = targetCoords.x, y = targetCoords.y, z = targetCoords.z }
        local coordsVec = vector3(coords.x, coords.y, coords.z)
        local pCoords = GetEntityCoords(ped)
        if #(pCoords - coordsVec) > 4.0 then
            return { ok = false, reason = 'too_far', message = 'ตำแหน่งวางไกลเกินไป' }
        end

        if Rules.isTooClose(coords, spots, Config.MinSpotSpacing) then
            return { ok = false, reason = 'too_close', message = 'อยู่ใกล้จุดเปิดหมวกอื่นเกินไป' }
        end

        spotSeq = spotSeq + 1
        local id = ('busk_%d'):format(spotSeq)
        local cleanHeading = isFinite(heading) and (heading % 360.0) or 0.0
        local spot = {
            id = id,
            ownerCid = cid,
            ownerSrc = src,
            ownerName = Rules.fullName(player.PlayerData.charinfo, GetPlayerName(src)),
            coords = coords,
            coordsVec = coordsVec,
            heading = cleanHeading,
            total = 0,
            donorSeq = 0,
            donors = {},
            top3 = {},
        }
        spots[id] = spot

        local snap = serializeSpot(spot)
        -- shortcut: broadcast to all clients (-1); payload is small and only fires on start/tip/close.
        TriggerClientEvent('clay-busking:syncSpot', -1, snap)
        return { ok = true, spot = snap }
    end)
end)

lib.callback.register('clay-busking:tip', function(src, spotId, rawAmount)
    if type(spotId) ~= 'string' then
        return { ok = false, reason = 'not_found', message = 'ไม่พบจุดเปิดหมวกนี้' }
    end

    return withPlayerLock(src, function()
        local amount = Rules.validateAmount(rawAmount, Config.MinTip, Config.MaxTip)
        if not amount then
            return { ok = false, reason = 'invalid_amount', message = 'จำนวนเงินไม่ถูกต้อง' }
        end

        return withSpotLock(spotId, function()
            local spot = spots[spotId]
            if not spot then
                return { ok = false, reason = 'not_found', message = 'จุดเปิดหมวกถูกปิดไปแล้ว' }
            end

            local player = qbx:GetPlayer(src)
            if not player or not player.PlayerData then
                return { ok = false, reason = 'error', message = 'ไม่พบข้อมูลผู้เล่น' }
            end

            local tipperCid = player.PlayerData.citizenid
            if tipperCid == spot.ownerCid then
                return { ok = false, reason = 'self_tip', message = 'ไม่สามารถทิปหมวกของตัวเองได้' }
            end

            if not isPlayerAlive(src, player) then
                return { ok = false, reason = 'dead', message = 'ไม่สามารถให้ทิปได้ในขณะนี้' }
            end

            local ped = GetPlayerPed(src)
            if GetVehiclePedIsIn(ped, false) ~= 0 then
                return { ok = false, reason = 'in_vehicle', message = 'ไม่สามารถให้ทิปขณะอยู่ในรถได้' }
            end

            if distanceToSpot(src, spot) > (Config.InteractDistance + 2.0) then
                return { ok = false, reason = 'too_far', message = 'อยู่ไกลจากหมวกเปิดหมวกเกินไป' }
            end

            -- Balance check with zero yield before RemoveMoney (QBox GetPlayer returns a copy).
            local balance = (player.PlayerData.money and player.PlayerData.money[Config.Account]) or 0
            if balance < amount then
                return { ok = false, reason = 'no_money', message = 'เงินไม่เพียงพอ' }
            end

            if not qbx:RemoveMoney(src, Config.Account, amount, 'clay-busking-tip') then
                return { ok = false, reason = 'no_money', message = 'หักเงินไม่สำเร็จ' }
            end

            local tipperName = Rules.fullName(player.PlayerData.charinfo, GetPlayerName(src))
            Rules.applyTip(spot, tipperCid, tipperName, amount)

            local snap = serializeSpot(spot)
            TriggerClientEvent('clay-busking:syncSpot', -1, snap)
            return { ok = true, spot = snap }
        end)
    end)
end)

lib.callback.register('clay-busking:collect', function(src, spotId)
    if type(spotId) ~= 'string' then
        return { ok = false, reason = 'not_found', message = 'ไม่พบจุดเปิดหมวกนี้' }
    end

    local popped = nil
    local errRes = withPlayerLock(src, function()
        return withSpotLock(spotId, function()
            local spot = spots[spotId]
            if not spot then
                return { ok = false, reason = 'not_found', message = 'จุดเปิดหมวกถูกปิดไปแล้ว' }
            end

            local player = qbx:GetPlayer(src)
            if not player or not player.PlayerData then
                return { ok = false, reason = 'error', message = 'ไม่พบข้อมูลผู้เล่น' }
            end

            if player.PlayerData.citizenid ~= spot.ownerCid then
                return { ok = false, reason = 'not_owner', message = 'เฉพาะเจ้าของหมวกเท่านั้นที่รับเงินได้' }
            end

            if distanceToSpot(src, spot) > (Config.InteractDistance + 2.0) then
                return { ok = false, reason = 'too_far', message = 'อยู่ไกลจากหมวกเปิดหมวกเกินไป' }
            end

            spots[spotId] = nil
            popped = spot
            return { ok = true }
        end)
    end)

    if not popped then
        return errRes
    end

    local paidOk, paid = payoutSpot(popped, 'clay-busking-collect', true, true)
    if not paidOk then
        return { ok = false, reason = 'payout_failed', message = 'จ่ายเงินไม่สำเร็จ กรุณาลองใหม่หรือติดต่อแอดมิน' }
    end
    return { ok = true, total = paid }
end)

RegisterNetEvent('clay-busking:ownerLeft', function(spotId)
    local src = source
    if type(spotId) ~= 'string' then return end

    local popped = nil
    withSpotLock(spotId, function()
        local spot = spots[spotId]
        if not spot or spot.ownerSrc ~= src then return end

        local player = qbx:GetPlayer(src)
        local dead = not isPlayerAlive(src, player)
        local far = distanceToSpot(src, spot) > Config.AutoEndRadius
        if not dead and not far then return end

        spots[spotId] = nil
        popped = spot
    end)

    if popped then
        payoutSpot(popped, 'clay-busking-auto', true)
    end
end)

-- qbx_core Logout() saves to MySQL BEFORE OnPlayerUnload and clears QBX.Players[src] before playerLoggedOut.
-- Pop spots immediately to block late tips, then pay via offline bank fallback once unregistered.
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    queueUnloadPayout(src)
end)

AddEventHandler('qbx_core:server:playerLoggedOut', function(src)
    flushPendingUnload(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    playerBusy[src] = nil
    if qbx:GetPlayer(src) == nil then
        flushPendingUnload(src)
        closeOwnedSpotsBySrc(src, 'clay-busking-auto', false)
    else
        -- If playerDropped fires during Logout's 200ms window, defer flush until player is unregistered.
        queueUnloadPayout(src)
        CreateThread(function()
            Wait(300)
            flushPendingUnload(src)
        end)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for src in pairs(pendingUnloadPayouts) do
        flushPendingUnload(src)
    end
    local ids = {}
    for id in pairs(spots) do
        ids[#ids + 1] = id
    end
    for _, id in ipairs(ids) do
        local spot = popSpot(id)
        if spot then
            payoutSpot(spot, 'clay-busking-auto', false)
        end
    end
end)

-- Authoritative server watchdog enforcing auto-end when owner moves too far, dies, or vanishes.
-- Uses ped + server-side Player(src).state.isDead (set by qbx_medical for DEAD and LAST_STAND)
-- to avoid copying full PlayerData across exports every 2s per active spot.
CreateThread(function()
    local interval = Config.ServerWatchdogMs or 2000
    while true do
        Wait(interval)
        if next(spots) ~= nil then
            local toClose = {}
            local limit = (Config.AutoEndRadius or 14.0) + 2.0
            for id, spot in pairs(spots) do
                local ped = GetPlayerPed(spot.ownerSrc)
                local deadOrMissing = ped == 0
                    or GetEntityHealth(ped) <= 0
                    or (Player and Player(spot.ownerSrc).state.isDead == true)
                if deadOrMissing or #(GetEntityCoords(ped) - spot.coordsVec) > limit then
                    toClose[#toClose + 1] = id
                end
            end
            for _, id in ipairs(toClose) do
                local spot = popSpot(id)
                if spot then
                    payoutSpot(spot, 'clay-busking-auto', true)
                end
            end
        end
    end
end)
