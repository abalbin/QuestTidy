local _, namespace = ...
local reviewFrame
local bagHighlight
local menuRegistered = false
local popupName = "QUESTTIDY_DELETE_QUEST_ITEM"
local fallbackIcon = "Interface\\Icons\\INV_Misc_QuestionMark"
local listWidth, rowHeight = 584, 62
local zoneFilters = {
    { key = "all", label = "All items" },
    { key = "current", label = "Current zone", empty = "No quest items with a known destination in this zone." },
    { key = "other", label = "Other zones", empty = "No quest items with known destinations in other zones." },
}
-- Forever quest 1459: the ID match also works when the quest's zone is collapsed.
local verifiedObjectives = { [1459] = { 6248, 6249 } }

local statuses = {
    active = { label = "Active quest", order = 1, mayDelete = false },
    starts_quest = { label = "Quest starter", order = 2, mayDelete = false },
    unknown = { label = "Use unknown", order = 3, mayDelete = true },
}

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffQuestTidy:|r " .. message)
end

local function IsPositiveInteger(value)
    return type(value) == "number" and value > 0 and value < math.huge and value % 1 == 0
end

local function LastBag()
    return Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
end

local function IsCarried(bag, slot)
    return type(bag) == "number" and bag % 1 == 0 and bag >= 0 and bag <= LastBag()
        and IsPositiveInteger(slot)
end

local function CopyRow(row)
    local copy = {}
    for key, value in pairs(row) do
        copy[key] = value
    end
    return copy
end

local function ItemName(link)
    return type(link) == "string" and link:match("|h%[(.-)%]|h") or nil
end

local function ObjectiveItemName(text, finished)
    if type(text) ~= "string" then
        return nil
    end
    text = text:gsub(" ", " ")
    if finished and text:match("%(([^()]*)%)%s*$") == (COMPLETE or "Complete") then
        text = text:gsub("%s+%([^()]*%)%s*$", "")
    end
    local name = text:gsub("^%s*%d+%s*/%s*%d+%s+", "")
        :gsub("[%s:]+%d+%s*/%s*%d+%s*$", ""):match("^%s*(.-)%s*$")
    return name ~= "" and not name:find("%d+%s*/%s*%d+") and name or nil
end

local function AddObjectiveMatch(byItem, key, quest, preferred)
    local match = byItem[key]
    if not match then
        match = { primary = quest, questIDs = {} }
        byItem[key] = match
    elseif preferred then
        match.primary = quest
    end
    match.questIDs[quest.id] = true
end

local function ReadActiveObjectives()
    local index = { byID = {}, byName = {}, complete = false }
    if not C_QuestLog or not C_QuestLog.GetInfo or not C_QuestLog.GetNumQuestLogEntries
        or not C_QuestLog.GetQuestObjectives or not C_QuestLog.IsOnQuest then
        return index
    end
    local seen, visible = {}, 0
    local complete = true
    local function addQuest(questID, title)
        if not IsPositiveInteger(questID) or seen[questID] or not C_QuestLog.IsOnQuest(questID) then
            return false
        end
        seen[questID] = true
        local quest = { id = questID, title = title or (C_QuestLog.GetTitleForQuestID
            and C_QuestLog.GetTitleForQuestID(questID)) }
        for _, itemID in ipairs(verifiedObjectives[questID] or {}) do
            AddObjectiveMatch(index.byID, itemID, quest, true)
        end
        local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
        local count = C_QuestLog.GetNumQuestObjectives and C_QuestLog.GetNumQuestObjectives(questID)
        if not ok or type(objectives) ~= "table" then
            complete = complete and ok and count == 0
            return true
        end
        if type(count) == "number" and #objectives < count then
            complete = false
        end
        for _, objective in ipairs(objectives) do
            if objective.type == "item" then
                local text = objective.text
                local itemID = type(text) == "string" and tonumber(text:match("|Hitem:(%d+)"))
                if itemID then
                    AddObjectiveMatch(index.byID, itemID, quest)
                else
                    local name = ObjectiveItemName(text, objective.finished)
                    if name then
                        AddObjectiveMatch(index.byName, name, quest)
                    else
                        complete = false
                    end
                end
            end
        end
        return true
    end
    local entries, total = C_QuestLog.GetNumQuestLogEntries()
    for entry = 1, entries do
        local info = C_QuestLog.GetInfo(entry)
        if info and not info.isHeader and addQuest(info.questID, info.title) then
            visible = visible + 1
        end
    end
    if C_QuestLog.GetNumQuestWatches and C_QuestLog.GetQuestIDForQuestWatchIndex then
        for watch = 1, C_QuestLog.GetNumQuestWatches() do
            addQuest(C_QuestLog.GetQuestIDForQuestWatchIndex(watch))
        end
    end
    for questID in pairs(verifiedObjectives) do
        addQuest(questID)
    end
    index.complete = complete and type(total) == "number" and visible == total
    return index
end

local function ReadItemGUID(bag, slot)
    if not C_Item or not C_Item.GetItemGUID or not ItemLocation or not ItemLocation.CreateFromBagAndSlot then
        return nil
    end
    local locationOK, location = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
    if locationOK and location then
        local ok, value = pcall(C_Item.GetItemGUID, location)
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end
end

local function ReadItem(bag, slot, objectives)
    if not IsCarried(bag, slot) or not C_Container or not C_Container.GetContainerItemInfo then
        return nil
    end
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if not ok or type(info) ~= "table" or not IsPositiveInteger(info.itemID) then
        return nil
    end
    local questOK, questInfo = false, nil
    if C_Container.GetContainerItemQuestInfo then
        questOK, questInfo = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
    end
    questOK = questOK and type(questInfo) == "table"
    local questID = questOK and questInfo.questID
    if not IsPositiveInteger(questID) then
        questID = nil
    end
    local classID, itemIcon
    if C_Item and C_Item.GetItemInfoInstant then
        local itemOK, _, _, _, _, icon, itemClass = pcall(C_Item.GetItemInfoInstant, info.itemID)
        if itemOK then
            classID, itemIcon = itemClass, icon
        end
    end
    local name = ItemName(info.hyperlink)
    local idMatch = objectives.byID[info.itemID]
    local nameMatch = objectives.byName[name and name:gsub(" ", " ")]
    local match = idMatch or nameMatch
    local quest = match and match.primary
    local isQuestItem = classID == 12 or (questOK and questInfo.isQuestItem == true) or quest ~= nil
    local active = (questOK and questInfo.isActive == true) or quest ~= nil
    if not isQuestItem and not questID and not active then
        return nil
    end

    local complete = questOK and type(questInfo.isQuestItem) == "boolean"
        and type(questInfo.isActive) == "boolean" and type(classID) == "number"
    if questID and C_QuestLog and C_QuestLog.IsOnQuest then
        local onQuestOK, onQuest = pcall(C_QuestLog.IsOnQuest, questID)
        if onQuestOK then
            active = active or onQuest == true
        else
            complete = false
        end
    elseif questID then
        complete = false
    end
    local relatedQuestIDs = questID and { [questID] = true } or {}
    if idMatch then
        for itemQuestID in pairs(idMatch.questIDs) do
            relatedQuestIDs[itemQuestID] = true
        end
    end
    if nameMatch then
        for itemQuestID in pairs(nameMatch.questIDs) do
            relatedQuestIDs[itemQuestID] = true
        end
    end
    if quest then
        questID = quest.id
    end
    local status = active and "active" or (questID and "starts_quest" or "unknown")
    local questTitle = quest and quest.title
    if not questTitle and active and questID and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        questTitle = C_QuestLog.GetTitleForQuestID(questID)
    end
    local completed
    if questID and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local completedOK, value = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
        if completedOK then
            completed = value
        end
    end
    local icon = IsPositiveInteger(info.iconFileID) and info.iconFileID
        or (IsPositiveInteger(itemIcon) and itemIcon or fallbackIcon)
    return {
        bag = bag, slot = slot, itemID = info.itemID, hyperlink = info.hyperlink,
        name = name or ("Item " .. info.itemID), icon = icon, isQuestItem = isQuestItem,
        count = info.stackCount, guid = ReadItemGUID(bag, slot), status = status, questID = questID,
        relatedQuestIDs = relatedQuestIDs,
        questTitle = questTitle, objectivesChecked = objectives.complete,
        completed = completed, locked = info.isLocked, metadataComplete = complete,
    }
end

function namespace.ScanQuestItems()
    local rows = {}
    if not C_Container or not C_Container.GetContainerNumSlots or not C_Container.GetContainerItemInfo then
        return rows, "Bag information is unavailable. Use ordinary bag management."
    end
    local objectives = ReadActiveObjectives()
    for bag = 0, LastBag() do
        local ok, count = pcall(C_Container.GetContainerNumSlots, bag)
        if ok and type(count) == "number" then
            for slot = 1, count do
                local row = ReadItem(bag, slot, objectives)
                if row then
                    rows[#rows + 1] = row
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.isQuestItem ~= b.isQuestItem then
            return a.isQuestItem
        end
        local aOrder, bOrder = statuses[a.status].order, statuses[b.status].order
        if aOrder ~= bOrder then
            return aOrder < bOrder
        end
        if a.bag ~= b.bag then
            return a.bag < b.bag
        end
        return a.slot < b.slot
    end)
    return rows
end

local function ReadZone(mapID, zoneType)
    local seen = {}
    while IsPositiveInteger(mapID) and not seen[mapID] do
        seen[mapID] = true
        local ok, map = pcall(C_Map.GetMapInfo, mapID)
        if not ok or type(map) ~= "table" then
            return nil
        end
        if map.mapType == zoneType then
            local name = type(map.name) == "string" and map.name ~= "" and map.name or nil
            return { id = mapID, name = name }
        end
        mapID = map.parentMapID
    end
end

local function ReadZoneContext()
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone
    if not zoneType or not C_Map or not C_Map.GetMapInfo or not C_Map.GetBestMapForUnit then
        return nil, function() end
    end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    local current = ok and ReadZone(mapID, zoneType) or nil
    local destinations = {}
    local function GetDestination(questID)
        if destinations[questID] == nil and GetQuestUiMapID then
            -- The native Destination Map omits travel waypoints.
            local success, questMapID = pcall(GetQuestUiMapID, questID, true)
            destinations[questID] = (success and ReadZone(questMapID, zoneType)) or false
        end
        return destinations[questID]
    end
    return current, GetDestination
end

local function ReadItemZone(row, currentZone, GetDestination)
    local zoneIDs, names = {}, {}
    local inCurrentZone, unknown = false, false
    for questID in pairs(row.relatedQuestIDs) do
        local zone = GetDestination(questID)
        if not zone then
            unknown = true
        elseif not zoneIDs[zone.id] then
            zoneIDs[zone.id] = true
            if zone.name then
                names[#names + 1] = zone.name
            end
            inCurrentZone = inCurrentZone or (currentZone and currentZone.id == zone.id)
        end
    end
    local scope = "unknown"
    if inCurrentZone then
        scope = "current"
    elseif currentZone and not unknown and next(zoneIDs) then
        scope = "other"
    end
    if #names == 0 then
        return scope
    end
    table.sort(names)
    return scope, table.concat(names, ", ") .. (unknown and " (some destinations unknown)" or "")
end

local function CanDelete(row)
    if InCombatLockdown() then
        return false, "Wait until combat ends to review deletion.", "In combat"
    end
    if not row or not statuses[row.status] or not statuses[row.status].mayDelete then
        return false, "This item is associated with an active quest or quest starter and is protected."
    end
    if not row.objectivesChecked then
        return false, "QuestTidy couldn't check every active quest. Expand your quest log and refresh the review.", "Quest check incomplete"
    end
    if not row.metadataComplete or type(row.hyperlink) ~= "string" or row.hyperlink == ""
        or not IsPositiveInteger(row.count) or row.locked == nil then
        return false, "Item information is incomplete. Wait for it to load or use ordinary bag management.", "Item data incomplete"
    end
    if row.locked then
        return false, "This item is locked. Wait for it to unlock.", "Item locked"
    end
    if not row.guid then
        return false, "This item has no stable identity. Use ordinary bag management.", "Item identity unavailable"
    end
    if not C_Item or not C_Item.DeleteItem or not GetCursorInfo then
        return false, "Item deletion is unavailable. Use ordinary bag management.", "Deletion unavailable"
    end
    if GetCursorInfo() ~= nil then
        return false, "Clear your cursor before requesting deletion.", "Clear your cursor"
    end
    return true
end

local function Revalidate(snapshot)
    if not snapshot or not IsCarried(snapshot.bag, snapshot.slot) then
        return nil, "The item location is no longer valid. Refresh the review."
    end
    local current = ReadItem(snapshot.bag, snapshot.slot, ReadActiveObjectives())
    if not current or current.itemID ~= snapshot.itemID or current.guid ~= snapshot.guid
        or current.hyperlink ~= snapshot.hyperlink or current.count ~= snapshot.count then
        return nil, "The item or stack changed. Refresh the review and select it again."
    end
    local allowed, reason = CanDelete(current)
    if not allowed then
        return nil, reason
    end
    return current
end

StaticPopupDialogs[popupName] = {
    text = "Delete this entire stack?\n\n%s\n\nUsage is unknown. This item may be needed for an active, future, or repeatable quest. Deletion may be irreversible.",
    button1 = "Delete stack",
    button2 = CANCEL or "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    exclusive = true,
    preferredIndex = 3,
    OnAccept = function(_, snapshot)
        local current, reason = Revalidate(snapshot)
        if not current then
            Print(reason)
            return
        end
        local ok, result = pcall(C_Item.DeleteItem, current.guid)
        if not ok or result == false then
            Print("The game blocked the deletion request. Use ordinary bag management.")
        else
            Print("Deletion requested. Check your bag; game restrictions may block it. Use ordinary bag management if the item remains.")
        end
    end,
}

function namespace.RequestDeleteQuestItem(row)
    if type(row) ~= "table" then
        Print("Select an item stack from the bag review.")
        return false
    end
    local snapshot = CopyRow(row)
    local current, reason = Revalidate(snapshot)
    if not current then
        Print(reason)
        return false
    end
    if not StaticPopup_Show then
        Print("Confirmation is unavailable. Use ordinary bag management.")
        return false
    end
    if StaticPopup_Visible and StaticPopup_Visible(popupName) then
        Print("Finish or cancel the current item confirmation first.")
        return false
    end
    local label = snapshot.hyperlink .. " x" .. snapshot.count
        .. " (bag " .. snapshot.bag .. ", slot " .. snapshot.slot .. ")"
    local popup = StaticPopup_Show(popupName, label, nil, snapshot)
    if not popup then
        Print("Confirmation could not open. Try again after closing other dialogs.")
        return false
    end
    return true
end

local function FindStack(row)
    if ReadItemGUID(row.bag, row.slot) == row.guid then
        return row.bag, row.slot
    end
    for bag = 0, LastBag() do
        local ok, count = pcall(C_Container.GetContainerNumSlots, bag)
        if ok and type(count) == "number" then
            for slot = 1, count do
                if ReadItemGUID(bag, slot) == row.guid then
                    return bag, slot
                end
            end
        end
    end
end

local function IsSlotButton(button, stack)
    return stack and button and button:IsVisible() and button:GetBagID() == stack.bag
        and button:GetID() == stack.slot
end

local function CreateBagHighlight()
    local frame = CreateFrame("Frame", "QuestTidyBagItemHighlight", UIParent)
    frame:Hide()
    frame:EnableMouse(false)
    local edges = {
        { "TOPLEFT", "TOPRIGHT", "SetHeight" },
        { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight" },
        { "TOPLEFT", "BOTTOMLEFT", "SetWidth" },
        { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth" },
    }
    for _, edge in ipairs(edges) do
        local texture = frame:CreateTexture(nil, "OVERLAY")
        texture:SetPoint(edge[1])
        texture:SetPoint(edge[2])
        texture[edge[3]](texture, 3)
        texture:SetColorTexture(1, 0.79, 0.12, 1)
    end
    frame:SetScript("OnHide", function(self)
        self.stack = nil
        self:Hide()
    end)
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.remaining = self.remaining - elapsed
        local stack = self.stack
        if self.remaining <= 0 or not IsSlotButton(self:GetParent(), stack) then
            self:Hide()
        elseif self.remaining <= self.nextIdentityCheck then
            self.nextIdentityCheck = self.remaining - 0.1
            if ReadItemGUID(stack.bag, stack.slot) ~= stack.guid then
                self:Hide()
            end
        end
    end)
    return frame
end

local function FindInBags(row)
    if bagHighlight then
        bagHighlight:Hide()
    end
    if InCombatLockdown() then
        Print("Wait until combat ends to find an item in your bags.")
        return
    end
    if not row or not row.guid then
        Print("This stack could not be identified. Refresh the review and try again.")
        return
    end
    if not OpenBag or not ContainerFrameUtil_GetItemButtonAndContainer
        or not C_Container or not C_Container.GetContainerNumSlots then
        Print("Find in bags is unavailable in this client.")
        return
    end
    local bag, slot = FindStack(row)
    if not bag then
        Print("The selected stack is no longer in your carried bags. Refresh the review.")
        return
    end
    OpenBag(bag)
    local button = ContainerFrameUtil_GetItemButtonAndContainer(bag, slot)
    local stack = { bag = bag, slot = slot, guid = row.guid }
    if not IsSlotButton(button, stack) or ReadItemGUID(bag, slot) ~= stack.guid then
        Print("The selected stack could not be highlighted. Check your bags and try again.")
        return
    end
    if not bagHighlight then
        bagHighlight = CreateBagHighlight()
    end
    reviewFrame:Hide()
    bagHighlight:SetParent(button)
    bagHighlight:ClearAllPoints()
    bagHighlight:SetAllPoints(button)
    bagHighlight:SetFrameStrata(button:GetFrameStrata())
    bagHighlight:SetFrameLevel(button:GetFrameLevel() + 1)
    bagHighlight.stack, bagHighlight.remaining, bagHighlight.nextIdentityCheck = stack, 3, 3
    bagHighlight:Show()
end

local function HideItemTooltip(icon)
    if GameTooltip:GetOwner() == icon then
        GameTooltip:Hide()
    end
end

local function CreateReviewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(listWidth, rowHeight)
    local rule = row:CreateTexture(nil, "BACKGROUND")
    rule:SetPoint("BOTTOMLEFT", 8, 0)
    rule:SetPoint("BOTTOMRIGHT", -8, 0)
    rule:SetHeight(1)
    rule:SetColorTexture(0.75, 0.65, 0.45, 0.17)

    local icon = CreateFrame("Frame", nil, row)
    icon:SetSize(36, 36)
    icon:SetPoint("LEFT", 8, 0)
    icon:EnableMouse(true)
    local border = icon:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.48, 0.39, 0.26, 1)
    icon.image = icon:CreateTexture(nil, "ARTWORK")
    icon.image:SetPoint("TOPLEFT", 1, -1)
    icon.image:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetScript("OnEnter", function(self)
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    icon:SetScript("OnLeave", HideItemTooltip)
    icon:SetScript("OnHide", HideItemTooltip)
    row.icon = icon

    row.title = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", 56, -9)
    row.title:SetPoint("TOPRIGHT", -110, -9)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)

    row.details = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.details:SetPoint("TOPLEFT", 56, -27)
    row.details:SetPoint("TOPRIGHT", -110, -27)
    row.details:SetJustifyH("LEFT")
    row.details:SetWordWrap(false)
    row.details:SetTextColor(0.78, 0.73, 0.64)

    row.destination = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.destination:SetPoint("TOPLEFT", 56, -43)
    row.destination:SetPoint("TOPRIGHT", -110, -43)
    row.destination:SetJustifyH("LEFT")
    row.destination:SetWordWrap(false)
    row.destination:SetTextColor(0.78, 0.73, 0.64)

    row.find = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.find:SetSize(96, 22)
    row.find:SetPoint("TOPRIGHT", -8, -7)
    row.find:SetText("Find in bags")
    row.find:SetScript("OnClick", function()
        FindInBags(row.snapshot)
    end)

    row.protected = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.protected:SetPoint("RIGHT", -8, -13)
    row.protected:SetWidth(96)
    row.protected:SetText("Protected")

    row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.button:SetSize(96, 22)
    row.button:SetPoint("BOTTOMRIGHT", -8, 7)
    row.button:SetText("Delete...")
    row.button:SetScript("OnClick", function()
        namespace.RequestDeleteQuestItem(row.snapshot)
    end)
    return row
end

local function RefreshReview()
    if not reviewFrame or not reviewFrame:IsShown() then
        return
    end
    local items, reason = namespace.ScanQuestItems()
    local currentZone, GetDestination = ReadZoneContext()
    local filter = reviewFrame.zoneFilter
    local zoneName = currentZone and currentZone.name
    reviewFrame.playerZone:SetText(zoneName and ("Current zone: " .. zoneName) or "Current zone unavailable")
    local rows = {}
    for _, snapshot in ipairs(items) do
        local scope, destinations = ReadItemZone(snapshot, currentZone, GetDestination)
        if filter.key == "all" or filter.key == scope then
            snapshot.destinations = destinations
            rows[#rows + 1] = snapshot
        end
    end
    for _, heading in ipairs(reviewFrame.sections) do
        heading:Hide()
    end
    local offset, lastSection = 0, nil
    for index, snapshot in ipairs(rows) do
        local section = snapshot.isQuestItem and 1 or 2
        if section ~= lastSection then
            if lastSection then
                offset = offset + 12
            end
            local heading = reviewFrame.sections[section]
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", 8, -offset)
            heading:Show()
            offset = offset + 22
            lastSection = section
        end

        local row = reviewFrame.rows[index]
        if not row then
            row = CreateReviewRow(reviewFrame.contents)
            reviewFrame.rows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -offset)
        offset = offset + rowHeight
        if row.icon.link ~= snapshot.hyperlink then
            HideItemTooltip(row.icon)
            row.icon.link = snapshot.hyperlink
        end
        row.icon.image:SetTexture(snapshot.icon)
        row.title:SetText(snapshot.name)
        local status = statuses[snapshot.status]
        local bag = snapshot.bag == 0 and "Backpack" or ("Bag " .. snapshot.bag)
        local allowed, _, unavailable = CanDelete(snapshot)
        local label = snapshot.questTitle and ("Active: " .. snapshot.questTitle) or status.label
        local details = (status.mayDelete and unavailable or label)
            .. "  •  Qty " .. tostring(snapshot.count or "?")
            .. "  •  " .. bag .. ", slot " .. snapshot.slot
        row.details:SetText(details)
        row.destination:SetText(snapshot.destinations and ("Quest destination: " .. snapshot.destinations)
            or "Quest destination unknown")
        row.protected:SetShown(not status.mayDelete)
        row.button:SetShown(status.mayDelete)
        row.button:SetEnabled(allowed)
        row.snapshot = snapshot
        row:Show()
    end
    for index = #rows + 1, #reviewFrame.rows do
        local row = reviewFrame.rows[index]
        HideItemTooltip(row.icon)
        row.icon.link = nil
        row.snapshot = nil
        row:Hide()
    end
    reviewFrame.contents:SetHeight(math.max(1, offset + 4))
    local empty = reason
    if not empty and #rows == 0 then
        if #items == 0 then
            empty = "No quest-related items in your carried bags."
        elseif not currentZone then
            empty = "Your current zone could not be determined."
        else
            empty = filter.empty
        end
    end
    reviewFrame.empty:SetText(empty or "")
end

local function CreateReview()
    local frame = CreateFrame("Frame", "QuestTidyBagReview", UIParent, "BasicFrameTemplateWithInset")
    frame:Hide()
    frame:SetSize(650, 500)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.TitleText:SetText("QuestTidy: Quest items")
    UISpecialFrames[#UISpecialFrames + 1] = "QuestTidyBagReview"
    local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    heading:SetPoint("TOPLEFT", 16, -66)
    heading:SetWidth(614)
    heading:SetJustifyH("LEFT")
    heading:SetText("Items with unknown destinations appear under All items. Review unknown quest use before deleting.")
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -88)
    scroll:SetPoint("BOTTOMRIGHT", -36, 45)
    frame.zoneFilter = zoneFilters[1]
    local selected
    for index, filter in ipairs(zoneFilters) do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(105, 22)
        button:SetPoint("TOPLEFT", 16 + (index - 1) * 109, -34)
        button:SetText(filter.label)
        if frame.zoneFilter == filter then
            button:LockHighlight()
            selected = button
        end
        button:SetScript("OnClick", function(self)
            if frame.zoneFilter ~= filter then
                selected:UnlockHighlight()
                self:LockHighlight()
                selected, frame.zoneFilter = self, filter
                scroll:SetVerticalScroll(0)
                RefreshReview()
            end
        end)
    end
    frame.playerZone = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.playerZone:SetPoint("TOPLEFT", 346, -40)
    frame.playerZone:SetPoint("TOPRIGHT", -16, -40)
    frame.playerZone:SetJustifyH("RIGHT")
    frame.playerZone:SetWordWrap(false)
    local contents = CreateFrame("Frame", nil, scroll)
    contents:SetSize(listWidth, 1)
    scroll:SetScrollChild(contents)
    frame.contents, frame.rows, frame.sections = contents, {}, {}
    for index, label in ipairs({ "Quest items", "Other quest-related items" }) do
        local section = contents:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        section:SetText(label)
        section:Hide()
        frame.sections[index] = section
    end
    frame.empty = contents:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.empty:SetPoint("TOPLEFT")
    frame.empty:SetWidth(listWidth)
    frame.empty:SetJustifyH("LEFT")
    local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refresh:SetSize(100, 22)
    refresh:SetPoint("BOTTOMRIGHT", -18, 14)
    refresh:SetText("Refresh")
    refresh:SetScript("OnClick", RefreshReview)
    frame:SetScript("OnShow", RefreshReview)
    return frame
end

function namespace.ReviewQuestItems()
    if InCombatLockdown() then
        Print("Wait until combat ends to open quest-item review.")
        return false
    end
    if not reviewFrame then
        reviewFrame = CreateReview()
    end
    if reviewFrame:IsShown() then
        RefreshReview()
    else
        reviewFrame:Show()
    end
    return true
end

local function AddReviewButton(_, rootDescription)
    rootDescription:CreateDivider()
    rootDescription:CreateButton("QuestTidy: Review quest items", function() namespace.ReviewQuestItems() end)
end

local function RegisterMenus()
    if menuRegistered or not Menu or not Menu.ModifyMenu then
        return
    end
    Menu.ModifyMenu("MENU_CONTAINER_FRAME", function(owner, rootDescription)
        local parent = owner and owner.GetParent and owner:GetParent()
        local bag = parent and parent.GetBagID and parent:GetBagID()
        if IsCarried(bag, 1) then
            AddReviewButton(owner, rootDescription)
        end
    end)
    Menu.ModifyMenu("MENU_CONTAINER_FRAME_COMBINED", AddReviewButton)
    menuRegistered = true
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_POI_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED")
events:RegisterEvent("ZONE_CHANGED_INDOORS")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
    RegisterMenus()
    RefreshReview()
end)
RegisterMenus()
