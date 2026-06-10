-- [[ SpellComboHistory 로직 흐름도 (Logic Flow) ]]
--
--  1. 이벤트 수신 (OnEvent)
--     - UNIT_SPELLCAST_START: 시전 스킬의 시작 시간 기록 (pendingCasts)
--     - UNIT_SPELLCAST_SUCCEEDED: 스킬 성공 시 바구니(frameSpells)에 담고 0.01초 타이머 작동
--
--  2. 버퍼링 및 수집 (C_Timer 0.01s)
--     - 연타나 매크로로 동시에 발생하는 여러 스킬을 하나로 묶어 처리 대기
--
--  3. 핵심 분석 (ProcessFrameSpells)
--     - [글쿨 판정]: 공용 글굴(61304)의 변화를 감지 (threshold 0.1s)
--     - [주인공 탐색]: 프레임 내 스킬 중 실제 글굴을 돌린 스킬 탐색 (gcdSpellIndex)
--     - [지연 계산]: (현재 스킬 시작 시각) - (이전 스킬 글굴 종료 시각) = 딜로스(wasteTime)
--     - [성적 부여]: 딜로스 <= 세계지연시간(핑) 이면 PERFECT 판정 및 콤보 +1
--
--  4. UI 갱신 (UpdateHistory)
--     - [아이콘 밀기]: 기존 아이콘들을 왼쪽으로 한 칸씩 이동
--     - [새 아이콘]: 1번 자리에 최신 스킬 아이콘 생성 및 그림 설정
--     - [텍스트 출력]: 판정 결과(START, PERFECT, 딜로스 초) 및 콤보 등급(STREAK 등) 표시
--
--  5. 설정 관리 (InitializeOptions)
--     - 사용자의 설정(잠금, 개수, 투명도 등)에 따라 실시간으로 배경(UpdateMainBackground) 및 가이드(UpdateDummyFrames) 갱신
-- -----------------------------------------------------------------------------------------------------------------------

-- [SpellComboHistory] 애드온 시작
-- 자주 사용하는 전역 함수들을 로컬로 불러와 성능 최적화 (Upvalue)
local GetTime = GetTime
-- 스킬의 기본 재사용 대기시간 정보를 가져오는 함수 로컬화
local GetSpellBaseCooldown = GetSpellBaseCooldown
-- 플레이어가 현재 전투 중인지 확인하는 함수 로컬화
local InCombatLockdown = InCombatLockdown
-- 전투 중인지 여부를 유닛 상태로 확인하는 함수 로컬화
local UnitAffectingCombat = UnitAffectingCombat
-- 네트워크 상태(핑 정보 등)를 가져오는 함수 로컬화
local GetNetStats = GetNetStats

-- 최신 와우 API와 구형 API 간의 호환성을 위해 스킬 정보 함수 로컬화
local GetSpellInfo = GetSpellInfo or function(id) return C_Spell.GetSpellInfo(id) end
-- 최신 와우 API와 구형 API 간의 호환성을 위해 스킬 쿨다운 함수 로컬화
local GetSpellCooldown = GetSpellCooldown or function(id) return C_Spell.GetSpellCooldown(id) end

-- 특정 스킬의 쿨다운 지속 시간(Duration)만 안전하게 가져오는 헬퍼 함수
local function GetSpellCooldownDuration(spellID)
    -- 최신 C_Spell API가 존재하는지 확인
    if C_Spell and C_Spell.GetSpellCooldown then
        -- 최신 API로 쿨다운 정보 획득
        local cd = C_Spell.GetSpellCooldown(spellID)
        -- 정보가 있으면 지속 시간을, 없으면 0을 반환
        return cd and cd.duration or 0
    end
    -- 구형 API로 쿨다운 지속 시간 획득
    local _, dur = GetSpellCooldown(spellID)
    -- 결과가 있으면 반환, 없으면 0을 반환
    return dur or 0
end

-- 이벤트를 수신할 메인 프레임 생성
local frame = CreateFrame("Frame", "SpellComboHistoryFrame", UIParent)
-- 스킬 사용 성공 이벤트를 프레임에 등록
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
-- 채널링 시작 및 종료 이벤트를 프레임에 등록
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")

-- 이전 스킬의 글로벌 쿨다운이 끝난 예상 시점 저장 변수
local lastGcdEndTime = 0
-- 이전 스킬의 글로벌 쿨다운이 시작된 시점 저장 변수
local lastGcdStartTime = 0
-- 이전 채널링 스킬이 끝난 시점 저장 변수
local lastChannelEndTime = 0
-- 현재 연속으로 성공한 PERFECT 콤보 횟수 저장 변수
local perfectCombo = 0
-- 전투 시작 시 "START" 문구를 띄우기 위한 상태 변수
local pendingStart = false
-- 생성된 아이콘 객체들을 담아두는 테이블
local icons = {} 
-- 화면에 표시될 아이콘의 가로세로 크기 (픽셀)
local ICON_SIZE = 40
-- 아이콘과 아이콘 사이의 간격 (픽셀)
local SPACING = 10

-- 아이콘 블록의 위치를 조정하는 이동 핸들 프레임 생성
local anchor = CreateFrame("Frame", "SpellComboHistoryAnchor", UIParent)
-- 핸들의 크기를 기본 아이콘 크기와 맞춤
anchor:SetSize(ICON_SIZE, ICON_SIZE)
-- 화면 중앙을 기본 위치로 설정
anchor:SetPoint("CENTER", 0, 0)
-- 프레임을 마우스로 움직일 수 있도록 설정
anchor:SetMovable(true)
-- 기본 상태에서는 마우스 클릭을 무시 (잠금 해제 시에만 활성화)
anchor:EnableMouse(false)
-- 왼쪽 버튼 드래그로 이동 가능하게 등록
anchor:RegisterForDrag("LeftButton")

-- 마우스 드래그 시 좌표 오프셋을 저장할 변수
local dragOffsetX, dragOffsetY = 0, 0

-- 화면 격자 표시용 프레임 생성 함수
local gridFrame
local function CreateGrid()
    if gridFrame then return end
    gridFrame = CreateFrame("Frame", nil, UIParent)
    gridFrame:SetAllPoints()
    gridFrame:SetFrameStrata("BACKGROUND")
    
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    -- 가로선 (40px 간격)
    for i = 0, h, 40 do
        local t = gridFrame:CreateTexture(nil, "BACKGROUND")
        t:SetHeight(1)
        t:SetPoint("LEFT", gridFrame, "LEFT")
        t:SetPoint("RIGHT", gridFrame, "RIGHT")
        t:SetPoint("BOTTOM", gridFrame, "BOTTOM", 0, i)
        t:SetColorTexture(1, 1, 1, 0.15)
    end
    -- 세로선 (40px 간격)
    for i = 0, w, 40 do
        local t = gridFrame:CreateTexture(nil, "BACKGROUND")
        t:SetWidth(1)
        t:SetPoint("TOP", gridFrame, "TOP", 0, 0)
        t:SetPoint("BOTTOM", gridFrame, "BOTTOM", 0, 0)
        t:SetPoint("LEFT", gridFrame, "LEFT", i, 0)
        t:SetColorTexture(1, 1, 1, 0.15)
    end
    -- 중앙 십자선 (진한 화이트 색상, 가이드용)
    gridFrame.vCenter = gridFrame:CreateTexture(nil, "ARTWORK")
    gridFrame.vCenter:SetWidth(2)
    gridFrame.vCenter:SetPoint("TOP", gridFrame, "TOP", 0, 0)
    gridFrame.vCenter:SetPoint("BOTTOM", gridFrame, "BOTTOM", 0, 0)
    gridFrame.vCenter:SetPoint("CENTER", gridFrame, "CENTER")
    gridFrame.vCenter:SetColorTexture(1, 1, 1, 0.4)
    
    gridFrame.hCenter = gridFrame:CreateTexture(nil, "ARTWORK")
    gridFrame.hCenter:SetHeight(2)
    gridFrame.hCenter:SetPoint("LEFT", gridFrame, "LEFT")
    gridFrame.hCenter:SetPoint("RIGHT", gridFrame, "RIGHT")
    gridFrame.hCenter:SetPoint("CENTER", gridFrame, "CENTER")
    gridFrame.hCenter:SetColorTexture(1, 1, 1, 0.4)
end

local function ToggleGrid(show)
    if show and SpellComboHistoryDB.useGrid then
        CreateGrid()
        gridFrame:Show()
    elseif gridFrame then
        gridFrame:Hide()
    end
end
-- 드래그를 시작했을 때 실행되는 스크립트
anchor:SetScript("OnDragStart", function(self)
    -- 현재 마우스 커서의 좌표 획득
    local cx, cy = GetCursorPosition()
    -- 와우 UI 스케일 값을 가져와 좌표 보정
    local scale = UIParent:GetEffectiveScale()
    -- 스케일이 적용된 실제 마우스 좌표 계산
    cx, cy = cx / scale, cy / scale
    -- 핸들 프레임의 현재 왼쪽과 아래쪽 좌표 획득
    local left, bottom = self:GetLeft(), self:GetBottom()
    -- 마우스 좌표와 프레임 좌표의 차이(오프셋) 계산
    dragOffsetX = cx - left
    -- 마우스 좌표와 프레임 좌표의 차이(오프셋) 계산
    dragOffsetY = cy - bottom
    
    -- 드래그 중 매 프레임마다 위치를 갱신하는 스크립트 설정
    self:SetScript("OnUpdate", function(self)
        -- 현재 마우스 좌표 다시 획득
        local nx, ny = GetCursorPosition()
        -- 다시 UI 스케일 보정
        local scale = UIParent:GetEffectiveScale()
        -- 보정된 마우스 좌표 계산
        nx, ny = nx / scale, ny / scale
        
        -- 마우스 좌표에서 오프셋을 빼서 새로운 프레임 위치 계산
        local newLeft = nx - dragOffsetX
        -- 마우스 좌표에서 오프셋을 빼서 새로운 프레임 위치 계산
        local newBottom = ny - dragOffsetY
        
        -- 현재 설정된 최대 아이콘 개수 획득
        local maxIcons = (SpellComboHistoryDB and SpellComboHistoryDB.maxIcons) or 6
        -- 현재 UI 스케일 획득
        local currentScale = self:GetScale()
        -- 1번 아이콘(anchor)의 시각적 크기
        local visualIconSize = ICON_SIZE * currentScale
        -- 아이콘들 사이의 간격을 포함한 총 오프셋 (1번 중심부터 N번 중심까지의 거리)
        local totalOffset = (maxIcons - 1) * (ICON_SIZE + SPACING) * currentScale
        
        -- 현재 마우스 위치를 기준으로 계산된 anchor의 중심점
        local anchorCenterX = newLeft + visualIconSize / 2
        local anchorCenterY = newBottom + visualIconSize / 2
        
        -- 전체 아이콘 블록(박스)의 기하학적 중심점 계산
        -- 아이콘들이 왼쪽으로 나열되므로, 중심점은 1번 아이콘 중심에서 총 오프셋의 절반만큼 왼쪽으로 간 지점입니다.
        local blockCenterX = anchorCenterX - (totalOffset / 2)
        local blockCenterY = anchorCenterY
        
        -- 전체 화면의 너비와 높이 획득
        local screenWidth = UIParent:GetWidth()
        local screenHeight = UIParent:GetHeight()
        
        -- 자석 효과가 적용된 중심점을 바탕으로 다시 anchor의 BOTTOMLEFT 좌표 산출
        local finalAnchorCenterX = blockCenterX + (totalOffset / 2)
        local finalLeft = finalAnchorCenterX - visualIconSize / 2
        local finalBottom = blockCenterY - visualIconSize / 2

        -- 격자 자석 효과 (사용 시 10px 단위로 정렬)
        if SpellComboHistoryDB.useGrid then
            finalLeft = math.floor(finalLeft / 10 + 0.5) * 10
            finalBottom = math.floor(finalBottom / 10 + 0.5) * 10
        end
        
        -- 프레임의 기존 위치 정보 삭제
        self:ClearAllPoints()
        -- 계산된 최종 좌표를 기준으로 프레임 재배치용 최종 좌표 설정
        self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", finalLeft, finalBottom)
    end)
end)

-- 드래그를 멈췄을 때 실행되는 스크립트
anchor:SetScript("OnDragStop", function(self)
    -- 위치 갱신 스크립트 제거
    self:SetScript("OnUpdate", nil)
    -- 현재 프레임의 최종 위치 정보 획득
    local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
    -- 세이브 파일에 기준점 저장
    SpellComboHistoryDB.point = point
    -- 세이브 파일에 X좌표 저장
    SpellComboHistoryDB.x = xOfs
    -- 세이브 파일에 Y좌표 저장
    SpellComboHistoryDB.y = yOfs
end)

-- 우클릭 시 즉시 잠금 기능 추가
anchor:SetScript("OnMouseDown", function(self, button)
    if button == "RightButton" then
        -- 위치 잠금 활성화
        SpellComboHistoryDB.isLocked = true
        -- 마우스 반응 비활성화
        self:EnableMouse(false)
        -- 가이드 프레임 및 격자 숨김
        UpdateDummyFrames(false)
        -- 설정창의 체크박스 상태 동기화
        if _G["SpellComboHistoryLockCheck"] then
            _G["SpellComboHistoryLockCheck"]:SetChecked(true)
        end
        print("|cff00ccff[SpellCombo] |rPosition locked via Right-click. (우클릭으로 위치가 잠겼습니다.)")
    end
end)

-- 이동 핸들 위에 표시될 텍스트를 담을 고레벨 프레임 생성 (아이콘보다 위에 보이게 함)
anchor.textFrame = CreateFrame("Frame", nil, anchor)
anchor.textFrame:SetAllPoints()
anchor.textFrame:SetFrameLevel(100) -- 아이콘 프레임들보다 높은 레벨 설정
anchor.textFrame:EnableMouse(false) -- 마우스 클릭이 관통되어 아래의 anchor가 잡히도록 설정

-- 이동 핸들 위에 표시될 텍스트 객체 생성
anchor.text = anchor.textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
-- 이동 방법 및 잠금 안내 문구 설정
anchor.text:SetText("MOVE (이동)\nRight-click to Lock (우클릭: 위치 잠금)")
-- 텍스트 정렬을 중앙으로 설정
anchor.text:SetJustifyH("CENTER")
-- 기본적으로 텍스트 프레임은 숨김 상태
anchor.textFrame:Hide()

-- 아이콘 바 전체의 배경 텍스처 생성
anchor.mainBg = anchor:CreateTexture(nil, "BACKGROUND")
-- 배경에 기본 검은색 반투명 색상 입힘
anchor.mainBg:SetColorTexture(0, 0, 0, 0.5)

-- 배경 바의 크기와 투명도를 설정값에 맞춰 갱신하는 함수
local function UpdateMainBackground()
    -- 현재 설정된 최대 아이콘 개수 획득
    local maxIcons = (SpellComboHistoryDB and SpellComboHistoryDB.maxIcons) or 6
    -- 아이콘들이 차지하는 전체 너비 계산
    local blockWidth = ICON_SIZE + (maxIcons - 1) * (ICON_SIZE + SPACING)
    
    -- 배경의 기존 위치 정보 삭제
    anchor.mainBg:ClearAllPoints()
    -- 우상단 기준점 설정 (여백 5px)
    anchor.mainBg:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 5, 5)
    -- 좌하단 기준점을 아이콘 블록 끝에 맞춤 (여백 5px)
    anchor.mainBg:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -(blockWidth - ICON_SIZE) - 5, -5)
    
    -- 세이브 파일에서 설정된 배경 투명도 획득
    local alpha = (SpellComboHistoryDB and SpellComboHistoryDB.bgAlpha)
    -- 설정값이 없으면 기본값 0.5 사용
    if alpha == nil then alpha = 0.5 end
    -- 배경에 최종 투명도 적용
    anchor.mainBg:SetColorTexture(0, 0, 0, alpha)
end

-- 설정 모드(잠금 해제) 시 가짜 프레임을 보여주거나 숨기는 함수
function UpdateDummyFrames(show)
    -- 숨겨야 하는 상황일 때
    if not show then
        -- 안내 텍스트 프레임 숨김
        if anchor.textFrame then anchor.textFrame:Hide() end
        -- 마우스 클릭 감지 영역을 원래대로 되돌림
        anchor:SetHitRectInsets(0, 0, 0, 0)
        -- 격자 숨김
        ToggleGrid(false)
        -- 아이콘 마우스 반응 복구
        for i = 1, #icons do
            if icons[i] then icons[i]:EnableMouse(true) end
        end
        -- 함수 종료
        return
    end

    -- 격자 표시
    ToggleGrid(true)

    -- 현재 최대 아이콘 개수 획득
    local maxIcons = (SpellComboHistoryDB and SpellComboHistoryDB.maxIcons) or 6
    -- 전체 너비 계산
    local blockWidth = ICON_SIZE + (maxIcons - 1) * (ICON_SIZE + SPACING)
    -- 전체 아이콘 블록의 중앙에 텍스트 배치
    anchor.text:ClearAllPoints()
    anchor.text:SetPoint("CENTER", anchor, "CENTER", -((blockWidth - ICON_SIZE) / 2), 0)
    -- 안내 텍스트 프레임 표시 (고레벨 프레임이라 아이콘을 덮음)
    anchor.textFrame:Show()
    
    -- 마우스로 드래그할 수 있는 영역을 전체 바 크기로 확장
    anchor:SetHitRectInsets(-(blockWidth - ICON_SIZE), 0, 0, 0)
    
    -- 이동 중 아이콘이 클릭을 방해하지 않도록 마우스 반응 비활성화
    for i = 1, #icons do
        if icons[i] then
            icons[i]:EnableMouse(not show)
        end
    end
end

-- 개별 스킬 아이콘 프레임을 생성하는 함수
local function CreateIcon()
    -- 새 프레임 생성 (anchor의 자식으로 설정하여 함께 스케일링되도록 함)
    local f = CreateFrame("Frame", nil, anchor)
    -- 기본 아이콘 크기 설정
    f:SetSize(ICON_SIZE, ICON_SIZE)
    
    -- 스킬 그림을 보여줄 텍스처 객체 생성
    f.tex = f:CreateTexture(nil, "ARTWORK")
    -- 텍스처를 프레임 전체에 꽉 채움
    f.tex:SetAllPoints()
    
    -- 지연 시간이나 PERFECT를 표시할 폰트 스트링 생성
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- 아이콘 바로 위에 배치 (여백 5px)
    f.text:SetPoint("BOTTOM", f, "TOP", 0, 5)
    -- 딜로스 표시용 기본 색상(빨간색) 설정
    f.text:SetTextColor(1, 0, 0) 
    
    -- 기본 폰트와 크기 획득
    local font, size = f.text:GetFont()
    -- 외곽선 효과 적용하여 가독성 높임
    f.text:SetFont(font, size, "OUTLINE")
    -- 나중에 폰트 크기를 변경하기 위해 원본 정보 저장
    f.baseFont = font
    -- 원본 크기 저장
    f.baseSize = size
    
    -- 콤보 등급(STREAK 등)을 표시할 별도의 폰트 스트링 생성
    f.comboText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- 지연 시간 텍스트 위에 배치
    f.comboText:SetPoint("BOTTOM", f.text, "TOP", 0, 2)
    -- 기본 폰트보다 약간 작게 설정
    f.comboText:SetFont(font, size * 0.9, "OUTLINE")
    -- 콤보 등급용 금색 계열 색상 설정
    f.comboText:SetTextColor(1, 0.8, 0)
    
    -- 마우스 클릭 및 올리기 이벤트 활성화
    f:EnableMouse(true)
    -- 마우스를 올렸을 때 실행되는 스크립트
    f:SetScript("OnEnter", function(self)
        -- 현재 아이콘에 등록된 스킬 ID가 있다면
        if self.spellID then
            -- 게임 툴팁 위치를 아이콘 위로 설정
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            -- 해당 스킬의 툴팁 정보 표시
            GameTooltip:SetSpellByID(self.spellID)
            -- 툴팁 창 띄우기
            GameTooltip:Show()
        end
    end)
    -- 마우스가 아이콘을 벗어났을 때 실행되는 스크립트
    f:SetScript("OnLeave", function(self)
        -- 툴팁 숨기기
        GameTooltip:Hide()
    end)
    
    -- 생성 시에는 일단 숨김
    f:Hide()
    -- 생성된 아이콘 프레임 반환
    return f
end

-- 콤보 횟수에 따른 문구와 색상 정보를 담은 테이블
local COMBO_LEVELS = {
    -- 50콤보 이상: 전설급
    {count = 50, text = "LEGEND", color = {1, 0.2, 0.2}},
    -- 20콤보 이상: 신급
    {count = 20, text = "GODLIKE", color = {0, 1, 1}},
    -- 10콤보 이상: 광기
    {count = 10, text = "INSANE", color = {1, 0.2, 0.8}},
    -- 5콤보 이상: 학살
    {count = 5,  text = "RAMPAGE", color = {1, 0.5, 0}},
    -- 2콤보 이상: 연속기
    {count = 2,  text = "STREAK",  color = {1, 0.8, 0}},
}

-- 현재 콤보 횟수에 맞는 텍스트와 색상을 반환하는 함수
local function GetComboTextAndColor(combo)
    -- 테이블을 위에서부터 차례대로 검사
    for _, level in ipairs(COMBO_LEVELS) do
        -- 현재 콤보가 해당 기준치 이상이라면
        if combo >= level.count then
            -- 콤보 횟수와 문구를 합쳐서 반환
            return combo .. "\n" .. level.text, unpack(level.color)
        end
    end
    -- 기준 미달 시 아무것도 반환하지 않음
    return nil
end

-- 스킬 사용 내역을 갱신하고 아이콘을 화면에 배치하는 함수
local function UpdateHistory(spellID, wasteTime, isOffGCD, isStart, isPerfect)
    -- 최대 표시 아이콘 개수 획득
    local maxIcons = (SpellComboHistoryDB and SpellComboHistoryDB.maxIcons) or 6
    -- 기존 아이콘들을 왼쪽으로 한 칸씩 밀어내는 루프 (역순)
    for i = maxIcons, 2, -1 do
        -- 바로 이전 칸에 아이콘이 표시 중이라면
        if icons[i-1] and icons[i-1]:IsShown() then
            -- 현재 칸에 아이콘 객체가 없으면 새로 생성
            if not icons[i] then icons[i] = CreateIcon() end
            -- 이전 칸의 스킬 그림 복사
            icons[i].tex:SetTexture(icons[i-1].tex:GetTexture())
            -- 이전 칸의 지연 시간 텍스트 복사
            icons[i].text:SetText(icons[i-1].text:GetText())
            -- 이전 칸의 텍스트 색상 복사
            icons[i].text:SetTextColor(icons[i-1].text:GetTextColor())
            -- 이전 칸의 콤보 등급 텍스트 복사
            icons[i].comboText:SetText(icons[i-1].comboText:GetText())
            -- 이전 칸의 콤보 등급 색상 복사
            icons[i].comboText:SetTextColor(icons[i-1].comboText:GetTextColor())
            -- 이전 칸의 스킬 ID 정보 복사 (툴팁용)
            icons[i].spellID = icons[i-1].spellID
            
            -- 이전 칸의 폰트 설정(크기, 효과 등) 복사
            local font, size, flags = icons[i-1].text:GetFont()
            -- 현재 칸에 폰트 설정 적용
            icons[i].text:SetFont(font, size, flags)
            
            -- 기준점(anchor)으로부터 위치를 왼쪽으로 점차 밀어냄
            icons[i]:SetPoint("CENTER", anchor, "CENTER", -((i-1) * (ICON_SIZE + SPACING)), 0)
            -- 아이콘 표시
            icons[i]:Show()
        end
    end

    -- 가장 최신 스킬이 표시될 1번 아이콘 프레임이 없으면 생성
    if not icons[1] then 
        -- 새 아이콘 생성
        icons[1] = CreateIcon()
    end
    -- 1번 아이콘을 기준점 정중앙에 배치
    icons[1]:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    
    -- 새 스킬의 그림 아이콘 ID를 저장할 변수
    local tex
    -- 최신 스킬 정보 API 사용 시도
    if C_Spell and C_Spell.GetSpellInfo then
        -- 스킬 정보를 가져옴
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        -- 정보가 있으면 아이콘 ID 추출
        tex = spellInfo and spellInfo.iconID
    else
        -- 구형 API를 통해 스킬 아이콘 추출
        local _
        _, _, tex = GetSpellInfo(spellID)
    end
    -- 1번 아이콘에 스킬 그림 적용
    icons[1].tex:SetTexture(tex)
    -- 1번 아이콘에 스킬 ID 저장
    icons[1].spellID = spellID
    
    -- 현재 플레이어의 전투 상태 다시 확인
    local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
    -- 1번 아이콘 객체 로컬 선언
    local icon1 = icons[1]
    -- 텍스트 및 콤보 텍스트 객체 로컬 선언
    local txt, comboTxt = icon1.text, icon1.comboText
    
    -- 이번 스킬이 콤보의 시작(START/RESTART)인 경우
    if isStart then
        -- 강조를 위해 폰트 크기 약간 축소 설정
        txt:SetFont(icon1.baseFont, icon1.baseSize * 0.8, "OUTLINE")
        -- 파란색 계열로 텍스트 색상 설정
        txt:SetTextColor(0, 0.6, 1)
        -- START 또는 RESTART 텍스트 출력
        txt:SetText(isStart)
        -- 콤보 등급은 초기화이므로 숨김
        comboTxt:SetText("")
    -- 비전투 중이거나 글쿨이 없는 유틸성 스킬인 경우
    elseif not inCombat or isOffGCD then
        -- 지연 시간 텍스트 숨김
        txt:SetText("")
        -- 콤보 등급 텍스트 숨김
        comboTxt:SetText("")
    -- PERFECT를 놓쳤고 딜로스 시간이 존재하는 경우
    elseif wasteTime and not isPerfect then
        -- 기본 폰트 크기로 복원
        txt:SetFont(icon1.baseFont, icon1.baseSize, "OUTLINE")
        -- 경고 의미로 빨간색 설정
        txt:SetTextColor(1, 0, 0)
        -- 소수점 둘째 자리까지 딜로스 시간 출력
        txt:SetText(string.format("%.2fs", wasteTime))
        -- 콤보가 끊겼으므로 등급 텍스트 숨김
        comboTxt:SetText("")
    -- PERFECT 판정에 성공한 경우
    else
        -- 깔끔하게 보여주기 위해 폰트 크기 축소
        txt:SetFont(icon1.baseFont, icon1.baseSize * 0.8, "OUTLINE")
        -- 성공 의미로 초록색 설정
        txt:SetTextColor(0, 1, 0)
        -- PERFECT 문구 출력
        txt:SetText("PERFECT")
        -- 현재 콤보 횟수에 맞는 등급 문구와 색상 획득
        local comboStr, r, g, b = GetComboTextAndColor(perfectCombo)
        -- 문구가 있으면 출력, 없으면 빈 칸
        comboTxt:SetText(comboStr or "")
        -- 문구가 존재할 때만 전용 색상 적용
        if comboStr then comboTxt:SetTextColor(r, g, b) end
    end
    -- 1번 아이콘 최종 표시
    icon1:Show()
end

-- 애드온 설정 창 UI를 초기화하는 함수
local function InitializeOptions()
    local panel = CreateFrame("Frame", "SpellComboHistoryOptionsPanel")
    panel.name = "SpellComboHistory"
    
    -- [1] 스크롤 프레임 생성
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

    -- [2] 실제 내용이 담길 컨텐츠 프레임 생성
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(600, 750) -- 설정 항목이 늘어날 경우 이 높이를 조절하세요
    scrollFrame:SetScrollChild(content)

    -- 제목 (content에 배치)
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("Spell Combo History Settings (설정)")

    -- 리스타트 타이머 슬라이더
    local slider = CreateFrame("Slider", "SpellComboHistoryRestartSlider", content, "OptionsSliderTemplate")
    slider:SetPoint("TOP", 0, -80)
    slider:SetMinMaxValues(1, 60)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(SpellComboHistoryDB.restartTimeout)
    _G[slider:GetName() .. "Low"]:SetText("1s")
    _G[slider:GetName() .. "High"]:SetText("60s")
    _G[slider:GetName() .. "Text"]:SetText("Restart Timeout (초기화 대기 시간): " .. SpellComboHistoryDB.restartTimeout .. "s")
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        SpellComboHistoryDB.restartTimeout = value
        _G[self:GetName() .. "Text"]:SetText("Restart Timeout (초기화 대기 시간): " .. value .. "s")
    end)
    
    -- 위치 잠금 체크박스
    local lockCheck = CreateFrame("CheckButton", "SpellComboHistoryLockCheck", content, "ChatConfigCheckButtonTemplate")
    lockCheck:SetPoint("TOP", -80, -130)
    _G[lockCheck:GetName() .. "Text"]:SetText("Lock Position (위치 잠금)")
    lockCheck:SetChecked(SpellComboHistoryDB.isLocked)
    lockCheck:SetScript("OnClick", function(self)
        local isLocked = self:GetChecked()
        SpellComboHistoryDB.isLocked = isLocked
        anchor:EnableMouse(not isLocked)
        UpdateDummyFrames(not isLocked)
    end)

    -- 격자 모드 체크박스
    local gridCheck = CreateFrame("CheckButton", "SpellComboHistoryGridCheck", content, "ChatConfigCheckButtonTemplate")
    gridCheck:SetPoint("TOP", -80, -165)
    _G[gridCheck:GetName() .. "Text"]:SetText("Use Grid & Snap (격자 자석)")
    gridCheck:SetChecked(SpellComboHistoryDB.useGrid)
    gridCheck:SetScript("OnClick", function(self)
        local useGrid = self:GetChecked()
        SpellComboHistoryDB.useGrid = useGrid
        if not SpellComboHistoryDB.isLocked then
            ToggleGrid(useGrid)
        end
    end)
    
    -- 최대 아이콘 개수 슬라이더
    local maxIconsSlider = CreateFrame("Slider", "SpellComboHistoryMaxIconsSlider", content, "OptionsSliderTemplate")
    maxIconsSlider:SetPoint("TOP", 0, -220)
    maxIconsSlider:SetMinMaxValues(4, 12)
    maxIconsSlider:SetValueStep(1)
    maxIconsSlider:SetObeyStepOnDrag(true)
    maxIconsSlider:SetValue(SpellComboHistoryDB.maxIcons)
    _G[maxIconsSlider:GetName() .. "Low"]:SetText("4")
    _G[maxIconsSlider:GetName() .. "High"]:SetText("12")
    _G[maxIconsSlider:GetName() .. "Text"]:SetText("Max Icons (최대 아이콘 개수): " .. SpellComboHistoryDB.maxIcons)
    maxIconsSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        SpellComboHistoryDB.maxIcons = value
        _G[self:GetName() .. "Text"]:SetText("Max Icons (최대 아이콘 개수): " .. value)
        for i = value + 1, #icons do
            if icons[i] then icons[i]:Hide() end
        end
        if not SpellComboHistoryDB.isLocked then
            UpdateDummyFrames(true)
        end
        UpdateMainBackground()
    end)
    
    -- 배경 투명도 슬라이더
    local bgAlphaSlider = CreateFrame("Slider", "SpellComboHistoryBgAlphaSlider", content, "OptionsSliderTemplate")
    bgAlphaSlider:SetPoint("TOP", 0, -290)
    bgAlphaSlider:SetMinMaxValues(0, 1)
    bgAlphaSlider:SetValueStep(0.05)
    bgAlphaSlider:SetObeyStepOnDrag(true)
    bgAlphaSlider:SetValue(SpellComboHistoryDB.bgAlpha or 0.5)
    _G[bgAlphaSlider:GetName() .. "Low"]:SetText("0%")
    _G[bgAlphaSlider:GetName() .. "High"]:SetText("100%")
    local alphaPercent = math.floor((SpellComboHistoryDB.bgAlpha or 0.5) * 100)
    _G[bgAlphaSlider:GetName() .. "Text"]:SetText("Background Transparency (배경 투명도): " .. alphaPercent .. "%")
    bgAlphaSlider:SetScript("OnValueChanged", function(self, value)
        SpellComboHistoryDB.bgAlpha = value
        local percent = math.floor(value * 100)
        _G[self:GetName() .. "Text"]:SetText("Background Transparency (배경 투명도): " .. percent .. "%")
        UpdateMainBackground()
    end)
    
    -- UI 크기 슬라이더 (가로세로 비율 유지)
    local uiScaleSlider = CreateFrame("Slider", "SpellComboHistoryUiScaleSlider", content, "OptionsSliderTemplate")
    uiScaleSlider:SetPoint("TOP", 0, -360)
    uiScaleSlider:SetMinMaxValues(0.5, 2.0)
    uiScaleSlider:SetValueStep(0.05)
    uiScaleSlider:SetObeyStepOnDrag(true)
    uiScaleSlider:SetValue(SpellComboHistoryDB.uiScale or 1.0)
    _G[uiScaleSlider:GetName() .. "Low"]:SetText("50%")
    _G[uiScaleSlider:GetName() .. "High"]:SetText("200%")
    local scalePercent = math.floor((SpellComboHistoryDB.uiScale or 1.0) * 100)
    _G[uiScaleSlider:GetName() .. "Text"]:SetText("UI Scale (전체 크기): " .. scalePercent .. "%")
    uiScaleSlider:SetScript("OnValueChanged", function(self, value)
        SpellComboHistoryDB.uiScale = value
        local percent = math.floor(value * 100)
        _G[self:GetName() .. "Text"]:SetText("UI Scale (전체 크기): " .. percent .. "%")
        anchor:SetScale(value)
    end)

    -- 주문 예약 시간 슬라이더
    local queueSlider = CreateFrame("Slider", "SpellComboHistoryQueueSlider", content, "OptionsSliderTemplate")
    queueSlider:SetPoint("TOP", 0, -450)
    queueSlider:SetMinMaxValues(0, 400)
    queueSlider:SetValueStep(10)
    queueSlider:SetObeyStepOnDrag(true)
    local currentQueue = tonumber(GetCVar("SpellQueueWindow")) or 400
    queueSlider:SetValue(currentQueue)
    _G[queueSlider:GetName() .. "Low"]:SetText("0ms")
    _G[queueSlider:GetName() .. "High"]:SetText("400ms")
    _G[queueSlider:GetName() .. "Text"]:SetText("Spell Queue Window (주문 예약 시간): " .. currentQueue .. "ms")
    queueSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        SetCVar("SpellQueueWindow", value)
        _G[self:GetName() .. "Text"]:SetText("Spell Queue Window (주문 예약 시간): " .. value .. "ms")
    end)

    -- 도움말 문구
    local helpText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    helpText:SetPoint("TOP", queueSlider, "BOTTOM", 0, -20)
    helpText:SetJustifyH("CENTER")
    helpText:SetText("Higher values allow pre-input spells to trigger smoothly but make it difficult to change skills urgently.\nLower values are directly affected by ping, potentially wasting time between spells.\n(높을수록 미리 입력된 스킬이 매끄럽게 발동되나 긴급하게 스킬을 변경하기 어렵습니다.\n낮을수록 핑의 영향을 직접적으로 받아 스킬간 간격이 낭비될 수 있습니다.)")

    -- 현재 수치 확인 버튼 추가
    local checkButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    checkButton:SetSize(200, 30)
    checkButton:SetPoint("TOP", helpText, "BOTTOM", 0, -15)
    checkButton:SetText("Check Current (현재 수치 확인)")
    checkButton:SetScript("OnClick", function()
        local val = GetCVar("SpellQueueWindow")
        print("|cff00ccff[SpellCombo] |rCurrent SpellQueueWindow: |cffffffff" .. val .. "ms")
    end)
    -- 내역 비우기 버튼 추가
    local clearButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    clearButton:SetSize(200, 30)
    clearButton:SetPoint("TOP", checkButton, "BOTTOM", 0, -10)
    clearButton:SetText("Clear History (내역 비우기)")
    clearButton:SetScript("OnClick", function()
        for i = 1, #icons do
            if icons[i] then
                icons[i]:Hide()
                icons[i].spellID = nil
            end
        end
        perfectCombo = 0
        print("|cff00ccff[SpellCombo] |rHistory has been cleared. (스킬 내역이 초기화되었습니다.)")
    end)

    -- 위치 초기화 버튼 추가
    local resetPosButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetPosButton:SetSize(200, 30)
    resetPosButton:SetPoint("TOP", clearButton, "BOTTOM", 0, -10)
    resetPosButton:SetText("Reset Position (위치 초기화)")
    resetPosButton:SetScript("OnClick", function()
        -- 프레임을 화면 중앙으로 이동
        anchor:ClearAllPoints()
        anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        
        -- 현재 위치 정보를 세이브 파일에 저장
        local point, _, _, x, y = anchor:GetPoint()
        SpellComboHistoryDB.point = point
        SpellComboHistoryDB.x = x
        SpellComboHistoryDB.y = y
        
        print("|cff00ccff[SpellCombo] |rPosition has been reset to center. (위치가 화면 중앙으로 초기화되었습니다.)")
    end)
    
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    else
        InterfaceOptions_AddCategory(panel)
    end

end

-- [메인 분석 로직] 한 프레임에 발생한 스킬들을 모아 글쿨 및 콤보 판정 수행을 위한 변수들
local pendingCasts = {}
-- 추가 이벤트 등록
frame:RegisterEvent("ADDON_LOADED")
-- 스킬 시전 시작 이벤트 등록
frame:RegisterEvent("UNIT_SPELLCAST_START")
-- 전투 종료 이벤트 등록
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
-- 전투 시작 이벤트 등록
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
-- 애완동물 대전 이벤트 등록
frame:RegisterEvent("PET_BATTLE_OPENING_START")
frame:RegisterEvent("PET_BATTLE_CLOSE")

-- 한 프레임 내 수집된 스킬들을 임시 저장하는 테이블
local frameSpells = {}
-- 0.01초 대기 후 분석을 실행할 타이머 핸들러
local processingTimer = nil

-- 프레임 내 수집된 스킬들을 분석하여 글쿨 주도권 및 콤보/지연 시간을 계산하는 핵심 함수
local function ProcessFrameSpells()
    -- 다음 분석을 위해 타이머 상태 초기화
    processingTimer = nil
    -- 현재까지 쌓인 스킬 바구니 복제
    local spells = frameSpells
    -- 원본 바구니 비우기
    frameSpells = {}
    
    -- 현재 공용 글쿨바(61304)의 상태를 저장할 변수들
    local currentStart = 0
    -- 공용 글쿨 지속 시간 저장 변수
    local currentDuration = 0
    -- 최신 API 사용 시도
    if C_Spell and C_Spell.GetSpellCooldown then
        -- 61304번(글로벌 쿨다운 전용 가짜 스킬)의 정보 획득
        local cooldownInfo = C_Spell.GetSpellCooldown(61304)
        -- 정보가 있으면 각각 할당
        if cooldownInfo then
            currentStart = cooldownInfo.startTime
            currentDuration = cooldownInfo.duration
        end
    else
        -- 구형 API를 통해 글쿨 정보 획득
        local start, duration = GetSpellCooldown(61304)
        -- 시작점 할당
        currentStart = start or 0
        -- 지속 시간 할당
        currentDuration = duration or 0
    end

    -- 새로운 글쿨 주기가 시작되었는지 확인 (0.1초 문턱값 적용)
    local gcdTriggered = false
    -- 시작 시각이 유효하고 이전 기록과 0.1초 이상 차이가 날 때만 신규 발동으로 인정
    if currentStart > 0 and math.abs(currentStart - lastGcdStartTime) >= 0.1 then
        -- 새로운 글쿨 발동 확인
        gcdTriggered = true
    end

    -- 이번 프레임에 들어온 스킬 중 누가 글쿨의 '진짜 주인공'인지 가려내는 변수
    local gcdSpellIndex = -1
    -- 이번에 글쿨이 새로 돌기 시작했다면
    if gcdTriggered then
        -- 앞에서부터 스킬들을 차례대로 전수 조사
        for i = 1, #spells do
            -- 스킬 정보를 하나씩 꺼냄
            local sp = spells[i]
            -- 시전 시간이 있는 스킬(캐스팅)은 무조건 주인공 자격 1순위
            if sp.castStartTime then
                -- 해당 스킬을 주도권자로 설정
                gcdSpellIndex = i
                -- 탐색 종료
                break
            end
            
            -- 스킬 자신의 현재 쿨다운 지속 시간을 가져옴
            local d = GetSpellCooldownDuration(sp.spellID)
            
            -- 숫자 연산 오류 방지를 위해 pcall로 안전하게 비교
            if pcall(function() return d + 0 end) then
                -- 스킬의 지속 시간이 공용 글굴바 지속 시간과 거의 일치(0.01초 차이)한다면
                if d > 0 and currentDuration > 0 and math.abs(d - currentDuration) < 0.01 then
                    -- 이 스킬이 바로 주인공!
                    gcdSpellIndex = i
                    -- 탐색 종료
                    break
                end
            end
        end

        -- 만약 정확하게 일치하는 걸 못 찾았다면 (0.01초 이상 오차 시)
        if gcdSpellIndex == -1 then
            -- 다시 한 번 순회하며 좀 더 느슨한 기준으로 탐색
            for i = 1, #spells do
                -- 스킬 정보 추출
                local sp = spells[i]
                -- 지속 시간 획득
                local d = GetSpellCooldownDuration(sp.spellID)
                
                -- 다시 안전하게 비교 루틴 실행
                if pcall(function() return d + 0 end) then
                    -- 스킬 지속 시간이 공용 글쿨 시간보다 크거나 거의 비슷하다면
                    if d >= currentDuration - 0.01 then
                        -- 주인공으로 간택
                        gcdSpellIndex = i
                        -- 탐색 종료
                        break
                    end
                end
            end
        end
        
        -- 모든 시도 끝에 주인공을 못 찾았다면 (매우 빠른 연타 시 발생 가능)
        if gcdSpellIndex == -1 then
            -- 가장 먼저 들어온 스킬을 주인공으로 결정하는 안전 장치
            gcdSpellIndex = 1
        end
    end

    -- 월드 핑(인터넷 지연 시간)을 가져와 PERFECT 판정 기준치 계산
    local _, _, _, lagWorld = GetNetStats()
    -- 밀리초를 초 단위로 변환 (예: 50ms -> 0.05s)
    local threshold = lagWorld / 1000

    -- 바구니에 담긴 스킬들을 하나씩 최종 판정하고 UI에 뿌려주는 루프
    for i, sp in ipairs(spells) do
        -- 이 스킬이 데이터베이스상 글로벌 쿨다운을 가진 스킬인지 확인
        local _, gcdMS = GetSpellBaseCooldown(sp.spellID)
        -- 글쿨 속성이 0이면 논-글쿨 스킬임
        local isOffGCD = (gcdMS == 0)
        
        -- 시전 시간이 있는 스킬은 내부 데이터와 상관없이 무조건 글쿨 스킬로 간주
        if sp.castStartTime then
            -- 논-글쿨 여부를 거짓으로 설정
            isOffGCD = false
        end

        -- 이전 스킬과의 딜로스 시간 저장용 변수
        local wasteTime = 0
        -- 현재 시스템 시각 획득
        local now = GetTime()
        -- 캐스팅 스킬이면 실제 시전 시작 시간을, 즉발기면 현재 시각을 기준점으로 사용
        local actionStartTime = sp.castStartTime or now
        -- 첫 시작 여부 저장
        local isStart = false
        -- PERFECT 성공 여부 저장
        local isPerfect = false
        -- 채널링 종료 시점과의 차이 계산용 변수 (충분히 큰 값으로 초기화)
        local channelWaste = 999
        
        -- 현재 플레이어의 실제로 전투 중인지 체크
        local inCombat = InCombatLockdown() or UnitAffectingCombat("player")

        -- 전투 상태일 때만 콤보 로직 수행
        if inCombat then
            -- 전투 시작 후 바로 들어온 첫 스킬인 경우
            if pendingStart then
                -- START 문구 설정
                isStart = "START"
                -- 대기 상태 해제
                pendingStart = false
                -- 콤보 카운트 시작
                perfectCombo = 1
                -- 채널링 종료 기록 초기화
                lastChannelEndTime = 0
                -- 첫 스킬은 항상 PERFECT 성공으로 간주
                isPerfect = true
            -- 글쿨 스킬이면서 유효한 시작 시간을 가지고 있을 때
            elseif not isOffGCD and actionStartTime > 0 then
                -- 설정 파일에서 리스타트 대기 시간 획득 (기본 10초)
                local timeout = (SpellComboHistoryDB and SpellComboHistoryDB.restartTimeout) or 10
                
                -- 이전에 저장된 데이터가 없거나, 너무 오랜만에 스킬을 쓴 경우 (timeout 경과)
                if lastGcdEndTime == 0 or actionStartTime > lastGcdEndTime + timeout then
                    -- 상황에 맞게 START 또는 RESTART 문구 부여
                    isStart = (lastGcdEndTime == 0) and "START" or "RESTART"
                    -- 콤보 카운트 1로 초기화
                    perfectCombo = 1
                    -- 초기화 첫 스킬도 PERFECT 성공으로 인정
                    isPerfect = true
                -- 일반적인 연속 사용(콤보 진행) 상황
                else
                    -- [5단계] 딜로스(wasteTime) 계산 및 PERFECT 판정
                    if actionStartTime > lastGcdEndTime then
                        -- 실제 발생한 딜로스 시간 계산
                        wasteTime = actionStartTime - lastGcdEndTime
                    end
                    
                    -- 발생한 딜로스가 내 핑 정보(threshold) 이하라면 PERFECT 성공
                    isPerfect = (wasteTime <= threshold)
                    
                    -- 혹은 이전 채널링 종료 시점과 거의 일치한다면 PERFECT 성공
                    if not isPerfect and lastChannelEndTime > 0 then
                        channelWaste = math.abs(actionStartTime - lastChannelEndTime)
                        if channelWaste <= threshold then
                            isPerfect = true
                        end
                    end
                    
                    -- 성공 시 콤보 +1, 실패 시 0으로 초기화 (삼항 연산 스타일)
                    perfectCombo = isPerfect and (perfectCombo + 1) or 0
                end
            end
            
            -- 이번에 사용한 스킬이 글쿨 스킬이라면 다음 스킬을 위해 타이머 기록 갱신
            if not isOffGCD and actionStartTime > 0 then
                -- 이전 글쿨 시작점 업데이트 (현재 도착 시각으로 동기화)
                lastGcdStartTime = now
                
                -- 다음 PERFECT 판정을 위해 이 스킬의 글굴이 언제 끝날지 저장
                if sp.castStartTime then
                    -- 시전 스킬은 시전 성공 시점이 바로 글쿨 종료 시점임
                    lastGcdEndTime = now
                else
                    -- 즉발기는 현재 도착 시각 + 공용 글굴 지속 시간을 더해 종료 시점 계산
                    lastGcdEndTime = now + currentDuration
                end
            end
        else
            -- 비전투 상태라면 모든 기록을 초기화하여 찌꺼기 방지
            perfectCombo = 0
            -- 딜로스 시간 초기화
            wasteTime = 0
            -- 판정 상태 초기화
            isPerfect = false
        end

        -- 준비된 모든 정보(스킬ID, 딜로스, 글쿨유무 등)를 보내 UI를 갱신
        UpdateHistory(sp.spellID, wasteTime, isOffGCD, isStart, isPerfect)
    end
end

-- 이벤트 수신 스크립트 최종 등록
frame:SetScript("OnEvent", function(self, event, unit, castID, spellID)
    -- 애드온이 처음 로드되었을 때 (로그인 시)
    if event == "ADDON_LOADED" and unit == "SpellComboHistory" then
        -- 세이브 데이터 테이블이 없으면 빈 테이블로 생성
        SpellComboHistoryDB = SpellComboHistoryDB or {}
        -- 리스타트 대기 시간 기본값 설정
        if SpellComboHistoryDB.restartTimeout == nil then SpellComboHistoryDB.restartTimeout = 10 end
        -- 위치 잠금 상태 기본값 설정
        if SpellComboHistoryDB.isLocked == nil then SpellComboHistoryDB.isLocked = true end
        -- 최대 아이콘 표시 개수 기본값 설정
        if SpellComboHistoryDB.maxIcons == nil then SpellComboHistoryDB.maxIcons = 6 end
        -- 배경 바 투명도 기본값 설정
        if SpellComboHistoryDB.bgAlpha == nil then SpellComboHistoryDB.bgAlpha = 0.5 end
        -- UI 크기(스케일) 기본값 설정
        if SpellComboHistoryDB.uiScale == nil then SpellComboHistoryDB.uiScale = 1.0 end
        -- 격자 모드 기본값 설정
        if SpellComboHistoryDB.useGrid == nil then SpellComboHistoryDB.useGrid = true end
        
        -- UI 스케일 적용
        anchor:SetScale(SpellComboHistoryDB.uiScale)
        
        -- 이전에 저장된 좌표가 있다면 해당 위치로 핸들 프레임 이동
        if SpellComboHistoryDB.point then
            -- 위치 정보 초기화
            anchor:ClearAllPoints()
            -- 저장된 기준점과 좌표 적용
            anchor:SetPoint(SpellComboHistoryDB.point, UIParent, SpellComboHistoryDB.point, SpellComboHistoryDB.x, SpellComboHistoryDB.y)
        end
        
        -- 잠금 여부에 따라 마우스 입력 활성화/비활성화
        anchor:EnableMouse(not SpellComboHistoryDB.isLocked)
        -- 잠금 해제 시 가이드 안내 문구 출력
        UpdateDummyFrames(not SpellComboHistoryDB.isLocked)
        -- 배경 바 크기 및 투명도 갱신
        UpdateMainBackground()
        
        -- 옵션 설정 창 초기화 함수 호출
        InitializeOptions()
        -- 함수 종료
        return
    end
    -- 플레이어가 전투를 마쳤을 때 (적 처치 등)
    if event == "PLAYER_REGEN_ENABLED" then
        -- 첫 시작 플래그 해제
        pendingStart = false
        -- 이전 글쿨 종료 기록 초기화
        lastGcdEndTime = 0
        -- 이전 글쿨 시작 기록 초기화
        lastGcdStartTime = 0
        -- 콤보 카운트 초기화
        perfectCombo = 0
        -- 채널링 종료 기록 초기화
        lastChannelEndTime = 0
        -- 함수 종료
        return
    end
    -- 플레이어가 전투에 돌입했을 때 (선공 등)
    if event == "PLAYER_REGEN_DISABLED" then
        -- 다음 스킬을 START로 표시하기 위해 플래그 설정
        pendingStart = true
        -- 채널링 종료 기록 초기화
        lastChannelEndTime = 0
        -- 함수 종료
        return
    end

    -- 애완동물 대전 시작 시 애드온 숨김
    if event == "PET_BATTLE_OPENING_START" then
        anchor:Hide()
        return
    end
    -- 애완동물 대전 종료 시 애드온 다시 표시
    if event == "PET_BATTLE_CLOSE" then
        anchor:Show()
        return
    end

    -- 이벤트의 대상이 플레이어 본인이 아니면 무시
    if unit ~= "player" then return end
    
    -- 캐스팅(시전) 또는 채널링 스킬을 시작했을 때
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        -- 시작 시각을 고유 캐스트 ID와 함께 기록 (나중에 성공 시 비교용)
        if castID then
            pendingCasts[castID] = GetTime()
        end
        -- 함수 종료
        return
    end

    -- 채널링이 끝났을 때 (자연 종료든 끊겼든)
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- 현재 시각을 채널링 종료 시점으로 기록
        lastChannelEndTime = GetTime()
        -- 함수 종료
        return
    end

    -- 스킬 사용이 최종적으로 성공했을 때
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- 플레이어가 배운(직업/종족) 스킬인지 확인하여 장신구 발동, 특성 내부 오라 등 필터링
        local isPlayerSpell = (C_SpellBook and C_SpellBook.IsSpellInSpellBook and C_SpellBook.IsSpellInSpellBook(spellID)) 
                           or (IsPlayerSpell and IsPlayerSpell(spellID))

        -- 플레이어 스킬이 아니라면 처리할 필요 없음
        if not isPlayerSpell then
            -- 해당 캐스트 데이터 삭제
            if castID then
                pendingCasts[castID] = nil
            end
            -- 함수 종료
            return
        end

        -- [1] 시전 시간 기록이 있다면 가져오고, 사용한 기록은 삭제 (메모리 관리)
        local castStartTime = castID and pendingCasts[castID]
        -- 데이터 파기
        if castID then
            pendingCasts[castID] = nil
        end

        -- [2] 스킬 성공 시점의 글쿨(61304) 시작 시간을 미리 수집 (동기화 보조 데이터)
        local syncStart = 0
        -- 최신 API 사용
        if C_Spell and C_Spell.GetSpellCooldown then
            -- 글굴바 정보 획득
            local cd = C_Spell.GetSpellCooldown(61304)
            -- 시작 시각 할당
            if cd then syncStart = cd.startTime end
        else
            -- 구형 API 사용
            local s = GetSpellCooldown(61304)
            -- 시작 시각 할당
            syncStart = s or 0
        end

        -- [3] 이번 프레임 바구니(frameSpells)에 스킬 정보를 담음
        table.insert(frameSpells, {spellID = spellID, castStartTime = castStartTime, syncStart = syncStart})

        -- [4] 아직 타이머가 돌고 있지 않다면, 0.01초 후에 분석 함수(ProcessFrameSpells)를 실행하도록 예약
        if not processingTimer then
            -- 0.01초 대기 후 핵심 분석 엔진 가동
            processingTimer = C_Timer.After(0.01, ProcessFrameSpells)
        end
    end
end)