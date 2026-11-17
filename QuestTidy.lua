local _, namespace = ...
local dialog, untrackButton, trackButton
local menuRegistered = false
local CanTrack

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffQuestTidy:|r " .. message)
end

local function IsQuestID(questID)
    return type(questID) == "number" and questID > 0
        and questID < math.huge and questID % 1 == 0
end

local function QuestIDText(questID)
    return string.format("%.0f", questID)
end

local function PlainText(text)
    return (tostring(text):gsub("|", "||"))
end

local function CanUntrack()
    if InCombatLockdown() then
        return false, "Wait until combat ends to clear quest tracking."
    end
    if not C_QuestLog or not C_QuestLog.GetNumQuestWatches
        or not C_QuestLog.GetQuestIDForQuestWatchIndex or not C_QuestLog.RemoveQuestWatch
        or not QuestUtil or not QuestUtil.CanRemoveQuestWatch then
        return false, "Quest tracking is not available yet."
    end
    if not QuestUtil.CanRemoveQuestWatch() then
        return false, "Quest untracking is restricted by the game for this character."
    end
    return true
end

local function UpdateButton()
    if untrackButton then
        local allowed = CanUntrack()
        untrackButton:SetEnabled(allowed and C_QuestLog.GetNumQuestWatches() > 0)
    end
    if trackButton then
        local allowed = CanTrack(false)
        trackButton:SetEnabled(allowed)
    end
end

function namespace.UntrackAll()
    local allowed, reason = CanUntrack()
    if not allowed then
        Print(reason)
        return 0, 0, reason
    end

    local watched, snapshot = {}, {}
    local removed, failed = 0, 0
    local focused = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
        and C_SuperTrack.GetSuperTrackedQuestID()
    for index = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
        if IsQuestID(questID) then
            if not snapshot[questID] then
                snapshot[questID] = true
                watched[#watched + 1] = questID
            end
        else
            failed = failed + 1
        end
    end

    local removedFocus = false
    for _, questID in ipairs(watched) do
        local ok, wasRemoved = pcall(C_QuestLog.RemoveQuestWatch, questID)
        if ok and wasRemoved then
            removed = removed + 1
            if questID == focused then
                removedFocus = true
            end
        else
            failed = failed + 1
        end
    end
    if removedFocus and C_SuperTrack.SetSuperTrackedQuestID
        and C_SuperTrack.GetSuperTrackedQuestID() == focused then
        C_SuperTrack.SetSuperTrackedQuestID(0)
    end
    UpdateButton()
    Print(string.format("Removed %d quest watch(es); %d failed. Automatic quest tracking may add quests again.", removed, failed))
    return removed, failed
end

CanTrack = function(readyOnly)
    if InCombatLockdown() then
        return false, "Wait until combat ends to change quest tracking."
    end
    if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries or not C_QuestLog.GetInfo
        or not C_QuestLog.GetNumQuestWatches or not C_QuestLog.GetQuestIDForQuestWatchIndex
        or not C_QuestLog.AddQuestWatch then
        return false, "Quest tracking is not available yet."
    end
    if readyOnly then
        if not C_QuestLog.ReadyForTurnIn then
            return false, "Ready-to-turn-in information is not available yet."
        end
        return CanUntrack()
    end
    return true
end

local function ReadLoggedQuests(readyOnly)
    local quests, desired, seen, collapsed = {}, {}, {}, {}
    local ok = pcall(function()
        local index = 1
        while index <= C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(index)
            if not info then
                error("Quest log changed during enumeration")
            end
            if info.isHeader and info.isCollapsed then
                collapsed[#collapsed + 1] = index
                ExpandQuestHeader(index)
                local expanded = C_QuestLog.GetInfo(index)
                if not expanded or expanded.isCollapsed then
                    error("Quest header could not expand")
                end
            elseif IsQuestID(info.questID) and not info.isHeader and not info.isTask
                and not info.isHidden and not info.isDisabledForSession
                and not (C_QuestLog.IsQuestDisabledForSession
                    and C_QuestLog.IsQuestDisabledForSession(info.questID))
                and not seen[info.questID] then
                local questID = info.questID
                seen[questID] = true
                if not readyOnly or C_QuestLog.ReadyForTurnIn(questID) == true then
                    quests[#quests + 1] = questID
                    desired[questID] = true
                end
            end
            index = index + 1
        end
    end)
    local restored = true
    for index = #collapsed, 1, -1 do
        local success = pcall(function()
            CollapseQuestHeader(collapsed[index])
            local header = C_QuestLog.GetInfo(collapsed[index])
            if not header or not header.isHeader or header.isCollapsed ~= true then
                error("Quest header could not restore")
            end
        end)
        restored = restored and success
    end
    if not ok or not restored then
        return nil, nil, "Could not read the complete quest log and restore its headers. No quest watches were changed."
    end
    return quests, desired
end

local function ChangeTracking(readyOnly)
    local allowed, reason = CanTrack(readyOnly)
    local result = { added = 0, removed = 0, already = 0, failed = 0, reason = reason }
    if not allowed then
        Print(reason)
        return result
    end
    local watchedOrder, watched = {}, {}
    for index = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
        if not IsQuestID(questID) then
            result.failed = result.failed + 1
        elseif not watched[questID] then
            watched[questID] = true
            watchedOrder[#watchedOrder + 1] = questID
        end
    end
    local quests, desired, readError = ReadLoggedQuests(readyOnly)
    if not quests then
        result.failed = result.failed + 1
        result.reason = readError
        Print(readError)
        return result
    end
    local focused = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
        and C_SuperTrack.GetSuperTrackedQuestID()
    local removedFocus = false
    if readyOnly then
        for _, questID in ipairs(watchedOrder) do
            if not desired[questID] then
                local ok, removed = pcall(C_QuestLog.RemoveQuestWatch, questID)
                if ok and removed == true then
                    result.removed = result.removed + 1
                    removedFocus = removedFocus or questID == focused
                else
                    result.failed = result.failed + 1
                end
            end
        end
    end
    for _, questID in ipairs(quests) do
        if watched[questID] then
            result.already = result.already + 1
        else
            local ok, added = pcall(C_QuestLog.AddQuestWatch, questID)
            if ok and added == true then
                result.added = result.added + 1
            else
                result.failed = result.failed + 1
            end
        end
    end
    if removedFocus and C_SuperTrack.SetSuperTrackedQuestID
        and C_SuperTrack.GetSuperTrackedQuestID() == focused then
        C_SuperTrack.SetSuperTrackedQuestID(0)
    end
    UpdateButton()
    Print(string.format("Added %d; removed %d; already tracked %d; failed %d. Watch limits or game restrictions can prevent changes. Automatic tracking may add quests again.",
        result.added, result.removed, result.already, result.failed))
    return result
end

function namespace.TrackAll()
    return ChangeTracking(false)
end

function namespace.TrackReady()
    return ChangeTracking(true)
end

local function SelectURL(editBox)
    editBox:SetFocus()
    editBox:HighlightText()
end

local function CreateDialog()
    local frame = CreateFrame("Frame", "QuestTidyDialog", UIParent, "BasicFrameTemplateWithInset")
    frame:Hide()
    frame:SetSize(540, 420)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.TitleText:SetText("Wowhead comments & tips")
    UISpecialFrames[#UISpecialFrames + 1] = "QuestTidyDialog"

    frame.QuestTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.QuestTitle:SetPoint("TOPLEFT", 16, -36)
    frame.QuestTitle:SetPoint("TOPRIGHT", -16, -36)
    frame.QuestTitle:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -90)
    scroll:SetPoint("BOTTOMRIGHT", -36, 85)
    local contents = CreateFrame("Frame", nil, scroll)
    contents:SetSize(480, 1)
    scroll:SetScrollChild(contents)
    local text = contents:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT")
    text:SetWidth(480)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    frame.Advice, frame.AdviceContents, frame.AdviceScroll = text, contents, scroll

    local copyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    copyLabel:SetPoint("BOTTOMLEFT", 18, 59)
    copyLabel:SetText("Latest comments in your browser. Copy with Ctrl+C / Cmd+C.")
    local url = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    url:SetPoint("BOTTOMLEFT", 22, 28)
    url:SetPoint("BOTTOMRIGHT", -20, 28)
    url:SetHeight(24)
    url:SetAutoFocus(false)
    url:SetScript("OnMouseUp", SelectURL)
    url:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(self.copyURL or "")
            self:HighlightText()
        end
    end)
    url:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        frame:Hide()
    end)
    url:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame:SetScript("OnHide", function() url:ClearFocus() end)
    frame.URL = url
    return frame
end

function namespace.OpenQuest(questID)
    if not IsQuestID(questID) then
        Print("Use a positive whole quest ID. Example: /questtidy 1456")
        return false
    end
    if not dialog then
        dialog = CreateDialog()
    end
    local note = namespace.Notes[questID]
    local questTitle = C_QuestLog and C_QuestLog.GetTitleForQuestID
        and C_QuestLog.GetTitleForQuestID(questID)
    dialog.QuestTitle:SetText(PlainText(questTitle or (note and note.title) or "Quest")
        .. "\nQuest ID " .. QuestIDText(questID))
    local body
    if note then
        body = "Player-reported advice\nCached snapshot reviewed " .. note.reviewed
            .. ". This addon does not fetch live comments.\n\n" .. note.summary
        for _, tip in ipairs(note.tips) do
            body = body .. "\n\n- " .. tip
        end
        body = body .. "\n\nSource: Wowhead Forever player comments. Open the link below for the latest reports."
    else
        body = "No bundled advice for this quest ID.\n\nThis does not mean there are no issues. Check the latest Wowhead Forever comments using the link below.\n\nThis addon does not fetch live comments. Advice bundled for other quests is a dated cached snapshot."
    end
    dialog.Advice:SetText(PlainText(body))
    dialog.AdviceContents:SetHeight(math.max(1, dialog.Advice:GetStringHeight()))
    dialog.AdviceScroll:SetVerticalScroll(0)
    dialog.URL.copyURL = "https://www.wowhead.com/forever/quest=" .. QuestIDText(questID) .. "#comments"
    dialog.URL:SetText(dialog.URL.copyURL)
    dialog:Show()
    SelectURL(dialog.URL)
    return true
end

local function RegisterMenu()
    if menuRegistered or not Menu or not Menu.ModifyMenu then
        return
    end
    Menu.ModifyMenu("MENU_QUEST_MAP_LOG_TITLE", function(owner, rootDescription)
        local questID = owner and owner.questID
        if not IsQuestID(questID) then
            return
        end
        if not QuestLogQuests_GetQuestButton or QuestLogQuests_GetQuestButton(questID) ~= owner then
            return
        end
        rootDescription:CreateDivider()
        rootDescription:CreateButton("Wowhead comments & tips", function()
            namespace.OpenQuest(questID)
        end)
    end)
    menuRegistered = true
end

local function CreateToolbar()
    if untrackButton or InCombatLockdown() then
        return
    end
    local questsFrame = QuestMapFrame and QuestMapFrame.QuestsFrame
    local scroll = questsFrame and questsFrame.ScrollFrame
    if not scroll then
        return
    end
    local anchor
    for index = 1, scroll:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = scroll:GetPoint(index)
        if point == "TOPLEFT" then
            anchor = { point, relativeTo, relativePoint, x, y }
            break
        end
    end
    if not anchor then
        return
    end
    scroll:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5] - 26)
    local button = CreateFrame("Button", nil, scroll, "UIPanelButtonTemplate")
    button:SetSize(100, 22)
    button:SetPoint("TOPRIGHT", questsFrame, "TOPRIGHT", 0, -1)
    button:SetText("Untrack all")
    button:SetScript("OnClick", namespace.UntrackAll)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Untrack all quests")
        GameTooltip:AddLine("Clears watched quests across all zones. Does not abandon quests. Automatic quest tracking may add them again.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    untrackButton = button
    trackButton = CreateFrame("Button", nil, scroll, "UIPanelButtonTemplate")
    trackButton:SetSize(110, 22)
    trackButton:SetPoint("TOPLEFT", questsFrame, "TOPLEFT", 0, -1)
    trackButton:SetText("Track quests")
    trackButton:SetScript("OnClick", function(self)
        if not MenuUtil or not MenuUtil.CreateContextMenu then
            Print("The tracking menu is not available yet. Use /questtidy track or /questtidy ready.")
            return
        end
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:CreateButton("Track all quests", function() namespace.TrackAll() end)
            rootDescription:CreateButton("Track ready quests only", function() namespace.TrackReady() end)
        end)
    end)
    UpdateButton()
end

SLASH_QUESTTIDY1 = "/questtidy"
SLASH_QUESTTIDY2 = "/qt"
SLASH_QUESTTIDY3 = "/fqn"
SlashCmdList.QUESTTIDY = function(message)
    local argument = (message or ""):match("^%s*(.-)%s*$")
    local command = argument:lower()
    if command == "untrack" then
        namespace.UntrackAll()
    elseif command == "track" then
        namespace.TrackAll()
    elseif command == "ready" then
        namespace.TrackReady()
    elseif command == "bags" then
        namespace.ReviewQuestItems()
    elseif command == "" or command == "help" then
        Print("/questtidy <questID> opens comments and tips. Commands: track, ready, untrack, bags. Aliases: /qt and /fqn.")
    else
        namespace.OpenQuest(tonumber(argument))
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
    RegisterMenu()
    CreateToolbar()
    UpdateButton()
end)
RegisterMenu()
CreateToolbar()
