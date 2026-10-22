-- TyaLin transparent loader
-- Fetches the built, obfuscated payload from the public repository.

local SCRIPT_URL = "https://raw.githubusercontent.com/Fajartya/TyaLin-FishIt/refs/heads/main/dist/payload.lua"

local function fetch()
    -- Roblox game:HttpGet
    if type(game) == "table" and type(game.HttpGet) == "function" then
        local ok, res = pcall(game.HttpGet, game, SCRIPT_URL)
        if ok and type(res) == "string" and #res > 50 then
            return res
        end
    end

    -- Synapse X
    if type(syn) == "table" and type(syn.request) == "function" then
        local ok, res = pcall(syn.request, { Url = SCRIPT_URL, Method = "GET" })
        if ok and res and type(res.Body) == "string" and #res.Body > 50 then
            return res.Body
        end
    end

    -- Krnl, Fluxus, Script-Ware, etc
    if type(request) == "function" then
        local ok, res = pcall(request, { Url = SCRIPT_URL, Method = "GET" })
        if ok and res then
            if type(res.Body) == "string" and #res.Body > 50 then
                return res.Body
            end
            if type(res.body) == "string" and #res.body > 50 then
                return res.body
            end
        end
    end

    -- http_request
    if type(http_request) == "function" then
        local ok, res = pcall(http_request, { Url = SCRIPT_URL, Method = "GET" })
        if ok and res then
            if type(res.Body) == "string" and #res.Body > 50 then
                return res.Body
            end
            if type(res.body) == "string" and #res.body > 50 then
                return res.body
            end
        end
    end

    -- Arceus X / others
    if type(httpget) == "function" then
        local ok, res = pcall(httpget, SCRIPT_URL)
        if ok and type(res) == "string" and #res > 50 then
            return res
        end
    end

    return nil
end

local function run()
    if type(loadstring) ~= "function" then
        warn("[TyaLin] loadstring is unavailable in this executor.")
        return
    end

    local source = fetch()
    if not source then
        warn("[TyaLin] Failed to download payload. Try rejoining or using a different executor.")
        return
    end

    local compileOk, chunk = pcall(loadstring, source)
    if not compileOk or type(chunk) ~= "function" then
        warn("[TyaLin] Failed to compile payload:", tostring(chunk))
        return
    end

    local runOk, err = pcall(chunk)
    if not runOk then
        warn("[TyaLin] Runtime error:", tostring(err))
    end
end

run()
