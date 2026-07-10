-- Teron's Debug Tools - Control Panel
-- The single unified options frame: a "Modules" tab (enable/disable + load-on-demand status for
-- every module) plus one dynamically-added tab per module that has actually loaded and registered
-- itself via TeronDebugTools:RegisterModule(). A module that isn't loaded this session simply has
-- no settings tab yet - enabling it takes effect after the next /reload, same as any real addon.

TeronDebugTools_ControlPanel = {}

local TAB_WIDTH = 84
local TAB_HEIGHT = 22
local TABS_PER_ROW = 5

local frame = CreateFrame("Frame", "TeronDebugToolsControlPanelFrame", UIParent)
frame:SetWidth(520)
frame:SetHeight(495)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
frame:SetFrameStrata("DIALOG")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function() this:StartMoving() end)
frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
-- Flat/minimal tooltip-style backdrop, not the ornate UI-DialogBox skin - see ErrorCatcherFrame.lua
-- for why: SetBackdropColor only tints the background, never the decorative border, so the
-- opacity slider wasn't visibly doing much and the whole toolkit didn't read as one consistent
-- design language across its windows.
frame:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
TeronDebugTools:RegisterOpacityFrame(frame)
frame:Hide()

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", frame, "TOP", 0, -16)
title:SetTextColor(1, 0.82, 0)
title:SetText("Teron's Debug Tools")

local closeButton = CreateFrame("Button", "TeronDebugToolsControlPanelCloseButton", frame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

-- Tab bar reserves two rows of vertical space regardless of how many tabs are actually in use
-- this session, so the content area below never has to reflow.
local tabContentFrame = CreateFrame("Frame", "TeronDebugToolsControlPanelContent", frame)
tabContentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -92)
tabContentFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)

local modulesPanel = CreateFrame("Frame", "TeronDebugToolsModulesPanel", tabContentFrame)
modulesPanel:SetAllPoints(tabContentFrame)

local moduleRows = {}
local modulePanels = {}
local tabButtonPool = {}
local activeTabKey = "Modules"

local function TDT_BuildOpacitySection(yOffset)
	local label = modulesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", modulesPanel, "TOPLEFT", 4, yOffset)
	label:SetText("Window background opacity")

	-- OptionsSliderTemplate's Low/High/Text sub-widgets aren't exposed as direct Lua fields on
	-- older templates like this one - they need the classic getglobal(frameName.."Suffix") lookup
	-- (this client's Lua 5.0 build has no "_G" global table - confirmed via a real runtime error,
	-- getglobal() is the actual vanilla-safe way to fetch a global by name string), which requires
	-- the slider to have a real string name (it does).
	local slider = CreateFrame("Slider", "TeronDebugToolsOpacitySlider", modulesPanel, "OptionsSliderTemplate")
	slider:SetWidth(300)
	slider:SetHeight(16)
	slider:SetOrientation("HORIZONTAL")
	slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 8, -18)
	slider:SetMinMaxValues(0.1, 1)
	slider:SetValueStep(0.05)

	getglobal("TeronDebugToolsOpacitySliderLow"):SetText("0.1")
	getglobal("TeronDebugToolsOpacitySliderHigh"):SetText("1.0")
	getglobal("TeronDebugToolsOpacitySliderText"):SetText("")

	local valueText = modulesPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	valueText:SetPoint("LEFT", slider, "RIGHT", 12, 0)
	valueText:SetText(string.format("%.2f", TeronDebugTools:GetBackgroundOpacity()))

	-- Deliberately never calls slider:SetValue() from inside this handler - Slider:SetValue()
	-- re-fires OnValueChanged (unlike CheckButton:SetChecked(), which doesn't re-fire OnClick),
	-- so a naive "sync the slider to itself" pattern here would be a C-stack-overflow infinite loop.
	slider:SetScript("OnValueChanged", function()
		local value = this:GetValue()
		TeronDebugTools:SetBackgroundOpacity(value)
		valueText:SetText(string.format("%.2f", value))
	end)

	-- Deliberately NOT synced here with slider:SetValue(TeronDebugTools:GetBackgroundOpacity()) -
	-- this function runs at file-load time, before ADDON_LOADED/before SavedVariables are actually
	-- injected, so GetBackgroundOpacity() could only ever see the hardcoded default here, never a
	-- real saved value. Worse, since SetValue() re-fires OnValueChanged, doing it here would WRITE
	-- that default straight back into TeronDebugToolsDB, permanently stomping the real saved value
	-- before it ever loads (the actual bug reported: opacity always resetting to 0.5 on /reload).
	-- The real sync happens in TDT_RefreshModulesPanel() instead, which only runs once the user
	-- actually opens this tab - always well after the addon has fully loaded.

	return yOffset - 52
end

local function TDT_BuildModulesPanel()
	local i
	local yOffset = -4
	local bonusHeaderShown = false

	yOffset = TDT_BuildOpacitySection(yOffset)

	for i = 1, table.getn(TeronDebugTools.modules) do
		local mod = TeronDebugTools.modules[i]

		if mod.bonus and not bonusHeaderShown then
			local header = modulesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			header:SetPoint("TOPLEFT", modulesPanel, "TOPLEFT", 4, yOffset)
			header:SetText("|cff999999Bonus (not a debugging tool)|r")
			yOffset = yOffset - 16
			bonusHeaderShown = true
		end

		local row = CreateFrame("Frame", "TeronDebugToolsModuleRow" .. mod.key, modulesPanel)
		row:SetWidth(480)
		row:SetHeight(40)
		row:SetPoint("TOPLEFT", modulesPanel, "TOPLEFT", 0, yOffset)

		local check = CreateFrame("CheckButton", "TeronDebugToolsModuleRow" .. mod.key .. "Check", row, "UICheckButtonTemplate")
		check:SetWidth(24)
		check:SetHeight(24)
		check:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
		check.moduleKey = mod.key
		check:SetScript("OnClick", function()
			TeronDebugTools:SetModuleEnabled(this.moduleKey, this:GetChecked() and true or false)
		end)

		local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		name:SetPoint("TOPLEFT", check, "TOPRIGHT", 4, -2)
		name:SetText(mod.displayName)

		local status = row:CreateFontString("TeronDebugToolsModuleRow" .. mod.key .. "Status", "OVERLAY", "GameFontNormalSmall")
		status:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)

		-- GameFontHighlightSmall, not GameFontDisableSmall - the latter is specifically the
		-- dimmed-out style meant for actually-disabled UI elements, not readable secondary text,
		-- and was nearly illegible against the dark backdrop for every row, enabled or not.
		local desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		desc:SetPoint("TOPLEFT", check, "BOTTOMRIGHT", 4, 2)
		desc:SetWidth(430)
		desc:SetJustifyH("LEFT")
		desc:SetText(mod.description)

		row.check = check
		row.status = status
		moduleRows[mod.key] = row

		yOffset = yOffset - 44
	end
end

local function TDT_RefreshModulesPanel()
	-- Real sync point for the opacity slider - see the long comment in TDT_BuildOpacitySection
	-- for why this can't happen at build time. This does re-fire the slider's own OnValueChanged,
	-- which writes the same value straight back to TeronDebugToolsDB - harmless here since by now
	-- the DB is guaranteed to already hold the real loaded value, so it's a same-value no-op write.
	local opacitySlider = getglobal("TeronDebugToolsOpacitySlider")
	if opacitySlider then
		opacitySlider:SetValue(TeronDebugTools:GetBackgroundOpacity())
	end

	local i
	for i = 1, table.getn(TeronDebugTools.modules) do
		local mod = TeronDebugTools.modules[i]
		local row = moduleRows[mod.key]
		if row then
			row.check:SetChecked(TeronDebugTools:IsModuleEnabled(mod.key))
			row.status:SetText(TeronDebugTools:GetModuleStatusText(mod.key))
		end
	end
end

local function TDT_GetOrCreateTabButton(index)
	local btn = tabButtonPool[index]
	if not btn then
		btn = CreateFrame("Button", "TeronDebugToolsControlPanelTab" .. index, frame, "UIPanelButtonTemplate")
		btn:SetWidth(TAB_WIDTH)
		btn:SetHeight(TAB_HEIGHT)
		tabButtonPool[index] = btn
	end
	return btn
end

local function TDT_SelectTab(key)
	activeTabKey = key
	modulesPanel:Hide()
	local k, panel
	for k, panel in pairs(modulePanels) do
		panel:Hide()
	end
	if key == "Modules" then
		TDT_RefreshModulesPanel()
		modulesPanel:Show()
	elseif modulePanels[key] then
		modulePanels[key]:Show()
	end
end

function TeronDebugTools_ControlPanel:RefreshModuleTabs()
	local index = 1
	local col = 0
	local row = 0

	local modulesTab = TDT_GetOrCreateTabButton(index)
	modulesTab:SetText("Modules")
	modulesTab:ClearAllPoints()
	modulesTab:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + col * (TAB_WIDTH + 4), -40 - row * (TAB_HEIGHT + 4))
	modulesTab:SetScript("OnClick", function() TDT_SelectTab("Modules") end)
	modulesTab:Show()
	col = col + 1
	index = index + 1

	local i
	for i = 1, table.getn(TeronDebugTools.modules) do
		local mod = TeronDebugTools.modules[i]
		local builder = TeronDebugTools.registeredPanels[mod.key]
		if builder then
			if not modulePanels[mod.key] then
				local panel = CreateFrame("Frame", "TeronDebugToolsControlPanelPanel" .. mod.key, tabContentFrame)
				panel:SetAllPoints(tabContentFrame)
				panel:Hide()
				builder(panel)
				modulePanels[mod.key] = panel
			end

			if col >= TABS_PER_ROW then
				col = 0
				row = row + 1
			end

			local tabBtn = TDT_GetOrCreateTabButton(index)
			tabBtn:SetText(mod.tabLabel or mod.displayName)
			tabBtn:ClearAllPoints()
			tabBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + col * (TAB_WIDTH + 4), -40 - row * (TAB_HEIGHT + 4))
			local key = mod.key
			tabBtn:SetScript("OnClick", function() TDT_SelectTab(key) end)
			tabBtn:Show()
			col = col + 1
			index = index + 1
		end
	end

	local j
	for j = index, table.getn(tabButtonPool) do
		tabButtonPool[j]:Hide()
	end

	TDT_SelectTab(activeTabKey)
end

function TeronDebugTools_ControlPanel:Show()
	self:RefreshModuleTabs()
	frame:Show()
end

function TeronDebugTools_ControlPanel:Hide()
	frame:Hide()
end

function TeronDebugTools_ControlPanel:Toggle()
	if frame:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

TDT_BuildModulesPanel()
TeronDebugTools_ControlPanel:RefreshModuleTabs()

SLASH_TERONDEBUGTOOLS1 = "/tdt"
SlashCmdList["TERONDEBUGTOOLS"] = function()
	TeronDebugTools_ControlPanel:Toggle()
end
