-- Options/IgnoreSubPanel.lua - Ignore List canvas subcategory: add a spell by
-- id / name / link, and remove ignored spells from a scrollable list.
local _, ns = ...
local L = ns.L

local GetSpellInfo = GetSpellInfo or function(id) return C_Spell.GetSpellInfo(id) end

local IgnoreSubPanel = {}
ns.IgnoreSubPanel = IgnoreSubPanel

-- Turn user input (ID, name, or spell link) into a spell ID.
local function resolveSpell(input)
    if not input then return nil end
    input = input:gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" then return nil end
    local linkID = input:match("spell:(%d+)")
    if linkID then return tonumber(linkID) end
    local num = tonumber(input)
    if num then return num end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(input)
        if info and info.spellID then return info.spellID end
    end
    return select(7, GetSpellInfo(input))
end

function IgnoreSubPanel:Build(parentCategory)
    local f = CreateFrame("Frame", "SpellHistoryEnhancedIgnoreSubPanel")
    f.name = L["IGNORE_LIST"]

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(L["IGNORE_LIST"])

    local hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    hint:SetWidth(420)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["IGNORE_HINT"])

    local addBox = CreateFrame("EditBox", "SpellHistoryEnhancedIgnoreAddBox", f, "InputBoxTemplate")
    addBox:SetSize(180, 24)
    addBox:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 8, -14)
    addBox:SetAutoFocus(false)

    local addButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addButton:SetSize(90, 24)
    addButton:SetPoint("LEFT", addBox, "RIGHT", 12, 0)
    addButton:SetText(L["IGNORE_ADD"])

    local function commitAdd()
        local id = resolveSpell(addBox:GetText())
        if id and ns.IgnoreList.SpellExists(id) then
            if ns.IgnoreList:Add(id) then
                local name = ns.IgnoreList.GetSpellNameIcon(id)
                print(ns.Constants.PRINT_PREFIX .. string.format(L["MSG_IGNORE_ADDED"], name or id))
            end
            addBox:SetText("")
            addBox:ClearFocus()
        else
            print(ns.Constants.PRINT_PREFIX .. L["MSG_IGNORE_INVALID"])
        end
    end
    addButton:SetScript("OnClick", commitAdd)
    addBox:SetScript("OnEnterPressed", commitAdd)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Scrollable list of ignored spells.
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", addBox, "BOTTOMLEFT", -8, -16)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 16)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(360, 10)
    scroll:SetScrollChild(content)

    local ignoreEmpty = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ignoreEmpty:SetPoint("TOPLEFT", 0, 0)
    ignoreEmpty:SetText(L["IGNORE_EMPTY"])

    local ignoreRows = {}
    local ROW_HEIGHT = 26
    local function rebuildIgnoreList()
        local ids = ns.IgnoreList:GetSorted()
        for _, row in ipairs(ignoreRows) do row:Hide() end
        ignoreEmpty:SetShown(#ids == 0)

        for i, spellID in ipairs(ids) do
            local row = ignoreRows[i]
            if not row then
                row = CreateFrame("Frame", nil, content)
                row:SetSize(340, ROW_HEIGHT)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(20, 20)
                row.icon:SetPoint("LEFT", 0, 0)
                row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
                row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.remove:SetSize(80, 22)
                row.remove:SetPoint("RIGHT", 0, 0)
                row.remove:SetText(L["IGNORE_REMOVE"])
                ignoreRows[i] = row
            end
            row:ClearAllPoints()
            if i == 1 then
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
            else
                row:SetPoint("TOPLEFT", ignoreRows[i - 1], "BOTTOMLEFT", 0, -4)
            end
            local name, icon = ns.IgnoreList.GetSpellNameIcon(spellID)
            row.icon:SetTexture(icon)
            row.name:SetText(name or ("Spell #" .. spellID))
            row.remove:SetScript("OnClick", function()
                if ns.IgnoreList:Remove(spellID) then
                    print(ns.Constants.PRINT_PREFIX .. string.format(L["MSG_IGNORE_REMOVED"], name or spellID))
                end
            end)
            row:Show()
        end

        content:SetSize(360, math.max(10, #ids * (ROW_HEIGHT + 4)))
    end
    self.rebuild = rebuildIgnoreList
    ns.IgnoreList:SetOnChanged(rebuildIgnoreList)
    rebuildIgnoreList()

    Settings.RegisterCanvasLayoutSubcategory(parentCategory, f, f.name)
end

-- Called after a profile switch (if the page was built).
function IgnoreSubPanel:Rebuild()
    if self.rebuild then self.rebuild() end
end
