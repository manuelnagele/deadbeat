-- Deadbeat's LibDataBroker bridge: every LDB data object (launchers and data sources from other addons) on the bar
-- without changes to those addons. Launchers sit in one tray badge that drops down a grid of icons; any object can be
-- pinned as its own badge; their LibDBIcon minimap buttons can be hidden. Spec: deadbeat-spec spec.md §4.11 (draft).
local _, ns = ...
local K = ns.kit
local P = K.P
local Broker = {}
ns.Broker = Broker

local LDB                            -- LibDataBroker-1.1, when some addon brought it
local objects, names = {}, {}        -- name -> data object; sorted names
local pinned = {}                    -- name -> badge
local m, tray, trayBadge, db
local COLS, CELL = 4, 68

local function settings(name)
    db.ldb = db.ldb or {}
    db.ldb[name] = db.ldb[name] or {}
    return db.ldb[name]
end

-- defaults: launchers in the tray, data sources too; nothing pinned; minimap buttons hidden while on the bar
local function inTray(name) return settings(name).tray ~= false end
local function isPinned(name) return settings(name).pin == true end
local function hideMinimap(name) return settings(name).minimap ~= "show" and (inTray(name) or isPinned(name)) end

local function icon(tex, obj)
    tex:SetTexture(obj.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    if obj.iconCoords then tex:SetTexCoord(unpack(obj.iconCoords)) else tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    if obj.iconR then tex:SetVertexColor(obj.iconR, obj.iconG or 1, obj.iconB or 1) else tex:SetVertexColor(1, 1, 1) end
end

local function title(name, obj) return obj.label or obj.tocname or name end

-- hovering and clicking an object's button: the object decides (OnTooltipShow, OnEnter/OnLeave, OnClick)
local function wire(button, name)
    button:RegisterForClicks("AnyUp")
    button:SetScript("OnClick", function(self, which)
        local obj = objects[name]
        if obj and obj.OnClick then pcall(obj.OnClick, self, which) end
    end)
    button:SetScript("OnEnter", function(self)
        local obj = objects[name]
        if not obj then return end
        if obj.OnTooltipShow then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
            pcall(obj.OnTooltipShow, GameTooltip)
            GameTooltip:Show()
        elseif obj.OnEnter then
            pcall(obj.OnEnter, self)
        else
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
            GameTooltip:AddLine(title(name, obj), P.bronze4[1], P.bronze4[2], P.bronze4[3])
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        local obj = objects[name]
        if obj and obj.OnLeave then pcall(obj.OnLeave, self) else GameTooltip:Hide() end
    end)
end

-- --- the minimap buttons (LibDBIcon) --------------------------------------------------------------

local function minimap(name)
    local icons = LibStub and LibStub("LibDBIcon-1.0", true)
    if not (icons and icons.IsRegistered and icons:IsRegistered(name)) then return end
    if hideMinimap(name) then pcall(icons.Hide, icons, name) else pcall(icons.Show, icons, name) end
end
function Broker.hasMinimap(name)
    local icons = LibStub and LibStub("LibDBIcon-1.0", true)
    return icons and icons.IsRegistered and icons:IsRegistered(name) or false
end

-- --- pinned badges ------------------------------------------------------------------------------------

local function drawPin(name)
    local b, obj = pinned[name], objects[name]
    if not (b and obj) then return end
    icon(b.icon, obj)
    local text = obj.text or (obj.value and (tostring(obj.value) .. (obj.suffix or ""))) or ""
    b.text:SetText(text)
    b:SetWidth(15 + (text ~= "" and ((b.text:GetStringWidth() or 20) + 2) or 0))
end

local function pin(name)
    if not pinned[name] then
        local b = m:Badge(16, { id = "ldb." .. name, label = title(name, objects[name]) .. " (LDB)" })
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(13, 13)
        b.icon:SetPoint("LEFT")
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 15, 0)
        local hit = CreateFrame("Button", nil, b)
        hit:SetAllPoints()
        wire(hit, name)
        pinned[name] = b
    end
    pinned[name]:SetShown(isPinned(name))
    drawPin(name)
end

-- --- the tray --------------------------------------------------------------------------------------------

local cells = {}

local function trayNames()
    local list = {}
    for _, name in ipairs(names) do if inTray(name) then list[#list + 1] = name end end
    return list
end

local function layoutTray()
    local list = trayNames()
    for i, name in ipairs(list) do
        local c = cells[i]
        if not c then
            c = CreateFrame("Button", nil, tray)
            c:SetSize(CELL, 50)
            c.icon = c:CreateTexture(nil, "ARTWORK")
            c.icon:SetSize(24, 24)
            c.icon:SetPoint("TOP", 0, -5)
            c.text = K.text(c, "GameFontHighlightSmall", P.warmGrey)
            c.text:SetPoint("TOP", c.icon, "BOTTOM", 0, -3)
            c.text:SetWidth(CELL - 4)
            local hi = c:CreateTexture(nil, "HIGHLIGHT")
            hi:SetAllPoints()
            hi:SetColorTexture(P.bronze4[1], P.bronze4[2], P.bronze4[3], 0.15)
            cells[i] = c
        end
        c.name = name
        wire(c, name)
        icon(c.icon, objects[name])
        c.text:SetText(title(name, objects[name]))
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", 8 + ((i - 1) % COLS) * CELL, -8 - math.floor((i - 1) / COLS) * 52)
        c:Show()
    end
    for i = #list + 1, #cells do cells[i]:Hide() end
    local rows = math.max(1, math.ceil(#list / COLS))
    tray:SetSize(16 + math.min(#list, COLS) * CELL, 16 + rows * 52)
    trayBadge:SetShown(#list > 0)
end

local function buildTray()
    trayBadge = m:Badge(14, { id = "ldb.tray", label = "Addon launchers (LDB tray)" })
    -- a 3 × 3 grid of small bronze squares: "the other addons"
    for i = 0, 8 do
        local sq = trayBadge:CreateTexture(nil, "ARTWORK")
        sq:SetSize(3, 3)
        sq:SetPoint("TOPLEFT", (i % 3) * 5, -1 - math.floor(i / 3) * 5)
        sq:SetColorTexture(P.bronze4[1], P.bronze4[2], P.bronze4[3], 1)
    end
    local hit = CreateFrame("Button", "DeadbeatTrayButton", trayBadge)
    hit:SetAllPoints()

    tray = CreateFrame("Frame", "DeadbeatTray", UIParent)
    tray:SetFrameStrata("DIALOG")
    tray:EnableMouse(true)
    tray.open, tray.pinned = false, false
    tray:SetScript("OnShow", function(self) self.open = true end)
    tray:SetScript("OnHide", function(self) self.open, self.pinned = false, false end)
    K.ground(tray, 0.96)
    K.border(tray, true)
    tray:Hide()
    -- open on hover or click; close a moment after the mouse left both the bar and the tray (the bar, not just the
    -- badge: the way down from the badge crosses the bar's lower band)
    -- A click pins it open until the next click or Esc. The frame method IsMouseOver, not the global MouseIsOver:
    -- Forever's client may not have the global (0.4.1's tray closed at once).
    local function open()
        GameTooltip:Hide()
        layoutTray()
        tray:ClearAllPoints()                                  -- away from the edge the bar sits on
        if Deadbeat.atBottom() then tray:SetPoint("BOTTOMRIGHT", trayBadge, "TOPRIGHT", 8, 12)
        else tray:SetPoint("TOPRIGHT", trayBadge, "BOTTOMRIGHT", 8, -12) end
        tray:Show()
    end
    hit:SetScript("OnEnter", function() if not tray.open then tray.pinned = false open() end end)
    hit:SetScript("OnClick", function()
        if tray.open and tray.pinned then tray:Hide() else tray.pinned = true open() end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "DeadbeatTray") end
    local function over(frame)
        if frame.IsMouseOver then return frame:IsMouseOver() end
        return MouseIsOver and MouseIsOver(frame)
    end
    local away = 0
    tray:SetScript("OnUpdate", function(self, elapsed)
        if self.pinned or over(self) or over(Deadbeat.frame) then away = 0 return end
        away = away + (elapsed or 0)
        if away > 0.5 then away = 0 self:Hide() end
    end)
end

-- --- objects coming and changing ---------------------------------------------------------------------------

local function add(name, obj)
    if objects[name] or type(obj) ~= "table" then return end
    objects[name] = obj
    names[#names + 1] = name
    table.sort(names, function(a, b) return title(a, objects[a]):lower() < title(b, objects[b]):lower() end)
    if isPinned(name) then pin(name) end
    minimap(name)
    if tray and tray:IsShown() then layoutTray() end
    if trayBadge then trayBadge:SetShown(#trayNames() > 0) end
end

local function changed(_, name, key)
    if pinned[name] and (key == "text" or key == "value" or key == "suffix" or key == "icon" or key == "label") then
        drawPin(name)
        Deadbeat.Refresh()
    end
end

-- Look for LDB (it arrives with whichever addon embeds it): at login and after each addon loads.
function Broker.scan()
    if not m then return end
    if not LDB then
        LDB = LibStub and LibStub("LibDataBroker-1.1", true)
        if not LDB then return end
        LDB.RegisterCallback(Broker, "LibDataBroker_DataObjectCreated", function(_, name, obj) add(name, obj) end)
        LDB.RegisterCallback(Broker, "LibDataBroker_AttributeChanged", changed)
    end
    for name, obj in LDB:DataObjectIterator() do add(name, obj) end
    -- the minimap buttons register late (in their own PLAYER_LOGIN): hide them again a moment later
    C_Timer.After(2, function() for _, n in ipairs(names) do minimap(n) end end)
end

-- --- the settings page -------------------------------------------------------------------------------------------

local function page(frame, width)
    local y = 0
    local heads = { { "In tray", width - 196 }, { "On bar", width - 132 }, { "Hide minimap", width - 58 } }
    for _, h in ipairs(heads) do
        local fs = K.text(frame, "GameFontHighlightSmall", P.warmGrey)
        fs:SetPoint("TOP", frame, "TOPLEFT", h[2] + 27, -4)
        fs:SetText(h[1])
    end
    y = 24
    frame.rows = {}
    for _, name in ipairs(names) do
        local obj = objects[name]
        local row = CreateFrame("Frame", nil, frame)
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetSize(width, 28)
        local ic = row:CreateTexture(nil, "ARTWORK")
        ic:SetSize(18, 18)
        ic:SetPoint("LEFT", 4, 0)
        icon(ic, obj)
        local fs = K.text(row, "GameFontHighlight", { 0.92, 0.88, 0.80 })
        fs:SetPoint("LEFT", 28, 0)
        fs:SetWidth(width - 230)
        fs:SetJustifyH("LEFT")
        fs:SetText(title(name, obj) .. ((obj.type == "data source") and "  |cff8f8275data|r" or ""))
        local function sw(x, get, set)
            local s = ns.Settings.toggle(row, { get = get, set = set })
            s:SetPoint("LEFT", x, 0)
            row.switches = row.switches or {}
            row.switches[#row.switches + 1] = s
        end
        sw(width - 196, function() return inTray(name) end, function(on)
            settings(name).tray = on
            minimap(name)
            if trayBadge then trayBadge:SetShown(#trayNames() > 0) end
            Deadbeat.Refresh()
        end)
        sw(width - 132, function() return isPinned(name) end, function(on)
            settings(name).pin = on
            pin(name)
            minimap(name)
            Deadbeat.Refresh()
        end)
        if Broker.hasMinimap(name) then
            sw(width - 58, function() return hideMinimap(name) end, function(on)
                settings(name).minimap = on and nil or "show"
                minimap(name)
            end)
        end
        frame.rows[#frame.rows + 1] = row
        y = y + 30
    end
    if #names == 0 then
        local fs = K.text(frame, "GameFontHighlightSmall", P.warmGrey)
        fs:SetPoint("TOPLEFT", 4, -28)
        fs:SetText("No LDB objects yet: none of your addons published one.")
    end
end

function Broker.build(database)
    db = database
    m = Deadbeat.Register("LDB", 90)
    buildTray()
    m:Options({ title = "LDB", icon = "Interface\\Icons\\INV_Misc_Gear_01", rows = {
        { kind = "header", label = "Other addons (LibDataBroker)" },
        { kind = "note", label = "Addons that offer an LDB launcher or data source. In tray: in the drop-down of the tray badge. On bar: its own badge (then pick where it shows on the Bar page). Hide minimap: its minimap button goes while it's in the tray or on the bar." },
        { kind = "custom", height = function() return 34 + 30 * math.max(1, #names) end, build = page,
          show = function(frame)
              for _, row in ipairs(frame.rows or {}) do for _, s in ipairs(row.switches or {}) do s.draw() end end
          end },
    } })
    Broker.scan()
end

function Broker.count() return #names end
function Broker.trayOpen() return tray and tray.open == true end
function Broker.closeTray() if tray and tray.open then tray:Hide() end end
