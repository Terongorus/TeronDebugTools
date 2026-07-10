-- Teron's Debug Tools - Resource Monitor
-- Lightweight, always-cheap memory/GC widget. Reimplements the source's polling cadence: label
-- text refreshes at 1Hz, the peak-memory-spike bar at ~10Hz, and OnUpdate itself is gated by
-- elapsed time on every tick rather than doing real work every frame.

TeronDebugTools_ResourceMonitor = {}
local RM = TeronDebugTools_ResourceMonitor

local LABEL_INTERVAL = 1.0
local PEAK_INTERVAL = 0.1
local PEAK_DECAY = 0.5

local function TDT_RM_InitDB()
	if not TeronDebugTools_ResourceMonitorDB then
		TeronDebugTools_ResourceMonitorDB = {}
	end
	if not TeronDebugTools_ResourceMonitorDB.point then
		TeronDebugTools_ResourceMonitorDB.point = { "CENTER", "UIParent", "CENTER", 200, 200 }
	end
end

local frame = CreateFrame("Button", "TeronDebugToolsResourceMonitorWidget", UIParent)
frame:SetWidth(190)
frame:SetHeight(80)
frame:SetFrameStrata("MEDIUM")
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
frame:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
TeronDebugTools:RegisterOpacityFrame(frame)

local rateText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
rateText:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
rateText:SetJustifyH("LEFT")

local memText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
memText:SetPoint("TOPLEFT", rateText, "BOTTOMLEFT", 0, -2)
memText:SetJustifyH("LEFT")

local cleanupText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
cleanupText:SetPoint("TOPLEFT", memText, "BOTTOMLEFT", 0, -2)
cleanupText:SetJustifyH("LEFT")

local peakBar = CreateFrame("StatusBar", "TeronDebugToolsResourceMonitorPeakBar", frame)
peakBar:SetWidth(174)
peakBar:SetHeight(14)
peakBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)
peakBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
peakBar:SetStatusBarColor(0.8, 0.2, 0.2)
peakBar:SetMinMaxValues(0, 200)
peakBar:SetValue(0)
peakBar.peak = 0

local function TDT_RM_ApplyPosition()
	local p = TeronDebugTools_ResourceMonitorDB.point
	frame:ClearAllPoints()
	frame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
end

frame:SetScript("OnDragStart", function()
	this:StartMoving()
end)
frame:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	local point, _, relPoint, x, y = this:GetPoint()
	TeronDebugTools_ResourceMonitorDB.point = { point, "UIParent", relPoint, x, y }
end)

frame:SetScript("OnClick", function()
	if arg1 == "LeftButton" then
		peakBar.peak = 0
		peakBar:SetValue(0)
	end
end)

frame:SetScript("OnEnter", function()
	GameTooltip:SetOwner(this, "ANCHOR_TOP")
	GameTooltip:SetText("Resource Monitor")
	GameTooltip:AddLine("Left-click: reset the peak bar", 1, 1, 1)
	GameTooltip:AddLine("Drag: move this widget", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)
frame:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)

local lastMem = gcinfo()
local maxMem = 0
local lastCleanupTime = nil
local labelElapsed = 0
local peakElapsed = 0

local function TDT_RM_UpdateLabels()
	local mem = gcinfo()
	local rate = mem - lastMem

	if mem < lastMem then
		lastCleanupTime = date("%H:%M:%S")
	end

	if mem > maxMem then
		maxMem = mem
	end

	rateText:SetText("Rate: " .. string.format("%.1f", rate) .. " KB/s")
	memText:SetText("Memory: " .. string.format("%.0f", mem / 1024) .. " / " .. string.format("%.0f", maxMem / 1024) .. " MB")

	if lastCleanupTime then
		cleanupText:SetText("Last cleanup: " .. lastCleanupTime)
	else
		cleanupText:SetText("Last cleanup: none yet")
	end

	if rate > peakBar.peak then
		peakBar.peak = rate
		local minVal, maxVal = peakBar:GetMinMaxValues()
		if peakBar.peak > maxVal then
			peakBar:SetMinMaxValues(0, peakBar.peak)
		end
		peakBar:SetValue(peakBar.peak)
	end

	lastMem = mem
end

frame:SetScript("OnUpdate", function()
	labelElapsed = labelElapsed + arg1
	peakElapsed = peakElapsed + arg1

	if peakElapsed >= PEAK_INTERVAL then
		peakElapsed = 0
		if peakBar.peak > 0 then
			peakBar.peak = peakBar.peak - PEAK_DECAY
			if peakBar.peak < 0 then
				peakBar.peak = 0
			end
			peakBar:SetValue(peakBar.peak)
		end
	end

	if labelElapsed >= LABEL_INTERVAL then
		labelElapsed = 0
		TDT_RM_UpdateLabels()
	end
end)

function RM:Show()
	frame:Show()
end

function RM:Hide()
	frame:Hide()
end

function RM:Toggle()
	if frame:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

function RM.BuildControlPanel(panel)
	local hideCheck = CreateFrame("CheckButton", "TeronDebugToolsRMHideCheck", panel, "UICheckButtonTemplate")
	hideCheck:SetWidth(24)
	hideCheck:SetHeight(24)
	hideCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -8)
	hideCheck:SetScript("OnClick", function()
		TeronDebugTools_ResourceMonitorDB.hidden = this:GetChecked() and true or false
		if TeronDebugTools_ResourceMonitorDB.hidden then
			RM:Hide()
		else
			RM:Show()
		end
	end)

	local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("LEFT", hideCheck, "RIGHT", 4, 0)
	label:SetWidth(400)
	label:SetJustifyH("LEFT")
	label:SetText("Hide the floating widget")

	panel:SetScript("OnShow", function()
		hideCheck:SetChecked(TeronDebugTools_ResourceMonitorDB.hidden)
	end)
end

local TDT_RMEvents = CreateFrame("Frame")
TDT_RMEvents:RegisterEvent("ADDON_LOADED")
TDT_RMEvents:SetScript("OnEvent", function()
	if event == "ADDON_LOADED" and arg1 == "TeronDebugTools_ResourceMonitor" then
		TDT_RM_InitDB()
		TDT_RM_ApplyPosition()
		if TeronDebugTools_ResourceMonitorDB.hidden then
			frame:Hide()
		end
		if TeronDebugTools and TeronDebugTools.RegisterModule then
			TeronDebugTools:RegisterModule("ResourceMonitor", RM.BuildControlPanel)
		end
	end
end)
