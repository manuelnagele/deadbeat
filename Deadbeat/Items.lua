-- Deadbeat's items (design language §2–5, §7): every module's items, grouped per module with a divider between
-- groups, laid out compact (one row, growing to 760 px, the rest behind "…") or full-width (left, centre, right
-- zones). One interaction everywhere: hover = the module's tooltip for that item, left-click = its action,
-- right-click = its settings, shift-drag = move the bar. The player's arrangement lives in DeadbeatDB.
local _, ns = ...
local K = ns.kit
local P = K.P
local Items = {}
ns.Items = Items

local RING = "Interface\\AddOns\\Deadbeat\\Textures\\ring"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MAX_WIDTH, STEP, GAP, PAD, DIV = 760, 24, 12, 10, 10
local CREAM = { 1, 0.93, 0.80 }
local STATES = { normal = CREAM, good = K.GREEN, warn = P.goldOn, bad = K.RED }
Items.STATES = STATES

local all = {}                       -- every item, in creation order
local bar
local dividers, lights = {}, {}
local hovered
local overflow = { items = {} }      -- the "…" item and the items behind it

local function db() return ns.db end
local function context() return Deadbeat.Context() end

-- --- the player's choices ----------------------------------------------------------------------------------

function Items.shown(it)                                    -- on the bar (else on the shelf)
    local s = db().items and db().items[it.key]
    if s == "show" then return true elseif s == "hide" then return false end
    return it.default
end

function Items.setShown(it, on)
    db().items = db().items or {}
    if on == it.default then db().items[it.key] = nil else db().items[it.key] = on and "show" or "hide" end
    Items.render()
end

function Items.allowed(it, ctx)                              -- in this place
    local mine = db().itemCtx and db().itemCtx[it.key]
    if mine and mine[ctx] ~= nil then return mine[ctx] end
    return not it.contexts or it.contexts[ctx] == true
end

function Items.setAllowed(it, ctx, on)
    db().itemCtx = db().itemCtx or {}
    db().itemCtx[it.key] = db().itemCtx[it.key] or {}
    db().itemCtx[it.key][ctx] = on
    Items.render()
end

function Items.showLabel(it) return db().labels and db().labels[it.key] == true end
function Items.setLabel(it, on)
    db().labels = db().labels or {}
    db().labels[it.key] = on or nil
    it:Set(it.value, it.state)
end

function Items.visible(it)
    return it:IsShown() and Items.shown(it) and Items.allowed(it, context())
end

-- groups in the player's order; a new module appends at the end
function Items.groups()
    local d = db()
    d.groups = d.groups or {}
    local known = {}
    for _, name in ipairs(d.groups) do known[name] = true end
    for _, m in ipairs(ns.modules) do
        if #m.items > 0 and not known[m.name] then d.groups[#d.groups + 1] = m.name known[m.name] = true end
    end
    local byName, out = {}, {}
    for _, m in ipairs(ns.modules) do byName[m.name] = m end
    for _, name in ipairs(d.groups) do if byName[name] and #byName[name].items > 0 then out[#out + 1] = byName[name] end end
    return out
end

-- a module's items in the player's order; a new item appends to its group
function Items.ordered(m)
    local d = db()
    d.itemOrder = d.itemOrder or {}
    local list = d.itemOrder[m.name] or {}
    d.itemOrder[m.name] = list
    local known = {}
    for _, id in ipairs(list) do known[id] = true end
    for _, it in ipairs(m.items) do if not known[it.id] then list[#list + 1] = it.id end end
    local out = {}
    for _, id in ipairs(list) do if m.byId[id] then out[#out + 1] = m.byId[id] end end
    return out
end

function Items.zone(m) return (db().zones and db().zones[m.name]) or "right" end
function Items.setZone(m, zone)
    db().zones = db().zones or {}
    db().zones[m.name] = zone ~= "right" and zone or nil
    Items.render()
end

-- --- an item ---------------------------------------------------------------------------------------------

local Item = {}
Item.__index = Item

function Item:Set(value, state)
    self.value, self.state = value and tostring(value) or "", STATES[state] and state or "normal"
    local f = self.frame
    if f.value then
        f.value:SetText(self.value)
        local c = STATES[self.state]
        f.value:SetTextColor(c[1], c[2], c[3])
        f.label:SetText(Items.showLabel(self) and self.name or "")
    end
    Items.render()
end

function Item:SetIcon(path)
    self.icon = path
    if self.frame.icon then self.frame.icon:SetTexture(path or "Interface\\Icons\\INV_Misc_QuestionMark") end
end

function Item:Show() if self.canvas then self.canvas:Show() else self.wanted = true Items.render() end end
function Item:Hide() if self.canvas then self.canvas:Hide() else self.wanted = false Items.render() end end
-- A widget is wanted while its module keeps the canvas shown: the canvas's own flag (IsShown), never its visibility,
-- which also goes when the bar hides the item frame around it (that once hid Lockout's diamonds for good).
function Item:IsShown()
    if self.canvas then return self.canvas:IsShown() == true end
    return self.wanted
end

function Item:Width()
    if self.canvas then return math.max(1, self.canvas:GetWidth() or 1) end
    local f, w = self.frame, 14
    if self.value ~= "" then w = w + 4 + (f.value:GetStringWidth() or 0) end
    if Items.showLabel(self) then w = w + 4 + (f.label:GetStringWidth() or 0) end
    return math.floor(w + 0.5)
end

local function makeFrame(it, opts)
    local f = CreateFrame("Button", nil, bar)
    f:SetSize(40, 16)
    f:SetFrameLevel(bar:GetFrameLevel() + 2)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:RegisterForDrag("LeftButton")
    f.item = it
    if it.kind == "widget" then
        local c = CreateFrame("Frame", nil, f)
        c:SetSize(opts.width or 40, 14)
        c:SetPoint("LEFT")
        c.item = it
        -- the module shows or hides its canvas: lay out again (not while the bar itself is hiding and showing frames)
        c:HookScript("OnShow", function() if not Items.rendering then Items.render() end end)
        c:HookScript("OnHide", function() if not Items.rendering then Items.render() end end)
        it.canvas = c
    else
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetSize(14, 14)
        f.icon:SetPoint("LEFT")
        f.icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        if f.CreateMaskTexture then
            local mask = f:CreateMaskTexture()
            mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(f.icon)
            f.icon:AddMaskTexture(mask)
        end
        f.ring = f:CreateTexture(nil, "OVERLAY")
        f.ring:SetTexture(RING)
        f.ring:SetSize(17, 17)
        f.ring:SetPoint("CENTER", f.icon)
        f.ring:SetVertexColor(P.bronze3[1], P.bronze3[2], P.bronze3[3], 1)
        f.value = K.text(f, "GameFontHighlightSmall", CREAM)
        f.value:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
        f.label = K.text(f, "GameFontNormalSmall", P.warmGrey)
        f.label:SetPoint("LEFT", f.value, "RIGHT", 4, 0)
    end
    f:SetScript("OnEnter", function() Items.enter(it) end)
    f:SetScript("OnLeave", function() Items.leave(it) end)
    f:SetScript("OnClick", function(_, button) Items.click(it, button) end)
    f:SetScript("OnDragStart", function()
        if ns.Edit and ns.Edit.active() then ns.Edit.drag(it) else ns.startMove() end
    end)
    f:SetScript("OnDragStop", function()
        if ns.Edit and ns.Edit.active() then ns.Edit.drop(it) else ns.stopMove() end
    end)
    f:Hide()
    return f
end

function Items.new(m, id, opts, kind)
    if m.byId[id] then return m.byId[id] end
    local it = setmetatable({ module = m, id = id, key = m.name .. "." .. id, name = opts.name or id,
                              icon = opts.icon or m.icon, kind = opts.kind or kind, default = opts.default ~= false,
                              contexts = opts.contexts, value = "", state = "normal", wanted = true }, Item)
    it.frame = makeFrame(it, opts)
    m.byId[id] = it
    m.items[#m.items + 1] = it
    all[#all + 1] = it
    Items.render()
    return it
end

-- every item, in the bar's order (for the console and edit mode)
function Items.all()
    local out = {}
    for _, m in ipairs(Items.groups()) do for _, it in ipairs(Items.ordered(m)) do out[#out + 1] = it end end
    return out
end
function Deadbeat.Items() return Items.all() end

-- --- layout ------------------------------------------------------------------------------------------------

local function divider(i, x)
    local d = dividers[i]
    if not d then
        d = bar:CreateTexture(nil, "ARTWORK")
        d:SetSize(1, 12)
        d:SetColorTexture(P.bronze2[1], P.bronze2[2], P.bronze2[3], 0.7)
        dividers[i] = d
    end
    d:ClearAllPoints()
    d:SetPoint("LEFT", bar, "LEFT", x, 0)
    d:Show()
end

-- one group's items from x (left to right); returns the x after it, and the group's span
local function placeGroup(m, list, x)
    local left = x
    for i, it in ipairs(list) do
        local w = it:Width()
        it.frame:SetWidth(w)
        it.frame:ClearAllPoints()
        it.frame:SetPoint("LEFT", bar, "LEFT", x, 0)
        it.frame:Show()
        x = x + w + (i < #list and GAP or 0)
    end
    m.span = { left, x }
    return x
end

local function groupWidth(list)
    local w = -GAP
    for _, it in ipairs(list) do w = w + it:Width() + GAP end
    return math.max(0, w)
end

-- the system items at the right end: the LDB tray, "…" (compact overflow), the gear
local function systemWidth()
    local w = 16
    if ns.tray and ns.tray:IsShown() then w = w + 14 + GAP end
    if overflow.button and #overflow.items > 0 then w = w + 12 + GAP end
    return w
end

local function placeSystem()
    local x = -8
    bar.gear:ClearAllPoints()
    bar.gear:SetPoint("RIGHT", bar, "RIGHT", x, 0)
    x = x - 16 - GAP
    if overflow.button then
        overflow.button:SetShown(#overflow.items > 0)
        if #overflow.items > 0 then
            overflow.button:ClearAllPoints()
            overflow.button:SetPoint("RIGHT", bar, "RIGHT", x, 0)
            x = x - 12 - GAP
        end
    end
    if ns.tray and ns.tray:IsShown() then
        ns.tray:ClearAllPoints()
        ns.tray:SetPoint("RIGHT", bar, "RIGHT", x, 0)
    end
end

function Items.render()
    if not bar or not db() or Items.rendering then return end
    Items.rendering = true
    local ok, err = pcall(Items.layout)
    Items.rendering = false
    if not ok then error(err, 0) end
end

function Items.layout()
    for _, it in ipairs(all) do it.frame:Hide() end
    for _, d in ipairs(dividers) do d:Hide() end
    overflow.items = {}
    local groups = {}
    for _, m in ipairs(Items.groups()) do
        local list = {}
        for _, it in ipairs(Items.ordered(m)) do if Items.visible(it) then list[#list + 1] = it end end
        m.span = nil
        if #list > 0 then groups[#groups + 1] = { m = m, list = list } end
    end
    local nd = 0
    if not ns.full() then
        -- compact: one row; past MAX_WIDTH the last groups go behind "…"
        local sys = systemWidth()
        local x = PAD
        for gi, g in ipairs(groups) do
            local w = groupWidth(g.list)
            local start = gi == 1 and x or x + DIV + 1 + DIV
            if start + w + DIV + 1 + DIV + sys + 12 + GAP + PAD > MAX_WIDTH then
                for i = gi, #groups do for _, it in ipairs(groups[i].list) do overflow.items[#overflow.items + 1] = it end end
                break
            end
            if gi > 1 then nd = nd + 1 divider(nd, x + DIV) end
            x = placeGroup(g.m, g.list, start)
        end
        local endX = (#groups > 0 and (x + DIV + 1 + DIV) or PAD)
        local want = math.min(MAX_WIDTH, math.ceil((endX + systemWidth() + 8) / STEP) * STEP)
        local current = bar:GetWidth() or want
        if want > current or want <= current - 2 * STEP then bar:SetWidth(want) end
        -- the divider before the system items sits by them (the bar may be a step wider than its content)
        if #groups > 0 then nd = nd + 1 divider(nd, (bar:GetWidth() or want) - 8 - systemWidth() - DIV - 1) end
    else
        -- full-width: left zone from the left, right zone up to the system items, centre in the middle
        local zones = { left = {}, center = {}, right = {} }
        for _, g in ipairs(groups) do local z = zones[Items.zone(g.m)] or zones.right z[#z + 1] = g end
        local x = PAD
        for gi, g in ipairs(zones.left) do
            if gi > 1 then nd = nd + 1 divider(nd, x + DIV) x = x + DIV + 1 + DIV end
            x = placeGroup(g.m, g.list, x)
        end
        local total = 0
        for gi, g in ipairs(zones.center) do total = total + groupWidth(g.list) + (gi > 1 and (2 * DIV + 1) or 0) end
        x = math.floor((bar:GetWidth() or 1000) / 2 - total / 2)
        for gi, g in ipairs(zones.center) do
            if gi > 1 then nd = nd + 1 divider(nd, x + DIV) x = x + DIV + 1 + DIV end
            x = placeGroup(g.m, g.list, x)
        end
        local right = (bar:GetWidth() or 1000) - PAD - systemWidth() - DIV - 1 - DIV
        if #zones.right > 0 then nd = nd + 1 divider(nd, right + DIV) end
        for gi = #zones.right, 1, -1 do
            local g = zones.right[gi]
            local w = groupWidth(g.list)
            placeGroup(g.m, g.list, right - w)
            right = right - w
            if gi > 1 then nd = nd + 1 divider(nd, right - DIV - 1) right = right - 2 * DIV - 1 end
        end
    end
    placeSystem()
    if ns.Edit and ns.Edit.active() then ns.Edit.redraw() end
end

-- --- hover, tooltips, clicks ----------------------------------------------------------------------------------

local function light(m, on)
    local l = lights[1]
    if not l then
        l = bar:CreateTexture(nil, "BACKGROUND", nil, 2)
        l:SetColorTexture(1, 1, 1, 0.04)
        lights[1] = l
    end
    l:SetShown(on and m.span ~= nil)
    if on and m.span then
        l:ClearAllPoints()
        l:SetPoint("LEFT", bar, "LEFT", m.span[1] - 5, 0)
        l:SetSize(m.span[2] - m.span[1] + 10, (bar:GetHeight() or 26) - 6)
    end
end

local function hint(it)
    local m, parts = it.module, {}
    local h = m.clickHint
    if type(h) == "function" then local ok, v = pcall(h, it) h = ok and v or nil end
    if m.click and h and h ~= "" then parts[#parts + 1] = "Click: " .. h end
    if #m.pages > 0 and not m.passRightClick then parts[#parts + 1] = "Right-click: settings" end
    return table.concat(parts, "  ·  ")
end

function Items.enter(it)
    hovered = it
    light(it.module, true)
    if ns.Edit and ns.Edit.active() then ns.Edit.enter(it) return end
    if ns.Broker and ns.Broker.trayOpen() then return end
    local m = it.module
    if m.enter and m.enter(it) then return end            -- an LDB object that draws its own tooltip
    local tip = GameTooltip
    if Deadbeat.atBottom() then tip:SetOwner(it.frame, "ANCHOR_TOP", 0, 4) else tip:SetOwner(it.frame, "ANCHOR_BOTTOM", 0, -4) end
    local icon = m.icon or it.icon
    local title = m.itemOnlyHeader and it.name or (m.name .. ((it.name ~= m.name) and ("  ·  " .. it.name) or ""))
    tip:AddLine((icon and (K.icon(icon, 14) .. " ") or "") .. title, P.bronze4[1], P.bronze4[2], P.bronze4[3])
    if m.tooltip then
        local ok, err = pcall(m.tooltip, tip, it, IsShiftKeyDown())
        if not ok then tip:AddLine("|cffff4040" .. tostring(err) .. "|r") end
    end
    local h = hint(it)
    if h ~= "" then tip:AddLine(h, P.warmGrey[1], P.warmGrey[2], P.warmGrey[3]) end
    tip:Show()
end

function Items.leave(it)
    hovered = nil
    light(it.module, false)
    if it.module.leave then it.module.leave(it) else GameTooltip:Hide() end
end

function Items.refreshTooltip()
    if hovered and GameTooltip:IsOwned(hovered.frame) then Items.enter(hovered) end
end

function Items.click(it, button)
    if ns.Edit and ns.Edit.active() then ns.Edit.click(it, button) return end
    local m = it.module
    if button == "RightButton" and not m.passRightClick then
        if m.pages[1] then Deadbeat.OpenSettings(m.pages[1]) end
        return
    end
    if m.click then
        local ok, err = pcall(m.click, it, button)
        if not ok then DEFAULT_CHAT_FRAME:AddMessage("|cffd8a446Deadbeat|r: " .. m.name .. ": " .. tostring(err)) end
    end
    Items.refreshTooltip()
end

-- --- the "…" overflow (compact) ------------------------------------------------------------------------------------

local function buildOverflow()
    local b = CreateFrame("Button", "DeadbeatOverflow", bar)
    b:SetSize(12, 16)
    b:SetFrameLevel(bar:GetFrameLevel() + 3)
    b.text = K.text(b, "GameFontHighlightSmall", P.bronze4)
    b.text:SetPoint("CENTER")
    b.text:SetText("…")
    local menu = CreateFrame("Frame", "DeadbeatOverflowMenu", UIParent)
    menu:SetFrameStrata("DIALOG")
    K.ground(menu, 0.96)
    K.border(menu, true)
    menu:Hide()
    menu.rows = {}
    local function open()
        for _, r in ipairs(menu.rows) do r:Hide() end
        for i, it in ipairs(overflow.items) do
            local r = menu.rows[i]
            if not r then
                r = CreateFrame("Button", nil, menu)
                r:SetSize(220, 20)
                r.text = K.text(r, "GameFontHighlightSmall")
                r.text:SetPoint("LEFT", 6, 0)
                local hi = r:CreateTexture(nil, "HIGHLIGHT")
                hi:SetAllPoints()
                hi:SetColorTexture(P.bronze4[1], P.bronze4[2], P.bronze4[3], 0.15)
                menu.rows[i] = r
            end
            r:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 20)
            r.text:SetText(K.icon(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark", 13) .. "  " ..
                (it.value ~= "" and (it.value .. "  ") or "") .. "|cff8f8275" .. it.name .. "|r")
            r:SetScript("OnClick", function(_, button) menu:Hide() Items.click(it, button) end)
            r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            r:Show()
        end
        menu:SetSize(232, 12 + #overflow.items * 20)
        menu:ClearAllPoints()
        if Deadbeat.atBottom() then menu:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", 8, 12)
        else menu:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 8, -12) end
        menu:Show()
    end
    b:SetScript("OnClick", function() if menu:IsShown() then menu:Hide() else open() end end)
    local away = 0
    menu:SetScript("OnUpdate", function(self, elapsed)
        local over = (self.IsMouseOver and self:IsMouseOver()) or (bar.IsMouseOver and bar:IsMouseOver())
        if over then away = 0 return end
        away = away + (elapsed or 0)
        if away > 0.6 then away = 0 self:Hide() end
    end)
    b:Hide()
    overflow.button = b
end

function Items.build(b)
    bar = b
    buildOverflow()
end
