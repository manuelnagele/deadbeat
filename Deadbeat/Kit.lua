-- Deadbeat's kit: the look every module shares, dressed like the user's FlareUI (palette, bronze border and bar
-- texture fetched by name from LibSharedMedia, never from FlareUI's frames). Exposed as Deadbeat.kit.
local _, ns = ...
local K = {}
ns.kit = K

-- FlareUI's palette (FlareUI Core.lua ns.PALETTE)
K.P = {
    ground = { 0.05, 0.04, 0.03 }, bronze1 = { 0.32, 0.24, 0.13 }, bronze2 = { 0.50, 0.38, 0.21 },
    bronze3 = { 0.65, 0.49, 0.27 }, bronze4 = { 0.80, 0.60, 0.34 }, goldOn = { 1, 0.82, 0.25 },
    warmGrey = { 0.56, 0.51, 0.46 },
}

-- FlareUI's "soft" colours: 35 % less saturated, a quarter of the way to a warm light bronze
function K.soft(r, g, b)
    local grey = 0.3 * r + 0.59 * g + 0.11 * b
    r, g, b = r + (grey - r) * 0.35, g + (grey - g) * 0.35, b + (grey - b) * 0.35
    return r + (0.85 - r) * 0.25, g + (0.70 - g) * 0.25, b + (0.50 - b) * 0.25
end
K.GREEN = { K.soft(0.40, 0.85, 0.40) }
K.RED = { K.soft(0.85, 0.30, 0.25) }

function K.hex(c)
    return ("%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

function K.media(kind, name)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return nil end
    local ok, file = pcall(LSM.Fetch, LSM, kind, name, true)
    return ok and type(file) == "string" and file or nil
end

function K.barTexture()
    return K.media("statusbar", "FlareUI Forever (Light)") or K.media("statusbar", "FlareUI Flat")
        or "Interface\\Buttons\\WHITE8x8"
end

function K.icon(path, size)
    return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(path, size or 14, size or 14)
end

-- a 3 px colour swatch for tooltip rows
function K.swatch(c)
    return ("|TInterface\\Buttons\\WHITE8x8:10:3:0:0:8:8:0:8:0:8:%d:%d:%d|t "):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

local function plainMoney(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g > 0 then return ("%dg %02ds"):format(g, s) end
    if s > 0 then return ("%ds %02dc"):format(s, c) end
    return ("%dc"):format(c)
end

-- Coin icons like the game shows money; rounded so lines stay short (copper only below 1g).
-- whole = true rounds to whole gold from 1g on (rates: "52 g/h").
function K.coins(copper, size, whole)
    copper = math.floor(copper or 0)
    if copper >= 1000000 or (whole and copper >= 10000) then copper = copper - copper % 10000
    elseif copper >= 10000 then copper = copper - copper % 100 end
    local fn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if fn then
        local ok, s = pcall(fn, copper, size or 12)
        if ok and s then return s end
    end
    return plainMoney(copper)
end

function K.clock(seconds)
    seconds = math.floor(seconds or 0)
    local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
    if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
    return ("%d:%02d"):format(m, s)
end

function K.border(frame, thin)
    local b = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    b:SetPoint("TOPLEFT", -1, 1)
    b:SetPoint("BOTTOMRIGHT", 1, -1)
    b:SetFrameLevel(frame:GetFrameLevel() + 3)
    local file = K.media("border", thin and "FlareUI Thin" or "FlareUI Frames")
    if file then
        b:SetBackdrop({ edgeFile = file, edgeSize = thin and 8 or 12 })
    else
        b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    end
    local c = K.P.bronze3
    b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    return b
end

function K.ground(frame, alpha)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local c = K.P.ground
    bg:SetColorTexture(c[1], c[2], c[3], alpha or 0.9)
    return bg
end

function K.text(parent, template, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    fs:SetWordWrap(false)
    return fs
end

-- a brief additive flash over a region (a bar that grew, a slot that filled)
function K.flash(region, parent)
    local hi = (parent or region:GetParent()):CreateTexture(nil, "OVERLAY")
    hi:SetAllPoints(region)
    hi:SetColorTexture(1, 0.95, 0.8, 1)
    hi:SetBlendMode("ADD")
    hi:SetAlpha(0)
    local anim = hi:CreateAnimationGroup()
    local up = anim:CreateAnimation("Alpha")
    up:SetFromAlpha(0) up:SetToAlpha(0.7) up:SetDuration(0.12)
    local down = anim:CreateAnimation("Alpha")
    down:SetFromAlpha(0.7) down:SetToAlpha(0) down:SetDuration(0.6) down:SetStartDelay(0.12)
    return anim
end
