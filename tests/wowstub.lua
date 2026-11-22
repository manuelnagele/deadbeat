-- luajit tests/smoke.lua: load the whole addon against a stubbed WoW API and drive a session.
-- Catches nil globals, typos and wrong call shapes that the core tests can't see. Not a WoW emulator.
local calls = {}
local function stub(name)
    local o = { _name = name }
    return setmetatable(o, { __index = function(t, k)
        return function(self, ...)
            calls[#calls + 1] = (name or "?") .. ":" .. k
            if k:match("^Create") then return stub(k) end
            if k == "GetWidth" then return 300 end
            if k == "GetHeight" then return 3 end
            if k == "IsShown" then return true end
            if k == "GetPoint" then return "TOP", nil, "BOTTOM", 0, -24 end
            if k == "GetFrameLevel" then return 1 end
            return nil
        end
    end })
end
local frames = {}
function CreateFrame(kind, name, parent, template)
    local f = stub(name or kind)
    local scripts, events = {}, {}
    rawset(f, "SetScript", function(self, k, fn) scripts[k] = fn end)
    rawset(f, "RegisterEvent", function(self, e) events[e] = true end)
    rawset(f, "_fire", function(self, e, ...) if scripts.OnEvent then scripts.OnEvent(self, e, ...) end end)
    rawset(f, "_script", function(self, k, ...) if scripts[k] then scripts[k](self, ...) end end)
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end
UIParent, Minimap, GameTooltip, DEFAULT_CHAT_FRAME = stub("UIParent"), stub("Minimap"), stub("GameTooltip"), stub("chat")
local tickers = {}
C_Timer = { NewTicker = function(_, fn) tickers[#tickers + 1] = fn end, After = function(_, fn) fn() end,
            NewTimer = function() return { Cancel = function() end } end }   -- timers never fire in the stub
local money = 10000
function GetMoney() return money end
function GetTime() return os.clock() end
function GetServerTime() return os.time() end
time, date = os.time, os.date
function UnitGUID() return "Player-1-ABC" end
function UnitFullName() return "Earl", "Realm" end
function UnitIsAFK() return false end
function UnitIsDeadOrGhost() return false end
local inInstance = true
function IsInInstance() return inInstance, inInstance and "party" or "none" end
function GetInstanceInfo() return "Maraudon", "party", 1, "", 5, 0, false, 349 end
function GetZoneText() return "Desolace" end
function GetNumLootItems() return 1 end
function GetLootSourceInfo() return "Creature-0-1-349-21543-11517-0001" end
function IsFishingLoot() return false end
local shift = false
function IsShiftKeyDown() return shift end
function GetZoneText() return "Desolace" end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function GetCoinTextureString(c) return tostring(c) .. "c" end
SlashCmdList = {}
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
ITEM_QUALITY_COLORS = { [2] = { r = 0.1, g = 1, b = 0.1, hex = "|cff1eff00" } }
C_Spell = { GetSpellName = function(id) return ({ [2366] = "Herb Gathering", [7620] = "Fishing" })[id] end }
C_Item = {
    GetItemInfo = function(id) return "Item" .. id, nil, 2, nil, nil, nil, nil, nil, nil, nil, 150, nil, nil, 2 end,
    GetItemNameByID = function(id) return "Item" .. id end,
    GetItemQualityByID = function() return 2 end,
    GetItemIconByID = function() return 134400 end,
}
ForeverMarketPrices = { updated = os.time(), c = { [13463] = 1900 }, g = {} }
Lockout = { Status = function() return { hourLeft = 2, hourUsed = 3, nextFree = os.time() + 120, dayLeft = 25, dayUsed = 5 } end }


function strsplit(sep, str, n)
    local out, start = {}, 1
    while true do
        if n and #out == n - 1 then out[#out + 1] = str:sub(start) break end
        local i, j = str:find(sep, start, true)
        if not i then out[#out + 1] = str:sub(start) break end
        out[#out + 1] = str:sub(start, i - 1)
        start = j + 1
    end
    return unpack(out)
end

-- a tooltip that counts its lines, so section logic can be checked
local lines = {}
GameTooltip = setmetatable({ lines = lines }, { __index = function(_, k)
    if k == "AddLine" or k == "AddDoubleLine" then return function(_, a) lines[#lines + 1] = tostring(a) end end
    if k == "NumLines" then return function() return #lines end end
    if k == "SetOwner" then return function() for i = #lines, 1, -1 do lines[i] = nil end end end
    if k == "IsOwned" then return function() return true end end
    return function() end
end })

return { frames = frames, tickers = tickers, tipLines = lines }
