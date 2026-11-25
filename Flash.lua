-- Flash.lua
-- Screen edge flash (like the low-health warning) and taskbar flash.

local _, ns = ...

local Flash = {}
ns.Flash = Flash

local PULSES = 3
local PULSE_SECONDS = 0.45

local frame

local function setAlphaAnim(a, from, to)
    if a.SetFromAlpha then
        a:SetFromAlpha(from)
        a:SetToAlpha(to)
    else
        a:SetChange(to - from)
    end
end

local function build()
    local f = CreateFrame("Frame", "RemindMeEdgeFlash", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(false)
    f:Hide()

    local tex = f:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
    tex:SetBlendMode("ADD")
    f.tex = tex

    local group = f:CreateAnimationGroup()
    for i = 1, PULSES do
        local up = group:CreateAnimation("Alpha")
        setAlphaAnim(up, 0, 1)
        up:SetDuration(PULSE_SECONDS)
        up:SetOrder(i * 2 - 1)
        up:SetSmoothing("OUT")
        local down = group:CreateAnimation("Alpha")
        setAlphaAnim(down, 1, 0)
        down:SetDuration(PULSE_SECONDS)
        down:SetOrder(i * 2)
        down:SetSmoothing("IN")
    end
    group:SetScript("OnFinished", function() f:Hide() end)
    f.group = group

    frame = f
end

-- Pulse the screen edges in the priority's colour.
function Flash.Edges(priority)
    if not frame then build() end
    local c = ns.PRIORITY_COLOR[priority] or ns.PRIORITY_COLOR.high
    frame.tex:SetVertexColor(c.r, c.g, c.b)
    frame.group:Stop()
    frame:Show()
    frame.group:Play()
end

-- Flash the game's taskbar button. Windows ignores this while the game has focus.
function Flash.Taskbar()
    if FlashClientIcon then FlashClientIcon() end
end
