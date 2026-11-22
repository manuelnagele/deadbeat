-- Deadbeat's edit mode (design language §6): the player arranges the bar. Gear → Edit bar (or right-click the gear).
-- Groups get a frame, items breathe. Drag an item within its group to reorder it, past its group to move the whole
-- group (and, full-width, into the zone it lands in), off the bar to hide it. The shelf under the bar lists hidden
-- items ("+" puts one back). Click an item for its options: label, places, hide. Done or Esc ends it.
local _, ns = ...
local K = ns.kit
local P = K.P
local Edit = {}
ns.Edit = Edit

local on = false
local shelf, popup, outline
local boxes = {}
local dragging
local CTX_LABEL = { farm = "Farm", raid = "Raid", dungeon = "Dungeon", city = "City", world = "World" }

function Edit.active() return on end

local function bar() return ns.bar end

local function button(parent, text, width, onClick)
    return ns.Settings.button(parent, text, width, onClick)
end

-- --- the frames that show edit mode ----------------------------------------------------------------------

local function box(i)
    local b = boxes[i]
    if not b then
        b = CreateFrame("Frame", nil, bar())
        b:SetFrameLevel(bar():GetFrameLevel() + 1)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.03)
        b.border = K.border(b, true)
        b.border:SetBackdropBorderColor(P.goldOn[1], P.goldOn[2], P.goldOn[3], 0.55)
        boxes[i] = b
    end
    return b
end

function Edit.redraw()
    if not on then return end
    for _, b in ipairs(boxes) do b:Hide() end
    local i = 0
    for _, m in ipairs(ns.Items.groups()) do
        if m.span then
            i = i + 1
            local b = box(i)
            b:ClearAllPoints()
            b:SetPoint("LEFT", bar(), "LEFT", m.span[1] - 4, 0)
            b:SetSize(m.span[2] - m.span[1] + 8, (bar():GetHeight() or 26) - 6)
            b:Show()
        end
    end
    if shelf and shelf:IsShown() then Edit.drawShelf() end
end

local function buildShelf()
    shelf = CreateFrame("Frame", "DeadbeatShelf", UIParent)
    shelf:SetFrameStrata("DIALOG")
    shelf:SetSize(440, 80)
    shelf:EnableMouse(true)
    K.ground(shelf, 0.96)
    K.border(shelf, true)
    if UISpecialFrames then table.insert(UISpecialFrames, "DeadbeatShelf") end
    shelf.title = K.text(shelf, "GameFontNormal", P.bronze4)
    shelf.title:SetPoint("TOPLEFT", 12, -10)
    shelf.title:SetText("Edit the bar")
    shelf.how = K.text(shelf, "GameFontHighlightSmall", P.warmGrey)
    shelf.how:SetPoint("TOPLEFT", 12, -28)
    shelf.how:SetWidth(416)
    shelf.how:SetJustifyH("LEFT")
    shelf.how:SetWordWrap(true)
    shelf.how:SetText("Drag an item: within its group to reorder it, past its group to move the group, off the bar to hide it. Click an item for its options.")
    local done = button(shelf, "Done", 60, function() Edit.toggle(false) end)
    done:SetPoint("TOPRIGHT", -10, -8)
    shelf.head = K.text(shelf, "GameFontHighlightSmall", P.bronze4)
    shelf.head:SetPoint("TOPLEFT", 12, -60)
    shelf.rows = {}
    shelf:SetScript("OnHide", function() if on then Edit.toggle(false) end end)
    -- items breathe while editing
    local t = 0
    shelf:SetScript("OnUpdate", function(_, elapsed)
        t = t + (elapsed or 0)
        local a = 0.82 + 0.18 * math.cos(t * 3)
        for _, it in ipairs(ns.Items.all()) do if it ~= dragging then it.frame:SetAlpha(a) end end
    end)
    shelf:Hide()
end

function Edit.drawShelf()
    for _, r in ipairs(shelf.rows) do r:Hide() end
    local hidden = {}
    for _, it in ipairs(ns.Items.all()) do if not ns.Items.shown(it) then hidden[#hidden + 1] = it end end
    shelf.head:SetText(#hidden > 0 and "Shelf: hidden items" or "Shelf: empty (every item is on the bar)")
    for i, it in ipairs(hidden) do
        local r = shelf.rows[i]
        if not r then
            r = CreateFrame("Frame", nil, shelf)
            r:SetSize(200, 22)
            r.text = K.text(r, "GameFontHighlightSmall")
            r.text:SetPoint("LEFT", 26, 0)
            r.text:SetWidth(170)
            r.text:SetJustifyH("LEFT")
            r.add = button(r, "+", 20, nil)
            r.add:SetPoint("LEFT")
            shelf.rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 12 + ((i - 1) % 2) * 210, -78 - math.floor((i - 1) / 2) * 24)
        r.text:SetText(K.icon(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark", 13) .. " " .. it.name ..
            "  |cff8f8275" .. it.module.name .. "|r")
        r.add:SetScript("OnClick", function() ns.Items.setShown(it, true) end)
        r:Show()
    end
    shelf:SetHeight(90 + math.ceil(#hidden / 2) * 24)
end

-- --- entering and leaving -------------------------------------------------------------------------------------

function Edit.toggle(want)
    if want == nil then want = not on end
    if want == on then return end
    on = want
    if not shelf then buildShelf() end
    if not outline then
        outline = CreateFrame("Frame", nil, bar())
        outline:SetPoint("TOPLEFT", -3, 3)
        outline:SetPoint("BOTTOMRIGHT", 3, -3)
        local b = K.border(outline, true)
        b:SetBackdropBorderColor(P.goldOn[1], P.goldOn[2], P.goldOn[3], 0.9)
    end
    outline:SetShown(on)
    if on then
        if DeadbeatSettings then DeadbeatSettings:Hide() end
        shelf:ClearAllPoints()
        if Deadbeat.atBottom() then shelf:SetPoint("BOTTOM", Deadbeat.DockEnd(), "TOP", 0, 10)
        else shelf:SetPoint("TOP", Deadbeat.DockEnd(), "BOTTOM", 0, -10) end
        shelf:Show()
        ns.Items.render()
    else
        if popup then popup:Hide() end
        for _, b in ipairs(boxes) do b:Hide() end
        for _, it in ipairs(ns.Items.all()) do it.frame:SetAlpha(1) end
        shelf:Hide()
        ns.Items.render()
    end
end

-- --- dragging ----------------------------------------------------------------------------------------------------

local function cursor()
    local x, y = GetCursorPosition()
    local s = bar():GetEffectiveScale() or 1
    return x / s, y / s
end

function Edit.drag(it)
    dragging = it
    if popup then popup:Hide() end
    it.frame:SetAlpha(1)
    it.frame:SetScript("OnUpdate", function(self)
        local x, y = cursor()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    end)
end

local function moveBefore(list, value, beforeValue)
    for i, v in ipairs(list) do if v == value then table.remove(list, i) break end end
    if beforeValue then
        for i, v in ipairs(list) do if v == beforeValue then table.insert(list, i, value) return end end
    end
    list[#list + 1] = value
end
Edit.moveBefore = moveBefore

-- Where did it land? Off the bar: hide. In its group's span: reorder in the group. Elsewhere: move the group there.
function Edit.dropAt(it, x, y)
    local b, d = bar(), ns.db
    local left, top, bottom = b:GetLeft() or 0, b:GetTop() or 0, b:GetBottom() or 0
    if y > top + 20 or y < bottom - 20 then
        ns.Items.setShown(it, false)
        return "hidden"
    end
    local rx = x - left
    local m = it.module
    local span = m.span or { rx, rx }
    if rx >= span[1] - 6 and rx <= span[2] + 6 then
        local before
        for _, other in ipairs(ns.Items.ordered(m)) do
            if other ~= it and ns.Items.visible(other) then
                local l = (other.frame:GetLeft() or 0) - left
                if rx < l + other:Width() / 2 then before = other.id break end
            end
        end
        moveBefore(d.itemOrder[m.name], it.id, before)
        ns.Items.render()
        return "reordered"
    end
    if ns.full() then
        local w = b:GetWidth() or 1000
        ns.Items.setZone(m, rx < w / 3 and "left" or (rx > 2 * w / 3 and "right" or "center"))
    end
    local before
    for _, g in ipairs(ns.Items.groups()) do
        if g ~= m and g.span and rx < (g.span[1] + g.span[2]) / 2 then before = g.name break end
    end
    moveBefore(d.groups, m.name, before)
    ns.Items.render()
    return "moved"
end

function Edit.drop(it)
    it.frame:SetScript("OnUpdate", nil)
    dragging = nil
    local x, y = cursor()
    Edit.dropAt(it, x, y)
    ns.Items.render()
end

-- --- an item's options -------------------------------------------------------------------------------------------

local function buildPopup()
    popup = CreateFrame("Frame", "DeadbeatItemOptions", UIParent)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetSize(300, 150)
    popup:EnableMouse(true)
    K.ground(popup, 0.97)
    K.border(popup, true)
    if UISpecialFrames then table.insert(UISpecialFrames, "DeadbeatItemOptions") end
    popup.title = K.text(popup, "GameFontNormal", P.bronze4)
    popup.title:SetPoint("TOPLEFT", 12, -10)
    local labelRow = CreateFrame("Frame", nil, popup)
    labelRow:SetSize(276, 26)
    labelRow:SetPoint("TOPLEFT", 12, -32)
    local lt = K.text(labelRow, "GameFontHighlightSmall")
    lt:SetPoint("LEFT")
    lt:SetText("Show its name after the value")
    popup.labelSwitch = ns.Settings.toggle(labelRow, {
        get = function() return popup.item and ns.Items.showLabel(popup.item) end,
        set = function(v) if popup.item then ns.Items.setLabel(popup.item, v) end end })
    popup.labelSwitch:SetPoint("RIGHT")
    local places = K.text(popup, "GameFontHighlightSmall", P.warmGrey)
    places:SetPoint("TOPLEFT", 12, -66)
    places:SetText("Shows in")
    popup.places = {}
    for i, ctx in ipairs(Deadbeat.CONTEXTS) do
        local b = button(popup, CTX_LABEL[ctx], 52, nil)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * 55, -84)
        b:SetScript("OnClick", function()
            local it = popup.item
            if not it then return end
            ns.Items.setAllowed(it, ctx, not ns.Items.allowed(it, ctx))
            Edit.drawPopup()
        end)
        b.ctx = ctx
        popup.places[i] = b
    end
    local hide = button(popup, "Hide (to the shelf)", 130, function()
        if popup.item then ns.Items.setShown(popup.item, false) end
        popup:Hide()
    end)
    hide:SetPoint("BOTTOMLEFT", 12, 12)
    local close = button(popup, "Close", 60, function() popup:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -12, 12)
    popup:Hide()
end

function Edit.drawPopup()
    local it = popup.item
    popup.title:SetText(it.module.name .. "  ·  " .. it.name)
    popup.labelSwitch.draw()
    for _, b in ipairs(popup.places) do
        local yes = ns.Items.allowed(it, b.ctx)
        local c = yes and K.GREEN or P.warmGrey
        b.text:SetTextColor(c[1], c[2], c[3])
    end
end

function Edit.click(it)
    if not popup then buildPopup() end
    popup.item = it
    popup:ClearAllPoints()
    if Deadbeat.atBottom() then popup:SetPoint("BOTTOM", it.frame, "TOP", 0, 12)
    else popup:SetPoint("TOP", it.frame, "BOTTOM", 0, -12) end
    Edit.drawPopup()
    popup:Show()
end

function Edit.enter(it)
    local tip = GameTooltip
    if Deadbeat.atBottom() then tip:SetOwner(it.frame, "ANCHOR_TOP", 0, 4) else tip:SetOwner(it.frame, "ANCHOR_BOTTOM", 0, -4) end
    tip:AddLine(it.module.name .. "  ·  " .. it.name, P.bronze4[1], P.bronze4[2], P.bronze4[3])
    tip:AddLine("Drag: move  ·  Click: options", P.warmGrey[1], P.warmGrey[2], P.warmGrey[3])
    tip:Show()
end
