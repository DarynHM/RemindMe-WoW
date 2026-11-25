-- Places.lua
-- The WoW side of location reminders: the place-name dictionary handed to the
-- parser, where the player is right now, and the events that fire place
-- reminders (arriving in a zone/subzone, opening a trainer/mailbox/... window).

local _, ns = ...

local Places = {}
ns.Places = Places

-- Seed names, so cities, zones and dungeons resolve even if C_Map is missing.
-- C_Map adds whatever else this client knows about.
local BUILTIN = {
    "Orgrimmar", "Thunder Bluff", "Undercity", "Stormwind City", "Ironforge", "Darnassus",
    "The Exodar", "Silvermoon City", "Shattrath City", "Booty Bay", "Ratchet", "Gadgetzan",
    "Everlook", "The Crossroads", "Goldshire", "Light's Hope Chapel", "Cenarion Hold",
    "Durotar", "Mulgore", "Tirisfal Glades", "Elwynn Forest", "Dun Morogh", "Teldrassil",
    "The Barrens", "Westfall", "Loch Modan", "Silverpine Forest", "Darkshore",
    "Redridge Mountains", "Duskwood", "Wetlands", "Hillsbrad Foothills", "Ashenvale",
    "Stonetalon Mountains", "Thousand Needles", "Arathi Highlands", "Alterac Mountains",
    "Badlands", "Swamp of Sorrows", "Desolace", "Dustwallow Marsh", "Stranglethorn Vale",
    "Tanaris", "Feralas", "The Hinterlands", "Searing Gorge", "Azshara", "Felwood",
    "Un'Goro Crater", "Burning Steppes", "Western Plaguelands", "Eastern Plaguelands",
    "Winterspring", "Moonglade", "Silithus", "Blasted Lands", "Deadwind Pass",
    "Ragefire Chasm", "Wailing Caverns", "The Deadmines", "Shadowfang Keep",
    "Blackfathom Deeps", "The Stockade", "Gnomeregan", "Razorfen Kraul", "Scarlet Monastery",
    "Razorfen Downs", "Uldaman", "Zul'Farrak", "Maraudon", "Sunken Temple",
    "Blackrock Depths", "Blackrock Spire", "Dire Maul", "Stratholme", "Scholomance",
    "Molten Core", "Onyxia's Lair", "Blackwing Lair", "Zul'Gurub", "Naxxramas",
    "Ruins of Ahn'Qiraj", "Ahn'Qiraj", "Blackrock Mountain",
    "Warsong Gulch", "Arathi Basin", "Alterac Valley",
}

-- Short names people type. Values are PlaceKeys of names above (or names the
-- client's C_Map provides; an alias whose target isn't known is ignored).
-- After a phrase ("when I get to if") any alias counts. Bare ("in org") only
-- 3+ letter ones count, or 2-letter ones typed in capitals ("at IF") - see
-- Parser.lua. "DM" is left out on purpose: Deadmines or Dire Maul?
local ALIASES = {
    -- cities and towns
    org = "orgrimmar", orgri = "orgrimmar", ogri = "orgrimmar", orgrimar = "orgrimmar",
    tb = "thunder bluff", bluff = "thunder bluff", uc = "undercity",
    sw = "stormwind city", stormwind = "stormwind city", ["if"] = "ironforge",
    darn = "darnassus", silvermoon = "silvermoon city", smc = "silvermoon city",
    exo = "exodar", shat = "shattrath city", shatt = "shattrath city",
    shattrath = "shattrath city", dal = "dalaran", dala = "dalaran",
    xr = "crossroads", xroads = "crossroads", bb = "booty bay", gz = "gadgetzan",
    gadget = "gadgetzan", lhc = "lights hope chapel", lights = "lights hope chapel",
    -- zones
    stv = "stranglethorn vale", stranglethorn = "stranglethorn vale",
    ungoro = "ungoro crater", epl = "eastern plaguelands", wpl = "western plaguelands",
    hillsbrad = "hillsbrad foothills", arathi = "arathi highlands", ashen = "ashenvale",
    stonetalon = "stonetalon mountains", needles = "thousand needles",
    ["1k needles"] = "thousand needles", dustwallow = "dustwallow marsh",
    redridge = "redridge mountains", elwynn = "elwynn forest", tirisfal = "tirisfal glades",
    silverpine = "silverpine forest", winter = "winterspring", wsprings = "winterspring",
    brm = "blackrock mountain", hfp = "hellfire peninsula", zang = "zangarmarsh",
    terokkar = "terokkar forest", bem = "blades edge mountains", smv = "shadowmoon valley",
    netherstorm = "netherstorm",
    -- dungeons
    rfc = "ragefire chasm", wc = "wailing caverns", vc = "deadmines", sfk = "shadowfang keep",
    bfd = "blackfathom deeps", stocks = "stockade", stockades = "stockade",
    gnomer = "gnomeregan", rfk = "razorfen kraul", sm = "scarlet monastery",
    ["sm lib"] = "scarlet monastery", ["sm arm"] = "scarlet monastery",
    ["sm cath"] = "scarlet monastery", ["sm gy"] = "scarlet monastery",
    rfd = "razorfen downs", ulda = "uldaman", zf = "zulfarrak", mara = "maraudon",
    st = "sunken temple", brd = "blackrock depths", lbrs = "blackrock spire",
    ubrs = "blackrock spire", strat = "stratholme", strath = "stratholme",
    scholo = "scholomance", kara = "karazhan",
    -- raids
    mc = "molten core", ony = "onyxias lair", onyxia = "onyxias lair",
    bwl = "blackwing lair", zg = "zulgurub", aq20 = "ruins of ahnqiraj",
    aq40 = "ahnqiraj", naxx = "naxxramas",
    -- battlegrounds
    wsg = "warsong gulch", ab = "arathi basin", av = "alterac valley",
}

local MAX_MAP_ID = 2500
local MAX_AREA_ID = 6000

local function key(name) return ns.Parser.PlaceKey(name) end

local dictionary

-- Map types worth offering: zones, dungeons, and micro maps (city districts).
local function wantedMapType(t)
    local E = Enum and Enum.UIMapType
    if E then return t == E.Zone or t == E.Dungeon or t == E.Micro end
    return t == 3 or t == 4 or t == 5
end

local function build()
    local names = {}
    for _, n in ipairs(BUILTIN) do names[key(n)] = n end
    if C_Map and C_Map.GetMapInfo then
        for id = 1, MAX_MAP_ID do
            local ok, info = pcall(C_Map.GetMapInfo, id)
            if ok and info and info.name and info.name ~= "" and wantedMapType(info.mapType) then
                names[key(info.name)] = info.name
            end
        end
    end
    -- Area names cover subzones ("Razor Hill", "Valley of Honor"). They never
    -- replace a map/built-in name, and dev leftovers are skipped.
    if C_Map and C_Map.GetAreaInfo then
        for id = 1, MAX_AREA_ID do
            local ok, name = pcall(C_Map.GetAreaInfo, id)
            if ok and type(name) == "string" and name ~= "" then
                local k = key(name)
                local lower = name:lower()
                if k ~= "" and not names[k] and not lower:find("unused") and not lower:find("test")
                    and not name:find("[%[%*]") then
                    names[k] = name
                end
            end
        end
    end
    return { names = names, aliases = ALIASES }
end

-- { names, aliases } for Parser.Parse(text, { places = ... }). Built on first use.
function Places.ParserContext()
    dictionary = dictionary or build()
    return dictionary
end

---------------------------------------------------------------------------
-- Where am I?
---------------------------------------------------------------------------

-- Set of PlaceKeys describing the player's location: zone, subzone, minimap
-- text, and the map chain up to (not including) the continent.
function Places.CurrentSet()
    local set = {}
    local function add(fn)
        local name = fn and fn()
        if name and name ~= "" then set[key(name)] = true end
    end
    add(GetRealZoneText)
    add(GetZoneText)
    add(GetSubZoneText)
    add(GetMinimapZoneText)

    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
        local id = C_Map.GetBestMapForUnit("player")
        local continent = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
        for _ = 1, 10 do
            local info = id and C_Map.GetMapInfo(id)
            if not info or (info.mapType or 0) <= continent then break end
            if info.name and info.name ~= "" then set[key(info.name)] = true end
            id = info.parentMapID
        end
    end
    return set
end

-- "orgrimmar, valley of honor" - the current place keys, for /remind where
-- and debug output.
function Places.Describe()
    local keys = {}
    for k in pairs(Places.CurrentSet()) do keys[#keys + 1] = k end
    table.sort(keys)
    return table.concat(keys, ", ")
end

function Places.IsHere(placeKey)
    return Places.CurrentSet()[placeKey] == true
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ZONE_EVENTS = {
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
}
local NPC_EVENTS = {
    TRAINER_SHOW = "trainer",
    MAIL_SHOW = "mailbox",
    MERCHANT_SHOW = "vendor",
    BANKFRAME_OPENED = "bank",
    AUCTION_HOUSE_SHOW = "ah",
    TAXIMAP_OPENED = "flight",
    GUILDBANKFRAME_OPENED = "gbank",
}

function Places.CheckNow()
    ns.Scheduler.CheckPlaces(Places.CurrentSet())
end

local frame

-- Called once the scheduler is running. Events this client doesn't have are
-- skipped (RegisterEvent errors on unknown events).
function Places.Start()
    if frame then return end
    frame = CreateFrame("Frame")
    for _, ev in ipairs(ZONE_EVENTS) do pcall(frame.RegisterEvent, frame, ev) end
    for ev in pairs(NPC_EVENTS) do pcall(frame.RegisterEvent, frame, ev) end
    frame:SetScript("OnEvent", function(_, event)
        local npc = NPC_EVENTS[event]
        if npc then
            ns.Debug("%s -> npc '%s'", event, npc)
            ns.Scheduler.CheckNpc(npc)
        else
            ns.Debug("%s -> here: %s", event, Places.Describe())
            Places.CheckNow()
        end
    end)
    Places.CheckNow()
end
