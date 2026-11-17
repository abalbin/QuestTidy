local _, namespace = ...
local reviewFrame
local menuRegistered = false
local popupName = "QUESTTIDY_DELETE_QUEST_ITEM"

local statuses = {
    active = { label = "Active quest item. Protected.", mayDelete = false },
    starts_quest = { label = "Associated quest starter. Protected, including repeatable or future quests.", mayDelete = false },
    unknown = { label = "Usage unknown. May be needed for an active, future, or repeatable quest.", mayDelete = true },
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

local function ReadItem(bag, slot)
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
    local classID
    if C_Item and C_Item.GetItemInfoInstant then
        local itemOK, _, _, _, _, _, itemClass = pcall(C_Item.GetItemInfoInstant, info.itemID)
        if itemOK then
            classID = itemClass
        end
    end
    if not (questOK and questInfo.isQuestItem) and not questID and classID ~= 12 then
        return nil
    end

    local complete = questOK and type(questInfo.isQuestItem) == "boolean"
        and type(questInfo.isActive) == "boolean" and type(classID) == "number"
    local active = questOK and questInfo.isActive == true
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
    local status = active and "active" or (questID and "starts_quest" or "unknown")
    local completed
    if questID and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local completedOK, value = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
        if completedOK then
            completed = value
        end
    end
    local guid
    if C_Item and C_Item.GetItemGUID and ItemLocation and ItemLocation.CreateFromBagAndSlot then
        local locationOK, location = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
        if locationOK and location then
            local guidOK, value = pcall(C_Item.GetItemGUID, location)
            if guidOK and type(value) == "string" and value ~= "" then
                guid = value
            end
        end
    end
    return {
        bag = bag, slot = slot, itemID = info.itemID, hyperlink = info.hyperlink,
        count = info.stackCount, guid = guid, status = status, questID = questID,
        completed = completed, locked = info.isLocked, metadataComplete = complete,
    }
end

function namespace.ScanQuestItems()
    local rows = {}
    if not C_Container or not C_Container.GetContainerNumSlots or not C_Container.GetContainerItemInfo then
        return rows, "Bag information is unavailable. Use ordinary bag management."
    end
    for bag = 0, LastBag() do
        local ok, count = pcall(C_Container.GetContainerNumSlots, bag)
        if ok and type(count) == "number" then
            for slot = 1, count do
                local row = ReadItem(bag, slot)
                if row then
                    rows[#rows + 1] = row
                end
            end
        end
    end
    return rows
end

local function CanDelete(row)
    if InCombatLockdown() then
        return false, "Wait until combat ends to review deletion."
    end
    if not row or not statuses[row.status] or not statuses[row.status].mayDelete then
        return false, "This item is associated with an active quest or quest starter and is protected."
    end
    if not row.metadataComplete or type(row.hyperlink) ~= "string" or row.hyperlink == ""
        or not IsPositiveInteger(row.count) or row.locked == nil then
        return false, "Item information is incomplete. Wait for it to load or use ordinary bag management."
    end
    if not row.guid or row.locked then
        return false, "This item is locked or has no stable identity. Use ordinary bag management."
    end
    if not C_Item or not C_Item.DeleteItem or not GetCursorInfo then
        return false, "Item deletion is unavailable. Use ordinary bag management."
    end
    if GetCursorInfo() ~= nil then
        return false, "Clear your cursor before requesting deletion."
    end
    return true
end

local function Revalidate(snapshot)
    if not snapshot or not IsCarried(snapshot.bag, snapshot.slot) then
        return nil, "The item location is no longer valid. Refresh the review."
    end
    local current = ReadItem(snapshot.bag, snapshot.slot)
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

local function RefreshReview()
    if not reviewFrame or not reviewFrame:IsShown() then
        return
    end
    local rows, reason = namespace.ScanQuestItems()
    for _, rowFrame in ipairs(reviewFrame.rows) do
        rowFrame:Hide()
    end
    for index, row in ipairs(rows) do
        local rowFrame = reviewFrame.rows[index]
        if not rowFrame then
            rowFrame = CreateFrame("Frame", nil, reviewFrame.contents)
            rowFrame:SetSize(584, 76)
            rowFrame:SetPoint("TOPLEFT", 0, -(index - 1) * 80)
            rowFrame.text = rowFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            rowFrame.text:SetPoint("TOPLEFT")
            rowFrame.text:SetWidth(474)
            rowFrame.text:SetJustifyH("LEFT")
            rowFrame.text:SetJustifyV("TOP")
            rowFrame.button = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
            rowFrame.button:SetSize(90, 22)
            rowFrame.button:SetPoint("TOPRIGHT", 0, -3)
            rowFrame.button:SetText("Delete...")
            reviewFrame.rows[index] = rowFrame
        end
        local snapshot = CopyRow(row)
        local allowed, unavailable = CanDelete(snapshot)
        local description = (snapshot.hyperlink or ("Item " .. snapshot.itemID))
            .. " x" .. tostring(snapshot.count or "?") .. "  |  Bag " .. snapshot.bag .. ", slot " .. snapshot.slot
            .. "\n" .. statuses[snapshot.status].label
        if snapshot.status == "unknown" and not allowed then
            description = description .. "\n" .. unavailable
        end
        rowFrame.text:SetText(description)
        rowFrame.button:SetEnabled(allowed)
        rowFrame.button:SetScript("OnClick", function() namespace.RequestDeleteQuestItem(snapshot) end)
        rowFrame:Show()
    end
    reviewFrame.contents:SetHeight(math.max(1, #rows * 80))
    reviewFrame.empty:SetText(reason or (#rows == 0 and "No quest-related items found in carried bags." or ""))
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
    heading:SetPoint("TOPLEFT", 16, -36)
    heading:SetWidth(614)
    heading:SetJustifyH("LEFT")
    heading:SetText("Carried bags only. Active quest items and quest starters are protected. Unknown usage does not mean useless. Review carefully before deleting a single stack; some quest items cannot be identified by the client.")
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -100)
    scroll:SetPoint("BOTTOMRIGHT", -36, 45)
    local contents = CreateFrame("Frame", nil, scroll)
    contents:SetSize(584, 1)
    scroll:SetScrollChild(contents)
    frame.contents, frame.rows = contents, {}
    frame.empty = contents:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.empty:SetPoint("TOPLEFT")
    frame.empty:SetWidth(584)
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
    reviewFrame:Show()
    RefreshReview()
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
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
    RegisterMenus()
    RefreshReview()
end)
RegisterMenus()
