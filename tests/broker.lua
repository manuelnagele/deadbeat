-- luajit tests/broker.lua: the LibDataBroker bridge with a fake LDB and LibDBIcon.
local W = dofile("tests/wowstub.lua")

-- a fake LibStub with LibDataBroker-1.1 and LibDBIcon-1.0
local objs, callbacks, hidden, shown = {}, {}, {}, {}
local LDB = {
    DataObjectIterator = function() return pairs(objs) end,
    RegisterCallback = function(_, event, fn) callbacks[event] = fn end,
}
local function newObject(name, obj)
    objs[name] = obj
    if callbacks.LibDataBroker_DataObjectCreated then callbacks.LibDataBroker_DataObjectCreated("x", name, obj) end
    return obj
end
local DBIcon = {
    IsRegistered = function(_, name) return name == "DBM" end,
    Hide = function(_, name) hidden[name] = true shown[name] = nil end,
    Show = function(_, name) shown[name] = true hidden[name] = nil end,
}
LibStub = setmetatable({}, { __call = function(_, lib) return ({ ["LibDataBroker-1.1"] = LDB, ["LibDBIcon-1.0"] = DBIcon })[lib] end })

local clicked
newObject("DBM", { type = "launcher", icon = "dbm", OnClick = function(_, b) clicked = b end,
                   OnTooltipShow = function(tip) tip:AddLine("DBM tip") end })

local ns = {}
for _, f in ipairs({ "Deadbeat/Kit.lua", "Deadbeat/Deadbeat.lua", "Deadbeat/Settings.lua", "Deadbeat/Broker.lua" }) do
    assert(loadfile(f))("Deadbeat", ns)
end
local events = W.frames[#W.frames]                  -- Deadbeat's event frame (the bar's frames come after it)
events:_fire("ADDON_LOADED", "Deadbeat")
events:_fire("PLAYER_LOGIN")
assert(ns.Broker.count() == 1, "objects there before login are found")
assert(hidden.DBM, "its minimap button is hidden (in the tray by default)")

-- one that arrives later, a data source
local bag = newObject("Bags", { type = "data source", text = "12/80", icon = "bag" })
assert(ns.Broker.count() == 2, "objects created later are found")

-- the tray: hover the badge, cells for both, a click goes to the object
DeadbeatTrayButton:_script("OnEnter")
assert(DeadbeatTray, "tray built")
-- the mouse is away (IsMouseOver false): a hovered tray closes, a clicked one stays
rawset(DeadbeatTray, "IsMouseOver", function() return false end)
rawset(DeadbeatBar, "IsMouseOver", function() return false end)
local hidden_ = false
rawset(DeadbeatTray, "Hide", function() hidden_ = true end)
DeadbeatTray:_script("OnUpdate", 1)
assert(hidden_, "hovered tray closes when the mouse is away")
hidden_ = false
DeadbeatTrayButton:_script("OnClick", "LeftButton")
DeadbeatTray:_script("OnUpdate", 1)
assert(not hidden_, "clicked tray stays open")

-- pin the data source; an attribute change redraws it
DeadbeatDB.ldb.Bags = { pin = true }
ns.Broker.scan()
Deadbeat.OpenSettings("LDB")
assert(DeadbeatSettings, "LDB settings page")
bag.text = "11/80"
callbacks.LibDataBroker_AttributeChanged("x", "Bags", "text", "11/80", bag)

-- the minimap switch: show DBM's button again
DeadbeatDB.ldb.DBM.minimap = "show"
ns.Broker.scan()
assert(shown.DBM and not hidden.DBM, "minimap button back when the switch is off")
print("broker ok")
