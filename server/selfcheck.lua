if not Config.Debug then return end

local R = BuskingRules
assert(R.validateAmount(1, 1, 100) == 1, 'min edge')
assert(R.validateAmount(100.0, 1, 100) == 100, 'whole float edge')
assert(R.validateAmount(0, 1, 100) == nil, 'reject 0')
assert(R.validateAmount(-5, 1, 100) == nil, 'reject negative')
assert(R.validateAmount(10.5, 1, 100) == nil, 'reject decimal')
assert(R.validateAmount('10', 1, 100) == nil, 'reject string')
assert(R.validateAmount(0 / 0, 1, 100) == nil, 'reject NaN')
assert(R.validateAmount(math.huge, 1, 100) == nil, 'reject inf')

assert(R.isTooClose({ x = 5.0, y = 0.0, z = 0.0 }, { s = { coords = { x = 0.0, y = 0.0, z = 0.0 } } }, 6.0), 'too close')
assert(not R.isTooClose({ x = 6.0, y = 0.0, z = 0.0 }, { s = { coords = { x = 0.0, y = 0.0, z = 0.0 } } }, 6.0), 'exact boundary ok')

local s = { total = 0, donorSeq = 0, donors = {}, top3 = {} }
R.applyTip(s, 'a', 'A', 500)
R.applyTip(s, 'b', 'B', 500)
assert(s.total == 1000 and s.top3[1].name == 'A' and s.top3[2].name == 'B', 'top3 tie break')
assert(R.fullName({ firstname = 'John', lastname = 'Doe' }, 'x') == 'John Doe', 'fullName')

print('^2[clay-busking] selfcheck ok^7')
