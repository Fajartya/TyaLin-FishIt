-- TyaLin diagnostic
--
-- Runs the same download/compile/start steps as the loader, but shows every
-- result on screen. Use it when the menu does not appear:
--
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/Fajartya/TyaLin-FishIt/main/diag.lua"))()

local URL = "https://raw.githubusercontent.com/Fajartya/TyaLin-FishIt/main/dist/payload.lua"

local lines = {}

local gui = Instance.new("ScreenGui")
gui.Name = "TyaLinDiag"
pcall(function() gui.ResetOnSpawn = false end)
pcall(function() gui.IgnoreGuiInset = true end)

local parent
pcall(function() parent = game:GetService("CoreGui") end)
if not parent then
    pcall(function()
        local players = game:GetService("Players")
        local localPlayer = players and players.LocalPlayer
        parent = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
    end)
end
pcall(function() gui.Parent = parent end)

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.new(0, 560, 0, 420)
frame.Position = UDim2.new(0, 40, 0, 40)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
frame.BorderSizePixel = 0
pcall(function() frame.Parent = gui end)

local corner = Instance.new("UICorner")
pcall(function()
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame
end)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 30)
title.Position = UDim2.new(0, 12, 0, 10)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = Color3.fromRGB(235, 240, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "TyaLin diagnostic"
pcall(function() title.Parent = frame end)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -24, 1, -52)
scroll.Position = UDim2.new(0, 12, 0, 46)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
pcall(function()
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
end)
pcall(function() scroll.Parent = frame end)

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, 0, 0, 0)
label.BackgroundTransparency = 1
label.Font = Enum.Font.Code
label.TextSize = 13
label.TextWrapped = true
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.TextColor3 = Color3.fromRGB(200, 230, 200)
pcall(function()
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.Parent = scroll
end)

local function log(message)
    lines[#lines + 1] = tostring(message)
    pcall(function() label.Text = table.concat(lines, "\n") end)
    pcall(print, "[TyaLin diag] " .. tostring(message))
end

local function has(name)
    return type(name) == "function"
end

-- 1. what the executor gives us
log("executor      : " .. tostring(identifyexecutor and identifyexecutor() or "-"))
log("game:HttpGet  : " .. tostring(type(game and game.HttpGet)))
log("request       : " .. tostring(type(request)))
log("http_request  : " .. tostring(type(http_request)))
log("loadstring    : " .. tostring(type(loadstring)))
log("getgenv       : " .. tostring(type(getgenv)))
log("hookfunction  : " .. tostring(type(hookfunction)))
log("")

-- 2. download
local function extract(response)
    if type(response) == "string" then
        return response
    end
    if type(response) == "table" then
        local body = response.Body or response.body or response.Content or response.content
        if type(body) == "string" then
            return body, response.StatusCode or response.status or response.status_code
        end
    end
    return nil
end

local source, code, how
if type(game) == "table" and type(game.HttpGet) == "function" then
    local ok, response = pcall(game.HttpGet, game, URL)
    if ok then
        source, code = extract(response)
        how = "game:HttpGet"
    else
        log("game:HttpGet error: " .. tostring(response))
    end
end

if not source and type(request) == "function" then
    local ok, response = pcall(request, { Url = URL, Method = "GET" })
    if ok then
        source, code = extract(response)
        how = "request"
    else
        log("request error: " .. tostring(response))
    end
end

if not source and type(http_request) == "function" then
    local ok, response = pcall(http_request, { Url = URL, Method = "GET" })
    if ok then
        source, code = extract(response)
        how = "http_request"
    end
end

if not source then
    log("download      : FAILED")
    return
end

log("download      : ok via " .. tostring(how) .. " (status " .. tostring(code or "-") .. ")")
log("payload bytes : " .. tostring(#source))
log("payload start : " .. tostring(string.sub(source, 1, 60)))

if #source < 100 then
    log("the response is too small, probably an error page")
    return
end

-- 3. compile
local chunk, compileError
if has(loadstring) then
    local ok, result, err = pcall(loadstring, source)
    if ok and type(result) == "function" then
        chunk = result
    else
        compileError = tostring(ok and err or result)
    end
end

if not chunk and has(load) then
    local ok, result, err = pcall(load, source, "=payload")
    if ok and type(result) == "function" then
        chunk = result
    else
        compileError = compileError or tostring(ok and err or result)
    end
end

if not chunk then
    log("compile       : FAILED")
    log(tostring(compileError))
    return
end

log("compile       : ok")
log("")

-- 4. run it and say why it stopped
log("starting the hub...")
local ok, err = pcall(chunk)
if not ok then
    log("runtime error : " .. tostring(err))
else
    log("runtime       : ok")
end

local hub
pcall(function()
    local players = game:GetService("Players")
    local localPlayer = players and players.LocalPlayer
    local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
    hub = playerGui and playerGui:FindFirstChild("TyaLinUI")
end)
if hub then
    local count = 0
    pcall(function() count = #hub:GetChildren() end)
    log("TyaLinUI      : found (" .. tostring(count) .. " children)")
    local main = hub:FindFirstChild("Main")
    log("Main frame    : " .. tostring(main ~= nil))
    if main then
        local body = main:FindFirstChild("Body")
        log("body          : " .. tostring(body ~= nil))
    end
else
    log("TyaLinUI      : not found")
end
