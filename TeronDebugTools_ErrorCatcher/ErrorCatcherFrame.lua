-- Teron's Debug Tools - Error Catcher (display frontend)
-- Single-error paged view. Key behavior change from the old click-to-open pattern: this window
-- pops up automatically on a new error by default, and if it's already open when another error
-- arrives, its content refreshes live instead of going stale until the user repages.

TeronDebugTools_ErrorCatcherFrame = {}
local ECF = TeronDebugTools_ErrorCatcherFrame
ECF.cur = 1
ECF.unreadCount = 0

local frame = CreateFrame("Frame", "TeronDebugToolsErrorCatcherWindow", UIParent)
frame:SetWidth(500)
frame:SetHeight(400)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
-- Higher strata than the Control Panel ("DIALOG") on purpose: this window is most often opened
-- from inside the Control Panel (or auto-popup while other UI is open), and at equal strata the
-- stacking order between same-level frames isn't guaranteed - it was landing behind the still-open
-- Control Panel, making Show() look like it did nothing.
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
-- Flat/minimal tooltip-style backdrop (same as Resource Monitor's widget), not the ornate
-- UI-DialogBox skin: SetBackdropColor only tints the *background* texture, never the border, so
-- the DialogBox's decorative gold corners stayed fully visible at every opacity setting no matter
-- what the slider was set to - and the overall look didn't resemble BugSack's clean, borderless
-- panel at all. This texture pair has a thin, subtle border that the opacity slider actually reads
-- as intended.
frame:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
TeronDebugTools:RegisterOpacityFrame(frame)
frame:Hide()

local closeButton = CreateFrame("Button", "TeronDebugToolsErrorCatcherWindowClose", frame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

local captionText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
captionText:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
captionText:SetTextColor(1, 0.82, 0)
captionText:SetText("No errors yet")

local scrollFrame = CreateFrame("ScrollFrame", "TeronDebugToolsErrorCatcherScroll", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -40)
scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 56)

local editBox = CreateFrame("EditBox", "TeronDebugToolsErrorCatcherEditBox", scrollFrame)
editBox:SetMultiLine(true)
editBox:SetFontObject(ChatFontNormal)
editBox:SetWidth(400)
editBox:SetHeight(1000)
editBox:SetAutoFocus(false)
editBox:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
editBox:SetScript("OnEscapePressed", function()
	frame:Hide()
end)
editBox:SetScript("OnTextChanged", function()
	if this:GetText() ~= this.currentText then
		this:SetText(this.currentText or "")
	end
end)
scrollFrame:SetScrollChild(editBox)

local function TDT_ECF_SetContent(text)
	editBox.currentText = text or ""
	editBox:SetText(editBox.currentText)
	-- SetCursorPosition was added in patch 2.3 - doesn't exist in 1.12.1. HighlightText(0, 0)
	-- alone is enough to clear any selection.
	editBox:HighlightText(0, 0)
end

-- Reimplements BugSack's error-text coloring concept (fresh code, not ported): escape any literal
-- pipe characters in the raw message first (WoW treats "|" specially for color codes, and a raw
-- error string could legitimately contain one), THEN layer in color codes for file:line references
-- and Lua's own `identifier' quoting style, so the codes we add can't collide with anything in the
-- original text.
local function TDT_ECF_ColorizeMessage(message)
	local text = (string.gsub(message, "|", "||"))

	-- file.lua:123  ->  orange filename, green line number
	text = string.gsub(text, "([%w_%-]+%.lua):(%d+)", "|cffffa500%1|r:|cff33ff33%2|r")

	-- `identifier'  ->  Lua's own error-message quoting style, highlighted blue-purple
	text = string.gsub(text, "`([^']+)'", "|cffcc99ff`%1'|r")

	return text
end

local function TDT_ECF_FormatEntry(entry)
	if not entry then
		return "No errors captured this session."
	end
	local header = "|cff999999[" .. (entry.time or "") .. " session " .. (entry.session or 0) .. " x" .. (entry.counter or 1) .. "]|r"
	return header .. "\n" .. TDT_ECF_ColorizeMessage(entry.message)
end

local function TDT_ECF_Refresh()
	local list = TeronDebugTools_ErrorCatcher:GetErrors()
	local total = table.getn(list)

	if total == 0 then
		captionText:SetText("No errors yet")
		TDT_ECF_SetContent("Nothing caught this session. Nice.")
		return
	end

	if ECF.cur > total then
		ECF.cur = total
	end
	if ECF.cur < 1 then
		ECF.cur = 1
	end

	captionText:SetText("Error " .. ECF.cur .. " of " .. total .. " (viewing session errors)")
	TDT_ECF_SetContent(TDT_ECF_FormatEntry(list[ECF.cur]))
end

local function TDT_ECF_ShowLatest()
	local list = TeronDebugTools_ErrorCatcher:GetErrors()
	ECF.cur = table.getn(list)
	TDT_ECF_Refresh()
end

-- Layout matches BugSack's actual bottom row: Prev/Next on the left, Okay centered, First/Last
-- on the right - not the First/Prev/Next/Last-then-Okay grouping this had before.
local prevButton = CreateFrame("Button", "TeronDebugToolsErrorCatcherPrev", frame, "UIPanelButtonTemplate")
prevButton:SetWidth(60)
prevButton:SetHeight(22)
prevButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 16)
prevButton:SetText("Prev")
prevButton:SetScript("OnClick", function()
	ECF.cur = ECF.cur - 1
	TDT_ECF_Refresh()
end)

local nextButton = CreateFrame("Button", "TeronDebugToolsErrorCatcherNext", frame, "UIPanelButtonTemplate")
nextButton:SetWidth(60)
nextButton:SetHeight(22)
nextButton:SetPoint("LEFT", prevButton, "RIGHT", 4, 0)
nextButton:SetText("Next")
nextButton:SetScript("OnClick", function()
	ECF.cur = ECF.cur + 1
	TDT_ECF_Refresh()
end)

local lastButton = CreateFrame("Button", "TeronDebugToolsErrorCatcherLast", frame, "UIPanelButtonTemplate")
lastButton:SetWidth(60)
lastButton:SetHeight(22)
lastButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 16)
lastButton:SetText("Last")
lastButton:SetScript("OnClick", function()
	TDT_ECF_ShowLatest()
end)

local firstButton = CreateFrame("Button", "TeronDebugToolsErrorCatcherFirst", frame, "UIPanelButtonTemplate")
firstButton:SetWidth(60)
firstButton:SetHeight(22)
firstButton:SetPoint("RIGHT", lastButton, "LEFT", -4, 0)
firstButton:SetText("First")
firstButton:SetScript("OnClick", function()
	ECF.cur = 1
	TDT_ECF_Refresh()
end)

-- Prominent dismiss action, mirroring the "Okay" button BugSack's frame has - separate from the
-- corner close X since a big, obvious dismiss button is easier to notice on a window that just
-- auto-popped up over whatever else was on screen. Centered, matching BugSack's layout.
local okayButton = CreateFrame("Button", "TeronDebugToolsErrorCatcherOkay", frame, "UIPanelButtonTemplate")
okayButton:SetWidth(96)
okayButton:SetHeight(28)
okayButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 16)
okayButton:SetText("Okay")
okayButton:SetScript("OnClick", function()
	frame:Hide()
end)

-- The top-right corner is already crowded (close X button + the scroll frame's own scrollbar
-- both sit there), so this goes in the gap between Next and the centered Okay button instead.
local clearButton = CreateFrame("Button", "TeronDebugToolsErrorCatcherClear", frame, "UIPanelButtonTemplate")
clearButton:SetWidth(50)
clearButton:SetHeight(22)
clearButton:SetPoint("LEFT", nextButton, "RIGHT", 8, 0)
clearButton:SetText("Clear")
clearButton:SetScript("OnClick", function()
	local list = TeronDebugTools_ErrorCatcher:GetErrors()
	local n = table.getn(list)
	local i
	for i = n, 1, -1 do
		table.remove(list, i)
	end
	ECF.cur = 1
	TDT_ECF_Refresh()
	TeronDebugTools:SetMinimapBadge(0)
	ECF.unreadCount = 0
end)

function ECF:Show()
	TDT_ECF_ShowLatest()
	frame:Show()
	TeronDebugTools:SetMinimapBadge(0)
	self.unreadCount = 0
end

function ECF:Hide()
	frame:Hide()
end

function ECF:Toggle()
	if frame:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

-- Called by the capture backend (ErrorCatcher.lua) every time a new/duplicate error is recorded.
function ECF:OnNewError()
	local db = TeronDebugTools_ErrorCatcherDB

	if db and db.soundEnabled then
		PlaySound("RaidWarning")
	end

	if frame:IsShown() then
		TDT_ECF_ShowLatest()
		TeronDebugTools:SetMinimapBadge(0)
	elseif db and db.autoPopup then
		self:Show()
	else
		self.unreadCount = self.unreadCount + 1
		TeronDebugTools:SetMinimapBadge(self.unreadCount)
	end
end

SLASH_TERONDEBUGTOOLSERRORS1 = "/tdterrors"
SlashCmdList["TERONDEBUGTOOLSERRORS"] = function()
	ECF:Toggle()
end

-- Control Panel settings tab for this module.
function ECF.BuildControlPanel(panel)
	local autoCheck = CreateFrame("CheckButton", "TeronDebugToolsErrorCatcherAutoPopupCheck", panel, "UICheckButtonTemplate")
	autoCheck:SetWidth(24)
	autoCheck:SetHeight(24)
	autoCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -8)

	local autoLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	autoLabel:SetPoint("LEFT", autoCheck, "RIGHT", 4, 0)
	autoLabel:SetWidth(400)
	autoLabel:SetJustifyH("LEFT")
	autoLabel:SetText("Automatically pop up this window when a new error is caught")

	autoCheck:SetScript("OnClick", function()
		TeronDebugTools_ErrorCatcherDB.autoPopup = this:GetChecked() and true or false
	end)

	local soundCheck = CreateFrame("CheckButton", "TeronDebugToolsErrorCatcherSoundCheck", panel, "UICheckButtonTemplate")
	soundCheck:SetWidth(24)
	soundCheck:SetHeight(24)
	soundCheck:SetPoint("TOPLEFT", autoCheck, "BOTTOMLEFT", 0, -12)

	local soundLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	soundLabel:SetPoint("LEFT", soundCheck, "RIGHT", 4, 0)
	soundLabel:SetText("Play a sound when a new error is caught")

	soundCheck:SetScript("OnClick", function()
		TeronDebugTools_ErrorCatcherDB.soundEnabled = this:GetChecked() and true or false
	end)

	local openButton = CreateFrame("Button", "TeronDebugToolsErrorCatcherOpenButton", panel, "UIPanelButtonTemplate")
	openButton:SetWidth(140)
	openButton:SetHeight(22)
	openButton:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 0, -16)
	openButton:SetText("Open error window")
	openButton:SetScript("OnClick", function()
		ECF:Show()
	end)

	-- Deliberately triggers a real Lua error (not a fake injected record) so the whole pipeline -
	-- the ScriptErrors_Message/seterrorhandler hooks, storage, sound, and auto-popup - can be
	-- verified end-to-end without waiting for something else to break.
	local testButton = CreateFrame("Button", "TeronDebugToolsErrorCatcherTestButton", panel, "UIPanelButtonTemplate")
	testButton:SetWidth(140)
	testButton:SetHeight(22)
	testButton:SetPoint("LEFT", openButton, "RIGHT", 8, 0)
	testButton:SetText("Trigger test error")
	testButton:SetScript("OnClick", function()
		-- A genuine unhandled error, not a fake injected record - it goes through the exact same
		-- engine protected-call -> geterrorhandler() path any real addon bug would.
		error("TeronDebugTools test error - this is expected, triggered manually from the Errors & Stack Traces tab.")
	end)

	panel:SetScript("OnShow", function()
		autoCheck:SetChecked(TeronDebugTools_ErrorCatcherDB.autoPopup)
		soundCheck:SetChecked(TeronDebugTools_ErrorCatcherDB.soundEnabled)
	end)
end
