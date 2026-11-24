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
