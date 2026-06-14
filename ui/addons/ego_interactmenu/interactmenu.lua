-- Advanced Captain Manager (ACM) - Lua UI Controller
local ffi = require("ffi")
local C = ffi.C

local categoryId = "advanced_captain_manager"

-- ============================================================
-- [핵심 수정 1] config.sections은 전역 persist 객체.
-- 매 메뉴 오픈마다 우리 카테고리가 누적되어 중복 발생.
-- on_start 진입 시 항상 먼저 정리 후 재삽입.
-- ============================================================
local function cleanup_category(configSections)
    for _, section in ipairs(configSections) do
        if section.subsections then
            for i = #section.subsections, 1, -1 do
                if section.subsections[i].id == categoryId then
                    table.remove(section.subsections, i)
                end
            end
        end
    end
end

-- ============================================================
-- [핵심 수정 2] realMenu.component는 존재하지 않는 필드.
-- 올바른 필드: realMenu.componentSlot.component
-- 지도 우클릭 시 componentSlot이 nil이거나 component가 0.
-- C.IsComponentClass 로 함선 여부 판별 (레퍼런스 모드 동일 방식).
-- ============================================================
local function is_ship_context(realMenu)
    local slot = realMenu.componentSlot
    if not slot then
        DebugError("[ACM UI Debug] No componentSlot - map/position context, skip")
        return false
    end
    local component = slot.component
    if not component or component == 0 then
        DebugError("[ACM UI Debug] componentSlot.component is 0 - not a ship context, skip")
        return false
    end
    local ok, isShip = pcall(function() return C.IsComponentClass(component, "ship") end)
    DebugError("[ACM UI Debug] component=" .. tostring(component) .. " isShip=" .. tostring(ok and isShip))
    return ok and isShip
end

local function get_parent_section(realMenu, playerShips)
    if realMenu.showPlayerInteractions then
        return "player_interaction"
    elseif #playerShips > 1 then
        return "selected_orders_all"
    else
        return "selected_orders"
    end
end

-- ============================================================
-- Hook 1: prepareSections_on_start
-- 카테고리를 subsections에 주입 (정리 후 재삽입)
-- ============================================================
local function on_prepare_sections_start(configSections)
    -- 항상 먼저 정리 (이전 메뉴 오픈에서 남은 항목 제거)
    cleanup_category(configSections)

    local realMenu = Helper.getMenu("InteractMenu")
    if not realMenu then return end

    if not is_ship_context(realMenu) then return end

    local playerShips = realMenu.selectedplayerships
    if not playerShips or #playerShips == 0 then return end

    local categoryName = ReadText(98765, 1)
    if (not categoryName) or (categoryName == "") or (string.find(categoryName, "ReadText")) then
        categoryName = "고급 함장 관리"
    end

    local parentSection = get_parent_section(realMenu, playerShips)
    for _, section in ipairs(configSections) do
        if section.id == parentSection then
            if not section.subsections then section.subsections = {} end
            table.insert(section.subsections, { id = categoryId, text = categoryName })
            DebugError("[ACM UI Debug] Category injected into section: " .. parentSection)
            break
        end
    end
end

-- ============================================================
-- Hook 2: prepareSections_on_end
-- 카테고리 내부 액션 3개 삽입
-- ============================================================
local function on_prepare_sections_end(configSections)
    local realMenu = Helper.getMenu("InteractMenu")
    if not realMenu then return end

    if not is_ship_context(realMenu) then return end

    local playerShips = realMenu.selectedplayerships
    if not playerShips or #playerShips == 0 then return end

    -- 1. 함장 일괄 할당 해제
    local unassignText = ReadText(98765, 2)
    if (not unassignText) or (unassignText == "") or (string.find(unassignText, "ReadText")) then
        unassignText = "함장 일괄 할당 해제"
    end
    local unassignEntry = {
        text = unassignText,
        script = function()
            DebugError("[ACM UI Debug] Unassign clicked! ships: " .. tostring(#playerShips))
            for _, ship in ipairs(playerShips) do
                local ok, err = pcall(function()
                    DebugError("[ACM UI Debug] Sending unassign for: " .. tostring(ship))
                    AddUITriggeredEvent("InteractMenu", "unassign_pilot", ship)
                end)
                if not ok then
                    DebugError("[ACM UI Debug] AddUITriggeredEvent failed: " .. tostring(err))
                end
            end
            realMenu.onCloseElement("close")
        end,
        active = true,
    }

    -- 2. 함장 일괄 배정 (XL>L>M>S 크기 우선순위 순)
    local assignText = ReadText(98765, 3)
    if (not assignText) or (assignText == "") or (string.find(assignText, "ReadText")) then
        assignText = "함장 일괄 배정"
    end
    local classPriority = { ship_xl = 4, ship_l = 3, ship_m = 2, ship_s = 1 }
    local purposePriority = { fight = 4, trade = 3, mine = 2, build = 1 }
    local assignEntry = {
        text = assignText,
        script = function()
            DebugError("[ACM UI Debug] Assign clicked! ships: " .. tostring(#playerShips))
            local sortedShips = {}
            for _, ship in ipairs(playerShips) do table.insert(sortedShips, ship) end
            table.sort(sortedShips, function(a, b)
                local classA = GetComponentData(a, "class") or "ship_s"
                local classB = GetComponentData(b, "class") or "ship_s"
                local pA = classPriority[classA] or 0
                local pB = classPriority[classB] or 0
                if pA ~= pB then return pA > pB end
                local purpA = GetComponentData(a, "primarypurpose") or "trade"
                local purpB = GetComponentData(b, "primarypurpose") or "trade"
                local ppA = purposePriority[purpA] or 0
                local ppB = purposePriority[purpB] or 0
                if ppA ~= ppB then return ppA > ppB end
                local hA = (GetComponentData(a, "maxhull") or 0) + (GetComponentData(a, "maxshield") or 0)
                local hB = (GetComponentData(b, "maxhull") or 0) + (GetComponentData(b, "maxshield") or 0)
                return hA > hB
            end)
            for _, ship in ipairs(sortedShips) do
                local ok, err = pcall(function()
                    DebugError("[ACM UI Debug] Sending assign for: " .. tostring(ship))
                    AddUITriggeredEvent("InteractMenu", "assign_pilot", ship)
                end)
                if not ok then
                    DebugError("[ACM UI Debug] AddUITriggeredEvent failed: " .. tostring(err))
                end
            end
            realMenu.onCloseElement("close")
        end,
        active = true,
    }

    -- 3. 함장 일괄 해고
    local fireText = ReadText(98765, 4)
    if (not fireText) or (fireText == "") or (string.find(fireText, "ReadText")) then
        fireText = "함장 일괄 해고"
    end
    local fireEntry = {
        text = fireText,
        script = function()
            DebugError("[ACM UI Debug] Fire clicked! ships: " .. tostring(#playerShips))
            for _, ship in ipairs(playerShips) do
                local ok, err = pcall(function()
                    DebugError("[ACM UI Debug] Sending fire for: " .. tostring(ship))
                    AddUITriggeredEvent("InteractMenu", "fire_pilot", ship)
                end)
                if not ok then
                    DebugError("[ACM UI Debug] AddUITriggeredEvent failed: " .. tostring(err))
                end
            end
            realMenu.onCloseElement("close")
        end,
        active = true,
    }

    -- 4. [DEBUG] 선원 role 스캔 (실제 controlrole 값 확인용)
    local scanEntry = {
        text = "[DEBUG] 선원 role 스캔",
        script = function()
            DebugError("[ACM UI Debug] Scan clicked! Scanning ship: " .. tostring(playerShips[1]))
            local ok, err = pcall(function()
                AddUITriggeredEvent("InteractMenu", "debug_scan_crew", playerShips[1])
            end)
            if not ok then
                DebugError("[ACM UI Debug] Scan failed: " .. tostring(err))
            end
            realMenu.onCloseElement("close")
        end,
        active = true,
    }

    if realMenu.insertInteractionContent then
        pcall(function()
            realMenu.insertInteractionContent(categoryId, unassignEntry)
            realMenu.insertInteractionContent(categoryId, assignEntry)
            realMenu.insertInteractionContent(categoryId, fireEntry)
            realMenu.insertInteractionContent(categoryId, scanEntry)
        end)
    end
end

-- ============================================================
-- 초기화
-- ============================================================
local function init()
    DebugError("[ACM Debug] interactmenu.lua init called!")

    if UIExtensions and UIExtensions.register then
        UIExtensions.register("interactmenu", "prepareSections_on_start", on_prepare_sections_start)
        UIExtensions.register("interactmenu", "prepareSections_on_end", on_prepare_sections_end)
        DebugError("[ACM Debug] Registered hooks via UIExtensions.register!")
    else
        DebugError("[ACM Debug] UIExtensions nil, trying Helper fallback...")
        local m = Helper.getMenu("InteractMenu")
        if m then
            m.registerCallback("prepareSections_on_start", on_prepare_sections_start, "advanced_captain_manager_start")
            m.registerCallback("prepareSections_on_end", on_prepare_sections_end, "advanced_captain_manager_end")
            DebugError("[ACM Debug] Registered hooks via Helper.getMenu fallback!")
        else
            DebugError("[ACM Debug] All registration methods failed.")
        end
    end
end

init()
