BuskingRules = {}

---@param raw any
---@param minAmount integer
---@param maxAmount integer
---@return integer?
function BuskingRules.validateAmount(raw, minAmount, maxAmount)
    if type(raw) ~= 'number' then return nil end
    if raw ~= raw or math.abs(raw) == math.huge then return nil end
    if math.floor(raw) ~= raw then return nil end

    local n = math.tointeger(raw)
    if not n then return nil end
    if n < minAmount or n > maxAmount then return nil end
    return n
end

---@param coords { x: number, y: number, z: number }
---@param spots table<string, { coords: { x: number, y: number, z: number } }>
---@param minSpacing number
---@return boolean
function BuskingRules.isTooClose(coords, spots, minSpacing)
    local minSq = minSpacing * minSpacing
    for _, spot in pairs(spots) do
        local c = spot.coords
        local dx = coords.x - c.x
        local dy = coords.y - c.y
        local dz = coords.z - c.z
        if (dx * dx + dy * dy + dz * dz) < minSq then
            return true
        end
    end
    return false
end

---@param donors table<string, { name: string, amount: integer, order: integer }>
---@return { name: string, amount: integer }[]
function BuskingRules.computeTop3(donors)
    local list = {}
    for _, entry in pairs(donors) do
        list[#list + 1] = entry
    end

    table.sort(list, function(a, b)
        if a.amount ~= b.amount then
            return a.amount > b.amount
        end
        return a.order < b.order
    end)

    local top3 = {}
    local limit = math.min(3, #list)
    for i = 1, limit do
        top3[i] = {
            name = list[i].name,
            amount = list[i].amount,
        }
    end
    return top3
end

---@param spot { total: integer, donorSeq: integer, donors: table, top3: table }
---@param cid string
---@param name string
---@param amount integer
---@return integer, { name: string, amount: integer }[]
function BuskingRules.applyTip(spot, cid, name, amount)
    local donor = spot.donors[cid]
    if donor then
        donor.amount = donor.amount + amount
        donor.name = name
    else
        spot.donorSeq = (spot.donorSeq or 0) + 1
        spot.donors[cid] = {
            cid = cid,
            name = name,
            amount = amount,
            order = spot.donorSeq,
        }
    end

    spot.total = (spot.total or 0) + amount
    spot.top3 = BuskingRules.computeTop3(spot.donors)
    return spot.total, spot.top3
end

---@param s any
---@return string
local function trim(s)
    if type(s) ~= 'string' then return '' end
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

---@param charinfo table?
---@param fallback string?
---@return string
function BuskingRules.fullName(charinfo, fallback)
    if type(charinfo) == 'table' then
        local first = trim(charinfo.firstname)
        local last = trim(charinfo.lastname)
        if first ~= '' and last ~= '' then
            return first .. ' ' .. last
        elseif first ~= '' then
            return first
        elseif last ~= '' then
            return last
        end
    end
    return trim(fallback)
end
