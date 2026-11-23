-- ChronoTimer 能量 / 连击点显示
-- 仅盗贼与小德（能量形态）可见
-- 简约风格：黄色能量长条 + 上方一排连击点小长条（只显示已获得的星数）

local COMBO_MAX = 5

-- 连击点颜色：高饱和亮色，对比度更高
local COMBO_COLORS = {
    { 0.10, 0.82, 1.00 },  -- 亮蓝
    { 0.72, 0.20, 1.00 },  -- 亮紫
    { 1.00, 0.12, 0.10 },  -- 亮红
    { 1.00, 0.82, 0.00 },  -- 亮金
    { 0.25, 1.00, 0.35 },  -- 亮绿
}

local BAR_TEX = "Interface\\TargetingFrame\\UI-StatusBar"

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[ChronoTimer]|r " .. tostring(msg))
end

-- 职业保护：仅盗贼与小德启用；职业尚未就绪时先放行，由运行时刷新兜底
local function IsEnergyClass()
    local _, class = UnitClass("player")
    if not class then return true end
    if class == "ROGUE" or class == "DRUID" then return true end
    if class == "潜行者" or class == "盗贼" or class == "德鲁伊" then return true end
    return false
end

if not IsEnergyClass() then
    function ChronoTimerEnergy_Refresh() end
    function ChronoTimerEnergy_Apply() end
    function ChronoTimerEnergy_ToggleMove() end
    function ChronoTimerEnergy_Reset() end
    return
end

local frame = CreateFrame("Frame", "ChronoTimerEnergyFrame", UIParent)
frame:SetFrameStrata("MEDIUM")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetWidth(166)
frame:SetHeight(30)
frame:SetPoint("CENTER", UIParent, "CENTER", -180, -160)
frame:Hide()
frame.unlocked = false

-- 能量条（普通黄色）
local bar = CreateFrame("StatusBar", nil, frame)
bar:SetStatusBarTexture(BAR_TEX)
bar:SetStatusBarColor(1, 0.82, 0.1)
bar:SetMinMaxValues(0, 100)
bar:SetValue(0)
frame.bar = bar

local bg = bar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(bar)
bg:SetTexture(0, 0, 0, 0.55)

local text = bar:CreateFontString(nil, "OVERLAY")
text:SetFontObject(GameFontNormalSmall)
text:SetPoint("CENTER", bar, "CENTER", 0, 0)
text:SetTextColor(1, 1, 1)
frame.text = text

-- 回能光标：标出下一次能量跳动的位置，随恢复进度从左向右移动
local tick = bar:CreateTexture(nil, "OVERLAY")
tick:SetTexture(1, 1, 1)
tick:SetAlpha(0.9)
tick:SetWidth(2)
tick:Hide()
frame.tick = tick

-- 回能节奏：经典服为每 2 秒一跳，实际间隔按观察到的跳动动态校准
local TICK_DEFAULT = 2
local lastMana, lastTickAt, tickInterval = nil, nil, TICK_DEFAULT
local tickVisible = false
local energyFull = false

-- 连击点：一排小长条，只显示已获得的星数
frame.dots = {}
for i = 1, COMBO_MAX do
    local seg = CreateFrame("Frame", nil, frame)
    -- 外圈黑边，地形再花也能看清
    local border = seg:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", seg, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", 1, -1)
    border:SetTexture(0, 0, 0, 0.9)

    local tex = seg:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(seg)
    tex:SetTexture(BAR_TEX)
    local c = COMBO_COLORS[i]
    tex:SetVertexColor(c[1], c[2], c[3])
    seg:Hide()
    frame.dots[i] = seg
end

-- 按设置重新排版：能量条宽高、连击点高度与间距
local function Layout()
    local p = ChronoTimerDB and ChronoTimerDB.profile or {}
    local bw = p.energyWidth or 150
    local bh = p.energyHeight or 12
    local ch = p.comboHeight or 6
    local sp = p.comboSpacing or 4
    local showBar   = p.showEnergyBar ~= false
    local showCombo = p.showComboPoints ~= false

    if bw < 40 then bw = 40 end
    if bh < 6  then bh = 6  end
    if ch < 2  then ch = 2  end
    if sp < 0  then sp = 0  end

    local pad  = 6
    local segW = (bw - (COMBO_MAX - 1) * sp) / COMBO_MAX
    if segW < 4 then segW = 4 end

    local h = pad
    if showCombo then h = h + ch end
    if showCombo and showBar then h = h + 4 end
    if showBar then h = h + bh end
    h = h + pad

    frame:SetWidth(bw + pad * 2)
    frame:SetHeight(h)

    for i = 1, COMBO_MAX do
        local d = frame.dots[i]
        d:SetWidth(segW)
        d:SetHeight(ch)
        d:ClearAllPoints()
        d:SetPoint("TOPLEFT", frame, "TOPLEFT", pad + (i - 1) * (segW + sp), -pad)
    end

    if showBar then bar:Show() else bar:Hide() end

    bar:ClearAllPoints()
    bar:SetWidth(bw)
    bar:SetHeight(bh)
    bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)

    local fs = bh - 4
    if fs < 8  then fs = 8  end
    if fs > 16 then fs = 16 end
    local path, _, flags = GameFontNormal:GetFont()
    text:SetFont(path, fs, flags or "")
end

-- 解锁 / 锁定拖动
local function SetUnlocked(v)
    frame.unlocked = v and true or false
    if frame.unlocked then
        frame:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        frame:SetBackdropBorderColor(0.2, 0.95, 0.4, 1)
    else
        frame:SetBackdrop(nil)
    end
end

-- 用独立的驱动帧刷新（隐藏的帧不会收到 OnUpdate）
local driver = CreateFrame("Frame")
driver.elapsed = 0
driver:SetScript("OnUpdate", function()
    this.elapsed = (this.elapsed or 0) + arg1
    if this.elapsed < 0.1 then return end
    this.elapsed = 0

    local p = ChronoTimerDB and ChronoTimerDB.profile
    if not p or p.showEnergy == false then
        if frame:IsShown() then frame:Hide() end
        return
    end

    local _, class = UnitClass("player")
    if class ~= "ROGUE" and class ~= "DRUID"
        and class ~= "潜行者" and class ~= "盗贼" and class ~= "德鲁伊" then
        if frame:IsShown() then frame:Hide() end
        return
    end

    -- 小德只有猎豹等能量形态显示
    if UnitPowerType and UnitPowerType("player") ~= 3 then
        if frame:IsShown() then frame:Hide() end
        return
    end

    if not frame:IsShown() then frame:Show() end

    local cur = UnitMana("player") or 0
    local max = UnitManaMax("player") or 100
    if max <= 0 then max = 100 end
    bar:SetMinMaxValues(0, max)
    bar:SetValue(cur)
    text:SetText(cur .. " / " .. max)

    -- 观测能量跳动，动态校准回能间隔（经典服默认 2 秒一跳）
    local now = GetTime()
    if lastMana == nil then
        lastMana = cur
    elseif cur > lastMana then
        local gain = cur - lastMana
        -- 小额度增量视为自然回能；菊花茶、药水等大额回复不参与校准
        if gain <= 30 then
            if lastTickAt then
                local gap = now - lastTickAt
                if gap > 0.5 and gap < 5 then
                    tickInterval = tickInterval * 0.6 + gap * 0.4
                end
            end
            lastTickAt = now
        end
        lastMana = cur
    elseif cur < lastMana then
        lastMana = cur
    end

    -- 回能光标：满能量时也显示，但透明度降低，按校准节奏自行循环
    energyFull = cur >= max
    if p.showEnergyTick == false or not lastTickAt then
        if tickVisible then tick:Hide() tickVisible = false end
    else
        if not tickVisible then tick:Show() tickVisible = true end
        if energyFull then
            tick:SetAlpha(0.3)
        else
            tick:SetAlpha(0.9)
        end
    end

    local cp = GetComboPoints("target")
    if cp == nil then cp = GetComboPoints() end
    if not cp then cp = 0 end
    if cp > COMBO_MAX then cp = COMBO_MAX end
    if p.showComboPoints == false then cp = 0 end
    for i = 1, COMBO_MAX do
        local d = frame.dots[i]
        if i <= cp then
            if not d:IsShown() then d:Show() end
        else
            if d:IsShown() then d:Hide() end
        end
    end
end)

-- 回能光标逐帧平滑移动（仅在可见时计算）
frame:SetScript("OnUpdate", function()
    if not tickVisible or not lastTickAt then return end
    local p = ChronoTimerDB and ChronoTimerDB.profile
    if not p or p.showEnergyTick == false then return end
    local progress = (GetTime() - lastTickAt) / tickInterval
    if progress >= 1 then
        if energyFull then
            -- 满能量时没有可观测的跳动，直接按校准间隔推进到下一个周期
            lastTickAt = lastTickAt + tickInterval * math.floor(progress)
            progress = (GetTime() - lastTickAt) / tickInterval
        else
            progress = 1
        end
    end
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end
    tick:SetHeight(bar:GetHeight())
    tick:ClearAllPoints()
    tick:SetPoint("CENTER", bar, "LEFT", (bar:GetWidth() or 0) * progress, 0)
end)

frame:SetScript("OnDragStart", function()
    if frame.unlocked or IsControlKeyDown() then
        this:StartMoving()
    end
end)
frame:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    local p = ChronoTimerDB and ChronoTimerDB.profile
    if not p then return end
    local x, y = this:GetCenter()
    local sw, sh = GetScreenWidth(), GetScreenHeight()
    if x and y and sw and sh then
        p.energyCX = x - sw / 2
        p.energyCY = y - sh / 2
    end
end)

-- 读取保存的位置
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 ~= "ChronoTimer" then return end
    local p = ChronoTimerDB and ChronoTimerDB.profile
    if p and p.energyCX and p.energyCY then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", p.energyCX, p.energyCY)
    end
    Layout()
end)

function ChronoTimerEnergy_Refresh()
    driver.elapsed = 1
end

-- 设置改动后立即重新排版并刷新
function ChronoTimerEnergy_Apply()
    Layout()
    driver.elapsed = 1
end

-- 解锁 / 锁定位置（供设置面板与命令调用）
function ChronoTimerEnergy_ToggleMove()
    SetUnlocked(not frame.unlocked)
    if frame.unlocked then
        Print("|cff00ff00位置已解锁|r：左键拖动能量条到想要的位置，再次点击按钮锁定")
    else
        Print("位置已锁定")
    end
end

function ChronoTimerEnergy_Reset()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", -180, -160)
    local p = ChronoTimerDB and ChronoTimerDB.profile
    if p then
        p.energyCX = nil
        p.energyCY = nil
    end
end
