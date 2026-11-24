local KEY_INTERACT = 38 -- E

---@type table<string, { state: table, coordsVec: vector3, rev: integer, isMine: boolean, entity: integer, spawnPoint: table?, interactPoint: table?, visualPoint: table?, inSpawnRange: boolean, spawning: boolean }>
local spots = {}
local inSpawnCount = 0
local hudLoopRunning = false
local ownerMonitorSpotId = nil

local cachedCid = nil
local openSpotId = nil
local openModalMode = nil
local placing = false
local promptSpotId = nil
local promptText = nil
local promptDist = math.huge
local lastHudId = nil
local lastHudRev = -1
local ensureOwnerMonitor

local function refreshCachedCid(playerData)
    local pd = playerData
    if type(pd) ~= 'table' then
        pd = exports.qbx_core:GetPlayerData()
    end
    cachedCid = pd and pd.citizenid or nil
    for id, entry in pairs(spots) do
        entry.isMine = cachedCid ~= nil and entry.state.ownerCid == cachedCid
        if entry.isMine and ensureOwnerMonitor then
            ensureOwnerMonitor(id)
        end
    end
end

local function myCitizenId()
    if cachedCid == nil and LocalPlayer.state.isLoggedIn then
        refreshCachedCid()
    end
    return cachedCid
end

local function isOwner(st)
    local cid = myCitizenId()
    return cid ~= nil and st.ownerCid == cid
end

local function isDeadNow()
    return IsEntityDead(cache.ped) or LocalPlayer.state.isDead == true
end

local function setPrompt(spotId, text, dist)
    if spotId == promptSpotId and text == promptText then
        if text and dist then promptDist = dist end
        return
    end
    promptSpotId = text and spotId or nil
    promptText = text
    promptDist = (text and dist) or math.huge
    if text then
        lib.showTextUI(text)
    else
        lib.hideTextUI()
    end
end

local function toUiSpot(st)
    if not st then return nil end
    return {
        id = st.id,
        total = st.total or 0,
        top3 = st.top3 or {},
    }
end

local function refreshHud(force)
    local pCoords = GetEntityCoords(cache.ped)
    local hudRadius = Config.HudRadius or 10.0
    local bestEntry, bestDist = nil, math.huge

    for id, entry in pairs(spots) do
        local dist = #(pCoords - entry.coordsVec)
        if dist <= hudRadius then
            if dist < bestDist or (dist == bestDist and (not bestEntry or id < bestEntry.state.id)) then
                bestDist = dist
                bestEntry = entry
            end
        end
    end

    local nextId = bestEntry and bestEntry.state.id or nil
    local nextRev = bestEntry and bestEntry.rev or 0
    if not force and nextId == lastHudId and nextRev == lastHudRev then return end
    lastHudId = nextId
    lastHudRev = nextRev
    SendNUIMessage({
        action = 'hud',
        spot = bestEntry and toUiSpot(bestEntry.state) or nil,
        ui = Config.Ui,
    })
end

local function despawnEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    DeleteEntity(entity)
end

local function ensureHudLoop()
    if hudLoopRunning then return end
    hudLoopRunning = true
    CreateThread(function()
        local despawnDist = (Config.PropSpawnDistance or 60.0) + 5.0
        while inSpawnCount > 0 do
            local pCoords = GetEntityCoords(cache.ped)
            for id, entry in pairs(spots) do
                if entry.inSpawnRange and #(pCoords - entry.coordsVec) > despawnDist then
                    entry.inSpawnRange = false
                    inSpawnCount = math.max(0, inSpawnCount - 1)
                    if promptSpotId == id then setPrompt(nil) end
                    despawnEntity(entry.entity)
                    entry.entity = 0
                end
            end
            refreshHud(false)
            if inSpawnCount <= 0 then break end
            Wait(250)
        end
        hudLoopRunning = false
        refreshHud(false)
    end)
end

local function closeModal()
    if not openSpotId then return end
    openSpotId = nil
    openModalMode = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeModal' })
end

local function openModal(spotId)
    local entry = spots[spotId]
    if not entry then return end
    if openSpotId then closeModal() end

    setPrompt(nil)
    openSpotId = spotId
    openModalMode = entry.isMine and 'collect' or 'tip'
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openModal',
        mode = openModalMode,
        spot = toUiSpot(entry.state),
        ui = Config.Ui,
        limits = { minTip = Config.MinTip, maxTip = Config.MaxTip },
    })

    CreateThread(function()
        local maxDist = (Config.InteractDistance or 2.2) + 2.0
        while openSpotId == spotId do
            local e = spots[spotId]
            if not e or isDeadNow() then
                closeModal()
                break
            end
            if #(GetEntityCoords(cache.ped) - e.coordsVec) > maxDist then
                closeModal()
                break
            end
            Wait(400)
        end
    end)
end

ensureOwnerMonitor = function(spotId)
    if ownerMonitorSpotId == spotId then return end
    ownerMonitorSpotId = spotId
    CreateThread(function()
        local maxDist = Config.AutoEndRadius or 14.0
        while ownerMonitorSpotId == spotId do
            local entry = spots[spotId]
            if not entry or not entry.isMine then
                ownerMonitorSpotId = nil
                break
            end
            local outOfRange = #(GetEntityCoords(cache.ped) - entry.coordsVec) > maxDist
            if outOfRange or isDeadNow() then
                TriggerServerEvent('clay-busking:ownerLeft', spotId)
                Wait(1500)
            else
                Wait(500)
            end
        end
    end)
end

local function ensureProp(entry)
    if entry.spawning or not entry.inSpawnRange then return end
    if entry.entity ~= 0 and DoesEntityExist(entry.entity) then return end

    entry.spawning = true
    CreateThread(function()
        local model = joaat(Config.PropModel)
        local ok, loaded = pcall(lib.requestModel, model, 5000)
        entry.spawning = false
        if not ok or not loaded then return end

        if spots[entry.state.id] ~= entry or not entry.inSpawnRange then
            SetModelAsNoLongerNeeded(model)
            return
        end

        local c = entry.state.coords
        local obj = CreateObject(model, c.x, c.y, c.z + (Config.PropZOffset or 0.0), false, false, false)
        SetModelAsNoLongerNeeded(model)
        if obj == 0 then return end

        SetEntityHeading(obj, entry.state.heading or 0.0)
        PlaceObjectOnGroundProperly(obj)
        FreezeEntityPosition(obj, true)
        SetEntityAsMissionEntity(obj, true, false)
        entry.entity = obj
    end)
end

local function drawOptionalVisuals(entry, dist)
    local c = entry.state.coords
    if Config.ShowZoneMarker and dist <= ((Config.HudRadius or 10.0) + 12.0) then
        local diameter = (Config.HudRadius or 10.0) * 2.0
        DrawMarker(25, c.x, c.y, c.z + 0.04, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, diameter, diameter, 1.0, 74, 222, 128, 90, false, false, 2, false, nil, nil, false)
    end
    if Config.Show3DText and dist <= (Config.HudRadius or 10.0) then
        SetDrawOrigin(c.x, c.y, c.z + 0.45, 0)
        SetTextScale(0.32, 0.32)
        SetTextFont(4)
        SetTextCentre(true)
        SetTextOutline()
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName(('Tip $ %d'):format(entry.state.total or 0))
        EndTextCommandDisplayText(0.0, 0.0)
        ClearDrawOrigin()
    end
end

-- Two-tier spatial points: 60m spawnPoint has NO nearby() (0 per-frame calls at 2.2m-60m);
-- interactPoint runs nearby() ONLY inside InteractDistance without relying on global isClosest.
local function attachPoints(entry)
    local spotId = entry.state.id
    local coords = entry.coordsVec

    local spawnPoint = lib.points.new({
        coords = coords,
        distance = Config.PropSpawnDistance or 60.0,
    })

    function spawnPoint:onEnter()
        if spots[spotId] ~= entry then return end
        if not entry.inSpawnRange then
            entry.inSpawnRange = true
            inSpawnCount = inSpawnCount + 1
        end
        ensureProp(entry)
        ensureHudLoop()
        refreshHud(false)
    end

    function spawnPoint:onExit()
        if entry.inSpawnRange then
            entry.inSpawnRange = false
            inSpawnCount = math.max(0, inSpawnCount - 1)
        end
        if promptSpotId == spotId then setPrompt(nil) end
        despawnEntity(entry.entity)
        entry.entity = 0
        refreshHud(false)
    end

    local interactPoint = lib.points.new({
        coords = coords,
        distance = Config.InteractDistance or 2.2,
    })

    function interactPoint:onExit()
        if promptSpotId == spotId then setPrompt(nil) end
    end

    function interactPoint:nearby()
        if spots[spotId] ~= entry then return end

        local canInteract = not openSpotId
            and not placing
            and not cache.vehicle
            and not isDeadNow()

        if not canInteract then
            if promptSpotId == spotId then setPrompt(nil) end
            return
        end

        local dist = self.currentDistance or 0.0
        if promptSpotId and promptSpotId ~= spotId and dist >= promptDist then
            return
        end

        local prompt = entry.isMine and '[E] เก็บเงินเปิดหมวก' or '[E] ให้ทิปเปิดหมวก'
        setPrompt(spotId, prompt, dist)

        if IsControlJustReleased(0, KEY_INTERACT) then
            setPrompt(nil)
            openModal(spotId)
        end
    end

    entry.spawnPoint = spawnPoint
    entry.interactPoint = interactPoint

    if Config.ShowZoneMarker or Config.Show3DText then
        local visualPoint = lib.points.new({
            coords = coords,
            distance = (Config.HudRadius or 10.0) + 12.0,
        })
        function visualPoint:nearby()
            if spots[spotId] ~= entry then return end
            drawOptionalVisuals(entry, self.currentDistance or #(GetEntityCoords(cache.ped) - coords))
        end
        entry.visualPoint = visualPoint
    end
end

local function removePoints(entry)
    if entry.spawnPoint then entry.spawnPoint:remove() end
    if entry.interactPoint then entry.interactPoint:remove() end
    if entry.visualPoint then entry.visualPoint:remove() end
end

local function upsertSpot(snapshot)
    if type(snapshot) ~= 'table' or not snapshot.id then return end
    local entry = spots[snapshot.id]
    if entry then
        entry.state = snapshot
        entry.rev = entry.rev + 1
        entry.isMine = isOwner(snapshot)
        ensureProp(entry)
    else
        local c = snapshot.coords
        local coordsVec = vec3(c.x, c.y, c.z)
        local nearNow = #(GetEntityCoords(cache.ped) - coordsVec) <= (Config.PropSpawnDistance or 60.0)
        entry = {
            state = snapshot,
            coordsVec = coordsVec,
            rev = 1,
            isMine = isOwner(snapshot),
            entity = 0,
            spawnPoint = nil,
            interactPoint = nil,
            visualPoint = nil,
            inSpawnRange = nearNow,
            spawning = false,
        }
        spots[snapshot.id] = entry
        if nearNow then
            inSpawnCount = inSpawnCount + 1
            ensureProp(entry)
            ensureHudLoop()
        end
        attachPoints(entry)
    end

    if entry.isMine then
        ensureOwnerMonitor(snapshot.id)
    end

    refreshHud(false)
    if openSpotId == snapshot.id then
        SendNUIMessage({
            action = 'updateModal',
            spot = toUiSpot(snapshot),
        })
    end
end

local function removeSpot(spotId)
    local entry = spots[spotId]
    if not entry then return end
    spots[spotId] = nil
    if entry.inSpawnRange then
        entry.inSpawnRange = false
        inSpawnCount = math.max(0, inSpawnCount - 1)
    end
    removePoints(entry)
    if promptSpotId == spotId then setPrompt(nil) end
    despawnEntity(entry.entity)
    if openSpotId == spotId then closeModal() end
    if ownerMonitorSpotId == spotId then ownerMonitorSpotId = nil end
    refreshHud(false)
end

local function syncAllSpots()
    local list = lib.callback.await('clay-busking:getAll', false)
    if type(list) ~= 'table' then return end
    for _, snapshot in ipairs(list) do
        upsertSpot(snapshot)
    end
end

local function playTipFeedback()
    PlaySoundFrontend(-1, 'LOCAL_PLYR_CASH_COUNTER_COMPLETE', 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', false)
    CreateThread(function()
        local ok, loaded = pcall(lib.requestAnimDict, 'pickup_object', 2000)
        if ok and loaded then
            TaskPlayAnim(cache.ped, 'pickup_object', 'pickup_low', 4.0, -4.0, 700, 48, 0.0, false, false, false)
        end
    end)
end

-- ox_inventory item export: client = { export = 'clay-busking.useBuskingHat' }
exports('useBuskingHat', function()
    if placing or openSpotId or isDeadNow() then return end
    if cache.vehicle then
        return lib.notify({ type = 'error', description = 'ไม่สามารถวางหมวกขณะอยู่ในรถได้' })
    end
    if IsPedFalling(cache.ped) or IsPedSwimming(cache.ped) then
        return lib.notify({ type = 'error', description = 'ไม่สามารถวางหมวกในบริเวณนี้ได้' })
    end

    setPrompt(nil)
    placing = true
    CreateThread(function()
        local completed = lib.progressCircle({
            duration = Config.PlaceDurationMs or 1000,
            position = 'bottom',
            label = 'กำลังวางหมวกเปิดหมวก...',
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = { dict = 'amb@medic@standing@kneel@base', clip = 'base' },
        })
        placing = false
        if not completed then return end

        local ped = cache.ped
        local forward = GetOffsetFromEntityInWorldCoords(ped, 0.0, Config.PlaceDistance or 1.0, 0.0)
        local found, groundZ = GetGroundZFor_3dCoord(forward.x, forward.y, forward.z + 1.0, false)
        local placeZ = found and groundZ or forward.z
        local heading = (GetEntityHeading(ped) + 180.0) % 360.0

        local res = lib.callback.await('clay-busking:start', false, {
            x = forward.x,
            y = forward.y,
            z = placeZ,
        }, heading)

        if not res or not res.ok then
            return lib.notify({ type = 'error', description = (res and res.message) or 'วางหมวกเปิดหมวกไม่สำเร็จ' })
        end

        upsertSpot(res.spot)
    end)
end)

RegisterNetEvent('clay-busking:syncSpot', function(snapshot)
    upsertSpot(snapshot)
end)

RegisterNetEvent('clay-busking:removeSpot', function(spotId)
    removeSpot(spotId)
end)

RegisterNUICallback('ready', function(_, cb)
    refreshHud(true)
    cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
    closeModal()
    cb({ ok = true })
end)

RegisterNUICallback('tip', function(data, cb)
    local targetSpotId = openSpotId
    if not targetSpotId or type(data) ~= 'table' then
        return cb({ ok = false, message = 'ไม่พบจุดเปิดหมวกนี้' })
    end
    local amount = tonumber(data.amount)
    local res = lib.callback.await('clay-busking:tip', false, targetSpotId, amount)
    if res and res.ok then
        if openSpotId == targetSpotId then closeModal() end
        playTipFeedback()
        lib.notify({ type = 'success', description = ('คุณให้ทิป $%d เรียบร้อยแล้ว'):format(amount) })
        return cb({ ok = true })
    end
    cb({ ok = false, message = (res and res.message) or 'ให้ทิปไม่สำเร็จ' })
end)

RegisterNUICallback('collect', function(_, cb)
    local targetSpotId = openSpotId
    if not targetSpotId then
        return cb({ ok = false, message = 'ไม่พบจุดเปิดหมวกนี้' })
    end
    local res = lib.callback.await('clay-busking:collect', false, targetSpotId)
    if res and res.ok then
        if openSpotId == targetSpotId then closeModal() end
        return cb({ ok = true })
    end
    cb({ ok = false, message = (res and res.message) or 'รับเงินไม่สำเร็จ' })
end)

local function cleanupAll(pushHud)
    closeModal()
    setPrompt(nil)
    ownerMonitorSpotId = nil
    cachedCid = nil
    for id, entry in pairs(spots) do
        removePoints(entry)
        despawnEntity(entry.entity)
        spots[id] = nil
    end
    inSpawnCount = 0
    if pushHud then
        refreshHud(true)
    end
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    refreshCachedCid()
    syncAllSpots()
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(playerData)
    refreshCachedCid(playerData)
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    cleanupAll(true)
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if LocalPlayer.state.isLoggedIn then
        refreshCachedCid()
        syncAllSpots()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    cleanupAll(false)
end)
