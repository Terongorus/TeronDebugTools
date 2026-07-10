-- Teron's Debug Tools - Performance Profiler
-- On-demand profiler: scans the frame tree, wraps each found frame's existing OnEvent/OnUpdate
-- handler to measure call count / cumulative time / cumulative memory delta, then ranks the
-- results in a bar-graph window. Hooks are fully reversible - "Stop Profiling" restores every
-- original handler it saved - since making this its own opt-in load-on-demand module is exactly
-- how the persistent hook overhead here stays under the user's control, not left running forever
-- once triggered.

TeronDebugTools_PerformanceProfiler = {}
local PP = TeronDebugTools_PerformanceProfiler

local MAX_SCAN_DEPTH = 12
local ROW_COUNT = 12

local hooked = {}
local stats = {}
local sortMode = "time"
local showOnEvent = true
local showOnUpdate = true
local rows = {}

--------------------------------------------------------------------------------
-- Logic (defined before any UI so button handlers below can reference these directly)
--------------------------------------------------------------------------------

local function TDT_PP_WrapHandler(frameObj, scriptType, label)
	local original = frameObj:GetScript(scriptType)
	if not original then
		return
	end
	if not hooked[frameObj] then
		hooked[frameObj] = {}
	end
	if hooked[frameObj][scriptType] then
		return
	end
	hooked[frameObj][scriptType] = original

	local statKey = label .. ":" .. scriptType
	if not stats[statKey] then
		stats[statKey] = { name = label, kind = scriptType, count = 0, totalTime = 0, totalMemory = 0 }
	end

	-- The wrapped handler is called with the same globals (this/event/arg1...) the engine already
	-- set before invoking it, so calling `original()` with no arguments correctly forwards them -
	-- vanilla widget scripts read their payload from globals, not function parameters.
	frameObj:SetScript(scriptType, function()
		local startTime = GetTime()
		local startMem = gcinfo()

		original()

		local stat = stats[statKey]
		stat.count = stat.count + 1
		stat.totalTime = stat.totalTime + (GetTime() - startTime)
		stat.totalMemory = stat.totalMemory + (gcinfo() - startMem)
	end)
end

local function TDT_PP_ScanFrame(frameObj, depth)
	if not frameObj or depth > MAX_SCAN_DEPTH then
		return
	end

	local name = frameObj.GetName and frameObj:GetName()
	if name then
		if frameObj:GetScript("OnEvent") then
			TDT_PP_WrapHandler(frameObj, "OnEvent", name)
		end
		if frameObj:GetScript("OnUpdate") then
			TDT_PP_WrapHandler(frameObj, "OnUpdate", name)
		end
	end

	-- Vanilla Lua 5.0 has no select(), so GetChildren()'s multiple returns are captured into a
	-- table instead of indexed with select(i, ...).
	local children = { frameObj:GetChildren() }
	local i
	for i = 1, table.getn(children) do
		TDT_PP_ScanFrame(children[i], depth + 1)
	end
end

local function TDT_PP_UnhookAll()
	local frameObj, scripts
	for frameObj, scripts in pairs(hooked) do
		local scriptType, original
		for scriptType, original in pairs(scripts) do
			frameObj:SetScript(scriptType, original)
		end
	end
	hooked = {}
	stats = {}
end

local function TDT_PP_StatValue(stat)
	if sortMode == "count" then
		return stat.count
	elseif sortMode == "memory" then
		return stat.totalMemory
	end
	return stat.totalTime
end

local function TDT_PP_GetSortedStats()
	local list = {}
	local key, stat
	for key, stat in pairs(stats) do
		if (stat.kind == "OnEvent" and showOnEvent) or (stat.kind == "OnUpdate" and showOnUpdate) then
			table.insert(list, stat)
		end
	end

	-- Insertion sort: the hooked-handler set is at most a few hundred entries and this only runs
	-- on a throttled 0.5s cadence, so O(n^2) here is not a concern.
	local i, j
	for i = 2, table.getn(list) do
		local current = list[i]
		local currentVal = TDT_PP_StatValue(current)
		j = i - 1
		while j >= 1 and TDT_PP_StatValue(list[j]) < currentVal do
			list[j + 1] = list[j]
			j = j - 1
		end
		list[j + 1] = current
	end

	return list
end

local function TDT_PP_RefreshDisplay()
	local list = TDT_PP_GetSortedStats()
	local maxVal = 0

	local i
	for i = 1, table.getn(list) do
		local val = TDT_PP_StatValue(list[i])
		if val > maxVal then
			maxVal = val
		end
	end
	if maxVal == 0 then
		maxVal = 1
	end

	for i = 1, ROW_COUNT do
		local stat = list[i]
		local bar = rows[i]
		if stat and bar then
			local val = TDT_PP_StatValue(stat)

			bar:SetMinMaxValues(0, maxVal)
			bar:SetValue(val)

			local ratio = val / maxVal
			if ratio > 0.66 then
				bar:SetStatusBarColor(0.8, 0.2, 0.2)
			elseif ratio > 0.33 then
				bar:SetStatusBarColor(0.9, 0.8, 0.1)
			else
				bar:SetStatusBarColor(0.2, 0.8, 0.2)
			end

			local kindColor = "|cff99ccff"
			if stat.kind == "OnUpdate" then
				kindColor = "|cffff9999"
			end
			bar.label:SetText(kindColor .. stat.name .. "|r")
			bar.fullLabel = stat.name .. " (" .. stat.kind .. ")"
			bar.tooltipCount = stat.count
			bar.tooltipTime = stat.totalTime
			bar.tooltipMemory = stat.totalMemory

			if sortMode == "count" then
				bar.value:SetText(tostring(stat.count))
			elseif sortMode == "memory" then
				bar.value:SetText(string.format("%.1f KB", stat.totalMemory))
			else
				bar.value:SetText(string.format("%.3f s", stat.totalTime))
			end

			bar:Show()
		elseif bar then
			bar:Hide()
		end
	end
end

local function TDT_PP_CreateRows(parent)
	local i
	for i = 1, ROW_COUNT do
		local bar = CreateFrame("StatusBar", "TeronDebugToolsPPRow" .. i, parent)
		bar:SetWidth(460)
		bar:SetHeight(18)
		bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8 - (i - 1) * 22)
		bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)

		local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("LEFT", bar, "LEFT", 4, 0)
		label:SetJustifyH("LEFT")

		local value = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		value:SetPoint("RIGHT", bar, "RIGHT", -4, 0)

		bar:EnableMouse(true)
		bar:SetScript("OnEnter", function()
			GameTooltip:SetOwner(this, "ANCHOR_TOP")
			GameTooltip:SetText(this.fullLabel or "")
			if this.tooltipCount then
				GameTooltip:AddLine("Count: " .. this.tooltipCount, 1, 1, 1)
				GameTooltip:AddLine("Total time: " .. string.format("%.3f", this.tooltipTime) .. "s", 1, 1, 1)
				GameTooltip:AddLine("Total memory: " .. string.format("%.1f", this.tooltipMemory) .. " KB", 1, 1, 1)
			end
			GameTooltip:Show()
		end)
		bar:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		bar.label = label
		bar.value = value
		bar:Hide()
		rows[i] = bar
	end
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame", "TeronDebugToolsPerformanceProfilerWindow", UIParent)
frame:SetWidth(500)
frame:SetHeight(420)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
-- Higher strata than the Control Panel ("DIALOG") on purpose - see ErrorCatcherFrame.lua for why:
-- at equal strata this window (opened via the "Open Profiler" button inside the Control Panel)
-- could land behind it instead of on top.
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

local closeButton = CreateFrame("Button", "TeronDebugToolsPerformanceProfilerClose", frame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", frame, "TOP", 0, -12)
title:SetTextColor(1, 0.82, 0)
title:SetText("Performance Profiler")

local scanButton = CreateFrame("Button", "TeronDebugToolsPPScanButton", frame, "UIPanelButtonTemplate")
scanButton:SetWidth(80)
scanButton:SetHeight(22)
scanButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -36)
scanButton:SetText("Scan")
scanButton:SetScript("OnClick", function()
	TDT_PP_ScanFrame(UIParent, 0)
	TDT_PP_ScanFrame(WorldFrame, 0)
	TDT_PP_RefreshDisplay()
end)

local stopButton = CreateFrame("Button", "TeronDebugToolsPPStopButton", frame, "UIPanelButtonTemplate")
stopButton:SetWidth(100)
stopButton:SetHeight(22)
stopButton:SetPoint("LEFT", scanButton, "RIGHT", 4, 0)
stopButton:SetText("Stop Profiling")
stopButton:SetScript("OnClick", function()
	TDT_PP_UnhookAll()
	TDT_PP_RefreshDisplay()
end)

local sortCountButton = CreateFrame("Button", "TeronDebugToolsPPSortCount", frame, "UIPanelButtonTemplate")
sortCountButton:SetWidth(70)
sortCountButton:SetHeight(22)
sortCountButton:SetPoint("LEFT", stopButton, "RIGHT", 12, 0)
sortCountButton:SetText("Count")
sortCountButton:SetScript("OnClick", function()
	sortMode = "count"
	TDT_PP_RefreshDisplay()
end)

local sortTimeButton = CreateFrame("Button", "TeronDebugToolsPPSortTime", frame, "UIPanelButtonTemplate")
sortTimeButton:SetWidth(70)
sortTimeButton:SetHeight(22)
sortTimeButton:SetPoint("LEFT", sortCountButton, "RIGHT", 4, 0)
sortTimeButton:SetText("Time")
sortTimeButton:SetScript("OnClick", function()
	sortMode = "time"
	TDT_PP_RefreshDisplay()
end)

local sortMemoryButton = CreateFrame("Button", "TeronDebugToolsPPSortMemory", frame, "UIPanelButtonTemplate")
sortMemoryButton:SetWidth(70)
sortMemoryButton:SetHeight(22)
sortMemoryButton:SetPoint("LEFT", sortTimeButton, "RIGHT", 4, 0)
sortMemoryButton:SetText("Memory")
sortMemoryButton:SetScript("OnClick", function()
	sortMode = "memory"
	TDT_PP_RefreshDisplay()
end)

local showEventCheck = CreateFrame("CheckButton", "TeronDebugToolsPPShowEvent", frame, "UICheckButtonTemplate")
showEventCheck:SetWidth(20)
showEventCheck:SetHeight(20)
showEventCheck:SetPoint("TOPLEFT", scanButton, "BOTTOMLEFT", 0, -8)
showEventCheck:SetChecked(true)
showEventCheck:SetScript("OnClick", function()
	showOnEvent = this:GetChecked() and true or false
	TDT_PP_RefreshDisplay()
end)
local showEventLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
showEventLabel:SetPoint("LEFT", showEventCheck, "RIGHT", 2, 0)
showEventLabel:SetText("OnEvent")

local showUpdateCheck = CreateFrame("CheckButton", "TeronDebugToolsPPShowUpdate", frame, "UICheckButtonTemplate")
showUpdateCheck:SetWidth(20)
showUpdateCheck:SetHeight(20)
showUpdateCheck:SetPoint("LEFT", showEventLabel, "RIGHT", 12, 0)
showUpdateCheck:SetChecked(true)
showUpdateCheck:SetScript("OnClick", function()
	showOnUpdate = this:GetChecked() and true or false
	TDT_PP_RefreshDisplay()
end)
local showUpdateLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
showUpdateLabel:SetPoint("LEFT", showUpdateCheck, "RIGHT", 2, 0)
showUpdateLabel:SetText("OnUpdate")

local autoCheck = CreateFrame("CheckButton", "TeronDebugToolsPPAutoUpdate", frame, "UICheckButtonTemplate")
autoCheck:SetWidth(20)
autoCheck:SetHeight(20)
autoCheck:SetPoint("LEFT", showUpdateLabel, "RIGHT", 12, 0)
local autoLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
autoLabel:SetPoint("LEFT", autoCheck, "RIGHT", 2, 0)
autoLabel:SetText("Auto-Update")

local rowContainer = CreateFrame("Frame", "TeronDebugToolsPPRowContainer", frame)
rowContainer:SetPoint("TOPLEFT", showEventCheck, "BOTTOMLEFT", -4, -12)
rowContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
TDT_PP_CreateRows(rowContainer)

local autoElapsed = 0
frame:SetScript("OnUpdate", function()
	if autoCheck:GetChecked() then
		autoElapsed = autoElapsed + arg1
		if autoElapsed >= 0.5 then
			autoElapsed = 0
			TDT_PP_RefreshDisplay()
		end
	end
end)

--------------------------------------------------------------------------------
-- Public API / control panel
--------------------------------------------------------------------------------

function PP:Scan()
	TDT_PP_ScanFrame(UIParent, 0)
	TDT_PP_ScanFrame(WorldFrame, 0)
	TDT_PP_RefreshDisplay()
end

function PP:UnhookAll()
	TDT_PP_UnhookAll()
	TDT_PP_RefreshDisplay()
end

function PP:Show()
	frame:Show()
end

function PP:Hide()
	frame:Hide()
end

function PP:Toggle()
	if frame:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

SLASH_TERONDEBUGTOOLSPROFILER1 = "/tdtprofiler"
SlashCmdList["TERONDEBUGTOOLSPROFILER"] = function()
	PP:Toggle()
end

function PP.BuildControlPanel(panel)
	local warning = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	warning:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -8)
	warning:SetWidth(460)
	warning:SetJustifyH("LEFT")
	warning:SetText("Hooking handlers to profile them adds overhead that stays until you click Stop Profiling. Use it when you need it, not as a background monitor.")

	local openButton = CreateFrame("Button", "TeronDebugToolsPPOpenButton", panel, "UIPanelButtonTemplate")
	openButton:SetWidth(160)
	openButton:SetHeight(22)
	openButton:SetPoint("TOPLEFT", warning, "BOTTOMLEFT", 0, -16)
	openButton:SetText("Open Profiler")
	openButton:SetScript("OnClick", function()
		PP:Show()
	end)
end

local TDT_PPEvents = CreateFrame("Frame")
TDT_PPEvents:RegisterEvent("ADDON_LOADED")
TDT_PPEvents:SetScript("OnEvent", function()
	if event == "ADDON_LOADED" and arg1 == "TeronDebugTools_PerformanceProfiler" then
		if TeronDebugTools and TeronDebugTools.RegisterModule then
			TeronDebugTools:RegisterModule("PerformanceProfiler", PP.BuildControlPanel)
		end
	end
end)
