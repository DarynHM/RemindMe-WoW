-- Options.lua
-- Options panel in Esc > Options > AddOns, built from stock Blizzard templates
-- so it matches the game's own settings pages.

local AddonName, ns = ...

local Options = {}
ns.Options = Options

local PANEL_NAME = "RemindMe"
local panel
local refreshers = {}   -- functions that sync widgets from settings (run on show)

local function onRefresh(fn)
    refreshers[#refreshers + 1] = fn
end

---------------------------------------------------------------------------
-- Widget helpers
---------------------------------------------------------------------------

local function header(parent, text, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    return fs
end

local function label(parent, text, x, y, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local checkCount = 0
-- text = nil gives a bare checkbox (for grids); tipTitle names it in the tooltip.
local function checkbox(parent, text, tooltip, x, y, get, set, tipTitle)
    checkCount = checkCount + 1
    local name = "RemindMeOptCheck" .. checkCount
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    local fs = cb.Text or cb.text or _G[name .. "Text"]
    if not fs then
        fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    if text then
        fs:SetFontObject("GameFontHighlight")
        fs:SetText(text)
        cb:SetHitRectInsets(0, -fs:GetStringWidth() - 4, 0, 0)
    else
        fs:SetText("")
    end
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
    end)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tipTitle or text, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    onRefresh(function() cb:SetChecked(get()) end)
    return cb
end

local function button(parent, text, width, x, y, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- Dropdown using the newer WowStyle1DropdownTemplate menu system (what the
-- client's own Settings screens use) when available, otherwise the classic
-- UIDropDownMenu system.
-- getOptions() -> { { value, label }, ... }
local function hasModernDropdown()
    return C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("WowStyle1DropdownTemplate") ~= nil
end

local MAX_MENU_ROWS = 20

local dropCount = 0
-- Small "play" button on the right of a menu row (modern Menu system only).
local PLAY_TEX = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-"

-- The menu row can swallow the play button's click (it then selects the row),
-- so the row's select handler also checks whether the mouse is over that
-- row's play button. playButtons[value] = the button drawn on that row.
local playButtons = {}
local lastPlayed = 0

local function playPreview(preview, value)
    local now = GetTime()
    if now == lastPlayed then return end -- button and row both saw one click
    lastPlayed = now
    preview(value)
end

-- True (after playing the sound) if this click was on the row's play button.
local function clickedPlay(preview, value)
    local pb = playButtons[value]
    if pb and pb.remindValue == value and pb:IsVisible() and pb:IsMouseOver() then
        playPreview(preview, value)
        return true
    end
    return false
end

local function attachPreview(desc, value, preview)
    if not (desc.AddInitializer) then return end
    desc:AddInitializer(function(row)
        if not row.AttachFrame then return end
        local play = row:AttachFrame("Button")
        play.remindValue = value
        playButtons[value] = play
        play:SetSize(18, 18)
        play:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        play:SetFrameLevel(row:GetFrameLevel() + 10)
        play:EnableMouse(true)
        play:RegisterForClicks("LeftButtonUp")
        play:SetNormalTexture(PLAY_TEX .. "Up")
        play:SetPushedTexture(PLAY_TEX .. "Down")
        play:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        play:SetScript("OnClick", function() playPreview(preview, value) end)
        play:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Play")
            GameTooltip:Show()
        end)
        play:SetScript("OnLeave", GameTooltip_Hide)
    end)
end

-- preview (optional): function(value), adds a play button to each row.
local function dropdown(parent, x, y, width, getOptions, get, set, preview)
    dropCount = dropCount + 1
    local name = "RemindMeOptDrop" .. dropCount

    local function labelFor(value)
        for _, o in ipairs(getOptions()) do
            if o[1] == value then return o[2] end
        end
        return tostring(value)
    end

    if hasModernDropdown() then
        local dd = CreateFrame("DropdownButton", name, parent, "WowStyle1DropdownTemplate")
        dd:SetPoint("TOPLEFT", x, y)
        dd:SetWidth(width + 20)
        dd:SetupMenu(function(_, root)
            local opts = getOptions()
            local function add(menu, o)
                -- Trailing spaces leave room for the play button on the widest row.
                local text = preview and (o[2] .. "        ") or o[2]
                local desc = menu:CreateRadio(text, function() return get() == o[1] end,
                    function()
                        if preview and clickedPlay(preview, o[1]) then
                            -- Play only: don't select, keep the menu open.
                            return MenuResponse and MenuResponse.Open
                        end
                        set(o[1])
                    end)
                if preview and desc then attachPreview(desc, o[1], preview) end
            end
            if #opts <= MAX_MENU_ROWS then
                for _, o in ipairs(opts) do add(root, o) end
            elseif root.SetScrollMode then
                -- Long lists (e.g. LibSharedMedia sounds) scroll instead of
                -- running off the screen.
                root:SetScrollMode(MAX_MENU_ROWS * 20)
                for _, o in ipairs(opts) do add(root, o) end
            else
                -- No scroll support: split into sub-menus of MAX_MENU_ROWS.
                for i = 1, #opts, MAX_MENU_ROWS do
                    local last = math.min(i + MAX_MENU_ROWS - 1, #opts)
                    local sub = root:CreateButton(opts[i][2] .. " ... " .. opts[last][2])
                    for j = i, last do add(sub, opts[j]) end
                end
            end
        end)
        onRefresh(function() dd:GenerateMenu() end)
        return dd
    end

    local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x - 16, y + 2) -- template has built-in left padding
    UIDropDownMenu_SetWidth(dd, width)
    UIDropDownMenu_Initialize(dd, function(self, level, menuList)
        local opts = getOptions()
        local first, last = 1, #opts
        if #opts > MAX_MENU_ROWS then
            if (level or 1) == 1 then
                -- Too long for one list: one arrow entry per chunk.
                for i = 1, #opts, MAX_MENU_ROWS do
                    local j = math.min(i + MAX_MENU_ROWS - 1, #opts)
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = opts[i][2] .. " ... " .. opts[j][2]
                    info.hasArrow = true
                    info.notCheckable = true
                    info.menuList = i
                    UIDropDownMenu_AddButton(info, level)
                end
                return
            end
            first = menuList or 1
            last = math.min(first + MAX_MENU_ROWS - 1, #opts)
        end
        for k = first, last do
            local o = opts[k]
            local info = UIDropDownMenu_CreateInfo()
            info.text = o[2]
            info.value = o[1]
            info.checked = (o[1] == get())
            info.func = function()
                set(o[1])
                UIDropDownMenu_SetText(dd, o[2])
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    onRefresh(function() UIDropDownMenu_SetText(dd, labelFor(get())) end)
    return dd
end

local function slider(parent, text, x, y, minV, maxV, step, get, set)
    local name = "RemindMeOptSlider" .. text:gsub("%W", "")
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", x, y)
    s:SetWidth(200)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local low = s.Low or _G[name .. "Low"]
    local high = s.High or _G[name .. "High"]
    local title = s.Text or _G[name .. "Text"]
    if low then low:SetText(minV) end
    if high then high:SetText(maxV) end
    local function updateTitle(v)
        if title then title:SetText(("%s: %.2f"):format(text, v)) end
    end
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        updateTitle(v)
        if not self.syncing then set(v) end
    end)
    onRefresh(function()
        s.syncing = true
        s:SetValue(get())
        updateTitle(get())
        s.syncing = false
    end)
    return s
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local function refreshAll()
    for _, fn in ipairs(refreshers) do fn() end
end

local ANIMATIONS = {
    { "none", "None" }, { "pulse", "Pulse" }, { "glow", "Glow" },
    { "ring", "Ring" }, { "sparkle", "Sparkles" }, { "comet", "Comet" },
}

local function buildPanel()
    panel = CreateFrame("Frame", "RemindMeOptionsPanel")
    panel.name = PANEL_NAME

    -- Everything lives in a scroll child so the page can grow.
    local scroll = CreateFrame("ScrollFrame", "RemindMeOptionsScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(620, 640)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then content:SetWidth(w) end end)

    local S = ns.settings
    local I = S.indicator
    local refreshIndicator = function() ns.Indicator.Refresh() end

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(PANEL_NAME)
    label(content, "Slack-style reminders. Type |cffffd100/remind help|r for commands.", 16, -40,
        "GameFontHighlightSmall")

    -- Alerts grid: one column per priority ------------------------------
    local y = -72
    header(content, "Alerts by priority", y)

    local COL_X = { low = 190, normal = 330, high = 470 }
    for _, p in ipairs(ns.PRIORITY_ORDER) do
        local fs = label(content, ns.Colorize(p, ns.PRIORITY_LABEL[p]), COL_X[p], y - 22, "GameFontNormal")
        fs:SetWidth(120)
        fs:SetJustifyH("LEFT")
    end

    local function checkRow(rowY, text, tooltip, key, onSet)
        label(content, text, 16, rowY - 6)
        for _, p in ipairs(ns.PRIORITY_ORDER) do
            local prof = S.profiles[p]
            checkbox(content, nil, tooltip, COL_X[p], rowY,
                function() return prof[key] end,
                function(v) prof[key] = v; if onSet then onSet(p) end end,
                text .. " (" .. ns.PRIORITY_LABEL[p] .. ")")
        end
    end

    checkRow(y - 40, "Chat message", "Print the reminder in your chat window.", "chat")
    checkRow(y - 66, "Raid warning", "Large text in the middle of the screen.", "raidWarning")
    checkRow(y - 92, "Play sound", "Play the sound chosen below.", "sound")

    label(content, "Sound", 16, y - 128)
    for _, p in ipairs(ns.PRIORITY_ORDER) do
        local prof = S.profiles[p]
        dropdown(content, COL_X[p], y - 120, 110, ns.Media.Sounds,
            function() return prof.soundKey end,
            function(v) prof.soundKey = v; ns.Media.PlaySound(v) end,
            ns.Media.PlaySound)
    end

    label(content, "Icon animation", 16, y - 162)
    for _, p in ipairs(ns.PRIORITY_ORDER) do
        local prof = S.profiles[p]
        dropdown(content, COL_X[p], y - 154, 110, function() return ANIMATIONS end,
            function() return prof.animation end,
            function(v) prof.animation = v; ns.Indicator.Preview(p) end)
    end

    checkRow(y - 188, "Screen edge flash", "Pulse the edges of the screen in the priority's colour.", "edgeFlash",
        function(p) if S.profiles[p].edgeFlash then ns.Flash.Edges(p) end end)
    checkRow(y - 214, "Taskbar flash",
        "Flash the game's taskbar button when a reminder fires while you're tabbed out.", "taskbarFlash")

    for _, p in ipairs(ns.PRIORITY_ORDER) do
        button(content, "Test", 80, COL_X[p], y - 248, function() ns.Notify.Test(p) end)
    end

    label(content, "Default priority", 16, y - 290)
    label(content, "used when a reminder doesn't say", 16, y - 304, "GameFontDisableSmall")
    dropdown(content, COL_X.low, y - 284, 110,
        function()
            local list = {}
            for _, p in ipairs(ns.PRIORITY_ORDER) do list[#list + 1] = { p, ns.PRIORITY_LABEL[p] } end
            return list
        end,
        function() return S.defaultPriority end,
        function(v) S.defaultPriority = v; refreshIndicator() end)

    -- Indicator -----------------------------------------------------------
    y = -400
    header(content, "On-screen indicator", y)
    checkbox(content, "Show indicator",
        "Show an icon (like the minimap mail icon) while reminders are waiting for you.", 16, y - 20,
        function() return I.enabled end, function(v) I.enabled = v; refreshIndicator() end)
    checkbox(content, "Lock position", "Uncheck to show the icon while this panel is open and drag it anywhere on screen. Once moved it stays there until you click 'Back to minimap'.", 16, y - 46,
        function() return I.locked end, function(v) I.locked = v; refreshIndicator() end)
    checkbox(content, "Only when a reminder is due", "Uncheck to keep the icon on screen all the time; it animates when something is due.", 16, y - 72,
        function() return I.onlyWhenDue ~= false end, function(v) I.onlyWhenDue = v; refreshIndicator() end)

    label(content, "Icon", 250, y - 26, "GameFontNormalSmall")
    local preview = content:CreateTexture(nil, "ARTWORK")
    preview:SetSize(28, 28)
    preview:SetPoint("TOPLEFT", 470, y - 40)
    local function iconOptions()
        local list = {}
        for _, key in ipairs(ns.Media.ICON_ORDER) do
            list[#list + 1] = { key, ns.Media.ICONS[key][1] }
        end
        return list
    end
    dropdown(content, 250, y - 40, 180, iconOptions,
        function() return I.icon end,
        function(v) I.icon = v; preview:SetTexture(ns.Media.IconTexture(v)); refreshIndicator() end)
    onRefresh(function() preview:SetTexture(ns.Media.IconTexture(I.icon)) end)

    slider(content, "Scale", 24, y - 126, 0.5, 2, 0.05,
        function() return I.scale end,
        function(v) I.scale = v; refreshIndicator() end)
    slider(content, "Opacity", 250, y - 126, 0.2, 1, 0.05,
        function() return I.alpha or 1 end,
        function(v) I.alpha = v; refreshIndicator() end)

    button(content, "Preview", 120, 16, y - 166, function() ns.Indicator.Preview() end)
    button(content, "Back to minimap", 120, 146, y - 166, function() ns.Indicator.ResetPosition() end)

    -- Clock -----------------------------------------------------------
    y = -606
    header(content, "Clock", y)
    label(content, "Times like \"at 12pm\" use:", 16, y - 26, "GameFontHighlightSmall")
    dropdown(content, 16, y - 42, 180,
        function() return { { "local", "Local (PC) time" }, { "server", "Realm (server) time" } } end,
        function() return S.clock end,
        function(v) S.clock = v end)
    content:SetHeight(-(y - 42) + 60)

    -- An unlocked indicator is only shown while this panel is open.
    panel:SetScript("OnShow", function()
        refreshAll()
        ns.Indicator.Refresh()
    end)
    panel:SetScript("OnHide", function() ns.Indicator.Refresh() end)
    refreshAll()
end

function Options.Build()
    if panel then return end
    buildPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, PANEL_NAME)
        Settings.RegisterAddOnCategory(category)
        Options.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function Options.IsShown()
    return panel ~= nil and panel:IsVisible()
end

function Options.Open()
    if Options.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(Options.category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Called twice: the first call often lands on the wrong page.
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
