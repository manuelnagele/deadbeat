-- luajit tests/smoke.lua: Deadbeat 2.0 on the shared harness: items, groups, interaction, contexts, layouts, the
-- console, and 1.x modules through the legacy layer.
local W = dofile(os.getenv("HARNESS") or "../deadbeat-spec/harness/wowstub.lua")   -- the shared harness
local ns = {}
local before = #W.frames
for _, file in ipairs({ "Deadbeat/Kit.lua", "Deadbeat/Deadbeat.lua", "Deadbeat/Items.lua", "Deadbeat/Settings.lua",
                        "Deadbeat/Broker.lua", "Deadbeat/Edit.lua" }) do assert(loadfile(file))("Deadbeat", ns) end
local events = W.frames[before + 1]                    -- Deadbeat's event frame
events:_fire("ADDON_LOADED", "Deadbeat")
events:_fire("PLAYER_LOGIN")
assert(DeadbeatBar and DeadbeatGear, "bar and gear built")
assert(Deadbeat.SPEC == "2.0", "spec version")

-- --- a 2.0 module: items, a widget, tooltip, click -----------------------------------------------------------
local hearth = Deadbeat.Register("Hearth", { icon = "hearth-icon", spec = "2.0" })
local bags = hearth:Item("bags", { name = "Bags", icon = "bag", contexts = { world = true, city = true, dungeon = true } })
local gold = hearth:Item("gold", { name = "Gold", icon = "coin" })
local mail = hearth:Item("mail", { name = "Mail", icon = "letter", default = false })
bags:Set("34", "normal")
gold:Set("412g", "good")
assert(bags.value == "34" and gold.state == "good", "values and states")
bags:Set("2", "nonsense")
assert(bags.state == "normal", "an unknown state is normal")
local canvas, slots = hearth:Widget("slots", { name = "Slots", width = 60 })
assert(canvas and slots.kind == "widget", "a widget gives a frame to draw into")
assert(hearth:Item("bags") == bags, "same id, same item")

local clicked, shown
hearth:Tooltip(function(tip, it, shift) tip:AddLine("tip for " .. it.id) end)
hearth:Click(function(it, button) clicked = it.id .. ":" .. button end, "open bags")
hearth:Options({ title = "Hearth", rows = { { kind = "note", label = "x" } } })

-- visibility: default items on the bar, the rest on the shelf; contexts; the player's choices
events:_fire("PLAYER_ENTERING_WORLD")                   -- the harness is in a party instance: "dungeon"
assert(Deadbeat.Context() == "dungeon", "dungeon")
assert(ns.Items.visible(bags) and ns.Items.visible(gold) and not ns.Items.visible(mail), "defaults: mail on the shelf")
ns.Items.setShown(mail, true)
assert(ns.Items.visible(mail) and DeadbeatDB.items["Hearth.mail"] == "show", "the player puts mail on the bar")
ns.Items.setShown(mail, false)
assert(DeadbeatDB.items["Hearth.mail"] == nil, "back to its default: nothing saved")
ns.Items.setAllowed(bags, "dungeon", false)
assert(not ns.Items.visible(bags), "the player hides bags in dungeons")
ns.Items.setAllowed(bags, "dungeon", true)
bags:Hide()
assert(not ns.Items.visible(bags), "a module hides its item")
bags:Show()

-- groups: a new module appends; the order is saved
local lockout = Deadbeat.Register("Lockout", { icon = "watch" })
lockout:Item("slots", { name = "Slots" }):Set("3/5", "good")
local names = {}
for _, m in ipairs(ns.Items.groups()) do names[#names + 1] = m.name end
assert(table.concat(names, ",") == "Hearth,Lockout", "groups in order, new ones appended: " .. table.concat(names, ","))
assert(table.concat(DeadbeatDB.itemOrder.Hearth, ",") == "bags,gold,mail,slots", "item order saved")

-- interaction: hover = the module's tooltip with the hub's header and hints; left = action; right = settings
for i = #W.tipLines, 1, -1 do W.tipLines[i] = nil end
bags.frame:_script("OnEnter")
local tip = table.concat(W.tipLines, "\n")
assert(tip:find("Hearth") and tip:find("Bags") and tip:find("tip for bags") and tip:find("Click: open bags")
    and tip:find("Right%-click: settings"), "item tooltip: " .. tip)
bags.frame:_script("OnLeave")
bags.frame:_script("OnClick", "LeftButton")
assert(clicked == "bags:LeftButton", "left-click is the module's action")
clicked = nil
bags.frame:_script("OnClick", "RightButton")
assert(clicked == nil and DeadbeatSettings, "right-click opens the module's settings, not its action")

-- layouts and the overflow
Deadbeat.SetLayout("top")
ns.Items.setZone(lockout, "center")
assert(ns.Items.zone(lockout) == "center", "a group in the centre zone")
Deadbeat.SetLayout("bottom")
bags.frame:_script("OnEnter")
Deadbeat.SetLayout("compact")
for i = 1, 30 do                                       -- more than fits in 760 px
    Deadbeat.Register("Filler" .. i):Item("x", { name = "X" }):Set("a long value " .. i)
end
assert(#ns.Items.all() > 30, "all items listed")

-- --- edit mode: the drop rules (cursor positions in bar coordinates) ---------------------------------------------
Deadbeat.SetLayout("compact")
rawset(DeadbeatBar, "GetLeft", function() return 100 end)
rawset(DeadbeatBar, "GetTop", function() return 500 end)
rawset(DeadbeatBar, "GetBottom", function() return 474 end)
ns.Edit.toggle(true)
assert(ns.Edit.active() and DeadbeatShelf, "edit mode with the shelf")
hearth.span = { 10, 120 }
rawset(bags.frame, "GetLeft", function() return 110 end)      -- bags at 10..30, gold at 50..80 (bar coords)
rawset(gold.frame, "GetLeft", function() return 150 end)
assert(ns.Edit.dropAt(gold, 105, 487) == "reordered", "dropped inside its group")
assert(DeadbeatDB.itemOrder.Hearth[1] == "gold", "gold now before bags: " .. table.concat(DeadbeatDB.itemOrder.Hearth, ","))
lockout.span = { 140, 170 }
-- (the stub's widget is 300 px wide, so the Hearth group spans 10..370 here)
assert(ns.Edit.dropAt(bags, 100 + 600, 487) == "moved", "dropped past its group")
assert(DeadbeatDB.groups[#DeadbeatDB.groups] == "Hearth" or DeadbeatDB.groups[1] ~= "Hearth", "the Hearth group moved")
assert(ns.Edit.dropAt(gold, 300, 300) == "hidden" and not ns.Items.shown(gold), "dropped off the bar: hidden")
ns.Edit.drawShelf()
ns.Items.setShown(gold, true)
ns.Edit.click(bags)
assert(DeadbeatItemOptions, "item options")
ns.Items.setLabel(bags, true)
assert(ns.Items.showLabel(bags), "show its name")
bags.frame:_script("OnEnter")
function GetCursorPosition() return 160, 487 end      -- inside the bar, over the Hearth group
ns.Edit.drag(bags)
ns.Edit.drop(bags)
ns.Edit.toggle(false)
assert(not ns.Edit.active(), "done")

-- --- a 1.x module keeps working (legacy) ---------------------------------------------------------------------------
local said
rawset(DEFAULT_CHAT_FRAME, "AddMessage", function(_, t) said = t end)
local haul = Deadbeat.Register("Haul", 10, { spec = "1.0" })
haul:Set("label", "Maraudon · run 3", 20)
assert(said and said:find("old %(1.x%) API"), "a one-time note about the old API")
haul:Set("primary", "3g 12s", 20)
assert(haul.legacyItem and haul.legacyItem.value == "Maraudon · run 3  ·  3g 12s", "fields join into one item: "
    .. tostring(haul.legacyItem and haul.legacyItem.value))
local badge = haul:Badge(40, { id = "haul.spark", label = "Sparkline", contexts = { farm = true } })
assert(badge and haul.byId.spark and haul.byId.spark.kind == "widget", "a badge becomes a widget item")
local sectioned, legacyClick
haul:Section(function(t, shift) sectioned = true t:AddLine("haul section") end)
haul:OnClick(function(button) legacyClick = button end)
haul.legacyItem.frame:_script("OnEnter")
assert(sectioned, "a section becomes the module's tooltip")
haul.legacyItem.frame:_script("OnClick", "LeftButton")
assert(legacyClick == "LeftButton", "OnClick still gets clicks")
local band = haul:Band(10)
haul:BandPriority(5, false)
assert(band, "a band call doesn't break")
haul:Clear("label") haul:Clear("primary")
assert(not haul.legacyItem.wanted, "no fields, no legacy item")

-- --- newer spec, contexts, the console ---------------------------------------------------------------------------
said = nil
Deadbeat.Register("Future", { spec = "3.0" })
assert(said and said:find("wants spec 3.0"), "warns about a newer spec major")
local seen
hearth:OnContext(function(c) seen = c end)
hearth:Claim("farm", true)
assert(Deadbeat.Context() == "farm" and seen == "farm", "farm while claimed")
hearth:Claim("farm", false)
Deadbeat.OpenSettings("Bar")
Deadbeat.OpenSettings("Hearth")
local panel = CreateFrame("Frame", "TestPanel", UIParent)
hearth:Dock(panel)
SlashCmdList.DEADBEAT("")
SlashCmdList.DEADBEAT("scale 1.2")
SlashCmdList.DEADBEAT("reset")
assert(Deadbeat.kit.coins(123456) and Deadbeat.kit.clock(3725) == "1:02:05", "kit")
print("deadbeat smoke ok")
