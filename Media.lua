-- Media.lua
-- Built-in icons and sounds, plus optional LibSharedMedia sounds when some other
-- addon has already loaded LSM (we don't bundle it).

local _, ns = ...

local Media = {}
ns.Media = Media

-- Icons: key -> { label, texture path }
Media.ICON_ORDER = { "watch", "letter", "scroll", "note", "hourglass", "mailbox" }
Media.ICONS = {
    watch     = { "Pocket watch", "Interface\\Icons\\INV_Misc_PocketWatch_01" },
    letter    = { "Letter",       "Interface\\Icons\\INV_Letter_15" },
    scroll    = { "Scroll",       "Interface\\Icons\\INV_Scroll_03" },
    note      = { "Note",         "Interface\\Icons\\INV_Misc_Note_01" },
    hourglass = { "Borrowed time", "Interface\\Icons\\Spell_Holy_BorrowedTime" },
    mailbox   = { "Mailbox",      "Interface\\Minimap\\Tracking\\Mailbox" },
}

function Media.IconTexture(key)
    local entry = Media.ICONS[key] or Media.ICONS.watch
    return entry[2]
end

-- Built-in sounds: key is a SOUNDKIT name; entries missing on this client are skipped.
local BUILTIN_SOUNDS = {
    { "RAID_WARNING",           "Raid warning" },
    { "READY_CHECK",            "Ready check" },
    { "ALARM_CLOCK_WARNING_3",  "Alarm clock" },
    { "IG_QUEST_LIST_COMPLETE", "Quest complete" },
    { "TELL_MESSAGE",           "Whisper" },
    { "MAP_PING",               "Map ping" },
    { "AUCTION_WINDOW_OPEN",    "Auction house" },
    { "IG_PLAYER_INVITE",       "Group invite" },
}

local LSM_PREFIX = "lsm:"

local function getLSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- Ordered list of { key, label } for the sound picker.
function Media.Sounds()
    local list = {}
    for _, s in ipairs(BUILTIN_SOUNDS) do
        if SOUNDKIT and SOUNDKIT[s[1]] then
            list[#list + 1] = { s[1], s[2] }
        end
    end
    local LSM = getLSM()
    if LSM then
        for _, name in ipairs(LSM:List("sound")) do
            if name ~= "None" then
                list[#list + 1] = { LSM_PREFIX .. name, name .. " |cff999999(SharedMedia)|r" }
            end
        end
    end
    return list
end

function Media.SoundLabel(key)
    for _, s in ipairs(Media.Sounds()) do
        if s[1] == key then return s[2] end
    end
    return key
end

function Media.PlaySound(key)
    if key and key:sub(1, #LSM_PREFIX) == LSM_PREFIX then
        local LSM = getLSM()
        local path = LSM and LSM:Fetch("sound", key:sub(#LSM_PREFIX + 1), true)
        if path then
            PlaySoundFile(path, "Master")
            return
        end
    end
    local kit = SOUNDKIT and (SOUNDKIT[key] or SOUNDKIT.RAID_WARNING) or 8959
    PlaySound(kit, "Master")
end
