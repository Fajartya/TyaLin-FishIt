-- TyaLin transparent loader
-- Fetches the built, obfuscated payload from the public repository.
--
-- Executor support:
--   Delta, Fluxus, KRNL, Script-Ware, Synapse X, Arceus X, ...
--
-- The loader only needs an HTTP function and loadstring. Both are looked up
-- at runtime, so a missing API produces a clear message instead of a stack
-- trace.

-- The canonical raw URL. The "/refs/heads/" variant is served from a
-- separate cache by raw.githubusercontent.com and can keep an old payload
-- alive for a while, so it is not used here.
local SCRIPT_URL = "https://raw.githubusercontent.com/Fajartya/TyaLin-FishIt/main/dist/payload.lua"

local function log(message)
    print("[TyaLin] " .. tostring(message))
end

-- The URL can be overridden from the executor console, which is handy when
-- the release repository moves:
--   getgenv().TyaLinPayloadUrl = "https://example.com/payload.lua"
local function resolveUrl()
    if type(getgenv) == "function" then
        local ok, shared = pcall(getgenv)
        if ok and type(shared) == "table" and type(shared.TyaLinPayloadUrl) == "string" then
            return shared.TyaLinPayloadUrl
        end
    end
    return SCRIPT_URL
end

-- Executors answer in different shapes: some return the body as a string,
-- others return a table such as
--   { Success = true, StatusCode = 200, Body = "...", Headers = {...} }
-- Both are accepted.
local function extractBody(response)
    if type(response) == "string" then
        if #response > 50 then
            return response
        end
        return nil
    end

    if type(response) == "table" then
        local body = response.Body or response.body or response.Content or response.content
        if type(body) == "string" and #body > 50 then
            return body
        end
        local code = response.StatusCode or response.status or response.status_code
        if type(code) == "number" then
            log("HTTP status " .. tostring(code))
        end
    end

    return nil
end

local function fetch(url)
    -- Roblox game:HttpGet (some executors implement it)
    if type(game) == "table" and type(game.HttpGet) == "function" then
        local ok, res = pcall(game.HttpGet, game, url)
        local body = ok and extractBody(res) or nil
        if body then
            return body
        end
    end

    -- Delta, Fluxus, KRNL, Script-Ware
    if type(request) == "function" then
        local ok, res = pcall(request, { Url = url, Method = "GET" })
        if ok then
            local body = extractBody(res)
            if body then
                return body
            end
        end
    end

    -- Synapse X
    if type(syn) == "table" and type(syn.request) == "function" then
        local ok, res = pcall(syn.request, { Url = url, Method = "GET" })
        if ok then
            local body = extractBody(res)
            if body then
                return body
            end
        end
    end

    -- http_request (Arceus X and others)
    if type(http_request) == "function" then
        local ok, res = pcall(http_request, { Url = url, Method = "GET" })
        if ok then
            local body = extractBody(res)
            if body then
                return body
            end
        end
    end

    -- httpget
    if type(httpget) == "function" then
        local ok, res = pcall(httpget, url)
        local body = ok and extractBody(res) or nil
        if body then
            return body
        end
    end

    return nil
end

local function compile(source)
    if type(loadstring) == "function" then
        local ok, chunk, err = pcall(loadstring, source)
        if ok and type(chunk) == "function" then
            return chunk
        end
        log("loadstring failed: " .. tostring(ok and err or chunk))
    end

    if type(load) == "function" then
        local ok, chunk, err = pcall(load, source, "=payload")
        if ok and type(chunk) == "function" then
            return chunk
        end
        log("load failed: " .. tostring(ok and err or chunk))
    end

    return nil
end

local function run()
    local url = resolveUrl()

    if type(loadstring) ~= "function" and type(load) ~= "function" then
        log("loadstring is unavailable in this executor.")
        return
    end

    local source = fetch(url)
    if not source then
        log("Failed to download the payload from " .. url)
        log("Check your connection, or set getgenv().TyaLinPayloadUrl to a mirror.")
        return
    end

    local chunk = compile(source)
    if not chunk then
        log("Failed to compile the payload.")
        return
    end

    local runOk, err = pcall(chunk)
    if not runOk then
        log("Runtime error: " .. tostring(err))
    end
end

run()
