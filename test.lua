function r()
  norns.script.load(norns.state.script)
end
--norns.script.load('/home/we/dust/code/nest_/test.lua')

include 'lib/nest_/norns'
tab = require 'tabutil'

include 'lib/nest_/grid'

n = nest_ {
    v = _grid.value {
        z = 2,
        x = function() return { 1, 16 } end,
        y = 1,
        action = function(s, v) print(v) end
    },
    m = _grid.toggle {
        z = 3,
        count = { 2, 3 },
        x = { 1, 16 },
        --x = 1,
        y = { 2, 8 },
        --y = 2,
        --action = function(s, v) print(v) end
    }
} :connect { g = grid.connect() }
