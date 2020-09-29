--[[

RN
a -> action
p

create an actions object with multiple action callbacks, alias .action to actions[1], set actions.__call to perform all actions in order. add return to action, to modify v

create _control.__call metatmethod as a shortcut to set() and a nifty control linking mechanism

nest.control(value) —- set shorthand
nest.control1(_control2, value) -- set _control1 = value & _control2.actions[#actions] = control1

CONCEPTS

allow _inputs, _outputs in a nest w/o a parent control, set control(/parent) manually. findmeta, en, will need to be functional w/o being inside a control

reimpliment _control as subtype of nest_, remove inputs{}, outputs{}; _input, _output simply refer to o, p (, meta), then self for members. _obj_ woudld support multiple parents and _i/_o would index them in order of appearence.

when nest_ arg type is not table add a number range or key list argument option to initialize blank table children at specified keys

add :each(function(k, _)) to _obj_. these would run after the top level table has been initialized, which helps to enable absolute paths to be used within a nest structure

try to impliment a top-down heirchy (inside of _input / _output), removing the need for the _meta key

or, on the opposite end of the spectrum, remove _meta altogether. with the each() function i'm starting to question why we need this technique ! we would need to repliment connect() as a method which adds devices to all children and grandchildren

add :append() and :prepend() to _obj_

add :append_all(), add a member to all children & grandchildren

actually impliment .enabled, which can be boolean or function

]]

-- _obj_ is a base object for all the types on this page that impliments concatenative programming. all subtypes of _obj_ have proprer copies of the tables in the prototype rather than delegated pointers, so changes to subtype members will never propogate up the tree

-- GOTCHA: overwriting an existing table value will not format type. if we do this, just make sure the type, p, k is correct

local tab = require 'tabutil'

_obj_ = {
    print = function(self) print(tostring(self)) end
}

function _obj_:new(o, clone_type)
    local _ = { -- the "instance table" - useful as it is ignored by the inheritance rules, and also hidden in subtables
        is_obj = true,
        p = nil,
        k = nil
    }

    local function formattype(t, k, v) 
        if type(v) == "table" then
            if v.is_obj then 
                v._.p = t
                v._.k = k
            else
                v = clone_type:new(v)
                v._.p = t
                v._.k = k
            end
        end

        return v
    end

    o = o or {}
    clone_type = clone_type or _obj_

    setmetatable(o, {
        __index = function(t, k)
            if k == "_" then return _
            elseif _[k] ~= nil then return _[k]
            elseif self[k] ~= nil then return self[k]
            else return nil end
        end,
        __newindex = function(t, k, v)
            if _[k] ~= nil then rawset(_,k,v) 
            else rawset(t, k, formattype(t, k, v)) end
        end,
        __concat = function (n1, n2)
            for k, v in pairs(n2) do
                n1[k] = v
            end
            return n1
        end--,
        --__tostring = function(t) return '_obj_' end
    })
    
    for k,v in pairs(o) do formattype(o, k, v) end -- stack overflow on c:new()

    for k,v in pairs(self) do 
        if not rawget(o, k) then
            if type(v) == "function" then
            elseif type(v) == "table" then
                local clone = formattype(self, k, v):new()
                o[k] = formattype(o, k, clone) ----
            else rawset(o,k,v) end 
        end
    end
    
    return o
end

_input = _obj_:new {
    is_input = true,
    transform = nil,
    handler = nil,
    deviceidx = nil,
    update = function(self, deviceidx, args)
        if(self.deviceidx == deviceidx) then
            return args
        else return nil end
    end
}

function _input:new(o)
    o = _obj_.new(self, o, _obj_)
    local _ = o._

    _.control = nil
    
    local mt = getmetatable(o)
    local mtn = mt.__newindex

    mt.__index = function(t, k) 
        if k == "_" then return _
        elseif _[k] ~= nil then return _[k]
        else
            local c = _.control and _.control[k]
            
            -- catch shared keys, otherwise privilege control keys
            if k == 'new' or k == 'update' or k == 'draw' or k == 'throw' then return self[k]
            else return c or self[k] end
        end
    end

    mt.__newindex = function(t, k, v)
        local c = _.control and _.control[k]
    
        if c and type(c) ~= 'function' then _.control[k] = v
        else mtn(t, k, v) end
    end

    return o
end

_output = _obj_:new {
    is_output = true,
    transform = nil,
    redraw = nil,
    deviceidx = nil,
    throw = function(self, ...)
        self.control.throw(self.control, self.deviceidx, ...)
    end,
    draw = function(self, deviceidx)
        if(self.deviceidx == deviceidx) then
            return {}
        else return nil end
    end
}

_output.new = _input.new

_control = _obj_:new {
    is_control = true,
    v = 0,
    order = 0,
    en = true,
    group = nil,
    a = function(s, v) end,
    init = function(s) end,
    help = function(s) end,
    do_init = function(self)
        self:init()
    end,
    update = function(self, deviceidx, args)
        local d = false

        for i,v in ipairs(self.inputs) do
            local hargs = v:update(deviceidx, args)
            
            if hargs ~= nil then
                d = true

                if self.metacontrols and not self.metacontrols_disabled then
                    for i,w in ipairs(self.metacontrols) do
                        w:pass(v.handler, hargs)
                    end
                end

                if v.handler then v:handler(table.unpack(hargs)) end
            end
        end

        if d then for i,v in ipairs(self.outputs) do
            self.device_redraws[deviceidx]()
        end end
    end,
    draw = function(self, deviceidx)
        for i,v in ipairs(self.outputs) do
            local rdargs = v:draw(deviceidx)
            if rdargs ~= nil and v.redraw then v:redraw(table.unpack(rdargs)) end
        end
    end,
    throw = function(self, deviceidx, method, ...)
        if self.catch and self.deviceidx == deviceidx then
            self:catch(deviceidx, method, ...)
        else self.p:throw(deviceidx, method, ...) end
    end,
    print = function(self) end,
    get = function(self) return self.v end,
    set = function(self, v, silent)
        self.v = v
        silent = silent or false

        if not silent then
            self:a(v, self.meta)

            if d then for i,v in ipairs(self.outputs) do
                self.device_redraws[deviceidx]()
            end end
        end
    end,
    write = function(self) end,
    read = function(self) end,
    inputs = {},
    outputs = {}
}

function _control:new(o)
    o = _obj_.new(self, o, _obj_)
    local _ = o._    

    local mt = getmetatable(o)
    local mti = mt.__index

    mt.__index = function(t, k) 
        local findmeta = function(nest)
            if nest and nest.is_nest then
                if nest._meta ~= nil and nest._meta[k] ~= nil then return nest._meta[k]
                elseif nest._._meta ~= nil and nest._._meta[k] ~= nil then return nest._._meta[k]
                elseif nest._.p ~= nil then return findmeta(nest._.p)
                else return nil end
            else return nil end
        end

        if k == "input" then return o.inputs[1]
        elseif k == "output" then return o.outputs[1]
        elseif k == "target" then return o.targets[1]
        else return findmeta(_.p) or mti(t, k) end
    end

    --mt.__tostring = function(t) return '_control' end

    for i,k in ipairs { "input", "output" } do -- lost on i/o table overwrite, fix in mt.__newindex
        local l = o[k .. 's']

        if rawget(o, k) then 
            rawset(l, 1, rawget(o, k))
            rawset(o, k, nil)
        end
        
        for i,v in ipairs(l) do
            if type(v) == 'table' and v['is_' .. k] then
                rawset(v._, 'control',  o)
                v.deviceidx = v.deviceidx or _.group and _.group.deviceidx or nil
            end
        end

        local lmt = getmetatable(l)
        local lmtn = lmt.__newindex

        lmt.__newindex = function(t, kk, v)
            lmtn(t, kk, v)

            if type(v) == 'table' and v['is_' .. k] then
                v._.control = o
                v.deviceidx = v.deviceidx or o.group and o.group.deviceidx or nil
            end
        end
    end
 
    return o
end

_metacontrol = _control:new {
    pass = function(self, f, args) end, --passing the function will work but cannot be recalled
    targets = {}
}

function _metacontrol:new(o)
    o = _control.new(self, o)

    local mt = getmetatable(o)
    mt.__tostring = function() return '_metacontrol' end

    local tmt = getmetatable(o.targets)
    local tmtn = mt.__newindex

    tmt.__newindex = function(t, k, v)
        tmtn(t, k, v)

        local mct
        if v.is_nest then
            if v._._meta == nil then v._._meta = {} end
            if v._._meta.metacontrols == nil then v._._meta.metacontrols = {} end
            mct = v._._meta.metacontrols
        elseif v.is_control then 
            if v.metacontrols == nil then v.metacontrols = {} end
            mct = v.metacontrols
        end

        table.insert(mct, o)
    end

    return o
end

nest_ = _obj_:new {
    do_init = function(self)
        self:init()
        table.sort(self, function(a,b) return a.order < b.order end)

        for k,v in pairs(self) do if v.is_nest or v.is_control then v:do_init() end end
    end,
    init = function(self) return self end,
    each = function(self, cb) return self end,
    update = function(self, deviceidx, args)
        for k,v in pairs(self) do if v.is_nest or v.is_control then
            v:update(deviceidx, args )
        end end
    end,
    draw = function(self, deviceidx)  
        for k,v in pairs(self) do if v.is_nest or v.is_control then
            v:draw(deviceidx)
        end end
    end,
    throw = function(self, deviceidx, method, ...)
        self.p:throw(deviceidx, method, ...)
    end,
    set = function(self, tv) end, --table set nest = { nest = { control = value } }
    get = function(self) end,
    write = function(self) end,
    read = function(self) end
}

function nest_:new(o)
    o = _obj_.new(self, o, nest_)
    local _ = o._ 

    _.is_nest = true
    _.en = true
    _.order = 0

    local mt = getmetatable(o)
    --mt.__tostring = function(t) return 'nest_' end

    return o
end

_group = _obj_:new {}

function _group:new(o)
    o = _obj_.new(self, o, _group)
    local _ = o._ 

    _.is_group = true
    _.deviceidx = ""

    local mt = getmetatable(o)
    local mtn = mt.__newindex

    mt.__newindex = function(t, k, v)
        mtn(t, k, v)

        if type(v) == "table" then
            if  v.is_control then
                v._.group = t
               
                for i,w in ipairs(v.inputs) do
                    w.deviceidx = w.deviceidx or _.deviceidx
                end
                for i,w in ipairs(v.outputs) do
                    w.deviceidx = w.deviceidx or _.deviceidx
                end
            elseif v.is_group then
                v._.deviceidx = _.deviceidx
            end
        end 
    end
    return o
end