-- Deadbeat: one bar that every module contributes to (compact or full-width). It draws the bar, its items, tooltips,
-- the settings console and edit mode, and knows nothing about gold, fish or lockouts. The design language:
-- deadbeat-spec DESIGN.md; the contract: spec.md (2.0), AGENTS.md.
--
--   local m = Deadbeat.Register("Hearth", { icon = "...", spec = "2.0" })
--   local bags = m:Item("bags", { name = "Bags", icon = "...", default = true, contexts = { world = true } })
--   bags:Set("34", "normal")                         -- value, state: normal | good | warn | bad
--   local w = m:Widget("slots", { name = "Slots", width = 60 })    -- a frame to draw into
--   m:Tooltip(function(tip, item, shift) end)        -- lines for an item's tooltip (header and hints are drawn for you)
--   m:Click(function(item, button) end, "open bags") -- left-click + its hint
--   m:Options({ title, icon, rows = { ... } })       -- settings pages (right-click opens the first)
--   m:Claim("farm", on)  m:OnContext(fn)  m:OnLayout(fn)  m:Dock(frame)
--   Deadbeat.kit · Deadbeat.Context() · Deadbeat.Layout() · Deadbeat.OpenSettings(title)
local ADDON, ns = ...
local K = ns.kit
local VERSION = "2.0.1"
local SPEC = "2.0"                 -- the spec version this hub implements (deadbeat-spec/spec.md)

Deadbeat = { kit = K, version = VERSION, SPEC = SPEC }

local CONTEXTS = { "farm", "raid", "dungeon", "city", "world" }
Deadbeat.CONTEXTS = CONTEXTS
local COMPACT_H, FULL_H = 26, 22
local claims = {}              -- module name -> true while it claims "farm"
local context = "world"
local modules = {}             -- in registration order
ns.modules = modules
local bar, db
local docked = {}

local function render() if ns.Items then ns.Items.render() end end

-- --- context -------------------------------------------------------------------

function Deadbeat.Context() return context end

local function computeContext()
    for _, on in pairs(claims) do if on then return "farm" end end
    local inside, kind = IsInInstance()
    if inside and kind == "raid" then return "raid" end
    if inside and (kind == "party" or kind == "scenario") then return "dungeon" end
    if IsResting and IsResting() then return "city" end
    return "world"
end

local function updateContext()
    local new = computeContext()
    if new == context then return end
    context = new
    for _, m in ipairs(modules) do
        if m.contextFn then pcall(m.contextFn, context) end
    end
    render()
end
Deadbeat.UpdateContext = updateContext

-- --- layout: one bar, compact (centred, movable) or full-width on the top or bottom edge ----------------

function Deadbeat.Layout() return (db and db.layout) or "compact" end
local function full() return Deadbeat.Layout() ~= "compact" end
local function atBottom() return Deadbeat.Layout() == "bottom" end
Deadbeat.atBottom = atBottom
ns.full = full

-- the last shown docked panel (or the bar): where things that open from the bar should start
function Deadbeat.DockEnd()
    local anchor = bar
    for _, f in ipairs(docked) do if f:IsShown() then anchor = f end end
    return anchor
end

local function relayoutDock()
    local anchor = bar
    for _, f in ipairs(docked) do
        if f:IsShown() then
            f:ClearAllPoints()
            if atBottom() then f:SetPoint("BOTTOM", anchor, "TOP", 0, 6) else f:SetPoint("TOP", anchor, "BOTTOM", 0, -6) end
            anchor = f
        end
    end
end

-- Put the bar where its layout says: compact at its saved spot (movable unless locked), full-width on an edge.
local function applyLayout()
    if not bar then return end
    local wide, bottom = full(), atBottom()
    bar:ClearAllPoints()
    if wide then
        bar:SetPoint(bottom and "BOTTOMLEFT" or "TOPLEFT", UIParent, bottom and "BOTTOMLEFT" or "TOPLEFT", 0, 0)
        bar:SetPoint(bottom and "BOTTOMRIGHT" or "TOPRIGHT", UIParent, bottom and "BOTTOMRIGHT" or "TOPRIGHT", 0, 0)
        bar:SetHeight(FULL_H)
    else
        local p = db.point
        if p then bar:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else bar:SetPoint("TOP", UIParent, "TOP", 0, -40) end
        bar:SetHeight(COMPACT_H)
    end
    bar.border:SetShown(not wide)
    bar.edge:SetShown(wide)
    bar.edge:ClearAllPoints()
    bar.edge:SetPoint(bottom and "TOPLEFT" or "BOTTOMLEFT")
    bar.edge:SetPoint(bottom and "TOPRIGHT" or "BOTTOMRIGHT")
    render()
    relayoutDock()
end
ns.applyLayout = applyLayout

function Deadbeat.SetLayout(layout)
    db.layout = layout ~= "compact" and layout or nil
    applyLayout()
    for _, m in ipairs(modules) do if m.layoutFn then pcall(m.layoutFn, Deadbeat.Layout()) end end
end

-- --- the bar -------------------------------------------------------------------

local function startMove()
    if IsShiftKeyDown() and not full() and not db.locked then bar:StartMoving() end
end
local function stopMove()
    bar:StopMovingOrSizing()
    if full() then return end
    local point, _, rel, x, y = bar:GetPoint()
    db.point = { point, rel, x, y }
end
ns.startMove, ns.stopMove = startMove, stopMove

local function build()
    bar = CreateFrame("Button", "DeadbeatBar", UIParent)
    bar:SetSize(200, COMPACT_H)
    K.ground(bar)
    bar.border = K.border(bar, true)
    bar.edge = bar:CreateTexture(nil, "BORDER")                 -- full-width: a bronze line on the inner edge
    bar.edge:SetHeight(1)
    bar.edge:SetColorTexture(K.P.bronze3[1], K.P.bronze3[2], K.P.bronze3[3], 1)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", startMove)
    bar:SetScript("OnDragStop", stopMove)

    -- the gear: every module's settings (left-click), edit mode (right-click)
    local P = K.P
    bar.gear = CreateFrame("Button", "DeadbeatGear", bar)
    bar.gear:SetSize(16, 16)
    bar.gear:SetFrameLevel(bar:GetFrameLevel() + 5)
    bar.gear:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local gear = bar.gear:CreateTexture(nil, "ARTWORK")
    gear:SetAllPoints()
    gear:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetVertexColor(P.bronze4[1], P.bronze4[2], P.bronze4[3])
    bar.gear:SetAlpha(0.5)
    bar.gear:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        if atBottom() then GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4) else GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4) end
        GameTooltip:AddLine("Deadbeat", P.bronze4[1], P.bronze4[2], P.bronze4[3])
        GameTooltip:AddLine("Click: settings  ·  Right-click: edit the bar", P.warmGrey[1], P.warmGrey[2], P.warmGrey[3])
        GameTooltip:Show()
    end)
    bar.gear:SetScript("OnLeave", function(self) self:SetAlpha(0.5) GameTooltip:Hide() end)
    bar.gear:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if ns.Edit then ns.Edit.toggle() end
        else
            Deadbeat.ToggleSettings()
        end
    end)

    bar:SetScale(db.scale or 1)
    bar:SetShown(db.shown ~= false)
    Deadbeat.frame = bar
    ns.bar = bar
    if ns.Items then ns.Items.build(bar) end
    applyLayout()
end

-- --- the module API ------------------------------------------------------------

local Module = {}
Module.__index = Module
ns.Module = Module

function Module:Item(id, opts) return ns.Items.new(self, id, opts or {}, "value") end

-- A frame (width × 14) to draw into; show and hide it as you like.
function Module:Widget(id, opts)
    local item = ns.Items.new(self, id, opts or {}, "widget")
    return item.canvas, item
end

function Module:Tooltip(fn) self.tooltip = fn end
function Module:Click(fn, hint) self.click, self.clickHint = fn, hint end

function Module:Claim(what, on)
    if what ~= "farm" then return end
    claims[self.name] = on and true or nil
    updateContext()
end

function Module:OnContext(fn) self.contextFn = fn end
function Module:OnLayout(fn) self.layoutFn = fn end

function Module:Options(page)
    self.pages[#self.pages + 1] = page.title
    ns.Settings.add(self, page)
end

function Module:Dock(frame)
    docked[#docked + 1] = frame
    frame:HookScript("OnShow", relayoutDock)
    frame:HookScript("OnHide", relayoutDock)
    relayoutDock()
end

-- --- 1.x, kept working one more major (spec 2.0 §legacy) --------------------------------------------------

local LEGACY_FIELDS = { "label", "clock", "primary", "secondary" }

local function legacyNote(m)
    if m.legacyNoted then return end
    m.legacyNoted = true
    DEFAULT_CHAT_FRAME:AddMessage(("|cffd8a446Deadbeat|r: %s uses the old (1.x) API; it works, but should move to items")
        :format(m.name))
end

local function legacyDraw(m)
    if not m.legacyItem then m.legacyItem = ns.Items.new(m, "legacy", { name = m.name, default = true }, "value") end
    local parts = {}
    for _, f in ipairs(LEGACY_FIELDS) do
        local v = m.fields[f] and m.fields[f].value
        if v and v ~= "" then parts[#parts + 1] = v end
    end
    if #parts > 0 then m.legacyItem:Set(table.concat(parts, "  ·  ")) m.legacyItem:Show() else m.legacyItem:Hide() end
end

function Module:Set(field, value, priority)
    legacyNote(self)
    self.fields[field] = { value = value, priority = priority or 0 }
    legacyDraw(self)
end

function Module:Clear(field)
    self.fields[field] = nil
    if self.legacyItem or next(self.fields) then legacyDraw(self) end
end

function Module:Badge(width, opts)
    legacyNote(self)
    opts = opts or {}
    self.badgeCount = (self.badgeCount or 0) + 1
    local id = opts.id and opts.id:gsub("^[^.]*%.", "") or ("badge" .. self.badgeCount)
    local canvas = self:Widget(id, { name = opts.label or id, width = width, contexts = opts.contexts, default = true })
    return canvas
end

function Module:Section(fn)
    legacyNote(self)
    self.tooltip = function(tip, _, shift) fn(tip, shift) end
end

function Module:OnClick(fn) self.click = function(_, button) fn(button) end end

function Module:Band()
    local f = CreateFrame("Frame", nil, UIParent)        -- 2.0 has no band: draw into nothing
    f:Hide()
    return f
end
function Module:BandPriority() end

-- --- registering -----------------------------------------------------------------

-- a module targeting a newer spec major than this hub: say so once, keep going
local function checkSpec(name, wanted)
    local want, have = tonumber((wanted or ""):match("^(%d+)")), tonumber(SPEC:match("^(%d+)"))
    if want and have and want > have then
        DEFAULT_CHAT_FRAME:AddMessage(("|cffd8a446Deadbeat|r: %s wants spec %s, this Deadbeat has %s: update Deadbeat")
            :format(name, wanted, SPEC))
    end
end

-- Register(name, { icon, spec }) — or 1.x: Register(name, order, { spec })
function Deadbeat.Register(name, a, b)
    for _, m in ipairs(modules) do if m.name == name then return m end end
    local opts = type(a) == "table" and a or b or {}
    if opts.spec then checkSpec(name, opts.spec) end
    local m = setmetatable({ name = name, icon = opts.icon, order = type(a) == "number" and a or nil, items = {},
                             byId = {}, fields = {}, pages = {} }, Module)
    modules[#modules + 1] = m
    return m
end

function Deadbeat.Refresh() render() end

function Deadbeat.RefreshTooltip() if ns.Items then ns.Items.refreshTooltip() end end

-- --- events & commands ---------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("MODIFIER_STATE_CHANGED")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_UPDATE_RESTING" }) do f:RegisterEvent(e) end
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        DeadbeatDB = DeadbeatDB or {}
        db = DeadbeatDB
        ns.db = db
        build()
    elseif event == "PLAYER_LOGIN" then
        Deadbeat.Register("Bar", { icon = "Interface\\Icons\\INV_Misc_Coin_01" }):Options({ title = "Bar",
            icon = "Interface\\Icons\\INV_Misc_Coin_01", rows = {
            { kind = "header", label = "The bar" },
            { kind = "button", label = "Arrange it: drag groups and items, hide and show them", text = "Edit bar",
              run = function() if ns.Edit then ns.Edit.toggle(true) end end },
            { kind = "toggle", label = "Show the bar", get = function() return bar:IsShown() end,
              set = function(on) bar:SetShown(on) db.shown = on end },
            { kind = "slider", label = "Size", min = 0.5, max = 2, step = 0.05, fmt = "%.2f",
              get = function() return db.scale or 1 end,
              set = function(v) db.scale = v bar:SetScale(v) end },
            { kind = "custom", height = 30, build = function(frame, width) ns.Settings.layoutRow(frame, width) end,
              show = function(frame) frame.drawLayout() end },
            { kind = "toggle", label = "Lock the compact bar in place", get = function() return db.locked == true end,
              set = function(on) db.locked = on or nil end },
            { kind = "button", label = "Compact position (shift-drag the bar to move it)", text = "Reset",
              run = function()
                  db.point = nil
                  applyLayout()
              end },
            { kind = "header", label = "What shows where" },
            { kind = "note", label = "The bar adapts to where you are. Switch each item on or off per place." },
            { kind = "custom", height = function() return 30 + 26 * #Deadbeat.Items() end,
              build = function(frame, width) ns.Settings.contextGrid(frame, width) end,
              show = function(frame) if frame.drawGrid then frame.drawGrid() end end },
        } })
        if ns.Broker then ns.Broker.build(db) end
        render()
    elseif event == "ADDON_LOADED" then
        if ns.Broker then ns.Broker.scan() end               -- another addon may have brought LDB objects
    elseif event == "MODIFIER_STATE_CHANGED" then
        Deadbeat.RefreshTooltip()
    else
        updateContext()
    end
end)

SLASH_DEADBEAT1 = "/deadbeat"
SlashCmdList.DEADBEAT = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
    if cmd == "" then
        bar:SetShown(true)
        db.shown = true
        Deadbeat.ToggleSettings()
    elseif cmd == "edit" then
        if ns.Edit then ns.Edit.toggle() end
    elseif cmd == "reset" then
        db.point, db.scale = nil, nil
        bar:SetScale(1)
        applyLayout()
    elseif cmd == "scale" and tonumber(arg) then
        db.scale = math.max(0.5, math.min(2, tonumber(arg)))
        bar:SetScale(db.scale)
    else
        local names = {}
        for _, m in ipairs(modules) do names[#names + 1] = m.name end
        DEFAULT_CHAT_FRAME:AddMessage(("|cffd8a446Deadbeat|r %s · modules: %s · /deadbeat (settings) · edit · reset · scale <n>")
            :format(VERSION, #names > 0 and table.concat(names, ", ") or "none"))
    end
end
