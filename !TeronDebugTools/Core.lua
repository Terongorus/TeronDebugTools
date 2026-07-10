-- Teron's Debug Tools - Core
-- Namespace, module registry, and first-run/login bootstrapping.
-- Vanilla 1.12.1: widget/event scripts read event/arg1/arg2... as globals, and "this" not "self".

TeronDebugTools = {}
TeronDebugTools.VERSION = "1.0.0"

TeronDebugTools.registeredPanels = {}
TeronDebugTools.opacityFrames = {}

local DEFAULT_BG_OPACITY = 0.5
local MIN_BG_OPACITY = 0.1
local MAX_BG_OPACITY = 1

-- Static module registry. folderName must match the module's own addon folder / .toc name exactly,
-- since it's passed straight to EnableAddOn/DisableAddOn/LoadAddOn/IsAddOnLoaded/GetAddOnInfo.
TeronDebugTools.modules = {
	{
		key = "ErrorCatcher",
		folderName = "TeronDebugTools_ErrorCatcher",
		displayName = "Errors & Stack Traces",
		tabLabel = "Errors",
		description = "Catches Lua errors and shows the stack trace, with an alert popup.",
		bonus = false,
		defaultEnabled = true,
	},
	{
		key = "DebugLog",
		folderName = "TeronDebugTools_DebugLog",
		displayName = "Debug Log",
		tabLabel = "Debug Log",
		description = "Keeps a persistent, per-label log other tools (and your own addons) can write to.",
		bonus = false,
		defaultEnabled = true,
	},
	{
		key = "VariableWatcher",
		folderName = "TeronDebugTools_VariableWatcher",
		displayName = "Variable Watcher",
		tabLabel = "Watcher",
		description = "Inspect and watch Lua variables or expressions live.",
		bonus = false,
		defaultEnabled = true,
	},
	{
		key = "ResourceMonitor",
		folderName = "TeronDebugTools_ResourceMonitor",
		displayName = "Resource Monitor",
		tabLabel = "Resources",
		description = "Lightweight memory and garbage-collection widget.",
		bonus = false,
		defaultEnabled = true,
	},
	{
		key = "PerformanceProfiler",
		folderName = "TeronDebugTools_PerformanceProfiler",
		displayName = "Performance Profiler",
		tabLabel = "Profiler",
		description = "On-demand profiler for frame OnEvent/OnUpdate handlers. Heavier - opt in when you need it.",
		bonus = false,
		defaultEnabled = false,
	},
	{
		key = "SaveReminder",
		folderName = "TeronDebugTools_SaveReminder",
		displayName = "Save Reminder",
		tabLabel = "Save",
		description = "Sends a configurable command (e.g. '.save') to remind the server to save your character, on private servers that support one. Not a debugging tool - included as a bonus, off by default.",
		bonus = true,
		defaultEnabled = false,
	},
}

function TeronDebugTools:GetModule(key)
	local i
	for i = 1, table.getn(self.modules) do
		if self.modules[i].key == key then
			return self.modules[i]
		end
	end
	return nil
end

function TeronDebugTools:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[Teron's Debug Tools]|r " .. msg)
end

-- Opportunistic logging: forwards into the Debug Log module if it's loaded, no-ops otherwise,
-- so other modules can log without a hard dependency on Debug Log.
function TeronDebugTools:Log(moduleKey, message)
	if IsAddOnLoaded("TeronDebugTools_DebugLog") and TeronDebugTools_DebugLog then
		TeronDebugTools_DebugLog:Log(moduleKey, message)
	end
end

-- Called by a module once it has finished loading, so the Control Panel can render its settings tab.
function TeronDebugTools:RegisterModule(key, panelBuilderFn)
	self.registeredPanels[key] = panelBuilderFn
	if TeronDebugTools_ControlPanel and TeronDebugTools_ControlPanel.RefreshModuleTabs then
		TeronDebugTools_ControlPanel:RefreshModuleTabs()
	end
end

-- Shared background-opacity setting for every dialog-style window this addon shows (Control
-- Panel, Error Catcher, Variable Watcher, Performance Profiler, Resource Monitor). Each of those
-- frames calls RegisterOpacityFrame(frame) once at creation, both to apply the current value
-- immediately and so a later slider change updates every open (or not-yet-opened) window at once.
function TeronDebugTools:GetBackgroundOpacity()
	if TeronDebugToolsDB and TeronDebugToolsDB.backgroundOpacity then
		return TeronDebugToolsDB.backgroundOpacity
	end
	return DEFAULT_BG_OPACITY
end

-- Defensive against TeronDebugToolsDB not existing yet, same reason as ModuleManager.lua's
-- IsModuleEnabled/SetModuleEnabled: this can be called from the opacity slider's initial
-- SetValue() at ControlPanel.lua's file top-level, which runs before ADDON_LOADED (and therefore
-- before SavedVariables) are ready.
function TeronDebugTools:SetBackgroundOpacity(value)
	if value < MIN_BG_OPACITY then
		value = MIN_BG_OPACITY
	elseif value > MAX_BG_OPACITY then
		value = MAX_BG_OPACITY
	end

	if not TeronDebugToolsDB then
		TeronDebugToolsDB = {}
	end
	TeronDebugToolsDB.backgroundOpacity = value

	local i
	for i = 1, table.getn(self.opacityFrames) do
		self.opacityFrames[i]:SetBackdropColor(0, 0, 0, value)
	end
end

function TeronDebugTools:RegisterOpacityFrame(frame)
	table.insert(self.opacityFrames, frame)
	frame:SetBackdropColor(0, 0, 0, self:GetBackgroundOpacity())
end

local function TDT_InitSavedVariables()
	if not TeronDebugToolsDB then
		TeronDebugToolsDB = {}
	end
	if not TeronDebugToolsDB.minimap then
		TeronDebugToolsDB.minimap = { angle = 215, hide = false }
	end
	if not TeronDebugToolsDB.moduleEnabled then
		TeronDebugToolsDB.moduleEnabled = {}
	end
	if not TeronDebugToolsDB.backgroundOpacity then
		TeronDebugToolsDB.backgroundOpacity = DEFAULT_BG_OPACITY
	end

	-- First run: seed our own enabled/disabled record from each module's default, and mirror it
	-- into the client's native addon-enable state (EnableAddOn/DisableAddOn) so a module we want
	-- off by default (Performance Profiler, Save Reminder) doesn't need a manual AddOns-list visit.
	-- Our own TeronDebugToolsDB.moduleEnabled stays the single source of truth read everywhere
	-- else in this addon; only first-run touches the native calls directly.
	if not TeronDebugToolsDB.firstRunDone then
		local i
		for i = 1, table.getn(TeronDebugTools.modules) do
			local mod = TeronDebugTools.modules[i]
			TeronDebugToolsDB.moduleEnabled[mod.key] = mod.defaultEnabled
			if mod.defaultEnabled then
				EnableAddOn(mod.folderName)
			else
				DisableAddOn(mod.folderName)
			end
		end
		TeronDebugToolsDB.firstRunDone = true
	end
end

-- ADDON_LOADED (not PLAYER_LOGIN) is what triggers loading enabled modules, and the addon's own
-- folder is "!TeronDebugTools" (not "TeronDebugTools") specifically so both of these fire as early
-- as possible: PLAYER_LOGIN doesn't happen until every regular addon has already fully loaded, so
-- waiting for it would mean the Error Catcher's hooks (seterrorhandler, ScriptErrors_Message)
-- install only after everything else already had its chance to error. The leading "!" forces this
-- addon to sort alphabetically before virtually every other addon, so ADDON_LOADED for it - and the
-- LoadAddOn("TeronDebugTools_ErrorCatcher") call that follows - fires as close to first as WoW's
-- addon-loading sequence allows. Same technique the original BugGrabber ("!BugGrabber") used.
local TDT_CoreFrame = CreateFrame("Frame", "TeronDebugToolsCoreFrame")
TDT_CoreFrame:RegisterEvent("ADDON_LOADED")
TDT_CoreFrame:SetScript("OnEvent", function()
	if event == "ADDON_LOADED" and arg1 == "!TeronDebugTools" then
		TDT_InitSavedVariables()
		TeronDebugTools:LoadEnabledModules()
	end
end)
