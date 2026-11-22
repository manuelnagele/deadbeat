-- luajit tests/smoke.lua: Deadbeat against a stubbed WoW API, with two fake modules.
local W = dofile(os.getenv("HARNESS") or "../deadbeat-spec/harness/wowstub.lua")   -- the shared harness
local ns = {}
for _, file in ipairs({ "Deadbeat/Kit.lua", "Deadbeat/Deadbeat.lua", "Deadbeat/Settings.lua", "Deadbeat/Broker.lua" }) do assert(loadfile(file))("Deadbeat", ns) end
local events = W.frames[#W.frames]
events:_fire("ADDON_LOADED", "Deadbeat")
events:_fire("PLAYER_LOGIN")
assert(DeadbeatBar, "bar built")

local haul = Deadbeat.Register("Haul", 10)
local catch = Deadbeat.Register("Catch", 30)
haul:Set("label", "Session", 10)
catch:Set("label", "Fishing · Feralas", 50)
local labelText
local realSet = DeadbeatBar.label.SetText
rawset(DeadbeatBar.label, "SetText", function(self, t) labelText = t end)
Deadbeat.Refresh()
assert(labelText == "Fishing · Feralas", "highest priority owns the label")
catch:Clear("label")
assert(labelText == "Session", "falls back when released")

local badge = haul:Badge(40)
local band = haul:Band(10)
local clicked
haul:OnClick(function() clicked = true end)
haul:Section(function(tip, shift) tip:AddLine("haul " .. tostring(shift)) end)
catch:Section(function() error("boom") end)                      -- a broken section must not break the tooltip
local panel = CreateFrame("Frame", "TestPanel", UIParent)
catch:Dock(panel)
DeadbeatBar:_script("OnClick", "LeftButton")
assert(clicked, "click goes to the label owner")
DeadbeatBar:_script("OnEnter")
local joined = table.concat(W.tipLines, "\n")
assert(joined:find("haul false") and joined:find("Catch: .*boom"), "sections + error line: " .. joined)
SlashCmdList.DEADBEAT("scale 1.2")
SlashCmdList.DEADBEAT("")
assert(Deadbeat.kit.coins(123456) and Deadbeat.kit.clock(3725) == "1:02:05", "kit")
-- the settings console: a page with every kind of row, opened from the gear
local on, scale, keys, ran, built = false, 1, {}, false, false
haul:Options({ title = "Haul", icon = "x", rows = {
    { kind = "header", label = "Runs" },
    { kind = "note", label = "a note" },
    { kind = "toggle", label = "T", get = function() return on end, set = function(v) on = v end },
    { kind = "button", label = "B", text = "Reset", run = function() ran = true end },
    { kind = "slider", label = "S", min = 0.5, max = 2, step = 0.05, fmt = "%.2f", get = function() return scale end,
      set = function(v) scale = v end },
    { kind = "keys", label = "K", get = function(slot) return keys[slot] end, set = function(slot, k) keys[slot] = k end },
    { kind = "custom", height = 100, build = function(f) built = f end },
} })
DeadbeatGear:_script("OnClick")
assert(DeadbeatSettings, "console opens from the gear")
Deadbeat.OpenSettings("Haul")
assert(built, "custom row built")
SlashCmdList.DEADBEAT("")
-- contexts: the stub is in a party instance; a claim makes it "farm"
events:_fire("PLAYER_ENTERING_WORLD")
assert(Deadbeat.Context() == "dungeon", "dungeon context: " .. Deadbeat.Context())
local seen
catch:OnContext(function(c) seen = c end)
catch:Claim("farm", true)
assert(Deadbeat.Context() == "farm" and seen == "farm", "farm while claimed")
catch:Claim("farm", false)
assert(Deadbeat.Context() == "dungeon", "back to dungeon")
local raidOnly = haul:Badge(30, { id = "test", label = "Test", contexts = { raid = true } })
assert(not Deadbeat.badgeAllowed(raidOnly, "dungeon") and Deadbeat.badgeAllowed(raidOnly, "raid"), "badge contexts")
Deadbeat.SetBadgeContext(raidOnly, "dungeon", true)
assert(Deadbeat.badgeAllowed(raidOnly, "dungeon"), "user override")
Deadbeat.OpenSettings("Bar")
assert(Deadbeat.SPEC == "1.0", "spec version")
local said
rawset(DEFAULT_CHAT_FRAME, "AddMessage", function(_, t) said = t end)
Deadbeat.Register("Future", 90, { spec = "2.0" })
assert(said and said:find("wants spec 2.0"), "warns about a newer spec major")
said = nil
Deadbeat.Register("Today", 91, { spec = "0.1" })
assert(not said, "no warning for the current spec")
-- layouts: compact by default, full-width bottom and top, back to compact
assert(Deadbeat.Layout() == "compact", "compact by default")
local seenLayout
catch:OnLayout(function(l) seenLayout = l end)
Deadbeat.SetLayout("bottom")
assert(Deadbeat.Layout() == "bottom" and seenLayout == "bottom" and DeadbeatDB.layout == "bottom", "full-width bottom")
Deadbeat.SetBadgeZone(raidOnly, "center")
assert(Deadbeat.BadgeZone(raidOnly) == "center", "badge in the centre zone")
Deadbeat.Refresh()
Deadbeat.OpenSettings("Bar")
DeadbeatBar:_script("OnEnter")
Deadbeat.SetLayout("top")
Deadbeat.SetLayout("compact")
assert(DeadbeatDB.layout == nil and Deadbeat.Layout() == "compact", "compact again")
print("deadbeat smoke ok")
