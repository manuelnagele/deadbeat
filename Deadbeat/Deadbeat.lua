-- Deadbeat: one bar that every module contributes to (compact or full-width); it draws the bar, its tooltip and the
-- settings console and knows nothing about gold, fish or lockouts. The contract: deadbeat-spec (spec.md, AGENTS.md).
--
--   local m = Deadbeat.Register("Hello", 70, { spec = "1.0" }) -- order: left/top first; spec: what you target
--   m:Set("label", "Maraudon · run 3", 20)           -- fields: label, clock, primary, secondary; highest priority wins
--   m:Clear("label")
--   local f = m:Badge(width, { id, label, contexts }) -- a frame on the right of the strip, yours to draw into;
--                                                    -- shown in its contexts (the user can change them in the console)
--   m:Claim("farm", on)                              -- you're farming (Catch while fishing): the bar's context is "farm"
--   m:OnContext(function(ctx) ... end)               -- farm / raid / dungeon / city / world
--   local band = m:Band(priority)                    -- the lower band (sparkline area); highest priority shows
--   m:Section(function(tip, shift) ... end)          -- your part of the tooltip; shift = nerd stats
--   m:OnClick(function(button) ... end)              -- clicks go to the module that owns the label
--   m:Dock(frame)                                    -- a panel stacked under the strip
--   m:Options({ title, icon, rows = { ... } })       -- a page in the settings console (the gear); see Settings.lua
--   Deadbeat.kit                                     -- palette, soft colours, coins, borders, fonts
--   Deadbeat.Layout()                                -- "compact" | "top" | "bottom" (full-width edge bar)
local ADDON, ns = ...
local K = ns.kit
local VERSION = "1.0.0"
local SPEC = "1.0"                 -- the spec version this hub implements (deadbeat-spec/spec.md)

Deadbeat = { kit = K, version = VERSION, SPEC = SPEC }

local FIELDS = { "label", "clock", "primary", "secondary" }
local CONTEXTS = { "farm", "raid", "dungeon", "city", "world" }
Deadbeat.CONTEXTS = CONTEXTS
local MIN_WIDTH, MAX_WIDTH, STEP = 420, 760, 24
local COMPACT_H, FULL_H = 34, 22
local claims = {}              -- module name -> true while it claims "farm"
local context = "world"
local modules = {}             -- in registration order; sorted by order on use
local bar, db
local docked = {}

local function sorted()
    local list = {}
    for _, m in ipairs(modules) do list[#list + 1] = m end
    table.sort(list, function(a, b) return a.order < b.order end)
    return list
end

-- --- layout --------------------------------------------------------------------

local function owner(field)
    local best
    for _, m in ipairs(modules) do
        local f = m.fields[field]
        if f and f.value ~= nil and (not best or f.priority > best.fields[field].priority
                or (f.priority == best.fields[field].priority and m.order < best.order)) then
            best = m
        end
    end
    return best
end

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

-- a badge shows in a context: the user's choice, else the module's default, else everywhere
local function allowed(badge)
    local id = badge.opts and badge.opts.id
    local mine = id and db and db.badgeCtx and db.badgeCtx[id]
    if mine and mine[context] ~= nil then return mine[context] end
    local defaults = badge.opts and badge.opts.contexts
    return not defaults or defaults[context] == true
end
Deadbeat.badgeAllowed = function(badge, ctx)
    local saved = context
    context = ctx
    local on = allowed(badge)
    context = saved
    return on
end

-- --- layout: one bar, compact (centred, movable) or full-width on the top or bottom edge ----------------

function Deadbeat.Layout() return (db and db.layout) or "compact" end
local function full() return Deadbeat.Layout() ~= "compact" end
local function atBottom() return Deadbeat.Layout() == "bottom" end
Deadbeat.atBottom = atBottom

function Deadbeat.BadgeZone(badge)
    local id = badge.opts and badge.opts.id
    return (id and db and db.badgeZone and db.badgeZone[id]) or "right"
end

function Deadbeat.SetBadgeZone(badge, zone)
    db.badgeZone = db.badgeZone or {}
    db.badgeZone[badge.opts.id] = zone ~= "right" and zone or nil
    Deadbeat.Refresh()
end

local render, render_compact
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

function render()
    if not bar then return end
    for _, field in ipairs(FIELDS) do
        local m = owner(field)
        bar[field]:SetText(m and m.fields[field].value or "")
    end
    if not owner("label") then bar.label:SetText("Deadbeat") end
    -- badges right to left in module order, left of the gear; each only in its contexts. Full-width: a badge may
    -- sit in the centre zone instead.
    local wide = full()
    local y = wide and -4 or -7
    local x = -30
    local centre = {}
    local list = sorted()
    for i = #list, 1, -1 do
        for _, b in ipairs(list[i].badges) do
            local show = b:IsShown() and allowed(b)
            b.holder:SetShown(show)
            if show then
                b.holder:SetSize(b:GetWidth(), b:GetHeight())
                b.holder:ClearAllPoints()
                if wide and Deadbeat.BadgeZone(b) == "center" then
                    table.insert(centre, 1, b)
                else
                    b.holder:SetPoint("TOPRIGHT", bar, "TOPRIGHT", x, y)
                    x = x - b:GetWidth() - 10
                end
            end
        end
    end
    if #centre > 0 then
        local total = -10
        for _, b in ipairs(centre) do total = total + b:GetWidth() + 10 end
        local cx = -total / 2
        for _, b in ipairs(centre) do
            b.holder:SetPoint("TOPLEFT", bar, "TOP", cx, y)
            cx = cx + b:GetWidth() + 10
        end
    end
    if wide then
        -- full-width: fields in the left zone, one after the other; the label may take up to 360 px
        local full_ = (bar.label.GetUnboundedStringWidth and bar.label:GetUnboundedStringWidth()) or (bar.label:GetStringWidth() or 0)
        bar.label:SetWidth(math.max(30, math.min(full_ + 2, 360)))
        bar.secondary:ClearAllPoints()
        bar.secondary:SetPoint("LEFT", bar.primary, "RIGHT", 14, 0)
    else
        render_compact(x)
    end
    -- the band: only the highest priority shows
    local top
    for _, m in ipairs(modules) do
        if m.band and m.band.wanted and (not top or m.band.priority > top.band.priority) then top = m end
    end
    for _, m in ipairs(modules) do
        if m.band then m.band:SetShown(m == top) end
    end
end

-- compact: the bar grows to fit what it has to say, the secondary sits before the badges
render_compact = function(x)
    local function w(fs) return fs:GetStringWidth() or 0 end
    local labelFull = (bar.label.GetUnboundedStringWidth and bar.label:GetUnboundedStringWidth()) or w(bar.label)
    local needed = 10 + labelFull + 6 + w(bar.clock) + 14 + w(bar.primary) + 8 + w(bar.secondary) + 12 - x + 4
    -- in 24 px steps, growing at once but shrinking only after a clear drop: a ticking clock ("34:50" → "34:51")
    -- must not resize the centred bar every second (0.4.0 jittered)
    local want = math.max(MIN_WIDTH, math.min(MAX_WIDTH, math.ceil(needed / STEP) * STEP))
    local current = bar:GetWidth() or MIN_WIDTH
    if want > current or want <= current - 2 * STEP then bar:SetWidth(want) end
    bar.secondary:ClearAllPoints()
    bar.secondary:SetPoint("TOPRIGHT", bar, "TOPRIGHT", x - 2, -9)
    -- the label gets what's left; a long one is cut with "…" instead of running into the numbers
    local function width(fs) return fs:GetStringWidth() or 0 end
    local right = -x + 2 + width(bar.secondary) + 12
    local used = 10 + 6 + width(bar.clock) + 14 + width(bar.primary) + 8
    local room = (bar:GetWidth() or MIN_WIDTH) - right - used
    local full_ = (bar.label.GetUnboundedStringWidth and bar.label:GetUnboundedStringWidth()) or width(bar.label)
    bar.label:SetWidth(math.max(30, math.min(full_ + 2, room)))
end

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
        bar:SetSize(MIN_WIDTH, COMPACT_H)
    end
    bar.border:SetShown(not wide)
    bar.edge:SetShown(wide)
    bar.edge:ClearAllPoints()
    bar.edge:SetPoint(bottom and "TOPLEFT" or "BOTTOMLEFT")
    bar.edge:SetPoint(bottom and "TOPRIGHT" or "BOTTOMRIGHT")
    local ty = wide and -6 or -9
    bar.label:ClearAllPoints()
    bar.label:SetPoint("TOPLEFT", 10, ty)
    bar.gear:ClearAllPoints()
    bar.gear:SetPoint("TOPRIGHT", -8, wide and -3 or -6)
    -- the band: the lower 9 px of the compact bar; a 3 px line along the inner edge of a full-width one
    bar.band:ClearAllPoints()
    if wide then
        bar.band:SetPoint(bottom and "TOPLEFT" or "BOTTOMLEFT", 0, bottom and -1 or 1)
        bar.band:SetPoint(bottom and "TOPRIGHT" or "BOTTOMRIGHT", 0, bottom and -1 or 1)
        bar.band:SetHeight(3)
    else
        bar.band:SetPoint("BOTTOMLEFT", 8, 5)
        bar.band:SetPoint("BOTTOMRIGHT", -8, 5)
        bar.band:SetHeight(9)
    end
    render()
    relayoutDock()
end

function Deadbeat.SetLayout(layout)
    db.layout = layout ~= "compact" and layout or nil
    applyLayout()
    for _, m in ipairs(modules) do if m.layoutFn then pcall(m.layoutFn, Deadbeat.Layout()) end end
end

-- --- the tooltip ---------------------------------------------------------------

local function showTooltip(self)
    if ns.Broker and ns.Broker.trayOpen() then return end       -- the tray drops down where the tooltip would
    local tip = GameTooltip
    if atBottom() then tip:SetOwner(self, "ANCHOR_TOP", 0, 4) else tip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4) end
    local shift = IsShiftKeyDown()
    local first = true
    for _, m in ipairs(sorted()) do
        if m.section then
            local before = tip:NumLines()
            if not first then tip:AddLine(" ") end
            local ok, err = pcall(m.section, tip, shift)
            if not ok then tip:AddLine("|cffff4040" .. m.name .. ": " .. tostring(err) .. "|r") end
            if tip:NumLines() > before + (first and 0 or 1) then first = false end
        end
    end
    local g = K.P.warmGrey
    if not first then tip:AddLine(" ") end
    tip:AddLine(shift and "Shift-drag: move  ·  /deadbeat" or "Shift: nerd stats", g[1], g[2], g[3])
    tip:Show()
end

function Deadbeat.RefreshTooltip()
    if bar and GameTooltip:IsOwned(bar) then showTooltip(bar) end
end

-- --- the bar -------------------------------------------------------------------

local function build()
    bar = CreateFrame("Button", "DeadbeatBar", UIParent)
    bar:SetSize(MIN_WIDTH, COMPACT_H)
    K.ground(bar)
    bar.border = K.border(bar, true)
    bar.edge = bar:CreateTexture(nil, "BORDER")                 -- full-width: a bronze line on the inner edge
    bar.edge:SetHeight(1)
    bar.edge:SetColorTexture(K.P.bronze3[1], K.P.bronze3[2], K.P.bronze3[3], 1)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    bar:RegisterForClicks("AnyUp")
    bar:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() and not full() and not db.locked then self:StartMoving() end
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        db.point = { point, rel, x, y }
    end)
    bar:SetScript("OnClick", function(_, button)
        local m = owner("label")
        if m and m.click then m.click(button) render() Deadbeat.RefreshTooltip() end
    end)
    bar:SetScript("OnEnter", showTooltip)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local P = K.P
    bar.label = K.text(bar, "GameFontNormalSmall", P.bronze4)
    bar.label:SetPoint("TOPLEFT", 10, -9)
    bar.label:SetJustifyH("LEFT")
    bar.clock = K.text(bar, "GameFontHighlightSmall", P.warmGrey)
    bar.clock:SetPoint("LEFT", bar.label, "RIGHT", 6, 0)
    bar.primary = K.text(bar, "GameFontHighlight")
    bar.primary:SetPoint("LEFT", bar.clock, "RIGHT", 14, 0)
    bar.secondary = K.text(bar, "GameFontHighlightSmall")
    bar.secondary:SetJustifyH("RIGHT")

    -- the gear: every module's settings
    bar.gear = CreateFrame("Button", "DeadbeatGear", bar)
    bar.gear:SetSize(16, 16)
    bar.gear:SetPoint("TOPRIGHT", -8, -6)
    bar.gear:SetFrameLevel(bar:GetFrameLevel() + 5)
    local gear = bar.gear:CreateTexture(nil, "ARTWORK")
    gear:SetAllPoints()
    gear:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetVertexColor(P.bronze4[1], P.bronze4[2], P.bronze4[3])
    bar.gear:SetAlpha(0.5)
    bar.gear:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        if atBottom() then GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4) else GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4) end
        GameTooltip:AddLine("Settings", P.bronze4[1], P.bronze4[2], P.bronze4[3])
        GameTooltip:Show()
    end)
    bar.gear:SetScript("OnLeave", function(self) self:SetAlpha(0.5) GameTooltip:Hide() end)
    bar.gear:SetScript("OnClick", function() Deadbeat.ToggleSettings() end)

    bar.band = CreateFrame("Frame", nil, bar)
    bar.band:SetPoint("BOTTOMLEFT", 8, 5)
    bar.band:SetPoint("BOTTOMRIGHT", -8, 5)
    bar.band:SetHeight(9)

    bar:SetScale(db.scale or 1)
    bar:SetShown(db.shown ~= false)
    Deadbeat.frame = bar
    applyLayout()
end

-- --- the module API ------------------------------------------------------------

local Module = {}
Module.__index = Module

function Module:Set(field, value, priority)
    self.fields[field] = { value = value, priority = priority or 0 }
    render()
end

function Module:Clear(field)
    self.fields[field] = nil
    render()
end

-- The module draws into f and shows/hides it as it likes; Deadbeat shows f's holder only in f's contexts.
function Module:Badge(width, opts)
    local holder = CreateFrame("Frame", nil, bar)
    holder:SetSize(width or 40, 14)
    local f = CreateFrame("Frame", nil, holder)
    f:SetSize(width or 40, 14)
    f:SetPoint("TOPRIGHT", holder, "TOPRIGHT")            -- the module may resize f; render sizes the holder to it
    f.holder, f.opts, f.module = holder, opts or false, self   -- false, not nil: a missing field
    f:HookScript("OnShow", function() render() end)
    f:HookScript("OnHide", function() render() end)
    self.badges[#self.badges + 1] = f
    render()
    return f
end

function Module:Claim(what, on)
    if what ~= "farm" then return end
    claims[self.name] = on and true or nil
    updateContext()
end

function Module:OnContext(fn) self.contextFn = fn end
function Module:OnLayout(fn) self.layoutFn = fn end

-- every badge with an id, for the console's grid
function Deadbeat.Badges()
    local out = {}
    for _, m in ipairs(sorted()) do
        for _, b in ipairs(m.badges) do if b.opts and b.opts.id then out[#out + 1] = b end end
    end
    return out
end

function Deadbeat.SetBadgeContext(badge, ctx, on)
    db.badgeCtx = db.badgeCtx or {}
    db.badgeCtx[badge.opts.id] = db.badgeCtx[badge.opts.id] or {}
    db.badgeCtx[badge.opts.id][ctx] = on
    render()
end

function Module:Band(priority)
    if not self.band then
        self.band = CreateFrame("Frame", nil, bar.band)
        self.band:SetAllPoints(bar.band)
    end
    self.band.priority = priority or 0
    self.band.wanted = true
    render()
    return self.band
end

function Module:BandPriority(priority, wanted)
    if not self.band then return end
    self.band.priority = priority or self.band.priority
    if wanted ~= nil then self.band.wanted = wanted end
    render()
end

function Module:Section(fn) self.section = fn end
function Module:Options(page) ns.Settings.add(self, page) end
function Module:OnClick(fn) self.click = fn end

function Module:Dock(frame)
    docked[#docked + 1] = frame
    frame:HookScript("OnShow", relayoutDock)
    frame:HookScript("OnHide", relayoutDock)
    relayoutDock()
end

-- a module targeting a newer spec major than this hub: say so once, keep going
local function checkSpec(name, wanted)
    local want, have = tonumber((wanted or ""):match("^(%d+)")), tonumber(SPEC:match("^(%d+)"))
    if want and have and want > have then
        DEFAULT_CHAT_FRAME:AddMessage(("|cffd8a446Deadbeat|r: %s wants spec %s, this Deadbeat has %s: update Deadbeat")
            :format(name, wanted, SPEC))
    end
end

function Deadbeat.Register(name, order, opts)
    for _, m in ipairs(modules) do if m.name == name then return m end end
    if opts and opts.spec then checkSpec(name, opts.spec) end
    local m = setmetatable({ name = name, order = order or 50, fields = {}, badges = {} }, Module)
    modules[#modules + 1] = m
    return m
end

function Deadbeat.Refresh() render() end

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
        build()
    elseif event == "PLAYER_LOGIN" then
        Deadbeat.Register("Bar", 0):Options({ title = "Bar", icon = "Interface\\Icons\\INV_Misc_Coin_01", rows = {
            { kind = "header", label = "The bar" },
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
            { kind = "note", label = "The bar adapts to where you are. Switch each badge on or off per place." },
            { kind = "custom", height = function() return 30 + 26 * #Deadbeat.Badges() end,
              build = function(frame, width) ns.Settings.contextGrid(frame, width) end,
              show = function(frame) if frame.drawGrid then frame.drawGrid() end end },
            { kind = "note", label = "Each addon of the family adds its own page here." },
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
    elseif cmd == "reset" then
        db.point, db.scale = nil, nil
        bar:ClearAllPoints()
        bar:SetPoint("TOP", UIParent, "TOP", 0, -40)
        bar:SetScale(1)
    elseif cmd == "scale" and tonumber(arg) then
        db.scale = math.max(0.5, math.min(2, tonumber(arg)))
        bar:SetScale(db.scale)
    else
        local names = {}
        for _, m in ipairs(sorted()) do names[#names + 1] = m.name end
        DEFAULT_CHAT_FRAME:AddMessage(("|cffd8a446Deadbeat|r %s · modules: %s · /deadbeat (show/hide) · reset · scale <n>")
            :format(VERSION, #names > 0 and table.concat(names, ", ") or "none"))
    end
end
