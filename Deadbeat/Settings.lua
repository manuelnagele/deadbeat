-- Deadbeat's settings console: every module's options in one window, opened from the gear on the bar. Modules hand in
-- pages of rows (m:Options); Deadbeat draws them FlareUI-style, all as things to click. Spec: deadbeat.md, 0.2.
--
--   m:Options({ title = "Catch", icon = "...", rows = { { kind = "toggle", label = "...", get = fn, set = fn }, ... } })
--   kinds: header, note, toggle, button (confirm = true: a second click does it), slider, keys, custom (see the spec)
--   Deadbeat.OpenSettings(title)
local _, ns = ...
local K = ns.kit
local P = K.P
local Settings = {}
ns.Settings = Settings

local WIDTH, HEIGHT, TABS = 640, 470, 156
local ROW = 30
local pages = {}                     -- { module, title, icon, rows, frame }
local win, current
local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }

local function print_(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffd8a446Deadbeat|r: " .. msg) end

-- --- pieces ----------------------------------------------------------------------------------

local function button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 22)
    K.ground(b, 0.95)
    K.border(b, true)
    b.text = K.text(b, "GameFontHighlightSmall", P.bronze4)
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    local hi = b:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(P.bronze4[1], P.bronze4[2], P.bronze4[3], 0.18)
    b:SetScript("OnClick", onClick)
    return b
end
Settings.button = button

local function label(parent, text, color)
    local fs = K.text(parent, "GameFontHighlight", color or { 0.92, 0.88, 0.80 })
    fs:SetPoint("LEFT", 4, 0)
    fs:SetText(text)
    return fs
end

-- a pill switch: green "on", grey "off"
local function toggle(parent, row)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(54, 22)
    s.bg = s:CreateTexture(nil, "BACKGROUND")
    s.bg:SetAllPoints()
    K.border(s, true)
    s.knob = s:CreateTexture(nil, "ARTWORK")
    s.knob:SetSize(18, 16)
    s.text = K.text(s, "GameFontHighlightSmall")
    local hi = s:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.08)
    function s.draw()
        local on = row.get() and true or false
        local c = on and K.GREEN or P.warmGrey
        s.bg:SetColorTexture(c[1] * 0.35, c[2] * 0.35, c[3] * 0.35, 0.95)
        s.knob:SetColorTexture(c[1], c[2], c[3], 1)
        s.knob:ClearAllPoints()
        s.knob:SetPoint(on and "RIGHT" or "LEFT", on and -3 or 3, 0)
        s.text:ClearAllPoints()
        s.text:SetPoint(on and "LEFT" or "RIGHT", on and 7 or -7, 0)
        s.text:SetText(on and "on" or "off")
        s.text:SetTextColor(c[1], c[2], c[3])
    end
    s:SetScript("OnClick", function() row.set(not row.get()) s.draw() end)
    return s
end
Settings.toggle = toggle

local function keyName(key)
    if not key then return "|cff8f8275—|r" end
    local text = GetBindingText and GetBindingText(key)
    return (type(text) == "string" and text ~= "") and text or key
end

-- --- key capture: the window listens for one key or pad button ----------------------------------------

local capture                        -- { row, slot, draw }

local function stopCapture()
    capture = nil
    win:EnableKeyboard(false)
    if win.EnableGamePadButton then pcall(win.EnableGamePadButton, win, false) end
end

local function startCapture(row, slot, draw)
    if InCombatLockdown() then print_("keys can't change in combat") return end
    capture = { row = row, slot = slot, draw = draw }
    win:EnableKeyboard(true)
    if win.SetPropagateKeyboardInput then pcall(win.SetPropagateKeyboardInput, win, false) end
    if slot == "pad" and win.EnableGamePadButton then pcall(win.EnableGamePadButton, win, true) end
    draw()
end

local function finishCapture(value)
    local c = capture
    stopCapture()
    if value then c.row.set(c.slot, value) end
    c.draw()
end

-- --- rows ----------------------------------------------------------------------------------------------

local function buildRow(page, row, y, width)
    local f = CreateFrame("Frame", nil, page.frame)
    f:SetPoint("TOPLEFT", 0, -y)
    local h = row.height
    if type(h) == "function" then h = h() end
    f:SetSize(width, row.kind == "custom" and h or (row.kind == "header" and 28 or ROW))
    local kind = row.kind
    if kind == "header" then
        local fs = K.text(f, "GameFontNormal", P.bronze4)
        fs:SetPoint("BOTTOMLEFT", 2, 4)
        fs:SetText(row.label)
        local line = f:CreateTexture(nil, "ARTWORK")
        line:SetPoint("BOTTOMLEFT", 0, 0)
        line:SetPoint("BOTTOMRIGHT", 0, 0)
        line:SetHeight(1)
        line:SetColorTexture(P.bronze2[1], P.bronze2[2], P.bronze2[3], 0.8)
    elseif kind == "note" then
        local fs = K.text(f, "GameFontHighlightSmall", P.warmGrey)
        fs:SetPoint("LEFT", 4, 0)
        fs:SetWidth(width - 8)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetText(row.label)
    elseif kind == "toggle" then
        label(f, row.label)
        local s = toggle(f, row)
        s:SetPoint("RIGHT", -4, 0)
        f.draw = s.draw
    elseif kind == "button" then
        label(f, row.label)
        local text = row.text or "Go"
        local b
        b = button(f, text, math.max(70, text:len() * 7 + 20), function()
            if row.confirm and not b.armed then              -- a second click within 3 s does it
                b.armed = true
                b.text:SetText("Sure?")
                C_Timer.After(3, function() b.armed = nil b.text:SetText(text) end)
                return
            end
            b.armed = nil
            b.text:SetText(text)
            row.run()
            if page.draw then page.draw() end
        end)
        b:SetPoint("RIGHT", -4, 0)
    elseif kind == "slider" then
        label(f, row.label)
        local value = K.text(f, "GameFontHighlight")
        local plus = button(f, "+", 26, nil)
        plus:SetPoint("RIGHT", -4, 0)
        value:SetPoint("RIGHT", plus, "LEFT", -10, 0)
        value:SetWidth(54)
        value:SetJustifyH("CENTER")
        local minus = button(f, "−", 26, nil)
        minus:SetPoint("RIGHT", value, "LEFT", -10, 0)
        local function nudge(d)
            local v = math.max(row.min, math.min(row.max, (row.get() or row.min) + d * row.step))
            row.set(math.floor(v / row.step + 0.5) * row.step)
            f.draw()
        end
        plus:SetScript("OnClick", function() nudge(1) end)
        minus:SetScript("OnClick", function() nudge(-1) end)
        function f.draw() value:SetText((row.fmt or "%s"):format(row.get() or row.min)) end
    elseif kind == "keys" then
        label(f, row.label)
        local clear = button(f, "Clear", 54, nil)
        clear:SetPoint("RIGHT", -4, 0)
        local pad = button(f, "Controller", 78, nil)
        pad:SetPoint("RIGHT", clear, "LEFT", -6, 0)
        local kb = button(f, "Keyboard", 72, nil)
        kb:SetPoint("RIGHT", pad, "LEFT", -6, 0)
        local value = K.text(f, "GameFontHighlight")
        value:SetPoint("RIGHT", kb, "LEFT", -12, 0)
        function f.draw()
            local waiting = capture and capture.row == row and capture.slot
            if waiting then
                value:SetText(("|cffffd100press a %s · Esc|r"):format(waiting == "pad" and "pad button" or "key"))
            else
                value:SetText(keyName(row.get("key")) .. "  |cff8f8275/|r  " .. keyName(row.get("pad")))
            end
        end
        kb:SetScript("OnClick", function() startCapture(row, "key", f.draw) end)
        pad:SetScript("OnClick", function() startCapture(row, "pad", f.draw) end)
        clear:SetScript("OnClick", function()
            if InCombatLockdown() then print_("keys can't change in combat") return end
            row.set("key", nil) row.set("pad", nil) f.draw()
        end)
    elseif kind == "custom" then
        local ok, err = pcall(row.build, f, width)
        if not ok then
            local fs = K.text(f, "GameFontHighlightSmall", K.RED)
            fs:SetPoint("TOPLEFT", 4, -4)
            fs:SetText(tostring(err))
        end
        if row.show then f.draw = function() pcall(row.show, f) end end
    end
    if kind ~= "header" and kind ~= "custom" and kind ~= "note" then
        local hi = f:CreateTexture(nil, "BACKGROUND")
        hi:SetAllPoints()
        hi:SetColorTexture(1, 1, 1, 0.025)
        hi:SetShown(page.stripe)
        page.stripe = not page.stripe
    end
    return f
end

local function buildPage(page)
    local width = WIDTH - TABS - 40
    page.frame = CreateFrame("Frame", nil, win.child)
    page.frame:SetPoint("TOPLEFT")
    page.frame:SetWidth(width)
    local y, rows = 0, {}
    for _, row in ipairs(page.rows) do
        local f = buildRow(page, row, y, width)
        rows[#rows + 1] = f
        y = y + f:GetHeight() + (row.kind == "header" and 4 or 2)
    end
    page.frame:SetHeight(y + 10)
    function page.draw() for _, f in ipairs(rows) do if f.draw then f.draw() end end end
end

-- --- the window -------------------------------------------------------------------------------------------

local function selectPage(page)
    if capture then stopCapture() end
    current = page
    for _, p in ipairs(pages) do
        if p.frame then p.frame:Hide() end
        p.tab.on:SetShown(p == page)
        p.tab.bar:SetShown(p == page)
        p.tab.text:SetTextColor(unpack(p == page and { 1, 0.93, 0.80 } or P.warmGrey))
    end
    if not page.frame then buildPage(page) end
    win.title:SetText(page.title)
    page.frame:Show()
    win.child:SetHeight(page.frame:GetHeight())
    win.scroll:SetVerticalScroll(0)
    page.draw()
end

local function buildTabs()
    local y = -44
    table.sort(pages, function(a, b)
        if a.module.order ~= b.module.order then return a.module.order < b.module.order end
        return a.n < b.n
    end)
    for _, page in ipairs(pages) do
        if not page.tab then
            local t = CreateFrame("Button", nil, win)
            t:SetSize(TABS - 16, 28)
            t.on = t:CreateTexture(nil, "BACKGROUND")
            t.on:SetAllPoints()
            t.on:SetColorTexture(P.bronze4[1], P.bronze4[2], P.bronze4[3], 0.16)
            t.bar = t:CreateTexture(nil, "ARTWORK")
            t.bar:SetPoint("TOPLEFT") t.bar:SetPoint("BOTTOMLEFT") t.bar:SetWidth(2)
            t.bar:SetColorTexture(P.goldOn[1], P.goldOn[2], P.goldOn[3], 1)
            t.icon = t:CreateTexture(nil, "ARTWORK")
            t.icon:SetSize(18, 18)
            t.icon:SetPoint("LEFT", 8, 0)
            t.icon:SetTexture(page.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            t.text = K.text(t, "GameFontHighlight", P.warmGrey)
            t.text:SetPoint("LEFT", t.icon, "RIGHT", 8, 0)
            t.text:SetText(page.title)
            local hi = t:CreateTexture(nil, "HIGHLIGHT")
            hi:SetAllPoints()
            hi:SetColorTexture(1, 1, 1, 0.06)
            t:SetScript("OnClick", function() selectPage(page) end)
            t.on:Hide()
            t.bar:Hide()
            page.tab = t
        end
        page.tab:ClearAllPoints()
        page.tab:SetPoint("TOPLEFT", 8, y)
        y = y - 30
    end
end

local function build()
    win = CreateFrame("Frame", "DeadbeatSettings", UIParent)
    win:SetSize(WIDTH, HEIGHT)
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)                 -- remembered: it opens where you put it
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        DeadbeatDB.console = { point, rel, x, y }
    end)
    K.ground(win, 0.96)
    K.border(win, false)
    if UISpecialFrames then table.insert(UISpecialFrames, "DeadbeatSettings") end
    local head = K.text(win, "GameFontNormal", P.bronze4)
    head:SetPoint("TOPLEFT", 16, -14)
    head:SetText("Deadbeat  ·  Settings")
    win.title = K.text(win, "GameFontNormalLarge", { 1, 0.93, 0.80 })
    win.title:SetPoint("TOPLEFT", TABS + 14, -12)
    button(win, "×", 24, function() win:Hide() end):SetPoint("TOPRIGHT", -10, -10)
    local split = win:CreateTexture(nil, "ARTWORK")
    split:SetPoint("TOPLEFT", TABS, -40)
    split:SetPoint("BOTTOMLEFT", TABS, 12)
    split:SetWidth(1)
    split:SetColorTexture(P.bronze2[1], P.bronze2[2], P.bronze2[3], 0.7)

    win.scroll = CreateFrame("ScrollFrame", nil, win)
    win.scroll:SetPoint("TOPLEFT", TABS + 14, -46)
    win.scroll:SetPoint("BOTTOMRIGHT", -18, 14)
    win.child = CreateFrame("Frame", nil, win.scroll)
    win.child:SetSize(WIDTH - TABS - 40, 10)
    win.scroll:SetScrollChild(win.child)
    win.scroll:EnableMouseWheel(true)
    win.scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, win.child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
    end)

    win:SetScript("OnKeyDown", function(_, key)
        if not capture or MODIFIERS[key] then return end
        if key == "ESCAPE" or capture.slot == "pad" then finishCapture(nil) return end
        finishCapture((IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
            .. (IsShiftKeyDown() and "SHIFT-" or "") .. key)
    end)
    win:SetScript("OnGamePadButtonDown", function(_, pad)
        if capture and capture.slot == "pad" then finishCapture(pad) end
    end)
    win:SetScript("OnHide", function() if capture then stopCapture() end end)
    win:Hide()
end

-- --- the Bar page: layout buttons, and the grid of items × places --------------------------------------------

local CTX_LABEL = { farm = "Farm", raid = "Raid", dungeon = "Dungeon", city = "City", world = "World" }

-- Bar page: Compact / Full-width top / Full-width bottom, as three buttons; the current one lit
function Settings.layoutRow(frame, width)
    label(frame, "Layout")
    local opts = { { "compact", "Compact" }, { "top", "Full-width top" }, { "bottom", "Full-width bottom" } }
    local buttons, x = {}, -4
    for i = #opts, 1, -1 do
        local key, text = opts[i][1], opts[i][2]
        local b = button(frame, text, text:len() * 7 + 18, function()
            Deadbeat.SetLayout(key)
            frame.drawLayout()
        end)
        b:SetPoint("RIGHT", x, 0)
        x = x - b:GetWidth() - 6
        b.key = key
        buttons[#buttons + 1] = b
    end
    function frame.drawLayout()
        for _, b in ipairs(buttons) do
            local on = b.key == Deadbeat.Layout()
            b.text:SetTextColor(unpack(on and P.goldOn or P.bronze4))
        end
    end
end

-- every item: on the bar or on the shelf, and the places it shows in
function Settings.contextGrid(frame, width)
    local cols, colW, barW = Deadbeat.CONTEXTS, 50, 58
    local x0 = width - #cols * colW
    local xb = x0 - barW
    local bh = K.text(frame, "GameFontHighlightSmall", P.warmGrey)
    bh:SetPoint("TOP", frame, "TOPLEFT", xb + barW / 2, -6)
    bh:SetText("On bar")
    for i, ctx in ipairs(cols) do
        local h = K.text(frame, "GameFontHighlightSmall", P.warmGrey)
        h:SetPoint("TOP", frame, "TOPLEFT", x0 + (i - 0.5) * colW, -6)
        h:SetText(CTX_LABEL[ctx])
    end
    local cells = {}
    local function square(x, y, get, set)
        local c = CreateFrame("Button", nil, frame)
        c:SetSize(20, 20)
        c:SetPoint("TOP", frame, "TOPLEFT", x, y)
        c.fill = c:CreateTexture(nil, "ARTWORK")
        c.fill:SetPoint("TOPLEFT", 3, -3)
        c.fill:SetPoint("BOTTOMRIGHT", -3, 3)
        K.border(c, true)
        local hi = c:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints()
        hi:SetColorTexture(1, 1, 1, 0.1)
        function c.draw()
            local on = get()
            local col = on and K.GREEN or P.bronze1
            c.fill:SetColorTexture(col[1], col[2], col[3], on and 1 or 0.6)
        end
        c:SetScript("OnClick", function() set(not get()) c.draw() end)
        cells[#cells + 1] = c
    end
    for r, it in ipairs(Deadbeat.Items()) do
        local y = -26 - (r - 1) * 26
        local name = K.text(frame, "GameFontHighlight", { 0.92, 0.88, 0.80 })
        name:SetPoint("TOPLEFT", 4, y - 4)
        name:SetWidth(xb - 12)                                      -- cut with "…" before the switches
        name:SetJustifyH("LEFT")
        name:SetText(it.name .. "  |cff8f8275" .. it.module.name .. "|r")
        square(xb + barW / 2, y, function() return ns.Items.shown(it) end, function(on) ns.Items.setShown(it, on) end)
        for i, ctx in ipairs(cols) do
            square(x0 + (i - 0.5) * colW, y, function() return ns.Items.allowed(it, ctx) end,
                function(on) ns.Items.setAllowed(it, ctx, on) end)
        end
    end
    function frame.drawGrid() for _, c in ipairs(cells) do c.draw() end end
end

-- --- API ---------------------------------------------------------------------------------------------------

function Settings.add(module, page)
    page.module, page.n = module, #pages
    pages[#pages + 1] = page
    if win then buildTabs() end
end

function Deadbeat.OpenSettings(title)
    if not Deadbeat.frame then return end
    if not win then build() end
    buildTabs()
    local page
    for _, p in ipairs(pages) do if p.title == title then page = p end end
    page = page or current or pages[1]
    if not win:IsShown() then
        -- where you last put it; else past the panels docked under the bar, away from the edge it sits on
        win:ClearAllPoints()
        local p = DeadbeatDB and DeadbeatDB.console
        if p then win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        elseif Deadbeat.atBottom() then win:SetPoint("BOTTOM", Deadbeat.DockEnd(), "TOP", 0, 10)
        else win:SetPoint("TOP", Deadbeat.DockEnd(), "BOTTOM", 0, -10) end
        if ns.Broker then ns.Broker.closeTray() end           -- one thing drops from the bar at a time
    end
    win:Show()
    if page then selectPage(page) end
end

function Deadbeat.ToggleSettings()
    if win and win:IsShown() then win:Hide() else Deadbeat.OpenSettings() end
end

function Deadbeat.RefreshSettings()
    if win and win:IsShown() and current then current.draw() end
end
