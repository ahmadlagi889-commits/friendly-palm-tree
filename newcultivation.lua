-- newcultivation Auto Hub
-- Fitur: Anti-idle, Auto-Combat, Auto-Quest/Mail/Farm/Pet Hatch
-- Loader Rayfield di bawah. Inject via executor.

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Players       = game:GetService("Players")
local RS            = game:GetService("ReplicatedStorage")
local RunService    = game:GetService("RunService")
local LP            = Players.LocalPlayer

-- ========== Remote Resolver ==========
-- Chinese folder segments (encoded to avoid mojibake in editors)
local function u(...) return string.char(...) end
local S = {
    events   = "\228\186\139\228\187\182",             -- 事件
    common   = "\229\133\172\231\148\168",             -- 公用
    mainQ    = "\228\184\187\231\186\191\228\187\187\229\138\161", -- 主线任务
    claim    = "\233\162\134\229\143\150\229\165\150\229\138\177", -- 领取奖励
    mail     = "\233\130\174\228\187\182",             -- 邮件
    mailAll  = "\233\162\134\229\143\150\229\133\168\233\131\168\233\130\174\228\187\182", -- 领取全部邮件
    farm     = "\229\134\156\231\148\176",             -- 农田
    harvest  = "\233\135\135\233\155\134",             -- 采集
    egg      = "\229\174\160\231\137\169\232\155\139", -- 宠物蛋
    hatch    = "\229\188\128\229\144\175",             -- 开启
    idle     = "\232\167\146\232\137\178",             -- 角色  (namespace only)
    idleTO   = "\232\167\146\232\137\178\233\151\178\231\189\174\232\182\133\230\151\182", -- 角色闲置超时 (guess; will fallback)
    setting  = "\232\174\190\231\189\174",             -- 设置
    settingF = "\231\142\169\229\174\182\228\191\174\230\148\185\232\174\190\231\189\174", -- 玩家修改设置
}

local function eventsRoot() return RS:WaitForChild(S.events, 10) end
local function commonRoot() return eventsRoot():WaitForChild(S.common, 10) end

local function resolveRemote(folder, name)
    local root = commonRoot()
    local f = root:FindFirstChild(folder)
    if not f then return nil end
    local r = f:FindFirstChild(name)
    return r
end

-- referenceManager fallback (nama pasti dari game)
local refMgr
pcall(function()
    refMgr = require(RS:WaitForChild("\232\132\154\230\156\172\230\168\161\229\157\151", 10) -- 脚本模块
        :WaitForChild(S.common, 10)
        :WaitForChild("\229\188\149\231\148\168\231\174\161\231\144\134\229\153\168", 10)) -- 引用管理器
end)

local function getEvent(folder, name)
    if refMgr and refMgr["\232\142\183\229\143\150\228\186\139\228\187\182\229\188\149\231\148\168"] then -- 获取事件引用
        local e = refMgr["\232\142\183\229\143\150\228\186\139\228\187\182\229\188\149\231\148\168"](folder, name)
        if e then return e end
    end
    return resolveRemote(folder, name)
end

-- ========== State ==========
local State = {
    antiIdle       = false,
    autoCombat     = false,
    autoQuestMain  = false,
    autoMail       = false,
    autoFarm       = false,
    autoEgg        = false,

    questInterval  = 10,
    mailInterval   = 60,
    farmInterval   = 15,
    eggInterval    = 5,
    combatInterval = 30,
    idleInterval   = 240,

    farmPos = Vector2.new(1276.1334228515625, 312.4964599609375),

}

local function log(msg)
    print("[Hub] " .. tostring(msg))
end

-- ========== Fire Helpers ==========
local function safeFire(folder, name, ...)
    local ok, ev = pcall(getEvent, folder, name)
    if not ok or not ev then
        log("Remote miss: " .. folder .. "/" .. name)
        return false
    end
    local args = {...}
    local ok2, err = pcall(function() ev:FireServer(unpack(args)) end)
    if not ok2 then log("Fire err "..name..": "..tostring(err)) end
    return ok2
end

-- ========== Loops ==========
local function loop(intervalKey, flagKey, fn, tag)
    task.spawn(function()
        while task.wait(1) do
            if State[flagKey] then
                local ok, err = pcall(fn)
                if not ok then log(tag.." err: "..tostring(err)) end
                task.wait(State[intervalKey])
            end
        end
    end)
end

-- Anti-idle: fire 角色闲置超时 periodically + reset Idled behavior
loop("idleInterval", "antiIdle", function()
    safeFire(S.idle, S.idleTO, nil)
end, "AntiIdle")

-- VirtualUser jiggle sebagai backup anti-idle (Roblox 20min kick)
task.spawn(function()
    LP.Idled:Connect(function()
        if not State.antiIdle then return end
        local vu = game:GetService("VirtualUser")
        vu:CaptureController()
        vu:ClickButton2(Vector2.new())
        log("VirtualUser jiggle")
    end)
end)

-- Auto-Combat: ensure setting 自动战斗 stays ON
local ZH_autoCombat = "\232\135\170\229\138\168\230\136\152\230\150\151" -- 自动战斗
local function isAutoCombatOn()
    if not refMgr then return nil end
    local ok, v = pcall(function()
        return refMgr["\232\142\183\229\143\150\231\142\169\229\174\182\229\128\188\229\175\185\232\177\161\229\128\188"]("\232\174\190\231\189\174", ZH_autoCombat) -- 获取玩家值对象值(设置, 自动战斗)
    end)
    if ok then return v end
    return nil
end
loop("combatInterval", "autoCombat", function()
    local on = isAutoCombatOn()
    if on == false then
        safeFire(S.setting, S.settingF, ZH_autoCombat)
        log("Toggle 自动战斗 ON")
    end
end, "AutoCombat")

-- Auto Main Quest claim
loop("questInterval", "autoQuestMain", function()
    safeFire(S.mainQ, S.claim, nil)
end, "MainQuest")

-- Auto Mail claim
loop("mailInterval", "autoMail", function()
    safeFire(S.mail, S.mailAll, nil)
end, "Mail")

-- Auto Farm harvest: SELALU semua plot 1-5 (server reject yang belum matang)
loop("farmInterval", "autoFarm", function()
    for i = 1, 5 do
        safeFire(S.farm, S.harvest, i, State.farmPos)
        task.wait(0.15)
    end
end, "Farm")

-- Auto Egg hatch
loop("eggInterval", "autoEgg", function()
    safeFire(S.egg, S.hatch, nil)
end, "Egg")

-- ========== UI ==========
local Window = Rayfield:CreateWindow({
    Name = "newcultivation Hub",
    LoadingTitle = "loading",
    LoadingSubtitle = "auto",
    ConfigurationSaving = { Enabled = true, FolderName = "newcultivation_hub", FileName = "cfg" },
    KeySystem = false,
})

-- Idle tab
local T1 = Window:CreateTab("Idle & Combat")
T1:CreateToggle({ Name = "Anti-Idle", CurrentValue = false, Flag = "antiIdle",
    Callback = function(v) State.antiIdle = v end })
T1:CreateSlider({ Name = "Idle Fire Interval (s)", Range = {60, 600}, Increment = 30,
    CurrentValue = State.idleInterval, Flag = "idleInterval",
    Callback = function(v) State.idleInterval = v end })
T1:CreateToggle({ Name = "Auto Combat (keep 自动战斗 ON)", CurrentValue = false, Flag = "autoCombat",
    Callback = function(v) State.autoCombat = v end })
T1:CreateSlider({ Name = "Combat Check Interval (s)", Range = {10, 120}, Increment = 5,
    CurrentValue = State.combatInterval, Flag = "combatInterval",
    Callback = function(v) State.combatInterval = v end })

-- Claim tab
local T2 = Window:CreateTab("Claim")
T2:CreateToggle({ Name = "Auto Main Quest 领取奖励", CurrentValue = false, Flag = "autoQuestMain",
    Callback = function(v) State.autoQuestMain = v end })
T2:CreateSlider({ Name = "Main Quest Interval (s)", Range = {0.1, 5}, Increment = 0.1,
    CurrentValue = State.questInterval, Flag = "questInterval",
    Callback = function(v) State.questInterval = v end })
T2:CreateToggle({ Name = "Auto Mail 领取全部", CurrentValue = false, Flag = "autoMail",
    Callback = function(v) State.autoMail = v end })
T2:CreateSlider({ Name = "Mail Interval (s)", Range = {30, 600}, Increment = 30,
    CurrentValue = State.mailInterval, Flag = "mailInterval",
    Callback = function(v) State.mailInterval = v end })
T2:CreateButton({ Name = "Claim Main Quest Once",
    Callback = function() safeFire(S.mainQ, S.claim, nil) end })
T2:CreateButton({ Name = "Claim All Mail Once",
    Callback = function() safeFire(S.mail, S.mailAll, nil) end })

-- Farm/Egg tab
local T3 = Window:CreateTab("Farm & Egg")
T3:CreateToggle({ Name = "Auto Farm Harvest (采集)", CurrentValue = false, Flag = "autoFarm",
    Callback = function(v) State.autoFarm = v end })
T3:CreateSlider({ Name = "Farm Interval (s)", Range = {5, 120}, Increment = 5,
    CurrentValue = State.farmInterval, Flag = "farmInterval",
    Callback = function(v) State.farmInterval = v end })
T3:CreateButton({ Name = "Harvest All Once (plot 1-5)",
    Callback = function()
        for i = 1, 5 do
            safeFire(S.farm, S.harvest, i, State.farmPos)
            task.wait(0.15)
        end
    end })
T3:CreateToggle({ Name = "Auto Hatch Pet Egg", CurrentValue = false, Flag = "autoEgg",
    Callback = function(v) State.autoEgg = v end })
T3:CreateSlider({ Name = "Hatch Interval (s)", Range = {1, 30}, Increment = 1,
    CurrentValue = State.eggInterval, Flag = "eggInterval",
    Callback = function(v) State.eggInterval = v end })
T3:CreateButton({ Name = "Hatch Once",
    Callback = function() safeFire(S.egg, S.hatch, nil) end })

-- Debug tab
local T4 = Window:CreateTab("Debug")
T4:CreateButton({ Name = "Print Remote Tree (事件/公用/*)",
    Callback = function()
        for _, folder in ipairs(commonRoot():GetChildren()) do
            print("[Folder]", folder.Name)
            for _, r in ipairs(folder:GetChildren()) do
                print("   -", r.ClassName, r.Name)
            end
        end
    end })
T4:CreateButton({ Name = "Fire Test: Main Quest Claim",
    Callback = function() safeFire(S.mainQ, S.claim, nil) end })

Rayfield:LoadConfiguration()
log("Ready")
