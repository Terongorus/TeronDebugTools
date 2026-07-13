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

-- debugstack() captures whatever the *current* call stack is, so calling it from inside our own
-- SetText hook or error handler naturally puts that hook's own frame at the very top of the
-- trace - noise that has nothing to do with the actual error and just pushes the real, useful
-- frames (the erroring function and its callers) down. debugstack() takes an explicit start-level
-- parameter (default 1 = the function calling it), so passing 2 skips exactly that one guaranteed
-- frame by position, not by pattern-matching the file name - unlike a text-based strip, this can
-- never mistake a genuine deeper bug inside this addon's own code for capture-mechanism noise and
-- swallow it too. Any error that actually originates elsewhere in TeronDebugTools (or any other
-- addon) is completely unaffected either way, since only this one fixed leading frame is ever
-- touched.
local function TDT_EC_HookedSetText(messageFrame, text)
	EC:RecordError((text or "") .. "\n" .. debugstack(2))
	if originalSetText then
		originalSetText(messageFrame, text)
	end
end

-- seterrorhandler is a single global slot, not a chain - whichever addon calls it *last* wins for
-- the rest of the session. Several tweak addons (e.g. ShaguTweaks' "Hide Errors" mod, which
-- replaces the global `error` with a no-op and re-calls seterrorhandler on it) reassert the slot
-- well after this module's own ADDON_LOADED-time install, silently swallowing every error from
-- that point on with no indication anything changed. TDT_EC_ClaimErrorHandler is a named,
-- comparable function (not a fresh closure) so callers can detect via geterrorhandler() whether
-- something else has taken the slot, and reclaim it - called once at install, again at PLAYER_LOGIN
-- (deterministically after every other addon's own VARIABLES_LOADED-time setup has run), and then
-- periodically by a watchdog below as a backstop against anything reasserted even later (e.g. a
-- live options-panel toggle).
local function TDT_EC_ErrorHandlerFn(err)
	EC:RecordError(tostring(err) .. "\n" .. debugstack(2))
end

local function TDT_EC_ClaimErrorHandler(announceIfReclaimed)
	if geterrorhandler() == TDT_EC_ErrorHandlerFn then
		return
	end
	local stolenBy = geterrorhandler()
	seterrorhandler(TDT_EC_ErrorHandlerFn)
	if announceIfReclaimed and stolenBy ~= nil then
		DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[Teron's Debug Tools]|r Error Catcher's error handler had been overridden by another addon (likely a \"hide Lua errors\" style tweak) - reclaimed it.")
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

	TDT_EC_ClaimErrorHandler(false)

	local watchdog = CreateFrame("Frame", "TeronDebugToolsErrorCatcherWatchdog")
	local elapsed = 0
	watchdog:SetScript("OnUpdate", function()
		elapsed = elapsed + arg1
		if elapsed < 2 then
			return
		end
		elapsed = 0
		TDT_EC_ClaimErrorHandler(true)
	end)
end

local TDT_ECEvents = CreateFrame("Frame", "TeronDebugToolsErrorCatcherEvents")
TDT_ECEvents:RegisterEvent("ADDON_LOADED")
TDT_ECEvents:RegisterEvent("PLAYER_LOGIN")
TDT_ECEvents:RegisterEvent("ADDON_ACTION_BLOCKED")
TDT_ECEvents:RegisterEvent("ADDON_ACTION_FORBIDDEN")
TDT_ECEvents:SetScript("OnEvent", function()
	if event == "ADDON_LOADED" and arg1 == "TeronDebugTools_ErrorCatcher" then
		TDT_EC_Enable()
		if TeronDebugTools and TeronDebugTools.RegisterModule and TeronDebugTools_ErrorCatcherFrame and TeronDebugTools_ErrorCatcherFrame.BuildControlPanel then
			TeronDebugTools:RegisterModule("ErrorCatcher", TeronDebugTools_ErrorCatcherFrame.BuildControlPanel)
		end
	elseif event == "PLAYER_LOGIN" then
		-- Every other addon's ADDON_LOADED and VARIABLES_LOADED handling (including any
		-- error-handler reassignment they do there) is guaranteed to have already run by the
		-- time PLAYER_LOGIN fires, so this reclaim is deterministic - not a race.
		TDT_EC_ClaimErrorHandler(true)
	elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		local kind = "BLOCKED"
		if event == "ADDON_ACTION_FORBIDDEN" then
			kind = "FORBIDDEN"
		end
		EC:RecordError("ADDON_ACTION_" .. kind .. ": " .. tostring(arg1) .. " tried to call " .. tostring(arg2))
	end
end)
