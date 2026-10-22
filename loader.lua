-- TyaLin transparent loader
-- Fetches the built, obfuscated payload from the public repository.
-- Run node tools/publish-payload.js to rebuild and push dist/payload.lua.

local SCRIPT_URL =
    "https://raw.githubusercontent.com/Fajartya/TyaLin-FishIt/main/dist/payload.lua"

local function run()
    if type(loadstring) ~= "function" then
        warn("[TyaLin] loadstring is unavailable in this environment.")
        return
    end

    local ok, source = pcall(function()
        return game:HttpGet(SCRIPT_URL)
    end)

    if not ok or type(source) ~= "string" or source == "" then
        warn("[TyaLin] Could not download source. Check the URL and network.")
        return
    end

    -- Downloaded source is executed below. Review it first.
    local compileOk, chunk = pcall(loadstring, source)
    if not compileOk or type(chunk) ~= "function" then
        warn("[TyaLin] Source compilation failed:", tostring(chunk))
        return
    end

    local runOk, err = pcall(chunk)
    if not runOk then
        warn("[TyaLin] Runtime error:", tostring(err))
    end
end

run()
