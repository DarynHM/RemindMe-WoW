-- Indicator.lua
-- On-screen reminder icon, styled like the minimap "You have mail" button.
-- Visible while fired reminders are waiting (or always, if "only when due" is
-- off), while previewing, or while unlocked with the options panel open.
--   Hover: list of due reminders.  Left-click: complete newest.
--   Right-click: snooze newest 10 min.  Shift-click: print full list.
--   Ctrl-click: open the options panel.

local _, ns = ...

local Indicator = {}
ns.Indicator = Indicator

local SNOOZE_SECONDS = 10 * 60
local PREVIEW_SECONDS = 10

local button
local previewUntil = 0
local previewPriority = "normal"

local function cfg()
    return ns.settings.indicator
end

---------------------------------------------------------------------------
-- Animation helpers (APIs differ slightly between client versions)
---------------------------------------------------------------------------

local function setScaleAnim(a, s)
    if a.SetScaleTo then
        a:SetScaleFrom(1, 1)
        a:SetScaleTo(s, s)
    else
        a:SetScale(s, s)
    end
end

local function setAlphaAnim(a, from, to)
    if a.SetFromAlpha then
        a:SetFromAlpha(from)
        a:SetToAlpha(to)
    else
        a:SetChange(to - from)
    end
end

local function buildAnimations(b)
    local anims = {}

    local pulse = b:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local s = pulse:CreateAnimation("Scale")
    setScaleAnim(s, 1.18)
    s:SetOrigin("CENTER", 0, 0)
    s:SetDuration(0.6)
    s:SetSmoothing("IN_OUT")
    anims.pulse = pulse

    local glow = b.glow:CreateAnimationGroup()
    glow:SetLooping("BOUNCE")
    local g = glow:CreateAnimation("Alpha")
    setAlphaAnim(g, 0.4, 1) -- gentle breathing, never fully off
    g:SetDuration(0.9)
    g:SetSmoothing("IN_OUT")
    anims.glow = glow

    return anims
end

---------------------------------------------------------------------------
-- Round effects: sparkles and comet (orbiting stars) and ring (soft halo).
-- Each effect's start(b, col) returns false if its art is missing on this
-- client, and the round glow is used instead. A child frame's OnUpdate
-- drives the orbiting ones.
---------------------------------------------------------------------------

-- SetTexture returns false for a missing file on modern clients (nil on old ones).
local function trySetTexture(tex, path)
    return tex:SetTexture(path) ~= false
end

local function setDriver(b, fn)
    if not b.fxDriver then b.fxDriver = CreateFrame("Frame", nil, b) end
    b.fxDriver.t = 0
    b.fxDriver:SetScript("OnUpdate", fn and function(self, elapsed)
        self.t = self.t + elapsed
        fn(self.t)
    end or nil)
end

-- The autocast-shine star, used by sparkles and comet.
local SPARK_TEX = "Interface\\ItemSocketingFrame\\UI-ItemSockets"
local SPARK_COORD = { 0.3984375, 0.4453125, 0.40234375, 0.44921875 }

-- b[field] = list of `count` star textures, or false if the art is missing.
local function getStars(b, field, count)
    if b[field] == nil then
        local list = {}
        for i = 1, count do
            local sp = b:CreateTexture(nil, "OVERLAY", nil, 3)
            if not trySetTexture(sp, SPARK_TEX) then list = false; break end
            sp:SetTexCoord(unpack(SPARK_COORD))
            sp:SetBlendMode("ADD")
            sp:Hide()
            list[i] = sp
        end
        b[field] = list
    end
    return b[field]
end

local function hideStars(list)
    if list then for _, sp in ipairs(list) do sp:Hide() end end
end

-- Sparkles: stars orbiting the round icon, half each way.
local SPARK_COUNT = 8

local function startSparkles(b, col)
    local stars = getStars(b, "sparks", SPARK_COUNT)
    if not stars then return false end
    local w = b:GetWidth()
    local r = w * 0.5
    for i, sp in ipairs(stars) do
        local size = (i % 2 == 1) and w * 0.45 or w * 0.28
        sp:SetSize(size, size)
        sp:SetVertexColor(col.r, col.g, col.b)
        sp:SetAlpha(1)
        sp:Show()
    end
    local step = 2 * math.pi / SPARK_COUNT
    local function orbit(t)
        for i, sp in ipairs(stars) do
            local dir = (i % 2 == 1) and 1 or -1
            local a = dir * t * 2.2 + i * step
            sp:SetPoint("CENTER", b, "CENTER", math.cos(a) * r, math.sin(a) * r)
        end
    end
    orbit(0)
    setDriver(b, orbit)
    return true
end

-- Comet: one bright star circling the icon with a fading tail.
local COMET_LEN = 7
local COMET_SPEED = 2 * math.pi / 1.6 -- one lap every 1.6 s
local COMET_GAP = 0.16                -- radians between tail stars

local function startComet(b, col)
    local stars = getStars(b, "comet", COMET_LEN)
    if not stars then return false end
    local w = b:GetWidth()
    local r = w * 0.5
    for i, sp in ipairs(stars) do
        local k = (i - 1) / COMET_LEN -- 0 at the head, towards 1 at the tail
        local size = w * (0.55 - 0.35 * k)
        sp:SetSize(size, size)
        sp:SetVertexColor(col.r, col.g, col.b)
        sp:SetAlpha(1 - 0.85 * k)
        sp:Show()
    end
    local function fly(t)
        local head = -t * COMET_SPEED + math.pi / 2 -- clockwise from the top
        for i, sp in ipairs(stars) do
            local a = head + (i - 1) * COMET_GAP
            sp:SetPoint("CENTER", b, "CENTER", math.cos(a) * r, math.sin(a) * r)
        end
    end
    fly(0)
    setDriver(b, fly)
    return true
end

-- Ring: a soft round halo behind the icon that breathes.
local function startRing(b, col)
    if not b.ring then
        local ring = b:CreateTexture(nil, "BACKGROUND")
        ring:SetPoint("CENTER")
        ring:SetBlendMode("ADD")
        b.ringOk = trySetTexture(ring, "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        b.ring = ring

        local grp = ring:CreateAnimationGroup()
        grp:SetLooping("BOUNCE")
        local a = grp:CreateAnimation("Alpha")
        setAlphaAnim(a, 0.35, 1)
        a:SetDuration(0.8)
        a:SetSmoothing("IN_OUT")
        local s = grp:CreateAnimation("Scale")
        setScaleAnim(s, 1.15)
        s:SetOrigin("CENTER", 0, 0)
        s:SetDuration(0.8)
        s:SetSmoothing("IN_OUT")
        b.ringAnim = grp
    end
    if not b.ringOk then return false end
    local w = b:GetWidth() * 1.9
    b.ring:SetSize(w, w)
    b.ring:SetVertexColor(col.r, col.g, col.b)
    b.ring:Show()
    b.ringAnim:Play()
    return true
end

local EFFECTS = { sparkle = startSparkles, comet = startComet, ring = startRing }

local function stopAnimations(b)
    for _, group in pairs(b.anims) do group:Stop() end
    b.glow:Hide()
    setDriver(b, nil)
    hideStars(b.sparks)
    hideStars(b.comet)
    if b.ring then b.ringAnim:Stop(); b.ring:Hide() end
    b.playingKey = nil
end

-- Animate using the given priority's profile; glows take its colour.
-- Refresh runs often (every scheduler tick), so leave a running animation
-- alone unless the animation or priority changed; restarting made the comet
-- jump back to the start.
local function playAnimation(b, priority)
    local which = ns.settings.profiles[priority].animation
    local key = tostring(which) .. ":" .. priority
    if b.playingKey == key then return end
    stopAnimations(b)
    b.playingKey = key
    local col = ns.PRIORITY_COLOR[priority]
    local effect = EFFECTS[which]
    if effect then
        if effect(b, col) then return end
        which = "glow" -- art missing on this client
    end
    local group = b.anims[which]
    if not group then return end
    if which == "glow" then
        b.glow:SetVertexColor(col.r, col.g, col.b)
        b.glow:Show()
    end
    group:Play()
end

---------------------------------------------------------------------------
-- Position
---------------------------------------------------------------------------

-- The minimap mail icon lives in different places depending on the UI code base.
-- On Mainline-style UIs the mail icon sits inside MinimapCluster.IndicatorFrame,
-- a layout row that resizes as icons show/hide, so anchor to the row itself
-- for a stable position.
local function findMailFrame()
    local cluster = MinimapCluster
    local indicator = cluster and cluster.IndicatorFrame
    return indicator                             -- Mainline-style UI (10.0+)
        or MiniMapMailFrame                      -- classic-style UI
        or MiniMapMailIcon
end

-- Ratio between the button's own coordinate space and UIParent's.
local function relScale()
    return button:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- Free position is stored as the icon's CENTRE in UIParent units, so it stays
-- put when the icon's scale changes.
function Indicator.ApplyPosition()
    if not button then return end
    local c = cfg()
    local mail = findMailFrame()
    button:ClearAllPoints()
    if c.freeX and c.freeY then
        local k = relScale()
        button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", c.freeX / k, c.freeY / k)
    elseif mail then
        button:SetPoint("RIGHT", mail, "LEFT", -2, 0)
    elseif Minimap then
        button:SetPoint("CENTER", Minimap, "BOTTOMLEFT", 8, 8)
    else
        button:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end
end

function Indicator.ResetPosition()
    local c = cfg()
    c.freeX, c.freeY = nil, nil
    Indicator.ApplyPosition()
end

---------------------------------------------------------------------------
-- Tooltip / clicks
---------------------------------------------------------------------------

local function showTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Reminders")
    local fired = ns.Scheduler.Fired()
    if #fired == 0 then
        GameTooltip:AddLine("Nothing due right now.", 0.6, 0.6, 0.6)
    else
        for _, r in ipairs(fired) do
            local p = ns.PriorityOf(r)
            local col = ns.PRIORITY_COLOR[p]
            -- Priority is shown by colour alone.
            GameTooltip:AddLine(r.code .. ". " .. ns.Notify.Escape(r.text), col.r, col.g, col.b, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: done   Right-click: snooze 10 min", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Shift-click: list all reminders", 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine("Ctrl-click: options", 0.6, 0.6, 0.6)
    if not cfg().locked then
        GameTooltip:AddLine("Unlocked: drag to move.", 0.25, 1, 0.25)
    end
    GameTooltip:Show()
end

local function onClick(self, mouseButton)
    if IsControlKeyDown() then
        GameTooltip:Hide()
        ns.Options.Open()
        return
    end
    if IsShiftKeyDown() then
        ns.Commands.ShowList()
        return
    end
    local r = ns.Scheduler.MostRecentFired()
    if not r then return end
    if mouseButton == "RightButton" then
        ns.Scheduler.Snooze(r, SNOOZE_SECONDS)
        ns.Print("snoozed |cffffffff" .. ns.Notify.Escape(r.text) .. "|r until " ..
            ns.Clock.Describe(r.snoozedUntil) .. ".")
    else
        if ns.Scheduler.Complete(r) then
            ns.Print("completed: " .. ns.Notify.Escape(r.text))
        else
            ns.Print("dismissed: " .. ns.Notify.Escape(r.text) .. " |cff999999(repeats)|r")
        end
    end
    if GameTooltip:IsOwned(self) then showTooltip(self) end
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function build()
    local b = CreateFrame("Button", "RemindMeIndicator", UIParent)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:SetClampedToScreen(true)
    b:SetMovable(true)
    -- We save the position ourselves; stop the client's layout cache from
    -- restoring a stale one over it.
    if b.SetDontSavePosition then b:SetDontSavePosition(true) end
    b:RegisterForDrag("LeftButton")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Borderless round icon: the texture fills the button and a circular
    -- mask clips it (MaskTexture where available, older SetMask otherwise).
    local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    local mask
    if b.CreateMaskTexture then
        mask = b:CreateMaskTexture()
        mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(b)
    end
    local function round(tex)
        if mask and tex.AddMaskTexture then
            tex:AddMaskTexture(mask)
        elseif tex.SetMask then
            tex:SetMask(MASK)
        end
    end

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(b)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    round(icon)
    b.icon = icon

    -- Glow: a coloured disc a little larger than the icon, behind it, so it
    -- reads as a ring hugging the round icon. The portrait mask image is
    -- itself a white disc, so no mask API is needed.
    local glow = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetTexture(MASK)
    glow:SetVertexColor(1, 0.82, 0.2)
    local gs = b:GetWidth() * 1.24 -- button is square
    glow:SetSize(gs, gs)
    glow:SetPoint("CENTER", 0, 0)
    glow:Hide()
    b.glow = glow

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.25)
    hl:SetBlendMode("ADD")
    round(hl)

    local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", -1, 1)
    b.count = count

    b.anims = buildAnimations(b)

    b:SetScript("OnEnter", showTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnDragStart", function(self)
        if not cfg().locked then
            stopAnimations(self)
            self:StartMoving()
        end
    end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local k = relScale()
        local c = cfg()
        c.freeX, c.freeY = cx * k, cy * k
        Indicator.ApplyPosition()
        Indicator.Refresh()
    end)

    button = b
    Indicator.ApplyPosition()
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function Indicator.Refresh()
    if not ns.settings then return end
    if not button then build() end

    local c = cfg()
    local due = #ns.Scheduler.Fired()
    local previewing = GetTime() < previewUntil
    -- Unlocked: show (for dragging) only while the options panel is open.
    local dragging = not c.locked and ns.Options and ns.Options.IsShown()
    local visible = previewing or dragging
        or (c.enabled and (due > 0 or c.onlyWhenDue == false))

    button:SetAlpha(c.alpha or 1)
    if button:GetScale() ~= (c.scale or 1) then
        button:SetScale(c.scale or 1)
        Indicator.ApplyPosition() -- keep the centre where it was
    end
    button.icon:SetTexture(ns.Media.IconTexture(c.icon))
    button.count:SetText(due > 1 and due or "")

    if not visible then
        stopAnimations(button)
        button:Hide()
        return
    end

    button:Show()
    if previewing then
        playAnimation(button, previewPriority)
    elseif due > 0 then
        playAnimation(button, ns.Scheduler.HighestFired())
    else
        stopAnimations(button) -- nothing due (always-on or unlocked): show still
    end
end

-- Show the icon for a few seconds with the given priority's animation
-- (defaults to the default priority).
function Indicator.Preview(priority)
    previewPriority = priority or ns.settings.defaultPriority
    previewUntil = GetTime() + PREVIEW_SECONDS
    Indicator.Refresh()
    C_Timer.After(PREVIEW_SECONDS + 0.1, Indicator.Refresh)
end

ns.OnRemindersChanged = Indicator.Refresh
