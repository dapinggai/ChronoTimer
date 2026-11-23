-- ArchiTotem pfUI 皮肤适配
-- pfUI 可能比 ChronoTimer 更晚加载，因此延迟检测并重复尝试，成功后立即停止

local pfui
local applied = false
local hooked = false

local function GetFontPath()
    -- 使用游戏自带字体，避免 pfUI 自定义字体不可用时文字消失
    if GameFontNormal and GameFontNormal.GetFont then
        local p = GameFontNormal:GetFont()
        if p and p ~= "" then return p end
    end
    return "Fonts\\FRIZQT__.TTF"
end

local function GetFontSize()
    local n = pfUI_config and pfUI_config.global and tonumber(pfUI_config.global.font_size)
    return n or 12
end

local function SetFS(fs, size)
    if fs and fs.SetFont then fs:SetFont(GetFontPath(), size, "OUTLINE") end
end

local ELEMENTS = { "Earth", "Fire", "Water", "Air" }
local ELEMENT_MAX = { Earth = 5, Fire = 5, Water = 5, Air = 7 }

local function ElementMax(el)
    local opt = ArchiTotem_Options and ArchiTotem_Options[string.sub(el, 1, 3)]
    return (opt and opt.max) or ELEMENT_MAX[el]
end

local function CropIcon(buttonName)
    local tex = _G[buttonName .. "Texture"]
    if tex and tex.SetTexCoord then
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

local function CropAll()
    for _, el in ipairs(ELEMENTS) do
        for i = 1, ElementMax(el) do
            CropIcon("ArchiTotemButton_" .. el .. i)
        end
    end
    CropIcon("ArchiTotemButton_AllTotems")
    CropIcon("ArchiTotemButton_Recall")
    CropIcon("ArchiTotemButton_PresetManager")
end

local function SafeBackdrop(f)
    if not (pfui and pfui.CreateBackdrop) then return end
    pcall(function()
        if f.GetBackdrop and f:GetBackdrop() then f:SetBackdrop(nil) end
        -- legacy 模式：不扩大点击区域，避免相邻按钮点击重叠
        pfui.CreateBackdrop(f, nil, true)
    end)
end

local function SkinButton(btn)
    if not btn or btn._ctPfSkinned then return end
    btn._ctPfSkinned = true

    local name = btn:GetName()
    if not name then return end

    -- 去掉暴雪风格边框
    local border = _G[name .. "Border"]
    if border and border.SetAlpha then border:SetAlpha(0) end

    if btn.SetNormalTexture then btn:SetNormalTexture("") end
    if btn.SetPushedTexture then btn:SetPushedTexture("") end
    if btn.SetDisabledTexture then btn:SetDisabledTexture("") end

    SafeBackdrop(btn)
    CropIcon(name)

    local fs = GetFontSize()
    SetFS(_G[name .. "CooldownText"], fs)

    if name == "ArchiTotemButton_AllTotems" then
        SetFS(_G["AllTotemsButtonText"], fs)
    elseif name == "ArchiTotemButton_Recall" then
        SetFS(_G["RecallButtonText"], fs)
    elseif name == "ArchiTotemButton_PresetManager" then
        SetFS(_G["PresetManagerButtonText"], fs)
    end
end

local function SkinFrame(f)
    if not f or f._ctPfSkinned then return end
    f._ctPfSkinned = true
    SafeBackdrop(f)
end

local PRESET_FONTS = {
    "ArchiTotemPresetTitle", "ArchiTotemCurrentTitle",
    "ArchiTotemCurrent_EarthText", "ArchiTotemCurrent_FireText",
    "ArchiTotemCurrent_WaterText", "ArchiTotemCurrent_AirText",
    "ArchiTotemSavePresetButtonText", "ArchiTotemPresetScaleValue",
    "ArchiTotemPresetListTitle", "ArchiTotemPresetHelpText",
}

local COVERAGE_FONTS = {
    "ArchiTotemCoverageTitleText",
    "ArchiTotemCoverage_EarthTitle", "ArchiTotemCoverage_EarthNames",
    "ArchiTotemCoverage_FireTitle", "ArchiTotemCoverage_FireNames",
    "ArchiTotemCoverage_WaterTitle", "ArchiTotemCoverage_WaterNames",
    "ArchiTotemCoverage_AirTitle", "ArchiTotemCoverage_AirNames",
}

local function ApplyAll()
    if applied then return end
    if not pfUI or not pfUI.api or not pfUI.api.CreateBackdrop then return end
    pfui = pfUI.api

    for _, el in ipairs(ELEMENTS) do
        for i = 1, ElementMax(el) do
            SkinButton(_G["ArchiTotemButton_" .. el .. i])
        end
    end
    SkinButton(_G["ArchiTotemButton_AllTotems"])
    SkinButton(_G["ArchiTotemButton_Recall"])
    SkinButton(_G["ArchiTotemButton_PresetManager"])

    SkinFrame(_G["ArchiTotemPresetFrame"])
    SkinFrame(_G["ArchiTotemCoverageFrame"])

    local fs = GetFontSize()
    local small = math.max(9, fs - 2)
    for _, n in ipairs(PRESET_FONTS) do SetFS(_G[n], fs) end
    for _, n in ipairs(COVERAGE_FONTS) do SetFS(_G[n], fs) end

    for _, el in ipairs(ELEMENTS) do SetFS(_G[el .. "DurationText"], small) end
    SetFS(_G["AllTotemsDurationText"], small)
    SetFS(_G["RecallDurationText"], small)

    CropAll()

    -- 每次刷新图标纹理后重新裁边（SetTexture 会重置 TexCoord）
    if ArchiTotem_UpdateTextures and not hooked then
        hooked = true
        local orig = ArchiTotem_UpdateTextures
        ArchiTotem_UpdateTextures = function()
            orig()
            CropAll()
        end
    end

    applied = true
end

local f = CreateFrame("Frame", "ChronoTimerArchiPfUI")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function()
    ApplyAll()
    if applied and this and this.UnregisterAllEvents then
        this:UnregisterAllEvents()
    end
end)

f.total = 0
f.acc = 0
f:SetScript("OnUpdate", function()
    if applied then
        this:SetScript("OnUpdate", nil)
        return
    end
    this.total = this.total + arg1
    this.acc = this.acc + arg1
    if this.acc >= 0.25 then
        this.acc = 0
        ApplyAll()
    end
    if this.total > 30 then
        this:SetScript("OnUpdate", nil)
    end
end)
