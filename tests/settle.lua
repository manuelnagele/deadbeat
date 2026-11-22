-- luajit tests/settle.lua: the bar settles. A stub with real visibility (parents, children, OnShow/OnHide on the frame
-- and its visible children) whose OnShow/OnHide and C_Timer.After are queued like the game's next frame. A layout
-- that answers its own visibility events chases itself forever: 2.0.1 hung the loading screen that way.
local H = dofile(os.getenv("HARNESS") or "../deadbeat-spec/harness/wowstub.lua")
local QUEUE = {}
local real = CreateFrame
function CreateFrame(kind, name, parent, template)
    local f = real(kind, name, parent, template)
    local scripts, hooks, kids = {}, {}, {}
    rawset(f, "_kids", kids)
    rawset(f, "_parent", parent)
    rawset(f, "_shown", true)
    if type(parent) == "table" and rawget(parent, "_kids") then table.insert(rawget(parent, "_kids"), f) end
    local function visible(fr)
        while fr do
            if rawget(fr, "_shown") == false then return false end
            fr = rawget(fr, "_parent")
        end
        return true
    end
    local set = rawget(f, "SetScript")
    rawset(f, "SetScript", function(self, k, fn) scripts[k] = fn set(self, k, fn) end)
    rawset(f, "HookScript", function(_, k, fn) hooks[k] = hooks[k] or {} table.insert(hooks[k], fn) end)
    rawset(f, "_fireScript", function(k)
        QUEUE[#QUEUE + 1] = function()
            if scripts[k] then scripts[k](f) end
            for _, h in ipairs(hooks[k] or {}) do h(f) end
        end
    end)
    local function fire(fr, k)
        rawget(fr, "_fireScript")(k)
        for _, c in ipairs(rawget(fr, "_kids")) do if rawget(c, "_shown") ~= false then fire(c, k) end end
    end
    rawset(f, "IsShown", function() return rawget(f, "_shown") ~= false end)
    rawset(f, "Show", function()
        if rawget(f, "_shown") ~= false then return end
        local was = visible(f)
        rawset(f, "_shown", true)
        if not was and visible(f) then fire(f, "OnShow") end
    end)
    rawset(f, "Hide", function()
        if rawget(f, "_shown") == false then return end
        local was = visible(f)
        rawset(f, "_shown", false)
        if was then fire(f, "OnHide") end
    end)
    rawset(f, "SetShown", function(self, on) if on then self:Show() else self:Hide() end end)
    return f
end
C_Timer.After = function(_, fn) QUEUE[#QUEUE + 1] = fn end

-- next frames until nothing is left to do; nil if it never settles
local function frames(limit)
    local n = 0
    while #QUEUE > 0 do
        local q = QUEUE
        QUEUE = {}
        for _, fn in ipairs(q) do fn() n = n + 1 end
        if n > limit then return nil end
    end
    return n
end

H.loadDeadbeat(os.getenv("DEADBEAT") or ".")
local m = Deadbeat.Register("Diamonds", { spec = "2.0" })
local canvas, widget = m:Widget("slots", { name = "Slots", width = 60 })
local value = m:Item("next", { name = "Next" })
value:Set("33s", "warn")
local other = Deadbeat.Register("Bags", { spec = "2.0" }):Item("bags", { name = "Bags" })
other:Set("28")
assert(frames(5000), "the bar settles after login")
assert(widget.frame:IsShown(), "the widget is on the bar")
for i = 1, 5 do
    value:Set(tostring(30 - i), "warn")                 -- a ticking value, every second
    other:Set(tostring(20 + i))
    assert(frames(5000), "the bar settles after updates")
end
canvas:Hide()
assert(frames(5000) and not widget.frame:IsShown(), "the module hides its widget: off the bar")
canvas:Show()
assert(frames(5000) and widget.frame:IsShown(), "and shows it again: back on the bar")
Deadbeat.SetLayout("top")
assert(frames(5000) and widget.frame:IsShown(), "settles in full-width too")
print("settle ok")
