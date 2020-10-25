local tab = require 'tabutil'

_grid = _device:new()
_grid.devk = 'g'

_grid.control = _control:new {
    v = 0,
    x = 1,
    y = 1,
    lvl = 15,
    input = _input:new(),
    output = _output:new()
}

local input_contained = function(s, inargs)
    local contained = { x = false, y = false }
    local axis_size = { x = nil, y = nil }

    local args = { x = inargs[1], y = inargs[2] }

    for i,v in ipairs{"x", "y"} do
        if type(s.p_[v]) == "table" then
            if #s.p_[v] == 1 then
                s[v] = s.p_[v][1]
                if s.p_[v] == args[v] then
                    contained[v] = true
                end
            elseif #s.p_[v] == 2 then
                if  s.p_[v][1] <= args[v] and args[v] <= s.p_[v][2] then
                    contained[v] = true
                end
                axis_size[v] = s.p_[v][2] - s.p_[v][1] + 1
            end
        else
            if s.p_[v] == args[v] then
                contained[v] = true
            end
        end
    end

    return contained.x and contained.y, axis_size
end

_grid.control.input.filter = function(s, args)
    if input_contained(s, args) then
        return args
    else return nil end
end

_grid.metacontrol = _metacontrol:new {
    v = 0,
    x = 1,
    y = 1,
    lvl = 15,
    input = _input:new(),
    output = _output:new()
}

_grid.muxcontrol = _grid.control:new()

-- update -> filter -> handler -> muxhandler -> action -> v

_grid.muxcontrol.input.muxhandler = _obj_:new {
    point = { function(s, z) end },
    line = { function(s, v, z) end },
    plane = { function(s, x, y, z) end }
}

_grid.muxcontrol.input.handler = function(s, k, ...)
    return s.muxhandler[k](s, ...)
end

_grid.muxcontrol.input.filter = function(s, args)
    local contained, axis_size = input_contained(s, args)

    if contained then
        if axis_size.x == nil and axis_size.y == nil then
            return { "point", args[1], args[2], args[3] }
        elseif axis_size.x ~= nil and axis_size.y ~= nil then
            return { "plane", args[1], args[2], args[3] }
        else
            if axis_size.x ~= nil then
                return { "line", args[1], args[2], args[3] }
            elseif axis_size.y ~= nil then
                return { "line", args[2], args[1], args[3] }
            end
        end
    else return nil end
end

_grid.muxcontrol.output.muxredraw = _obj_:new {
    point = function(s) end,
    line_x = function(s) end,
    line_y = function(s) end,
    plane = function(s) end
}

_grid.muxcontrol.output.redraw = function(s, g, v)
    local has_axis = { x = false, y = false }

    for i,v in ipairs{"x", "y"} do
        if type(s.p_[v]) == "table" then
            if #s.p_[v] == 1 then
            elseif #s.p_[v] == 2 then
                has_axis[v] = true
            end
        end
    end

    if has_axis.x == false and has_axis.y == false then
        return s.muxredraw.point(s, g, v)
    elseif has_axis.x and has_axis.y then
        return s.muxredraw.plane(s, g, v)
    else
        if has_axis.x then
            return s.muxredraw.line_x(s, g, v)
        elseif has_axis.y then
            return s.muxredraw.line_y(s, g, v)
        end
    end
end

_grid.muxmetacntrl = _grid.metacontrol:new {
    input = _grid.muxcontrol.input:new(),
    output = _grid.muxcontrol.output:new()
}

_grid.binary = _grid.muxcontrol:new({ count = nil, fingers = nil }) -- local supertype for binary, toggle, trigger

local function minit(axis) 
    local v
    if axis.x and axis.y then 
        v = {}
        for x = 1, axis.x do 
            v[x] = {}
            for y = 1, axis.y do
                v[x][y] = 0
            end
        end
    elseif axis.x or axis.y then
        v = {}
        for x = 1, (axis.x or axis.y) do 
            v[x] = 0
        end
    else 
        v = 0
    end

    return v
end

_grid.binary.new = function(self, o) 
    o = _grid.muxcontrol.new(self, o)

    rawset(o, 'list', {})

    local _, axis = input_contained(o, { -1, -1 })

    local v = minit(axis)
    o.held = minit(axis)
    o.tdown = minit(axis)
    o.tlast = minit(axis)
    o.theld = minit(axis)
    o.vinit = minit(axis)

    if type(o.v) ~= 'table' or type(o.v) == 'table' and #o.v ~= #v then o.v = v end
    
    return o
end

_grid.binary.input.muxhandler = _obj_:new {
    point = function(s, x, y, z, min, max, wrap)
        if z > 0 then 
            s.tlast = s.tdown
            s.tdown = util.time()
        else s.theld = util.time() - s.tdown end
        return z, s.theld
    end,
    line = function(s, x, y, z, min, max, wrap)
        local i = x - s.p_.x[1] + 1
        local add
        local rem

        if z > 0 then
            add = i
            s.tlast[i] = s.tdown[i]
            s.tdown[i] = util.time()
            table.insert(s.list, i)
            if wrap and #s.list > wrap then rem = table.remove(s.list, 1) end
        else
            local k = tab.key(s.list, i)
            if k then
                rem = table.remove(s.list, k)
            end
            s.theld[i] = util.time() - s.tdown[i]
        end
        
        if add then s.held[add] = 1 end
        if rem then s.held[rem] = 0 end

        return (#s.list >= min and (max == nil or #s.list <= max)) and s.held or s.vinit, add, rem, s.theld, s.list
    end,
    plane = function(s, x, y, z, min, max, wrap)
        local i = { x = x - s.p_.x[1] + 1, y = y - s.p_.y[1] + 1 }
        local add
        local rem

        if z > 0 then
            add = i
            s.tlast[i.x][i.y] = s.tdown[i.x][i.y]
            s.tdown[i.x][i.y] = util.time()
            table.insert(s.list, i)
            if wrap and (#s.list > wrap) then rem = table.remove(s.list, 1) end
        else
            rem = i
            for j,w in ipairs(s.list) do
                if w.x == i.x and w.y == i.y then 
                    rem = table.remove(s.list, j)
                end
            end
            s.theld[i.x][i.y] = util.time() - s.tdown[i.x][i.y]
        end

        if add then s.held[add.x][add.y] = 1 end
        if rem then s.held[rem.x][rem.y] = 0 end

        return (#s.list >= min and (max == nil or #s.list <= max)) and s.held or s.vinit, add, rem, s.theld, s.list
    end
}

local lvl = function(s, i)
    local x = s.p_.lvl
    -- come back later and understand or not understand ? :)
    return (type(x) ~= 'table') and ((i > 0) and x or 0) or x[i + 1] or 15
end

_grid.binary.output.muxredraw = _obj_:new {
    point = function(s, g, v)
        local lvl = lvl(s, v)
        if lvl > 0 then g:led(s.p_.x, s.p_.y, lvl) end
    end,
    line_x = function(s, g, v)
        for x,l in ipairs(v) do 
            local lvl = lvl(s, l)
            if lvl > 0 then g:led(x + s.p_.x[1] - 1, s.p_.y, lvl) end
        end
    end,
    line_y = function(s, g, v)
        for y,l in ipairs(v) do 
            local lvl = lvl(s, l)
            if lvl > 0 then g:led(s.p_.x, y + s.p_.y[1] - 1, lvl) end
        end
    end,
    plane = function(s, g, v)
        for x,r in ipairs(v) do 
            for y,l in ipairs(r) do 
                local lvl = lvl(s, l)
                if lvl > 0 then g:led(x + s.p_.x[1] - 1, y + s.p_.y[1] - 1, lvl) end
            end
        end
    end
}

_grid.momentary = _grid.binary:new()

local function count(s) 
    local min = 0
    local max = nil

    if type(s.p_.count) == "table" then 
        max = s.p_.count[#s.p_.count]
        min = #s.p_.count > 1 and s.p_.count[1] or 0
    else max = s.p_.count end

    return min, max
end

local function fingers(s)
    local min = 0
    local max = nil

    if type(s.p_.fingers) == "table" then 
        max = s.p_.fingers[#s.p_.fingers]
        min = #s.p_.fingers > 1 and s.p_.fingers[1] or 0
    else max = s.p_.fingers end

    return min, max
end

_grid.momentary.input.muxhandler = _obj_:new {
    point = function(s, x, y, z)
        local max
        local min, wrap = count(s)
        if s.fingers then
            min, max = fingers(s)
        end        

        return _grid.binary.input.muxhandler.point(s, x, y, z, min, max, wrap)
    end,
    line = function(s, x, y, z)
        local max
        local min, wrap = count(s)
        if s.fingers then
            min, max = fingers(s)
        end        

        return _grid.binary.input.muxhandler.line(s, x, y, z, min, max, wrap)
    end,
    plane = function(s, x, y, z)
        local max
        local min, wrap = count(s)
        if s.fingers then
            min, max = fingers(s)
        end        

        return _grid.binary.input.muxhandler.plane(s, x, y, z, min, max, wrap)
    end
}

_grid.toggle = _grid.binary:new { edge = 1 }

_grid.toggle.new = function(self, o) 
    o = _grid.binary.new(self, o)

    rawset(o, 'toglist', {})

    local _, axis = input_contained(o, { -1, -1 })

    --o.tog = minit(axis)
    o.ttog = minit(axis)
    
    return o
end

local function toggle(s, v)
    return (v + 1) % (((type(s.lvl) == 'table') and #s.lvl > 1) and (#s.lvl) or 2)
end

_grid.toggle.input.muxhandler = _obj_:new {
    point = function(s, x, y, z)
        local held = _grid.binary.input.muxhandler.point(s, x, y, z)

        if s.edge == held then
            return toggle(s, s.v), util.time() - s.tlast, s.theld
        end
    end,
    line = function(s, x, y, z)
        local held, hadd, hrem, theld, hlist = _grid.binary.input.muxhandler.line(s, x, y, z, fingers(s))
        local min, max = count(s)
        local i
        local add
        local rem
       
        if s.edge == 1 and hadd then i = hadd end
        if s.edge == 0 and hrem then i = hrem end
 
        if i then   
            if #s.toglist >= min then
                local v = toggle(s, s.v[i])
                print(v, s.v[i]) 
                
                if v > 0 then
                    add = i
                    
                    if v == 1 then table.insert(s.toglist, i) end
                    if max and #s.toglist > max then rem = table.remove(s.toglist, 1) end
                else 
                    local k = tab.key(s.toglist, i)
                    if k then
                        rem = table.remove(s.toglist, k)
                    end
                end
            
                s.ttog[i] = util.time() - s.tlast[i]

                if add then s.v[add] = v end
                if rem then s.v[rem] = 0 end

            elseif #hlist >= min then
                for j,w in ipairs(hlist) do
                    s.toglist[j] = w
                    s.v[w] = 1
                end
            end
            
            if #s.toglist < min then
                for j,w in ipairs(s.v) do s.v[j] = 0 end
                s.toglist = {}
            end

            return s.v, add, rem, s.ttog, theld, s.toglist
        end
    end,
    plane = function(s, x, y, z)
        local held, hadd, hrem, theld, hlist = _grid.binary.input.muxhandler.plane(s, x, y, z, fingers(s))
        local min, max = count(s)
        local i
        local add
        local rem
       
        if s.edge == 1 and hadd then i = hadd end
        if s.edge == 0 and hrem then i = hrem end
        
        if i then   
            if #s.toglist >= min then
                local v = toggle(s, s.v[i.x][i.y])
                
                if v > 0 then
                    add = i
                    
                    if v == 1 then table.insert(s.toglist, i) end
                    if max and #s.toglist > max then rem = table.remove(s.toglist, 1) end
                else 
                    for j,w in ipairs(s.toglist) do
                        if w.x == i.x and w.y == i.y then 
                            rem = table.remove(s.toglist, j)
                        end
                    end
                end
            
                s.ttog[i.x][i.y] = util.time() - s.tlast[i.x][i.y]

                if add then s.v[add.x][add.y] = v end
                if rem then s.v[rem.x][rem.y] = 0 end

            elseif #hlist >= min then
                for j,w in ipairs(hlist) do
                    s.toglist[j] = w
                    s.v[w.x][w.y] = 1
                end
            end

            if #s.toglist < min then
                for x,w in ipairs(s.v) do 
                    for y,_ in ipairs(w) do
                        s.v[x][y] = 0
                    end
                end
                s.toglist = {}
            end

            return s.v, add, rem, s.ttog, theld, s.toglist
        end
    end
}

_grid.trigger = _grid.binary:new { edge = 1, blinktime = 0.1 }

_grid.trigger.new = function(self, o) 
    o = _grid.binary.new(self, o)

    rawset(o, 'triglist', {})

    local _, axis = input_contained(o, { -1, -1 })
    o.tdelta = minit(axis)
    
    return o
end

_grid.trigger.input.muxhandler = _obj_:new {
    point = function(s, x, y, z)
        local held = _grid.binary.input.muxhandler.point(s, x, y, z)
        
        if s.edge == held then
            return 1, util.time() - s.tlast, s.theld
        end
    end,
    line = function(s, x, y, z)
        local held, hadd, hrem, theld, hlist = _grid.binary.input.muxhandler.line(s, x, y, z, fingers(s))
        local min, max = count(s) --------
        local ret = false
        local lret

        if s.edge == 1 and #hlist > min and hadd then
            s.v[hadd] = 1
            s.tdelta[hadd] = util.time() - s.tlast[hadd]

            ret = true
            lret = hlist
        elseif s.edge == 1 and #hlist == min and hadd then
            for i,w in ipairs(hlist) do 
                s.v[w] = 1

                s.tdelta[w] = util.time() - s.tlast[w]
            end

            ret = true
            lret = hlist
        elseif s.edge == 0 and #hlist >= min - 1 and hrem and not hadd then
            s.triglist = {}

            for i,w in ipairs(hlist) do 
                if s.v[w] <= 0 then
                    s.v[w] = 1
                    s.tdelta[w] = util.time() - s.tlast[w]
                    table.insert(s.triglist, w)
                end
            end
            
            if s.v[hrem] <= 0 then
                ret = true
                lret = s.triglist
                s.v[hrem] = 1 
                s.tdelta[hrem] = util.time() - s.tlast[hrem]
                table.insert(s.triglist, hrem)
            end
        end
            
        if ret then return s.v, s.tdelta, s.theld, lret end
    end,
    plane = function(s, x, y, z)
        local held, hadd, hrem, theld, hlist = _grid.binary.input.muxhandler.plane(s, x, y, z, fingers(s))
        local min, max = count(s) ---------
        local ret = false
        local lret

        if s.edge == 1 and #hlist > min and hadd then
            s.v[hadd.x][hadd.y] = 1
            s.tdelta[hadd.x][hadd.y] = util.time() - s.tlast[hadd.x][hadd.y]

            ret = true
            lret = hlist
        elseif s.edge == 1 and #hlist == min and hadd then
            for i,w in ipairs(hlist) do 
                s.v[w.x][w.y] = 1

                s.tdelta[w.x][w.y] = util.time() - s.tlast[w.x][w.y]
            end

            ret = true
            lret = hlist
        elseif s.edge == 0 and #hlist >= min - 1 and hrem and not hadd then
            s.triglist = {}

            for i,w in ipairs(hlist) do 
                if s.v[w.x][w.y] <= 0 then
                    s.v[w.x][w.y] = 1
                    s.tdelta[w.x][w.y] = util.time() - s.tlast[w.x][w.y]
                    table.insert(s.triglist, w)
                end
            end
            
            if s.v[hrem.x][hrem.y] <= 0 then
                ret = true
                lret = s.triglist
                s.v[hrem.x][hrem.y] = 1 
                s.tdelta[hrem.x][hrem.y] = util.time() - s.tlast[hrem.x][hrem.y]
                table.insert(s.triglist, hrem)
            end
        end
            
        if ret then return s.v, s.tdelta, s.theld, lret end
    end
}

_grid.trigger.output.muxredraw = _obj_:new {
    point = function(s, g, v)
        local l = lvl(s, 0)
        if v > 0 then
            s.v = v - 1/30/s.blinktime
            l = lvl(s, s.v > 0 and 1 or 0)
        else
            s.v = 0
        end
        
        if l > 0 then g:led(s.p_.x, s.p_.y, l) end
        
        return s.v > 0
    end,
    line_x = function(s, g, v)
        local ret = false

        for x,w in ipairs(v) do 
            local l = lvl(s, 0)
            if w > 0 then 
                s.v[x] = w - 1/30/s.blinktime
                l = lvl(s, s.v[x] > 0 and 1 or 0)
            else
                s.v[x] = 0
            end
            
            if l > 0 then g:led(x + s.p_.x[1] - 1, s.p_.y, l) end
            ret = true
        end

        return ret
    end,
    line_y = function(s, g, v)
        local ret = false

        for x,w in ipairs(v) do 
            local l = lvl(s, 0)
            if w > 0 then 
                s.v[x] = w - 1/30/s.blinktime
                l = lvl(s, s.v[x] > 0 and 1 or 0)
            else
                s.v[x] = 0
            end
            
            if l > 0 then g:led(s.p_.x, y + s.p_.y[1] - 1, l) end
            ret = true
        end

        return ret
    end,
    plane = function(s, g, v)
        local ret = false

        for x,r in ipairs(v) do 
            for y,w in ipairs(r) do 
                local l = lvl(s, 0)
                if w > 0 then 
                    s.v[x][y] = w - 1/30/s.blinktime
                    l = lvl(s, s.v[x][y] > 0 and 1 or 0)
                else
                    s.v[x][y] = 0
                end
                
                if l > 0 then g:led(x + s.p_.x[1] - 1, y + s.p_.y[1] - 1, l) end
                ret = true
            end
        end

        return ret
    end
}

_grid.fill = _grid.muxcontrol:new()
_grid.fill.input = nil

_grid.fill.new = function(self, o) 
    o = _grid.muxcontrol.new(self, o)

    local _, axis = input_contained(o, { -1, -1 })
    local v

    if axis.x and axis.y then 
        v = {}
        for x = 1, axis.x do 
            v[x] = {}
            for y = 1, axis.y do
                v[x][y] = 1
            end
        end
    elseif axis.x or axis.y then
        v = {}
        for x = 1, (axis.x or axis.y) do 
            v[x] = 1
        end
    else 
        v = 1
    end

    if type(o.v) ~= type(v) then o.v = v end

    return o
end

_grid.fill.output.muxredraw = _obj_:new {
    point = _grid.binary.output.muxredraw.point,
    line_x = _grid.binary.output.muxredraw.line_x,
    line_y = _grid.binary.output.muxredraw.line_y,
    plane = _grid.binary.output.muxredraw.plane
}

_grid.value = _grid.muxcontrol:new { edge = 1, fingers = nil, tdown = 0, filtersame = true, count = { 1, 1 } }

_grid.value.new = function(self, o) 
    o = _grid.muxcontrol.new(self, o)

    rawset(o, 'hlist', {})
    o.count = { 1, 1 }

    local _, axis = input_contained(o, { -1, -1 })
   
    if axis.x and axis.y then o.v = type(o.v) == 'table' and o.v or { x = 0, y = 0 } end
 
    return o
end

_grid.value.input.muxhandler = _obj_:new {
    point = function(s, x, y, z) 
        if z > 0 then return 0 end
    end,
    line = function(s, x, y, z) 
        local i = x - s.p_.x[1]
        local min, max = fingers(s)

        if z > 0 then
            if #s.hlist == 0 then s.tdown = util.time() end
            table.insert(s.hlist, i)
           
            if s.edge == 1 then 
                if i ~= s.v or (not s.filtersame) then 
                    local len = #s.hlist
                    s.hlist = {}

                    if max == nil or len <= max then
                        return i, len > 1 and util.time() - s.tdown or 0
                    end
                end
            end
        else
            if s.edge == 0 then
                if #s.hlist >= min then
                    i = s.hlist[#s.hlist]
                    local len = #s.hlist
                    s.hlist = {}

                    if max == nil or len <= max then
                        if i ~= s.v or (not s.filtersame) then 
                           return i, util.time() - s.tdown
                        end
                    end
                else
                    local k = tab.key(s.hlist, i)
                    if k then
                        rem = table.remove(s.hlist, k)
                    end
                end
            end
        end
    end,
    plane = function(s, x, y, z) 
        local i = { x = x - s.p_.x[1], y = y - s.p_.y[1] }

        local min, max = fingers(s)

        if z > 0 then
            if #s.hlist == 0 then s.tdown = util.time() end
            table.insert(s.hlist, i)
           
            if s.edge == 1 then 
                if (not (i.x == s.v.x and i.y == s.v.y)) or (not s.filtersame) then 
                    local len = #s.hlist
                    s.hlist = {}
                    s.v.x = i.x
                    s.v.y = i.y

                    if max == nil or len <= max then
                        return s.v, len > 1 and util.time() - s.tdown or 0
                    end
                end
            end
        else
            if s.edge == 0 then
                if #s.hlist >= min then
                    i = s.hlist[#s.hlist]
                    local len = #s.hlist
                    s.hlist = {}

                    if max == nil or len <= max then
                        if (not (i.x == s.v.x and i.y == s.v.y)) or (not s.filtersame) then 
                            s.v.x = i.x
                            s.v.y = i.y
                            return i, util.time() - s.tdown
                        end
                    end
                else
                    for j,w in ipairs(s.hlist) do
                        if w.x == i.x and w.y == i.y then 
                            table.remove(s.hlist, j)
                        end
                    end
                end
            end
        end
    end
}

_grid.value.output.muxredraw = _obj_:new {
    point = function(s, g, v)
        local lvl = lvl(s, 1)
        if lvl > 0 then g:led(s.p_.x, s.p_.y, lvl) end
    end,
    line_x = function(s, g, v)
        for i = s.p_.x[1], s.p_.x[2] do
            local lvl = lvl(s, (s.v == i - s.p_.x[1]) and 1 or 0)
            if lvl > 0 then g:led(i, s.p_.y, lvl) end
        end
    end,
    line_y = function(s, g, v)
        for i = s.p_.y[1], s.p_.y[2] do
            local lvl = lvl(s, (s.v == i - s.p_.y[1]) and 1 or 0)
            if lvl > 0 then g:led(s.p_.x, i, lvl) end
        end
    end,
    plane = function(s, g, v)
        for i = s.p_.x[1], s.p_.x[2] do
            for j = s.p_.y[1], s.p_.y[2] do
                local l = lvl(s, ((s.v.x == i - s.p_.x[1]) and (s.v.y == j - s.p_.y[1])) and 1 or 0)
                if l > 0 then g:led(i, j, l) end
            end
        end
    end
}

return _grid
