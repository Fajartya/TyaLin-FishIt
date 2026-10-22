-- Generated bundle. Do not edit; run `npm run bundle` instead.
local __tyalin_modules = {}

__tyalin_modules["license"] = (function()
--[[
    TyaLin license module.

    Validates a license key against a license server that you control. The
    client only sends the user's key, their Roblox user id and a device
    fingerprint; the server decides whether the key is valid, expired, or
    already bound to too many devices.

    The client never holds a shared secret, so nothing here needs to be
    hidden. A client side check can always be patched, so the real value is
    on the server: it can refuse a key, expire it, or revoke it.

    Options:
        endpoint  -> license server URL
        request   -> function(body) -> response string   (injected, testable)
        userId    -> owner id sent to the server
        deviceId  -> device fingerprint sent to the server
        storage   -> { read = fn(path) -> string|nil, write = fn(path, value) }
        keyPath   -> where the key is stored
]]

local License = {}
License.__index = License

local DEFAULT_KEY_PATH = "TyaLin/license.txt"

------------------------------------------------------------------ json
local function jsonEscape(text)
    return tostring(text)
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
        :gsub("\t", "\\t")
end

local function encodeJson(value)
    local kind = type(value)
    if kind == "string" then
        return '"' .. jsonEscape(value) .. '"'
    elseif kind == "number" or kind == "boolean" then
        return tostring(value)
    elseif kind == "table" then
        local parts = {}
        for key, item in pairs(value) do
            parts[#parts + 1] = '"' .. jsonEscape(key) .. '":' .. encodeJson(item)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

-- Flat object parser: {"a":1,"b":"text","c":true}
local function decodeJson(text)
    if type(text) ~= "string" then
        return nil, "not a string"
    end

    local result = {}
    local pos = 1
    local len = #text

    local function skipSpace()
        while pos <= len and text:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local function parseString()
        pos = pos + 1
        local buffer = {}
        while pos <= len do
            local char = text:sub(pos, pos)
            pos = pos + 1
            if char == '"' then
                return table.concat(buffer)
            elseif char == "\\" then
                local escape = text:sub(pos, pos)
                pos = pos + 1
                local map = {
                    n = "\n", t = "\t", r = "\r", b = "\b", f = "\f",
                    ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
                }
                buffer[#buffer + 1] = map[escape] or escape
            else
                buffer[#buffer + 1] = char
            end
        end
        return nil, "unterminated string"
    end

    local function parseValue()
        skipSpace()
        local char = text:sub(pos, pos)
        if char == '"' then
            return parseString()
        elseif char == "{" then
            pos = pos + 1
            local object = {}
            skipSpace()
            if text:sub(pos, pos) == "}" then
                pos = pos + 1
                return object
            end
            while true do
                skipSpace()
                local key = parseString()
                if not key then
                    return nil, "bad key"
                end
                skipSpace()
                if text:sub(pos, pos) ~= ":" then
                    return nil, "missing colon"
                end
                pos = pos + 1
                local value = parseValue()
                if value == nil then
                    return nil, "bad value"
                end
                object[key] = value
                skipSpace()
                local nextChar = text:sub(pos, pos)
                pos = pos + 1
                if nextChar == "}" then
                    break
                end
            end
            return object
        elseif text:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif text:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif text:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            local number = text:sub(pos):match("^-?%d+%.?%d*")
            if not number or number == "" then
                return nil, "bad number"
            end
            pos = pos + #number
            return tonumber(number)
        end
    end

    local value, err = parseValue()
    if value == nil and err == nil then
        return nil, "empty response"
    end
    return value, err
end

------------------------------------------------------------------ transport
local function urlEncode(text)
    return tostring(text):gsub("[^%w%-%_%.%~]", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
end

local function defaultTransport(self, body, payload)
    local requestFn = request
    if type(requestFn) ~= "function" and type(syn) == "table" then
        requestFn = syn.request
    end
    if type(requestFn) ~= "function" and type(http_request) == "function" then
        requestFn = http_request
    end

    if type(requestFn) == "function" then
        local ok, response = pcall(requestFn, {
            Url = self.endpoint,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
        if ok and type(response) == "string" and response ~= "" then
            return response
        end
        return nil, tostring(response)
    end

    if type(game) == "table" and type(game.HttpGet) == "function" then
        local url = string.format(
            "%s?key=%s&userId=%s&deviceId=%s&timestamp=%s",
            self.endpoint,
            urlEncode(payload.key),
            urlEncode(payload.userId),
            urlEncode(payload.deviceId),
            tostring(payload.timestamp)
        )
        local ok, response = pcall(game.HttpGet, game, url)
        if ok and type(response) == "string" and response ~= "" then
            return response
        end
        return nil, tostring(response)
    end

    return nil, "no HTTP transport available"
end

------------------------------------------------------------------ module
function License.new(options)
    options = options or {}

    local self = setmetatable({
        endpoint = options.endpoint or "",
        request = options.request,
        userId = tostring(options.userId or "unknown"),
        deviceId = tostring(options.deviceId or "unknown"),
        storage = options.storage,
        keyPath = options.keyPath or DEFAULT_KEY_PATH,
        state = {
            key = nil,
            valid = false,
            expiresAt = nil,
            plan = nil,
            message = "Not verified.",
            checkedAt = nil,
        },
    }, License)

    return self
end

function License:status()
    return self.state.message
end

function License:isValid()
    if not self.state.valid then
        return false
    end
    if self.state.expiresAt and self.state.expiresAt > 0 and self.state.expiresAt < os.time() then
        return false
    end
    return true
end

function License:decode(response)
    if type(response) ~= "string" or response == "" then
        return nil, "empty response"
    end
    return decodeJson(response)
end

function License:send(body, payload)
    if type(self.request) == "function" then
        local ok, response, err = pcall(self.request, body, payload)
        if not ok then
            return nil, tostring(response)
        end
        if type(response) ~= "string" or response == "" then
            return nil, tostring(err or "empty response")
        end
        return response
    end
    return defaultTransport(self, body, payload)
end

function License:verify(key)
    if type(key) ~= "string" or key == "" then
        self.state.valid = false
        self.state.message = "No license key given."
        return false, self.state.message
    end

    if self.endpoint == "" then
        self.state.valid = false
        self.state.message = "No license server is configured."
        return false, self.state.message
    end

    local payload = {
        key = key,
        userId = self.userId,
        deviceId = self.deviceId,
        timestamp = os.time(),
    }

    local response, err = self:send(encodeJson(payload), payload)
    if not response then
        self.state.valid = false
        self.state.message = "License server unreachable: " .. tostring(err)
        return false, self.state.message
    end

    local data, decodeErr = self:decode(response)
    if type(data) ~= "table" then
        self.state.valid = false
        self.state.message = "Unexpected license response: " .. tostring(decodeErr)
        return false, self.state.message
    end

    self.state.key = key
    self.state.valid = data.valid == true
    self.state.expiresAt = tonumber(data.expires) or nil
    self.state.plan = data.plan
    self.state.message = tostring(
        data.message or (self.state.valid and "License valid." or "License rejected.")
    )
    self.state.checkedAt = os.time()

    if self.state.valid then
        self:saveKey(key)
    end

    return self.state.valid, self.state.message
end

function License:saveKey(key)
    if not self.storage or type(self.storage.write) ~= "function" then
        return false, "no storage"
    end
    local ok, err = pcall(self.storage.write, self.keyPath, key)
    return ok, err
end

function License:loadKey()
    if not self.storage or type(self.storage.read) ~= "function" then
        return nil
    end
    local ok, value = pcall(self.storage.read, self.keyPath)
    if ok and type(value) == "string" and value ~= "" then
        self.state.key = value
        return value
    end
    return nil
end

-- Loads the stored key and verifies it in one step.
function License:checkStored()
    local key = self:loadKey()
    if not key then
        self.state.message = "No stored license key."
        return false, self.state.message
    end
    return self:verify(key)
end

License.encodeJson = encodeJson
License.decodeJson = decodeJson

return License

end)()

__tyalin_modules["config"] = (function()
--[[
    TyaLin settings schema.

    Every persisted setting is declared here once, with the type and the
    values it accepts. sanitize() takes whatever was read from disk and
    returns a clean settings table plus the list of problems it found, so a
    corrupted, outdated or hand edited config falls back to the defaults
    instead of breaking the hub.

    The values follow Fish It: the rarity ladder is Common, Uncommon, Rare,
    Epic, Legendary, Mythic, Secret, Forgotten. Islands and NPCs use the
    names the game itself shows.

    The hub uses this module when it is bundled into the payload; without a
    bundle it keeps working with the same rules inlined in TyaLin.lua.
]]

local Config = {}

-- Ordered from the most common tier to the rarest one.
Config.RARITY_VALUES = {
    "Common",
    "Uncommon",
    "Rare",
    "Epic",
    "Legendary",
    "Mythic",
    "Secret",
    "Forgotten",
}

Config.TELEPORT_TARGETS = { "Spots", "NPCs", "Islands", "Players" }
Config.MODES = { "Legit", "Blatant" }
Config.THEMES = { "Minimal" }

-- Islands the game ships with, used by the island picker.
Config.ISLANDS = {
    "Fisherman Island",
    "Kohana Volcano",
    "Coral Reefs",
    "Tropical Grove",
    "Lost Isle",
    "Deep Sea",
    "Ancient Jungle",
    "Esoteric Depths",
    "Copper Canyon",
    "Crater Island",
    "Classic Island",
    "Underwater City",
    "Treasure Room",
    "Sisyphus Statue",
}

-- NPCs the game ships with, used by the NPC picker.
Config.NPCS = {
    "Sell NPC",
    "Appraiser Jess",
    "Bait Burt",
    "Spin Wheel",
    "Luck Machine",
    "Enchant Altar",
    "Luck Totem",
    "Mermaid",
    "Boat Expert",
    "Hazmat Leader",
    "Joe's Rods",
    "Traveling Merchant",
    "Party Wizard",
    "John Doe",
}

Config.DEFAULTS = {
    AutoFishing = false,
    AutoSell = false,
    AutoStart = false,
    AutoCycle = false,
    Notifications = true,
    Theme = "Minimal",
    LicenseKey = "",
    LicenseEndpoint = "",
    LicenseRequired = false,
    Mode = "Legit",
    MinRarity = "Uncommon",
    MaxRarity = "Forgotten",
    TeleportTarget = "Spots",
    IncludeSecret = false,
    AutoEquipRod = true,
    AutoEquipBait = true,
    InventoryLimit = 10,
    RecastDelay = 0.4,
    BiteTimeout = 20,
    TargetIsland = "",
    TargetNPC = "",
}

Config.SCHEMA = {
    AutoFishing = { kind = "boolean" },
    AutoSell = { kind = "boolean" },
    AutoStart = { kind = "boolean" },
    AutoCycle = { kind = "boolean" },
    Notifications = { kind = "boolean" },
    Theme = { kind = "string", values = Config.THEMES },
    LicenseKey = { kind = "string" },
    LicenseEndpoint = { kind = "string" },
    LicenseRequired = { kind = "boolean" },
    Mode = { kind = "string", values = Config.MODES },
    MinRarity = { kind = "string", values = Config.RARITY_VALUES },
    MaxRarity = { kind = "string", values = Config.RARITY_VALUES },
    TeleportTarget = { kind = "string", values = Config.TELEPORT_TARGETS },
    IncludeSecret = { kind = "boolean" },
    AutoEquipRod = { kind = "boolean" },
    AutoEquipBait = { kind = "boolean" },
    InventoryLimit = { kind = "number", min = 1, max = 200 },
    RecastDelay = { kind = "number", min = 0, max = 60 },
    BiteTimeout = { kind = "number", min = 1, max = 300 },
    TargetIsland = { kind = "string" },
    TargetNPC = { kind = "string" },
}

local function copyDefaults()
    local copy = {}
    for key, value in pairs(Config.DEFAULTS) do
        copy[key] = value
    end
    return copy
end

-- Rank inside the rarity ladder, 0 for unknown names.
function Config.rank(rarity)
    for index, name in ipairs(Config.RARITY_VALUES) do
        if name == rarity then
            return index
        end
    end
    return 0
end

function Config.defaults()
    return copyDefaults()
end

local function isOneOf(value, allowed)
    for _, name in ipairs(allowed) do
        if name == value then
            return true
        end
    end
    return false
end

--[[
    sanitize(raw) -> settings, problems

    settings holds only known keys with the right type and an accepted
    value. problems is a list of human readable descriptions, one per field
    that had to be replaced by its default.
]]
function Config.sanitize(raw)
    local settings = copyDefaults()
    local problems = {}

    if type(raw) ~= "table" then
        problems[#problems + 1] = "config was not a table"
        return settings, problems
    end

    for key, value in pairs(raw) do
        local schema = Config.SCHEMA[key]
        if not schema then
            problems[#problems + 1] = "unknown setting '" .. tostring(key) .. "' was dropped"
        elseif schema.kind == "boolean" then
            if type(value) == "boolean" then
                settings[key] = value
            else
                problems[#problems + 1] = key .. " must be true or false"
            end
        elseif schema.kind == "number" then
            if type(value) ~= "number" then
                problems[#problems + 1] = key .. " must be a number"
            elseif value < schema.min or value > schema.max then
                problems[#problems + 1] = key .. " is out of range"
            else
                settings[key] = value
            end
        elseif schema.kind == "string" then
            if type(value) ~= "string" then
                problems[#problems + 1] = key .. " must be text"
            elseif schema.values and not isOneOf(value, schema.values) then
                problems[#problems + 1] = key .. " has an unsupported value"
            else
                settings[key] = value
            end
        end
    end

    -- A range that runs backwards is repaired instead of rejected.
    if Config.rank(settings.MinRarity) > Config.rank(settings.MaxRarity) then
        settings.MinRarity, settings.MaxRarity = settings.MaxRarity, settings.MinRarity
        problems[#problems + 1] = "the rarity range was reversed"
    end

    return settings, problems
end

--[[
    merge(current, changes) -> settings, problems

    Applies a partial table of changes on top of the current settings and
    validates the result.
]]
function Config.merge(current, changes)
    local base = copyDefaults()
    if type(current) == "table" then
        for key, value in pairs(current) do
            if Config.SCHEMA[key] then
                base[key] = value
            end
        end
    end
    if type(changes) == "table" then
        for key, value in pairs(changes) do
            base[key] = value
        end
    end
    return Config.sanitize(base)
end

return Config

end)()

__tyalin_modules["rarities"] = (function()
--[[
    Shared rarity ladder.

    Ordered from the most common tier to the rarest one:

        Common -> Uncommon -> Rare -> Epic -> Legendary -> Mythic -> Secret -> Forgotten

    "Forgotten" is the newest tier in Fish It, above "Secret", with spawn
    chances around 1 in 25 million.

    The order is a default: every module accepts an explicit list when a game
    uses a different ladder.
]]

local Rarities = {}

Rarities.Order = {
    "Common",
    "Uncommon",
    "Rare",
    "Epic",
    "Legendary",
    "Mythic",
    "Secret",
    "Forgotten",
}

Rarities.Index = {}
for position, name in ipairs(Rarities.Order) do
    Rarities.Index[name] = position
end

-- Rank of a rarity name. Unknown names rank 0.
function Rarities.Rank(name)
    return Rarities.Index[name] or 0
end

-- True when name is at least as rare as minimum.
function Rarities.AtLeast(name, minimum)
    local rank = Rarities.Rank(name)
    if rank == 0 then
        return false
    end
    return rank >= Rarities.Rank(minimum)
end

-- True when name sits between minimum and maximum (inclusive).
function Rarities.Between(name, minimum, maximum)
    local rank = Rarities.Rank(name)
    if rank == 0 then
        return false
    end
    if minimum and rank < Rarities.Rank(minimum) then
        return false
    end
    if maximum and rank > Rarities.Rank(maximum) then
        return false
    end
    return true
end

-- List of rarity names between minimum and maximum (inclusive).
function Rarities.List(minimum, maximum)
    local list = {}
    for _, name in ipairs(Rarities.Order) do
        if Rarities.Between(name, minimum, maximum) then
            list[#list + 1] = name
        end
    end
    return list
end

-- Next rarity in the ladder, wrapping around at the end.
function Rarities.Next(name, step)
    local index = Rarities.Index[name]
    if not index then
        return Rarities.Order[1]
    end
    local target = index + (step or 1)
    if target < 1 then
        target = #Rarities.Order
    elseif target > #Rarities.Order then
        target = 1
    end
    return Rarities.Order[target]
end

return Rarities

end)()

__tyalin_modules["enchants"] = (function()
--[[
    TyaLin enchant table.

    The rod enchants of Fish It. Every entry lists what the enchant does,
    which slot it can live in and how strong it is.

    Luck and reel speed are the two numbers the fishing loop cares about:
    a rod with a high reel speed gives a shorter window to reel in, so the
    loop has to check more often. A rod with a negative luck (Cursed I) is
    a bad rod for rare hunting, and the gear module warns about it.

    Slot:
        primary -> rolled at the Enchant Altar
        second  -> only with a Transcended Stone at the Sacred Temple
]]

local Enchants = {}

--[[
    luck        flat luck percent, negative when the enchant hurts
    reelSpeed   percent faster reeling, 0 when it does not change it
    mutation    percent more mutation chance
    shiny       percent more shiny chance
    gold        percent more gold mutation chance
    size        percent bigger fish
    xp          experience multiplier
    fairy       percent more fairy dust
    night       luck bonus that only counts at night
    rain        luck bonus that only counts while it rains
    secret      luck bonus for secret rarity fish
    shark       luck bonus for shark fish
    rainbow     fewer casts needed for the rainbow boost
    tier        S, A, B, C or D
]]

Enchants.List = {
    {
        name = "Leprechaun II",
        tier = "S",
        luck = 50,
    },
    {
        name = "Mutation Hunter II",
        tier = "S",
        mutation = 30,
    },
    {
        name = "Empowered I",
        tier = "S",
        luck = 20,
        reelSpeed = 10,
    },
    {
        name = "Leprechaun I",
        tier = "A",
        luck = 30,
    },
    {
        name = "Big Hunter I",
        tier = "A",
        size = 10,
    },
    {
        name = "Prismatic I",
        tier = "A",
        rainbow = 10,
    },
    {
        name = "Gold Digger I",
        tier = "A",
        gold = 10,
    },
    {
        name = "Cursed I",
        tier = "A",
        luck = -75,
        mutation = 75,
    },
    {
        name = "Mutation Hunter I",
        tier = "B",
        mutation = 10,
    },
    {
        name = "XPerienced I",
        tier = "B",
        xp = 1.5,
    },
    {
        name = "Reeler II",
        tier = "B",
        reelSpeed = 14,
    },
    {
        name = "Reeler I",
        tier = "B",
        reelSpeed = 7,
    },
    {
        name = "Stargazer I",
        tier = "C",
        luck = 60,
        night = true,
    },
    {
        name = "Stargazer II",
        tier = "C",
        luck = 100,
        night = true,
    },
    {
        name = "Stormhunter I",
        tier = "C",
        luck = 80,
        rain = true,
    },
    {
        name = "Stormhunter II",
        tier = "C",
        luck = 140,
        rain = true,
    },
    {
        name = "Glistening I",
        tier = "D",
        shiny = 10,
    },
    {
        name = "Mutation Hunter III",
        tier = "S",
        mutation = 40,
    },
    {
        name = "Stormhunter III",
        tier = "S",
        luck = 200,
        rain = true,
    },
    {
        name = "Perfection",
        tier = "S",
        slot = "second",
        perfect = true,
    },
    {
        name = "SECRET Hunter",
        tier = "S",
        secret = 100,
    },
    {
        name = "Shark Hunter",
        tier = "S",
        shark = 100,
    },
    {
        name = "Fairy Hunter I",
        tier = "A",
        fairy = 20,
    },
}

Enchants.Index = {}
for _, entry in ipairs(Enchants.List) do
    Enchants.Index[entry.name] = entry
end

-- Tiers from the strongest to the weakest.
Enchants.TierOrder = { "S", "A", "B", "C", "D" }

-- The enchant with that name, or nil.
function Enchants.Get(name)
    if type(name) ~= "string" then
        return nil
    end
    return Enchants.Index[name]
end

--[[
    Effects(name)

    The numbers of one enchant. Unknown names give an empty table, so a rod
    with a newer enchant still works.
]]
function Enchants.Effects(name)
    local entry = Enchants.Get(name)
    if not entry then
        return {}
    end

    local effects = {}
    for key, value in pairs(entry) do
        if key ~= "name" and key ~= "tier" and key ~= "slot" then
            effects[key] = value
        end
    end
    return effects
end

-- How strong an enchant is. Higher is better.
function Enchants.Score(name)
    local entry = Enchants.Get(name)
    if not entry then
        return 0
    end

    local score = 0
    score = score + (entry.luck or 0) * 10
    score = score + (entry.reelSpeed or 0) * 20
    score = score + (entry.mutation or 0) * 8
    score = score + (entry.shiny or 0) * 6
    score = score + (entry.gold or 0) * 6
    score = score + (entry.size or 0) * 4
    score = score + (entry.fairy or 0) * 4
    score = score + (entry.secret or 0) * 6
    score = score + (entry.shark or 0) * 6
    if entry.night or entry.rain then
        score = score + 40
    end
    if entry.perfect then
        score = score + 60
    end
    if (entry.xp or 1) > 1 then
        score = score + 20
    end
    return score
end

--[[
    EffectiveLuck(name, weather)

    The luck the enchant really gives right now. Night and rain enchants
    only count when it is night or raining, and a negative luck stays
    negative.
]]
function Enchants.EffectiveLuck(name, weather)
    weather = weather or {}

    local entry = Enchants.Get(name)
    if not entry then
        return 0
    end

    local luck = entry.luck or 0
    if entry.night and not weather.night then
        luck = 0
    end
    if entry.rain and not weather.rain then
        luck = 0
    end
    return luck
end

--[[
    ReelSpeed(name)

    How much faster the rod reels in. A higher number means a shorter
    window, so the loop checks more often.
]]
function Enchants.ReelSpeed(name)
    local entry = Enchants.Get(name)
    if not entry then
        return 0
    end
    return entry.reelSpeed or 0
end

--[[
    Best(list)

    The strongest enchant in a list. The list holds either names or tables
    with an "enchant" field.
]]
function Enchants.Best(list)
    local best
    local bestScore = nil
    for _, entry in ipairs(list or {}) do
        local name = entry
        if type(entry) == "table" then
            name = entry.enchant or entry.name
        end
        local score = Enchants.Score(name)
        if bestScore == nil or score > bestScore then
            best = name
            bestScore = score
        end
    end
    return best, bestScore or 0
end

return Enchants

end)()

__tyalin_modules["locations"] = (function()
--[[
    TyaLin location database.

    Holds the known positions for Fish It so teleport can pick the right
    place even if the injected API does not return coordinates, or to show
    a clean picker to the user.

    Names follow the game: islands, NPCs, and player targets. Coordinates
    are in workspace units; exact values depend on the game build, but the
    shape matches the map the community knows.
]]

local Locations = {}

-- Fishing islands / boat spots people usually want to go to.
Locations.Islands = {
    { id = "fisherman_island", name = "Fisherman Island", position = Vector3.new(-29, 4, 137) },
    { id = "kohana_volcano", name = "Kohana Volcano", position = Vector3.new(-656, 25, 178) },
    { id = "coral_reefs", name = "Coral Reefs", position = Vector3.new(-3095, 3, 1304) },
    { id = "tropical_grove", name = "Tropical Grove", position = Vector3.new(-2033, 8, -716) },
    { id = "lost_isle", name = "Lost Isle", position = Vector3.new(3697, 46, 937) },
    { id = "deep_sea", name = "Deep Sea", position = Vector3.new(5400, -150, 2100) },
    { id = "ancient_jungle", name = "Ancient Jungle", position = Vector3.new(7115, 52, -1325) },
    { id = "esoteric_depths", name = "Esoteric Depths", position = Vector3.new(3150, -195, -2920) },
    { id = "copper_canyon", name = "Copper Canyon", position = Vector3.new(11280, 88, 2460) },
    { id = "crater_island", name = "Crater Island", position = Vector3.new(14850, 64, -865) },
    { id = "classic_island", name = "Classic Island", position = Vector3.new(-8420, 36, 5640) },
    { id = "underwater_city", name = "Underwater City", position = Vector3.new(-9640, -248, -7120) },
    { id = "treasure_room", name = "Treasure Room", position = Vector3.new(9025, -312, 1280) },
    { id = "sisyphus_statue", name = "Sisyphus Statue", position = Vector3.new(12640, -426, -1845) },
}

-- NPCs the player usually wants to walk to.
Locations.NPCs = {
    { id = "sell_npc", name = "Sell NPC", position = Vector3.new(-42, 4, 118) },
    { id = "appraiser_jess", name = "Appraiser Jess", position = Vector3.new(-16, 4, 146) },
    { id = "bait_burt", name = "Bait Burt", position = Vector3.new(28, 4, 102) },
    { id = "spin_wheel", name = "Spin Wheel", position = Vector3.new(64, 5, 156) },
    { id = "luck_machine", name = "Luck Machine", position = Vector3.new(-84, 5, 64) },
    { id = "enchant_altar", name = "Enchant Altar", position = Vector3.new(3150, -195, -2920) },
    { id = "luck_totem", name = "Luck Totem", position = Vector3.new(162, 6, 86) },
    { id = "mermaid", name = "Mermaid", position = Vector3.new(428, 4, -244) },
    { id = "boat_expert", name = "Boat Expert", position = Vector3.new(-118, 4, 84) },
    { id = "hazmat_leader", name = "Hazmat Leader", position = Vector3.new(-656, 26, 196) },
    { id = "joes_rods", name = "Joe's Rods", position = Vector3.new(-6, 4, 176) },
    { id = "traveling_merchant", name = "Traveling Merchant", position = Vector3.new(246, 5, 214) },
    { id = "party_wizard", name = "Party Wizard", position = Vector3.new(-196, 6, 242) },
    { id = "john_doe", name = "John Doe", position = Vector3.new(324, 6, 168) },
}

-- Common fishing spots by island. Handy when you want to hop straight to
-- a spot without looping the whole list.
Locations.Spots = {
    { id = "fisherman_island", name = "Fisherman Island", position = Vector3.new(-29, 4, 137) },
    { id = "kohana_volcano", name = "Kohana Volcano", position = Vector3.new(-656, 25, 178) },
    { id = "coral_reefs", name = "Coral Reefs", position = Vector3.new(-3095, 3, 1304) },
    { id = "tropical_grove", name = "Tropical Grove", position = Vector3.new(-2033, 8, -716) },
    { id = "lost_isle", name = "Lost Isle", position = Vector3.new(3697, 46, 937) },
    { id = "treasure_room", name = "Treasure Room", position = Vector3.new(9025, -312, 1280) },
    { id = "sisyphus_statue", name = "Sisyphus Statue", position = Vector3.new(12640, -426, -1845) },
    { id = "underwater_city", name = "Underwater City", position = Vector3.new(-9640, -248, -7120) },
}

-- Build a lookup table by name/id.
Locations.ByName = {}
for kind, list in pairs({ Islands = Locations.Islands, NPCs = Locations.NPCs, Spots = Locations.Spots }) do
    Locations.ByName[kind] = {}
    for _, entry in ipairs(list) do
        local key = tostring(entry.name):lower()
        Locations.ByName[kind][key] = entry
        if entry.id then
            Locations.ByName[kind][tostring(entry.id):lower()] = entry
        end
    end
end

--[[
    Get(kind, name)

    Looks up a location by kind (islands/npcs/spots/players) and name.
    Returns the entry or nil.
]]
function Locations.Get(kind, name)
    if not kind or not name then
        return nil
    end
    local lowerKind = tostring(kind):lower()
    local map = Locations.ByName[lowerKind == "player" and "Players" or (lowerKind == "npc" and "NPCs" or (lowerKind == "island" and "Islands" or (lowerKind == "spot" and "Spots" or nil)))]
    if not map then
        if lowerKind == "players" and Locations.ByName.Players then
            map = Locations.ByName.Players
        end
    end
    if not map then
        return nil
    end
    return map[tostring(name):lower()]
end

-- List for a target kind.
function Locations.List(kind)
    local lowerKind = tostring(kind):lower()
    if lowerKind == "npcs" or lowerKind == "npc" then
        return Locations.NPCs
    elseif lowerKind == "islands" or lowerKind == "island" then
        return Locations.Islands
    elseif lowerKind == "spots" or lowerKind == "spot" then
        return Locations.Spots
    elseif lowerKind == "players" or lowerKind == "player" then
        return Locations.Players or {}
    end
    return {}
end

-- All entries combined in order of kind.
function Locations.All()
    local out = {}
    for _, entry in ipairs(Locations.Spots) do
        out[#out + 1] = entry
    end
    for _, entry in ipairs(Locations.NPCs) do
        out[#out + 1] = entry
    end
    for _, entry in ipairs(Locations.Islands) do
        out[#out + 1] = entry
    end
    for _, entry in ipairs(Locations.Players or {}) do
        out[#out + 1] = entry
    end
    return out
end

return Locations


end)()

__tyalin_modules["gear"] = (function()
--[[
    TyaLin gear module.

    Keeps track of what is actually in the hands: which rod is equipped,
    which enchant it carries and which bait is selected. The fishing loop
    uses that information for two things.

    1. Adaptive settings. A rod with a high reel speed gives a shorter
       window, so the loop checks more often and recasts faster. The
       enchant adds to that: Reeler II and Empowered I reel in faster.

    2. Ghost fishing protection. Ghost fishing is what happens when the
       script casts while the previous line is still out, or when the rod
       or the enchant changes halfway through a session. The server then
       keeps the old line and the new one is lost, so nothing is ever
       caught. The module takes a snapshot before every cast and compares
       it with the current state; a mismatch cancels the stale line before
       the next cast.

    API contract:
        api.GetRods()         -> { { id, name, rarity, luck, speed,
                                     enchant = "Leprechaun II" | { name = ... },
                                     equipped = bool } }
        api.GetEquippedRod()  -> rod (optional)
        api.GetBait()         -> bait (optional)
        api.GetCastState()    -> { casting = bool, rodId, spotId } (optional)
        api.CancelCast()      -> cancels the line (optional)
        api.EquipRod(id)      -> ok, error
]]

local Gear = {}
Gear.__index = Gear

local DEFAULTS = {
    biteTimeout = 20,
    recastDelay = 0.4,
    poll = 0.25,
    minPoll = 0.05,
    maxPoll = 0.5,
    requireEnchant = false,
    minRarity = nil,
    preferEnchant = nil, -- an enchant name, "best" or nil
}

local function enchantModule()
    local registry = rawget(_G, "__tyalin_modules")
    if type(registry) == "table" and type(registry.enchants) == "table" then
        return registry.enchants
    end
    return nil
end

-- The enchant of a rod, as a name.
local function enchantName(rod)
    if type(rod) ~= "table" then
        return nil
    end
    local enchant = rod.enchant or rod.enchants or rod.enchantment
    if type(enchant) == "string" then
        return enchant
    end
    if type(enchant) == "table" then
        return enchant.name or enchant[1]
    end
    return nil
end

function Gear.new(api, options)
    assert(type(api) == "table", "Gear.new requires an api table")
    options = options or {}

    local self = setmetatable({
        api = api,
        options = {
            biteTimeout = options.biteTimeout or DEFAULTS.biteTimeout,
            recastDelay = options.recastDelay or DEFAULTS.recastDelay,
            poll = options.poll or DEFAULTS.poll,
            minPoll = options.minPoll or DEFAULTS.minPoll,
            maxPoll = options.maxPoll or DEFAULTS.maxPoll,
            requireEnchant = options.requireEnchant == true,
            minRarity = options.minRarity,
            preferEnchant = options.preferEnchant,
        },
        snapshot = nil,
        stats = { checks = 0, ghosts = 0, switches = 0 },
    }, Gear)

    self.onStatus = options.onStatus
    return self
end

function Gear:report(message)
    if self.onStatus then
        self.onStatus(message)
    end
end

-- Every rod the game exposes.
function Gear:rods()
    if type(self.api.GetRods) ~= "function" then
        return {}
    end
    local ok, list = pcall(self.api.GetRods)
    if not ok or type(list) ~= "table" then
        return {}
    end
    return list
end

-- The rod that is in the hands right now.
function Gear:current()
    if type(self.api.GetEquippedRod) == "function" then
        local ok, rod = pcall(self.api.GetEquippedRod)
        if ok and type(rod) == "table" then
            return rod
        end
    end

    for _, rod in ipairs(self:rods()) do
        if type(rod) == "table" and rod.equipped then
            return rod
        end
    end
    return nil
end

-- The bait that is selected.
function Gear:bait()
    if type(self.api.GetBait) ~= "function" then
        return nil
    end
    local ok, bait = pcall(self.api.GetBait)
    if ok and type(bait) == "table" then
        return bait
    end
    return nil
end

--[[
    profile()

    The settings that fit the rod in the hands. A faster rod gets a shorter
    bite timeout, a shorter recast delay and a tighter polling interval, so
    the loop keeps up with the reel.
]]
function Gear:profile()
    local rod = self:current()
    local profile = {
        rod = rod,
        rodId = rod and rod.id or nil,
        rodName = rod and rod.name or nil,
        rarity = rod and rod.rarity or nil,
        enchant = nil,
        enchantTier = nil,
        luck = 0,
        reelSpeed = 0,
        biteTimeout = self.options.biteTimeout,
        recastDelay = self.options.recastDelay,
        poll = self.options.poll,
    }

    if not rod then
        return profile
    end

    local enchants = enchantModule()
    local name = enchantName(rod)
    profile.enchant = name

    if enchants and name then
        local entry = enchants.Get(name)
        if entry then
            profile.enchantTier = entry.tier
        end
        profile.luck = enchants.EffectiveLuck(name, self:weather()) or 0
        profile.reelSpeed = enchants.ReelSpeed(name) or 0
    end

    -- The rod's own speed and luck count as well.
    local baseSpeed = tonumber(rod.speed) or 0
    profile.luck = profile.luck + (tonumber(rod.luck) or 0)

    local speedFactor = 1 + ((baseSpeed + profile.reelSpeed) / 100)

    profile.biteTimeout = math.max(3, self.options.biteTimeout / math.max(1, speedFactor))
    profile.recastDelay = math.max(0.05, self.options.recastDelay / math.max(1, speedFactor))

    local poll = self.options.poll / math.max(1, speedFactor)
    profile.poll = math.max(self.options.minPoll, math.min(self.options.maxPoll, poll))

    return profile
end

-- The weather, when the game reports it.
function Gear:weather()
    if type(self.api.GetWeather) ~= "function" then
        return {}
    end
    local ok, weather = pcall(self.api.GetWeather)
    if ok and type(weather) == "table" then
        return weather
    end
    return {}
end

--[[
    isGhost()

    True when a line from an earlier cast is still out. Casting on top of
    it is what makes a script fish forever without catching anything.
]]
function Gear:isGhost()
    if type(self.api.GetCastState) ~= "function" then
        return false
    end
    local ok, state = pcall(self.api.GetCastState)
    if not ok or type(state) ~= "table" then
        return false
    end
    return state.casting == true
end

--[[
    snapshot()

    Remembers the rod, the enchant and the bait for the next cast. The
    snapshot is what the guard compares against.
]]
function Gear:snapshot()
    local profile = self:profile()
    self.snapshot = {
        rodId = profile.rodId,
        enchant = profile.enchant,
        baitId = self:bait() and self:bait().id or nil,
        at = self.api.Now and self.api.Now() or nil,
    }
    return self.snapshot
end

--[[
    guard()

    Compares the snapshot with the current state. When the rod, the
    enchant or the bait changed, the stale line is cancelled so the next
    cast starts clean. Returns ok, message.
]]
function Gear:guard()
    self.stats.checks = self.stats.checks + 1

    if not self.snapshot then
        return true, "no snapshot"
    end

    local rod = self:current()
    local rodId = rod and rod.id or nil
    local enchant = enchantName(rod)
    local bait = self:bait()
    local baitId = bait and bait.id or nil

    local changed = nil
    if rodId ~= self.snapshot.rodId then
        changed = "rod changed"
    elseif enchant ~= self.snapshot.enchant then
        changed = "enchant changed"
    elseif baitId ~= self.snapshot.baitId then
        changed = "bait changed"
    end

    if not changed then
        return true, "unchanged"
    end

    self.stats.switches = self.stats.switches + 1

    if self:isGhost() then
        self.stats.ghosts = self.stats.ghosts + 1
        if type(self.api.CancelCast) == "function" then
            pcall(self.api.CancelCast)
        end
        self:report("stale line cancelled (" .. changed .. ")")
        return false, "stale line cancelled (" .. changed .. ")"
    end

    return false, changed
end

--[[
    check()

    The full check before a cast: the rod has to be there, it may need an
    enchant and no old line may still be out. Returns ok, message.
]]
function Gear:check()
    local rod = self:current()
    if not rod then
        return false, "no rod equipped"
    end

    if self.options.requireEnchant then
        local name = enchantName(rod)
        if not name then
            return false, "the equipped rod has no enchant"
        end
    end

    if self:isGhost() then
        self.stats.ghosts = self.stats.ghosts + 1
        if type(self.api.CancelCast) == "function" then
            pcall(self.api.CancelCast)
        end
        self:report("ghost fishing detected, old line cleared")
        return false, "ghost fishing cleared"
    end

    return true, "ready"
end

--[[
    wants(rod)

    True when this rod fits the preferences: it has the wanted enchant, it
    is at least the wanted rarity and it has an enchant when one is
    required.
]]
function Gear:wants(rod)
    if type(rod) ~= "table" then
        return false
    end

    local name = enchantName(rod)
    if self.options.requireEnchant and not name then
        return false
    end

    local prefer = self.options.preferEnchant
    if prefer and prefer ~= "best" and name ~= prefer then
        return false
    end

    return true
end

-- The strongest rod that fits the preferences.
function Gear:best()
    local enchants = enchantModule()
    local best
    local bestScore = nil

    for _, rod in ipairs(self:rods()) do
        if self:wants(rod) then
            local score = 0
            score = score + (tonumber(rod.luck) or 0) * 10
            score = score + (tonumber(rod.speed) or 0) * 5
            if enchants then
                score = score + enchants.Score(enchantName(rod))
            end
            if bestScore == nil or score > bestScore then
                best = rod
                bestScore = score
            end
        end
    end

    return best, bestScore or 0
end

return Gear

end)()

__tyalin_modules["rod"] = (function()
--[[
    TyaLin rod module.

    Picks the strongest rod the game exposes and equips it, so the fishing
    loop always uses the best gear available.

    API contract:
        api.GetRods()    -> { { id, name, rarity, power, level, equipped } }
        api.EquipRod(id) -> ok, error

    Like every other module this one only talks to the injected API table,
    so it works with any game that exposes rods.
]]

local Rod = {}
Rod.__index = Rod

local RARITY_FALLBACK = {
    "Common", "Uncommon", "Rare", "Epic", "Legendary",
    "Mythic", "Secret", "Forgotten",
}

local function rarityRank(name)
    local registry = rawget(_G, "__tyalin_modules")
    local module = registry and registry.rarities
    if type(module) == "table" and type(module.Rank) == "function" then
        return module.Rank(name)
    end
    for index, entry in ipairs(RARITY_FALLBACK) do
        if entry == name then
            return index
        end
    end
    return 0
end

function Rod.new(api, options)
    assert(type(api) == "table", "Rod.new requires an api table")
    options = options or {}

    local self = setmetatable({
        api = api,
        options = {
            prefer = options.prefer, -- "best" (default), a rod id or a rod name
        },
        stats = { equipped = 0, equippedId = nil },
    }, Rod)

    self.onStatus = options.onStatus
    return self
end

function Rod:report(message)
    if self.onStatus then
        self.onStatus(message)
    end
end

function Rod:rods()
    if type(self.api.GetRods) ~= "function" then
        return {}
    end
    local ok, list = pcall(self.api.GetRods)
    if not ok or type(list) ~= "table" then
        return {}
    end
    return list
end

-- Rarer rods win first, then the stronger ones, then the higher level.
function Rod:score(rod)
    local rank = rarityRank(rod.rarity)
    return rank * 1000000
        + (tonumber(rod.power) or 0) * 1000
        + (tonumber(rod.level) or 0)
end

function Rod:best()
    local best
    for _, rod in ipairs(self:rods()) do
        if type(rod) == "table" and (not best or self:score(rod) > self:score(best)) then
            best = rod
        end
    end
    return best
end

-- A rod the user asked for by id or by name.
function Rod:preferred()
    local prefer = self.options.prefer
    if not prefer or prefer == "" or prefer == "best" then
        return nil
    end
    for _, rod in ipairs(self:rods()) do
        if tostring(rod.id) == tostring(prefer) or tostring(rod.name) == tostring(prefer) then
            return rod
        end
    end
    return nil
end

function Rod:equip(rod)
    if type(rod) ~= "table" then
        return false, "no rod available"
    end
    if type(self.api.EquipRod) ~= "function" then
        return false, "this game does not expose rods"
    end

    local ok, err = self.api.EquipRod(rod.id)
    if not ok then
        return false, err or "equip failed"
    end

    self.stats.equipped = self.stats.equipped + 1
    self.stats.equippedId = rod.id
    local message = "equipped " .. tostring(rod.name)
    self:report(message)
    return true, message
end

function Rod:equipBest()
    local rod = self:preferred() or self:best()
    if not rod then
        return false, "no rod available"
    end
    if rod.equipped then
        self.stats.equippedId = rod.id
        return true, tostring(rod.name) .. " is already equipped"
    end
    return self:equip(rod)
end

return Rod

end)()

__tyalin_modules["bait"] = (function()
--[[
    TyaLin bait module.

    Equips the strongest bait the game exposes, the same way the rod module
    picks a rod.

    API contract:
        api.GetBaits()    -> { { id, name, rarity, equipped } }
        api.EquipBait(id) -> ok, error
]]

local Bait = {}
Bait.__index = Bait

local RARITY_FALLBACK = {
    "Common", "Uncommon", "Rare", "Epic", "Legendary",
    "Mythic", "Secret", "Forgotten",
}

local function rarityRank(name)
    local registry = rawget(_G, "__tyalin_modules")
    local module = registry and registry.rarities
    if type(module) == "table" and type(module.Rank) == "function" then
        return module.Rank(name)
    end
    for index, entry in ipairs(RARITY_FALLBACK) do
        if entry == name then
            return index
        end
    end
    return 0
end

function Bait.new(api, options)
    assert(type(api) == "table", "Bait.new requires an api table")
    options = options or {}

    local self = setmetatable({
        api = api,
        options = {
            prefer = options.prefer,
        },
        stats = { equipped = 0, equippedId = nil },
    }, Bait)

    self.onStatus = options.onStatus
    return self
end

function Bait:report(message)
    if self.onStatus then
        self.onStatus(message)
    end
end

function Bait:baits()
    if type(self.api.GetBaits) ~= "function" then
        return {}
    end
    local ok, list = pcall(self.api.GetBaits)
    if not ok or type(list) ~= "table" then
        return {}
    end
    return list
end

function Bait:score(bait)
    return rarityRank(bait.rarity) * 1000000 + (tonumber(bait.luck) or 0)
end

function Bait:best()
    local best
    for _, bait in ipairs(self:baits()) do
        if type(bait) == "table" and (not best or self:score(bait) > self:score(best)) then
            best = bait
        end
    end
    return best
end

function Bait:preferred()
    local prefer = self.options.prefer
    if not prefer or prefer == "" or prefer == "best" then
        return nil
    end
    for _, bait in ipairs(self:baits()) do
        if tostring(bait.id) == tostring(prefer) or tostring(bait.name) == tostring(prefer) then
            return bait
        end
    end
    return nil
end

function Bait:equip(bait)
    if type(bait) ~= "table" then
        return false, "no bait available"
    end
    if type(self.api.EquipBait) ~= "function" then
        return false, "this game does not expose baits"
    end

    local ok, err = self.api.EquipBait(bait.id)
    if not ok then
        return false, err or "equip failed"
    end

    self.stats.equipped = self.stats.equipped + 1
    self.stats.equippedId = bait.id
    local message = "equipped " .. tostring(bait.name)
    self:report(message)
    return true, message
end

function Bait:equipBest()
    local bait = self:preferred() or self:best()
    if not bait then
        return false, "no bait available"
    end
    if bait.equipped then
        self.stats.equippedId = bait.id
        return true, tostring(bait.name) .. " is already equipped"
    end
    return self:equip(bait)
end

return Bait

end)()

__tyalin_modules["multi_rod"] = (function()
--[[
    TyaLin multi rod module.

    Fish It lets a player keep more than one rod on the bar. Every rod on
    the bar casts its own line, so several fish can be pulled in the same
    pull instead of one fish per pull. That is the difference between the
    plain game and a script that fishes with a full bar.

    This module keeps the equipped rods in sync and drives them together:

        local multi = MultiRod.new(api, { max = 3 })
        multi:equipBestSet()      -- fill the bar with the strongest rods
        multi:cast(spotId)        -- one line per rod on the bar
        multi:waitBites(timeout)  -- pull every rod that bit
        multi:haulReady()         -- returns the fish that were pulled

    API contract:
        api.GetRods()    -> { { id, name, rarity, luck, speed, equipped } }
        api.EquipRod(id) -> ok, error
        api.Cast(spotId, rodId)    -> ok, error
        api.Haul(rodId)            -> fish, error
        api.IsBiteReady(rodId)     -> boolean (optional)
        api.OnBite(handler)        -> connection (Disconnect)
        api.Wait(seconds)          -> waits
]]

local MultiRod = {}
MultiRod.__index = MultiRod

local RARITY_FALLBACK = {
    "Common", "Uncommon", "Rare", "Epic", "Legendary",
    "Mythic", "Secret", "Forgotten",
}

local function rarityRank(name)
    local registry = rawget(_G, "__tyalin_modules")
    local module = registry and registry.rarities
    if type(module) == "table" and type(module.Rank) == "function" then
        return module.Rank(name)
    end
    for index, entry in ipairs(RARITY_FALLBACK) do
        if entry == name then
            return index
        end
    end
    return 0
end

local DEFAULTS = {
    max = 3,        -- how many rods may sit on the bar at once
    prefer = nil,   -- "best" (default), a rod id or a rod name
    settleTime = 0.05,
}

function MultiRod.new(api, options)
    assert(type(api) == "table", "MultiRod.new requires an api table")
    options = options or {}

    local self = setmetatable({
        api = api,
        options = {
            max = math.max(1, math.min(tonumber(options.max) or DEFAULTS.max, 5)),
            prefer = options.prefer or DEFAULTS.prefer,
            settleTime = options.settleTime or DEFAULTS.settleTime,
        },
        stats = { casts = 0, pulls = 0, fish = 0 },
    }, MultiRod)

    self.onStatus = options.onStatus
    return self
end

function MultiRod:report(message)
    if self.onStatus then
        self.onStatus(message)
    end
end

function MultiRod:rods()
    if type(self.api.GetRods) ~= "function" then
        return {}
    end
    local ok, list = pcall(self.api.GetRods)
    if not ok or type(list) ~= "table" then
        return {}
    end
    return list
end

-- The rods that are on the bar right now.
function MultiRod:equipped()
    local list = {}
    for _, rod in ipairs(self:rods()) do
        if type(rod) == "table" and rod.equipped then
            list[#list + 1] = rod
        end
    end
    return list
end

-- How many rods may be used at once.
function MultiRod:capacity()
    local count = #self:equipped()
    if count == 0 then
        return 0
    end
    return math.min(count, self.options.max)
end

-- Rarer rods win first, then the stronger ones.
function MultiRod:score(rod)
    return rarityRank(rod.rarity) * 1000000
        + (tonumber(rod.luck) or tonumber(rod.power) or 0) * 1000
        + (tonumber(rod.speed) or 0)
end

--[[
    equipBestSet()

    Fills the bar with the strongest rods the game exposes. The bar is a
    limited slot list, so a game that only allows one rod keeps one.
]]
function MultiRod:equipBestSet()
    if type(self.api.EquipRod) ~= "function" then
        return 0, "this game does not expose rods"
    end

    local rods = self:rods()
    if #rods == 0 then
        return 0, "no rods available"
    end

    local wanted = {}
    if self.options.prefer and self.options.prefer ~= "best" then
        for _, rod in ipairs(rods) do
            if tostring(rod.id) == tostring(self.options.prefer)
                or tostring(rod.name) == tostring(self.options.prefer) then
                wanted[#wanted + 1] = rod
            end
        end
    end

    if #wanted == 0 then
        local sorted = {}
        for _, rod in ipairs(rods) do
            sorted[#sorted + 1] = rod
        end
        table.sort(sorted, function(a, b)
            if self:score(a) == self:score(b) then
                return tostring(a.id) < tostring(b.id)
            end
            return self:score(a) > self:score(b)
        end)
        for index = 1, math.min(self.options.max, #sorted) do
            wanted[index] = sorted[index]
        end
    end

    local equipped = 0
    for _, rod in ipairs(wanted) do
        if equipped >= self.options.max then
            break
        end
        local ok = rod.equipped
        if not ok then
            local callOk, result = pcall(self.api.EquipRod, rod.id)
            ok = callOk and result and true or false
        end
        if ok then
            equipped = equipped + 1
        end
    end

    if equipped == 0 then
        return 0, "no rod could be equipped"
    end

    self:report(string.format("bar ready: %d rod(s)", equipped))
    return equipped
end

--[[
    cast(spotId)

    Casts one line per rod on the bar. Returns the number of lines that went
    out and a list of the rods that are now waiting for a bite.
]]
function MultiRod:cast(spotId)
    local rods = self:equipped()
    if #rods == 0 then
        return 0, {}
    end

    local waiting = {}
    for index = 1, math.min(#rods, self.options.max) do
        local rod = rods[index]
        local ok, err
        if type(self.api.Cast) == "function" then
            ok, err = self.api.Cast(spotId, rod.id)
        else
            ok, err = false, "this game does not expose a cast call"
        end
        if ok then
            waiting[#waiting + 1] = rod
            self.stats.casts = self.stats.casts + 1
        else
            self:report("cast failed: " .. tostring(err))
        end
    end

    if #waiting == 0 then
        return 0, "every cast was refused"
    end
    return #waiting, waiting
end

-- The rods that already bit.
function MultiRod:ready()
    local list = {}
    for _, rod in ipairs(self:equipped()) do
        if type(self.api.IsBiteReady) == "function" then
            local ok, ready = pcall(self.api.IsBiteReady, rod.id)
            if ok and ready then
                list[#list + 1] = rod
            end
        end
    end
    return list
end

-- Pulls every rod that bit. Returns the fish that were pulled.
function MultiRod:haulReady()
    local fish = {}
    for _, rod in ipairs(self:ready()) do
        if type(self.api.Haul) == "function" then
            local ok, result = pcall(self.api.Haul, rod.id)
            if ok and type(result) == "table" then
                fish[#fish + 1] = result
                self.stats.fish = self.stats.fish + 1
            end
        end
    end

    if #fish > 0 then
        self.stats.pulls = self.stats.pulls + 1
    end
    return fish
end

--[[
    waitBites(timeout)

    Waits until at least one rod bites or the timeout expires, and pulls
    every rod that is ready. Returns the fish that were pulled.
]]
function MultiRod:waitBites(timeout)
    local poll = 0.25
    local waited = 0
    local pulled = {}

    while waited < timeout do
        self.api.Wait(poll)
        waited = waited + poll

        local ready = self:ready()
        if #ready > 0 then
            pulled = self:haulReady()
            if #pulled > 0 then
                return pulled
            end
        end
    end

    return pulled
end

return MultiRod

end)()

__tyalin_modules["notifier"] = (function()
--[[
    TyaLin notifier.

    In "legit" mode every message is printed as it arrives. In "blatant" mode
    the messages are grouped by kind and only a short summary is printed, so
    a fishing session produces about three lines instead of one line per
    event.

    Groups are recognised by the wording of the message:
        caught, sold, equipped, arrived, timeout, failed, error, license

    A group that reaches the threshold prints one line right away, so a long
    session still shows progress without flooding the console.

    Usage:
        local notifier = Notifier.new({
            mode = "legit",
            max = 3,
            threshold = 10,
            onMessage = function(text) print(text) end,
            onUpdate = function(summary) end,
        })

        notifier:push("caught Kraken (Secret)")
        notifier:flush()
]]

local Notifier = {}
Notifier.__index = Notifier

-- Ordered by priority: the first match wins.
local PATTERNS = {
    { word = "too many", key = "failures", priority = 1 },
    { word = "cast failed", key = "failed", priority = 1 },
    { word = "failed", key = "failed", priority = 1 },
    { word = "error", key = "error", priority = 1 },
    { word = "reject", key = "rejected", priority = 1 },
    { word = "timeout", key = "timeout", priority = 2 },
    { word = "caught", key = "caught", priority = 2 },
    { word = "sold", key = "sold", priority = 2 },
    { word = "license", key = "license", priority = 3 },
    { word = "equipped", key = "equipped", priority = 3 },
    { word = "arrived", key = "arrived", priority = 4 },
    { word = "teleport", key = "teleport", priority = 4 },
    { word = "config", key = "config", priority = 5 },
    { word = "mode", key = "mode", priority = 5 },
}

local DEFAULTS = {
    mode = "legit",
    max = 3,
    threshold = 10,
}

function Notifier.new(options)
    options = options or {}

    local self = setmetatable({
        mode = options.mode or DEFAULTS.mode,
        max = options.max or DEFAULTS.max,
        threshold = options.threshold or DEFAULTS.threshold,
        groups = {},
        order = {},
        onMessage = options.onMessage,
        onUpdate = options.onUpdate,
    }, Notifier)

    return self
end

function Notifier:isSummary()
    return self.mode ~= "legit"
end

function Notifier:setMode(mode)
    if mode == self.mode then
        return
    end
    self:flush()
    self.mode = mode
    self:updateStatus()
end

-- Recognises the kind of a message.
function Notifier:classify(message)
    local text = string.lower(tostring(message))
    for _, pattern in ipairs(PATTERNS) do
        if text:find(pattern.word, 1, true) then
            return pattern.key, pattern.priority
        end
    end
    return "other", 6
end

function Notifier:emit(text)
    if self.onMessage then
        self.onMessage(text)
    end
end

function Notifier:line(group)
    if group.count <= 1 then
        return group.last
    end
    return string.format("%s x%d  (%s)", group.key, group.count, group.last)
end

function Notifier:removeGroup(key)
    self.groups[key] = nil
    for index, name in ipairs(self.order) do
        if name == key then
            table.remove(self.order, index)
            break
        end
    end
end

--[[
    push(message)

    Legit mode prints the message straight away. Summary mode files it under
    its group and prints a line for that group once it reaches the threshold.
]]
function Notifier:push(message)
    if type(message) ~= "string" or message == "" then
        return
    end

    if not self:isSummary() then
        self:emit(message)
        return
    end

    local key, priority = self:classify(message)
    local group = self.groups[key]
    if not group then
        group = { key = key, priority = priority, count = 0, last = message }
        self.groups[key] = group
        self.order[#self.order + 1] = key
    end

    group.count = group.count + 1
    group.last = message

    if group.count >= self.threshold then
        self:emit(self:line(group))
        group.count = 0
        self:removeGroup(key)
    end

    self:updateStatus()
end

--[[
    flush()

    Prints the pending groups, most important first, at most "max" lines.
    The remaining groups are mentioned in the last line.
]]
function Notifier:flush()
    if not self:isSummary() then
        return
    end

    local pending = {}
    for _, key in ipairs(self.order) do
        local group = self.groups[key]
        if group then
            pending[#pending + 1] = group
        end
    end
    if #pending == 0 then
        return
    end

    table.sort(pending, function(a, b)
        if a.priority == b.priority then
            return a.key < b.key
        end
        return a.priority < b.priority
    end)

    local shown = math.min(self.max, #pending)
    for index = 1, shown do
        self:emit(self:line(pending[index]))
    end

    local extra = #pending - shown
    if extra > 0 then
        self:emit(string.format("+%d more message group(s)", extra))
    end

    self.groups = {}
    self.order = {}
    self:updateStatus()
end

function Notifier:reset()
    self.groups = {}
    self.order = {}
    self:updateStatus()
end

-- One line describing everything that is pending.
function Notifier:summary()
    if not self:isSummary() then
        return ""
    end
    if #self.order == 0 then
        return "quiet"
    end

    local parts = {}
    for _, key in ipairs(self.order) do
        local group = self.groups[key]
        if group then
            parts[#parts + 1] = string.format("%s x%d", group.key, group.count)
        end
    end
    return table.concat(parts, "  |  ")
end

function Notifier:updateStatus()
    if self.onUpdate then
        self.onUpdate(self:summary())
    end
end

return Notifier

end)()

__tyalin_modules["auto_bridge"] = (function()
--[[
    TyaLin Auto Bridge

    Tries to discover fishing related remotes in the game and builds an
    adapter that fits the TyaLin modules (Fishing, MultiRod, Gear, AutoSell).

    This does not hardcode a single game's remote table. It looks for common
    patterns:
        ReplicatedStorage, Remotes, Network, Events, Packages
        names containing: fish, cast, reel, bait, rod, sell, inventory, bite

    If it cannot find enough remotes, it falls back to the mock-like
    contract and reports what it found so the user knows why.
]]

local AutoBridge = {}

local function findServices()
    local services = {}
    pcall(function() services.ReplicatedStorage = game:GetService("ReplicatedStorage") end)
    pcall(function() services.ReplicatedFirst = game:GetService("ReplicatedFirst") end)
    pcall(function() services.Workspace = game:GetService("Workspace") end)
    pcall(function() services.Players = game:GetService("Players") end)
    pcall(function() services.StarterGui = game:GetService("StarterGui") end)
    return services
end

local function deepScan(root, depth, out)
    depth = depth or 0
    if not root or depth > 6 then
        return
    end
    local ok, children = pcall(function() return root:GetChildren() end)
    if not ok or not children then
        return
    end
    for _, child in ipairs(children) do
        table.insert(out, child)
        deepScan(child, depth + 1, out)
    end
end

local function scoreInstance(inst, hints)
    local name = string.lower(inst.Name or "")
    local className = inst.ClassName or ""
    local score = 0
    if className == "RemoteEvent" or className == "RemoteFunction" or className == "UnreliableRemoteEvent" then
        score = score + 2
    end
    for _, hint in ipairs(hints) do
        if name:find(hint) then
            score = score + 3
        end
    end
    if name:find("fish") then score = score + 2 end
    if name:find("cast") then score = score + 2 end
    if name:find("reel") then score = score + 2 end
    if name:find("haul") then score = score + 2 end
    if name:find("bite") then score = score + 2 end
    if name:find("rod") then score = score + 1 end
    if name:find("sell") then score = score + 1 end
    return score
end

local function findRemotes()
    local services = findServices()
    local candidates = {}
    local roots = {}
    for _, svc in pairs(services) do
        if svc then table.insert(roots, svc) end
    end
    pcall(function() table.insert(roots, game) end)

    for _, root in ipairs(roots) do
        local list = {}
        deepScan(root, 0, list)
        for _, inst in ipairs(list) do
            local score = scoreInstance(inst, {"fish", "cast", "reel", "pull", "rod", "bait", "sell", "inventory"})
            if score >= 3 then
                candidates[#candidates + 1] = { instance = inst, score = score, name = inst.Name }
            end
        end
    end

    table.sort(candidates, function(a,b) return a.score > b.score end)
    return candidates
end

local function fireRemote(remote, ...)
    if not remote then return false, "no remote" end
    local className = remote.ClassName
    if className == "RemoteFunction" then
        local ok, res = pcall(function() return remote:InvokeServer(...) end)
        return ok, res
    elseif className == "RemoteEvent" or className == "UnreliableRemoteEvent" then
        local ok, err = pcall(function() remote:FireServer(...) end)
        return ok, err
    end
    return false, "unknown remote type"
end

function AutoBridge.build(options)
    options = options or {}
    local remotes = findRemotes()
    local Fishing = options.Fishing
    local MultiRod = options.MultiRod
    local Gear = options.Gear
    local Rod = options.Rod
    local Bait = options.Bait
    local AutoSell = options.AutoSell
    local Teleport = options.Teleport
    local Locations = options.Locations

    local api = {}
    api.name = options.name or "auto-bridge"
    api.remotes = remotes

    -- Try to wire common calls
    for _, cand in ipairs(remotes) do
        local name = string.lower(cand.name)
        if not api.Cast and (name:find("cast")) then api._cast = cand.instance end
        if not api.Reel and (name:find("reel") or name:find("pull")) then api._reel = cand.instance end
        if not api.Haul and (name:find("haul")) then api._haul = cand.instance end
        if not api.Sell and name:find("sell") then api._sell = cand.instance end
        if not api.EquipRod and name:find("equip") and name:find("rod") then api._equiprod = cand.instance end
        if not api.EquipBait and name:find("equip") and name:find("bait") then api._equipbait = cand.instance end
    end

    function api.Cast(spotId)
        if api._cast then
            return fireRemote(api._cast, spotId)
        end
        return false, "no cast remote found"
    end

    function api.Haul()
        if api._haul then
            local ok, res = fireRemote(api._haul)
            if ok then return res end
        end
        if api._reel then
            local ok, res = fireRemote(api._reel)
            if ok then return res end
        end
        return nil, "no haul remote found"
    end

    function api.GetSpots()
        if options.getSpots then return options.getSpots() end
        if Locations and Locations.List then return Locations.List("spots") end
        return {}
    end

    function api.GetNPCs()
        if options.getNPCs then return options.getNPCs() end
        if Locations and Locations.List then return Locations.List("npcs") end
        return {}
    end

    function api.GetIslands()
        if options.getIslands then return options.getIslands() end
        if Locations and Locations.List then return Locations.List("islands") end
        return {}
    end

    function api.GetPlayers()
        if options.getPlayers then return options.getPlayers() end
        if Locations and Locations.List then return Locations.List("players") end
        return {}
    end

    function api.Wait(seconds)
        local t = tonumber(seconds) or 0
        if type(task) == "table" and task.wait then
            task.wait(t)
            return
        end
        if typeof and typeof(game:GetService("RunService")) == "Instance" then
            local rs = game:GetService("RunService")
            if rs.Heartbeat then
                local start = tick()
                while tick() - start < t do rs.Heartbeat:Wait() end
                return
            end
        end
    end

    function api.OnBite(handler)
        local connection = {}
        function connection:Disconnect() end
        return connection
    end

    function api.IsBiteReady()
        return true
    end

    function api.CancelCast()
        return true
    end

    function api.MoveTo(pos)
        local player = game:GetService("Players").LocalPlayer
        local char = player and player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp and pos then
            pcall(function() hrp.CFrame = CFrame.new(pos) end)
            return true
        end
        return false, "no character"
    end

    function api.SitBoat()
        local player = game:GetService("Players").LocalPlayer
        local char = player and player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function() hum:Sit() end)
        end
        return true
    end

    function api.ForceFloat()
        local player = game:GetService("Players").LocalPlayer
        local char = player and player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Swimming) end)
        end
        return true
    end

    function api.StopMovement()
        local player = game:GetService("Players").LocalPlayer
        local char = player and player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then pcall(function() hrp.AssemblyLinearVelocity = Vector3.new() end) end
        return true
    end

    function api.EquipRod(id)
        if api._equiprod then return fireRemote(api._equiprod, id) end
        if Rod and Rod.equipBest then return Rod.equipBest() end
        return false, "no equip rod remote"
    end

    function api.EquipBait(id)
        if api._equipbait then return fireRemote(api._equipbait, id) end
        if Bait and Bait.equipBest then return Bait.equipBest() end
        return false, "no equip bait remote"
    end

    function api.Sell(ids)
        if api._sell then
            local ok, res = fireRemote(api._sell, ids)
            if ok then return res end
        end
        return 0, 0
    end

    local session = { fishing = nil }
    local adapter = { name = api.name .. (#remotes > 0 and " (linked)" or " (scan)"), api = api }

    function adapter.startAutoFishing(report, opts)
        if not Fishing then return false, "Fishing module missing" end
        opts = opts or {}

        local fishing = Fishing.new(api, {
            maxCasts = opts.maxCasts or 50,
            biteTimeout = opts.biteTimeout or 20,
            recastDelay = opts.recastDelay or 0.25,
            includeSecret = opts.includeSecret ~= false,
            multiPull = true,
            mode = string.lower(opts.Mode or "blatant"),
            autoEquipRod = opts.AutoEquipRod ~= false,
            autoEquipBait = opts.AutoEquipBait ~= false,
            minRarity = opts.MinRarity,
            maxRarity = opts.MaxRarity,
            onStatus = function(m) if report then report(m) end end,
            onCatch = function(c) if report then report("Caught: " .. tostring(c.name) .. " [" .. tostring(c.rarity) .. "]") end end,
        })

        if Gear then fishing.gear = Gear.new(api, { onStatus = function(m) if report then report(m) end end }) end
        if MultiRod then fishing.multi = MultiRod.new(api, { max = 3, onStatus = function(m) if report then report(m) end end }) end
        if Rod then fishing.rod = Rod.new(api, { onStatus = function(m) if report then report(m) end end }) end
        if Bait then fishing.bait = Bait.new(api, { onStatus = function(m) if report then report(m) end end }) end

        session.fishing = fishing
        if type(task) == "table" and task.spawn then
            task.spawn(function()
                local st = fishing:run()
                session.fishing = nil
                if report then
                    report(string.format("Auto Fishing finished: %d casts | %d catches", st.casts or 0, st.catches or 0))
                end
            end)
            return true, "Auto Fishing started (" .. (#remotes > 0 and "linked" or "searching") .. ")", true
        end

        local st = fishing:start()
        session.fishing = nil
        return true, string.format("Auto Fishing finished: %d casts | %d catches", st.casts or 0, st.catches or 0), false
    end

    function adapter.stopAutoFishing(report)
        if session.fishing then
            session.fishing:stop()
            session.fishing = nil
            if report then report("Auto Fishing stopped.") end
            return true, "Auto Fishing stopped."
        end
        return false, "no session running"
    end

    function adapter.autoSell(report, opts)
        if not AutoSell then return false, "AutoSell module missing" end
        opts = opts or {}
        local seller = AutoSell.new(api, {
            maxInventory = opts.InventoryLimit or 10,
            minRarity = opts.MinRarity or "Uncommon",
            maxRarity = opts.MaxRarity or "Forgotten",
            onStatus = function(m) if report then report(m) end end,
        })
        local sold, msg = seller:tick()
        if sold then return true, msg or "Auto sell finished." end
        return false, msg or "Nothing to sell."
    end

    function adapter.teleport(report, target)
        if not Teleport then return false, "Teleport module missing" end
        local tp = Teleport.new(api, {
            target = string.lower(target or "spots"),
            order = "price",
            includeSecret = true,
            useBoat = true,
            floatOnWater = true,
            forceFloat = true,
            onStatus = function(m) if report then report(m) end end,
        })
        if Locations then tp.locations = Locations end
        if type(target) == "string" and target ~= "Spots" and target ~= "NPCs" and target ~= "Islands" and target ~= "Players" then
            local ok, res = tp:goTo(target)
            if ok then return true, "Arrived at " .. tostring(res) end
            return false, res
        end
        local visited = tp:run()
        local count = 0
        for _ in pairs(visited) do count = count + 1 end
        return true, string.format("Teleport finished: %d waypoints visited.", count)
    end

    function adapter.equipRod(report)
        if api.EquipRod then
            local ok, res = api.EquipRod()
            if report then report(ok and (res or "Rod equipped") or (res or "Equip failed")) end
            return ok and true or false, res
        end
        return false, "no rod equip"
    end

    function adapter.equipBait(report)
        if api.EquipBait then
            local ok, res = api.EquipBait()
            if report then report(ok and (res or "Bait equipped") or (res or "Equip failed")) end
            return ok and true or false, res
        end
        return false, "no bait equip"
    end

    return adapter
end

return AutoBridge

end)()

__tyalin_modules["fishing"] = (function()
--[[
    TyaLin fishing module.

    Owns the fishing state machine only:

        Idle -> Cast -> Wait for bite -> Haul -> repeat

    Every server interaction goes through an injected API table, so this file
    never references a specific game's remotes. The same module runs against
    the mock server in mock/ and against a live server once an authorized
    API implementation is supplied by the caller.

    API contract:
        api.Cast(spotId)              -> ok, error
        api.Haul()                    -> fish, error
        api.OnBite(handler)           -> connection (Disconnect)
        api.Wait(seconds)             -> waits, advances the clock
        api.IsBiteReady()             -> boolean (optional)
        api.GetSpots()                -> { { id, name, rarity, price, secret } }
]]

local Fishing = {}
Fishing.__index = Fishing

local RARITY_FALLBACK = {
    "Common", "Uncommon", "Rare", "Epic", "Legendary",
    "Mythic", "Secret", "Forgotten",
}

local function rarityRank(name)
    local registry = rawget(_G, "__tyalin_modules")
    local module = registry and registry.rarities
    if type(module) == "table" and type(module.Rank) == "function" then
        return module.Rank(name)
    end
    for index, entry in ipairs(RARITY_FALLBACK) do
        if entry == name then
            return index
        end
    end
    return 0
end

-- Pacing per mode. "legit" keeps human like delays, "blatant" casts as fast
-- as the server accepts.
Fishing.Pacing = {
    legit = { poll = 1, recast = 1.5 },
    blatant = { poll = 0.25, recast = 0.1 },
}

local DEFAULTS = {
    biteTimeout = 20,
    recastDelay = 0.4,
    maxCasts = nil,
    maxErrors = 5,
    stopOnRarity = nil,
    includeSecret = false,
    spotOrder = nil,
    minRarity = nil,
    maxRarity = nil,
    mode = "legit",
    autoEquipRod = true,
    autoEquipBait = true,
    multiPull = false,
}

function Fishing.new(api, options)
    assert(type(api) == "table", "Fishing.new requires an api table")
    options = options or {}

    local self = setmetatable({
        api = api,
        running = false,
        errors = 0,
        stats = { attempts = 0, casts = 0, catches = 0, best = nil },
        options = {},
    }, Fishing)

    for key, value in pairs(DEFAULTS) do
        self.options[key] = value
    end
    for key, value in pairs(options) do
        if key ~= "onCatch" and key ~= "onStatus" and key ~= "rod" and key ~= "bait"
            and key ~= "multi" then
            self.options[key] = value
        end
    end

    -- The mode is stored in lower case. "Legit" and "Blatant" from the
    -- settings are accepted as well.
    self.options.mode = tostring(self.options.mode or "legit"):lower()

    -- Optional gear modules. When present the best rod and bait are equipped
    -- before the first cast.
    self.rod = options.rod
    self.bait = options.bait

    -- Optional multi rod module. When present every rod on the bar casts a
    -- line, so one pull can bring in several fish.
    self.multi = options.multi

    -- Optional gear checker. Prevents ghost fishing and adapts timing to
    -- the equipped rod and its enchant.
    self.gear = options.gear

    local pacing = Fishing.Pacing[self.options.mode] or Fishing.Pacing.legit
    self.pacing = pacing

    self.onCatch = options.onCatch
    self.onStatus = options.onStatus
    return self
end

function Fishing:report(message)
    if self.onStatus then
        self.onStatus(message)
    end
end

function Fishing:pickSpot()
    local spots = self.api.GetSpots and self.api.GetSpots() or {}
    local low = self.options.minRarity and rarityRank(self.options.minRarity) or 0
    local high = self.options.maxRarity and rarityRank(self.options.maxRarity) or 0

    local function usable(spot)
        if not (self.options.includeSecret or not spot.secret) then
            return false
        end
        if low == 0 and high == 0 then
            return true
        end
        local value = rarityRank(spot.rarity)
        if value == 0 then
            return false
        end
        if low > 0 and value < low then
            return false
        end
        if high > 0 and value > high then
            return false
        end
        return true
    end

    if self.options.spotOrder then
        for _, wanted in ipairs(self.options.spotOrder) do
            for _, spot in ipairs(spots) do
                if spot.id == wanted and usable(spot) then
                    return spot
                end
            end
        end
        return nil
    end

    local best
    for _, spot in ipairs(spots) do
        if usable(spot) then
            if not best or (spot.price or 0) > (best.price or 0) then
                best = spot
            end
        end
    end
    return best
end

-- Equips the best rod once, before the loop starts.
function Fishing:equipRod()
    if not self.options.autoEquipRod or not self.rod then
        return false
    end
    local ok, message = self.rod:equipBest()
    if not ok then
        self:report("rod: " .. tostring(message))
    end
    return ok
end

-- Equips the best bait once, before the loop starts.
function Fishing:equipBait()
    if not self.options.autoEquipBait or not self.bait then
        return false
    end
    local ok, message = self.bait:equipBest()
    if not ok then
        self:report("bait: " .. tostring(message))
    end
    return ok
end

-- Prepares the gear for the next cast (snapshot + guard against ghost fishing).
function Fishing:prepareCast()
    if not self.gear then
        return true
    end

    local ok, message = self.gear:guard()
    if not ok then
        if message and message:find("cancelled") then
            self:report(message)
            self.gear:snapshot()
            return true
        end
        -- Something is wrong (no rod, old line still out). Try to clear it.
        local ready, readyMessage = self.gear:check()
        if not ready then
            self:report(readyMessage)
            self.gear:snapshot()
            return false, readyMessage
        end
    end

    self.gear:snapshot()
    return true
end

-- Adaptive timings based on the rod and its enchant.
function Fishing:timings()
    local timings = {
        timeout = self.options.biteTimeout,
        recast = self.options.recastDelay,
        poll = nil,
    }

    if self.gear then
        local profile = self.gear:profile()
        if profile.biteTimeout then
            timings.timeout = profile.biteTimeout
        end
        if profile.recastDelay then
            timings.recast = profile.recastDelay
        end
        if profile.poll then
            timings.poll = profile.poll
        end
    end

    -- Pacing still applies in legit mode.
    if self.pacing and self.options.mode == "legit" then
        if self.pacing.recast then
            timings.recast = math.min(timings.recast, self.pacing.recast)
        end
        if self.pacing.poll and timings.poll then
            timings.poll = math.min(timings.poll, self.pacing.poll)
        end
    end

    if self.options.mode == "blatant" then
        -- Blatant mode casts as fast as possible. The gear still prevents
        -- ghost fishing, but the delay is kept minimal.
        timings.recast = math.min(timings.recast or 0.1, 0.15)
    end

    return timings
end

function Fishing:waitForBite(timeout)
    local timings = self:timings()
    timeout = timeout or timings.timeout

    local bitten = false
    local connection
    if self.api.OnBite then
        connection = self.api.OnBite(function()
            bitten = true
        end)
    end

    local poll = timings.poll or (self.pacing and self.pacing.poll or 0.25)
    local waited = 0
    while waited < timeout and not bitten do
        self.api.Wait(poll)
        waited = waited + poll
        if self.api.IsBiteReady and self.api.IsBiteReady() then
            bitten = true
        end
    end

    if connection and connection.Disconnect then
        connection:Disconnect()
    end
    return bitten
end

--[[
    useMulti()

    True when the rod bar holds more than one rod, so a single pull can
    bring in more than one fish.
]]
function Fishing:useMulti()
    if not self.options.multiPull or not self.multi then
        return false
    end
    return self.multi:capacity() > 1
end

-- Casts one line per rod on the bar.
function Fishing:castAt(spot)
    if self:useMulti() then
        local count, result = self.multi:cast(spot.id)
        if count == 0 then
            return false, result or "no rod could be cast"
        end
        self.stats.casts = self.stats.casts + count
        return true, count
    end

    local ok, err = self.api.Cast(spot.id)
    if ok then
        self.stats.casts = self.stats.casts + 1
    end
    return ok, err
end

--[[
    pull()

    Waits for a bite and returns the fish that came in. With a full rod bar
    this is a list of several fish, otherwise a single fish.
]]
function Fishing:pull(timeout)
    if self:useMulti() then
        local fish = self.multi:waitBites(timeout)
        if #fish == 0 then
            return false, {}
        end
        return true, fish
    end

    if not self:waitForBite(timeout) then
        return false, {}
    end

    local fish, haulError = self.api.Haul()
    if not fish then
        return false, {}
    end
    return true, { fish }
end

function Fishing:run()
    self.running = true
    self:equipRod()
    self:equipBait()

    if self:useMulti() then
        self.multi:equipBestSet()
    end

    if self.gear then
        self.gear:snapshot()
    end

    while self.running do
        self.stats.attempts = self.stats.attempts + 1

        if self.options.maxCasts and self.stats.attempts > self.options.maxCasts then
            self:report("cast limit reached (" .. tostring(self.stats.casts) .. ")")
            break
        end

        local spot = self:pickSpot()
        if not spot then
            self:report("no spot available")
            break
        end

        local prepOk, prepErr = self:prepareCast()
        if not prepOk then
            self.errors = self.errors + 1
            self:report(prepErr)
            if self.errors >= self.options.maxErrors then
                self:report("too many cast failures, stopping")
                break
            end
            self.api.Wait(1)
        else
            local ok, err = self:castAt(spot)
            if not ok then
                self.errors = self.errors + 1
                self:report("cast failed: " .. tostring(err))
                if self.errors >= self.options.maxErrors then
                    self:report("too many cast failures, stopping")
                    break
                end
                self.api.Wait(1)
            else
                self.errors = 0

                local timings = self:timings()
                local pulled, fishList = self:pull(timings.timeout or self.options.biteTimeout)
                if pulled and #fishList > 0 then
                    self.stats.catches = self.stats.catches + #fishList
                    local names = {}
                    for _, fish in ipairs(fishList) do
                        if not self.stats.best or (fish.price or 0) > (self.stats.best.price or 0) then
                            self.stats.best = fish
                        end
                        names[#names + 1] = tostring(fish.name) .. " (" .. tostring(fish.rarity) .. ")"
                        if self.onCatch then
                            self.onCatch(fish)
                        end
                    end

                    if #fishList > 1 then
                        -- One pull, several fish.
                        self:report(string.format(
                            "pulled %d fish at once: %s",
                            #fishList,
                            table.concat(names, ", ")
                        ))
                    else
                        self:report("caught " .. tostring(names[1]))
                    end

                    if self.options.stopOnRarity then
                        for _, fish in ipairs(fishList) do
                            if fish.rarity == self.options.stopOnRarity then
                                self:report("stopping after " .. tostring(self.options.stopOnRarity))
                                self.running = false
                                break
                            end
                        end
                    end
                else
                    self:report("bite timeout at " .. tostring(spot.name))
                    if self.api.CancelCast then
                        self.api.CancelCast()
                    end
                end

                local delay = timings.recast or self.options.recastDelay
                self.api.Wait(delay)
            end
        end
    end

    self.running = false
    return self.stats
end

-- Runs the loop synchronously. Handy for tests and for scripted sessions.
function Fishing:start()
    if self.running then
        return false, "already running"
    end
    return self:run()
end

-- Runs the loop in a background task when the host provides one.
function Fishing:spawn()
    if self.running then
        return false, "already running"
    end
    if type(task) == "table" and task.spawn then
        self.running = true
        task.spawn(function()
            self:run()
        end)
        return true
    end
    return self:start()
end

function Fishing:stop()
    self.running = false
    return true
end

return Fishing

end)()

__tyalin_modules["auto_sell"] = (function()
--[[
    TyaLin auto sell module.

    Sells the inventory when it grows past a limit or when it holds a fish
    inside the configured rarity range. Uses the same injected API as the
    other modules, so no remotes are referenced here.

    Rarity range: the default window is Uncommon up to Forgotten. A fish
    outside that window is only sold when the inventory limit is reached,
    because then the whole bag has to go.

    API contract:
        api.GetInventory()  -> { { id, name, rarity, price } }
        api.Sell(ids)       -> soldCount, money
                               (ids is optional; when given, only those fish
                               are sold. Implementations may ignore it.)
]]

local AutoSell = {}
AutoSell.__index = AutoSell

-- Used when the shared rarity module is not bundled next to this file.
AutoSell.RarityLadder = {
    "Common", "Uncommon", "Rare", "Epic", "Legendary",
    "Mythic", "Secret", "Forgotten",
}

local function rarityModule()
    local registry = rawget(_G, "__tyalin_modules")
    if type(registry) == "table" and type(registry.rarities) == "table" then
        return registry.rarities
    end
    return nil
end

local function rank(name)
    local module = rarityModule()
    if module then
        return module.Rank(name)
    end
    for index, entry in ipairs(AutoSell.RarityLadder) do
        if entry == name then
            return index
        end
    end
    return 0
end

function AutoSell.new(api, options)
    assert(type(api) == "table", "AutoSell.new requires an api table")
    options = options or {}

    local self = setmetatable({
        api = api,
        options = {
            enabled = options.enabled ~= false,
            minRarity = options.minRarity or "Uncommon",
            maxRarity = options.maxRarity or "Forgotten",
            maxInventory = options.maxInventory or 10,
        },
        stats = { sold = 0, money = 0, lastSold = {} },
    }, AutoSell)

    self.onStatus = options.onStatus
    return self
end

function AutoSell:report(message)
    if self.onStatus then
        self.onStatus(message)
    end
end

-- The rarity names this seller is allowed to sell.
function AutoSell:sellableRarities()
    local module = rarityModule()
    if module then
        return module.List(self.options.minRarity, self.options.maxRarity)
    end

    local list = {}
    local low = rank(self.options.minRarity)
    local high = rank(self.options.maxRarity)
    for index, name in ipairs(AutoSell.RarityLadder) do
        if index >= low and index <= high then
            list[#list + 1] = name
        end
    end
    return list
end

function AutoSell:rangeText()
    return tostring(self.options.minRarity) .. " - " .. tostring(self.options.maxRarity)
end

-- Fish inside the rarity window.
function AutoSell:candidates(inventory)
    inventory = inventory or (self.api.GetInventory and self.api.GetInventory()) or {}
    local low = rank(self.options.minRarity)
    local high = rank(self.options.maxRarity)
    local list = {}

    for _, fish in ipairs(inventory) do
        local value = rank(fish.rarity)
        if value >= low and value <= high then
            list[#list + 1] = fish
        end
    end
    return list
end

function AutoSell:shouldSell()
    if not self.options.enabled then
        return false
    end

    local inventory = self.api.GetInventory and self.api.GetInventory() or {}
    if #inventory >= self.options.maxInventory then
        return true
    end

    return #self:candidates(inventory) > 0
end

function AutoSell:tick()
    if not self:shouldSell() then
        return false, "nothing to sell"
    end

    local inventory = self.api.GetInventory and self.api.GetInventory() or {}
    local limitHit = #inventory >= self.options.maxInventory
    local picked = self:candidates(inventory)

    local ids = {}
    for _, fish in ipairs(picked) do
        ids[#ids + 1] = fish.id
    end

    local count, money
    if limitHit or #ids == 0 then
        -- The bag is full: everything goes, including the fish outside the
        -- rarity window.
        count, money = self.api.Sell()
    else
        local ok, soldCount, soldMoney = pcall(self.api.Sell, ids)
        if not ok then
            -- An implementation that does not accept a selection still works.
            count, money = self.api.Sell()
        else
            count, money = soldCount, soldMoney
        end
    end

    if not count or count == 0 then
        return false, "sell rejected"
    end

    self.stats.sold = self.stats.sold + count
    self.stats.money = self.stats.money + (money or 0)
    self.stats.lastSold = picked

    local message = string.format(
        "sold %d fish for %d (%s)",
        count,
        money or 0,
        self:rangeText()
    )
    self:report(message)
    return true, message
end

return AutoSell

end)()

__tyalin_modules["teleport"] = (function()
--[[
    TyaLin teleport module.

    Walks a list of waypoints through the injected API. The module only
    deals with coordinates, so it can drive any movement implementation.

    Four target kinds are supported and selected with the "target" option:
        spots   -> api.GetSpots()
        npcs    -> api.GetNPCs()
        islands -> api.GetIslands()
        players -> api.GetPlayers()

    Every getter is optional. A kind whose getter is missing is reported and
    skipped instead of raising an error.

    API contract:
        api.GetSpots()   -> { { id, name, rarity, price, secret, position } }
        api.GetNPCs()    -> { { id, name, position } }
        api.GetIslands() -> { { id, name, rarity, price, position } }
        api.GetPlayers() -> { { id, name, position } }
        api.MoveTo(position) -> ok, error
        api.Wait(seconds)    -> waits
        api.GetCharacter()   -> character (optional)
        api.GetBoat()        -> boat model (optional)
        api.SitBoat()        -> places player in boat (optional)
        api.UnequipTools()   -> unequips tools if needed (optional)
        api.ForceFloat()     -> enables float/sea level lock (optional)
        api.StopMovement()   -> stops velocity (optional)
]]

local Teleport = {}
Teleport.__index = Teleport

local RARITY_FALLBACK = {
    "Common", "Uncommon", "Rare", "Epic", "Legendary",
    "Mythic", "Secret", "Forgotten",
}

local function rarityRank(name)
    local registry = rawget(_G, "__tyalin_modules")
    local module = registry and registry.rarities
    if type(module) == "table" and type(module.Rank) == "function" then
        return module.Rank(name)
    end
    for index, entry in ipairs(RARITY_FALLBACK) do
        if entry == name then
            return index
        end
    end
    return 0
end

local function locationsModule()
    local registry = rawget(_G, "__tyalin_modules")
    if type(registry) == "table" and type(registry.locations) == "table" then
        return registry.locations
    end
    return nil
end

Teleport.Targets = { "spots", "npcs", "islands", "players" }

local GETTERS = {
    spots = "GetSpots",
    npcs = "GetNPCs",
    islands = "GetIslands",
    players = "GetPlayers",
}

function Teleport.new(api, options)
    assert(type(api) == "table", "Teleport.new requires an api table")
    options = options or {}

    local self = setmetatable({
        api = api,
        options = {
            settleTime = options.settleTime or 0.3,
            order = options.order or "price",
            target = options.target or "spots",
            includeSecret = options.includeSecret or false,
            minRarity = options.minRarity,
            maxRarity = options.maxRarity,
            includePlayers = options.includePlayers ~= false,
            useBoat = options.useBoat ~= false,
            floatOnWater = options.floatOnWater ~= false,
            forceFloat = options.forceFloat ~= false,
            goToPlayer = options.goToPlayer or false,
        },
        visited = {},
    }, Teleport)

    self.onStatus = options.onStatus
    return self
end

function Teleport:report(message)
    if self.onStatus then
        self.onStatus(message)
    end
end

--[[
    mergeWithLocations(list, kind)

    Fills missing positions from the bundled location database.
]]
function Teleport:mergeWithLocations(list, kind)
    local locations = locationsModule()
    if not locations or type(list) ~= "table" then
        return list
    end

    local out = {}
    for _, entry in ipairs(list) do
        if type(entry) == "table" and not entry.position then
            local found = locations.Get(kind, entry.name) or locations.Get(kind, entry.id)
            if found and found.position then
                local copy = {}
                for key, value in pairs(entry) do
                    copy[key] = value
                end
                copy.position = found.position
                entry = copy
            end
        end
        out[#out + 1] = entry
    end
    return out
end

--[[
    findFallback(kind, name)

    Looks up in the bundled database even if the API does not return the list.
]]
function Teleport:findFallback(kind, name)
    local locations = locationsModule()
    if not locations then
        return nil
    end
    return locations.Get(kind, name)
end

-- The raw list of entries for the configured target kind.
function Teleport:entries()
    local getter = GETTERS[self.options.target]
    if not getter then
        return nil, "unknown target: " .. tostring(self.options.target)
    end

    local list
    if type(self.api[getter]) == "function" then
        local ok, result = pcall(self.api[getter])
        if ok and type(result) == "table" then
            list = result
        end
    end

    if not list then
        local locations = locationsModule()
        if locations then
            local kind = self.options.target
            if kind == "spots" then
                list = locations.List("spots")
            elseif kind == "npcs" then
                list = locations.List("npcs")
            elseif kind == "islands" then
                list = locations.List("islands")
            elseif kind == "players" then
                list = locations.List("players")
            end
        end
    end

    if not list then
        return nil, "this game does not expose " .. self.options.target
    end

    list = self:mergeWithLocations(list, self.options.target)
    return list
end

function Teleport:waypoints()
    local list, problem = self:entries()
    if not list then
        self:report(problem)
        return {}
    end

    local low = self.options.minRarity and rarityRank(self.options.minRarity) or 0
    local high = self.options.maxRarity and rarityRank(self.options.maxRarity) or 0
    local filtered = {}

    for _, entry in ipairs(list) do
        local keep = true

        if self.options.includeSecret == false and entry.secret then
            keep = false
        end
        if self.options.target == "players" and self.options.includePlayers == false then
            keep = false
        end
        if keep and (low > 0 or high > 0) then
            local value = rarityRank(entry.rarity)
            if value == 0 then
                keep = false
            elseif low > 0 and value < low then
                keep = false
            elseif high > 0 and value > high then
                keep = false
            end
        end
        if keep and not entry.position then
            keep = false
        end

        if keep then
            filtered[#filtered + 1] = entry
        end
    end

    if self.options.order == "price" then
        table.sort(filtered, function(a, b)
            return (a.price or 0) > (b.price or 0)
        end)
    elseif self.options.order == "rarity" then
        table.sort(filtered, function(a, b)
            return rarityRank(a.rarity) > rarityRank(b.rarity)
        end)
    elseif self.options.order == "name" then
        table.sort(filtered, function(a, b)
            return tostring(a.name or a.id) < tostring(b.name or b.id)
        end)
    else
        table.sort(filtered, function(a, b)
            return tostring(a.id) < tostring(b.id)
        end)
    end

    return filtered
end

--[[
    prepareForFishing()

    Prepares to fish at the destination. For islands and event spots the
    player needs to be on water or in the boat; some locations are over
    water (Megalodon hunt, etc). The module asks the adapter to do the
    right thing if it can, otherwise it just reports.
]]
function Teleport:prepareForFishing()
    if self.options.useBoat and type(self.api.SitBoat) == "function" then
        pcall(self.api.SitBoat)
    end
    if self.options.unequip and type(self.api.UnequipTools) == "function" then
        pcall(self.api.UnequipTools)
    end
    if self.options.forceFloat and type(self.api.ForceFloat) == "function" then
        pcall(self.api.ForceFloat)
        return
    end
    if self.options.floatOnWater and type(self.api.SetFloating) == "function" then
        pcall(self.api.SetFloating, true)
        return
    end
    if self.options.floatOnWater and type(self.api.SetStateEnabled) == "function" then
        pcall(self.api.SetStateEnabled, Enum.HumanoidStateType.Swimming, true)
    end
end

function Teleport:visit(entry)
    if not entry.position then
        self:report("no position for " .. tostring(entry.id))
        return false
    end

    if type(self.api.StopMovement) == "function" then
        pcall(self.api.StopMovement)
    end

    local ok, err = self.api.MoveTo(entry.position)
    if not ok then
        self:report("move failed: " .. tostring(err))
        return false
    end

    if self.api.Wait then
        self.api.Wait(self.options.settleTime)
    end

    -- Get ready to fish at the spot (boat/float).
    self:prepareForFishing()
    if self.api.Wait then
        self.api.Wait(0.2)
    end

    self.visited[#self.visited + 1] = entry.id
    self:report("arrived at " .. tostring(entry.name or entry.id))
    return true
end

function Teleport:run()
    local visited = {}
    for _, entry in ipairs(self:waypoints()) do
        if self:visit(entry) then
            visited[entry.id] = true
        end
    end
    return visited
end

-- Jumps straight to one named entry, without walking the whole list.
function Teleport:goTo(name)
    if not name or name == "" then
        return false, "no target given"
    end

    local wanted = tostring(name):lower()
    local list, problem = self:entries()
    if list then
        for _, entry in ipairs(list) do
            local label = tostring(entry.name or entry.id):lower()
            if label == wanted or tostring(entry.id):lower() == wanted then
                if self:visit(entry) then
                    return true, tostring(entry.name or entry.id)
                end
                return false, "move failed"
            end
        end
    end

    -- Fall back to the bundled database (works even if the API does not
    -- expose the list).
    local locations = locationsModule()
    if locations then
        for _, kind in ipairs({ "spots", "npcs", "islands", "players" }) do
            if self.options.target == kind or self.options.target == nil or self.options.target == "" then
                local entry = locations.Get(kind, name)
                if entry and entry.position then
                    if self:visit(entry) then
                        return true, entry.name
                    end
                    return false, "move failed"
                end
            end
        end
        for _, kind in ipairs({ "spots", "npcs", "islands", "players" }) do
            local entry = locations.Get(kind, name)
            if entry and entry.position then
                if self:visit(entry) then
                    return true, entry.name
                end
                return false, "move failed"
            end
        end
    end

    if problem then
        self:report(problem)
    end
    return false, "no target named " .. tostring(name)
end

-- Teleport straight to another player's position.
function Teleport:toPlayer(playerName)
    self.options.target = "players"
    self.options.goToPlayer = true
    local ok, result = self:goTo(playerName)
    if ok then
        self:prepareForFishing()
    end
    return ok, result
end

return Teleport

end)()

_G.__tyalin_modules = __tyalin_modules

--[[
    TyaLin — Fish It Hub
    Version: 1.1.0
    Readable source. No hidden HTTP requests or game remotes.

    Gameplay automation is not implemented in this release. The GUI can be
    driven by an adapter injected by the host (see resolveAdapter below);
    without an adapter the buttons only change UI state.
]]

local VERSION = "1.1.0"
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
if not player then
    warn("[TyaLin] LocalPlayer is unavailable.")
    return
end

-- Avoid duplicate windows if the script is reloaded.
local playerGui = player:FindFirstChildOfClass("PlayerGui")
if playerGui and playerGui:FindFirstChild("TyaLinUI") then
    playerGui.TyaLinUI:Destroy()
end

-- Modules that were bundled into the payload are available here. Without a
-- bundle the hub still runs, it just reports the feature as unavailable.
local function loadBundledModule(name)
    local registry = rawget(_G, "__tyalin_modules")
    if type(registry) == "table" and type(registry[name]) == "table" then
        return registry[name]
    end
    return nil
end

local ConfigModule = loadBundledModule("config")
local RaritiesModule = loadBundledModule("rarities")

-- Fallback used when the hub runs outside a bundle. The bundled config
-- module is the authoritative schema; this copy only keeps the plain
-- TyaLin.lua usable on its own.
local FALLBACK_DEFAULTS = {
    AutoFishing = false,
    AutoSell = false,
    Notifications = true,
    Theme = "Minimal",
    LicenseKey = "",
    LicenseEndpoint = "",
    LicenseRequired = false,
    Mode = "Legit",
    MinRarity = "Uncommon",
    MaxRarity = "Forgotten",
    TeleportTarget = "Spots",
    IncludeSecret = false,
    AutoEquipRod = true,
    AutoEquipBait = true,
    InventoryLimit = 10,
    RecastDelay = 0.4,
    BiteTimeout = 20,
    TargetIsland = "",
    TargetNPC = "",
}

local FALLBACK_RARITIES = {
    "Common", "Uncommon", "Rare", "Epic", "Legendary",
    "Mythic", "Secret", "Forgotten",
}

local function defaultSettings()
    if ConfigModule and type(ConfigModule.defaults) == "function" then
        return ConfigModule.defaults()
    end
    local copy = {}
    for key, value in pairs(FALLBACK_DEFAULTS) do
        copy[key] = value
    end
    return copy
end

local function sanitizeSettings(raw)
    if ConfigModule and type(ConfigModule.sanitize) == "function" then
        return ConfigModule.sanitize(raw)
    end

    local settings = defaultSettings()
    local problems = {}
    if type(raw) ~= "table" then
        return settings, { "config was not a table" }
    end
    for key, value in pairs(raw) do
        local fallback = FALLBACK_DEFAULTS[key]
        if fallback == nil then
            problems[#problems + 1] = "unknown setting '" .. tostring(key) .. "' was dropped"
        elseif type(value) ~= type(fallback) then
            problems[#problems + 1] = key .. " has the wrong type"
        else
            settings[key] = value
        end
    end
    return settings, problems
end

local function rarityLadder()
    if RaritiesModule and type(RaritiesModule.Order) == "table" then
        return RaritiesModule.Order
    end
    return FALLBACK_RARITIES
end

local State = defaultSettings()

local CONFIG_PATH = "TyaLin/config.json"

-- Optional adapter. A host that is allowed to automate a game can inject a
-- table before this script runs; the GUI then calls that adapter instead of
-- only flipping UI state. No game specific knowledge lives in this file.
--
-- Adapter contract (every extra argument is optional, so an adapter written
-- for an older release keeps working):
--   name                     -> label shown in the UI
--   startAutoFishing(report, options) -> ok, message, stillRunning
--   stopAutoFishing(report)            -> ok, message
--   autoSell(report, options)           -> ok, message
--   teleport(report, target)            -> ok, message
--   equipRod(report)                    -> ok, message
--   equipBait(report)                   -> ok, message
--
-- options carries the settings that change the behaviour: Mode, MinRarity,
-- MaxRarity, IncludeSecret, AutoEquipRod, AutoEquipBait, InventoryLimit,
-- RecastDelay and BiteTimeout.
local function resolveAdapter()
    local env = _G
    if type(getgenv) == "function" then
        local ok, shared = pcall(getgenv)
        if ok and type(shared) == "table" then
            env = shared
        end
    end

    local candidate = env.TyaLinAdapter
    if type(candidate) == "function" then
        local ok, result = pcall(candidate)
        candidate = ok and result or nil
    end

    if type(candidate) == "table" then
        return candidate
    end
    return nil
end

local Adapter = resolveAdapter()
local ADAPTER_NAME = Adapter and (tostring(Adapter.name or "connected adapter")) or nil

-- Executor file APIs, when they exist, are used to persist the license key
-- and the device id.
local function executorStorage()
    if type(readfile) ~= "function" or type(writefile) ~= "function" then
        return nil
    end
    return {
        read = function(path)
            if type(isfile) == "function" and not isfile(path) then
                return nil
            end
            return readfile(path)
        end,
        write = function(path, value)
            if type(makefolder) == "function" then
                pcall(makefolder, "TyaLin")
            end
            writefile(path, value)
        end,
    }
end

-- A random tag stored next to the config. It is not a hardware fingerprint:
-- it identifies this installation, not the device.
local function resolveDeviceId(storage)
    if storage then
        local ok, value = pcall(storage.read, "TyaLin/device.txt")
        if ok and type(value) == "string" and value ~= "" then
            return value
        end

        local generated = tostring(os.time()) .. "-" .. tostring(math.random(1, 1000000))
        if type(HttpService) == "table" and type(HttpService.GenerateGUID) == "function" then
            local guidOk, guid = pcall(HttpService.GenerateGUID, HttpService, false)
            if guidOk and type(guid) == "string" and guid ~= "" then
                generated = guid
            end
        end
        pcall(storage.write, "TyaLin/device.txt", generated)
        return generated
    end
    return "user-" .. tostring(player.UserId)
end

local function safeNotify(statusLabel, message)
    if statusLabel then
        statusLabel.Text = "Status: " .. message
    end
    if State.Notifications then
        print("[TyaLin] " .. message)
    end
end

-- Every setting is written, so a repaired or reset config is a complete
-- file instead of a partial one.
local function settingsPayload()
    local payload = {}
    for key in pairs(defaultSettings()) do
        payload[key] = State[key]
    end
    return payload
end

local function saveConfig()
    if type(writefile) ~= "function" or type(makefolder) ~= "function" then
        return false, "File APIs unavailable; config cannot persist."
    end

    local ok, err = pcall(function()
        if type(isfolder) == "function" and not isfolder("TyaLin") then
            makefolder("TyaLin")
        elseif type(isfolder) ~= "function" then
            pcall(makefolder, "TyaLin")
        end

        writefile(CONFIG_PATH, HttpService:JSONEncode(settingsPayload()))
    end)

    return ok, err
end

--[[
    loadConfig() -> ok, message

    A config that cannot be parsed, or that holds values the schema rejects,
    is repaired instead of blocking the hub. The repaired file is written back
    so the next start is clean.
]]
local function loadConfig()
    if type(readfile) ~= "function" or type(isfile) ~= "function" then
        return false, "File APIs unavailable; using session defaults."
    end

    if not isfile(CONFIG_PATH) then
        return true, "No saved config; defaults in use."
    end

    local readOk, raw = pcall(function()
        return HttpService:JSONDecode(readfile(CONFIG_PATH))
    end)

    if not readOk or type(raw) ~= "table" then
        -- A broken file is replaced by the defaults.
        State = defaultSettings()
        saveConfig()
        return true, "Config was unreadable and has been reset to defaults."
    end

    local settings, problems = sanitizeSettings(raw)
    State = settings

    if #problems > 0 then
        saveConfig()
        return true, "Config repaired: " .. tostring(#problems) .. " value(s) reset to defaults."
    end

    return true, "Config loaded."
end

-- Restores every setting to its default and stores the result.
local function resetConfig()
    State = defaultSettings()
    local ok, err = saveConfig()
    if not ok then
        return false, tostring(err)
    end
    return true, "Config reset to defaults."
end

-- Load the saved config so the license key and endpoint are known before
-- anything else runs.
local configMessage = nil
pcall(function()
    local ok, message = loadConfig()
    configMessage = message
end)

local STORAGE = executorStorage()
local LicenseModule = loadBundledModule("license")
local license = nil

if LicenseModule then
    license = LicenseModule.new({
        endpoint = State.LicenseEndpoint,
        userId = tostring(player.UserId),
        deviceId = resolveDeviceId(STORAGE),
        storage = STORAGE,
    })
end

-- Try to auto-connect to the game if no adapter was injected.
if not Adapter then
    local AutoBridge = loadBundledModule("auto_bridge")
    local FishingMod = loadBundledModule("fishing")
    local MultiRodMod = loadBundledModule("multi_rod")
    local GearMod = loadBundledModule("gear")
    local RodMod = loadBundledModule("rod")
    local BaitMod = loadBundledModule("bait")
    local AutoSellMod = loadBundledModule("auto_sell")
    local TeleportMod = loadBundledModule("teleport")
    local LocationsMod = loadBundledModule("locations")

    if AutoBridge and FishingMod then
        local ok, bridged = pcall(AutoBridge.build, {
            Fishing = FishingMod,
            MultiRod = MultiRodMod,
            Gear = GearMod,
            Rod = RodMod,
            Bait = BaitMod,
            AutoSell = AutoSellMod,
            Teleport = TeleportMod,
            Locations = LocationsMod,
            name = "game-bridge",
        })
        if ok and type(bridged) == "table" then
            Adapter = bridged
            ADAPTER_NAME = tostring(Adapter.name or "game-bridge")
        end
    end
end

-- Minimal GUI
local gui = Instance.new("ScreenGui")
gui.Name = "TyaLinUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local guiParent = player:FindFirstChildOfClass("PlayerGui")
if not guiParent then
    guiParent = player:WaitForChild("PlayerGui")
end
gui.Parent = guiParent

local COLORS = {
    Background = Color3.fromRGB(24, 24, 29),
    Panel = Color3.fromRGB(34, 34, 41),
    Button = Color3.fromRGB(46, 46, 55),
    Accent = Color3.fromRGB(153, 130, 255),
    Text = Color3.fromRGB(242, 242, 247),
    Muted = Color3.fromRGB(171, 171, 185),
    Border = Color3.fromRGB(68, 68, 80),
}

local WINDOW_WIDTH = 380
local WINDOW_HEIGHT = 392
local COLLAPSED_SIZE = 46

local function addCorner(instance, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 8)
    corner.Parent = instance
    return corner
end

local function addStroke(instance)
    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.Border
    stroke.Thickness = 1
    stroke.Parent = instance
    return stroke
end

local window = Instance.new("Frame")
window.Name = "Main"
window.Size = UDim2.fromOffset(WINDOW_WIDTH, WINDOW_HEIGHT)
window.Position = UDim2.new(0.5, -190, 0.5, -196)
window.BackgroundColor3 = COLORS.Background
window.BorderSizePixel = 0
window.ClipsDescendants = true
window.Parent = gui
addCorner(window, 12)
addStroke(window)

local topbar = Instance.new("Frame")
topbar.Name = "Topbar"
topbar.Size = UDim2.new(1, 0, 0, 52)
topbar.BackgroundColor3 = COLORS.Panel
topbar.BorderSizePixel = 0
topbar.Parent = window
addCorner(topbar, 12)

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(16, 5)
title.Size = UDim2.new(1, -110, 0, 25)
title.Font = Enum.Font.GothamBold
title.Text = "TyaLin"
title.TextSize = 17
title.TextColor3 = COLORS.Text
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = topbar

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.fromOffset(16, 28)
subtitle.Size = UDim2.new(1, -110, 0, 16)
subtitle.Font = Enum.Font.Gotham
subtitle.Text = "FISH IT  •  v" .. VERSION
subtitle.TextSize = 10
subtitle.TextColor3 = COLORS.Muted
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = topbar

-- The topbar buttons are square icons so the bar never stretches.
local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.fromOffset(28, 28)
closeButton.Position = UDim2.new(1, -34, 0, 12)
closeButton.BackgroundColor3 = COLORS.Button
closeButton.Text = "X"
closeButton.TextColor3 = COLORS.Text
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 13
closeButton.AutoButtonColor = true
closeButton.Parent = topbar
addCorner(closeButton, 7)

local minimizeButton = Instance.new("TextButton")
minimizeButton.Name = "MinimizeButton"
minimizeButton.Size = UDim2.fromOffset(28, 28)
minimizeButton.Position = UDim2.new(1, -66, 0, 12)
minimizeButton.BackgroundColor3 = COLORS.Button
minimizeButton.Text = "-"
minimizeButton.TextColor3 = COLORS.Text
minimizeButton.Font = Enum.Font.GothamBold
minimizeButton.TextSize = 15
minimizeButton.AutoButtonColor = true
minimizeButton.Parent = topbar
addCorner(minimizeButton, 7)

-- The collapsed window shows this icon only.
local restoreButton = Instance.new("TextButton")
restoreButton.Name = "RestoreButton"
restoreButton.Size = UDim2.fromOffset(COLLAPSED_SIZE, COLLAPSED_SIZE)
restoreButton.Position = UDim2.fromOffset(0, 0)
restoreButton.BackgroundColor3 = COLORS.Accent
restoreButton.Text = "T"
restoreButton.TextColor3 = COLORS.Text
restoreButton.Font = Enum.Font.GothamBold
restoreButton.TextSize = 18
restoreButton.AutoButtonColor = true
restoreButton.Visible = false
restoreButton.Parent = window
addCorner(restoreButton, 12)

local body = Instance.new("ScrollingFrame")
body.Name = "Body"
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.Position = UDim2.fromOffset(14, 62)
body.Size = UDim2.new(1, -28, 1, -74)
body.ScrollBarThickness = 3
body.ScrollingDirection = Enum.ScrollingDirection.Y
body.CanvasSize = UDim2.new(0, 0, 0, 0)
body.AutomaticSize = Enum.AutomaticSize.Y
body.Parent = window

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 7)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = body

local status = Instance.new("TextLabel")
status.Name = "Status"
status.LayoutOrder = 0
status.Size = UDim2.new(1, 0, 0, 34)
status.BackgroundColor3 = COLORS.Panel
status.BorderSizePixel = 0
status.Text = Adapter and ("Status: adapter ready (" .. ADAPTER_NAME .. ")")
    or "Status: UI ready; gameplay modules are inactive"
status.TextColor3 = COLORS.Muted
status.TextSize = 10
status.Font = Enum.Font.Gotham
status.TextWrapped = true
status.Parent = body
addCorner(status, 7)

local connections = {}

local function track(connection)
    if connection then
        connections[#connections + 1] = connection
    end
    return connection
end

local function makeButton(name, text, order, callback)
    local button = Instance.new("TextButton")
    button.Name = name
    button.LayoutOrder = order
    button.Size = UDim2.new(1, 0, 0, 34)
    button.BackgroundColor3 = COLORS.Button
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = COLORS.Text
    button.TextSize = 12
    button.Font = Enum.Font.GothamMedium
    button.AutoButtonColor = true
    button.Parent = body
    addCorner(button, 7)

    track(button.MouseButton1Click:Connect(function()
        local ok, err = pcall(callback, button)
        if not ok then
            warn("[TyaLin] UI callback error:", tostring(err))
            safeNotify(status, "UI action failed.")
        end
    end))
    return button
end

-- Two buttons side by side, used for the sell rarity window.
local function makeRow(name, order)
    local row = Instance.new("Frame")
    row.Name = name
    row.LayoutOrder = order
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundTransparency = 1
    row.Parent = body

    local function half(suffix, offset, text, callback)
        local button = Instance.new("TextButton")
        button.Name = name .. suffix
        button.Size = UDim2.new(0.5, -4, 0, 34)
        button.Position = UDim2.fromOffset(offset, 0)
        button.BackgroundColor3 = COLORS.Button
        button.BorderSizePixel = 0
        button.Text = text
        button.TextColor3 = COLORS.Text
        button.TextSize = 11
        button.Font = Enum.Font.GothamMedium
        button.AutoButtonColor = true
        button.Parent = row
        addCorner(button, 7)
        track(button.MouseButton1Click:Connect(function()
            local ok, err = pcall(callback, button)
            if not ok then
                warn("[TyaLin] UI callback error:", tostring(err))
                safeNotify(status, "UI action failed.")
            end
        end))
        return button
    end

    return half, row
end

local autoFishingButton
local autoSellButton
local notificationButton
local teleportButton
local teleportTargetButton
local licenseButton
local rodButton
local baitButton
local modeButton
local minRarityButton
local maxRarityButton

local function autoSuffix()
    return Adapter and ("ON (" .. ADAPTER_NAME .. ")") or "ON (not connected)"
end

local function updateToggleLabels()
    if autoFishingButton then
        autoFishingButton.Text = "Auto Fishing: " ..
            (State.AutoFishing and autoSuffix() or "OFF")
    end
    if autoSellButton then
        autoSellButton.Text = "Auto Sell: " ..
            (State.AutoSell and autoSuffix() or "OFF")
    end
    if notificationButton then
        notificationButton.Text = "Notifications: " ..
            (State.Notifications and "ON" or "OFF")
    end
    if teleportTargetButton then
        teleportTargetButton.Text = "Teleport To: " .. tostring(State.TeleportTarget)
    end
    if modeButton then
        modeButton.Text = "Mode: " .. tostring(State.Mode)
    end
    if minRarityButton then
        minRarityButton.Text = "Sell Min: " .. tostring(State.MinRarity)
    end
    if maxRarityButton then
        maxRarityButton.Text = "Sell Max: " .. tostring(State.MaxRarity)
    end
    if rodButton then
        rodButton.Text = "Equip Best Rod: " .. (State.AutoEquipRod and "ON" or "OFF")
    end
    if baitButton then
        baitButton.Text = "Equip Best Bait: " .. (State.AutoEquipBait and "ON" or "OFF")
    end
    if subtitle then
        subtitle.Text = "FISH IT  •  v" .. VERSION .. "  •  " .. tostring(State.Mode):upper()
    end
end

local function updateLicenseLabel()
    if not licenseButton then
        return
    end
    if not license then
        licenseButton.Text = "License: not configured"
        return
    end
    if license:isValid() then
        local plan = license.state.plan and (" (" .. tostring(license.state.plan) .. ")") or ""
        licenseButton.Text = "License: valid" .. plan
    elseif State.LicenseKey ~= "" then
        licenseButton.Text = "License: invalid"
    else
        licenseButton.Text = "License: not configured"
    end
end

-- The options the adapter receives. Only the settings that change behaviour
-- are passed, so a simple adapter can ignore them.
local function adapterOptions()
    return {
        Mode = State.Mode,
        MinRarity = State.MinRarity,
        MaxRarity = State.MaxRarity,
        IncludeSecret = State.IncludeSecret,
        AutoEquipRod = State.AutoEquipRod,
        AutoEquipBait = State.AutoEquipBait,
        InventoryLimit = State.InventoryLimit,
        RecastDelay = State.RecastDelay,
        BiteTimeout = State.BiteTimeout,
        TargetIsland = State.TargetIsland,
        TargetNPC = State.TargetNPC,
    }
end

autoFishingButton = makeButton("AutoFishingButton", "Auto Fishing: OFF", 1, function()
    if State.LicenseRequired and (not license or not license:isValid()) then
        safeNotify(status, "A valid license is required before auto fishing can start.")
        return
    end

    if Adapter and type(Adapter.startAutoFishing) == "function" then
        if State.AutoFishing then
            if type(Adapter.stopAutoFishing) == "function" then
                Adapter.stopAutoFishing(function(message)
                    safeNotify(status, message)
                end)
            end
            State.AutoFishing = false
            updateToggleLabels()
            safeNotify(status, "Auto Fishing stopped.")
        else
            local ok, message, running = Adapter.startAutoFishing(function(update)
                safeNotify(status, update)
            end, adapterOptions())
            if ok then
                -- running == false means the session already finished.
                State.AutoFishing = running == true
                updateToggleLabels()
                safeNotify(status, tostring(message or "Auto Fishing started."))
            else
                safeNotify(status, "Auto Fishing could not start: " .. tostring(message))
            end
        end
        return
    end

    State.AutoFishing = not State.AutoFishing
    updateToggleLabels()
    safeNotify(status, "Auto Fishing is a UI toggle only; no game action executed.")
end)

autoSellButton = makeButton("AutoSellButton", "Auto Sell: OFF", 2, function()
    if Adapter and type(Adapter.autoSell) == "function" then
        local ok, message = Adapter.autoSell(function(update)
            safeNotify(status, update)
        end, adapterOptions())
        State.AutoSell = true
        updateToggleLabels()
        if ok then
            safeNotify(status, tostring(message or "Auto sell finished."))
        else
            safeNotify(status, "Auto sell failed: " .. tostring(message))
        end
        return
    end

    State.AutoSell = not State.AutoSell
    updateToggleLabels()
    safeNotify(status, "Auto Sell is a UI toggle only; no game action executed.")
end)

-- The sell window: Uncommon up to Forgotten by default.
local half = makeRow("SellRangeRow", 3)
minRarityButton = half("Min", 0, "Sell Min: " .. tostring(State.MinRarity), function()
    local ladder = rarityLadder()
    local index = 1
    for position, name in ipairs(ladder) do
        if name == State.MinRarity then
            index = position
            break
        end
    end
    State.MinRarity = ladder[(index % #ladder) + 1]
    updateToggleLabels()
    safeNotify(status, "Sell window starts at " .. tostring(State.MinRarity) .. ".")
end)

maxRarityButton = half("Max", 0, "Sell Max: " .. tostring(State.MaxRarity), function()
    local ladder = rarityLadder()
    local index = #ladder
    for position, name in ipairs(ladder) do
        if name == State.MaxRarity then
            index = position
            break
        end
    end
    State.MaxRarity = ladder[(index % #ladder) + 1]
    updateToggleLabels()
    safeNotify(status, "Sell window ends at " .. tostring(State.MaxRarity) .. ".")
end)

teleportTargetButton = makeButton("TeleportTargetButton", "Teleport To: " .. tostring(State.TeleportTarget), 4, function()
    local targets = { "Spots", "NPCs", "Islands", "Players" }
    local index = 1
    for position, name in ipairs(targets) do
        if name == State.TeleportTarget then
            index = position
            break
        end
    end
    State.TeleportTarget = targets[(index % #targets) + 1]
    updateToggleLabels()
    safeNotify(status, "Teleport target set to " .. tostring(State.TeleportTarget) .. ".")
end)

teleportButton = makeButton("TeleportButton", "Teleport: unavailable", 5, function()
    if Adapter and type(Adapter.teleport) == "function" then
        local ok, message = Adapter.teleport(function(update)
            safeNotify(status, update)
        end, State.TeleportTarget)
        if ok then
            safeNotify(status, tostring(message or "Teleport finished."))
        else
            safeNotify(status, "Teleport failed: " .. tostring(message))
        end
        return
    end
    safeNotify(status, "Teleport is disabled in this foundation release.")
end)

if Adapter and type(Adapter.teleport) == "function" then
    teleportButton.Text = "Teleport: ready"
end

rodButton = makeButton("RodButton", "Equip Best Rod: " .. (State.AutoEquipRod and "ON" or "OFF"), 6, function()
    if Adapter and type(Adapter.equipRod) == "function" then
        local ok, message = Adapter.equipRod(function(update)
            safeNotify(status, update)
        end)
        if ok then
            State.AutoEquipRod = true
            updateToggleLabels()
            safeNotify(status, tostring(message or "Best rod equipped."))
        else
            safeNotify(status, "Rod equip failed: " .. tostring(message))
        end
        return
    end

    State.AutoEquipRod = not State.AutoEquipRod
    updateToggleLabels()
    safeNotify(status, "Auto equip rod is a UI toggle only; no game action executed.")
end)

baitButton = makeButton("BaitButton", "Equip Best Bait: " .. (State.AutoEquipBait and "ON" or "OFF"), 7, function()
    if Adapter and type(Adapter.equipBait) == "function" then
        local ok, message = Adapter.equipBait(function(update)
            safeNotify(status, update)
        end)
        if ok then
            State.AutoEquipBait = true
            updateToggleLabels()
            safeNotify(status, tostring(message or "Best bait equipped."))
        else
            safeNotify(status, "Bait equip failed: " .. tostring(message))
        end
        return
    end

    State.AutoEquipBait = not State.AutoEquipBait
    updateToggleLabels()
    safeNotify(status, "Auto equip bait is a UI toggle only; no game action executed.")
end)

modeButton = makeButton("ModeButton", "Mode: " .. tostring(State.Mode), 8, function()
    State.Mode = (State.Mode == "Legit") and "Blatant" or "Legit"
    updateToggleLabels()
    safeNotify(status, "Mode set to " .. tostring(State.Mode) .. ".")
end)

makeButton("SaveConfigButton", "Save Config", 9, function()
    local ok, err = saveConfig()
    if ok then
        safeNotify(status, "Config saved.")
    else
        warn("[TyaLin] Save config:", tostring(err))
        safeNotify(status, "Config could not be saved.")
    end
end)

makeButton("LoadConfigButton", "Load Config", 10, function()
    local ok, err = loadConfig()
    updateToggleLabels()
    updateLicenseLabel()
    if ok then
        safeNotify(status, tostring(err))
    else
        safeNotify(status, tostring(err))
    end
end)

makeButton("ResetConfigButton", "Reset Config", 11, function()
    local ok, message = resetConfig()
    updateToggleLabels()
    updateLicenseLabel()
    if ok then
        safeNotify(status, tostring(message))
    else
        safeNotify(status, "Config could not be reset: " .. tostring(message))
    end
end)

notificationButton = makeButton("NotificationsButton", "Notifications: ON", 12, function()
    State.Notifications = not State.Notifications
    updateToggleLabels()
    safeNotify(status, "Notification preference changed.")
end)

licenseButton = makeButton("LicenseButton", "License: not configured", 13, function()
    if not license then
        safeNotify(status, "No license module is bundled in this build.")
        return
    end

    if State.LicenseEndpoint == "" then
        safeNotify(status, "No license server is configured.")
        return
    end

    local key = State.LicenseKey
    if (not key or key == "") and type(prompt) == "function" then
        local ok, entered = pcall(prompt, "TyaLin", "Enter your license key")
        if ok and type(entered) == "string" then
            key = entered
        end
    end

    if not key or key == "" then
        safeNotify(status, "No license key given.")
        return
    end

    local valid, message = license:verify(key)
    if valid then
        State.LicenseKey = key
        updateLicenseLabel()
        safeNotify(status, "License accepted: " .. tostring(message))
    else
        safeNotify(status, "License rejected: " .. tostring(message))
    end
end)

updateToggleLabels()
updateLicenseLabel()

-- A stored license key is verified once at startup.
if license and State.LicenseKey ~= "" then
    local function verifyStored()
        pcall(function()
            license:verify(State.LicenseKey)
        end)
        updateLicenseLabel()
    end
    if type(task) == "table" and task.spawn then
        task.spawn(verifyStored)
    else
        verifyStored()
    end
end

-- Drag window with mouse or touch.
local dragging = false
local dragInput
local dragStart
local startPosition

track(topbar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPosition = window.Position
        dragInput = input
    end
end))

track(UserInputService.InputChanged:Connect(function(input)
    if dragging and (
        input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    ) then
        local delta = input.Position - dragStart
        window.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end))

track(UserInputService.InputEnded:Connect(function(input)
    if input == dragInput
        or input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
        dragInput = nil
    end
end))

-- Minimize collapses the window to a single icon; the icon restores it.
local minimized = false

local function setMinimized(value)
    minimized = value
    body.Visible = not value
    topbar.Visible = not value
    restoreButton.Visible = value
    window.Size = value
        and UDim2.fromOffset(COLLAPSED_SIZE, COLLAPSED_SIZE)
        or UDim2.fromOffset(WINDOW_WIDTH, WINDOW_HEIGHT)
end

track(minimizeButton.MouseButton1Click:Connect(function()
    setMinimized(true)
end))

track(restoreButton.MouseButton1Click:Connect(function()
    setMinimized(false)
end))

--[[
    shutdown() stops everything the hub started and removes the window.

    The close button calls it, and the same function is exposed as
    TyaLinStop so a host can stop the hub without clicking.
]]
local closed = false

local function shutdown()
    if closed then
        return
    end
    closed = true

    if State.AutoFishing and Adapter and type(Adapter.stopAutoFishing) == "function" then
        pcall(Adapter.stopAutoFishing, function() end)
    end
    State.AutoFishing = false

    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    connections = {}

    pcall(function()
        gui:Destroy()
    end)

    print("[TyaLin] closed; the script has stopped.")
end

track(closeButton.MouseButton1Click:Connect(function()
    shutdown()
end))

_G.TyaLinStop = shutdown

if Adapter then
    print("[TyaLin] v" .. VERSION .. " initialized. Adapter: " .. ADAPTER_NAME)
else
    print("[TyaLin] v" .. VERSION .. " initialized. Gameplay automation is not connected.")
end

if configMessage then
    print("[TyaLin] " .. configMessage)
end
