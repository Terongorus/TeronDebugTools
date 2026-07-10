-- Teron's Debug Tools - Debug Log
-- Per-label ring-buffer log store. This is the closest thing to "log output to a file" a WoW
-- addon can actually do: the SavedVariables table below is written to a real .lua file on disk
-- at logout/reload - there's no live/arbitrary file-write API in this client. Other modules (and
-- the user's own addons) can log through TeronDebugTools:Log(label, msg), which forwards here.

TeronDebugTools_DebugLog = {}
local DL = TeronDebugTools_DebugLog

local DEFAULT_SIZE = 200

local function TDT_DL_InitDB()
	if not TeronDebugTools_DebugLogDB then
		TeronDebugTools_DebugLogDB = {}
	end
	if not TeronDebugTools_DebugLogDB.logs then
		TeronDebugTools_DebugLogDB.logs = {}
	end
	if not TeronDebugTools_DebugLogDB.sizes then
		TeronDebugTools_DebugLogDB.sizes = {}
	end
	if not TeronDebugTools_DebugLogDB.defaultSize then
		TeronDebugTools_DebugLogDB.defaultSize = DEFAULT_SIZE
	end
end

local function TDT_DL_GetSize(label)
	local size = TeronDebugTools_DebugLogDB.sizes[label]
	if not size then
		size = TeronDebugTools_DebugLogDB.defaultSize
	end
	return size
end

function DL:Log(label, msg)
	if not label or not msg then
		return
	end
	label = tostring(label)
	msg = tostring(msg)

	local logs = TeronDebugTools_DebugLogDB.logs
	if not logs[label] then
		logs[label] = {}
	end

	table.insert(logs[label], "[" .. date("%H:%M:%S") .. "] " .. msg)

	local size = TDT_DL_GetSize(label)
	while table.getn(logs[label]) > size do
		table.remove(logs[label], 1)
	end
end

function DL:Dump(label)
	local logs = TeronDebugTools_DebugLogDB.logs

	if not label or label == "" then
		local key
		local found = false
		for key in pairs(logs) do
			found = true
			TeronDebugTools:Print("|cffffcc00" .. key .. "|r: " .. table.getn(logs[key]) .. " entries")
		end
		if not found then
			TeronDebugTools:Print("Debug Log is empty.")
		end
		return
	end

	local entries = logs[label]
	if not entries or table.getn(entries) == 0 then
		TeronDebugTools:Print("No entries logged for '" .. label .. "'.")
		return
	end

	TeronDebugTools:Print("Debug Log - " .. label .. ":")
	local i
	for i = 1, table.getn(entries) do
		DEFAULT_CHAT_FRAME:AddMessage(entries[i])
	end
end

function DL:Clear(label)
	if label then
		TeronDebugTools_DebugLogDB.logs[label] = nil
	else
		TeronDebugTools_DebugLogDB.logs = {}
	end
end

function DL:SetSize(label, size)
	size = tonumber(size)
	if not size or size < 10 then
		size = 10
	end
	if size > 2000 then
		size = 2000
	end
	if label then
		TeronDebugTools_DebugLogDB.sizes[label] = size
	else
		TeronDebugTools_DebugLogDB.defaultSize = size
	end
end

function DL:GetLabels()
	local labels = {}
	local key
	for key in pairs(TeronDebugTools_DebugLogDB.logs) do
		table.insert(labels, key)
	end
	return labels
end

SLASH_TERONDEBUGTOOLSLOG1 = "/tdtlog"
SlashCmdList["TERONDEBUGTOOLSLOG"] = function(msg)
	if msg and msg ~= "" then
		DL:Dump(msg)
	else
		DL:Dump()
	end
end

-- Control Panel settings tab: label overview + clear-all. Buffer sizing stays a slash-command/API
-- knob (DL:SetSize) rather than a UI field, since it's a per-label setting other addons choose.
function DL.BuildControlPanel(panel)
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -8)
	title:SetText("Other tools log through here. Use /tdtlog <label> to dump one to chat.")
	title:SetWidth(460)
	title:SetJustifyH("LEFT")

	local listText = panel:CreateFontString("TeronDebugToolsDebugLogListText", "OVERLAY", "GameFontHighlightSmall")
	listText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	listText:SetWidth(460)
	listText:SetJustifyH("LEFT")

	local clearButton = CreateFrame("Button", "TeronDebugToolsDebugLogClearButton", panel, "UIPanelButtonTemplate")
	clearButton:SetWidth(120)
	clearButton:SetHeight(22)
	clearButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 4, 8)
	clearButton:SetText("Clear all logs")
	clearButton:SetScript("OnClick", function()
		DL:Clear()
		listText:SetText("(empty)")
	end)

	panel:SetScript("OnShow", function()
		local labels = DL:GetLabels()
		if table.getn(labels) == 0 then
			listText:SetText("(empty)")
		else
			local lines = ""
			local i
			for i = 1, table.getn(labels) do
				local label = labels[i]
				local count = table.getn(TeronDebugTools_DebugLogDB.logs[label])
				lines = lines .. "|cffffcc00" .. label .. "|r: " .. count .. " entries\n"
			end
			listText:SetText(lines)
		end
	end)
end

local TDT_DLEvents = CreateFrame("Frame")
TDT_DLEvents:RegisterEvent("ADDON_LOADED")
TDT_DLEvents:SetScript("OnEvent", function()
	if event == "ADDON_LOADED" and arg1 == "TeronDebugTools_DebugLog" then
		TDT_DL_InitDB()
		if TeronDebugTools and TeronDebugTools.RegisterModule then
			TeronDebugTools:RegisterModule("DebugLog", DL.BuildControlPanel)
		end
	end
end)
