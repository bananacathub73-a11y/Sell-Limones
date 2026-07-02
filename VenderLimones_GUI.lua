--[[
    Vender Limones  🍋  (Sell Lemons — BloxByte Games)
    Clean GUI Auto-Farm  |  built from decompile + Cobalt remote-spy analysis

    Verified mechanics (from the game's own code):
      * Each purchasable in <MyTycoon>.Purchases.<Area>...<Item> is a Model with a
        `Purchase` RemoteFunction and attributes: Enabled / Purchased / Requires.
        Buying = Purchase:InvokeServer()  (success throws no error; returns nil).
        Items unlock in sequence as prerequisites are bought (Enabled flips true).
      * Cash drops: server fires Core.RemoteSignal "CashDropService.New"(token,life,pos);
        client redeems with Core.RemoteRequest "CashDropService.Redeem":InvokeServer(token).
        We redeem instantly instead of walking over them.
      * Progression: <MyTycoon>.Remotes.Rebirth / Evolve / Ascend are RemoteFunctions,
        InvokeServer() performs the action (server validates eligibility, errors if not).
      * Income: <MyTycoon>.Remotes.WakeIncomeStream:InvokeServer() wakes/claims income.
--]]

--==================================================================
-- Services
--==================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

-- Cash-drop remote wrappers (use game's own modules for correct serialization)
local RemoteSignal  = require(ReplicatedStorage.Core.RemoteSignal)
local RemoteRequest = require(ReplicatedStorage.Core.RemoteRequest)

--==================================================================
-- State
--==================================================================
local State = {
    AutoBuy      = false,
    AutoCollect  = false,
    AutoIncome   = false,
    AutoRebirth  = false,
    AutoEvolve   = false,
    AutoAscend   = false,
    AntiAFK      = true,
}

--==================================================================
-- Tycoon discovery (re-resolves automatically)
--==================================================================
local function getMyTycoon()
    for _, t in ipairs(workspace:GetChildren()) do
        if t.Name:match("^Tycoon%d+$") then
            local o = t:FindFirstChild("Owner")
            if o and o.Value == LocalPlayer then return t end
        end
    end
end

local function tycoonRemote(name)
    local t = getMyTycoon()
    if not t then return end
    local r = t:FindFirstChild("Remotes")
    return r and r:FindFirstChild(name)
end

local function getChar()
    local c = LocalPlayer.Character
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    if hrp and hum and hum.Health > 0 then return c, hrp, hum end
end

--==================================================================
-- AUTO BUY  (only Enabled & not-yet-Purchased items, respects sequence)
--==================================================================
task.spawn(function()
    while true do
        if State.AutoBuy then
            local t = getMyTycoon()
            local pur = t and t:FindFirstChild("Purchases")
            if pur then
                for _, d in ipairs(pur:GetDescendants()) do
                    if not State.AutoBuy then break end
                    if d:IsA("RemoteFunction") and d.Name == "Purchase" then
                        local m = d.Parent
                        if m:GetAttribute("Enabled") and not m:GetAttribute("Purchased") then
                            pcall(function() d:InvokeServer() end)  -- errors if unaffordable; retried next pass
                        end
                    end
                end
            end
            task.wait(0.5)
        else
            task.wait(0.3)
        end
    end
end)

--==================================================================
-- AUTO COLLECT CASH DROPS  (redeem the instant they spawn)
--==================================================================
do
    local ok, redeem = pcall(function() return RemoteRequest.new("CashDropService.Redeem") end)
    local ok2, newSig = pcall(function() return RemoteSignal.new("CashDropService.New") end)
    if ok and ok2 and redeem and newSig then
        newSig.OnClientEvent:Connect(function(token)
            if State.AutoCollect and token ~= nil then
                pcall(function() redeem:InvokeServer(token) end)
            end
        end)
    end
end

--==================================================================
-- AUTO INCOME / REBIRTH / EVOLVE / ASCEND
--==================================================================
task.spawn(function()
    while true do
        task.wait(1)
        if State.AutoIncome  then local r = tycoonRemote("WakeIncomeStream"); if r then pcall(function() r:InvokeServer() end) end end
        if State.AutoRebirth then local r = tycoonRemote("Rebirth");          if r then pcall(function() r:InvokeServer() end) end end
        if State.AutoEvolve  then local r = tycoonRemote("Evolve");           if r then pcall(function() r:InvokeServer() end) end end
        if State.AutoAscend  then local r = tycoonRemote("Ascend");           if r then pcall(function() r:InvokeServer() end) end end
    end
end)

--==================================================================
-- Anti-AFK
--==================================================================
LocalPlayer.Idled:Connect(function()
    if State.AntiAFK then
        local vu = game:GetService("VirtualUser")
        vu:CaptureController()
        vu:ClickButton2(Vector2.new())
    end
end)

--==================================================================
-- Teleport helper (to a Location part in my tycoon)
--==================================================================
local function tpTo(locName)
    local _, hrp = getChar()
    local t = getMyTycoon()
    local loc = t and t:FindFirstChild("Locations")
    local part = loc and loc:FindFirstChild(locName)
    if hrp and part then hrp.CFrame = part.CFrame + Vector3.new(0, 4, 0) end
end

--==================================================================
-- ===========================  GUI  ==============================
--==================================================================
local COL = {
    bg     = Color3.fromRGB(24, 26, 20),
    panel  = Color3.fromRGB(34, 38, 28),
    accent = Color3.fromRGB(210, 200, 40),   -- lemon yellow
    green  = Color3.fromRGB(120, 200, 90),
    off    = Color3.fromRGB(60, 62, 52),
    text   = Color3.fromRGB(240, 242, 225),
    sub    = Color3.fromRGB(160, 165, 140),
}

local parentGui
local ok1, hui = pcall(function() return gethui() end)
if ok1 and hui then parentGui = hui
else
    local ok2, core = pcall(function() return cloneref(game:GetService("CoreGui")) end)
    if ok2 and core then parentGui = core
    else parentGui = game:GetService("CoreGui") end
end

local old = parentGui:FindFirstChild("LemonHub")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "LemonHub"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent = parentGui end)
if not gui.Parent then
    gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
end

local function corner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p end
local function padAll(p, n)
    local u = Instance.new("UIPadding")
    u.PaddingLeft=UDim.new(0,n); u.PaddingRight=UDim.new(0,n); u.PaddingTop=UDim.new(0,n); u.PaddingBottom=UDim.new(0,n)
    u.Parent = p
end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 300, 0, 400)
main.Position = UDim2.new(0, 40, 0.5, -200)
main.BackgroundColor3 = COL.bg
main.BorderSizePixel = 0
main.Parent = gui
corner(main, 12)
local stroke = Instance.new("UIStroke"); stroke.Color = COL.accent; stroke.Thickness = 1.5; stroke.Transparency = 0.35; stroke.Parent = main

-- title bar
local bar = Instance.new("Frame")
bar.Size = UDim2.new(1,0,0,42); bar.BackgroundColor3 = COL.panel; bar.BorderSizePixel = 0; bar.Parent = main
corner(bar, 12)
local barFix = Instance.new("Frame"); barFix.Size=UDim2.new(1,0,0,14); barFix.Position=UDim2.new(0,0,1,-14)
barFix.BackgroundColor3=COL.panel; barFix.BorderSizePixel=0; barFix.Parent=bar

local title = Instance.new("TextLabel")
title.BackgroundTransparency=1; title.Size=UDim2.new(1,-50,1,0); title.Position=UDim2.new(0,14,0,0)
title.Font=Enum.Font.GothamBold; title.Text="🍋 Lemon Tycoon Hub"; title.TextSize=15
title.TextColor3=COL.text; title.TextXAlignment=Enum.TextXAlignment.Left; title.Parent=bar

local minBtn = Instance.new("TextButton")
minBtn.Size=UDim2.new(0,30,0,30); minBtn.Position=UDim2.new(1,-38,0,6)
minBtn.BackgroundColor3=COL.off; minBtn.Text="—"; minBtn.TextColor3=COL.text
minBtn.Font=Enum.Font.GothamBold; minBtn.TextSize=14; minBtn.Parent=bar
corner(minBtn, 8)

-- body
local body = Instance.new("ScrollingFrame")
body.Size=UDim2.new(1,0,1,-42); body.Position=UDim2.new(0,0,0,42)
body.BackgroundTransparency=1; body.BorderSizePixel=0
body.ScrollBarThickness=3; body.ScrollBarImageColor3=COL.accent
body.CanvasSize=UDim2.new(0,0,0,0); body.AutomaticCanvasSize=Enum.AutomaticSize.Y; body.Parent=main
padAll(body, 12)
local list = Instance.new("UIListLayout"); list.Padding=UDim.new(0,8); list.SortOrder=Enum.SortOrder.LayoutOrder; list.Parent=body

local function sectionLabel(txt)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency=1; l.Size=UDim2.new(1,0,0,16)
    l.Font=Enum.Font.GothamBold; l.TextSize=11; l.TextColor3=COL.sub
    l.Text=string.upper(txt); l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=body
end

-- stats card
local stats = Instance.new("Frame")
stats.Size=UDim2.new(1,0,0,54); stats.BackgroundColor3=COL.panel; stats.BorderSizePixel=0; stats.Parent=body
corner(stats,10); padAll(stats,10)
local statText = Instance.new("TextLabel")
statText.BackgroundTransparency=1; statText.Size=UDim2.new(1,0,1,0)
statText.Font=Enum.Font.Gotham; statText.TextSize=13; statText.TextColor3=COL.text
statText.TextXAlignment=Enum.TextXAlignment.Left; statText.TextYAlignment=Enum.TextYAlignment.Top
statText.Text="Locating tycoon..."; statText.Parent=stats

local function makeToggle(text, key, onColor)
    local f = Instance.new("TextButton")
    f.Size=UDim2.new(1,0,0,38); f.BackgroundColor3=COL.panel; f.BorderSizePixel=0
    f.Text=""; f.AutoButtonColor=false; f.Parent=body
    corner(f,10)
    local lbl=Instance.new("TextLabel")
    lbl.BackgroundTransparency=1; lbl.Size=UDim2.new(1,-60,1,0); lbl.Position=UDim2.new(0,12,0,0)
    lbl.Font=Enum.Font.GothamMedium; lbl.TextSize=14; lbl.TextColor3=COL.text
    lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Text=text; lbl.Parent=f
    local knobBG=Instance.new("Frame")
    knobBG.Size=UDim2.new(0,42,0,22); knobBG.Position=UDim2.new(1,-54,0.5,-11)
    knobBG.BackgroundColor3=COL.off; knobBG.BorderSizePixel=0; knobBG.Parent=f
    corner(knobBG,11)
    local knob=Instance.new("Frame")
    knob.Size=UDim2.new(0,18,0,18); knob.Position=UDim2.new(0,2,0.5,-9)
    knob.BackgroundColor3=COL.text; knob.BorderSizePixel=0; knob.Parent=knobBG
    corner(knob,9)
    local function render()
        local on=State[key]
        TweenService:Create(knobBG,TweenInfo.new(0.15),{BackgroundColor3=on and (onColor or COL.accent) or COL.off}):Play()
        TweenService:Create(knob,TweenInfo.new(0.15),{Position=on and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)}):Play()
    end
    f.MouseButton1Click:Connect(function() State[key]=not State[key]; render() end)
    render()
end

local function makeButton(text, cb, color)
    local b=Instance.new("TextButton")
    b.Size=UDim2.new(1,0,0,34); b.BackgroundColor3=color or COL.off; b.BorderSizePixel=0
    b.Font=Enum.Font.GothamBold; b.TextSize=13; b.TextColor3=COL.text; b.Text=text; b.Parent=body
    corner(b,10)
    b.MouseButton1Click:Connect(function() pcall(cb) end)
end

sectionLabel("Stats")
sectionLabel("Automation")
makeToggle("Auto Buy (all upgrades)", "AutoBuy", COL.green)
makeToggle("Auto Collect Cash Drops", "AutoCollect", COL.green)
makeToggle("Auto Claim Income", "AutoIncome", COL.green)
makeToggle("Auto Rebirth", "AutoRebirth")
makeToggle("Auto Evolve", "AutoEvolve")
makeToggle("Auto Ascend", "AutoAscend")
makeToggle("Anti-AFK", "AntiAFK")

sectionLabel("Actions")
makeButton("Rebirth Now", function() local r=tycoonRemote("Rebirth"); if r then r:InvokeServer() end end, COL.accent)
makeButton("Evolve Now",  function() local r=tycoonRemote("Evolve");  if r then r:InvokeServer() end end, COL.accent)
makeButton("Ascend Now",  function() local r=tycoonRemote("Ascend");  if r then r:InvokeServer() end end, COL.accent)

sectionLabel("Teleports")
makeButton("TP → My Tycoon Spawn", function() tpTo("Spawn") end)
makeButton("TP → Minigame Race",   function() tpTo("MinigameRace") end)
makeButton("TP → Lemon Trading",   function() tpTo("Lemon Trading") end)

--==================================================================
-- Live stats
--==================================================================
task.spawn(function()
    while gui.Parent do
        local t = getMyTycoon()
        if t then
            local pur = t:FindFirstChild("Purchases")
            local owned, avail = 0, 0
            if pur then
                for _, d in ipairs(pur:GetDescendants()) do
                    if d:IsA("RemoteFunction") and d.Name == "Purchase" then
                        local m = d.Parent
                        if m:GetAttribute("Purchased") then owned += 1
                        elseif m:GetAttribute("Enabled") then avail += 1 end
                    end
                end
            end
            statText.Text = string.format(
                "Tycoon:  %s\nUpgrades owned:  %d   |   Ready to buy:  %d",
                t.Name, owned, avail
            )
        else
            statText.Text = "No tycoon claimed yet.\nStep on an empty plot to claim one."
        end
        task.wait(0.6)
    end
end)

--==================================================================
-- Minimize + drag
--==================================================================
local minimized=false
minBtn.MouseButton1Click:Connect(function()
    minimized=not minimized
    TweenService:Create(main,TweenInfo.new(0.2),{Size=minimized and UDim2.new(0,300,0,42) or UDim2.new(0,300,0,400)}):Play()
    body.Visible=not minimized
    minBtn.Text=minimized and "+" or "—"
end)

do
    local dragging, dragStart, startPos
    bar.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            dragging=true; dragStart=i.Position; startPos=main.Position
            i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false end end)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            local d=i.Position-dragStart
            main.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
        end
    end)
end

print("[Lemon Tycoon Hub] Loaded. Tycoon:", (getMyTycoon() and getMyTycoon().Name) or "not found")
