local addonPath = arg[1] or "."
local passed = 0

local function equal(actual, expected, message)
	assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, run)
	run()
	passed = passed + 1
	print("PASS " .. name)
end

local function setup(options)
	options = options or {}
	local state = { frames = {}, messages = {}, menus = {}, watches = {}, removed = {}, failed = {}, rows = {}, focus = 0,
		quests = {}, ready = {}, added = {}, bagItems = {}, onQuest = {}, completed = {}, deleteCalls = {} }
	local methods = {}
	local function region(parent, name)
		local value = setmetatable({ parent = parent, name = name, scripts = {}, events = {}, points = {}, shown = true, enabled = true }, { __index = methods })
		state.frames[#state.frames + 1] = value
		return value
	end
	function methods:SetScript(event, callback) self.scripts[event] = callback end
	function methods:GetScript(event) return self.scripts[event] end
	function methods:HookScript(event, callback)
		local old = self.scripts[event]
		self.scripts[event] = function(...)
			if old then old(...) end
			callback(...)
		end
	end
	function methods:RegisterEvent(event) self.events[event] = true end
	function methods:UnregisterEvent(event) self.events[event] = nil end
	function methods:UnregisterAllEvents() self.events = {} end
	function methods:SetPoint(point, relativeTo, relativePoint, x, y)
		for i, anchor in ipairs(self.points) do
			if anchor[1] == point then
				self.points[i] = { point, relativeTo, relativePoint, x, y }
				return
			end
		end
		self.points[#self.points + 1] = { point, relativeTo, relativePoint, x, y }
	end
	function methods:GetPoint(index) return unpack(self.points[index or 1]) end
	function methods:GetNumPoints() return #self.points end
	function methods:ClearAllPoints() self.points = {} end
	function methods:SetSize(width, height) self.width, self.height = width, height end
	function methods:SetWidth(width) self.width = width end
	function methods:SetHeight(height) self.height = height end
	function methods:GetWidth() return self.width or 500 end
	function methods:GetHeight() return self.height or 400 end
	function methods:SetText(value) self.text = value end
	function methods:GetText() return self.text or "" end
	function methods:GetStringHeight() return math.ceil(#self:GetText() / 60) * 16 end
	function methods:GetStringWidth() return #self:GetText() * 7 end
	function methods:SetFormattedText(format, ...) self:SetText(string.format(format, ...)) end
	function methods:CreateFontString(name) return region(self, name) end
	function methods:CreateTexture(name) return region(self, name) end
	function methods:SetTexture(texture) self.texture = texture end
	function methods:SetHyperlink(link) self.hyperlink = link end
	function methods:SetParent(parent) self.parent = parent end
	function methods:GetParent() return self.parent end
	function methods:GetName() return self.name end
	function methods:SetScrollChild(child) self.scrollChild = child end
	function methods:GetVerticalScrollRange() return 0 end
	function methods:Show()
		local changed = not self.shown
		self.shown = true
		if changed and self.scripts.OnShow then self.scripts.OnShow(self) end
	end
	function methods:Hide()
		local changed = self.shown
		self.shown = false
		if changed and self.scripts.OnHide then self.scripts.OnHide(self) end
	end
	function methods:IsShown() return self.shown end
	function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
	function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
	function methods:Enable() self.enabled = true end
	function methods:Disable() self.enabled = false end
	function methods:SetEnabled(enabled) self.enabled = enabled end
	function methods:IsEnabled() return self.enabled end
	function methods:SetFocus() self.focused = true end
	function methods:ClearFocus() self.focused = false end
	function methods:HighlightText() self.highlighted = true end
	for _, method in ipairs({ "SetMovable", "EnableMouse", "RegisterForDrag", "SetClampedToScreen", "SetFrameStrata", "SetFrameLevel", "SetAutoFocus", "SetMultiLine", "SetFontObject", "SetJustifyH", "SetJustifyV", "SetTextInsets", "SetMaxLetters", "SetTextColor", "SetWordWrap", "SetNonSpaceWrap", "SetHyperlinksEnabled", "SetVerticalScroll", "SetAllPoints", "StartMoving", "StopMovingOrSizing", "SetHitRectInsets", "SetNormalFontObject", "SetDisabledFontObject", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetResizable", "SetResizeBounds", "SetPropagateKeyboardInput", "SetColorTexture", "SetTexCoord", "SetVertexColor", "SetMaxLines" }) do
		methods[method] = function() end
	end
	local env = setmetatable({}, { __index = _G })
	env._G = env
	env.UIParent = region()
	env.UISpecialFrames = {}
	env.SlashCmdList = {}
	env.GameFontHighlight = {}
	env.GameFontHighlightSmall = {}
	env.GameFontNormalSmall = {}
	env.InCombatLockdown = function() return state.combat or false end
	env.IsLoggedIn = function() return true end
	env.GetBuildInfo = function() return "1.60.1", "70959", "", 16001 end
	env.GetCVarBool = function() return true end
	env.print = function(...) state.messages[#state.messages + 1] = table.concat({...}, " ") end
	env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) state.messages[#state.messages + 1] = text end }
	env.CreateFrame = function(_, name, parent, template)
		local frame = region(parent, name)
		if name then env[name] = frame end
		if template and template:find("BasicFrameTemplate") then
			frame.TitleText = region(frame)
			frame.CloseButton = region(frame)
		end
		return frame
	end
	env.GameTooltip = region()
	env.GameTooltip.SetOwner = function(self, owner) self.owner = owner end
	env.GameTooltip.GetOwner = function(self) return self.owner end
	env.GameTooltip.AddLine = function() end
	env.QuestUtil = { CanRemoveQuestWatch = function() return not state.restricted end }
	env.Constants = { QuestWatchConsts = { MAX_QUEST_WATCHES = 40 } }
	local function visibleQuests()
		local visible, collapsed = {}, false
		for _, info in ipairs(state.quests) do
			if info.isHeader then
				collapsed = info.isCollapsed
				visible[#visible + 1] = info
			elseif not collapsed then
				visible[#visible + 1] = info
			end
		end
		return visible
	end
	env.ExpandQuestHeader = function(index)
		local header = visibleQuests()[index]
		assert(header and header.isHeader, "expansion targets a header")
		header.isCollapsed = false
	end
	env.CollapseQuestHeader = function(index)
		local header = visibleQuests()[index]
		assert(header and header.isHeader, "collapse targets a header")
		header.isCollapsed = true
	end
	env.C_QuestLog = {
		GetNumQuestLogEntries = function() return #visibleQuests() end,
		GetInfo = function(index)
			local info = visibleQuests()[index]
			if not info then return nil end
			local copy = {}
			for key, value in pairs(info) do copy[key] = value end
			copy.questLogIndex = index
			return copy
		end,
		ReadyForTurnIn = function(id) return state.ready[id] end,
		IsComplete = function() return false end,
		IsQuestDisabledForSession = function(id) return state.disabledQuest == id end,
		GetQuestWatchType = function(id)
			for _, watched in ipairs(state.watches) do if watched == id then return 1 end end
		end,
		AddQuestWatch = function(id)
			if state.failAdd == id or #state.watches >= (state.watchCap or 40) then return false end
			for _, watched in ipairs(state.watches) do if watched == id then return false end end
			state.watches[#state.watches + 1] = id
			state.added[#state.added + 1] = id
			return true
		end,
		IsOnQuest = function(id) return state.onQuest[id] or false end,
		IsQuestFlaggedCompleted = function(id) return state.completed[id] or false end,
		GetNumQuestWatches = function() return #state.watches end,
		GetQuestIDForQuestWatchIndex = function(index) return state.watches[index] end,
		RemoveQuestWatch = function(id)
			if state.failed[id] then return false end
			for index, watched in ipairs(state.watches) do
				if watched == id then
					table.remove(state.watches, index)
					state.removed[#state.removed + 1] = id
					return true
				end
			end
			return false
		end,
		GetTitleForQuestID = function(id) return id == 1456 and "The Karnitol Shipwreck" or "Another quest" end,
		GetLogIndexForQuestID = function(id) return state.rows[id] and 1 or nil end,
	}
	env.C_SuperTrack = {
		GetSuperTrackedQuestID = function() return state.focus end,
		SetSuperTrackedQuestID = function(id) state.focus = id end,
	}
	env.QuestLogButtonTypes = { Quest = 1 }
	env.QuestLogQuests_GetQuestButton = function(id) return state.rows[id] end
	env.Menu = { ModifyMenu = function(tag, callback)
		assert(not state.menus[tag], "menu registered twice")
		state.menus[tag] = callback
	end }
	local function generateMenu(owner, callback)
		local entries = {}
		local root = { CreateDivider = function() end, CreateTitle = function() end }
		function root:CreateButton(label, action)
			local entry = { label = label, click = action, enabled = true }
			function entry:SetEnabled(enabled) self.enabled = enabled end
			entries[#entries + 1] = entry
			return entry
		end
		callback(owner, root, nil)
		return entries
	end
	env.MenuUtil = { CreateContextMenu = function(owner, callback)
		state.lastMenu = generateMenu(owner, callback)
		return {}
	end }
	env.Enum = { BagIndex = { Backpack = 0, ReagentBag = 5 }, ItemClass = { Questitem = 12 } }
	env.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
	env.GetCursorInfo = function() if state.cursor then return unpack(state.cursor) end end
	env.StaticPopupDialogs = {}
	env.StaticPopup_Show = function(name, text1, text2, data)
		state.popup = { name = name, data = data, text1 = text1, text2 = text2 }
		return state.popup
	end
	env.StaticPopup_Hide = function() state.popup = nil end
	env.StaticPopup_Visible = function(name) return state.popup and state.popup.name == name end
	env.YES, env.NO, env.DELETE, env.CANCEL = "Yes", "No", "Delete", "Cancel"
	local function bagItem(bag, slot) return (state.bagItems[bag] or {})[slot] end
	env.C_Container = {
		GetContainerNumSlots = function(bag)
			assert(bag >= 0 and bag <= 5, "scan accessed bank or keyring")
			local count = 0
			for slot in pairs(state.bagItems[bag] or {}) do count = math.max(count, slot) end
			return count
		end,
		GetContainerItemInfo = bagItem,
		GetContainerItemQuestInfo = function(bag, slot) local item = bagItem(bag, slot); return item and item.questInfo end,
	}
	env.C_Item = {
		GetItemGUID = function(location) local item = bagItem(location.bag, location.slot); return item and item.guid end,
		GetItemInfoInstant = function(id)
			for _, items in pairs(state.bagItems) do
				for _, item in pairs(items) do
					if item.itemID == id and not item.uncached then return id, "Quest", "Quest", "", item.fallbackIcon, item.classID or 12, 0 end
				end
			end
		end,
		GetItemInfo = function(id) return "Quest item " .. tostring(id) end,
		RequestLoadItemDataByID = function() end,
		DeleteItem = function(guid)
			if state.deleteBlocked then error("Deletion is restricted") end
			state.deleteCalls[#state.deleteCalls + 1] = guid
			if state.deleteNoop then return end
			for _, items in pairs(state.bagItems) do
				for slot, item in pairs(items) do
					if item.guid == guid then items[slot] = nil; return end
				end
			end
		end,
	}
	env.QuestMapFrame = region(env.UIParent)
	env.QuestMapFrame.QuestsFrame = region(env.QuestMapFrame)
	local scroll = region(env.QuestMapFrame.QuestsFrame)
	scroll:SetPoint("TOPLEFT", env.QuestMapFrame.QuestsFrame, "TOPLEFT", 0, -29)
	scroll:SetPoint("BOTTOMRIGHT", env.QuestMapFrame.QuestsFrame, "BOTTOMRIGHT", 0, 0)
	env.QuestMapFrame.QuestsFrame.ScrollFrame = scroll
	env.QuestScrollFrame = scroll
	state.scroll = scroll
	if options.delayed then
		state.savedMap, env.QuestMapFrame = env.QuestMapFrame, nil
		state.savedScroll, env.QuestScrollFrame = env.QuestScrollFrame, nil
		state.savedMenu, env.Menu = env.Menu, nil
	end
	state.combat = options.combat
	local ns = {}
	for _, file in ipairs({ "Notes.lua", "BagReview.lua", "QuestTidy.lua" }) do
		local chunk = assert(loadfile(addonPath .. "/" .. file))
		setfenv(chunk, env)
		chunk("QuestTidy", ns)
	end
	function state:event(event, ...)
		local count = #self.frames
		for i = 1, count do
			local frame = self.frames[i]
			if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
		end
	end
	function state:hasText(fragment)
		for _, frame in ipairs(self.frames) do
			if type(frame.text) == "string" and frame.text:find(fragment, 1, true) then return true end
		end
		return false
	end
	function state:button(label)
		for _, frame in ipairs(self.frames) do if frame.text == label then return frame end end
		error("Missing button " .. label)
	end
	function state:menu(owner, tag)
		return generateMenu(owner, assert(self.menus[tag or "MENU_QUEST_MAP_LOG_TITLE"], "native menu not registered"))
	end
	function state:confirm()
		local popup = assert(self.popup, "confirmation not shown")
		self.env.StaticPopupDialogs[popup.name].OnAccept(popup, popup.data)
		self.popup = nil
	end
	state.env, state.ns = env, ns
	state:event("ADDON_LOADED", "QuestTidy")
	state:event("PLAYER_LOGIN")
	state:event("PLAYER_ENTERING_WORLD")
	return state
end

test("untracks every watch despite shrinking indices", function()
	local s = setup()
	s.watches = { 1456, 1454, 987 }
	s.ns.UntrackAll()
	equal(#s.watches, 0, "remaining watches")
	equal(#s.removed, 3, "removed watches")
end)

test("clears only the successfully removed focused quest", function()
	local s = setup()
	s.watches, s.focus = { 1456, 1454 }, 1456
	s.ns.UntrackAll()
	equal(s.focus, 0, "removed quest focus")
	s.watches, s.focus = { 1456 }, 777
	s.ns.UntrackAll()
	equal(s.focus, 777, "unrelated focus")
end)

test("failed removal retains watch and focus", function()
	local s = setup()
	s.watches, s.focus, s.failed[1456] = { 1456, 1454 }, 1456, true
	s.ns.UntrackAll()
	equal(#s.watches, 1, "remaining failed watch")
	equal(s.watches[1], 1456, "failed quest")
	equal(s.focus, 1456, "failed quest focus")
end)

test("combat and native restrictions refuse removal", function()
	local s = setup()
	s.watches, s.combat = { 1456 }, true
	s.ns.UntrackAll()
	equal(#s.removed, 0, "combat removals")
	s.combat, s.restricted = false, true
	s.ns.UntrackAll()
	equal(#s.removed, 0, "restricted removals")
end)

test("zero watches is safe and leaves focus alone", function()
	local s = setup()
	s.focus = 777
	s.ns.UntrackAll()
	equal(#s.removed, 0, "empty removal")
	equal(s.focus, 777, "unrelated focus")
end)

test("button follows watch and combat state", function()
	local s = setup()
	local button = s:button("Untrack all")
	equal(button:IsEnabled(), false, "empty button")
	s.watches = { 1456 }
	s:event("QUEST_WATCH_LIST_CHANGED")
	equal(button:IsEnabled(), true, "watched button")
	s.combat = true
	s:event("PLAYER_REGEN_DISABLED")
	equal(button:IsEnabled(), false, "combat button")
	s.combat = false
	s:event("PLAYER_REGEN_ENABLED")
	equal(button:IsEnabled(), true, "post-combat button")
	assert(button.scripts.OnClick, "button click callback")
	button.scripts.OnClick(button)
	equal(#s.watches, 0, "button removed watch")
end)

test("toolbar reserves one row and preserves bottom anchor", function()
	local s = setup()
	local _, _, _, _, y = s.scroll:GetPoint(1)
	equal(y, -55, "top inset")
	equal(s.scroll:GetNumPoints(), 2, "anchor count")
	equal(select(1, s.scroll:GetPoint(2)), "BOTTOMRIGHT", "bottom anchor")
	s:event("PLAYER_ENTERING_WORLD")
	s:event("ADDON_LOADED", "OtherAddon")
	equal(select(5, s.scroll:GetPoint(1)), -55, "no repeated inset")
	s.scroll:Hide()
	equal(s:button("Untrack all"):IsVisible(), false, "hidden in details")
end)

test("quest link and notes use exact numeric chain step", function()
	local s = setup()
	s.ns.OpenQuest(1456)
	assert(s:hasText("https://www.wowhead.com/forever/quest=1456#comments"), "exact comments URL")
	assert(s:hasText("2026-11-17"), "review date")
	assert(s:hasText("Slitherblade"), "practical advice")
	s.ns.OpenQuest(1454)
	assert(s:hasText("https://www.wowhead.com/forever/quest=1454#comments"), "other chain URL")
	assert(s:hasText("No bundled advice"), "unknown advice state")
	assert(not s:hasText("Slitherblade"), "previous step advice must not leak")
end)

test("invalid IDs never create Wowhead links", function()
	local s = setup()
	for _, id in ipairs({ -1, 0, 1.5, "1456", "invalid", math.huge }) do s.ns.OpenQuest(id) end
	assert(not s:hasText("wowhead.com/forever/quest="), "invalid link")
end)

test("uncached quest uses the bundled quest title", function()
	local s = setup()
	s.env.C_QuestLog.GetTitleForQuestID = function() return nil end
	s.ns.OpenQuest(1456)
	assert(s:hasText("The Karnitol Shipwreck"), "bundled quest title")
end)

test("native quest menu captures ID before row reuse", function()
	local s = setup()
	local row = { questID = 1456, GetButtonType = function() return 1 end }
	s.rows[1456] = row
	local entries = s:menu(row)
	equal(#entries, 1, "added menu entries")
	equal(entries[1].label, "Wowhead comments & tips", "menu label")
	row.questID = 1454
	entries[1].click()
	assert(s:hasText("https://www.wowhead.com/forever/quest=1456#comments"), "captured quest ID")
end)

test("waypoint and invalid owners do not get quest actions", function()
	local s = setup()
	equal(#s:menu({}), 0, "waypoint")
	equal(#s:menu(nil), 0, "missing owner")
	equal(#s:menu({ questID = -1 }), 0, "invalid ID")
	equal(#s:menu({ questID = 1456 }), 0, "non-native owner")
end)

test("late native UI and combat initialization retry safely", function()
	local s = setup({ delayed = true, combat = true })
	equal(next(s.menus), nil, "missing menu API")
	s.env.Menu, s.env.QuestMapFrame, s.env.QuestScrollFrame = s.savedMenu, s.savedMap, s.savedScroll
	s:event("ADDON_LOADED", "Blizzard_UIPanels_Game")
	s.combat = false
	s:event("PLAYER_REGEN_ENABLED")
	assert(s.menus.MENU_QUEST_MAP_LOG_TITLE, "late menu registration")
	equal(select(5, s.scroll:GetPoint(1)), -55, "late toolbar")
end)

test("slash commands invoke the same guarded actions", function()
	local s = setup()
	local command = s.env.SlashCmdList.QUESTTIDY
	assert(command, "slash command registered")
	command("1456")
	assert(s:hasText("https://www.wowhead.com/forever/quest=1456#comments"), "slash quest URL")
	s.watches, s.combat = { 1456 }, true
	command("untrack")
	equal(#s.removed, 0, "slash combat guard")
	s.combat = false
	command("untrack")
	equal(#s.watches, 0, "slash untrack")
end)

test("individual removal exceptions do not stop remaining quests", function()
	local s = setup()
	s.watches = { 1456, 1454, 777 }
	local remove = s.env.C_QuestLog.RemoveQuestWatch
	s.env.C_QuestLog.RemoveQuestWatch = function(id)
		if id == 1454 then error("Client refused removal") end
		return remove(id)
	end
	local removed, failed = s.ns.UntrackAll()
	equal(removed, 2, "successful removals")
	equal(failed, 1, "failed removals")
	equal(s.watches[1], 1454, "refused watch remains")
end)

test("track all includes collapsed zones and preserves existing watches", function()
	local s = setup()
	s.quests = { { isHeader = true, isCollapsed = true }, { questID = 10 }, { questID = 20 },
		{ questID = 30, isTask = true }, { questID = 40, isHidden = true }, { questID = 50 }, { questID = 10 } }
	s.disabledQuest, s.watches = 50, { 20, 777 }
	local result = s.ns.TrackAll()
	equal(result.added, 1, "newly tracked")
	equal(result.already, 1, "existing eligible watch")
	equal(#s.watches, 3, "additive watch count")
	equal(#s.removed, 0, "no removal in track-all mode")
	equal(s.added[1], 10, "collapsed quest")
	equal(s.quests[1].isCollapsed, true, "collapsed state restored")
end)

test("tracking restores multiple collapsed headers at shifted indices", function()
	local s = setup()
	s.quests = { { isHeader = true, isCollapsed = true }, { questID = 10 },
		{ isHeader = true, isCollapsed = false }, { questID = 20 },
		{ isHeader = true, isCollapsed = true }, { questID = 30 } }
	s.ready, s.watches = { [10] = true, [30] = true }, { 10, 20 }
	local result = s.ns.TrackReady()
	equal(result.added, 1, "hidden ready quest added")
	equal(result.removed, 1, "nonready quest removed")
	equal(s.quests[1].isCollapsed, true, "first header restored")
	equal(s.quests[3].isCollapsed, false, "expanded header preserved")
	equal(s.quests[5].isCollapsed, true, "last header restored")
end)

test("quest read failure restores headers before refusing watch changes", function()
	local s = setup()
	s.quests, s.watches = { { isHeader = true, isCollapsed = true }, { questID = 10 } }, { 20 }
	s.env.C_QuestLog.ReadyForTurnIn = function() error("Readiness unavailable") end
	local result = s.ns.TrackReady()
	assert(result.reason, "incomplete enumeration refused")
	equal(s.quests[1].isCollapsed, true, "header restored on error")
	equal(#s.added, 0, "no added watches")
	equal(#s.removed, 0, "no removed watches")
end)

test("silent header restoration refusal prevents watch changes", function()
	local s = setup()
	s.quests = { { isHeader = true, isCollapsed = true }, { questID = 10 } }
	s.env.CollapseQuestHeader = function() end
	local result = s.ns.TrackAll()
	assert(result.reason, "restoration failure reported")
	equal(#s.added, 0, "no watches added after refused restoration")
end)

test("ready only includes talk-only readiness without IsComplete", function()
	local s = setup()
	s.quests = { { questID = 10 }, { questID = 20 }, { questID = 30 }, { questID = 40 } }
	s.ready, s.watches, s.focus = { [10] = true, [20] = true, [30] = false }, { 10, 30, 777 }, 30
	local result = s.ns.TrackReady()
	equal(result.added, 1, "missing ready watch")
	equal(result.removed, 2, "nonready removal")
	equal(result.already, 1, "ready watch retained")
	equal(#s.watches, 2, "ready-only watch count")
	equal(s.watches[1], 10, "existing ready quest")
	equal(s.watches[2], 20, "talk-only ready quest")
	equal(s.focus, 0, "removed focused quest")
end)

test("watch cap and failed additions produce partial results", function()
	local s = setup()
	s.quests, s.watchCap = { { questID = 10 }, { questID = 20 } }, 1
	local result = s.ns.TrackAll()
	equal(result.added, 1, "cap allows first quest")
	equal(result.failed, 1, "cap refusal counted")
	equal(#s.watches, 1, "actual watch count")
end)

test("ready mode respects native removal restriction before any mutation", function()
	local s = setup()
	s.quests, s.watches, s.ready[20], s.restricted = { { questID = 20 } }, { 10 }, true, true
	local result = s.ns.TrackReady()
	assert(result.reason, "restriction reason")
	equal(#s.removed, 0, "no removal")
	equal(#s.added, 0, "no partial addition")
end)

test("ready mode reports a failed removal instead of claiming an exact set", function()
	local s = setup()
	s.quests, s.watches, s.ready[20], s.failed[10] = { { questID = 20 } }, { 10 }, true, true
	local result = s.ns.TrackReady()
	equal(result.failed, 1, "failed removal count")
	equal(result.added, 1, "ready quest addition")
	equal(#s.watches, 2, "refused watch remains")
end)

test("tracking menu actions return native default close response", function()
	local s = setup()
	s.quests = { { questID = 10 } }
	local button = s:button("Track quests")
	button.scripts.OnClick(button)
	equal(#s.lastMenu, 2, "tracking choices")
	equal(s.lastMenu[1].click(), nil, "menu responder must not return result table")
	equal(s.watches[1], 10, "menu tracks quest")
end)

local function putItem(s, bag, slot, fields)
	local item = { itemID = 1000 + bag * 100 + slot, stackCount = 2, isLocked = false,
		guid = "Item-" .. bag .. "-" .. slot, classID = 12,
		questInfo = { isQuestItem = true, isActive = false } }
	for key, value in pairs(fields or {}) do item[key] = value end
	item.hyperlink = item.hyperlink or ("|Hitem:" .. item.itemID .. "|h[Quest item]|h")
	s.bagItems[bag] = s.bagItems[bag] or {}
	s.bagItems[bag][slot] = item
	return item
end

local function unknownItem()
	local s = setup()
	local item = putItem(s, 0, 1)
	local rows = s.ns.ScanQuestItems()
	equal(#rows, 1, "discovered item")
	equal(rows[1].status, "unknown", "unknown use classification")
	return s, item, rows[1]
end

test("bag scan includes carried reagent bag and excludes bank", function()
	local s = setup()
	putItem(s, 0, 1)
	putItem(s, 5, 1)
	putItem(s, 6, 1)
	putItem(s, -1, 1)
	putItem(s, 0, 2, { classID = 7, questInfo = { isQuestItem = false, isActive = false } })
	equal(#s.ns.ScanQuestItems(), 2, "carried quest items only")
end)

test("bag review puts quest items first and shows their inventory icons", function()
	local s = setup()
	putItem(s, 0, 1, { classID = 7, questInfo = { isQuestItem = false, isActive = false, questID = 91 } })
	local venom = putItem(s, 0, 5, { iconFileID = 134015, fallbackIcon = 134016,
		hyperlink = "|Hitem:1005|h[Scorpashi Venom]|h", questInfo = { isQuestItem = false, isActive = false } })
	putItem(s, 1, 1, { classID = 7, fallbackIcon = 134017, questInfo = { isQuestItem = true, isActive = true } })
	local rows = s.ns.ScanQuestItems()
	equal(#rows, 3, "three visible items")
	equal(rows[1].bag, 1, "known active quest item first")
	equal(rows[2].itemID, venom.itemID, "quest-class item before earlier quest starter")
	equal(rows[3].slot, 1, "other quest-related item last")
	assert(s.ns.ReviewQuestItems(), "review opens")
	local textures = {}
	for _, region in ipairs(s.frames) do
		if region.texture and region:IsVisible() then textures[region.texture] = true end
	end
	assert(textures[134015], "inventory icon is displayed")
	assert(textures[134017], "item API icon is displayed when inventory icon is missing")
	assert(not textures[134016], "inventory icon takes precedence")
end)

test("all quest starters remain protected including completed ones", function()
	local s = setup()
	putItem(s, 0, 1, { questInfo = { isQuestItem = true, isActive = false, questID = 90 } })
	s.completed[90] = true
	local row = s.ns.ScanQuestItems()[1]
	equal(row.status, "starts_quest", "completed starter status")
	equal(s.ns.RequestDeleteQuestItem(row), false, "starter deletion rejected")
	equal(s.popup, nil, "no delete confirmation")
end)

test("client active flag and active quest ID both protect items", function()
	local s = setup()
	putItem(s, 0, 1, { questInfo = { isQuestItem = true, isActive = true } })
	putItem(s, 0, 2, { questInfo = { isQuestItem = true, isActive = false, questID = 90 } })
	s.onQuest[90] = true
	for _, row in ipairs(s.ns.ScanQuestItems()) do
		equal(row.status, "active", "active status")
		equal(s.ns.RequestDeleteQuestItem(row), false, "active item protected")
	end
end)

test("requesting deletion requires confirmation and targets one full stack", function()
	local s, item, row = unknownItem()
	putItem(s, 0, 2)
	assert(s.ns.RequestDeleteQuestItem(row), "confirmation opened")
	equal(#s.deleteCalls, 0, "no deletion before confirmation")
	assert(s.popup.text1:find("x2", 1, true), "stack count disclosed")
	s:confirm()
	equal(#s.deleteCalls, 1, "one deletion")
	equal(s.deleteCalls[1], item.guid, "confirmed instance")
	assert(s.bagItems[0][2], "other item preserved")
end)

test("canceling confirmation deletes nothing", function()
	local s, _, row = unknownItem()
	s.ns.RequestDeleteQuestItem(row)
	local popup = s.popup
	local cancel = s.env.StaticPopupDialogs[popup.name].OnCancel
	if cancel then cancel(popup, popup.data) end
	s.popup = nil
	equal(#s.deleteCalls, 0, "cancel has no mutation")
	assert(s.bagItems[0][1], "item remains")
end)

test("moved items and replaced GUIDs invalidate open confirmation", function()
	for _, change in ipairs({ "move", "guid", "count", "link" }) do
		local s, item, row = unknownItem()
		s.ns.RequestDeleteQuestItem(row)
		if change == "move" then s.bagItems[0][1], s.bagItems[0][2] = nil, item end
		if change == "guid" then item.guid = "Different-instance" end
		if change == "count" then item.stackCount = 1 end
		if change == "link" then item.hyperlink = "|Hitem:1001:1|h[Changed]|h" end
		s:confirm()
		equal(#s.deleteCalls, 0, change .. " aborts deletion")
	end
end)

test("new combat cursor lock or active state aborts confirmation", function()
	for _, change in ipairs({ "combat", "cursor", "lock", "active", "starter", "metadata" }) do
		local s, item, row = unknownItem()
		s.ns.RequestDeleteQuestItem(row)
		if change == "combat" then s.combat = true end
		if change == "cursor" then s.cursor = { "item", 999 } end
		if change == "lock" then item.isLocked = true end
		if change == "active" then item.questInfo.isActive = true end
		if change == "starter" then item.questInfo.questID = 90 end
		if change == "metadata" then item.questInfo = nil end
		s:confirm()
		equal(#s.deleteCalls, 0, change .. " aborts deletion")
	end
end)

test("missing GUID or cached metadata never enables deletion", function()
	for _, change in ipairs({ "guid", "cache", "metadata" }) do
		local s, item = unknownItem()
		if change == "guid" then item.guid = nil end
		if change == "cache" then item.uncached = true end
		if change == "metadata" then item.questInfo = nil end
		local row = s.ns.ScanQuestItems()[1]
		if row then equal(s.ns.RequestDeleteQuestItem(row), false, change .. " cannot delete") end
		equal(#s.deleteCalls, 0, "no delete request")
	end
end)

test("popup data is independent of refreshed or mutated rows", function()
	local s, item, row = unknownItem()
	s.ns.RequestDeleteQuestItem(row)
	row.guid, row.slot = "Other-guid", 2
	s:confirm()
	equal(s.deleteCalls[1], item.guid, "original popup snapshot retained")
end)

test("restricted deletion and void no-op requests never claim success", function()
	for _, blocked in ipairs({ true, false }) do
		local s, _, row = unknownItem()
		s.deleteBlocked, s.deleteNoop = blocked, true
		s.ns.RequestDeleteQuestItem(row)
		s:confirm()
		assert(s.bagItems[0][1], "item still present")
		local last = s.messages[#s.messages]:lower()
		assert(not last:find("success", 1, true) and not last:find("item deleted", 1, true), "no false deletion claim")
	end
end)

test("bag menus target carried separate and combined bags", function()
	local s = setup()
	local function owner(bag) return { GetParent = function() return { GetBagID = function() return bag end } end } end
	equal(#s:menu(owner(0), "MENU_CONTAINER_FRAME"), 1, "backpack action")
	equal(#s:menu(owner(6), "MENU_CONTAINER_FRAME"), 0, "no bank action")
	equal(#s:menu(owner(-1), "MENU_CONTAINER_FRAME"), 0, "no keyring action")
	equal(#s:menu({}, "MENU_CONTAINER_FRAME_COMBINED"), 1, "combined bag action")
	local entry = s:menu(owner(0), "MENU_CONTAINER_FRAME")[1]
	equal(entry.click(), nil, "bag responder returns default close response")
end)

print(string.format("%d behavior checks passed. In-game layout and protected actions remain unverified.", passed))
