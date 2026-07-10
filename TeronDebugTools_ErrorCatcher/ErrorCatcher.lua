-- Teron's Debug Tools - Error Catcher (capture backend)
-- Reimplements the classic vanilla error-capture technique: the client's default Lua-error dialog
-- (ScriptErrors / ScriptErrors_Message) is how `error()` calls actually surface in 1.12.1, so
-- hooking its SetText call and suppressing its Show is how an error catcher intercepts them here -
-- there's no reliable seterrorhandler-chaining alternative in this client. seterrorhandler is also
-- set directly as a second capture path for errors that don't go through the dialog.
-- Note: a known vanilla client bug corrupts SavedVariables string entries longer than ~983
-- characters, so stored messages are capped well under that.

TeronDebugTools_ErrorCatcher = {}
local EC = TeronDebugTools_ErrorCatcher

local MAX_MESSAGE_LENGTH = 950
local DEFAULT_LIMIT = 50

EC.session = 1
local liveErrors = {}
local recording = false

local function TDT_EC_Trim(str, maxLen)
	if string.len(str) > maxLen then
		return string.sub(str, 1, maxLen) .. " ...(truncated)"
	end
	return str
end

local function TDT_EC_InitDB()
	if not TeronDebugTools_ErrorCatcherDB then
		TeronDebugTools_ErrorCatcherDB = {}
	end
	if TeronDebugTools_ErrorCatcherDB.limit == nil then
		TeronDebugTools_ErrorCatcherDB.limit = DEFAULT_LIMIT
	end
	if TeronDebugTools_ErrorCatcherDB.autoPopup == nil then
		TeronDebugTools_ErrorCatcherDB.autoPopup = true
	end
	if TeronDebugTools_ErrorCatcherDB.soundEnabled == nil then
		TeronDebugTools_ErrorCatcherDB.soundEnabled = true
	end
	if TeronDebugTools_ErrorCatcherDB.session == nil then
		TeronDebugTools_ErrorCatcherDB.session = 0
	end
	TeronDebugTools_ErrorCatcherDB.session = TeronDebugTools_ErrorCatcherDB.session + 1
	EC.session = TeronDebugTools_ErrorCatcherDB.session

	-- Errors don't carry over between sessions - a /reload or fresh login starts with a clean
	-- slate rather than accumulating stale errors from three reloads ago. The "session" counter
	-- above and each record's stamped session number become redundant with this always cleared,
	-- but are kept so the "(x3)" dedupe-counter tooltip/caption text still reads sensibly.
	TeronDebugTools_ErrorCatcherDB.errors = {}
end

function EC:GetErrors()
	if TeronDebugTools_ErrorCatcherDB then
		return TeronDebugTools_ErrorCatcherDB.errors
	end
	return liveErrors
end

-- `recording` is a reentrancy guard, not a permanent kill-switch: if something downstream (most
-- likely the display frontend) errors while we're still handling an earlier error, that nested
-- call is dropped so it can't recurse - but the guard always resets right after, via pcall, even
-- if the body below errors. An earlier version used a one-way "looping = true" latch that, once
-- tripped by a real display bug, silently disabled error capture for the rest of the session -
-- exactly the failure mode that let a later, unrelated error go uncaught. Storage (table.insert)
-- also happens *before* the frontend notify step, so even if the display call fails, the error
-- itself is never lost - only its popup notification might not have shown.
function EC:RecordError(message)
	if not message or message == "" then
		return
	end
	if recording then
		return
	end
	recording = true

	local ok, err = pcall(function()
		message = TDT_EC_Trim(message, MAX_MESSAGE_LENGTH)

		local list = self:GetErrors()
		local last = list[table.getn(list)]

		if last and last.message == message and last.session == self.session then
			last.counter = last.counter + 1
			last.time = date("%H:%M:%S")
		else
			local limit = DEFAULT_LIMIT
			if TeronDebugTools_ErrorCatcherDB then
				limit = TeronDebugTools_ErrorCatcherDB.limit
			end

			table.insert(list, {
				message = message,
				session = self.session,
				counter = 1,
				time = date("%H:%M:%S"),
			})

			while table.getn(list) > limit do
				table.remove(list, 1)
			end
		end

		TeronDebugTools:Log("ErrorCatcher", message)

		if TeronDebugTools_ErrorCatcherFrame and TeronDebugTools_ErrorCatcherFrame.OnNewError then
			TeronDebugTools_ErrorCatcherFrame:OnNewError()
		end
	end)

	recording = false

	if not ok then
		DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[Teron's Debug Tools]|r Error Catcher hit an internal error while recording (" .. tostring(err) .. "). That one error may be incomplete, but capture will keep working for the next one.")
	end
end

-- Formats the most recent captured errors as ready-to-display tooltip lines (number, occurrence
-- count, first line of the message only - not the full stack trace), for the minimap button.
function EC:GetTooltipLines(maxLines)
	local list = self:GetErrors()
	local total = table.getn(list)
	local lines = {}
	local startIndex = total - maxLines + 1
	if startIndex < 1 then
		startIndex = 1
	end

	local i
	for i = startIndex, total do
		local entry = list[i]
		local firstLine = entry.message
		local newlinePos = string.find(firstLine, "\n", 1, true)
		if newlinePos then
			firstLine = string.sub(firstLine, 1, newlinePos - 1)
		end
		table.insert(lines, i .. ". (x" .. entry.counter .. ") " .. firstLine)
	end

	return lines, total
end

local originalSetText = nil

local function TDT_EC_HookedSetText(messageFrame, text)
	EC:RecordError((text or "") .. "\n" .. debugstack())
	if originalSetText then
		originalSetText(messageFrame, text)
	end
end

local function TDT_EC_Enable()
	TDT_EC_InitDB()

	if ScriptErrors_Message and ScriptErrors_Message.SetText then
		originalSetText = ScriptErrors_Message.SetText
		ScriptErrors_Message.SetText = TDT_EC_HookedSetText
	end
	if ScriptErrors then
		ScriptErrors.Show = function() end
	end

	seterrorhandler(function(err)
		EC:RecordError(tostring(err) .. "\n" .. debugstack())
	end)
end

local TDT_ECEvents = CreateFrame("Frame", "TeronDebugToolsErrorCatcherEvents")
TDT_ECEvents:RegisterEvent("ADDON_LOADED")
TDT_ECEvents:RegisterEvent("ADDON_ACTION_BLOCKED")
TDT_ECEvents:RegisterEvent("ADDON_ACTION_FORBIDDEN")
TDT_ECEvents:SetScript("OnEvent", function()
	if event == "ADDON_LOADED" and arg1 == "TeronDebugTools_ErrorCatcher" then
		TDT_EC_Enable()
		if TeronDebugTools and TeronDebugTools.RegisterModule and TeronDebugTools_ErrorCatcherFrame and TeronDebugTools_ErrorCatcherFrame.BuildControlPanel then
			TeronDebugTools:RegisterModule("ErrorCatcher", TeronDebugTools_ErrorCatcherFrame.BuildControlPanel)
		end
	elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		local kind = "BLOCKED"
		if event == "ADDON_ACTION_FORBIDDEN" then
			kind = "FORBIDDEN"
		end
		EC:RecordError("ADDON_ACTION_" .. kind .. ": " .. tostring(arg1) .. " tried to call " .. tostring(arg2))
	end
end)
