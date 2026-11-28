-- =====================================================================
--  ChronoTimer - Chronometer 重构版（乌龟服 / 需 Nampower）
--  功能：显示玩家自身 Buff / Debuff 的剩余时间
--  界面：沿用 Chronometer 的 CandyBar 计时条外观 + Waterfall 设置面板
--  数据：Nampower 事件 + GetPlayerBuff / GetPlayerBuffTimeLeft
--  仓库：https://github.com/dapinggai/ChronoTimer
-- =====================================================================

ChronoTimer = {}
local CT = ChronoTimer

local GROUP_SELF   = "ChronoTimerSelf"    -- 自身 Buff / Debuff / 图腾：向下排开
local GROUP_TARGET = "ChronoTimerTarget"  -- 目标 Debuff：向上排开
local PREFIX = "CT_"
local ADDON  = "ChronoTimer"

-- ---------------- 依赖库 ----------------
local candy, paint, waterfall, gratuity

local function LoadLibraries()
    if not AceLibrary then return false end
    if AceLibrary:HasInstance("CandyBar-2.2")  then candy     = AceLibrary("CandyBar-2.2")  end
    if AceLibrary:HasInstance("PaintChips-2.0") then paint    = AceLibrary("PaintChips-2.0") end
    if AceLibrary:HasInstance("Waterfall-1.0")  then waterfall = AceLibrary("Waterfall-1.0")  end
    if AceLibrary:HasInstance("Gratuity-2.0")   then gratuity  = AceLibrary("Gratuity-2.0")   end
    return candy and paint and waterfall
end

-- ---------------- 材质 ----------------
local TEXORDER = { "default", "banto", "smooth", "perl", "glaze", "cilo", "charcoal",
                   "diagonal", "fifths", "smoothv2", "Healbot", "LiteStep", "Rocks", "Runes", "Xeon" }

local TEXPATH = {
    ["default"]  = nil,
    ["banto"]    = "Interface\\AddOns\\ChronoTimer\\Textures\\banto",
    ["smooth"]   = "Interface\\AddOns\\ChronoTimer\\Textures\\smooth",
    ["perl"]     = "Interface\\AddOns\\ChronoTimer\\Textures\\perl",
    ["glaze"]    = "Interface\\AddOns\\ChronoTimer\\Textures\\glaze",
    ["cilo"]     = "Interface\\AddOns\\ChronoTimer\\Textures\\cilo",
    ["charcoal"] = "Interface\\AddOns\\ChronoTimer\\Textures\\Charcoal",
    ["diagonal"] = "Interface\\AddOns\\ChronoTimer\\Textures\\Diagonal",
    ["fifths"]   = "Interface\\AddOns\\ChronoTimer\\Textures\\Fifths",
    ["smoothv2"] = "Interface\\AddOns\\ChronoTimer\\Textures\\Smoothv2",
    ["Healbot"]  = "Interface\\AddOns\\ChronoTimer\\Textures\\Healbot",
    ["LiteStep"] = "Interface\\AddOns\\ChronoTimer\\Textures\\LiteStep",
    ["Rocks"]    = "Interface\\AddOns\\ChronoTimer\\Textures\\Rocks",
    ["Runes"]    = "Interface\\AddOns\\ChronoTimer\\Textures\\Runes",
    ["Xeon"]     = "Interface\\AddOns\\ChronoTimer\\Textures\\Xeon",
}

-- 供其它模块（Energy.lua）按材质名取贴图路径，未匹配时回落到默认材质
function ChronoTimer_TexturePath(name)
    return TEXPATH[name] or "Interface\\TargetingFrame\\UI-StatusBar"
end

-- ---------------- 默认配置（对照 Chronometer 默认值） ----------------
local defaults = {
    enabled      = true,
    showBuffs    = true,
    showDebuffs  = true,
    showTotems   = true,
    onlyTrackList = false,
    auraList     = "",
    ignoreList   = "",
    ignoreFood   = true,
    selfBuffsOnly = false,
    trackTarget  = true,
    trackHoTs    = true,
    clickRecastHoT = true,
    trackFireVulnerability = true,
    trackBladeFlurry = true,   -- 盗贼：监控常驻 Buff「剑刃乱舞」
    showEnergy   = true,
    showEnergyBar = true,
    showComboPoints = true,
    showEnergyTick = true,
    energyCombatOnly = false,
    energyTex    = "default",
    showEnslave  = true,
    enslaveDuration = 0,   -- 0 = 自动（固定 300 秒）
    energyWidth  = 150,
    energyHeight = 12,
    comboHeight  = 6,
    comboSpacing = 4,
    comboStyle   = "bar",   -- bar 长条 / diamond 菱形 / circle 圆形
    pvpDR        = true,
    minDuration  = 0,
    maxDuration  = 0,

    barscale     = 1,
    barwidth     = 200,
    barheight    = 18,
    spacing      = 0,
    reverse      = false,
    bartex       = "default",
    ghost        = 0,

    textsize     = 10,
    textcolor    = "white",
    barcolor     = "gray",
    debuffcolor  = "red",
    bgcolor      = "teal",
    bgalpha      = 0.5,
    multicolor   = true,
    classColors  = true,

    showText     = true,
    text         = "$s",

    anchorX      = nil,
    anchorY      = nil,
    minimapAngle = 200,
    hideMinimap  = false,

    -- 图标模式
    displayMode  = "bar",
    iconSize     = 40,
    iconSpacing  = 6,
    iconPerRow   = 8,
    iconTextSize = 0,
    stackTextSize = 0,
    iconSecondMode = false,
    ccCenter     = true,
    ccSize       = 64,
    iconX        = nil,
    iconY        = nil,
    ccX          = nil,
    ccY          = nil,
}

-- ---------------- 运行期状态 ----------------
local db
local active      = {}      -- key -> 光环计时；外部光环按 targetGuid + spellId 独立保存
CT.active = active          -- 供图标模式模块读取
local targetStacks = {}     -- 外部光环最近一次层数（事件可能早于 AURA_CAST_ON_OTHER 到达）
local unitCache   = {}      -- GUID -> 名称、职业、是否玩家
local selfCastAuras = {}    -- spellId -> true/false：该光环最近一次是否由自己（含宠物）施放
local selfCastSeen  = false -- 是否收到过 AURA_CAST_ON_SELF（未开启 Nampower 事件时不做来源过滤）
local scanStamp   = 0
local lastScan    = 0
local pendingScan = false
local initialized = false
local npOK        = false

local anchor
local minimapButton

-- ---------------- 小工具 ----------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[ChronoTimer]|r " .. tostring(msg))
end

local function round(v)
    if v >= 0 then return math.floor(v + 0.5) end
    return math.ceil(v - 0.5)
end

-- 颜色：字符串直接用 PaintChips 名称，表则动态注册
local function ColorName(color, slot)
    if type(color) == "string" then return color end
    if type(color) == "table" then
        local r = tonumber(color[1]) or 1
        local g = tonumber(color[2]) or 1
        local b = tonumber(color[3]) or 1
        local name = "ct_dyn_" .. (slot or "tmp")
        paint:RegisterColor(name, r, g, b)
        return name
    end
    if slot == "textcolor"   then return "white" end
    if slot == "debuffcolor" then return "red"   end
    if slot == "bgcolor"     then return "teal"  end
    return "gray"
end

-- ---------------- 多彩调色板 ----------------
-- Buff 只用冷色 / 生机色，Debuff 只用暖色 / 警示色，色相互不重叠，便于一眼区分
local BUFF_PALETTE = {
    { 0.25, 0.85, 0.45 }, -- 翠绿
    { 0.15, 0.75, 0.95 }, -- 天蓝
    { 0.35, 0.95, 0.85 }, -- 青绿
    { 0.55, 0.85, 0.30 }, -- 黄绿
    { 0.45, 0.65, 1.00 }, -- 淡蓝
    { 0.85, 0.80, 0.25 }, -- 金黄
    { 0.45, 0.95, 0.60 }, -- 薄荷
    { 0.25, 0.60, 0.80 }, -- 灰蓝
}

local DEBUFF_PALETTE = {
    { 0.95, 0.20, 0.20 }, -- 红
    { 0.95, 0.45, 0.10 }, -- 橙
    { 0.80, 0.15, 0.55 }, -- 品红
    { 0.75, 0.25, 0.90 }, -- 紫
    { 0.85, 0.30, 0.30 }, -- 暗红
    { 0.95, 0.60, 0.15 }, -- 琥珀
    { 0.70, 0.10, 0.25 }, -- 酒红
    { 0.95, 0.35, 0.70 }, -- 玫红
}

-- ---------------- 职业颜色（用于框体与设置界面，不影响 Buff 填充色） ----------------
local CLASS_COLORS = {
    WARRIOR = { 0.78, 0.61, 0.43 },
    PALADIN = { 0.96, 0.55, 0.73 },
    HUNTER  = { 0.67, 0.83, 0.45 },
    ROGUE   = { 1.00, 0.96, 0.41 },
    PRIEST  = { 1.00, 1.00, 1.00 },
    SHAMAN  = { 0.14, 0.35, 1.00 },
    MAGE    = { 0.41, 0.80, 0.94 },
    WARLOCK = { 0.58, 0.51, 0.79 },
    DRUID   = { 1.00, 0.49, 0.04 },
}

local CLASS_LOCALE = {
    ["战士"] = "WARRIOR", ["圣骑士"] = "PALADIN", ["猎人"] = "HUNTER",
    ["潜行者"] = "ROGUE", ["盗贼"] = "ROGUE", ["牧师"] = "PRIEST",
    ["萨满祭司"] = "SHAMAN", ["萨满"] = "SHAMAN", ["法师"] = "MAGE",
    ["术士"] = "WARLOCK", ["德鲁伊"] = "DRUID",
}

-- 取单位职业的英文标识（1.12 第二个返回值通常是英文，兼容本地化名称兜底）
local function UnitClassToken(unit)
    local localized, token = UnitClass(unit)
    if token and CLASS_COLORS[token] then return token end
    if localized and CLASS_LOCALE[localized] then return CLASS_LOCALE[localized] end
    if localized and CLASS_COLORS[localized] then return localized end
    return nil
end

local function ClassColorName(token)
    if token and CLASS_COLORS[token] then return "ctclass_" .. token end
    return nil
end

local function StringHash(str)
    local h = 5381
    for i = 1, string.len(str) do
        -- Lua 5.0 没有 % 运算符，使用 math.mod
        h = math.mod(h * 33 + string.byte(str, i), 2147483647)
    end
    return h
end

-- 按法术 ID（无 ID 时按名称）稳定分配颜色，同一个光环颜色不会跳变
local function AuraColorName(isDebuff, spellId, name, fallback)
    if not db.multicolor then
        return ColorName(isDebuff and db.debuffcolor or db.barcolor,
                         isDebuff and "debuffcolor" or "barcolor")
    end
    local pal = isDebuff and DEBUFF_PALETTE or BUFF_PALETTE
    local seed
    if spellId and spellId > 0 then
        seed = "spell:" .. spellId
    else
        seed = "name:" .. tostring(name or fallback or "unknown")
    end
    local idx = math.mod(StringHash(seed), table.getn(pal)) + 1
    return (isDebuff and "ctdebuff" or "ctbuff") .. idx
end

-- ---------------- 法术名 / 图标 ----------------
local spellNameCache, spellIconCache, textureNameCache = {}, {}, {}
local scanTip

local function GetScanTip()
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "ChronoTimerScanTip", UIParent, "GameTooltipTemplate")
    end
    return scanTip
end

local function SpellName(spellId)
    if not spellId or spellId <= 0 then return nil end
    local cached = spellNameCache[spellId]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local name
    if GetSpellRecField then
        name = GetSpellRecField(spellId, "name")
    elseif GetSpellRec then
        local rec = GetSpellRec(spellId)
        if rec then name = rec.name end
    end
    spellNameCache[spellId] = name or false
    return name
end

local function SpellIcon(spellId)
    if not spellId or spellId <= 0 then return nil end
    local cached = spellIconCache[spellId]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local path
    if GetSpellIconTexture and GetSpellRecField then
        local iconId = GetSpellRecField(spellId, "spellIconID")
        if iconId then path = GetSpellIconTexture(iconId) end
    end
    spellIconCache[spellId] = path or false
    return path
end

-- ---------------- 目标定位（GUID → 单位 / 名称） ----------------
local function UnitFromGUID(guid)
    if not guid or not UnitExists then return nil end
    local list = { "target", "mouseover", "player", "pet", "party1", "party2", "party3", "party4" }
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, 40 do
            list[table.getn(list) + 1] = "raid" .. i
        end
    end
    for i = 1, table.getn(list) do
        local u = list[i]
        if UnitExists(u) and GetUnitGUID and GetUnitGUID(u) == guid then
            return u
        end
    end
    return nil
end

local function UnitNameByGUID(guid)
    local u = UnitFromGUID(guid)
    if u then
        local n = UnitName(u)
        if n and n ~= "" then return n end
    end
    if guid and GetUnitField then
        local ok, n = pcall(GetUnitField, guid, "name")
        if ok and n and n ~= "" then return n end
    end
    return nil
end

local function RememberUnit(guid)
    if not guid then return nil end
    local info = unitCache[guid] or {}
    local u = UnitFromGUID(guid)
    info.name = UnitNameByGUID(guid) or info.name
    if u then
        info.classToken = UnitClassToken(u) or info.classToken
        if UnitIsPlayer then info.isPlayer = UnitIsPlayer(u) end
    else
        local okClass, token = pcall(UnitClassToken, guid)
        if okClass and token then info.classToken = token end
        if UnitIsPlayer then
            local okPlayer, isPlayer = pcall(UnitIsPlayer, guid)
            if okPlayer and isPlayer ~= nil then info.isPlayer = isPlayer end
        end
    end
    unitCache[guid] = info
    return info
end

local function CanAttackGUID(guid)
    if not guid or not UnitCanAttack then return false end
    local ok, hostile = pcall(UnitCanAttack, "player", guid)
    if ok and hostile ~= nil then return hostile end
    local u = UnitFromGUID(guid)
    if u then return UnitCanAttack("player", u) and true or false end
    return false
end

local function TooltipBuffName(buffIndex, texture)
    if texture and textureNameCache[texture] then return textureNameCache[texture] end
    local name
    if gratuity then
        gratuity:SetPlayerBuff(buffIndex)
        name = gratuity:GetLine(1)
    else
        local tip = GetScanTip()
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        tip:ClearLines()
        tip:SetPlayerBuff(buffIndex)
        local fs = getglobal("ChronoTimerScanTipTextLeft1")
        name = fs and fs:GetText()
    end
    if name and texture then textureNameCache[texture] = name end
    return name
end

-- ---------------- 文本 ----------------
local function BuildText(name, stacks, targetName)
    if not db.showText then return "" end
    local text = db.text or "$s"
    if text == "$s" and targetName and targetName ~= "" then
        text = "$s - $t"
    end
    text = string.gsub(text, "%$s", name or "")
    text = string.gsub(text, "%$n", tostring(stacks or 1))
    text = string.gsub(text, "%$t", targetName or "")
    return text
end

-- ---------------- 计时条 ----------------
local function ApplyBarSettings(id, isDebuff, spellId, name, fallback, classToken, selfDebuff)
    if db.barscale then candy:SetCandyBarScale(id, db.barscale) end
    candy:SetCandyBarWidth(id,  db.barwidth  or 200)
    candy:SetCandyBarHeight(id, db.barheight or 18)
    candy:SetCandyBarFontSize(id, db.textsize or 10)
    candy:SetCandyBarTexture(id, TEXPATH[db.bartex])
    candy:SetCandyBarColor(id, AuraColorName(isDebuff, spellId, name, fallback))
    candy:SetCandyBarTextColor(id, ColorName(db.textcolor, "textcolor"))
    local classColor = db.classColors and ClassColorName(classToken) or nil
    if selfDebuff and isDebuff then
        -- 自身 Debuff：背景固定暗红，与 Buff、目标 Debuff 区分
        candy:SetCandyBarBackgroundColor(id, "ctbg_selfdebuff", db.bgalpha or 0.5)
    elseif classColor then
        -- 框体背景用职业色，填充色仍保持 Buff/Debuff 分色
        candy:SetCandyBarBackgroundColor(id, classColor, db.bgalpha or 0.5)
    elseif db.multicolor then
        -- 背景同样按类型区分：Buff 墨绿，Debuff 暗红
        candy:SetCandyBarBackgroundColor(id, isDebuff and "ctbg_debuff" or "ctbg_buff",
                                         db.bgalpha or 0.5)
    else
        candy:SetCandyBarBackgroundColor(id, ColorName(db.bgcolor, "bgcolor"), db.bgalpha)
    end
    candy:SetCandyBarReversed(id, db.reverse)
    if db.ghost and db.ghost > 0 then
        candy:SetCandyBarFade(id, db.ghost, true)
    else
        candy:SetCandyBarFade(id, 0, false)
    end
end

-- 计时条模式：层数数字改到图标左侧显示（CandyBar 默认居中盖在图标上）
local function ApplyStackTextLayout(id)
    if not candy or not candy.var then return end
    local h = candy.var.handlers and candy.var.handlers[id]
    local icon = h and h.frame and h.frame.icon
    local fs = icon and icon.text
    if not fs then return end
    local hgt = icon:GetHeight() or 18
    fs:ClearAllPoints()
    fs:SetHeight(hgt)
    fs:SetJustifyH("RIGHT")
    fs:SetJustifyV("MIDDLE")
    fs:SetPoint("RIGHT", icon, "LEFT", -2, 0)
end

local function ApplyStacksText(id, stacks)
    if not candy or not candy:IsCandyBarRegistered(id) then return end
    if stacks and stacks > 1 then
        candy:SetIconText(id, tostring(stacks))
    else
        candy:SetIconText(id, "")
    end
    ApplyStackTextLayout(id)
end

-- 目标身上是否仍有该光环（查不到数据时按“仍在”处理，避免误删）
local function AuraPresent(guid, spellId)
    if not GetUnitField or not guid or not spellId then return true end
    local ok, auras = pcall(GetUnitField, guid, "aura")
    if not ok or type(auras) ~= "table" then return true end
    for _, id in pairs(auras) do
        if id == spellId then return true end
    end
    return false
end

-- 淡出后延迟注销（对应 Chronometer 的 Ghost）
local pendingRemoval = {}

-- 目标光环的延迟移除：叠层刷新时客户端可能先发“移除”再发“新增”，
-- 立刻删除会让计时闪一下就消失，这里给刷新留出取消窗口
local externalRemoval = {}

local function CancelExternalRemoval(key)
    externalRemoval[key] = nil
end

local function CancelPendingRemoval(id)
    for i = table.getn(pendingRemoval), 1, -1 do
        if pendingRemoval[i].id == id then
            table.remove(pendingRemoval, i)
        end
    end
end

local function RemoveBar(key)
    local v = active[key]
    if not v then return end
    active[key] = nil
    targetStacks[key] = nil
    externalRemoval[key] = nil
    candy:StopCandyBar(v.id)
    if db.ghost and db.ghost > 0 then
        pendingRemoval[table.getn(pendingRemoval) + 1] = { id = v.id, at = GetTime() + db.ghost }
    else
        candy:UnregisterCandyBar(v.id)
    end
end

local function UpdatePendingRemovals(now)
    for key, at in pairs(externalRemoval) do
        if not active[key] then
            externalRemoval[key] = nil
        elseif now >= at then
            externalRemoval[key] = nil
            local v = active[key]
            if v and not AuraPresent(v.targetGuid, v.spellId) then
                if CT.auraDebug then
                    Print("[EVT-DEL] " .. tostring(v.name) .. " 事件移除确认，删除")
                end
                RemoveBar(key)
            end
        end
    end
    if table.getn(pendingRemoval) == 0 then return end
    local keep = {}
    for i = 1, table.getn(pendingRemoval) do
        local p = pendingRemoval[i]
        if now >= p.at then
            candy:UnregisterCandyBar(p.id)
        else
            keep[table.getn(keep) + 1] = p
        end
    end
    pendingRemoval = keep
end

function CT.CastTrackedHoT(key, button)
    if button and button ~= "LeftButton" then return end
    if not db or not db.enabled or not db.clickRecastHoT then return end
    local v = active[key]
    if not v or v.auraKind ~= "hot" or not v.targetGuid then return end
    if not CastSpellByName or not v.castName then
        Print("无法补施放：缺少法术名称或 CastSpellByName")
        return
    end
    local ok, err = pcall(CastSpellByName, v.castName, v.targetGuid)
    if not ok then Print("补施放失败：" .. tostring(err)) end
    -- 不在这里重置计时，等待施法成功事件，避免读条技能提前计时
end

local function OnHotBarClick(id, button, key)
    CT.CastTrackedHoT(key, button)
end

local function ApplyBarClick(key)
    local v = active[key]
    if not v or not candy:IsCandyBarRegistered(v.id) then return end
    if v.auraKind == "hot" and db.clickRecastHoT then
        candy:SetCandyBarOnClick(v.id, OnHotBarClick, key)
    else
        candy:SetCandyBarOnClick(v.id, nil)
    end
end

local function CreateBar(key, spellId, name, icon, duration, isDebuff, stacks, buffIndex, isTarget, targetGuid, targetName, auraKind, castName)
    if not duration or duration <= 0 then return end
    if not icon then icon = "Interface\\Icons\\INV_Misc_QuestionMark" end
    local id = PREFIX .. key
    CancelPendingRemoval(id)
    if candy:IsCandyBarRegistered(id) then
        candy:UnregisterCandyBar(id)
    end
    local colorName = AuraColorName(isDebuff, spellId, name, key)
    candy:RegisterCandyBar(id, duration, BuildText(name, stacks, targetName), icon, colorName)
    candy:RegisterCandyBarWithGroup(id, isTarget and GROUP_TARGET or GROUP_SELF)
    local cachedUnit = isTarget and targetGuid and unitCache[targetGuid]
    local classToken = isTarget and (cachedUnit and cachedUnit.classToken or nil) or UnitClassToken("player")
    ApplyBarSettings(id, isDebuff, spellId, name, key, classToken, not isTarget)
    ApplyStacksText(id, stacks)
    candy:StartCandyBar(id, false)
    local now = GetTime()
    active[key] = {
        id = id, name = name, icon = icon, duration = duration, spellId = spellId,
        isDebuff = isDebuff, stacks = stacks, stamp = scanStamp, buffIndex = buffIndex,
        isTarget = isTarget or false, targetGuid = targetGuid, targetName = targetName,
        auraKind = auraKind, castName = castName, classToken = classToken,
        started = now,
        endsAt = now + duration,
    }
    ApplyBarClick(key)
end

local function ApplyGroupAnchor()
    if not candy or not anchor then return end
    -- 图标模式：把计时条组移到屏幕外，仅由图标模式负责显示
    if db.displayMode == "icon" then
        if candy:IsCandyBarGroupRegistered(GROUP_SELF) then
            candy:SetCandyBarGroupPoint(GROUP_SELF, "TOPLEFT", UIParent, "TOPLEFT", -6000, 6000)
        end
        if candy:IsCandyBarGroupRegistered(GROUP_TARGET) then
            candy:SetCandyBarGroupPoint(GROUP_TARGET, "TOPLEFT", UIParent, "TOPLEFT", -6000, 6000)
        end
        return
    end
    -- 自身 Buff / Debuff / 图腾：从锚点向下依次排开
    -- 目标 Debuff：从锚点向上依次排开，两组互不重叠
    -- 计时条左侧有等于高度的图标，整体中心会右偏，这里做半个图标的补偿
    local xo = -(db.barheight or 18) / 2
    if candy:IsCandyBarGroupRegistered(GROUP_SELF) then
        candy:SetCandyBarGroupPoint(GROUP_SELF, "TOP", anchor, "BOTTOM", xo, 0)
        candy:SetCandyBarGroupGrowth(GROUP_SELF, false)
        candy:UpdateCandyBarSpacing(GROUP_SELF, db.spacing or 0)
    end
    if candy:IsCandyBarGroupRegistered(GROUP_TARGET) then
        candy:SetCandyBarGroupPoint(GROUP_TARGET, "BOTTOM", anchor, "TOP", xo, 0)
        candy:SetCandyBarGroupGrowth(GROUP_TARGET, true)
        candy:UpdateCandyBarSpacing(GROUP_TARGET, db.spacing or 0)
    end
    anchor:SetWidth(db.barwidth or 200)
end

-- 锚点框架颜色：按玩家职业着色（关闭职业配色时恢复默认青色）
local function UpdateAnchorColors()
    if not anchor then return end
    local token = db.classColors and UnitClassToken("player") or nil
    local c = token and CLASS_COLORS[token]
    if c then
        anchor:SetBackdropColor(c[1] * 0.25, c[2] * 0.25, c[3] * 0.25, 0.7)
        if anchor.SetBackdropBorderColor then
            anchor:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        end
    else
        anchor:SetBackdropColor(0, 0.45, 0.45, 0.65)
        if anchor.SetBackdropBorderColor then
            anchor:SetBackdropBorderColor(0.30, 1, 0.90, 1)
        end
    end
end

local function RefreshAllBars()
    if not candy then return end
    for key, v in pairs(active) do
        ApplyBarSettings(v.id, v.isDebuff, v.spellId, v.name, v.id, v.classToken, not v.isTarget)
        local barText = BuildText(v.name, v.stacks, v.targetName)
        if v.permanent then barText = barText .. "（常驻）" end
        candy:SetCandyBarText(v.id, barText)
        ApplyStacksText(v.id, v.stacks)
        ApplyBarClick(key)
    end
    ApplyGroupAnchor()
    UpdateAnchorColors()
    if ChronoTimerIconMode then ChronoTimerIconMode:ApplySettings() end
end

local function ClearAll()
    for key in pairs(active) do
        local v = active[key]
        active[key] = nil
        candy:StopCandyBar(v.id)
        candy:UnregisterCandyBar(v.id)
    end
    for i = 1, table.getn(pendingRemoval) do
        candy:UnregisterCandyBar(pendingRemoval[i].id)
    end
    pendingRemoval = {}
    for key in pairs(targetStacks) do
        targetStacks[key] = nil
    end
end

-- ---------------- 自定义监控名单 ----------------
local whitelistNames, whitelistIds = {}, {}

local function TrimName(s)
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

-- 把名单文本拆成名称数组（支持 , ; ， ； 、 及换行分隔）
local function SplitAuraList(text)
    local names = {}
    text = tostring(text or "")
    text = string.gsub(text, "，", ",")
    text = string.gsub(text, "；", ";")
    text = string.gsub(text, "、", ",")
    for name in string.gfind(text, "[^,;\r\n]+") do
        name = TrimName(name)
        if string.len(name) > 0 then
            names[table.getn(names) + 1] = name
        end
    end
    return names
end

-- 名单项既可以是法术 ID（纯数字），也可以是技能名称
local function ParseListEntry(entry)
    if string.find(entry, "^%d+$") then
        local id = tonumber(entry)
        if id and id > 0 then return id, nil end
    end
    return nil, entry
end

local function BuildWhitelist()
    whitelistNames, whitelistIds = {}, {}
    local names = SplitAuraList(db.auraList)
    for i = 1, table.getn(names) do
        local id, name = ParseListEntry(names[i])
        if id then
            whitelistIds[id] = true
        else
            whitelistNames[name] = true
            whitelistNames[string.lower(name)] = true
        end
    end
end

local function IsAuraWanted(name, spellId)
    if not db.onlyTrackList then return true end
    if spellId and whitelistIds[spellId] then return true end
    if not name then return false end
    return whitelistNames[name] == true or whitelistNames[string.lower(name)] == true
end

-- ---------------- 忽略名单 / 吃喝过滤 / 只显示自己施加的 Buff ----------------
local ignoreNames, ignoreIds = {}, {}

local function BuildIgnoreList()
    ignoreNames, ignoreIds = {}, {}
    local names = SplitAuraList(db.ignoreList)
    for i = 1, table.getn(names) do
        local id, name = ParseListEntry(names[i])
        if id then
            ignoreIds[id] = true
        else
            ignoreNames[string.lower(name)] = true
        end
    end
end

-- 命中忽略名单：法术 ID 精确匹配，或名称包含任意关键词（不区分大小写）
local function IsAuraIgnored(name, spellId)
    if spellId and ignoreIds[spellId] then return true end
    if not name then return false end
    local n = string.lower(name)
    for kw in pairs(ignoreNames) do
        if string.find(n, kw, 1, true) then return true end
    end
    return false
end

-- 食物 / 饮料类 Buff 的关键词与图标特征：乌龟服里实际显示为「喝水」「进食」
local FOOD_WORDS = { "进食", "喝水", "食物", "饮料", "饮食", "饱食", "food", "drink", "well fed" }
local FOOD_ICONS = { "inv_drink", "inv_misc_food" }

local function IsFoodDrink(texture, name)
    if texture then
        local t = string.lower(texture)
        for i = 1, table.getn(FOOD_ICONS) do
            if string.find(t, FOOD_ICONS[i], 1, true) then return true end
        end
    end
    if not name then return false end
    local n = string.lower(name)
    for i = 1, table.getn(FOOD_WORDS) do
        if string.find(n, FOOD_WORDS[i], 1, true) then return true end
    end
    return false
end

-- Buff / Debuff 是否允许显示（白名单 + 忽略名单 + 来源 + 吃喝过滤）
local function AuraAllowed(name, texture, isDebuff, spellId)
    if not IsAuraWanted(name, spellId) then return false end
    if IsAuraIgnored(name, spellId) then return false end
    if not isDebuff then
        if db.selfBuffsOnly and selfCastSeen and spellId then
            -- 只有明确判定为他人施放时才隐藏；来源未知的光环先放行，避免误伤
            if selfCastAuras[spellId] == false then return false end
        end
        if db.ignoreFood and IsFoodDrink(texture, name) then return false end
    end
    return true
end

-- ---------------- PvP 控制递减（DR） ----------------
-- 自身中控的剩余时间来自服务端（GetPlayerBuffTimeLeft），本身就是递减后的真实值；
-- 这里只针对“我们施加到玩家目标身上的控制”。
-- 分类与基础时长都取自 Nampower / DBC，不再按技能名称猜测：
--   AURA_CAST_ON_OTHER 第 5 个参数 effectAuraName = DBC EffectApplyAuraName
--   AURA_CAST_ON_OTHER 第 8 个参数 durationMs    = 法术时长（充当施法者时含客户端修正）
--   GetSpellRecField(spellId, "effectApplyAuraName") 作为事件缺参时的权威兜底
-- Nampower 没有 DR 专用 API，因此递减倍率（100% -> 50% -> 25% -> 免疫）与 18 秒窗口
-- 仍是服务端规则的客户端预估，不是 DBC 数据；实际结束以光环消失为准。
-- 注意：香草瘫痪类还有“心跳挣脱”机制，第一次也可能提前醒（随机、不进 DR），
-- 所以这里的时长是上限，实际可能更早结束
local DR_WINDOW = 18

-- EffectApplyAuraName（DBC 权威字段）→ 递减类别
-- 5=困惑（变形/闷棍/凿击/致盲/冰冻陷阱等），6=魅惑，7=恐惧，12=昏迷，26=定身
local AURA_DR_CATEGORY = {
    [5]  = "incap",
    [6]  = "charm",
    [7]  = "fear",
    [12] = "stun",
    [26] = "root",
}

local drState = {}

-- 圣骑士审判 Debuff：Turtle 上随近战命中挂上/刷新，AURA_CAST 事件可能不带施法者归属，
-- 需要单独兜底，否则怪物身上的审判永远没有倒计时
-- 审判 Debuff 固定 10 秒
local JUDGEMENT_DURATION = 10
local JUDGEMENT_NAMES = {
    ["智慧审判"] = true, ["光明审判"] = true, ["十字军审判"] = true, ["公正审判"] = true,
    ["Judgement of Wisdom"] = true, ["Judgement of Light"] = true,
    ["Judgement of the Crusader"] = true, ["Judgement of Justice"] = true,
}

-- 强化灼烧产生的团队共享火焰易伤：30 秒，最多 5 层
local FIRE_VULNERABILITY_ID = 22959
local FIRE_VULNERABILITY_DURATION = 30
local FIRE_VULNERABILITY_MAX_STACKS = 5
local FIRE_VULNERABILITY_CASTS = {
    [2948] = true, [8444] = true, [8445] = true, [8446] = true,
    [10205] = true, [10206] = true, [10207] = true,
    [2136] = true, [2137] = true, [2138] = true, [8412] = true,
    [8413] = true, [10197] = true, [10199] = true,
}

-- 火焰易伤固定 30 秒（不再读取 DBC）
local function FireVulnerabilityDuration()
    return FIRE_VULNERABILITY_DURATION
end

-- 同一个法术可能按效果逐条触发 AURA_CAST_ON_OTHER，短时间去重避免递减被重复累加
local targetCastGuard = {}

local function IsDuplicateTargetCast(spellId, targetGuid)
    local key = tostring(spellId) .. "|" .. tostring(targetGuid)
    local now = GetTime()
    if targetCastGuard[key] and now - targetCastGuard[key] < 0.2 then
        return true
    end
    targetCastGuard[key] = now
    return false
end

-- 判定控制类别：优先事件里的 effectAuraName，缺失时读 Nampower 的 DBC 字段
local function AuraDRCategory(spellId, effectAuraName)
    if effectAuraName and AURA_DR_CATEGORY[effectAuraName] then
        return AURA_DR_CATEGORY[effectAuraName]
    end
    if not spellId or spellId <= 0 or not GetSpellRecField then return nil end
    local ok, fields = pcall(GetSpellRecField, spellId, "effectApplyAuraName")
    if not ok or not fields then return nil end
    if type(fields) == "table" then
        for _, v in pairs(fields) do
            local cat = AURA_DR_CATEGORY[v]
            if cat then return cat end
        end
    else
        return AURA_DR_CATEGORY[fields]
    end
    return nil
end

-- /ct dr 调试：直接打印 Nampower 传回的原始字段，便于核对分类依据
function CT.DebugAuraCast(spellId, casterGuid, targetGuid, effect, effectAuraName, durationMs, capStatus)
    if not CT.drDebug then return end
    local cat = AuraDRCategory(spellId, effectAuraName)
    Print("[DR] " .. tostring(SpellName(spellId) or ("法术 " .. tostring(spellId)))
        .. " id=" .. tostring(spellId)
        .. " effect=" .. tostring(effect)
        .. " auraName=" .. tostring(effectAuraName)
        .. " dur=" .. tostring(durationMs) .. "ms"
        .. " cap=" .. tostring(capStatus)
        .. " 类别=" .. tostring(cat or "无"))
end

-- 供图标模式判断“自身控制类 Debuff”：以 DBC effectApplyAuraName 为准（Nampower），
-- 5/6/7/12/26 分别对应困惑/魅惑/恐惧/昏迷/定身，避免中英文名称差异导致识别失败
local controlSpellCache = {}
function CT.IsControlAura(spellId)
    if not spellId or spellId <= 0 then return false end
    local cached = controlSpellCache[spellId]
    if cached ~= nil then return cached end
    local control = AuraDRCategory(spellId, nil) ~= nil
    controlSpellCache[spellId] = control
    return control
end

local function DRMultiplier(guid, category, now)
    if not guid or not category then return 1 end
    local t = drState[guid]
    if not t then
        t = {}
        drState[guid] = t
    end
    local s = t[category]
    if not s or (now - s.last) > DR_WINDOW then
        t[category] = { last = now, count = 1 }
        return 1
    end
    s.last = now
    s.count = s.count + 1
    if s.count == 2 then return 0.5 end
    if s.count == 3 then return 0.25 end
    return 0
end

-- ---------------- 其他单位上的光环（Nampower，按 GUID 多目标） ----------------
local function ExternalKey(spellId, targetGuid)
    return "t" .. tostring(targetGuid) .. "_" .. tostring(spellId)
end

local function ClearTargetBars(hostileOnly)
    local remove = {}
    for key, v in pairs(active) do
        if v.isTarget and (not hostileOnly or v.isDebuff) then
            remove[table.getn(remove) + 1] = key
        end
    end
    for i = 1, table.getn(remove) do RemoveBar(remove[i]) end
end

local function ClearAuraKind(auraKind)
    local remove = {}
    for key, v in pairs(active) do
        if v.isTarget and v.auraKind == auraKind then
            remove[table.getn(remove) + 1] = key
        end
    end
    for i = 1, table.getn(remove) do RemoveBar(remove[i]) end
end

local function RemoveUnitBars(targetGuid)
    if not targetGuid then return end
    local remove = {}
    for key, v in pairs(active) do
        if v.isTarget and v.targetGuid == targetGuid then
            remove[table.getn(remove) + 1] = key
        end
    end
    for i = 1, table.getn(remove) do RemoveBar(remove[i]) end
    unitCache[targetGuid] = nil
end

local function RemoveExternalAura(targetGuid, spellId)
    if not targetGuid or not spellId then return end
    local key = ExternalKey(spellId, targetGuid)
    local v = active[key]
    if not v then return end
    -- 刚创建或刚被刷新时收到的移除事件，多半是叠层刷新过程中的“先移除后新增”，
    -- 直接删除会让计时闪一下就消失；给后续的新增事件留出取消窗口
    if GetTime() - (v.refreshedAt or v.started or 0) < 0.5 then return end
    -- 光环还在目标身上：这是层数变化而不是消失
    if AuraPresent(targetGuid, spellId) then return end
    externalRemoval[key] = GetTime() + 0.4
end

local function SpellCastName(spellId)
    if GetSpellNameAndRankForId then
        local ok, name = pcall(GetSpellNameAndRankForId, spellId)
        if ok and name and name ~= "" then return name end
    end
    return SpellName(spellId)
end

-- 读取指定 GUID 身上某光环的真实层数（aura 与 auraApplications 槽位一一对应）
local function ReadAuraStacks(guid, spellId)
    if not GetUnitField or not guid or not spellId then return nil end
    local auras = GetUnitField(guid, "aura")
    if type(auras) ~= "table" then return nil end
    local slot
    for i, id in pairs(auras) do
        if id == spellId then slot = i; break end
    end
    if not slot then return nil end
    local apps = GetUnitField(guid, "auraApplications")
    local n
    if type(apps) == "table" then n = apps[slot] end
    -- auraApplications 是 0 基的应用次数：层数 = 次数 + 1
    if type(n) == "number" then
        n = n + 1
    else
        n = 1
    end
    if n < 1 then n = 1 end
    return n
end

-- 外部 HoT / DoT / Debuff：建立或刷新对应目标的计时条
local function ApplyTargetDebuff(spellId, targetGuid, duration, stacks, effectAuraName, auraKind, castName)
    if not spellId or spellId <= 0 or not targetGuid then return end
    if not duration or duration <= 0 then return end
    if duration < (db.minDuration or 0) then return end
    if db.maxDuration and db.maxDuration > 0 and duration > db.maxDuration then return end
    auraKind = auraKind or "debuff"
    local key = ExternalKey(spellId, targetGuid)
    local old = active[key]
    local cached = targetStacks[key]
    local prevStacks = old and old.stacks or nil
    local previousName = old and old.targetName or nil
    local previousCast = old and old.castName or nil
    -- AURA_CAST_ON_OTHER 不带层数信息：使用近期实际新增事件或旧条层数
    if not stacks or stacks <= 1 then
        if cached and cached.at and GetTime() - cached.at < 2 then
            stacks = cached.stacks
        elseif prevStacks and prevStacks > 1 then
            stacks = prevStacks
        end
    end
    -- 层数以客户端光环字段为准：叠层事件在第 3 层以后可能不再触发
    if auraKind == "shared" then
        local real = ReadAuraStacks(targetGuid, spellId)
        if real then stacks = real end
    end
    local name = SpellName(spellId) or ("法术 " .. spellId)
    if not IsAuraWanted(name, spellId) then
        if old then RemoveBar(key) end
        return
    end
    if IsAuraIgnored(name, spellId) then
        if old then RemoveBar(key) end
        return
    end
    local info = RememberUnit(targetGuid) or {}
    -- 玩家目标上的控制类 Debuff 按 DBC 光环类型分档，再按递减规则估算实际时长
    if auraKind ~= "hot" and db.pvpDR and info.isPlayer then
        local cat = AuraDRCategory(spellId, effectAuraName)
        if cat then
            duration = duration * DRMultiplier(targetGuid, cat, GetTime())
            if duration < 0.5 then return end
        end
    end
    local targetName = info.name or previousName or "未知目标"
    castName = castName or previousCast or SpellCastName(spellId)
    if old then
        -- 光环被刷新：原地续满时长，代替“先删除再新建”，避免计时闪一下
        local now = GetTime()
        old.duration = duration
        old.endsAt = now + duration
        old.refreshedAt = now
        old.stacks = stacks
        old.name = name
        old.icon = SpellIcon(spellId) or old.icon
        old.targetName = targetName
        old.castName = castName
        old.auraKind = auraKind
        CancelExternalRemoval(key)
        candy:SetCandyBarTime(old.id, duration)
        candy:StartCandyBar(old.id, false)
        candy:SetCandyBarText(old.id, BuildText(name, stacks, targetName))
        ApplyStacksText(old.id, stacks)
        return
    end
    CreateBar(key, spellId, name, SpellIcon(spellId), duration, auraKind ~= "hot", stacks,
        nil, true, targetGuid, targetName, auraKind, castName)
end

-- 判断施法者是否为玩家本人 / 宠物 / 召唤物 / 图腾
local function IsCasterSelf(casterGuid)
    if not casterGuid or type(casterGuid) ~= "string" then return false end
    -- 兼容事件参数为 "player" / "pet" 等单位标记的情况
    if casterGuid == "player" or casterGuid == "pet" then
        casterGuid = GetUnitGUID and GetUnitGUID(casterGuid)
        if not casterGuid then return false end
    end
    local playerGuid = GetUnitGUID and GetUnitGUID("player")
    if not playerGuid then return false end
    if casterGuid == playerGuid then return true end
    if GetUnitGUID and GetUnitGUID(casterGuid .. "owner") == playerGuid then return true end
    if GetUnitField then
        if GetUnitField(casterGuid, "charm") == playerGuid then return true end
        if GetUnitField(casterGuid, "createdBy") == playerGuid then return true end
    end
    return false
end

-- 1.12 无法直接取目标 Debuff 名称，用图标粗略确认该 Debuff 仍在目标身上
local function TargetHasIcon(icon)
    if not icon or string.find(icon, "INV_Misc_QuestionMark", 1, true) then return true end
    local want = string.lower(icon)
    for i = 1, 16 do
        local tex = UnitDebuff("target", i)
        if not tex then break end
        if string.lower(tex) == want then return true end
    end
    return false
end

-- 目标身上现有的审判 Debuff（spellId -> true），由 Nampower 原始光环字段刷新
local judgementSeen = {}

-- 圣骑士审判兜底：action = "cast" 判断归属 / "added" 建条 / "hit" 近战命中刷新
-- 集中到一个函数，避免主事件闭包新增过多 upvalue（Lua 5.0 单闭包上限 32）
local function HandleJudgement(action, spellId, targetGuid, stacks)
    if UnitClassToken("player") ~= "PALADIN" then return false end

    if action == "cast" then
        local nm = SpellName(spellId)
        return nm ~= nil and JUDGEMENT_NAMES[nm] == true
    end

    if action == "hit" then
        local now = GetTime()
        for key, v in pairs(active) do
            if v.isTarget and v.targetGuid == targetGuid and JUDGEMENT_NAMES[v.name]
                and (judgementSeen[v.spellId] or TargetHasIcon(v.icon)) then
                local dur = v.duration or JUDGEMENT_DURATION
                if dur and dur > 0 then
                    v.duration = dur
                    v.endsAt = now + dur
                    candy:SetCandyBarTimeLeft(v.id, dur)
                end
            end
        end
        return true
    end

    -- action == "added"：审判 Debuff 首次出现在目标身上
    local nm = SpellName(spellId)
    if not nm or not JUDGEMENT_NAMES[nm] then return false end
    local key = ExternalKey(spellId, targetGuid)
    if active[key] then return false end
    local dur = JUDGEMENT_DURATION
    if not dur or dur <= 0 then return false end
    if dur < (db.minDuration or 0) then return false end
    if (db.maxDuration or 0) > 0 and dur > db.maxDuration then return false end
    ApplyTargetDebuff(spellId, targetGuid, dur, stacks, nil, "debuff")
    return active[key] ~= nil
end

-- 用 GetUnitField 直接读目标光环，绕开事件不带归属的问题
local function ScanJudgement(now)
    if UnitClassToken("player") ~= "PALADIN" then return end
    if not GetUnitField then return end
    local guid = GetUnitGUID and GetUnitGUID("target")
    if not guid then return end

    local auras = GetUnitField(guid, "aura")
    local present = {}
    if type(auras) == "table" then
        for _, id in pairs(auras) do
            if type(id) == "number" and id > 0 then
                local nm = SpellName(id)
                if nm and JUDGEMENT_NAMES[nm] then
                    present[id] = true
                    local key = ExternalKey(id, guid)
                    if not active[key] then
                        local dur = JUDGEMENT_DURATION
                        if dur and dur > 0 then
                            ApplyTargetDebuff(id, guid, dur, 1, nil, "debuff")
                            local nv = active[key]
                            if nv then nv.judgement = true end
                        end
                    end
                end
            end
        end
    end

    judgementSeen = present

    local gone = {}
    for key, v in pairs(active) do
        if v.isTarget and v.judgement and v.targetGuid == guid and not present[v.spellId] then
            gone[table.getn(gone) + 1] = key
        end
    end
    for i = 1, table.getn(gone) do
        RemoveBar(gone[i])
    end
end

-- 火焰易伤等团队共享叠层光环：定时按客户端光环字段校正层数
local function RefreshSharedStacks()
    if not GetUnitField then return end
    for _, v in pairs(active) do
        if v.auraKind == "shared" and v.targetGuid then
            local n = ReadAuraStacks(v.targetGuid, v.spellId)
            if n and n ~= v.stacks then
                v.stacks = n
                candy:SetCandyBarText(v.id, BuildText(v.name, n, v.targetName))
                ApplyStacksText(v.id, n)
            end
        end
    end
end

-- ---------------- 扫描 ----------------
-- 盗贼「剑刃乱舞」：乌龟服为持续到取消的常驻 Buff（无剩余时间），独立监控。
-- ProcessBladeFlurry 在图腾处理之后定义（依赖 HideBarTimerText / PERMANENT_TOTEM），这里前向声明。
local ProcessBladeFlurry
local BLADE_FLURRY_IDS = { [13877] = true }
local function IsBladeFlurry(spellId, name)
    if spellId and BLADE_FLURRY_IDS[spellId] then return true end
    if name and string.find(name, "剑刃乱舞", 1, true) then return true end
    return false
end

local lastSkipPrint = 0
local function DebugSkipAura(texture, reason)
    if not CT.auraDebug then return end
    local now = GetTime()
    if now - lastSkipPrint < 2 then return end
    lastSkipPrint = now
    Print("[SKIP] " .. tostring(texture) .. " " .. reason)
end

local function ProcessAura(buffIndex, isDebuff, stamp)
    -- 盗贼剑刃乱舞：常驻 Buff，剩余时间可能返回 nil / 0 / 负数，先于一切时长过滤处理
    local bfRogue = (not isDebuff) and db.trackBladeFlurry and UnitClassToken("player") == "ROGUE"
    if bfRogue and ProcessBladeFlurry then
        local sid = GetPlayerBuffID and GetPlayerBuffID(buffIndex) or nil
        if sid and BLADE_FLURRY_IDS[sid] then
            ProcessBladeFlurry(buffIndex, sid, SpellName(sid), GetPlayerBuffTexture(buffIndex), stamp)
            return
        end
    end

    local timeLeft = GetPlayerBuffTimeLeft(buffIndex)
    if not timeLeft or timeLeft <= 0 then
        -- 名称兜底：自定义 ID 或取不到 ID 时按中文名识别
        if bfRogue and ProcessBladeFlurry then
            local tex = GetPlayerBuffTexture(buffIndex)
            local sid = GetPlayerBuffID and GetPlayerBuffID(buffIndex) or nil
            local nm = SpellName(sid) or TooltipBuffName(buffIndex, tex)
            if IsBladeFlurry(sid, nm) then
                ProcessBladeFlurry(buffIndex, sid, nm, tex, stamp)
                return
            end
        end
        if not timeLeft then
            DebugSkipAura(GetPlayerBuffTexture(buffIndex), "无剩余时间")
            return
        end
    end

    local texture = GetPlayerBuffTexture(buffIndex)
    local spellId
    if GetPlayerBuffID then spellId = GetPlayerBuffID(buffIndex) end

    local key
    if spellId and spellId > 0 then
        key = (isDebuff and "d" or "b") .. spellId
    else
        key = (isDebuff and "d" or "b") .. (texture or "unknown")
        key = string.gsub(key, "\\", "_")
    end

    local maxDur = db.maxDuration or 0
    if timeLeft <= 0 or timeLeft < (db.minDuration or 0)
        or (maxDur > 0 and timeLeft > maxDur) then
        DebugSkipAura(texture, "剩余 " .. tostring(timeLeft) .. " 秒被时长过滤")
        if active[key] then RemoveBar(key) end
        return
    end

    local stacks
    if GetPlayerBuffApplications then
        stacks = GetPlayerBuffApplications(buffIndex)
    end
    if stacks and stacks < 1 then stacks = nil end

    local v = active[key]
    local name = v and v.name
    if not name then
        name = SpellName(spellId) or TooltipBuffName(buffIndex, texture)
               or (spellId and ("法术 " .. spellId)) or "未知光环"
    end
    -- 白名单 / 忽略名单 / 只显示自己施加的 Buff / 吃喝过滤
    if not AuraAllowed(name, texture, isDebuff, spellId or (v and v.spellId)) then
        DebugSkipAura(texture, tostring(name) .. " 被名单 / 来源 / 吃喝过滤")
        if v then RemoveBar(key) end
        return
    end

    if v then
        v.stamp = stamp
        v.buffIndex = buffIndex
        if timeLeft > v.duration + 0.5 then
            -- 光环被刷新，时长变长：重建计时条
            RemoveBar(key)
            v = nil
        else
            if v.stacks ~= stacks then
                v.stacks = stacks
                candy:SetCandyBarText(v.id, BuildText(v.name, stacks))
                ApplyStacksText(v.id, stacks)
            end
            -- 用服务端剩余时间校正本地倒计时
            if timeLeft <= v.duration then
                candy:SetCandyBarTimeLeft(v.id, timeLeft)
                v.endsAt = GetTime() + timeLeft
            end
        end
    end

    if not v then
        local icon = SpellIcon(spellId) or texture
        CreateBar(key, spellId, name, icon, timeLeft, isDebuff, stacks, buffIndex)
    end
end

-- ---------------- 萨满图腾（常驻图腾 + 施放计时） ----------------
local TOTEM_SLOTS = 4
local PERMANENT_TOTEM = 86400

-- slot: 1=大地 2=火焰 3=水 4=空气（与 GetTotemInfo 槽位一致）
local TOTEM_LIST = {
    { slot = 1, duration = 45,  icon = "Interface\\Icons\\Spell_Nature_StrengthOfEarthTotem02", en = "Earthbind Totem",           zh = "地缚图腾" },
    { slot = 1, duration = 120, icon = "Interface\\Icons\\Spell_Nature_TremorTotem",             en = "Tremor Totem",              zh = "战栗图腾" },
    { slot = 1, duration = 120, icon = "Interface\\Icons\\Spell_Nature_EarthBindTotem",          en = "Strength of Earth Totem",   zh = "大地之力图腾" },
    { slot = 1, duration = 120, icon = "Interface\\Icons\\Spell_Nature_StoneSkinTotem",          en = "Stoneskin Totem",           zh = "石肤图腾" },
    { slot = 1, duration = 15,  icon = "Interface\\Icons\\Spell_Nature_StoneClawTotem",          en = "Stoneclaw Totem",           zh = "石爪图腾" },
    { slot = 2, duration = 55,  icon = "Interface\\Icons\\Spell_Fire_SearingTotem",              en = "Searing Totem",             zh = "灼热图腾" },
    { slot = 2, duration = 5,   icon = "Interface\\Icons\\Spell_Fire_SealOfFire",                en = "Fire Nova Totem",           zh = "火焰新星图腾" },
    { slot = 2, duration = 20,  icon = "Interface\\Icons\\Spell_Fire_SelfDestruct",              en = "Magma Totem",               zh = "熔岩图腾" },
    { slot = 2, duration = 120, icon = "Interface\\Icons\\Spell_FrostResistanceTotem_01",        en = "Frost Resistance Totem",    zh = "抗寒图腾" },
    { slot = 2, duration = 120, icon = "Interface\\Icons\\Spell_Nature_GuardianWard",            en = "Flametongue Totem",         zh = "火舌图腾" },
    { slot = 3, duration = 60,  icon = "Interface\\Icons\\Spell_Nature_ManaRegenTotem",          en = "Mana Spring Totem",         zh = "法力之泉图腾" },
    { slot = 3, duration = 60,  icon = "Interface\\Icons\\INV_Spear_04",                         en = "Healing Stream Totem",      zh = "治疗之泉图腾" },
    { slot = 3, duration = 120, icon = "Interface\\Icons\\Spell_FireResistanceTotem_01",         en = "Fire Resistance Totem",     zh = "抗火图腾" },
    { slot = 3, duration = 120, icon = "Interface\\Icons\\Spell_Nature_PoisonCleansingTotem",    en = "Poison Cleansing Totem",    zh = "清毒图腾" },
    { slot = 3, duration = 120, icon = "Interface\\Icons\\Spell_Nature_DiseaseCleansingTotem",   en = "Disease Cleansing Totem",   zh = "祛病图腾" },
    { slot = 4, duration = 120, icon = "Interface\\Icons\\Spell_Nature_Brilliance",              en = "Tranquil Air Totem",        zh = "宁静之风图腾" },
    { slot = 4, duration = 45,  icon = "Interface\\Icons\\Spell_Nature_GroundingTotem",          en = "Grounding Totem",           zh = "根基图腾" },
    { slot = 4, duration = 120, icon = "Interface\\Icons\\Spell_Nature_Windfury",                en = "Windfury Totem",            zh = "风怒图腾" },
    { slot = 4, duration = 120, icon = "Interface\\Icons\\Spell_Nature_InvisibilityTotem",       en = "Grace of Air Totem",        zh = "风之优雅图腾" },
    { slot = 4, duration = 120, icon = "Interface\\Icons\\Spell_Nature_NatureResistanceTotem",   en = "Nature Resistance Totem",   zh = "自然抗性图腾" },
    { slot = 4, duration = 120, icon = "Interface\\Icons\\Spell_Nature_EarthBind",               en = "Windwall Totem",            zh = "风墙图腾" },
    { slot = 4, duration = 300, icon = "Interface\\Icons\\Spell_Nature_RemoveCurse",             en = "Sentry Totem",              zh = "岗哨图腾" },
}

local TOTEM_INFO = {}
for i = 1, table.getn(TOTEM_LIST) do
    local t = TOTEM_LIST[i]
    TOTEM_INFO[string.lower(t.en)] = t
    TOTEM_INFO[t.zh] = t
end

-- 图腾掌握天赋加成（+20% 持续时间）。剔除内置图腾助手后由计时模块自行检测，
-- 不再依赖 ArchiTotem 的全局变量。挂在 CT 上避免占用文件的局部变量名额。
CT.totemicMasteryBonus = 0
function CT.UpdateTotemicMasteryBonus()
    if UnitClassToken and UnitClassToken("player") ~= "SHAMAN" then
        CT.totemicMasteryBonus = 0
        return
    end
    if not GetNumTalentTabs or not GetNumTalents or not GetTalentInfo then
        CT.totemicMasteryBonus = 0
        return
    end
    local numTabs = GetNumTalentTabs() or 0
    local has = false
    for tab = 1, numTabs do
        local n = GetNumTalents(tab) or 0
        for i = 1, n do
            local name, _, _, _, rank = GetTalentInfo(tab, i)
            local ok = name and (
                name == "Totemic Mastery" or name == "图腾掌握" or name == "图腾精通"
                or (string.find(tostring(name), "Totem") and string.find(tostring(name), "Master"))
                or (string.find(tostring(name), "图腾") and (string.find(tostring(name), "掌") or string.find(tostring(name), "精通") or string.find(tostring(name), "统御")))
            )
            if ok and (rank or 0) > 0 then
                has = true
                break
            end
        end
        if has then break end
    end
    CT.totemicMasteryBonus = has and 0.20 or 0
end

-- ---------------- 术士：奴役恶魔（恶魔叛变倒计时） ----------------
local ENSLAVE_SPELLS = { [1098] = true, [11725] = true, [11726] = true }
local ENSLAVE_ICON = "Interface\\Icons\\Spell_Shadow_EnslaveDemon"

-- 兼容自定义等级：按名称兜底识别奴役恶魔
local function IsEnslaveSpell(spellId)
    if not spellId or spellId <= 0 then return false end
    if ENSLAVE_SPELLS[spellId] then return true end
    local name = SpellName(spellId)
    if not name then return false end
    if string.find(name, "奴役恶魔") then return true end
    if string.find(string.lower(name), "enslave demon") then return true end
    return false
end

local function OnEnslaveCast(spellId)
    if not initialized or not db.enabled or db.showEnslave == false then return end
    if UnitClassToken("player") ~= "WARLOCK" then return end
    if not IsEnslaveSpell(spellId) then return end
    local duration = tonumber(db.enslaveDuration) or 0
    if duration <= 0 then duration = 300 end
    if duration < 30 then duration = 30 end
    CreateBar("enslave", spellId, "恶魔叛变", SpellIcon(spellId) or ENSLAVE_ICON,
        duration, true)
    local bar = active["enslave"]
    if bar then bar.isEnslave = true end
end

-- 一键施放时 GetTotemInfo 可能还没刷新，按 SPELL_GO_SELF 记录补位
local totemCasts = {}

local function HideBarTimerText(id)
    local h = candy.var and candy.var.handlers and candy.var.handlers[id]
    local f = h and h.frame
    if f and f.timertext then f.timertext:Hide() end
end

local function RecallTotems()
    for slot = 1, TOTEM_SLOTS do totemCasts[slot] = nil end
    local remove = {}
    for key, v in pairs(active) do
        if v.isTotem then remove[table.getn(remove) + 1] = key end
    end
    for i = 1, table.getn(remove) do RemoveBar(remove[i]) end
end

local ScanAuras

local function OnTotemCast(spellId)
    if not initialized or not db.showTotems or not spellId then return end
    local name = nil
    if GetSpellNameAndRankForId then
        name = GetSpellNameAndRankForId(spellId)
    end
    if spellId == 36936 or name == "图腾召回" or (name and string.lower(name) == "totemic recall") then
        RecallTotems()
        return
    end
    if not name then return end
    name = string.gsub(name, "%s*%(.*%)$", "")
    local info = TOTEM_INFO[name] or TOTEM_INFO[string.lower(name)]
    if not info then return end
    totemCasts[info.slot] = {
        name = name, icon = SpellIcon(spellId) or info.icon,
        started = GetTime(),
        -- 补位时长用内置图腾表，真实剩余时间仍以 GetTotemInfo 为准
        duration = info.duration,
        permanent = false,
    }
    ScanAuras(true)
end

local function ProcessTotem(slot, now, seen)
    local haveTotem, name, startTime, duration, icon = false, nil, nil, nil, nil
    if GetTotemInfo then
        haveTotem, name, startTime, duration, icon = GetTotemInfo(slot)
    end

    local cast = totemCasts[slot]
    local permanent = false
    local useCast = false
    if cast then
        -- 倒计时按施放时刻 + 表中时长推算
        useCast = true
        if not cast.permanent then
            local castDuration = cast.duration
            if castDuration and CT.totemicMasteryBonus and CT.totemicMasteryBonus > 0 then
                castDuration = castDuration * (1 + CT.totemicMasteryBonus)
            end
            local left = cast.started + (castDuration or 0) - now
            if left <= 0 then
                totemCasts[slot] = nil
                return
            end
        end
        name, icon = cast.name, cast.icon
        startTime, duration = cast.started, cast.duration
        permanent = cast.permanent
    end
    if not useCast then
        if haveTotem then
            -- 常驻图腾没有持续时间：一直显示，不做倒计时
            permanent = (not duration) or duration <= 0 or (not startTime) or startTime <= 0
        elseif not cast then
            return
        end
    end

    -- 归一化，避免 nil 与默认值不一致导致每帧重建
    if not name then name = "图腾 " .. slot end
    -- 图标：部分客户端 GetTotemInfo 返回数字图标 ID 且没有 GetSpellIconTexture，
    -- 转不出贴图路径时回落到内置图腾表，避免图标空白或只显示一部分
    if type(icon) == "number" then
        icon = GetSpellIconTexture and GetSpellIconTexture(icon) or nil
    end
    local plain = string.gsub(name, "%s*%(.*%)$", "")
    local info = TOTEM_INFO[name] or TOTEM_INFO[plain] or TOTEM_INFO[string.lower(plain)]
    if type(icon) ~= "string" or icon == "" then
        icon = (info and info.icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    -- 时长以内置图腾表为准（部分客户端 GetTotemInfo 返回值不准）
    if not permanent and info and type(info.duration) == "number" and info.duration > 0 then
        duration = info.duration
    end
    -- 图腾掌握天赋延长持续时间
    if not permanent and duration and CT.totemicMasteryBonus and CT.totemicMasteryBonus > 0 then
        duration = duration * (1 + CT.totemicMasteryBonus)
    end

    local remain
    if permanent then
        remain = PERMANENT_TOTEM
    else
        remain = startTime + duration - now
        if remain <= 0 then return end
        if remain < (db.minDuration or 0) then return end
        if db.maxDuration and db.maxDuration > 0 and remain > db.maxDuration then return end
    end

    local key = "totem" .. slot
    seen[key] = true

    local v = active[key]
    -- 图腾被替换（名称、图标或常驻状态变化）时重建计时条
    if v and (v.name ~= name or v.icon ~= icon or (v.permanent or false) ~= permanent) then
        RemoveBar(key)
        v = nil
    end
    if v then
        if not permanent then
            if remain > v.duration + 1 then
                RemoveBar(key)
                v = nil
            elseif remain <= v.duration then
                candy:SetCandyBarTimeLeft(v.id, remain)
                v.endsAt = now + remain
            end
        end
    end
    if not v then
        CreateBar(key, nil, name, icon, remain, false, nil, nil, false, nil)
        local bar = active[key]
        if bar then
            bar.isTotem = true
            bar.permanent = permanent
            if permanent then
                candy:SetCandyBarText(bar.id, BuildText(name, nil) .. "（常驻）")
                HideBarTimerText(bar.id)
            end
        end
    end
end

-- 盗贼：剑刃乱舞（常驻 Buff）。复用图腾的"（常驻）+ 隐藏时间文本"做法，
-- 用超长时长注册计时条，再隐藏剩余时间文本；图标模式按 permanent 不显示倒计时。
-- 取消 Buff 后本帧不再被调用，stamp 不更新，由 ScanAuras 的过期清理自动移除。
ProcessBladeFlurry = function(buffIndex, spellId, name, texture, stamp)
    local key = "bladeflurry"
    local v = active[key]
    if v then
        v.stamp = stamp
        v.buffIndex = buffIndex
        return
    end
    local icon = SpellIcon(spellId) or texture
    CreateBar(key, spellId, name or "剑刃乱舞", icon, PERMANENT_TOTEM, false, nil, buffIndex)
    local bar = active[key]
    if bar then
        bar.permanent = true
        bar.isBladeFlurry = true
        candy:SetCandyBarText(bar.id, BuildText(bar.name, nil) .. "（常驻）")
        HideBarTimerText(bar.id)
        if CT.auraDebug then
            Print("[BF] 剑刃乱舞 常驻监控 sid=" .. tostring(spellId) .. " tex=" .. tostring(texture))
        end
    end
end

local function ScanTotems(now)
    local stale = {}
    if not db.showTotems then
        for key, v in pairs(active) do
            if v.isTotem then stale[table.getn(stale) + 1] = key end
        end
        for slot = 1, TOTEM_SLOTS do totemCasts[slot] = nil end
    else
        local seen = {}
        for slot = 1, TOTEM_SLOTS do
            ProcessTotem(slot, now, seen)
        end
        for key, v in pairs(active) do
            if v.isTotem and not seen[key] then
                stale[table.getn(stale) + 1] = key
            end
        end
    end
    for i = 1, table.getn(stale) do
        RemoveBar(stale[i])
    end
end

ScanAuras = function(force)
    if not initialized or not db or not db.enabled then return end
    local now = GetTime()
    if not force and (now - lastScan) < 0.1 then
        pendingScan = true
        return
    end
    lastScan = now
    pendingScan = false
    scanStamp = scanStamp + 1
    local stamp = scanStamp

    if db.showBuffs then
        for i = 0, 31 do
            local bidx = GetPlayerBuff(i, "HELPFUL")
            if not bidx or bidx == -1 then break end
            ProcessAura(bidx, false, stamp)
        end
    end
    if db.showDebuffs then
        for i = 0, 15 do
            local bidx = GetPlayerBuff(i, "HARMFUL")
            if not bidx or bidx == -1 then break end
            ProcessAura(bidx, true, stamp)
        end
    end

    -- 图腾：读取 GetTotemInfo，按剩余时间维护计时条
    ScanTotems(now)

    -- 圣骑士审判：直接读目标光环字段，维护审判 Debuff 计时
    ScanJudgement(now)

    -- 火焰易伤：叠层事件不可靠，按光环字段校正层数
    RefreshSharedStacks()

    -- 术士奴役恶魔：关闭监控、宠物消失/更换时立即移除
    local ebar = active["enslave"]
    if ebar then
        local pg = GetUnitGUID and GetUnitGUID("pet")
        local age = now - (ebar.started or now)
        if db.showEnslave == false then
            RemoveBar("enslave")
        elseif age >= 2.5 then
            -- 施放后留出宠物切换的缓冲，避免刚召唤就被判定为已消失
            if not pg then
                RemoveBar("enslave")
            elseif not ebar.petGuid then
                ebar.petGuid = pg
            elseif ebar.petGuid ~= pg then
                RemoveBar("enslave")
            end
        end
    end

    -- 清理本帧没再出现的光环（目标 debuff / 图腾由各自逻辑维护）
    local stale = {}
    for key, v in pairs(active) do
        if not v.isTarget and not v.isTotem and not v.isEnslave and v.stamp ~= stamp then
            stale[table.getn(stale) + 1] = key
        end
    end
    for i = 1, table.getn(stale) do
        RemoveBar(stale[i])
    end

    -- Nampower：用 GUID 读取玩家光环原始字段，做最后一次权威校验
    if GetUnitField and GetUnitGUID then
        local guid = GetUnitGUID("player")
        if guid then
            local auras = GetUnitField(guid, "aura")
            if type(auras) == "table" then
                local present, total = {}, 0
                for _, spellId in pairs(auras) do
                    total = total + 1
                    if type(spellId) == "number" and spellId > 0 then
                        present[spellId] = true
                    end
                end
                if total > 0 then
                    local gone = {}
                    for key, v in pairs(active) do
                        if not v.isTarget and not v.isTotem and not v.isEnslave and not v.isBladeFlurry and v.spellId and v.spellId > 0
                            and not present[v.spellId] then
                            gone[table.getn(gone) + 1] = key
                        end
                    end
                    for i = 1, table.getn(gone) do
                        RemoveBar(gone[i])
                    end
                end
            end
        end
    end

    -- 外部光环：自然到期、死亡和实际消失按 GUID 清理；查不到单位不等于死亡
    local externalGuids, expired = {}, {}
    for key, v in pairs(active) do
        if v.isTarget then
            if v.endsAt and v.endsAt <= now then
                if CT.auraDebug then
                    Print("[EXP] " .. tostring(v.name) .. " 到期删除")
                end
                expired[table.getn(expired) + 1] = key
            elseif v.targetGuid then
                externalGuids[v.targetGuid] = true
            end
        end
    end
    for i = 1, table.getn(expired) do RemoveBar(expired[i]) end

    if GetUnitField then
        for guid in pairs(externalGuids) do
            local info = unitCache[guid]
            if not info or not info.name then info = RememberUnit(guid) end
            if info then
                for key, v in pairs(active) do
                    if v.isTarget and v.targetGuid == guid then
                        local changed = false
                        if info.name and v.targetName ~= info.name then
                            v.targetName = info.name
                            candy:SetCandyBarText(v.id, BuildText(v.name, v.stacks, v.targetName))
                            changed = true
                        end
                        if info.classToken and v.classToken ~= info.classToken then
                            v.classToken = info.classToken
                            changed = true
                        end
                        if changed then
                            ApplyBarSettings(v.id, v.isDebuff, v.spellId, v.name, v.id, v.classToken, not v.isTarget)
                        end
                    end
                end
            end

            local exists = false
            if UnitExists then
                local ok, result = pcall(UnitExists, guid)
                exists = ok and result or false
            end
            local unit = UnitFromGUID(guid)
            if unit then exists = true end
            if exists then
                local dead = false
                if UnitIsDeadOrGhost then
                    local ok, result = pcall(UnitIsDeadOrGhost, guid)
                    dead = ok and result or false
                    if not dead and unit then dead = UnitIsDeadOrGhost(unit) or false end
                end
                if dead then
                    RemoveUnitBars(guid)
                else
                    local ok, auras = pcall(GetUnitField, guid, "aura")
                    if ok and type(auras) == "table" then
                        local present = {}
                        for _, spellId in pairs(auras) do
                            if type(spellId) == "number" and spellId > 0 then
                                present[spellId] = true
                            end
                        end
                        local gone = {}
                        for key, v in pairs(active) do
                            if v.isTarget and v.targetGuid == guid and v.spellId then
                                if now - (v.refreshedAt or v.started or now) > 0.75
                                    and not present[v.spellId] then
                                    if CT.auraDebug then
                                        Print("[GONE] " .. tostring(v.name) .. " 光环字段已缺失，扫描删除")
                                    end
                                    gone[table.getn(gone) + 1] = key
                                elseif present[v.spellId] then
                                    -- 层数会随消耗变化且客户端不一定发事件：每次扫描按光环字段校正
                                    local real = ReadAuraStacks(guid, v.spellId)
                                    if real and v.stacks ~= real then
                                        v.stacks = real
                                        targetStacks[key] = { guid = guid, stacks = real, at = now }
                                        candy:SetCandyBarText(v.id, BuildText(v.name, real, v.targetName))
                                        ApplyStacksText(v.id, real)
                                    end
                                end
                            end
                        end
                        for i = 1, table.getn(gone) do RemoveBar(gone[i]) end
                    end
                end
            end
        end
    end
end

-- 名单 / 监控模式变化后：重算名单、立即清理不在名单里的计时条，再扫描一次
local function ApplyWhitelistChange()
    BuildWhitelist()
    BuildIgnoreList()
    local remove = {}
    for key, v in pairs(active) do
        if not v.isTotem and not AuraAllowed(v.name, v.icon, v.isDebuff, v.spellId) then
            remove[table.getn(remove) + 1] = key
        end
    end
    for i = 1, table.getn(remove) do
        RemoveBar(remove[i])
    end
    ScanAuras(true)
end

-- ---------------- 监控名单查看面板 ----------------
local listFrame

local function GetActiveByName(name)
    local lname = string.lower(name)
    for key, v in pairs(active) do
        if not v.isTotem and v.name and string.lower(v.name) == lname then
            return v
        end
    end
    return nil
end

local function GetActiveBySpellId(spellId)
    for key, v in pairs(active) do
        if not v.isTotem and v.spellId == spellId then
            return v
        end
    end
    return nil
end

local function GetListRow(f, i)
    if not f.rows[i] then
        local nameFs = f:CreateFontString(nil, "OVERLAY")
        nameFs:SetFontObject(GameFontNormalSmall)
        nameFs:SetJustifyH("LEFT")
        local statusFs = f:CreateFontString(nil, "OVERLAY")
        statusFs:SetFontObject(GameFontNormalSmall)
        statusFs:SetJustifyH("RIGHT")
        f.rows[i] = { name = nameFs, status = statusFs }
    end
    local row = f.rows[i]
    local y = -46 - (i - 1) * 17
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y)
    row.status:ClearAllPoints()
    row.status:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, y)
    row.name:Show()
    row.status:Show()
    return row
end

local function RefreshMonitorList()
    if not listFrame or not listFrame:IsShown() then return end
    local names = SplitAuraList(db.auraList)
    local n = table.getn(names)
    local hint = ""
    if not db.onlyTrackList then
        hint = "未开启「仅监控自定义名单」，当前显示全部光环"
    end
    if n == 0 then
        hint = "名单为空：设置 → 常规 → 监控名单 中填写"
    end
    listFrame.hint:SetText(hint)

    local now = GetTime()
    for i = 1, n do
        local row = GetListRow(listFrame, i)
        local entry = names[i]
        local spellId, bar, label
        if string.find(entry, "^%d+$") then
            spellId = tonumber(entry)
            bar = GetActiveBySpellId(spellId)
            label = (SpellName(spellId) or "未知法术") .. " (" .. entry .. ")"
        else
            bar = GetActiveByName(entry)
            label = entry
        end
        row.name:SetText(label)
        if bar then
            local left = (bar.started or now) + bar.duration - now
            if left < 0 then left = 0 end
            row.name:SetTextColor(0.4, 1, 0.5)
            row.status:SetText((bar.isTarget and "目标 " or "") .. string.format("%.1f秒", left))
            row.status:SetTextColor(0.4, 1, 0.5)
        else
            row.name:SetTextColor(0.62, 0.62, 0.62)
            row.status:SetText("未激活")
            row.status:SetTextColor(0.5, 0.5, 0.5)
        end
    end
    for i = n + 1, table.getn(listFrame.rows) do
        listFrame.rows[i].name:Hide()
        listFrame.rows[i].status:Hide()
    end

    local h = 46 + n * 17 + 14
    if h < 90 then h = 90 end
    if h > 480 then h = 480 end
    listFrame:SetHeight(h)
end

local function CreateMonitorList()
    if listFrame then return listFrame end
    local f = CreateFrame("Frame", "ChronoTimerMonitorList", UIParent)
    listFrame = f
    f:SetWidth(260)
    f:SetHeight(120)
    f:SetPoint("CENTER", UIParent, "CENTER", 300, 80)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
    if f.SetBackdropBorderColor then
        f:SetBackdropBorderColor(0.30, 1, 0.90, 1)
    end

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(GameFontNormal)
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -10)
    title:SetText("监控名单")
    title:SetTextColor(0.45, 1, 0.9)

    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetFontObject(GameFontNormalSmall)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    hint:SetTextColor(0.7, 0.7, 0.7)
    f.hint = hint

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)

    f.rows = {}
    f.elapsed = 0
    f:SetScript("OnUpdate", function()
        this.elapsed = (this.elapsed or 0) + arg1
        if this.elapsed >= 0.5 then
            this.elapsed = 0
            RefreshMonitorList()
        end
    end)

    if UISpecialFrames then
        local found = false
        for i = 1, table.getn(UISpecialFrames) do
            if UISpecialFrames[i] == "ChronoTimerMonitorList" then found = true end
        end
        if not found then
            table.insert(UISpecialFrames, "ChronoTimerMonitorList")
        end
    end
    return f
end

local function ShowMonitorList()
    local f = CreateMonitorList()
    f:Show()
    RefreshMonitorList()
end

-- ---------------- 忽略名单查看面板 ----------------
local ignoreFrame

local function RefreshIgnoreList()
    if not ignoreFrame or not ignoreFrame:IsShown() then return end
    local names = SplitAuraList(db.ignoreList)
    local n = table.getn(names)
    local hint
    if n == 0 then
        hint = "名单为空：设置 → 常规 → 忽略名单 中填写"
    else
        hint = "共 " .. n .. " 项，命中的光环不会显示计时条"
    end
    ignoreFrame.hint:SetText(hint)

    for i = 1, n do
        local row = GetListRow(ignoreFrame, i)
        local entry = names[i]
        if string.find(entry, "^%d+$") then
            row.name:SetText((SpellName(tonumber(entry)) or "未知法术") .. " (" .. entry .. ")")
            row.status:SetText("法术 ID")
        else
            row.name:SetText(entry)
            row.status:SetText("包含匹配")
        end
        row.name:SetTextColor(0.95, 0.6, 0.6)
        row.status:SetTextColor(0.75, 0.62, 0.62)
    end
    for i = n + 1, table.getn(ignoreFrame.rows) do
        ignoreFrame.rows[i].name:Hide()
        ignoreFrame.rows[i].status:Hide()
    end

    local h = 46 + n * 17 + 14
    if h < 90 then h = 90 end
    if h > 320 then h = 320 end
    ignoreFrame:SetHeight(h)
end

local function CreateIgnoreList()
    if ignoreFrame then return ignoreFrame end
    local f = CreateFrame("Frame", "ChronoTimerIgnoreList", UIParent)
    ignoreFrame = f
    f:SetWidth(260)
    f:SetHeight(120)
    f:SetPoint("CENTER", UIParent, "CENTER", 300, -240)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
    if f.SetBackdropBorderColor then
        f:SetBackdropBorderColor(1, 0.45, 0.45, 1)
    end

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(GameFontNormal)
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -10)
    title:SetText("忽略名单")
    title:SetTextColor(1, 0.55, 0.55)

    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetFontObject(GameFontNormalSmall)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    hint:SetTextColor(0.7, 0.7, 0.7)
    f.hint = hint

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)

    f.rows = {}
    f.elapsed = 0
    f:SetScript("OnUpdate", function()
        this.elapsed = (this.elapsed or 0) + arg1
        if this.elapsed >= 0.5 then
            this.elapsed = 0
            RefreshIgnoreList()
        end
    end)

    if UISpecialFrames then
        local found = false
        for i = 1, table.getn(UISpecialFrames) do
            if UISpecialFrames[i] == "ChronoTimerIgnoreList" then found = true end
        end
        if not found then
            table.insert(UISpecialFrames, "ChronoTimerIgnoreList")
        end
    end
    return f
end

local function ShowIgnoreList()
    local f = CreateIgnoreList()
    f:Show()
    RefreshIgnoreList()
end

-- ---------------- 拖动锚点 ----------------
local function SaveAnchorPosition()
    if not anchor then return end
    local upscale = UIParent:GetEffectiveScale()
    if not upscale or upscale == 0 then upscale = 1 end
    local ascale = anchor:GetEffectiveScale()
    if not ascale or ascale == 0 then ascale = 1 end
    local left, bottom = anchor:GetLeft(), anchor:GetBottom()
    if not left or not bottom then return end
    db.anchorX = round(left * ascale / upscale)
    db.anchorY = round(bottom * ascale / upscale)
end

local function CreateAnchor()
    anchor = CreateFrame("Button", "ChronoTimerAnchor", UIParent)
    anchor:SetWidth(db.barwidth or 200)
    anchor:SetHeight(24)
    anchor:SetFrameStrata("MEDIUM")
    anchor:EnableMouse(true)
    anchor:SetMovable(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetClampedToScreen(true)

    -- 用标准背景 + 边框贴图，避免手工拉伸 Tooltip 边框导致的错位
    anchor:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    anchor:SetBackdropColor(0, 0.45, 0.45, 0.65)
    if anchor.SetBackdropBorderColor then
        anchor:SetBackdropBorderColor(0.30, 1, 0.90, 1)
    end

    local label = anchor:CreateFontString(nil, "OVERLAY")
    label:SetFontObject(GameFontNormalSmall)
    label:ClearAllPoints()
    label:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    label:SetTextColor(1, 1, 1, 1)
    label:SetText("ChronoTimer 拖动锚点")
    anchor.label = label

    anchor:SetScript("OnDragStart", function() this:StartMoving() end)
    anchor:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        SaveAnchorPosition()
    end)
    anchor:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("ChronoTimer 计时条锚点")
        GameTooltip:AddLine("按住左键拖动，计时条会跟随移动", 1, 1, 1)
        GameTooltip:Show()
    end)
    anchor:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if db.anchorX and db.anchorY then
        anchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.anchorX, db.anchorY)
    else
        anchor:SetPoint("TOP", UIParent, "TOP", 0, -180)
    end
    UpdateAnchorColors()
    anchor:Hide()
end

function CT:ToggleAnchor()
    if not anchor then return end
    if anchor:IsShown() then
        anchor:Hide()
    else
        anchor:Show()
    end
end

function CT:RunTest()
    if not candy then return end
    local now = GetTime()
    for i = 1, 5 do
        local key = "test" .. i
        local id = PREFIX .. key
        if candy:IsCandyBarRegistered(id) then candy:UnregisterCandyBar(id) end
        local dur = math.random(4) + 3
        local isDebuff = (i > 3)
        local label = (isDebuff and "测试Debuff" or "测试Buff") .. i
        local icon = "Interface\\Icons\\Spell_Shadow_ManaBurn"
        candy:RegisterCandyBar(id, dur, label, icon,
            AuraColorName(isDebuff, nil, label, id))
        candy:RegisterCandyBarWithGroup(id, isDebuff and GROUP_TARGET or GROUP_SELF)
        ApplyBarSettings(id, isDebuff, nil, label, id, UnitClassToken("player"))
        candy:StartCandyBar(id, true)
        -- 同步写入 active，图标模式下也能看到测试图标
        active[key] = {
            id = id, name = label, icon = icon, duration = dur, isDebuff = isDebuff,
            started = now, endsAt = now + dur, isTarget = true,
        }
    end
    if ChronoTimerIconMode then ChronoTimerIconMode:Update(true) end
end

-- ---------------- 小地图按钮 ----------------
local function UpdateMinimapPosition()
    if not minimapButton then return end
    local angle = math.rad(db.minimapAngle or 200)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end

local ApplySettingsColor

local function CreateMinimapButton()
    if not Minimap then return end
    local b = CreateFrame("Button", "ChronoTimerMinimapButton", Minimap)
    b:SetWidth(32)
    b:SetHeight(32)
    b:SetFrameStrata("MEDIUM")
    b:EnableMouse(true)
    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    -- 1.12 原生客户端可能没有 RegisterForClicks，调用前先判断，避免整个初始化中断
    if b.RegisterForClicks then
        b:RegisterForClicks("LeftButtonUp")
    end

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture("Interface\\AddOns\\ChronoTimer\\icon")
    b.icon:SetWidth(20)
    b.icon:SetHeight(20)
    b.icon:SetPoint("CENTER", 0, 0)

    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b.border:SetWidth(53)
    b.border:SetHeight(53)
    b.border:SetPoint("TOPLEFT", 0, 0)

    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("ChronoTimer 光环计时")
        GameTooltip:AddLine("左键：打开设置", 1, 1, 1)
        GameTooltip:AddLine("左键拖动：沿小地图移动", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b:SetScript("OnDragStart", function()
        this.dragging = true
        this.lastDrag = GetTime()
    end)
    b:SetScript("OnDragStop", function()
        this.dragging = false
        this.lastDrag = GetTime()
    end)
    b:SetScript("OnUpdate", function()
        if not this.dragging then return end
        local scale = Minimap:GetEffectiveScale()
        if not scale or scale == 0 then scale = 1 end
        local px, py = GetCursorPosition()
        px, py = px / scale, py / scale
        local mx, my = Minimap:GetCenter()
        if not mx or not my then return end
        db.minimapAngle = math.deg(math.atan2(py - my, px - mx))
        UpdateMinimapPosition()
    end)
    b:SetScript("OnClick", function()
        if this.lastDrag and (GetTime() - this.lastDrag) < 0.25 then return end
        if waterfall then
            waterfall:Open(ADDON)
            ApplySettingsColor()
        end
    end)

    minimapButton = b
    UpdateMinimapPosition()
    if db.hideMinimap then b:Hide() end
end

-- ---------------- 设置面板（Waterfall，同 Chronometer） ----------------
local function GetField(field)
    return function() return db[field] end
end

local function SetField(field)
    return function(v)
        db[field] = v
        RefreshAllBars()
    end
end

local function GetColor(field)
    return function()
        local c = db[field]
        local r, g, b, a = 1, 1, 1, 1
        if type(c) == "string" then
            local _, rr, gg, bb = paint:GetRGBPercent(c)
            r, g, b = rr or 1, gg or 1, bb or 1
        elseif type(c) == "table" then
            r, g, b, a = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end
        return r, g, b, a
    end
end

local function SetColor(field)
    return function(r, g, b, a)
        db[field] = { r, g, b, a or 1 }
        RefreshAllBars()
    end
end

local function BuildOptions()
    local hcolor = "|cFF77BBFF"

    local options = {
        type = "group",
        icon = "Interface\\AddOns\\ChronoTimer\\icon",
        args = {
            main = {
                name = hcolor .. "常规", type = "group", order = 10,
                args = {
                    enabled = {
                        name = "启用计时", type = "toggle", order = 1,
                        desc = "关闭后不扫描光环，已显示的计时条会清空",
                        get = function() return db.enabled end,
                        set = function(v)
                            db.enabled = v
                            if not v then ClearAll() else ScanAuras(true) end
                        end,
                    },
                    buffs = {
                        name = "显示 Buff", type = "toggle", order = 2,
                        desc = "显示自身有益光环的剩余时间",
                        get = GetField("showBuffs"), set = SetField("showBuffs"),
                    },
                    debuffs = {
                        name = "显示 Debuff", type = "toggle", order = 3,
                        desc = "显示自身有害光环的剩余时间",
                        get = GetField("showDebuffs"), set = SetField("showDebuffs"),
                    },
                    minDuration = {
                        name = "最短显示时长", type = "range", order = 4,
                        desc = "剩余时间低于该秒数的光环不显示（0 = 全部显示）",
                        min = 0, max = 30, step = 1,
                        get = GetField("minDuration"), set = SetField("minDuration"),
                    },
                    maxDuration = {
                        name = "最长显示时长", type = "range", order = 5,
                        desc = "剩余时间超过该秒数的光环不显示，用于过滤长时间祝福类 Buff（0 = 不过滤）",
                        min = 0, max = 1800, step = 15,
                        get = function() return db.maxDuration or 0 end,
                        set = function(v)
                            db.maxDuration = v
                            if v and v > 0 then
                                local now = GetTime()
                                local over = {}
                                for key, bar in pairs(active) do
                                    local left = (bar.started or now) + bar.duration - now
                                    if left > v then
                                        over[table.getn(over) + 1] = key
                                    end
                                end
                                for i = 1, table.getn(over) do
                                    RemoveBar(over[i])
                                end
                            end
                            ScanAuras(true)
                        end,
                    },
                    onlyTrackList = {
                        name = "仅监控自定义名单", type = "toggle", order = 5.5,
                        desc = "开启后只显示名单里的 Buff / Debuff，其余光环一律不显示；图腾计时不受影响",
                        get = function() return db.onlyTrackList end,
                        set = function(v)
                            db.onlyTrackList = v
                            ApplyWhitelistChange()
                        end,
                    },
                    auraList = {
                        name = "监控名单", type = "text", order = 5.6,
                        desc = "要监控的 Buff / Debuff，可填名称或法术 ID，多个用逗号或换行分隔，例如：切割,破甲,172",
                        usage = "名称需与游戏内一致；纯数字按法术 ID 精确匹配；用 , ; 、 或换行分隔",
                        get = function() return db.auraList or "" end,
                        set = function(v)
                            db.auraList = v
                            ApplyWhitelistChange()
                        end,
                    },
                    viewList = {
                        name = "查看监控名单", type = "execute", order = 5.7,
                        desc = "打开面板查看名单中每个光环当前的计时状态（也可用 /ct list）",
                        func = function() ShowMonitorList() end,
                    },
                    selfBuffsOnly = {
                        name = "只显示自己施加的 Buff", type = "toggle", order = 5.75,
                        desc = "只显示自己（含宠物）施放的 Buff，别人给的王者祝福、智慧祝福等不再显示",
                        get = function() return db.selfBuffsOnly end,
                        set = function(v)
                            db.selfBuffsOnly = v
                            ApplyWhitelistChange()
                        end,
                    },
                    ignoreFood = {
                        name = "忽略食物 / 饮水 Buff", type = "toggle", order = 5.8,
                        desc = "进食、饮水产生的 Buff 不再显示计时条",
                        get = function() return db.ignoreFood end,
                        set = function(v)
                            db.ignoreFood = v
                            ApplyWhitelistChange()
                        end,
                    },
                    ignoreList = {
                        name = "忽略名单", type = "text", order = 5.85,
                        desc = "要排除的 Buff / Debuff，可填名称关键词或法术 ID，多个用逗号分隔，例如：王者,智慧,172",
                        usage = "名称按包含匹配（不区分大小写）；纯数字按法术 ID 精确匹配；用 , ; 、 或换行分隔",
                        get = function() return db.ignoreList or "" end,
                        set = function(v)
                            db.ignoreList = v
                            ApplyWhitelistChange()
                        end,
                    },
                    viewIgnore = {
                        name = "查看忽略名单", type = "execute", order = 5.87,
                        desc = "打开面板查看忽略名单中的每个关键词 / 法术 ID（也可用 /ct ignore）",
                        func = function() ShowIgnoreList() end,
                    },
                    trackTarget = {
                        name = "显示多目标 DoT / Debuff", type = "toggle", order = 6,
                        desc = "按 GUID 显示你（含宠物）施加在敌人身上的 DoT / Debuff，切换目标不会清除",
                        get = function() return db.trackTarget end,
                        set = function(v)
                            db.trackTarget = v
                            if not v then ClearTargetBars(true) end
                        end,
                    },
                    trackHoTs = {
                        name = "跟踪友方 HoT", type = "toggle", order = 6.1,
                        desc = "跟踪你施加的周期治疗，切换目标后继续显示目标名和剩余时间",
                        get = function() return db.trackHoTs end,
                        set = function(v)
                            db.trackHoTs = v
                            if not v then ClearAuraKind("hot") end
                        end,
                    },
                    clickRecastHoT = {
                        name = "点击补 HoT", type = "toggle", order = 6.2,
                        desc = "左键点击 HoT 计时条或图标，直接对原目标施放同等级技能，不切换当前目标",
                        get = function() return db.clickRecastHoT end,
                        set = function(v)
                            db.clickRecastHoT = v
                            RefreshAllBars()
                        end,
                    },
                    trackFireVulnerability = {
                        name = "跟踪火焰易伤", type = "toggle", order = 6.3,
                        desc = "跟踪团队共享的强化灼烧 Debuff：30 秒、最多 5 层，需要开启多目标 DoT / Debuff",
                        get = function() return db.trackFireVulnerability end,
                        set = function(v)
                            db.trackFireVulnerability = v
                            if not v then ClearAuraKind("shared") end
                        end,
                    },
                    pvpDR = {
                        name = "PvP 控制按递减估算", type = "toggle", order = 6.5,
                        desc = "对玩家目标身上的控制类 Debuff（羊、闷棍、冰冻陷阱等）按 18 秒递减规则估算时长：100% → 50% → 25% → 免疫",
                        usage = "香草瘫痪类还有心跳挣脱机制，第一次也可能提前醒，所以计时条显示的是上限，实际会随光环消失提前结束",
                        get = function() return db.pvpDR end,
                        set = function(v)
                            db.pvpDR = v
                            ClearTargetBars(true)
                        end,
                    },
                    showText = {
                        name = "显示文字", type = "toggle", order = 7,
                        get = GetField("showText"), set = SetField("showText"),
                    },
                    barText = {
                        name = "文字内容", type = "text", order = 8,
                        desc = "$s = 法术名称，$n = 叠加层数，$t = 光环所在目标名称",
                        usage = "$s = 法术名称，$n = 叠加层数，$t = 目标名称；默认多目标光环显示「$s - $t」",
                        get = GetField("text"), set = SetField("text"),
                    },
                    test = {
                        name = "运行测试条", type = "execute", order = 20,
                        desc = "生成 5 条测试计时条",
                        func = function() CT:RunTest() end,
                    },
                },
            },
            bar = {
                name = hcolor .. "计时条", type = "group", order = 20,
                args = {
                    anchor = {
                        name = "显示/隐藏拖动锚点", type = "execute", order = 1,
                        desc = "显示后可拖动计时条位置，拖动完可再次点击隐藏",
                        func = function() CT:ToggleAnchor() end,
                    },
                    width = {
                        name = "宽度", type = "range", order = 10,
                        min = 50, max = 300, step = 1,
                        get = GetField("barwidth"), set = SetField("barwidth"),
                    },
                    height = {
                        name = "高度", type = "range", order = 11,
                        min = 8, max = 30, step = 1,
                        get = GetField("barheight"), set = SetField("barheight"),
                    },
                    spacing = {
                        name = "条间距", type = "range", order = 12,
                        min = 0, max = 15, step = 1,
                        get = GetField("spacing"), set = SetField("spacing"),
                    },
                    scale = {
                        name = "整体缩放", type = "range", order = 13,
                        min = 0.5, max = 1.5, step = 0.05,
                        get = GetField("barscale"), set = SetField("barscale"),
                    },
                    texture = {
                        name = "材质", type = "text", order = 20,
                        validate = TEXORDER,
                        get = GetField("bartex"), set = SetField("bartex"),
                    },
                    classColors = {
                        name = "职业配色（框架）", type = "toggle", order = 24,
                        desc = "计时条框体与锚点框架按职业着色：自身 Buff/图腾用你的职业色，目标 Debuff 用目标职业色；填充色不变",
                        get = function() return db.classColors end,
                        set = function(v) db.classColors = v; RefreshAllBars() end,
                    },
                    multicolor = {
                        name = "多彩颜色（区分 Buff/Debuff）", type = "toggle", order = 25,
                        desc = "开启后每个光环自动分配不同颜色：Buff 使用冷色系，Debuff 使用暖色系，背景也随类型着色",
                        get = function() return db.multicolor end,
                        set = function(v) db.multicolor = v; RefreshAllBars() end,
                    },
                    barcolor = {
                        name = "Buff 颜色（关闭多彩时）", type = "color", order = 30,
                        get = GetColor("barcolor"), set = SetColor("barcolor"),
                    },
                    debuffcolor = {
                        name = "Debuff 颜色（关闭多彩时）", type = "color", order = 31,
                        get = GetColor("debuffcolor"), set = SetColor("debuffcolor"),
                    },
                    bgcolor = {
                        name = "背景颜色（关闭多彩时）", type = "color", order = 32,
                        get = GetColor("bgcolor"), set = SetColor("bgcolor"),
                    },
                    bgalpha = {
                        name = "背景透明度", type = "range", order = 33,
                        min = 0, max = 1, step = 0.05,
                        get = function() return db.bgalpha or 0.5 end,
                        set = function(v) db.bgalpha = v; RefreshAllBars() end,
                    },
                    textcolor = {
                        name = "文字颜色", type = "color", order = 34,
                        get = GetColor("textcolor"), set = SetColor("textcolor"),
                    },
                    textsize = {
                        name = "文字大小", type = "range", order = 35,
                        min = 8, max = 20, step = 1,
                        get = GetField("textsize"), set = SetField("textsize"),
                    },
                    reverse = {
                        name = "反向填充", type = "toggle", order = 41,
                        get = GetField("reverse"), set = SetField("reverse"),
                    },
                    ghost = {
                        name = "淡出停留", type = "range", order = 42,
                        desc = "计时结束后条停留淡出的秒数（0 = 立即消失）",
                        min = 0, max = 10, step = 0.5,
                        get = GetField("ghost"), set = SetField("ghost"),
                    },
                    reset = {
                        name = "重置位置", type = "execute", order = 50,
                        desc = "把计时条锚点恢复到屏幕中上方",
                        func = function()
                            db.anchorX, db.anchorY = nil, nil
                            if anchor then
                                anchor:ClearAllPoints()
                                anchor:SetPoint("TOP", UIParent, "TOP", 0, -180)
                            end
                        end,
                    },
                },
            },
            iconmode = {
                name = hcolor .. "图标模式", type = "group", order = 25,
                args = {
                    useIcons = {
                        name = "使用图标显示（替代计时条）", type = "toggle", order = 1,
                        desc = "开启后以 WeakAuras 风格的图标 + 倒计时显示，计时条自动隐藏；关闭后恢复条状显示",
                        get = function() return db.displayMode == "icon" end,
                        set = function(v)
                            db.displayMode = v and "icon" or "bar"
                            ApplyGroupAnchor()
                            if ChronoTimerIconMode then
                                ChronoTimerIconMode:SetEnabled(db.displayMode == "icon")
                                ChronoTimerIconMode:ApplySettings()
                            end
                        end,
                    },
                    iconSize = {
                        name = "图标大小", type = "range", order = 2,
                        desc = "图标模式下每个光环图标的边长",
                        min = 20, max = 80, step = 1,
                        get = function() return db.iconSize or 40 end,
                        set = function(v)
                            db.iconSize = v
                            if ChronoTimerIconMode then ChronoTimerIconMode:ApplySettings() end
                        end,
                    },
                    iconSpacing = {
                        name = "图标间距", type = "range", order = 3,
                        desc = "图标之间的间隔像素",
                        min = 0, max = 20, step = 1,
                        get = function() return db.iconSpacing or 6 end,
                        set = function(v)
                            db.iconSpacing = v
                            if ChronoTimerIconMode then ChronoTimerIconMode:ApplySettings() end
                        end,
                    },
                    iconPerRow = {
                        name = "每行图标数量", type = "range", order = 4,
                        desc = "横向排满这么多个图标后自动换行，自身 Buff 向下、目标 Debuff 向上",
                        min = 1, max = 20, step = 1,
                        get = function() return db.iconPerRow or 8 end,
                        set = function(v)
                            db.iconPerRow = v
                            if ChronoTimerIconMode then ChronoTimerIconMode:ApplySettings() end
                        end,
                    },
                    iconTextSize = {
                        name = "倒计时文字大小", type = "range", order = 5,
                        desc = "图标上倒计时数字的字号，0 表示跟随图标大小自动缩放",
                        min = 0, max = 40, step = 1,
                        get = function() return db.iconTextSize or 0 end,
                        set = function(v)
                            db.iconTextSize = v
                            if ChronoTimerIconMode then ChronoTimerIconMode:ApplySettings() end
                        end,
                    },
                    stackTextSize = {
                        name = "层数文字大小", type = "range", order = 6,
                        desc = "图标角落层数数字的字号，0 表示跟随图标大小自动缩放",
                        min = 0, max = 40, step = 1,
                        get = function() return db.stackTextSize or 0 end,
                        set = function(v)
                            db.stackTextSize = v
                            if ChronoTimerIconMode then ChronoTimerIconMode:ApplySettings() end
                        end,
                    },
                    iconSecondMode = {
                        name = "以整秒显示倒计时", type = "toggle", order = 7,
                        desc = "开启后统一显示整秒数字；关闭时 60 秒以上显示分:秒，10 秒内显示一位小数",
                        get = function() return db.iconSecondMode end,
                        set = function(v)
                            db.iconSecondMode = v
                            if ChronoTimerIconMode then ChronoTimerIconMode:ApplySettings() end
                        end,
                    },
                    unlockIcon = {
                        name = "解锁图标位置", type = "execute", order = 8,
                        desc = "点击后出现拖动框，拖好位置再次点击锁定",
                        func = function()
                            if ChronoTimerIconMode then ChronoTimerIconMode:ToggleUnlock() end
                        end,
                    },
                    resetIcon = {
                        name = "重置图标位置", type = "execute", order = 9,
                        func = function()
                            if ChronoTimerIconMode then ChronoTimerIconMode:ResetIconPosition() end
                        end,
                    },
                    ccCenter = {
                        name = "控制类 Debuff 居中显示", type = "toggle", order = 10,
                        desc = "自身眩晕、定身等控制类 Debuff 单独显示在屏幕中央，图标上下带灰色横线与红色柔光；条形与图标模式下都会显示",
                        get = function() return db.ccCenter end,
                        set = function(v)
                            db.ccCenter = v
                            if ChronoTimerIconMode then ChronoTimerIconMode:ApplySettings() end
                        end,
                    },
                    ccSize = {
                        name = "居中图标大小", type = "range", order = 11,
                        min = 40, max = 120, step = 1,
                        get = function() return db.ccSize or 64 end,
                        set = function(v)
                            db.ccSize = v
                            if ChronoTimerIconMode then ChronoTimerIconMode:ApplySettings() end
                        end,
                    },
                    unlockCC = {
                        name = "解锁居中图标位置", type = "execute", order = 12,
                        desc = "点击后出现拖动框，拖好位置再次点击锁定",
                        func = function()
                            if ChronoTimerIconMode then ChronoTimerIconMode:ToggleCCUnlock() end
                        end,
                    },
                    resetCC = {
                        name = "重置居中图标位置", type = "execute", order = 13,
                        func = function()
                            if ChronoTimerIconMode then ChronoTimerIconMode:ResetCCPosition() end
                        end,
                    },
                },
            },
            energy = {
                name = hcolor .. "能量/连击点", type = "group", order = 27,
                args = {
                    showEnergy = {
                        name = "显示能量与连击点", type = "toggle", order = 1,
                        desc = "仅盗贼与小德生效，小德只在猎豹等能量形态显示",
                        get = function() return db.showEnergy ~= false end,
                        set = function(v)
                            db.showEnergy = v
                            if ChronoTimerEnergy_Refresh then ChronoTimerEnergy_Refresh() end
                        end,
                    },
                    showEnergyBar = {
                        name = "显示能量条", type = "toggle", order = 2,
                        desc = "关闭后只显示连击点，不显示能量进度条",
                        get = function() return db.showEnergyBar ~= false end,
                        set = function(v)
                            db.showEnergyBar = v
                            if ChronoTimerEnergy_Apply then ChronoTimerEnergy_Apply() end
                        end,
                    },
                    showComboPoints = {
                        name = "显示连击点", type = "toggle", order = 3,
                        desc = "关闭后只显示能量条，不显示连击点小长条",
                        get = function() return db.showComboPoints ~= false end,
                        set = function(v)
                            db.showComboPoints = v
                            if ChronoTimerEnergy_Apply then ChronoTimerEnergy_Apply() end
                        end,
                    },
                    showEnergyTick = {
                        name = "显示回能光标", type = "toggle", order = 4,
                        desc = "在能量条上显示一条移动的白色光标，提示下一次回能跳动的位置；间隔按角色实际回能速度动态校准",
                        get = function() return db.showEnergyTick ~= false end,
                        set = function(v)
                            db.showEnergyTick = v
                            if ChronoTimerEnergy_Refresh then ChronoTimerEnergy_Refresh() end
                        end,
                    },
                    energyCombatOnly = {
                        name = "仅战斗中显示", type = "toggle", order = 5,
                        desc = "开启后能量条与连击点只在进入战斗时出现，脱战后自动隐藏",
                        get = function() return db.energyCombatOnly == true end,
                        set = function(v)
                            db.energyCombatOnly = v
                            if ChronoTimerEnergy_Refresh then ChronoTimerEnergy_Refresh() end
                        end,
                    },
                    energyTex = {
                        name = "能量条材质", type = "text", order = 6,
                        desc = "能量条与连击点小长条的填充材质，与计时条材质列表相同，default 为暴雪标准条",
                        validate = TEXORDER,
                        get = function() return db.energyTex or "default" end,
                        set = function(v)
                            db.energyTex = v
                            if ChronoTimerEnergy_Apply then ChronoTimerEnergy_Apply() end
                        end,
                    },
                    moveEnergy = {
                        name = "移动位置（解锁拖动）", type = "execute", order = 7,
                        desc = "点击后能量条出现绿框，直接用左键拖动即可移动，再次点击锁定（也可随时按住 Ctrl 拖动）",
                        func = function()
                            if ChronoTimerEnergy_ToggleMove then ChronoTimerEnergy_ToggleMove() end
                        end,
                    },
                    energyWidth = {
                        name = "能量条宽度", type = "range", order = 8,
                        desc = "能量进度条的宽度（像素）",
                        min = 60, max = 400, step = 5,
                        get = function() return db.energyWidth or 150 end,
                        set = function(v)
                            db.energyWidth = v
                            if ChronoTimerEnergy_Apply then ChronoTimerEnergy_Apply() end
                        end,
                    },
                    energyHeight = {
                        name = "能量条高度", type = "range", order = 9,
                        desc = "能量进度条的高度（像素），文字大小随之缩放",
                        min = 6, max = 40, step = 1,
                        get = function() return db.energyHeight or 12 end,
                        set = function(v)
                            db.energyHeight = v
                            if ChronoTimerEnergy_Apply then ChronoTimerEnergy_Apply() end
                        end,
                    },
                    comboHeight = {
                        name = "连击点高度", type = "range", order = 10,
                        desc = "每格连击点的尺寸：长条模式为高度，菱形 / 圆形为边长（像素）",
                        min = 2, max = 40, step = 1,
                        get = function() return db.comboHeight or 6 end,
                        set = function(v)
                            db.comboHeight = v
                            if ChronoTimerEnergy_Apply then ChronoTimerEnergy_Apply() end
                        end,
                    },
                    comboSpacing = {
                        name = "连击点间距", type = "range", order = 11,
                        desc = "连击点小长条 / 图形之间的间隔（像素）",
                        min = 0, max = 20, step = 1,
                        get = function() return db.comboSpacing or 4 end,
                        set = function(v)
                            db.comboSpacing = v
                            if ChronoTimerEnergy_Apply then ChronoTimerEnergy_Apply() end
                        end,
                    },
                    comboStyle = {
                        name = "连击点样式", type = "text", order = 11.5,
                        desc = "长条：铺满能量条宽度；正方形 / 菱形 / 圆形：在能量条上方居中的图形，大小由「连击点高度」控制",
                        validate = { "长条", "正方形", "菱形", "圆形" },
                        get = function()
                            local s = db.comboStyle or "bar"
                            if s == "square"  then return "正方形" end
                            if s == "diamond" then return "菱形" end
                            if s == "circle"  then return "圆形" end
                            return "长条"
                        end,
                        set = function(v)
                            if v == "正方形" then db.comboStyle = "square"
                            elseif v == "菱形" then db.comboStyle = "diamond"
                            elseif v == "圆形" then db.comboStyle = "circle"
                            else db.comboStyle = "bar" end
                            if ChronoTimerEnergy_Apply then ChronoTimerEnergy_Apply() end
                        end,
                    },
                    resetEnergy = {
                        name = "恢复默认位置", type = "execute", order = 12,
                        desc = "把能量条移回屏幕中下方",
                        func = function()
                            if ChronoTimerEnergy_Reset then ChronoTimerEnergy_Reset() end
                        end,
                    },
                },
            },
            warlock = {
                name = hcolor .. "术士", type = "group", order = 28,
                args = {
                    showEnslave = {
                        name = "监控恶魔叛变", type = "toggle", order = 1,
                        desc = "术士专用：施放奴役恶魔后显示叛变倒计时，宠物消失或被替换时自动移除",
                        get = function() return db.showEnslave ~= false end,
                        set = function(v) db.showEnslave = v end,
                    },
                    enslaveDuration = {
                        name = "叛变倒计时（秒）", type = "range", order = 2,
                        desc = "0 = 按法术数据自动（推荐）；手动填写后对下一次施放生效",
                        min = 0, max = 600, step = 10,
                        get = function() return db.enslaveDuration or 0 end,
                        set = function(v) db.enslaveDuration = v end,
                    },
                },
            },
            shaman = {
                name = hcolor .. "萨满", type = "group", order = 28.5,
                args = {
                    showTotems = {
                        name = "显示图腾", type = "toggle", order = 1,
                        desc = "显示自己已施放图腾的剩余持续时间（萨满）",
                        get = function() return db.showTotems end,
                        set = function(v)
                            db.showTotems = v
                            if v then
                                ScanAuras(true)
                            else
                                local keys = {}
                                for key, bar in pairs(active) do
                                    if bar.isTotem then keys[table.getn(keys) + 1] = key end
                                end
                                for i = 1, table.getn(keys) do
                                    RemoveBar(keys[i])
                                end
                            end
                        end,
                    },
                },
            },
            rogue = {
                name = hcolor .. "盗贼", type = "group", order = 28.6,
                args = {
                    trackBladeFlurry = {
                        name = "监控剑刃乱舞", type = "toggle", order = 1,
                        desc = "乌龟服剑刃乱舞为持续到取消的常驻 Buff（无剩余时间）。开启后，激活时显示一条常驻计时条 / 图标，取消后自动隐藏；仅盗贼生效。",
                        get = function() return db.trackBladeFlurry end,
                        set = function(v)
                            db.trackBladeFlurry = v
                            if v then
                                ScanAuras(true)
                            elseif active["bladeflurry"] then
                                RemoveBar("bladeflurry")
                            end
                        end,
                    },
                },
            },
            minimap = {
                name = hcolor .. "小地图", type = "group", order = 30,
                args = {
                    hide = {
                        name = "隐藏小地图按钮", type = "toggle", order = 1,
                        get = function() return db.hideMinimap end,
                        set = function(v)
                            db.hideMinimap = v
                            if minimapButton then
                                if v then minimapButton:Hide() else minimapButton:Show() end
                            end
                        end,
                    },
                },
            },
        },
    }

    -- 萨满专属页：仅萨满可见
    if UnitClassToken("player") ~= "SHAMAN" then
        options.args.shaman = nil
    end

    -- 能量 / 连击点仅盗贼与小德可用：其他职业移除该分类
    local energyClass = UnitClassToken("player")
    if energyClass ~= "ROGUE" and energyClass ~= "DRUID" then
        options.args.energy = nil
    end

    -- 恶魔叛变倒计时仅术士可用：其他职业移除该分类
    if UnitClassToken("player") ~= "WARLOCK" then
        options.args.warlock = nil
    end

    -- 盗贼专属页：仅盗贼可见
    if UnitClassToken("player") ~= "ROGUE" then
        options.args.rogue = nil
    end

    -- 设置界面标题栏使用玩家职业颜色
    local classToken = UnitClassToken("player")
    local cc = classToken and CLASS_COLORS[classToken]
    local cr, cg, cb = 0.2, 1.0, 0.8
    if cc then cr, cg, cb = cc[1], cc[2], cc[3] end

    waterfall:Register(ADDON, "aceOptions", options,
        "title", "ChronoTimer 光环计时",
        "colorR", cr, "colorG", cg, "colorB", cb,
        "treeLevels", 3)
end

-- 设置页使用说明：常驻显示在分类页顶部，选项区域自动下移
local function SetupIntroText()
    local info = waterfall and waterfall.registry and waterfall.registry[ADDON]
    local frame = info and info.frame
    if not frame or not frame.mainpane or not frame.mainpane.scrollframe then return end
    if frame._ctIntroShown then return end
    frame._ctIntroShown = true

    local pane = frame.mainpane
    local host = pane.frame
    local fs = host:CreateFontString("ChronoTimerIntroText", "OVERLAY")
    fs:SetFontObject(GameFontNormal)
    fs:SetJustifyH("LEFT")
    fs:SetWidth(300)
    fs:SetPoint("TOPLEFT", host, "TOPLEFT", 19, -37)

    local npLine = npOK and "|cff00ff00Nampower 已连接|r" or "|cffff0000未检测到 Nampower|r"
    fs:SetText(
        "|cFF77BBFFChronoTimer 光环计时  v1.6.27|r\n" ..
        npLine .. "\n\n" ..
        "自身光环 / 图腾 / 多目标 HoT / DoT 计时\n" ..
        "HoT 左键补施 · 团队共享火焰易伤\n" ..
        "/ct 设置 · /ct list 名单\n" ..
        "/ct ignore 忽略\n" ..
        "拖动锚点可移动计时条\n" ..
        "仓库 github.com/dapinggai/ChronoTimer"
    )

    local h = fs:GetHeight()
    if not h or h < 20 then h = 120 end

    local sf = pane.scrollframe
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", host, "TOPLEFT", 9, -(37 + h + 10))
    sf:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -28, 12)
end

-- 设置界面颜色跟随职业（打开时再校正一次，避免登录瞬间取不到职业）
function ApplySettingsColor()
    local info = waterfall.registry and waterfall.registry[ADDON]
    local frame = info and info.frame
    if not frame then return end
    SetupIntroText()
    local token = UnitClassToken("player")
    local c = token and CLASS_COLORS[token]
    if c then frame:SetColor(c[1], c[2], c[3]) end
end

-- ---------------- 初始化 ----------------
local function CopyDefaults()
    if type(ChronoTimerDB) ~= "table" then ChronoTimerDB = {} end
    if type(ChronoTimerDB.profile) ~= "table" then ChronoTimerDB.profile = {} end
    db = ChronoTimerDB.profile
    for k, v in pairs(defaults) do
        if db[k] == nil then
            db[k] = v
        end
    end
end

local function RegisterPaintColors()
    paint:RegisterColor("gray",   0.5, 0.5, 0.5)
    paint:RegisterColor("forest", 0.0, 0.5, 0.0)
    paint:RegisterColor("maroon", 0.5, 0.0, 0.0)
    paint:RegisterColor("navy",   0.0, 0.0, 0.5)
    paint:RegisterColor("olive",  0.5, 0.5, 0.0)
    paint:RegisterColor("purple", 0.5, 0.0, 0.5)
    paint:RegisterColor("teal",   0.0, 0.5, 0.5)

    -- 多彩 Buff / Debuff 调色板
    for i = 1, table.getn(BUFF_PALETTE) do
        local c = BUFF_PALETTE[i]
        paint:RegisterColor("ctbuff" .. i, c[1], c[2], c[3])
    end
    for i = 1, table.getn(DEBUFF_PALETTE) do
        local c = DEBUFF_PALETTE[i]
        paint:RegisterColor("ctdebuff" .. i, c[1], c[2], c[3])
    end
    -- 背景分色：Buff 墨绿 / Debuff 暗红
    paint:RegisterColor("ctbg_buff",   0.04, 0.20, 0.12)
    paint:RegisterColor("ctbg_debuff", 0.30, 0.03, 0.03)
    -- 自身 Debuff 背景：更饱和的红，和 Buff / 目标 Debuff 区分
    paint:RegisterColor("ctbg_selfdebuff", 0.48, 0.02, 0.02)
    -- 职业色（用于计时条框体 / 锚点框架）
    for token, c in pairs(CLASS_COLORS) do
        paint:RegisterColor("ctclass_" .. token, c[1], c[2], c[3])
    end
end

-- 安全执行：单步失败只提示，不中断整个初始化（避免个别客户端/库版本差异导致设置面板打不开）
local function SafeCall(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        Print("|cffff0000" .. label .. "失败：" .. tostring(err) .. "|r")
        Print("|cffff8080请把上面这行错误发给作者，或输入 /ct status 查看诊断信息|r")
    end
    return ok
end

local function PrintStatus()
    local lines = {}
    lines[1] = "版本 1.6.27"
    lines[2] = "Nampower：" .. (npOK and "已连接" or "未检测到")
    lines[3] = "依赖库：" ..
        "CandyBar=" .. (candy and "有" or "无") ..
        " PaintChips=" .. (paint and "有" or "无") ..
        " Waterfall=" .. (waterfall and "有" or "无")
    local reg = waterfall and waterfall:IsRegistered(ADDON)
    lines[4] = "设置面板注册：" .. (reg and "成功" or "失败")
    lines[5] = "小地图按钮：" .. (minimapButton and "已创建" or "未创建") ..
        "（隐藏=" .. tostring(db and db.hideMinimap) .. "）"
    local n = 0
    for _ in pairs(active) do n = n + 1 end
    lines[6] = "当前计时条：" .. n .. " 条"
    lines[7] = "API：GetUnitGUID=" .. (GetUnitGUID and "有" or "无") ..
        " GetUnitField=" .. (GetUnitField and "有" or "无") ..
        " GetPlayerBuffID=" .. (GetPlayerBuffID and "有" or "无")
    lines[8] = "存档：ChronoTimerDB" .. (type(ChronoTimerDB) == "table" and " 存在" or " 不存在")
    lines[9] = "更新地址：https://github.com/dapinggai/ChronoTimer"
    for i = 1, table.getn(lines) do Print(lines[i]) end
end

local function OpenSettings()
    if not waterfall then
        Print("|cffff0000缺少 Waterfall-1.0 库，无法打开设置面板（请安装/更新 !Libs）|r")
        return
    end
    if not waterfall:IsRegistered(ADDON) then
        Print("|cffff0000设置面板未注册成功，请查看登录时的红色报错，或输入 /ct status|r")
        return
    end
    waterfall:Open(ADDON)
    if ApplySettingsColor then ApplySettingsColor() end
end


local function Init()
    if initialized then return end

    -- 先注册命令，保证即使依赖库缺失/UI 创建失败，/ct 仍然可用
    SLASH_CHRONOTIMER1 = "/ct"
    SlashCmdList["CHRONOTIMER"] = function(msg)
        msg = string.lower(msg or "")
        if msg == "list" or msg == "名单" then
            ShowMonitorList()
        elseif msg == "status" or msg == "状态" then
            PrintStatus()
        elseif msg == "ignore" or msg == "忽略" then
            ShowIgnoreList()
        elseif msg == "jd" or msg == "审判" then
            if not GetUnitField then
                Print("当前客户端没有 GetUnitField，Nampower 版本过低")
            else
                local guid = GetUnitGUID and GetUnitGUID("target")
                if not guid then
                    Print("没有目标")
                else
                    local auras = GetUnitField(guid, "aura")
                    local n = 0
                    if type(auras) == "table" then
                        for _, id in pairs(auras) do
                            if type(id) == "number" and id > 0 then
                                n = n + 1
                                if n <= 10 then
                                    Print("目标光环 " .. id .. " " .. tostring(SpellName(id)))
                                end
                            end
                        end
                    end
                    Print("目标光环数量：" .. n)
                end
            end
        elseif msg == "dr" or msg == "递减" then
            CT.drDebug = not CT.drDebug
            if CT.drDebug then
                Print("DR 调试已开启：施法时打印 Nampower 的 effect/effectAuraName/durationMs")
            else
                Print("DR 调试已关闭")
            end
        elseif msg == "aura" or msg == "光环" then
            CT.auraDebug = not CT.auraDebug
            if CT.auraDebug then
                Print("光环调试已开启：打印目标光环的施放/新增/移除与删除原因")
            else
                Print("光环调试已关闭")
            end
        elseif msg == "cc" or msg == "控制" then
            if ChronoTimerIconMode and ChronoTimerIconMode.DebugCC then
                ChronoTimerIconMode:DebugCC()
            else
                Print("图标模块尚未初始化")
            end
        else
            OpenSettings()
        end
    end

    if not LoadLibraries() then
        Print("|cffff0000缺少依赖库（!Libs / CandyBar-2.2 / Waterfall-1.0），插件无法工作|r")
        Print("|cffff8080请把 !Libs 放到 Interface\\AddOns\\ 下，并在角色选择界面的插件列表里确认已勾选|r")
        Print("|cffff8080依赖库加载后再输入 /reload 重试，输入 /ct status 可查看诊断|r")
        return
    end

    RegisterPaintColors()
    CopyDefaults()
    BuildWhitelist()
    BuildIgnoreList()
    CreateAnchor()

    SafeCall("创建计时条分组", function()
        candy:RegisterCandyBarGroup(GROUP_SELF, db.spacing or 0, true)
        candy:RegisterCandyBarGroup(GROUP_TARGET, db.spacing or 0, true)
        ApplyGroupAnchor()
    end)

    SafeCall("创建小地图按钮", CreateMinimapButton)
    SafeCall("创建设置面板", BuildOptions)
    SafeCall("初始化图标模式", function()
        if ChronoTimerIconMode then
            ChronoTimerIconMode:Initialize(db, active)
        end
    end)

    initialized = true
    -- 正常加载时不输出任何提示，仅在有问题时提示
    if not npOK then
        Print("|cffff0000未检测到 Nampower|r：光环名称可能不准确，多目标 HoT / DoT、火焰易伤与来源过滤不可用")
    end
    if not waterfall:IsRegistered(ADDON) then
        Print("|cffff0000设置面板注册失败，请输入 /ct status 并把结果发给作者|r")
    end

    -- 补一次初始扫描，避免刚登录时没有条
    ScanAuras(true)
end

-- ---------------- 事件 ----------------
local function DetectNampower()
    local ok, detected = pcall(function()
        if GetNampowerVersion then
            local major = GetNampowerVersion()
            if major and major > 0 then return true end
        end
        if CheckNampower then
            if CheckNampower() then return true end
        end
        return false
    end)
    if ok then return detected end
    return false
end

local function RegSafe(frame, eventName)
    pcall(function() frame:RegisterEvent(eventName) end)
end

CT.npOK = DetectNampower()
npOK = CT.npOK

local ev = CreateFrame("Frame")
RegSafe(ev, "VARIABLES_LOADED")
RegSafe(ev, "PLAYER_LOGIN")
RegSafe(ev, "PLAYER_ENTERING_WORLD")
RegSafe(ev, "PLAYER_AURAS_CHANGED")
RegSafe(ev, "UNIT_AURA")
RegSafe(ev, "ZONE_CHANGED_NEW_AREA")
RegSafe(ev, "PLAYER_DEAD")
-- 萨满图腾掌握天赋：登录时与天赋变更后重新检测加成
RegSafe(ev, "PLAYER_TALENT_UPDATE")
RegSafe(ev, "CHARACTER_POINTS_CHANGED")

-- Nampower 施法成功事件：用于识别一键释放/常驻图腾
if CT.npOK then
    pcall(function() SetCVar("NP_EnableSpellGoEvents", "1") end)
    RegSafe(ev, "SPELL_GO_SELF")
end

-- Nampower 光环事件：新增/移除时立即重扫
RegSafe(ev, "BUFF_ADDED_SELF")
RegSafe(ev, "BUFF_REMOVED_SELF")
RegSafe(ev, "DEBUFF_ADDED_SELF")
RegSafe(ev, "DEBUFF_REMOVED_SELF")

-- Nampower 外部光环事件：按 GUID 追踪多目标 HoT / DoT / Debuff
RegSafe(ev, "AURA_CAST_ON_OTHER")
RegSafe(ev, "BUFF_ADDED_OTHER")
RegSafe(ev, "BUFF_REMOVED_OTHER")
RegSafe(ev, "DEBUFF_ADDED_OTHER")
RegSafe(ev, "DEBUFF_REMOVED_OTHER")
RegSafe(ev, "UNIT_DIED")
RegSafe(ev, "PLAYER_TARGET_CHANGED")
if CT.npOK then pcall(function() SetCVar("NP_EnableUnitEventsGuid", "1") end) end
-- 圣骑士审判 Debuff 随近战命中刷新（Nampower 两个事件名语义可能相反，都注册）
RegSafe(ev, "AUTO_ATTACK_SELF")
RegSafe(ev, "AUTO_ATTACK_OTHER")

-- Nampower 自身光环事件：记录 Buff 的来源（是否自己施放）
if CT.npOK then
    pcall(function() SetCVar("NP_EnableAuraCastEvents", "1") end)
end
RegSafe(ev, "AURA_CAST_ON_SELF")

local function HasFullImprovedScorch()
    if UnitClassToken("player") ~= "MAGE" or not GetTalentInfo or not GetNumTalents then
        return false
    end
    local tabs = GetNumTalentTabs and GetNumTalentTabs() or 3
    for tab = 1, tabs do
        for index = 1, GetNumTalents(tab) do
            local _, texture, _, _, rank = GetTalentInfo(tab, index)
            if texture and string.find(texture, "Spell_Fire_SoulBurn", 1, true) then
                return tonumber(rank) == 3
            end
        end
    end
    return false
end

local function HandleFireVulnerabilitySpellGo(spellId, targetGuid, numTargetsHit, numTargetsMissed)
    if not initialized or not db.enabled or not db.trackTarget or not db.showDebuffs
        or not db.trackFireVulnerability or not FIRE_VULNERABILITY_CASTS[spellId]
        or not targetGuid or not numTargetsHit or numTargetsHit <= 0
        or (numTargetsMissed and numTargetsMissed > 0) then return end
    local v = active[ExternalKey(FIRE_VULNERABILITY_ID, targetGuid)]
    if not v or v.auraKind ~= "shared"
        or (v.stacks or 1) < FIRE_VULNERABILITY_MAX_STACKS then return end
    -- 满层时没有新的叠层事件，只有自己的 3/3 天赋且命中才按成功施法续时
    if not HasFullImprovedScorch() then return end
    ApplyTargetDebuff(FIRE_VULNERABILITY_ID, targetGuid, FireVulnerabilityDuration(),
        FIRE_VULNERABILITY_MAX_STACKS, nil, "shared")
end

-- ---------------- 连击点通用时长推断 ----------------
-- 终结技 DoT 的真实时长由连击点决定（割裂 1~5 星 = 8/10/12/14/16 秒），
-- 其中割裂还会叠加「血腥气息」天赋加成（1 级 +4 秒，2 级及以上 +6 秒）。
-- 但 Nampower 的 AURA_CAST_ON_OTHER 只回 DBC 占位时长（割裂固定 6000ms）。
-- 现在按 DBC 方式处理：
--   * 基础时长读 GetSpellRecField(spellId, "duration")（DBC 权威值）
--   * 轮询自己当前目标的连击点，消耗后的短窗口内落地、且 DBC 基础为占位值的 DoT，
--     按 DBC 基础 + 2 秒 × 连击点 计时
--   * 德鲁伊撕扯等 DBC 基础为真实时长（12 秒）的 DoT 会自动跳过
--   * 个别法术 DBC 读数与实际不符时，在 CP_BASE_OVERRIDE 里按法术 ID 校准
local CP_POLL_INTERVAL = 0.15
local CP_SPEND_WINDOW   = 2.0
local CP_PLACEHOLDER_MS = 6500
local CP_PER_POINT      = 2

-- DBC 基础时长与实际规则不符时的校准表：[spellId] = 基础毫秒
local CP_BASE_OVERRIDE = {
    -- [1943] = 6000,   -- 割裂 Rank 1：DBC 读数不对时再放开
}

local cpHold, cpHoldAt, cpHoldGuid = 0, nil, nil
local cpPollAt = 0

-- 割裂（Rupture）额外受「血腥气息 / Taste for Blood」天赋影响：
-- 1 级 +4 秒，2 级及以上 +6 秒（客户端第 3 级已废弃但数据仍为 +6 秒）。
-- 时长规则与 Chronometer 的盗贼数据保持一致：基础时长 + 2 秒 × 连击点 + 天赋加成。
local TASTE_FOR_BLOOD_BONUS = { 4, 6, 6 }
local TASTE_FOR_BLOOD_NAMES = {
    ["Taste for Blood"] = true,
    ["血腥气息"] = true,
    ["嗜血渴望"] = true,   -- zhTW
}
-- 割裂名称：只认中文名，其他语言客户端靠图标名识别
local RUPTURE_NAMES = {
    ["割裂"] = true,
}

local tasteForBloodRank, tasteForBloodAt = nil, 0
-- 血腥气息天赋等级；30 秒缓存，避免每次 DoT 都扫一遍天赋
local function TasteForBloodRank()
    local now = GetTime()
    if tasteForBloodRank and now - tasteForBloodAt < 30 then
        return tasteForBloodRank
    end
    tasteForBloodAt = now
    tasteForBloodRank = 0
    if not GetTalentInfo or not GetNumTalents
        or (UnitClassToken and UnitClassToken("player") ~= "ROGUE") then
        return 0
    end
    local tabs = GetNumTalentTabs and GetNumTalentTabs() or 3
    for tab = 1, tabs do
        for index = 1, GetNumTalents(tab) do
            local name, texture, _, _, rank = GetTalentInfo(tab, index)
            local matched = name and TASTE_FOR_BLOOD_NAMES[name]
            if not matched and texture then
                matched = string.find(string.lower(texture), "tasteforblood", 1, true) ~= nil
            end
            if matched then
                tasteForBloodRank = tonumber(rank) or 0
                return tasteForBloodRank
            end
        end
    end
    return 0
end

local function PollComboPoints(now)
    if not GetComboPoints then return end
    local cp = GetComboPoints() or 0
    if cp > 0 then
        cpHold = cp
        cpHoldAt = now
        cpHoldGuid = GetUnitGUID and GetUnitGUID("target") or nil
    end
end

-- DBC 基础时长（毫秒），读不到返回 nil
local spellDurationCache = {}
local function SpellBaseDurationMs(spellId)
    if not spellId or spellId <= 0 or not GetSpellRecField then return nil end
    local cached = spellDurationCache[spellId]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local ok, v = pcall(GetSpellRecField, spellId, "duration")
    if ok and type(v) == "number" and v > 0 then
        if v <= 60 then v = v * 1000 end   -- 兼容以秒为单位的返回
        spellDurationCache[spellId] = v
        return v
    end
    spellDurationCache[spellId] = false
    return nil
end

-- 判断是否为割裂（只认中文名，图标名兜底）
local function IsRuptureSpell(spellId)
    local name = SpellName(spellId)
    if name then
        name = string.gsub(name, "^%s*(.-)%s*$", "%1")
        if RUPTURE_NAMES[name] then return true end
    end
    local icon = SpellIcon(spellId)
    if icon and string.find(string.lower(icon), "rupture", 1, true) then return true end
    return false
end

-- 肾击（Kidney Shot）：1 秒 + 1 秒 × 连击点（与 Chronometer 的 rs=1, cp=1 一致）
local KIDNEY_SHOT_NAMES = {
    ["肾击"] = true,
    ["腎擊"] = true,   -- zhTW
}

local function IsKidneyShotSpell(spellId)
    local name = SpellName(spellId)
    if name then
        name = string.gsub(name, "^%s*(.-)%s*$", "%1")
        if KIDNEY_SHOT_NAMES[name] then return true end
    end
    local icon = SpellIcon(spellId)
    if icon and string.find(string.lower(icon), "kidneyshot", 1, true) then return true end
    return false
end

-- 肾击时长：事件缺时长或只给 1 秒基础值时，用连击点推算
local function ComboPointStunDuration(spellId, targetGuid, effectAuraName, now)
    if effectAuraName and effectAuraName ~= 12 then return nil end
    if not cpHold or cpHold <= 0 or not cpHoldAt then return nil end
    if (now - cpHoldAt) > CP_SPEND_WINDOW then return nil end
    if cpHoldGuid and targetGuid and cpHoldGuid ~= targetGuid then return nil end
    if not IsKidneyShotSpell(spellId) then return nil end
    return 1 + cpHold
end

-- 返回按连击点推算的秒数；nil 表示保持事件反馈的时长
local function ComboPointDoTDuration(spellId, targetGuid, effectAuraName, durationMs, now)
    if effectAuraName ~= 3 then return nil end
    if not cpHold or cpHold <= 0 or not cpHoldAt then return nil end
    if (now - cpHoldAt) > CP_SPEND_WINDOW then return nil end
    if cpHoldGuid and targetGuid and cpHoldGuid ~= targetGuid then return nil end

    -- 割裂单独处理：部分客户端 DBC/事件时长给的是满级或占位值（实测 12 秒），
    -- 不能走下面的“占位值”判断，直接按真实规则计算：
    --   8 秒（1 星）+ 2 秒 × (连击点 - 1) + 血腥气息天赋加成
    if IsRuptureSpell(spellId) then
        local duration = 8 + CP_PER_POINT * (cpHold - 1)
        local rank = TasteForBloodRank()
        local bonus = rank > 0 and TASTE_FOR_BLOOD_BONUS[rank]
        if bonus then duration = duration + bonus end
        return duration
    end

    local baseMs = CP_BASE_OVERRIDE[spellId] or SpellBaseDurationMs(spellId) or durationMs
    if not baseMs or baseMs <= 0 then return nil end
    -- 只处理 DBC 基础本身是占位值的终结技 DoT；真实时长的 DoT 不动
    if baseMs > CP_PLACEHOLDER_MS then return nil end
    return baseMs / 1000 + CP_PER_POINT * cpHold
end

local function HandleExternalCast(spellId, casterGuid, targetGuid, effectAuraName, durationMs)
    if not initialized or not db.enabled or not spellId or not targetGuid then return end
    if spellId == FIRE_VULNERABILITY_ID then
        if db.trackTarget and db.showDebuffs and db.trackFireVulnerability then
            RememberUnit(targetGuid)
            ApplyTargetDebuff(FIRE_VULNERABILITY_ID, targetGuid, FireVulnerabilityDuration(),
                nil, nil, "shared")
        end
        return
    end
    local ownCast = IsCasterSelf(casterGuid)
    -- 事件缺时长时用 DBC 基础时长兜底
    if not durationMs or durationMs <= 0 then durationMs = SpellBaseDurationMs(spellId) end
    -- 肾击：DBC 只有 1 秒基础值，真实时长按连击点计算
    local cpStun = ownCast and ComboPointStunDuration(spellId, targetGuid, effectAuraName, GetTime())
    if cpStun and (not durationMs or durationMs <= 0) then durationMs = cpStun * 1000 end
    if not durationMs or durationMs <= 0 then return end

    if not ownCast and (casterGuid or not HandleJudgement("cast", spellId)) then return end
    local isHot = effectAuraName == 8
    local hostile = CanAttackGUID(targetGuid)
    if isHot then
        if not db.trackHoTs or hostile then return end
    elseif not db.trackTarget or not db.showDebuffs or not hostile then
        return
    end
    if IsDuplicateTargetCast(spellId, targetGuid) then return end

    -- 直接使用事件反馈的实际时长，不在本地做任何扣减，避免显示比实际短
    local duration = durationMs / 1000
    -- 终结技 DoT：事件只回占位时长，用刚消耗的连击点推算真实时长
    if ownCast then
        local cpDuration = ComboPointDoTDuration(spellId, targetGuid, effectAuraName, durationMs, GetTime())
        if CT.drDebug and effectAuraName == 3 then
            Print("[CP] " .. tostring(SpellName(spellId) or spellId)
                .. " event=" .. tostring(durationMs) .. "ms"
                .. " dbc=" .. tostring(SpellBaseDurationMs(spellId) or "nil")
                .. " cp=" .. tostring(cpHold)
                .. " -> " .. tostring(cpDuration))
        end
        if cpDuration and cpDuration > duration then duration = cpDuration end
        -- 肾击：事件只给 1 秒基础值时改用连击点推算的时长
        if cpStun and duration <= 1.5 and cpStun > duration then duration = cpStun end
    end
    local auraKind = isHot and "hot" or (effectAuraName == 3 and "dot" or "debuff")
    if CT.auraDebug then
        Print("[CAST] " .. tostring(SpellName(spellId) or spellId) .. " dur=" .. tostring(duration)
            .. "s 原始=" .. tostring(durationMs) .. "ms aura=" .. tostring(effectAuraName))
    end
    RememberUnit(targetGuid)
    ApplyTargetDebuff(spellId, targetGuid, duration, nil, effectAuraName, auraKind,
        SpellCastName(spellId))
end

local function HandleExternalAdded(isDebuff, targetGuid, spellId, stacks)
    if not initialized or not db.enabled or not targetGuid or not spellId then return end
    if isDebuff and spellId == FIRE_VULNERABILITY_ID then
        if db.trackTarget and db.showDebuffs and db.trackFireVulnerability then
            stacks = math.min(stacks or 1, FIRE_VULNERABILITY_MAX_STACKS)
            RememberUnit(targetGuid)
            ApplyTargetDebuff(FIRE_VULNERABILITY_ID, targetGuid, FireVulnerabilityDuration(),
                stacks, nil, "shared")
        end
        return
    end
    stacks = stacks or 1
    if CT.auraDebug and isDebuff then
        Print("[ADD] " .. tostring(SpellName(spellId) or spellId) .. " 事件层数=" .. tostring(stacks)
            .. " 字段层数=" .. tostring(ReadAuraStacks(targetGuid, spellId)))
    end
    local key = ExternalKey(spellId, targetGuid)
    targetStacks[key] = { guid = targetGuid, stacks = stacks, at = GetTime() }
    RememberUnit(targetGuid)

    local v = active[key]
    if isDebuff and not v and db.trackTarget and db.showDebuffs then
        local curGuid = GetUnitGUID and GetUnitGUID("target")
        if curGuid and targetGuid == curGuid then
            HandleJudgement("added", spellId, targetGuid, stacks)
            v = active[key]
        end
    end
    if v then
        -- 新增/叠层事件说明光环此刻仍在目标身上：续满时长并取消待移除，
        -- 避免叠层刷新后计时按旧的到期时间被提前清掉
        local now = GetTime()
        v.refreshedAt = now
        CancelExternalRemoval(key)
        if v.duration and v.duration > 0 then
            v.endsAt = now + v.duration
            candy:SetCandyBarTime(v.id, v.duration)
            candy:StartCandyBar(v.id, false)
        end
        if v.stacks ~= stacks then
            v.stacks = stacks
            candy:SetCandyBarText(v.id, BuildText(v.name, stacks, v.targetName))
            ApplyStacksText(v.id, stacks)
        end
    end
end

local function HandleExternalRemoved(targetGuid, spellId, stacks)
    if initialized and targetGuid and spellId then
        if CT.auraDebug then
            Print("[REM] " .. tostring(SpellName(spellId) or spellId) .. " 事件层数=" .. tostring(stacks)
                .. " 字段层数=" .. tostring(ReadAuraStacks(targetGuid, spellId)))
        end
        RemoveExternalAura(targetGuid, spellId)
    end
end

local function HandleUnitDied(unitOrGuid)
    if not initialized or not unitOrGuid then return end
    local guid = unitOrGuid
    if UnitExists and GetUnitGUID then
        local ok, exists = pcall(UnitExists, unitOrGuid)
        if ok and exists then guid = GetUnitGUID(unitOrGuid) or guid end
    end
    RemoveUnitBars(guid)
end

ev:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        Init()

    elseif event == "PLAYER_LOGIN" then
        if initialized then CT.UpdateTotemicMasteryBonus() end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if initialized then
            ClearAll()
            ScanAuras(true)
            CT.UpdateTotemicMasteryBonus()
        else
            Init()   -- 依赖库加载较慢时再尝试一次
        end

    elseif event == "PLAYER_TALENT_UPDATE" or event == "CHARACTER_POINTS_CHANGED" then
        if initialized then CT.UpdateTotemicMasteryBonus() end

    elseif event == "PLAYER_AURAS_CHANGED" then
        if initialized then ScanAuras(false) end

    elseif event == "UNIT_AURA" then
        if initialized and (arg1 == "player" or arg1 == nil) then
            ScanAuras(false)
        end

    elseif event == "BUFF_ADDED_SELF" or event == "BUFF_REMOVED_SELF"
        or event == "DEBUFF_ADDED_SELF" or event == "DEBUFF_REMOVED_SELF" then
        if initialized then ScanAuras(false) end

    elseif event == "SPELL_GO_SELF" then
        -- 参数：arg2 = spellId
        if initialized then
            OnTotemCast(arg2)
            OnEnslaveCast(arg2)
            HandleFireVulnerabilitySpellGo(arg2, arg4, arg6, arg7)
        end

    elseif event == "AURA_CAST_ON_SELF" then
        -- 参数：spellId, casterGuid, ...；记录该 Buff 最近一次是否由自己/宠物施放
        if arg1 and arg1 > 0 then
            selfCastSeen  = true
            selfCastAuras[arg1] = IsCasterSelf(arg2)
            if initialized and db.selfBuffsOnly then
                pendingScan = true
            end
        end

    elseif event == "AURA_CAST_ON_OTHER" then
        -- 参数：spellId, casterGuid, targetGuid, effect, effectAuraName,
        --       amplitude, miscValue, durationMs, auraCapStatus（Nampower 实际签名）
        if initialized then CT.DebugAuraCast(arg1, arg2, arg3, arg4, arg5, arg8, arg9) end
        HandleExternalCast(arg1, arg2, arg3, arg5, arg8)

    elseif event == "AUTO_ATTACK_SELF" or event == "AUTO_ATTACK_OTHER" then
        -- Turtle 机制：审判 Debuff 随圣骑士近战命中刷新，同步重置计时条
        local attackerGuid, hitGuid = arg1, arg2
        local myGuid = GetUnitGUID and GetUnitGUID("player")
        if initialized and myGuid and attackerGuid == myGuid and hitGuid then
            HandleJudgement("hit", nil, hitGuid)
        end

    elseif event == "BUFF_ADDED_OTHER" then
        HandleExternalAdded(false, arg1, arg3, arg4)

    elseif event == "DEBUFF_ADDED_OTHER" then
        HandleExternalAdded(true, arg1, arg3, arg4)

    elseif event == "BUFF_REMOVED_OTHER" or event == "DEBUFF_REMOVED_OTHER" then
        HandleExternalRemoved(arg1, arg3, arg4)

    elseif event == "UNIT_DIED" then
        HandleUnitDied(arg1)

    elseif event == "PLAYER_TARGET_CHANGED" then
        if initialized and GetUnitGUID then
            local guid = GetUnitGUID("target")
            if guid then RememberUnit(guid) end
        end

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        if initialized then
            ClearAll()
            ScanAuras(true)
        end

    elseif event == "PLAYER_DEAD" then
        if initialized then ClearAll() end
    end
end)

ev:SetScript("OnUpdate", function()
    if not initialized then return end
    local now = GetTime()
    UpdatePendingRemovals(now)
    if (now - cpPollAt) >= CP_POLL_INTERVAL then
        cpPollAt = now
        PollComboPoints(now)
    end
    if (now - lastScan) >= 1.0 then
        ScanAuras(true)
    elseif pendingScan and (now - lastScan) >= 0.1 then
        ScanAuras(true)
    end
end)
