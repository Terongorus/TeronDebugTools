-- Teron's Debug Tools - Save Reminder
-- Reimplements the periodic + triggered chat-command automation used on private servers that
-- implement a custom GM-save handler. Not a debugging tool by itself - included as a bonus
-- module, off by default, kept out of the way of the five real debugging modules.
-- The command itself is configurable, not hardcoded to ".save" - that's AutoSave's original
-- command, but it's specific to whichever server implements it (confirmed: Kronos does not), so
-- there's no single command guaranteed to work everywhere.

TeronDebugTools_SaveReminder = {}
local SR = TeronDebugTools_SaveReminder

local MIN_INTERVAL = 100
local DEFAULT_INTERVAL = 400
local CHECK_INTERVAL = 5
local DEFAULT_SAVE_COMMAND = ".save"

local lastSaveTime = 0
local checkElapsed = 0

local function TDT_SR_InitDB()
	if not TeronDebugTools_SaveReminderDB then
		TeronDebugTools_SaveReminderDB = {}
	end
	if TeronDebugTools_SaveReminderDB.interval == nil then
		TeronDebugTools_SaveReminderDB.interval = DEFAULT_INTERVAL
	end
	if TeronDebugTools_SaveReminderDB.printConfirm == nil then
		TeronDebugTools_SaveReminderDB.printConfirm = false
	end
	if TeronDebugTools_SaveReminderDB.triggerPeriodic == nil then
		TeronDebugTools_SaveReminderDB.triggerPeriodic = true
	end
	if TeronDebugTools_SaveReminderDB.triggerCombat == nil then
		TeronDebugTools_SaveReminderDB.triggerCombat = false
	end
	if TeronDebugTools_SaveReminderDB.triggerLevel == nil then
		TeronDebugTools_SaveReminderDB.triggerLevel = false
	end
	if TeronDebugTools_SaveReminderDB.triggerSkill == nil then
		TeronDebugTools_SaveReminderDB.triggerSkill = false
	end
	if TeronDebugTools_SaveReminderDB.triggerQuest == nil then
		TeronDebugTools_SaveReminderDB.triggerQuest = false
	end
	if TeronDebugTools_SaveReminderDB.saveCommand == nil then
		TeronDebugTools_SaveReminderDB.saveCommand = DEFAULT_SAVE_COMMAND
	end
	lastSaveTime = GetTime()
end

local function TDT_SR_DoSave(reason)
	if UnitAffectingCombat("player") then
		return
	end
	-- No AFK suppression: vanilla 1.12.1 has no UnitIsAFK (added post-vanilla) and no UnitFlags
	-- either, so there's no reliable, non-locale-dependent way to query current AFK state at all
	-- (only PLAYER_FLAGS_CHANGED, which reports that *something* changed, not what to). Tracking
	-- it via CHAT_MSG_SYSTEM text-matching would only work on English clients and could break on
	-- any server with custom message text, so it's left out rather than shipped fragile.

	local command = TeronDebugTools_SaveReminderDB.saveCommand
	if not command or command == "" then
		-- Cleared out (e.g. no equivalent command exists on this server) - nothing to send.
		return
	end

	SendChatMessage(command, "SAY", nil)
	lastSaveTime = GetTime()

	if TeronDebugTools_SaveReminderDB.printConfirm then
		TeronDebugTools:Print("Save Reminder: sent " .. command .. " (" .. reason .. ")")
	end
end

local eventsFrame = CreateFrame("Frame", "TeronDebugToolsSaveReminderEvents")
eventsFrame:RegisterEvent("ADDON_LOADED")
eventsFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventsFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventsFrame:RegisterEvent("CHAT_MSG_SKILL")
eventsFrame:RegisterEvent("QUEST_TURNED_IN")
eventsFrame:SetScript("OnEvent", function()
	if event == "ADDON_LOADED" and arg1 == "TeronDebugTools_SaveReminder" then
		TDT_SR_InitDB()
		if TeronDebugTools and TeronDebugTools.RegisterModule then
			TeronDebugTools:RegisterModule("SaveReminder", SR.BuildControlPanel)
		end
	elseif event == "PLAYER_REGEN_ENABLED" and TeronDebugTools_SaveReminderDB and TeronDebugTools_SaveReminderDB.triggerCombat then
		TDT_SR_DoSave("left combat")
	elseif event == "PLAYER_LEVEL_UP" and TeronDebugTools_SaveReminderDB and TeronDebugTools_SaveReminderDB.triggerLevel then
		TDT_SR_DoSave("level up")
	elseif event == "CHAT_MSG_SKILL" and TeronDebugTools_SaveReminderDB and TeronDebugTools_SaveReminderDB.triggerSkill then
		TDT_SR_DoSave("skill up")
	elseif event == "QUEST_TURNED_IN" and TeronDebugTools_SaveReminderDB and TeronDebugTools_SaveReminderDB.triggerQuest then
		TDT_SR_DoSave("quest turned in")
	end
end)

-- Coarse 5s-throttled timer rather than a dedicated per-frame OnUpdate doing real work - a single
-- elapsed-time comparison every 5s is negligible, and doesn't depend on combat-adjacent events
-- happening to fire often enough to piggyback on.
local timerFrame = CreateFrame("Frame")
timerFrame:SetScript("OnUpdate", function()
	checkElapsed = checkElapsed + arg1
	if checkElapsed < CHECK_INTERVAL then
		return
	end
	checkElapsed = 0

	if not TeronDebugTools_SaveReminderDB or not TeronDebugTools_SaveReminderDB.triggerPeriodic then
		return
	end

	local interval = TeronDebugTools_SaveReminderDB.interval
	if interval < MIN_INTERVAL then
		interval = MIN_INTERVAL
	end

	if GetTime() - lastSaveTime >= interval then
		TDT_SR_DoSave("periodic")
	end
end)

function SR.BuildControlPanel(panel)
	local y = -8

	local function TDT_SR_MakeCheck(name, labelText, dbKey)
		local check = CreateFrame("CheckButton", "TeronDebugToolsSaveReminder" .. name, panel, "UICheckButtonTemplate")
		check:SetWidth(24)
		check:SetHeight(24)
		check:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, y)

		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("LEFT", check, "RIGHT", 4, 0)
		label:SetText(labelText)

		check:SetScript("OnClick", function()
			TeronDebugTools_SaveReminderDB[dbKey] = this:GetChecked() and true or false
		end)

		y = y - 28
		return check
	end

	local periodicCheck = TDT_SR_MakeCheck("Periodic", "Save periodically", "triggerPeriodic")
	local combatCheck = TDT_SR_MakeCheck("Combat", "Save when leaving combat", "triggerCombat")
	local levelCheck = TDT_SR_MakeCheck("Level", "Save on level up", "triggerLevel")
	local skillCheck = TDT_SR_MakeCheck("Skill", "Save on skill up", "triggerSkill")
	local questCheck = TDT_SR_MakeCheck("Quest", "Save on quest turn-in", "triggerQuest")
	local confirmCheck = TDT_SR_MakeCheck("Confirm", "Print a chat confirmation on save", "printConfirm")

	-- Not hardcoded to ".save" - that only works on servers that implement that exact custom
	-- command (confirmed: Kronos doesn't). Leaving this blank disables sending anything at all.
	local commandLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	commandLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, y - 8)
	commandLabel:SetText("Command to send (blank = disabled, server-specific):")

	local commandBox = CreateFrame("EditBox", "TeronDebugToolsSaveReminderCommand", panel, "InputBoxTemplate")
	commandBox:SetWidth(100)
	commandBox:SetHeight(20)
	commandBox:SetPoint("LEFT", commandLabel, "RIGHT", 8, 0)
	commandBox:SetAutoFocus(false)
	commandBox:SetScript("OnEnterPressed", function()
		TeronDebugTools_SaveReminderDB.saveCommand = this:GetText()
		this:ClearFocus()
	end)

	local intervalLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	intervalLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, y - 36)
	intervalLabel:SetText("Periodic interval, seconds (minimum " .. MIN_INTERVAL .. "):")

	local intervalBox = CreateFrame("EditBox", "TeronDebugToolsSaveReminderInterval", panel, "InputBoxTemplate")
	intervalBox:SetWidth(60)
	intervalBox:SetHeight(20)
	intervalBox:SetPoint("LEFT", intervalLabel, "RIGHT", 8, 0)
	intervalBox:SetAutoFocus(false)
	intervalBox:SetNumeric(true)
	intervalBox:SetScript("OnEnterPressed", function()
		local val = tonumber(this:GetText())
		if val and val >= MIN_INTERVAL then
			TeronDebugTools_SaveReminderDB.interval = val
		else
			TeronDebugTools_SaveReminderDB.interval = MIN_INTERVAL
			this:SetText(tostring(MIN_INTERVAL))
		end
		this:ClearFocus()
	end)

	panel:SetScript("OnShow", function()
		periodicCheck:SetChecked(TeronDebugTools_SaveReminderDB.triggerPeriodic)
		combatCheck:SetChecked(TeronDebugTools_SaveReminderDB.triggerCombat)
		levelCheck:SetChecked(TeronDebugTools_SaveReminderDB.triggerLevel)
		skillCheck:SetChecked(TeronDebugTools_SaveReminderDB.triggerSkill)
		questCheck:SetChecked(TeronDebugTools_SaveReminderDB.triggerQuest)
		confirmCheck:SetChecked(TeronDebugTools_SaveReminderDB.printConfirm)
		intervalBox:SetText(tostring(TeronDebugTools_SaveReminderDB.interval))
		commandBox:SetText(TeronDebugTools_SaveReminderDB.saveCommand or "")
	end)
end
