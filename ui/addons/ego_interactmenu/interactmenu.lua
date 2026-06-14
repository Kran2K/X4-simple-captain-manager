-- Advanced Captain Manager (ACM) - Lua UI Controller
-- Extended with Kuertee's UI Extensions & HUD

local categoryId = "advanced_captain_manager"

local function get_parent_section(realMenu, playerShips)
    local parentSection = "selected_orders"
    if realMenu.showPlayerInteractions then
        parentSection = "player_interaction"
    elseif #playerShips > 1 then
        parentSection = "selected_orders_all"
    end
    return parentSection
end

-- 1. prepareSections_on_start: 카테고리를 subsections에 안전하게 주입
local function on_prepare_sections_start(configSections)
    local realMenu = Helper.getMenu("InteractMenu")
    if not realMenu then return end

    local playerShips = realMenu.selectedplayerships
    if not playerShips or #playerShips == 0 then
        return
    end

    local categoryName = ReadText(98765, 1)
    if (not categoryName) or (categoryName == "") or (string.find(categoryName, "ReadText")) then
        categoryName = "고급 함장 관리"
    end

    local parentSection = get_parent_section(realMenu, playerShips)

    -- parentSection의 subsections에 카테고리 주입
    for _, section in ipairs(configSections) do
        if section.id == parentSection then
            if not section.subsections then
                section.subsections = {}
            end
            local found = false
            for _, subsec in ipairs(section.subsections) do
                if subsec.id == categoryId then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(section.subsections, { id = categoryId, text = categoryName })
            end
            break
        end
    end
end

-- 2. prepareSections_on_end: 카테고리 내부 액션 3개 삽입
local function on_prepare_sections_end(configSections)
    local realMenu = Helper.getMenu("InteractMenu")
    if not realMenu then return end

    local playerShips = realMenu.selectedplayerships
    if not playerShips or #playerShips == 0 then
        return
    end

    -- 1. 함장 일괄 할당 해제 (Batch Unassign)
    local unassignText = ReadText(98765, 2)
    if (not unassignText) or (unassignText == "") or (string.find(unassignText, "ReadText")) then
        unassignText = "함장 일괄 할당 해제"
    end
    local unassignEntry = {
        text = unassignText,
        script = function()
            for _, ship in ipairs(playerShips) do
                AddUITriggeredEvent("InteractMenu", "unassign_pilot", ConvertStringTo64Bit(tostring(ship)))
            end
            realMenu.onCloseElement("close")
        end,
        active = true,
    }

    -- 2. 함장 일괄 배정 (Batch Assign)
    local assignText = ReadText(98765, 3)
    if (not assignText) or (assignText == "") or (string.find(assignText, "ReadText")) then
        assignText = "함장 일괄 배정"
    end
    
    -- 클래스(크기) 우선순위 정의 (XL > L > M > S)
    local classPriority = {
        ship_xl = 4,
        ship_l = 3,
        ship_m = 2,
        ship_s = 1
    }

    local assignEntry = {
        text = assignText,
        script = function()
            local sortedShips = {}
            for _, ship in ipairs(playerShips) do
                table.insert(sortedShips, ship)
            end

            -- 기본 정렬 우선순위 고정 (전투=4, 무역=3, 채집=2, 건설=1)
            local purposePriority = {
                fight = 4,
                trade = 3,
                mine = 2,
                build = 1
            }

            table.sort(sortedShips, function(a, b)
                local classA = GetComponentData(a, "class") or "ship_s"
                local classB = GetComponentData(b, "class") or "ship_s"
                local pA = classPriority[classA] or 0
                local pB = classPriority[classB] or 0
                
                if pA ~= pB then
                    return pA > pB -- XL > L > M > S 순 정렬
                end

                local purpA = GetComponentData(a, "primarypurpose") or "trade"
                local purpB = GetComponentData(b, "primarypurpose") or "trade"
                local purpPriA = purposePriority[purpA] or 0
                local purpPriB = purposePriority[purpB] or 0

                if purpPriA ~= purpPriB then
                    return purpPriA > purpPriB -- 전투, 무역, 채집, 건설 순
                end

                local hullA = GetComponentData(a, "maxhull") or 0
                local shieldA = GetComponentData(a, "maxshield") or 0
                local totalA = hullA + shieldA

                local hullB = GetComponentData(b, "maxhull") or 0
                local shieldB = GetComponentData(b, "maxshield") or 0
                local totalB = hullB + shieldB

                return totalA > totalB -- 선체+쉴드량 내구도 순 정렬
            end)

            -- 정렬된 순서대로 배정 이벤트 전송
            for _, ship in ipairs(sortedShips) do
                AddUITriggeredEvent("InteractMenu", "assign_pilot", ConvertStringTo64Bit(tostring(ship)))
            end
            realMenu.onCloseElement("close")
        end,
        active = true,
    }

    -- 3. 함장 일괄 해고 (Batch Fire)
    local fireText = ReadText(98765, 4)
    if (not fireText) or (fireText == "") or (string.find(fireText, "ReadText")) then
        fireText = "함장 일괄 해고"
    end
    local fireEntry = {
        text = fireText,
        script = function()
            for _, ship in ipairs(playerShips) do
                AddUITriggeredEvent("InteractMenu", "fire_pilot", ConvertStringTo64Bit(tostring(ship)))
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
        end)
    end
end

local function init()
    DebugError("[ACM Debug] interactmenu.lua init called!")
    
    if UIExtensions and UIExtensions.register then
        UIExtensions.register("interactmenu", "prepareSections_on_start", on_prepare_sections_start)
        UIExtensions.register("interactmenu", "prepareSections_on_end", on_prepare_sections_end)
        DebugError("[ACM Debug] Registered interactmenu hooks successfully via UIExtensions.register!")
    else
        DebugError("[ACM Debug] UIExtensions is nil during init. Trying Helper fallback...")
        local m = Helper.getMenu("InteractMenu")
        if m then
            m.registerCallback("prepareSections_on_start", on_prepare_sections_start, "advanced_captain_manager_start")
            m.registerCallback("prepareSections_on_end", on_prepare_sections_end, "advanced_captain_manager_end")
            DebugError("[ACM Debug] Registered interactmenu hooks successfully via Helper.getMenu fallback!")
        else
            DebugError("[ACM Debug] All registration methods failed.")
        end
    end
end

init()
