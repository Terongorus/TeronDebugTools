-- Teron's Debug Tools - Variable Watcher
-- Inspect tab: evaluate a one-off expression via loadstring("return "..expr) and pretty-print it.
-- Watch tab: a persistent named list, re-evaluated on demand or on a throttled 0.5s timer (never
-- per-frame) when Live Updates is on - matches the source behavior this reimplements.

TeronDebugTools_VariableWatcher = {}
local VW = TeronDebugTools_VariableWatcher

-- Forward declarations: several closures below reference each other out of definition order.
-- A `local` declared here and assigned later still resolves correctly as a shared upvalue for
-- any closure created after this declaration point, since Lua captures the variable, not its
-- value at closure-creation time.
local TDT_VW_SelectTab
local TDT_VW_RunInspect
local TDT_VW_SaveWatchList
local TDT_VW_RefreshWatchList

local MAX_DEPTH = 6
local MAX_KEYS = 200
local WATCH_AUTO_INTERVAL = 0.5
local ROW_HEIGHT = 20

local function TDT_VW_Trim(s)
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function TDT_VW_TypeColor(t)
	if t == "string" then
		return "|cffff9999"
	elseif t == "number" then
		return "|cff99ccff"
	elseif t == "boolean" then
		return "|cffffcc00"
	elseif t == "table" then
		return "|cff99ff99"
	end
	return "|cffcccccc"
end

local function TDT_VW_Serialize(value, depth, seen)
	depth = depth or 0
	seen = seen or {}
	local t = type(value)

	if t == "string" then
		return TDT_VW_TypeColor(t) .. string.format("%q", value) .. "|r"
	elseif t == "number" or t == "boolean" then
		return TDT_VW_TypeColor(t) .. tostring(value) .. "|r"
	elseif t == "nil" then
		return "|cff999999nil|r"
	elseif t == "table" then
		if seen[value] then
			return "|cff999999<circular>|r"
		end
		if depth >= MAX_DEPTH then
			return "|cff999999{...}|r"
		end
		seen[value] = true

		local lines = {}
		local indent = string.rep("  ", depth + 1)
		local count = 0
		local k, v
		for k, v in pairs(value) do
			count = count + 1
			if count > MAX_KEYS then
				table.insert(lines, indent .. "|cff999999... (truncated)|r")
				break
			end
			table.insert(lines, indent .. tostring(k) .. " = " .. TDT_VW_Serialize(v, depth + 1, seen))
		end

		seen[value] = nil

		if table.getn(lines) == 0 then
			return "{}"
		end
		return "{\n" .. table.concat(lines, "\n") .. "\n" .. string.rep("  ", depth) .. "}"
	else
		return TDT_VW_TypeColor(t) .. "<" .. t .. ">|r"
	end
end

local function TDT_VW_QuickSummary(value)
	local t = type(value)
	if t == "table" then
		local n = 0
		local k
		for k in pairs(value) do
			n = n + 1
		end
		return "table (" .. n .. " keys)"
	elseif t == "string" then
		return string.format("%q", value)
	else
		return tostring(value)
	end
end

local function TDT_VW_Evaluate(expr)
	local chunk, err = loadstring("return " .. expr)
	if not chunk then
		return nil, "Parse error: " .. tostring(err)
	end
	local ok, result = pcall(chunk)
	if not ok then
		return nil, "Runtime error: " .. tostring(result)
	end
	return result, nil
end

local function TDT_VW_InitDB()
	if not TeronDebugTools_VariableWatcherDB then
		TeronDebugTools_VariableWatcherDB = {}
	end
	if not TeronDebugTools_VariableWatcherDB.watchItems then
		TeronDebugTools_VariableWatcherDB.watchItems = {}
	end
	if TeronDebugTools_VariableWatcherDB.autoRefresh == nil then
		TeronDebugTools_VariableWatcherDB.autoRefresh = false
	end
end

-- Main window
local frame = CreateFrame("Frame", "TeronDebugToolsVariableWatcherWindow", UIParent)
frame:SetWidth(520)
frame:SetHeight(460)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
-- Higher strata than the Control Panel ("DIALOG") on purpose - see ErrorCatcherFrame.lua for why:
-- at equal strata this window (opened via the "Open Variable Watcher" button inside the Control
-- Panel) could land behind it instead of on top.
frame:SetFrameStrata("FULLSCREEN_DIALOG")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function()
	this:StartMoving()
end)
frame:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
end)
-- Flat/minimal tooltip-style backdrop, not the ornate UI-DialogBox skin - see ErrorCatcherFrame.lua
-- for why.
frame:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
TeronDebugTools:RegisterOpacityFrame(frame)
frame:Hide()

local closeButton = CreateFrame("Button", "TeronDebugToolsVariableWatcherClose", frame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", frame, "TOP", 0, -12)
title:SetTextColor(1, 0.82, 0)
title:SetText("Variable Watcher")

local inspectTabButton = CreateFrame("Button", "TeronDebugToolsVWInspectTab", frame, "UIPanelButtonTemplate")
inspectTabButton:SetWidth(80)
inspectTabButton:SetHeight(22)
inspectTabButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -40)
inspectTabButton:SetText("Inspect")
inspectTabButton:SetScript("OnClick", function()
	TDT_VW_SelectTab("Inspect")
end)

local watchTabButton = CreateFrame("Button", "TeronDebugToolsVWWatchTab", frame, "UIPanelButtonTemplate")
watchTabButton:SetWidth(80)
watchTabButton:SetHeight(22)
watchTabButton:SetPoint("LEFT", inspectTabButton, "RIGHT", 4, 0)
watchTabButton:SetText("Watch")
watchTabButton:SetScript("OnClick", function()
	TDT_VW_SelectTab("Watch")
end)

--------------------------------------------------------------------------------
-- Inspect panel
--------------------------------------------------------------------------------

local inspectPanel = CreateFrame("Frame", "TeronDebugToolsVWInspectPanel", frame)
inspectPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -68)
inspectPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)

local inspectInput = CreateFrame("EditBox", "TeronDebugToolsVWInspectInput", inspectPanel, "InputBoxTemplate")
inspectInput:SetWidth(340)
inspectInput:SetHeight(20)
inspectInput:SetPoint("TOPLEFT", inspectPanel, "TOPLEFT", 8, -8)
inspectInput:SetAutoFocus(false)
inspectInput:SetScript("OnEnterPressed", function()
	TDT_VW_RunInspect(this:GetText())
end)

local inspectButton = CreateFrame("Button", "TeronDebugToolsVWInspectButton", inspectPanel, "UIPanelButtonTemplate")
inspectButton:SetWidth(80)
inspectButton:SetHeight(22)
inspectButton:SetPoint("LEFT", inspectInput, "RIGHT", 8, 0)
inspectButton:SetText("Inspect")
inspectButton:SetScript("OnClick", function()
	TDT_VW_RunInspect(inspectInput:GetText())
end)

local inspectScrollFrame = CreateFrame("ScrollFrame", "TeronDebugToolsVWInspectScroll", inspectPanel, "UIPanelScrollFrameTemplate")
inspectScrollFrame:SetPoint("TOPLEFT", inspectInput, "BOTTOMLEFT", -8, -12)
inspectScrollFrame:SetPoint("BOTTOMRIGHT", inspectPanel, "BOTTOMRIGHT", -20, 40)

local inspectOutput = CreateFrame("EditBox", "TeronDebugToolsVWInspectOutput", inspectScrollFrame)
inspectOutput:SetMultiLine(true)
inspectOutput:SetFontObject(ChatFontNormal)
inspectOutput:SetWidth(430)
inspectOutput:SetHeight(1000)
inspectOutput:SetAutoFocus(false)
inspectOutput:SetPoint("TOPLEFT", inspectScrollFrame, "TOPLEFT", 0, 0)
inspectOutput:SetScript("OnTextChanged", function()
	if this:GetText() ~= this.currentText then
		this:SetText(this.currentText or "")
	end
end)
inspectScrollFrame:SetScrollChild(inspectOutput)

local function TDT_VW_SetInspectOutput(text)
	inspectOutput.currentText = text or ""
	inspectOutput:SetText(inspectOutput.currentText)
	-- SetCursorPosition was added in patch 2.3 - doesn't exist in 1.12.1. HighlightText(0, 0)
	-- alone is enough to clear any selection.
	inspectOutput:HighlightText(0, 0)
end

TDT_VW_RunInspect = function(expr)
	if not expr or expr == "" then
		return
	end
	inspectInput:SetText(expr)
	local value, err = TDT_VW_Evaluate(expr)
	if err then
		TDT_VW_SetInspectOutput("|cffff5555" .. err .. "|r")
	else
		TDT_VW_SetInspectOutput(TDT_VW_Serialize(value, 0, {}))
	end
end

local clearInspectButton = CreateFrame("Button", "TeronDebugToolsVWClearInspect", inspectPanel, "UIPanelButtonTemplate")
clearInspectButton:SetWidth(100)
clearInspectButton:SetHeight(22)
clearInspectButton:SetPoint("BOTTOMLEFT", inspectPanel, "BOTTOMLEFT", 8, 4)
clearInspectButton:SetText("Clear")
clearInspectButton:SetScript("OnClick", function()
	TDT_VW_SetInspectOutput("")
	inspectInput:SetText("")
end)

local copyHint = inspectPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
copyHint:SetPoint("LEFT", clearInspectButton, "RIGHT", 12, 0)
copyHint:SetText("Click into the result box and press Ctrl+A, Ctrl+C to copy")

--------------------------------------------------------------------------------
-- Watch panel
--------------------------------------------------------------------------------

local watchPanel = CreateFrame("Frame", "TeronDebugToolsVWWatchPanel", frame)
watchPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -68)
watchPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
watchPanel:Hide()

local addInput = CreateFrame("EditBox", "TeronDebugToolsVWAddInput", watchPanel, "InputBoxTemplate")
addInput:SetWidth(340)
addInput:SetHeight(20)
addInput:SetPoint("TOPLEFT", watchPanel, "TOPLEFT", 8, -8)
addInput:SetAutoFocus(false)

local addButton = CreateFrame("Button", "TeronDebugToolsVWAddButton", watchPanel, "UIPanelButtonTemplate")
addButton:SetWidth(80)
addButton:SetHeight(22)
addButton:SetPoint("LEFT", addInput, "RIGHT", 8, 0)
addButton:SetText("Add")

local watchScrollFrame = CreateFrame("ScrollFrame", "TeronDebugToolsVWWatchScroll", watchPanel, "UIPanelScrollFrameTemplate")
watchScrollFrame:SetPoint("TOPLEFT", addInput, "BOTTOMLEFT", -8, -12)
watchScrollFrame:SetPoint("BOTTOMRIGHT", watchPanel, "BOTTOMRIGHT", -20, 76)

local watchScrollChild = CreateFrame("Frame", "TeronDebugToolsVWWatchScrollChild", watchScrollFrame)
watchScrollChild:SetWidth(460)
watchScrollChild:SetHeight(1)
watchScrollFrame:SetScrollChild(watchScrollChild)

local watchRows = {}
local watchList = {}

local function TDT_VW_GetOrCreateWatchRow(index)
	local row = watchRows[index]
	if row then
		return row
	end

	row = CreateFrame("Frame", "TeronDebugToolsWatchRow" .. index, watchScrollChild)
	row:SetWidth(460)
	row:SetHeight(ROW_HEIGHT)

	local removeBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
	removeBtn:SetWidth(16)
	removeBtn:SetHeight(16)
	removeBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
	removeBtn:SetScript("OnClick", function()
		local parentRow = this:GetParent()
		table.remove(watchList, parentRow.index)
		TDT_VW_SaveWatchList()
		TDT_VW_RefreshWatchList()
	end)

	local nameButton = CreateFrame("Button", nil, row)
	nameButton:SetPoint("LEFT", removeBtn, "RIGHT", 4, 0)
	nameButton:SetWidth(160)
	nameButton:SetHeight(ROW_HEIGHT)
	-- SetNormalFontObject was added in patch 3.0 as a replacement for SetTextFontObject (added
	-- 1.10, removed 3.0.2) - the latter is the correct name for 1.12.1.
	nameButton:SetTextFontObject(GameFontNormalSmall)
	nameButton:SetScript("OnClick", function()
		TDT_VW_SelectTab("Inspect")
		TDT_VW_RunInspect(this:GetText())
	end)

	local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	valueText:SetPoint("LEFT", nameButton, "RIGHT", 4, 0)
	valueText:SetWidth(270)
	valueText:SetJustifyH("LEFT")

	row.removeBtn = removeBtn
	row.nameButton = nameButton
	row.valueText = valueText
	watchRows[index] = row
	return row
end

TDT_VW_SaveWatchList = function()
	local items = {}
	local i
	for i = 1, table.getn(watchList) do
		table.insert(items, watchList[i].expr)
	end
	TeronDebugTools_VariableWatcherDB.watchItems = items
end

TDT_VW_RefreshWatchList = function()
	local i
	for i = 1, table.getn(watchList) do
		local item = watchList[i]
		local row = TDT_VW_GetOrCreateWatchRow(i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", watchScrollChild, "TOPLEFT", 0, -(i - 1) * (ROW_HEIGHT + 2))
		row.index = i
		row.nameButton:SetText(item.expr)

		local value, err = TDT_VW_Evaluate(item.expr)
		if err then
			row.valueText:SetText("|cffff5555" .. err .. "|r")
		else
			row.valueText:SetText(TDT_VW_QuickSummary(value))
		end
		row:Show()
	end

	local j
	for j = table.getn(watchList) + 1, table.getn(watchRows) do
		watchRows[j]:Hide()
	end

	watchScrollChild:SetHeight(table.getn(watchList) * (ROW_HEIGHT + 2) + 4)
end

addButton:SetScript("OnClick", function()
	local text = addInput:GetText()
	if text and text ~= "" then
		local remaining = text
		while remaining and remaining ~= "" do
			local commaPos = string.find(remaining, ",", 1, true)
			local piece
			if commaPos then
				piece = string.sub(remaining, 1, commaPos - 1)
				remaining = string.sub(remaining, commaPos + 1)
			else
				piece = remaining
				remaining = nil
			end
			piece = TDT_VW_Trim(piece)
			if piece ~= "" then
				table.insert(watchList, { expr = piece })
			end
		end
		addInput:SetText("")
		TDT_VW_SaveWatchList()
		TDT_VW_RefreshWatchList()
	end
end)
addInput:SetScript("OnEnterPressed", function()
	addButton:Click()
end)

local liveCheck = CreateFrame("CheckButton", "TeronDebugToolsVWLiveCheck", watchPanel, "UICheckButtonTemplate")
liveCheck:SetWidth(24)
liveCheck:SetHeight(24)
liveCheck:SetPoint("BOTTOMLEFT", watchPanel, "BOTTOMLEFT", 4, 40)
liveCheck:SetScript("OnClick", function()
	TeronDebugTools_VariableWatcherDB.autoRefresh = this:GetChecked() and true or false
end)

local liveLabel = watchPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
liveLabel:SetPoint("LEFT", liveCheck, "RIGHT", 2, 0)
liveLabel:SetText("Live Updates (every 0.5s)")

local refreshAllButton = CreateFrame("Button", "TeronDebugToolsVWRefreshAll", watchPanel, "UIPanelButtonTemplate")
refreshAllButton:SetWidth(100)
refreshAllButton:SetHeight(22)
refreshAllButton:SetPoint("BOTTOMLEFT", watchPanel, "BOTTOMLEFT", 8, 8)
refreshAllButton:SetText("Refresh All")
refreshAllButton:SetScript("OnClick", function()
	TDT_VW_RefreshWatchList()
end)

local clearAllButton = CreateFrame("Button", "TeronDebugToolsVWClearAll", watchPanel, "UIPanelButtonTemplate")
clearAllButton:SetWidth(100)
clearAllButton:SetHeight(22)
clearAllButton:SetPoint("LEFT", refreshAllButton, "RIGHT", 8, 0)
clearAllButton:SetText("Clear All")
clearAllButton:SetScript("OnClick", function()
	watchList = {}
	TDT_VW_SaveWatchList()
	TDT_VW_RefreshWatchList()
end)

-- Throttled live-refresh: accumulates frame time and only does real work every 0.5s, matching
-- the source behavior this reimplements - never a per-frame table walk.
local liveElapsed = 0
watchPanel:SetScript("OnUpdate", function()
	if TeronDebugTools_VariableWatcherDB and TeronDebugTools_VariableWatcherDB.autoRefresh then
		liveElapsed = liveElapsed + arg1
		if liveElapsed >= WATCH_AUTO_INTERVAL then
			liveElapsed = 0
			TDT_VW_RefreshWatchList()
		end
	end
end)

--------------------------------------------------------------------------------
-- Tab switching, public API, slash command, control panel
--------------------------------------------------------------------------------

TDT_VW_SelectTab = function(name)
	if name == "Watch" then
		inspectPanel:Hide()
		watchPanel:Show()
		TDT_VW_RefreshWatchList()
	else
		watchPanel:Hide()
		inspectPanel:Show()
	end
end

function VW:Show()
	frame:Show()
end

function VW:Hide()
	frame:Hide()
end

function VW:Toggle()
	if frame:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

SLASH_TERONDEBUGTOOLSWATCH1 = "/tdtwatch"
SlashCmdList["TERONDEBUGTOOLSWATCH"] = function(msg)
	VW:Show()
	if msg and msg ~= "" then
		TDT_VW_SelectTab("Inspect")
		TDT_VW_RunInspect(msg)
	end
end

function VW.BuildControlPanel(panel)
	local defaultLiveCheck = CreateFrame("CheckButton", "TeronDebugToolsVWDefaultLiveCheck", panel, "UICheckButtonTemplate")
	defaultLiveCheck:SetWidth(24)
	defaultLiveCheck:SetHeight(24)
	defaultLiveCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -8)
	defaultLiveCheck:SetScript("OnClick", function()
		TeronDebugTools_VariableWatcherDB.autoRefresh = this:GetChecked() and true or false
		liveCheck:SetChecked(TeronDebugTools_VariableWatcherDB.autoRefresh)
	end)

	local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("LEFT", defaultLiveCheck, "RIGHT", 4, 0)
	label:SetText("Live Updates on by default when the Watch tab is open")

	local openButton = CreateFrame("Button", "TeronDebugToolsVWOpenButton", panel, "UIPanelButtonTemplate")
	openButton:SetWidth(160)
	openButton:SetHeight(22)
	openButton:SetPoint("TOPLEFT", defaultLiveCheck, "BOTTOMLEFT", 0, -16)
	openButton:SetText("Open Variable Watcher")
	openButton:SetScript("OnClick", function()
		VW:Show()
	end)

	panel:SetScript("OnShow", function()
		defaultLiveCheck:SetChecked(TeronDebugTools_VariableWatcherDB.autoRefresh)
	end)
end

local TDT_VWEvents = CreateFrame("Frame")
TDT_VWEvents:RegisterEvent("ADDON_LOADED")
TDT_VWEvents:SetScript("OnEvent", function()
	if event == "ADDON_LOADED" and arg1 == "TeronDebugTools_VariableWatcher" then
		TDT_VW_InitDB()

		local i
		for i = 1, table.getn(TeronDebugTools_VariableWatcherDB.watchItems) do
			table.insert(watchList, { expr = TeronDebugTools_VariableWatcherDB.watchItems[i] })
		end
		liveCheck:SetChecked(TeronDebugTools_VariableWatcherDB.autoRefresh)

		if TeronDebugTools and TeronDebugTools.RegisterModule then
			TeronDebugTools:RegisterModule("VariableWatcher", VW.BuildControlPanel)
		end
	end
end)
