-- ChronoTimer 图标模式（WeakAuras 风格图标倒计时）
-- 由主文件 ChronoTimer.lua 在初始化时调用 Initialize(db, active)
-- 只负责显示，计时数据仍由主文件维护在 active 表中

local IM = {}
ChronoTimerIconMode = IM

local ICON_DEFAULT = "Interface\\Icons\\INV_Misc_QuestionMark"

-- 自身控制类 Debuff 关键词（眩晕 / 定身 等），不区分大小写
local CC_WORDS = {
    "眩晕", "昏迷", "击晕", "闷棍", "凿击", "定身", "禁锢", "缠绕", "纠缠",
    "冰冻", "冰冻陷阱", "冰霜新星", "恐惧", "破胆怒吼", "魅惑", "变形", "睡眠", "沉睡", "蛛网",
    "肾击", "偷袭", "制裁之锤", "忏悔", "致盲", "心灵尖啸", "翼龙钉刺", "休眠",
    "军团镣铐", "镣铐",
    "stun", "sap", "gouge", "root", "frost nova", "frostbite", "entangling",
    "polymorph", "fear", "charm", "sleep", "kidney shot", "cheap shot",
    "hammer of justice", "concussion blow", "bash", "pounce", "war stomp",
    "intercept", "feral charge", "web", "intimidating shout",
    "psychic scream", "blind", "repentance", "wyvern sting", "hibernate",
    "death coil", "scare beast", "turn undead", "charge stun", "legion shackles",
}

local db, active
local container          -- 图标锚点（可拖动）
local icons = {}         -- key -> frame
local ccFrame, ccIcon    -- 屏幕中央控制类 Debuff
local ccBars = {}        -- 上下红条
local enabled = false
local unlocked = false
local ccUnlocked = false
local lastUpdate = 0
local initialized = false
local pfui               -- pfUI API（若已加载，则使用 pfUI 风格边框）
local PFUI_FONT

local function GetFontPath()
    -- 使用游戏自带字体，避免 pfUI 自定义字体不存在导致文字不显示
    if GameFontNormal and GameFontNormal.GetFont then
        local p = GameFontNormal:GetFont()
        if p and p ~= "" then return p end
    end
    return "Fonts\\FRIZQT__.TTF"
end

local function SetFontSize(fs, size)
    fs:SetFont(GetFontPath(), size, "OUTLINE")
end

-- pfUI 在场时用它的扁平细边框，否则用原生提示框边框
local function SkinFrame(f, br, bg, bb)
    if pfui and pfui.CreateBackdrop then
        pfui.CreateBackdrop(f)
        if f.backdrop and br then
            f.backdrop:SetBackdropBorderColor(br, bg, bb, 1)
        end
    else
        f:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, tileSize = 16, edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        f:SetBackdropColor(0, 0, 0, 0.65)
        f:SetBackdropBorderColor(br or 0.05, bg or 0.05, bb or 0.05, 1)
    end
end

local function SetSkinBackground(f, alpha, br, bg, bb)
    if f.backdrop then
        f.backdrop:SetBackdropColor(0, 0, 0, alpha)
        f.backdrop:SetBackdropBorderColor(br, bg, bb, alpha > 0 and 1 or 0)
    else
        f:SetBackdropColor(0, 0, 0, alpha)
        f:SetBackdropBorderColor(br, bg, bb, alpha > 0 and 1 or 0)
    end
end

-- 图标描边颜色：自身 Debuff 四周染红，其余保持默认深灰
local BORDER_DEFAULT     = { 0.05, 0.05, 0.05 }
local BORDER_SELF_DEBUFF = { 1, 0.08, 0.08 }

local function SetIconBorder(f, c)
    if f.backdrop then
        f.backdrop:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    else
        f:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    end
end

local function FormatTime(rem, asSeconds)
    if asSeconds then
        return tostring(math.ceil(rem))
    end
    if rem >= 60 then
        local m = math.floor(rem / 60)
        local s = math.floor(math.mod(rem, 60))
        if s < 10 then return m .. ":0" .. s end
        return m .. ":" .. s
    end
    return tostring(math.ceil(rem))
end

-- 倒计时文字大小：0 表示按图标尺寸自动
local function CountdownFontSize(iconSize)
    local v = db and db.iconTextSize or 0
    if v and v > 0 then return v end
    return math.max(10, math.floor(iconSize * 0.46))
end

local function StackFontSize(iconSize)
    local v = db and db.stackTextSize or 0
    if v and v > 0 then return v end
    return math.max(8, math.floor(CountdownFontSize(iconSize) * 0.65))
end

local function CCTextFontSize(ccSize)
    local v = db and db.iconTextSize or 0
    if v and v > 0 then return v end
    return math.max(10, math.floor(ccSize * 0.40))
end

local function CCStackFontSize(ccSize)
    local v = db and db.stackTextSize or 0
    if v and v > 0 then return v end
    return 12
end

local function IsCCName(name)
    if not name then return false end
    local lname = string.lower(name)
    for i = 1, table.getn(CC_WORDS) do
        if string.find(lname, CC_WORDS[i], 1, true) then return true end
    end
    return false
end

local TARGET_LABEL_HEIGHT = 11

local function CreateIconFrame(parent, size, withTarget)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(size)
    f:SetHeight(size + (withTarget and TARGET_LABEL_HEIGHT or 0))
    f.hasTarget = withTarget and true or false
    f.size = size
    SkinFrame(f, 0.05, 0.05, 0.05)

    local inset = pfui and 1 or 2
    f.inset = inset
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
    f.icon:SetWidth(size - inset * 2)
    f.icon:SetHeight(size - inset * 2)
    f.icon:SetTexture(ICON_DEFAULT)
    if pfui then
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("CENTER", f.icon, "CENTER", 0, 0)
    SetFontSize(f.text, CountdownFontSize(size))
    f.text:SetTextColor(1, 1, 1, 1)
    f.text:SetShadowColor(0, 0, 0, 1)
    f.text:SetShadowOffset(1, -1)

    f.stack = f:CreateFontString(nil, "OVERLAY")
    f.stack:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", -3, 3)
    SetFontSize(f.stack, StackFontSize(size))
    f.stack:SetTextColor(1, 0.9, 0.3, 1)
    f.stack:SetShadowColor(0, 0, 0, 1)
    f.stack:SetShadowOffset(1, -1)

    if withTarget then
        f.targetName = f:CreateFontString(nil, "OVERLAY")
        f.targetName:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 0)
        f.targetName:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 0)
        f.targetName:SetHeight(TARGET_LABEL_HEIGHT)
        f.targetName:SetJustifyH("CENTER")
        SetFontSize(f.targetName, math.max(8, math.floor(size * 0.22)))
        f.targetName:SetTextColor(0.85, 0.95, 1, 1)
        f.targetName:SetShadowColor(0, 0, 0, 1)
        f.targetName:SetShadowOffset(1, -1)

        f.click = CreateFrame("Button", nil, f)
        f.click:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        f.click:SetWidth(size)
        f.click:SetHeight(size)
        f.click:RegisterForClicks("LeftButtonUp")
        f.click:SetScript("OnClick", function()
            if unlocked or not this.key then return end
            ChronoTimer.CastTrackedHoT(this.key, arg1)
        end)
    end

    return f
end

local function ResizeIcon(f, size)
    f.size = size
    f:SetWidth(size)
    f:SetHeight(size + (f.targetName and TARGET_LABEL_HEIGHT or 0))
    local inset = f.inset or 2
    f.icon:SetWidth(size - inset * 2)
    f.icon:SetHeight(size - inset * 2)
    SetFontSize(f.text, CountdownFontSize(size))
    SetFontSize(f.stack, StackFontSize(size))
    if f.targetName then
        SetFontSize(f.targetName, math.max(8, math.floor(size * 0.22)))
        f.click:SetWidth(size)
        f.click:SetHeight(size)
    end
end

local function SavePosition(frame, xKey, yKey)
    if not frame or not db then return end
    local upscale = UIParent:GetEffectiveScale()
    if not upscale or upscale == 0 then upscale = 1 end
    local fscale = frame:GetEffectiveScale()
    if not fscale or fscale == 0 then fscale = 1 end
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not left or not bottom then return end
    db[xKey] = math.floor(left * fscale / upscale + 0.5)
    db[yKey] = math.floor(bottom * fscale / upscale + 0.5)
end

-- 新版 CC 已固定布局，这个函数留空占位
local function StyleRedBars(size)
end

local function CreateCC()
    ccFrame = CreateFrame("Frame", "ChronoTimerCCFrame", UIParent)
    ccFrame:SetFrameStrata("TOOLTIP")
    ccFrame:SetFrameLevel(120)
    ccFrame:SetWidth(220)
    ccFrame:SetHeight(56)
    ccFrame:SetMovable(true)
    ccFrame:SetClampedToScreen(true)
    ccFrame:EnableMouse(false)
    ccFrame:RegisterForDrag("LeftButton")

    -- 上下红色梯形柔光：宽边贴住图标、向外收窄渐隐，上下镜像对称
    local GLOW = "Interface\\AddOns\\ChronoTimer\\Textures\\ccglow"
    local GAP, GH = 10, 32

    ccFrame.glowTop = ccFrame:CreateTexture(nil, "ARTWORK")
    ccFrame.glowTop:SetTexture(GLOW)
    ccFrame.glowTop:SetVertexColor(1, 0, 0)
    ccFrame.glowTop:SetBlendMode("BLEND")
    ccFrame.glowTop:SetPoint("BOTTOMLEFT", ccFrame, "TOPLEFT", 0, GAP)
    ccFrame.glowTop:SetPoint("BOTTOMRIGHT", ccFrame, "TOPRIGHT", 0, GAP)
    ccFrame.glowTop:SetHeight(GH)

    ccFrame.glowBottom = ccFrame:CreateTexture(nil, "ARTWORK")
    ccFrame.glowBottom:SetTexture(GLOW)
    ccFrame.glowBottom:SetVertexColor(1, 0, 0)
    ccFrame.glowBottom:SetBlendMode("BLEND")
    ccFrame.glowBottom:SetTexCoord(0, 1, 1, 0)   -- 垂直翻转，让宽边贴住图标
    ccFrame.glowBottom:SetPoint("TOPLEFT", ccFrame, "BOTTOMLEFT", 0, -GAP)
    ccFrame.glowBottom:SetPoint("TOPRIGHT", ccFrame, "BOTTOMRIGHT", 0, -GAP)
    ccFrame.glowBottom:SetHeight(GH)

    -- 深色背景去掉，完全透明
    --（保留一个 1x1 的 invisible texture 让 frame 的 TOPLEFT/BOTTOMRIGHT 有依附）

    -- 图标（居中，倒计时在其左、技能名在其右，整组落在泛光区域中央）
    local iconSize = 40
    ccIcon = CreateFrame("Frame", nil, ccFrame)
    ccIcon:SetPoint("CENTER", ccFrame, "CENTER", 0, 0)
    ccIcon:SetWidth(iconSize)
    ccIcon:SetHeight(iconSize)
    ccIcon.icon = ccIcon:CreateTexture(nil, "ARTWORK")
    ccIcon.icon:SetPoint("TOPLEFT", ccIcon, "TOPLEFT", 0, 0)
    ccIcon.icon:SetPoint("BOTTOMRIGHT", ccIcon, "BOTTOMRIGHT", 0, 0)
    ccIcon.icon:SetTexture(ICON_DEFAULT)
    ccIcon.stack = ccIcon:CreateFontString(nil, "OVERLAY")
    ccIcon.stack:SetPoint("BOTTOMRIGHT", ccIcon, "BOTTOMRIGHT", -2, 2)
    SetFontSize(ccIcon.stack, CCStackFontSize(iconSize))
    ccIcon.stack:SetTextColor(1, 0.9, 0.3, 1)
    ccIcon.stack:SetShadowColor(0, 0, 0, 1)
    ccIcon.stack:SetShadowOffset(1, -1)
    ccIcon.stack:SetText("")

    -- 技能名称（图标右侧，垂直居中）
    ccFrame.title = ccFrame:CreateFontString(nil, "OVERLAY")
    ccFrame.title:SetPoint("LEFT", ccIcon, "RIGHT", 8, 0)
    ccFrame.title:SetJustifyH("LEFT")
    ccFrame.title:SetFont(GetFontPath(), 13, "OUTLINE")
    ccFrame.title:SetTextColor(1, 1, 1, 1)
    ccFrame.title:SetShadowColor(0, 0, 0, 1)
    ccFrame.title:SetShadowOffset(1, -1)
    ccFrame.title:SetText("")

    -- 剩余时间（图标左侧，垂直居中）
    ccIcon.text = ccFrame:CreateFontString(nil, "OVERLAY")
    ccIcon.text:SetPoint("RIGHT", ccIcon, "LEFT", -8, 0)
    ccIcon.text:SetJustifyH("RIGHT")
    ccIcon.text:SetFont(GetFontPath(), 16, "OUTLINE")
    ccIcon.text:SetTextColor(1, 0.9, 0.4, 1)
    ccIcon.text:SetShadowColor(0, 0, 0, 1)
    ccIcon.text:SetShadowOffset(1, -1)
    ccIcon.text:SetText("")

    ccFrame.label = ccFrame:CreateFontString(nil, "OVERLAY")
    ccFrame.label:SetFontObject(GameFontNormalSmall)
    ccFrame.label:SetPoint("BOTTOM", ccFrame, "BOTTOM", 0, -16)
    ccFrame.label:SetTextColor(1, 0.5, 0.5, 1)
    ccFrame.label:SetText("控制类 Debuff（可拖动）")
    ccFrame.label:Hide()

    -- 泛光颜色加重到最深：纯红、完全不透明度（不再做呼吸脉动）
    ccFrame.glowTop:SetVertexColor(1, 0, 0)
    ccFrame.glowBottom:SetVertexColor(1, 0, 0)
    ccFrame.glowTop:SetAlpha(1)
    ccFrame.glowBottom:SetAlpha(1)

    ccFrame:SetScript("OnDragStart", function()
        if not ccUnlocked then return end
        this:StartMoving()
    end)
    ccFrame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        SavePosition(this, "ccX", "ccY")
    end)

    if db.ccX and db.ccY then
        ccFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.ccX, db.ccY)
    else
        ccFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
    ccFrame:Hide()
end

local function CreateContainer()
    container = CreateFrame("Frame", "ChronoTimerIconAnchor", UIParent)
    container:SetFrameStrata("MEDIUM")
    container:SetWidth(db.iconSize or 40)
    container:SetHeight(db.iconSize or 40)
    container:SetMovable(true)
    container:SetClampedToScreen(true)
    container:EnableMouse(false)
    container:RegisterForDrag("LeftButton")
    SkinFrame(container, 0.3, 1, 0.9)
    SetSkinBackground(container, 0, 0.3, 1, 0.9)

    container.label = container:CreateFontString(nil, "OVERLAY")
    container.label:SetFontObject(GameFontNormalSmall)
    container.label:SetPoint("TOP", container, "BOTTOM", 0, -4)
    container.label:SetTextColor(0.5, 1, 0.9, 1)
    container.label:SetText("ChronoTimer 图标位置（可拖动）")
    container.label:Hide()

    container:SetScript("OnDragStart", function()
        if not unlocked then return end
        this:StartMoving()
    end)
    container:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        SavePosition(this, "iconX", "iconY")
    end)

    if db.iconX and db.iconY then
        container:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.iconX, db.iconY)
    else
        container:SetPoint("TOP", UIParent, "TOP", 0, -180)
    end
    container:Hide()
end

-- 独立驱动帧：条形模式下图标容器是隐藏的，挂在容器上的 OnUpdate 不会触发，
-- 中央控制图标需要在两种显示模式下都刷新，所以单独用常驻帧驱动
local ticker
local function CreateTicker()
    ticker = CreateFrame("Frame", "ChronoTimerIconTicker", UIParent)
    ticker:SetWidth(1)
    ticker:SetHeight(1)
    ticker:SetScript("OnUpdate", function()
        local now = GetTime()
        if (now - lastUpdate) < 0.1 then return end
        lastUpdate = now
        IM:Update(false)
    end)
end

function IM:Initialize(database, activeTable)
    if initialized then return end
    if not database or not activeTable then return end
    db = database
    active = activeTable
    CreateContainer()
    CreateCC()
    CreateTicker()
    self:ApplySettings()
    self:SetEnabled(db.displayMode == "icon")
    initialized = true
end

function IM:ApplySettings()
    if not container or not db then return end
    local size = db.iconSize or 40
    local spacing = db.iconSpacing or 6
    local cols = db.iconPerRow or 8
    if cols < 1 then cols = 1 end

    container:SetWidth(cols * size + (cols - 1) * spacing)
    container:SetHeight(size + TARGET_LABEL_HEIGHT)

    for key, f in pairs(icons) do
        ResizeIcon(f, size)
    end

    -- 新版 CC 是固定尺寸矩形框，这里不再根据 db.ccSize 动态调整
    if ccFrame then
        StyleRedBars(db.ccSize or 64)
    end
    if ccIcon and ccIcon.stack then
        SetFontSize(ccIcon.stack, CCStackFontSize(40))
    end

    self:Update(true)
end

function IM:SetEnabled(on)
    enabled = on
    if not container then return end
    if on then
        container:Show()
        self:Update(true)
    else
        container:Hide()
        -- 中央控制图标不随显示模式关闭（「中央控制图标」关闭时由 Update 隐藏）
        if ccFrame then
            ccUnlocked = false
            ccFrame:EnableMouse(false)
            ccFrame.label:Hide()
        end
        unlocked = false
        container:EnableMouse(false)
        SetSkinBackground(container, 0, 0.3, 1, 0.9)
        container.label:Hide()
    end
end

function IM:ToggleUnlock()
    if not container then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[ChronoTimer]|r 图标模式尚未初始化")
        return
    end
    if not enabled then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[ChronoTimer]|r 请先开启「使用图标显示」")
        return
    end
    unlocked = not unlocked
    if unlocked then
        container:Show()
        container:EnableMouse(true)
        SetSkinBackground(container, 0.45, 0.3, 1, 0.9)
        container.label:Show()
    else
        container:EnableMouse(false)
        SetSkinBackground(container, 0, 0.3, 1, 0.9)
        container.label:Hide()
    end
    self:Update(true)
end

function IM:ToggleCCUnlock()
    if not ccFrame then return end
    if not enabled and not db.ccCenter then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[ChronoTimer]|r 请先开启「使用图标显示」或「中央控制图标」")
        return
    end
    ccUnlocked = not ccUnlocked
    if ccUnlocked then
        ccFrame:Show()
        ccFrame:EnableMouse(true)
        SetSkinBackground(ccFrame, 0.55, 0.3, 1, 0.9)
        ccFrame.label:Show()
    else
        ccFrame:EnableMouse(false)
        SetSkinBackground(ccFrame, 0, 0.3, 1, 0.9)
        ccFrame.label:Hide()
    end
    self:Update(true)
end

function IM:ResetIconPosition()
    db.iconX, db.iconY = nil, nil
    if container then
        container:ClearAllPoints()
        container:SetPoint("TOP", UIParent, "TOP", 0, -180)
    end
    self:Update(true)
end

function IM:ResetCCPosition()
    db.ccX, db.ccY = nil, nil
    if ccFrame then
        ccFrame:ClearAllPoints()
        ccFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
    self:Update(true)
end

-- pfUI 可能比本插件更晚完成初始化，因此延迟检测并重新美化
local function TrySkinPfUI()
    if pfui or not pfUI or not pfUI.api or not pfUI.api.CreateBackdrop then return end
    pfui = pfUI.api
    PFUI_FONT = (pfUI.path or "Interface\\AddOns\\pfUI") .. "\\fonts\\RobotoMono.ttf"

    local function Reskin(f, br, bg, bb)
        if f:GetBackdrop() then f:SetBackdrop(nil) end
        pfui.CreateBackdrop(f)
        if f.backdrop and br then
            f.backdrop:SetBackdropBorderColor(br, bg, bb, 1)
        end
    end

    Reskin(container, 0.3, 1, 0.9)
    SetSkinBackground(container, unlocked and 0.45 or 0, 0.3, 1, 0.9)

    -- 已创建的图标框同步切换为 pfUI 风格（细边框 + 8% 裁边）
    for _, f in pairs(icons) do
        Reskin(f, 0.05, 0.05, 0.05)
        f.inset = 1
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if f.size then ResizeIcon(f, f.size) end
    end

    if ccFrame then
        SetSkinBackground(ccFrame, ccUnlocked and 0.3 or 0, 0.3, 1, 0.9)
    end

    local size = db.iconSize or 40
    for key, f in pairs(icons) do
        Reskin(f, 0.05, 0.05, 0.05)
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ResizeIcon(f, size)
    end
end

function IM:Update(force)
    if not db or not container then return end
    local iconMode = enabled
    -- 图标列表只属于图标模式；中央控制图标在两种模式下都显示
    if not iconMode and not db.ccCenter then
        container:Hide()
        if ccFrame then ccFrame:Hide() end
        return
    end
    if iconMode then
        if not container:IsShown() then container:Show() end
    else
        container:Hide()
    end
    TrySkinPfUI()

    local now = GetTime()
    local size = db.iconSize or 40
    local spacing = db.iconSpacing or 6
    local cols = db.iconPerRow or 8
    if cols < 1 then cols = 1 end
    local step = size + spacing
    local showCC = db.ccCenter

    local selfList, targetList, seen = {}, {}, {}
    local ccEntry = nil

    for key, v in pairs(active) do
        local ends = v.endsAt or v.expires
        if ends and v.name then
            local rem = ends - now
            if rem > 0 then
                local isCC = showCC and v.isDebuff and not v.isTotem and not v.isTarget
                    and (IsCCName(v.name)
                         or (v.spellId and ChronoTimer and ChronoTimer.IsControlAura
                             and ChronoTimer.IsControlAura(v.spellId)))
                if isCC and not ccEntry then
                    ccEntry = { key = key, v = v, rem = rem }
                else
                    seen[key] = true
                    local e = { key = key, v = v, rem = rem }
                    if v.isTarget then
                        targetList[table.getn(targetList) + 1] = e
                    else
                        selfList[table.getn(selfList) + 1] = e
                    end
                end
            end
        end
    end

    table.sort(selfList, function(a, b) return a.rem < b.rem end)
    table.sort(targetList, function(a, b) return a.rem < b.rem end)

    -- 横向排满一行后换行；自身向下生长（不显示目标名文字，也不留文字高度），目标 Debuff 向上生长
    local function PlaceIcons(list, upward)
        local rowStep = upward and (step + TARGET_LABEL_HEIGHT) or step
        for i = 1, table.getn(list) do
            local e = list[i]
            local f = icons[e.key]
            if f and f.hasTarget ~= upward then
                f:Hide()
                icons[e.key] = nil
                f = nil
            end
            if not f then
                f = CreateIconFrame(container, size, upward)
                icons[e.key] = f
            end
            f:Show()
            f:ClearAllPoints()

            local idx = i - 1
            local col = math.mod(idx, cols)
            local row = math.floor(idx / cols)
            local x = col * step
            if upward then
                f:SetPoint("BOTTOMLEFT", container, "TOPLEFT", x, row * rowStep)
            else
                f:SetPoint("TOPLEFT", container, "TOPLEFT", x, -(row * rowStep))
            end

            f.icon:SetTexture(e.v.icon or ICON_DEFAULT)
            if e.v.isDebuff and not e.v.isTarget then
                SetIconBorder(f, BORDER_SELF_DEBUFF)
            else
                SetIconBorder(f, BORDER_DEFAULT)
            end
            if f.targetName then
                -- 目标身上的计时（HoT / DoT / Debuff）统一显示怪物名称
                f.targetName:SetText(e.v.targetName or "")
            end
            if f.click then
                f.click.key = e.key
                f.click:EnableMouse(not unlocked and e.v.auraKind == "hot"
                    and db.clickRecastHoT and true or false)
            end
            if e.v.permanent then
                f.text:SetText("")
            else
                f.text:SetText(FormatTime(e.rem, db.iconSecondMode))
            end
            if e.v.stacks and e.v.stacks > 1 then
                f.stack:SetText(tostring(e.v.stacks))
            else
                f.stack:SetText("")
            end
        end
    end

    if iconMode then
        PlaceIcons(selfList, false)
        PlaceIcons(targetList, true)

        for key, f in pairs(icons) do
            if not seen[key] then
                if f.click then f.click.key = nil end
                if f.targetName then f.targetName:SetText("") end
                f:Hide()
            end
        end
    else
        -- 条形模式：图标列表不显示，只保留中央控制图标
        for key, f in pairs(icons) do
            if f.click then f.click.key = nil end
            if f.targetName then f.targetName:SetText("") end
            f:Hide()
        end
    end

    if ccEntry and ccFrame then
        ccFrame:Show()
        ccIcon.icon:SetTexture(ccEntry.v.icon or ICON_DEFAULT)
        ccFrame.title:SetText(ccEntry.v.name or "")
        if ccEntry.v.permanent then
            ccIcon.text:SetText("")
        elseif db.iconSecondMode or ccEntry.rem >= 10 then
            ccIcon.text:SetText(tostring(math.ceil(ccEntry.rem)))
        else
            ccIcon.text:SetText(string.format("%.1f", ccEntry.rem))
        end
        if ccEntry.v.stacks and ccEntry.v.stacks > 1 then
            ccIcon.stack:SetText(tostring(ccEntry.v.stacks))
        else
            ccIcon.stack:SetText("")
        end
    elseif ccFrame then
        ccFrame.title:SetText("")
        if not ccUnlocked then ccFrame:Hide() end
    end
end

-- /ct cc 诊断：列出自身 Debuff，以及名称判定 / DBC 判定结果
function IM:DebugCC()
    local function msg(s)
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[ChronoTimer]|r " .. tostring(s))
    end
    if not db then msg("图标模块尚未初始化") return end
    msg("显示模式=" .. tostring(db.displayMode)
        .. "，中央控制图标=" .. (db.ccCenter and "开启" or "关闭")
        .. "，图标模块=" .. (enabled and "开启" or "关闭"))
    if not active then msg("active 表不可用") return end
    local count = 0
    for key, v in pairs(active) do
        local ends = v.endsAt or v.expires
        local rem = ends and (ends - GetTime()) or -1
        if rem > 0 and v.isDebuff then
            count = count + 1
            local byId = v.spellId and ChronoTimer and ChronoTimer.IsControlAura
                and ChronoTimer.IsControlAura(v.spellId)
            msg(tostring(v.name) .. "  id=" .. tostring(v.spellId)
                .. "  rem=" .. tostring(math.floor(rem))
                .. "  isTarget=" .. tostring(v.isTarget)
                .. "  名称判定=" .. tostring(IsCCName(v.name))
                .. "  DBC判定=" .. tostring(byId))
        end
    end
    if count == 0 then msg("当前没有自身 Debuff") end
end
