-- Teron's Debug Tools - Minimap Button
-- Custom draggable minimap icon (no LibDBIcon/FuBar dependency). Left-click opens the Control
-- Panel. Position persists as an angle around the minimap in TeronDebugToolsDB.minimap.angle.

local TDT_MinimapButton = CreateFrame("Button", "TeronDebugToolsMinimapButton", Minimap)
TDT_MinimapButton:SetWidth(31)
TDT_MinimapButton:SetHeight(31)
TDT_MinimapButton:SetFrameStrata("MEDIUM")
TDT_MinimapButton:SetFrameLevel(8)
TDT_MinimapButton:SetMovable(true)
TDT_MinimapButton:EnableMouse(true)
TDT_MinimapButton:RegisterForDrag("LeftButton")
TDT_MinimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
TDT_MinimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local icon = TDT_MinimapButton:CreateTexture(nil, "BACKGROUND")
icon:SetWidth(20)
icon:SetHeight(20)
icon:SetPoint("TOPLEFT", TDT_MinimapButton, "TOPLEFT", 5, -5)
icon:SetTexture("Interface\\Icons\\INV_Gizmo_02")
TDT_MinimapButton.icon = icon

local overlay = TDT_MinimapButton:CreateTexture(nil, "OVERLAY")
overlay:SetWidth(53)
overlay:SetHeight(53)
overlay:SetPoint("TOPLEFT", TDT_MinimapButton, "TOPLEFT", 0, 0)
overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local badge = TDT_MinimapButton:CreateFontString("TeronDebugToolsMinimapBadge", "OVERLAY", "GameFontNormalSmall")
badge:SetPoint("BOTTOMRIGHT", TDT_MinimapButton, "BOTTOMRIGHT", -2, 2)
badge:SetTextColor(1, 0.2, 0.2)
badge:Hide()
TDT_MinimapButton.badge = badge

-- Public API: Error Catcher (or any module) can call this to show an unread-error count.
function TeronDebugTools:SetMinimapBadge(count)
	if count and count > 0 then
		badge:SetText(tostring(count))
		badge:Show()
	else
		badge:Hide()
	end
end

local function TDT_UpdateMinimapPosition()
	local angle = TeronDebugToolsDB.minimap.angle or 215
	local radius = 80
	local x = math.cos(math.rad(angle)) * radius
	local y = math.sin(math.rad(angle)) * radius
	TDT_MinimapButton:ClearAllPoints()
	TDT_MinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

TDT_MinimapButton:SetScript("OnDragStart", function()
	this:LockHighlight()
	this.dragging = true
end)

TDT_MinimapButton:SetScript("OnDragStop", function()
	this:UnlockHighlight()
	this.dragging = false
end)

-- Throttled: only recompute the angle while actively dragging, not every frame otherwise.
TDT_MinimapButton:SetScript("OnUpdate", function()
	if this.dragging then
		local mx, my = Minimap:GetCenter()
		local px, py = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		px, py = px / scale, py / scale
		local angle = math.deg(math.atan2(py - my, px - mx))
		TeronDebugToolsDB.minimap.angle = angle
		TDT_UpdateMinimapPosition()
	end
end)

TDT_MinimapButton:SetScript("OnClick", function()
	if arg1 == "LeftButton" then
		if TeronDebugTools_ControlPanel then
			TeronDebugTools_ControlPanel:Toggle()
		end
	elseif arg1 == "RightButton" then
		-- Opportunistic: only works if Error Catcher happens to be loaded, same guard pattern as
		-- the tooltip preview below. Does nothing otherwise, rather than erroring.
		if IsAddOnLoaded("TeronDebugTools_ErrorCatcher") and TeronDebugTools_ErrorCatcherFrame then
			TeronDebugTools_ErrorCatcherFrame:Show()
		end
	end
end)

TDT_MinimapButton:SetScript("OnEnter", function()
	GameTooltip:SetOwner(this, "ANCHOR_LEFT")
	GameTooltip:SetText("Teron's Debug Tools")

	-- Recent-errors preview, matching BugSack's minimap tooltip (number, occurrence count, first
	-- line of each message). Opportunistic: only shown if Error Catcher happens to be loaded.
	if IsAddOnLoaded("TeronDebugTools_ErrorCatcher") and TeronDebugTools_ErrorCatcher then
		local lines, total = TeronDebugTools_ErrorCatcher:GetTooltipLines(5)
		if total > 0 then
			GameTooltip:AddLine(" ")
			local i
			for i = 1, table.getn(lines) do
				GameTooltip:AddLine(lines[i], 1, 0.82, 0)
			end
			if total > table.getn(lines) then
				GameTooltip:AddLine("(+" .. (total - table.getn(lines)) .. " earlier this session)", 0.6, 0.6, 0.6)
			end
		end
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Left-click: open control panel", 1, 1, 1)
	if IsAddOnLoaded("TeronDebugTools_ErrorCatcher") then
		GameTooltip:AddLine("Right-click: open latest error", 1, 1, 1)
	end
	GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)

TDT_MinimapButton:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)

local TDT_MinimapEventFrame = CreateFrame("Frame")
TDT_MinimapEventFrame:RegisterEvent("PLAYER_LOGIN")
TDT_MinimapEventFrame:SetScript("OnEvent", function()
	TDT_UpdateMinimapPosition()
end)
