-- ListWindow.lua
-- A basic reminder list window in the default Blizzard style: one row per
-- reminder in priority order, with a priority dropdown, the text, where /
-- when it triggers, its status, and Done / Delete buttons.
--   Open: Shift-click the icon, or /remind list.  Escape closes it.
--   Resize with the grip (bottom right). Text columns size to their content;
--   drag a header's right edge to widen one, double-click the edge to reset.

local _, ns = ...

local ListWindow = {}
ns.ListWindow = ListWindow

local FRAME_NAME = "RemindMeListFrame"
local ROW_H = 26
local PAD = 6                        -- text padding inside a column
local MIN_W, MIN_H = 480, 170
local DEFAULT_W, DEFAULT_H = 660, 300
local HEADER_H = 22

-- key, header title, font, and how the width is set:
--   fixed = width in px; auto columns size to content (capped by `max`).
local COLUMNS = {
    { key = "priority", title = "Priority", fixed = 104 },
    { key = "reminder", title = "Reminder", font = "GameFontHighlight", max = 300, flex = true },
    { key = "trigger",  title = "Triggers", font = "GameFontHighlightSmall", max = 260 },
    { key = "status",   title = "Status",   font = "GameFontHighlightSmall", max = 180 },
    { key = "actions",  title = "",         fixed = 128 },
}

local frame, scroll, list, header, emptyText, measurer
local rows = {}
local headers, handles = {}, {}
local auto = {}      -- auto widths from content, per column key
local widths = {}    -- current layout widths, per column key

local function cfg()
    return ns.settings.window
end

local function hasTemplate(name)
    return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(name) ~= nil
end

---------------------------------------------------------------------------
-- Measuring / layout
---------------------------------------------------------------------------

local function textWidth(font, s)
    measurer:SetFontObject(font)
    measurer:SetText(s or "")
    return measurer:GetStringWidth() or 0
end

local function computeAuto(items)
    for _, col in ipairs(COLUMNS) do
        if not col.fixed then
            local w = textWidth("GameFontNormalSmall", col.title)
            for _, it in ipairs(items) do
                w = math.max(w, textWidth(col.font, it[col.key]))
            end
            auto[col.key] = math.min(math.ceil(w) + PAD * 2, col.max)
        end
    end
end

-- Widths: fixed columns as-is; auto columns use the larger of the auto width
-- and any width you dragged; the flex column (Reminder) also fills spare room.
local function computeWidths()
    local saved = cfg().cols
    local total, flexCol = 0, nil
    for _, col in ipairs(COLUMNS) do
        local w = col.fixed or math.max(auto[col.key] or 40, saved[col.key] or 0)
        widths[col.key] = w
        total = total + w
        if col.flex then flexCol = col end
    end
    local avail = scroll:GetWidth()
    if flexCol and total < avail then
        widths[flexCol.key] = widths[flexCol.key] + (avail - total)
        total = avail
    end
    return total
end

local function applyHeaderWidth(h, w)
    if WhoFrameColumn_SetWidth and h.isWhoHeader then
        WhoFrameColumn_SetWidth(h, w)
    else
        h:SetWidth(w)
    end
end

local function layout()
    if not frame then return end
    local total = computeWidths()
    list:SetWidth(math.max(total, 1))

    local x = 0
    for i, col in ipairs(COLUMNS) do
        local w = widths[col.key]
        local h = headers[i]
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", header, "TOPLEFT", x, 0)
        applyHeaderWidth(h, w)
        if handles[col.key] then
            handles[col.key]:ClearAllPoints()
            handles[col.key]:SetPoint("TOPLEFT", header, "TOPLEFT", x + w - 4, 0)
        end
        for _, row in ipairs(rows) do
            local cell = row.cells[col.key]
            if col.key == "priority" then
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", row, "LEFT", x + 2, 0)
                cell:SetWidth(w - 6)
            elseif col.key == "actions" then
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", row, "LEFT", x + 4, 0)
            else
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", row, "LEFT", x + PAD, 0)
                cell:SetWidth(w - PAD * 2)
            end
        end
        x = x + w
    end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function priorityLabel(p)
    return ns.Colorize(p, ns.PRIORITY_LABEL[p])
end

local function setPriority(r, p)
    if r.priority == p then return end
    r.priority = p
    ns.OnRemindersChanged()
end

local function makePriorityControl(row)
    if hasTemplate("WowStyle1DropdownTemplate") then
        local dd = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
        dd:SetupMenu(function(_, root)
            for _, p in ipairs({ "high", "normal", "low" }) do
                root:CreateRadio(priorityLabel(p),
                    function() return row.reminder and ns.PriorityOf(row.reminder) == p end,
                    function() if row.reminder then setPriority(row.reminder, p) end end)
            end
        end)
        dd.Update = function(self) self:GenerateMenu() end
        return dd
    end
    -- Fallback: a button that cycles High > Normal > Low.
    local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    b:SetHeight(22)
    local NEXT = { high = "normal", normal = "low", low = "high" }
    b:SetScript("OnClick", function()
        if row.reminder then setPriority(row.reminder, NEXT[ns.PriorityOf(row.reminder)]) end
    end)
    b.Update = function(self)
        if row.reminder then self:SetText(priorityLabel(ns.PriorityOf(row.reminder))) end
    end
    return b
end

local function showRowTooltip(row)
    local r = row.reminder
    if not r then return end
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
    local col = ns.PRIORITY_COLOR[ns.PriorityOf(r)]
    GameTooltip:AddLine(row.texts.reminder, col.r, col.g, col.b, true)
    GameTooltip:AddLine(row.texts.trigger, 1, 1, 1, true)
    GameTooltip:AddLine(row.texts.status, 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

local function newRow(i)
    local row = CreateFrame("Frame", nil, list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
    row:EnableMouse(true)
    row.cells, row.texts = {}, {}

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.35)
    hl:SetAllPoints(row)

    row.cells.priority = makePriorityControl(row)

    for _, col in ipairs(COLUMNS) do
        if col.font then
            local fs = row:CreateFontString(nil, "ARTWORK", col.font)
            fs:SetJustifyH("LEFT")
            if fs.SetWordWrap then fs:SetWordWrap(false) end
            if fs.SetMaxLines then fs:SetMaxLines(1) end
            row.cells[col.key] = fs
        end
    end

    local actions = CreateFrame("Frame", nil, row)
    actions:SetSize(120, 22)
    local done = CreateFrame("Button", nil, actions, "UIPanelButtonTemplate")
    done:SetSize(56, 22)
    done:SetPoint("LEFT", actions, "LEFT", 0, 0)
    done:SetText("Done")
    done:SetScript("OnClick", function()
        if row.reminder then ns.Scheduler.Complete(row.reminder) end
    end)
    local delete = CreateFrame("Button", nil, actions, "UIPanelButtonTemplate")
    delete:SetSize(60, 22)
    delete:SetPoint("LEFT", done, "RIGHT", 2, 0)
    delete:SetText("Delete")
    delete:SetScript("OnClick", function()
        if row.reminder then ns.Scheduler.Remove(row.reminder) end
    end)
    row.cells.actions = actions
    row.doneButton = done

    row:SetScript("OnEnter", showRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function setRow(row, r, item)
    row.reminder = r
    row.texts = item
    row.cells.reminder:SetText(item.reminder)
    row.cells.trigger:SetText(item.trigger)
    row.cells.status:SetText(item.status)
    if r.fired then
        row.cells.status:SetTextColor(1, 0.5, 0.25)
    else
        row.cells.status:SetTextColor(0.8, 0.8, 0.8)
    end
    -- A repeating reminder's Done only dismisses the current alert.
    if r.fired or not (r.trigger and r.trigger.every) then
        row.doneButton:Enable()
    else
        row.doneButton:Disable()
    end
    row.cells.priority:Update()
    row:Show()
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local function savePosition()
    local c = cfg()
    c.left, c.top = frame:GetLeft(), frame:GetTop()
    c.w, c.h = frame:GetWidth(), frame:GetHeight()
end

local function setTitle(f, text)
    if f.SetTitle then
        f:SetTitle(text)
    elseif f.TitleText then
        f.TitleText:SetText(text)
    else
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOP", f, "TOP", 0, -6)
        t:SetText(text)
    end
end

-- Default-UI frame: ButtonFrameTemplate, else BasicFrameTemplateWithInset,
-- else a plain dialog box with a close button.
local function createFrame()
    local f, top, bottom
    if hasTemplate("ButtonFrameTemplate") then
        f = CreateFrame("Frame", FRAME_NAME, UIParent, "ButtonFrameTemplate")
        if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(f) end
        if type(f.Inset) == "table" and f.Inset.ClearAllPoints then
            f.Inset:ClearAllPoints()
            f.Inset:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -24)
            f.Inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 22)
        end
        top, bottom = -28, 26
    elseif hasTemplate("BasicFrameTemplateWithInset") then
        f = CreateFrame("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
        top, bottom = -30, 22
    else
        f = CreateFrame("Frame", FRAME_NAME, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
        end
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
        top, bottom = -32, 22
    end
    setTitle(f, "RemindMe")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_W, MIN_H)
    elseif f.SetMinResize then
        f:SetMinResize(MIN_W, MIN_H)
    end
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    f:Hide()
    tinsert(UISpecialFrames, FRAME_NAME)
    return f, top, bottom
end

local function startColumnDrag(handle)
    local key = handle.key
    local startX = GetCursorPosition()
    local startW = widths[key]
    local scale = frame:GetEffectiveScale()
    handle:SetScript("OnUpdate", function()
        local x = GetCursorPosition()
        local w = math.max(auto[key] or 40, startW + (x - startX) / scale)
        cfg().cols[key] = math.floor(w + 0.5)
        layout()
    end)
end

local function build()
    local top, bottom
    frame, top, bottom = createFrame()

    measurer = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    measurer:Hide()

    header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, top)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, top)
    header:SetHeight(HEADER_H)
    if header.SetClipsChildren then header:SetClipsChildren(true) end

    local useWho = hasTemplate("WhoFrameColumnHeaderTemplate")
    for i, col in ipairs(COLUMNS) do
        local h
        if useWho then
            h = CreateFrame("Button", nil, header, "WhoFrameColumnHeaderTemplate")
            h:SetScript("OnClick", nil) -- the template sorts the Who list
            h.isWhoHeader = true
            h:SetText(col.title)
        else
            h = CreateFrame("Frame", nil, header)
            local t = h:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            t:SetPoint("LEFT", h, "LEFT", PAD, 0)
            t:SetText(col.title)
            local line = h:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(1, 1, 1, 0.15)
            line:SetHeight(1)
            line:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
            line:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
        end
        h:SetHeight(HEADER_H)
        headers[i] = h

        -- Drag handle on the right edge of each auto-sized column.
        if not col.fixed then
            local hd = CreateFrame("Button", nil, header)
            hd:SetSize(8, HEADER_H)
            hd:SetFrameLevel(h:GetFrameLevel() + 5)
            hd.key = col.key
            local tex = hd:CreateTexture(nil, "HIGHLIGHT")
            tex:SetColorTexture(1, 0.82, 0, 0.5)
            tex:SetPoint("TOP", hd, "TOP", 0, -2)
            tex:SetPoint("BOTTOM", hd, "BOTTOM", 0, 2)
            tex:SetWidth(2)
            hd:RegisterForClicks("LeftButtonUp")
            hd:SetScript("OnMouseDown", startColumnDrag)
            hd:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
            hd:SetScript("OnDoubleClick", function(self)
                self:SetScript("OnUpdate", nil)
                cfg().cols[self.key] = nil
                layout()
            end)
            hd:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Drag to resize, double-click to reset")
                GameTooltip:Show()
            end)
            hd:SetScript("OnLeave", function() GameTooltip:Hide() end)
            handles[col.key] = hd
        end
    end

    scroll = CreateFrame("ScrollFrame", "RemindMeListScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, bottom)
    list = CreateFrame("Frame", nil, scroll)
    list:SetSize(1, 1)
    scroll:SetScrollChild(list)

    emptyText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    emptyText:SetPoint("TOP", scroll, "TOP", 0, -24)
    emptyText:SetText("No reminders.")

    -- Size grip, bottom right.
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        savePosition()
        layout()
    end)

    frame:SetScript("OnSizeChanged", function() if list then layout() end end)
    frame:SetScript("OnShow", function() ListWindow.Refresh() end)

    -- Restore size and position.
    local c = cfg()
    frame:SetSize(c.w or DEFAULT_W, c.h or DEFAULT_H)
    frame:ClearAllPoints()
    if c.left and c.top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", c.left, c.top)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function ListWindow.Refresh()
    if not frame or not frame:IsShown() or not ns.settings then return end
    local reminders = ns.Scheduler.ByPriority()
    local items = {}
    for i, r in ipairs(reminders) do
        items[i] = {
            reminder = ns.Notify.Escape(r.text),
            trigger = ns.Notify.Escape(ns.Scheduler.TriggerText(r)),
            status = ns.Scheduler.StatusText(r),
        }
    end
    computeAuto(items)
    for i, r in ipairs(reminders) do
        rows[i] = rows[i] or newRow(i)
        setRow(rows[i], r, items[i])
    end
    for i = #reminders + 1, #rows do
        rows[i].reminder = nil
        rows[i]:Hide()
    end
    list:SetHeight(math.max(#reminders * ROW_H, 1))
    if #reminders == 0 then emptyText:Show() else emptyText:Hide() end
    layout()
end

function ListWindow.Open()
    if not ns.settings then return end
    if not frame then build() end
    frame:Show()
    frame:Raise()
    ListWindow.Refresh() -- OnShow doesn't fire if it was already open
end

function ListWindow.Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        ListWindow.Open()
    end
end

function ListWindow.IsShown()
    return frame ~= nil and frame:IsShown()
end
