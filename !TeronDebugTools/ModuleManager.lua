-- Teron's Debug Tools - Module Manager
-- Enable/disable + load-on-demand orchestration. TeronDebugToolsDB.moduleEnabled is the single
-- source of truth for "should this module load at next login"; EnableAddOn/DisableAddOn are kept
-- in sync as a best-effort mirror so a manual visit to the character-select AddOns list agrees
-- with the control panel, but nothing here depends on parsing GetAddOnInfo's return values.

-- Defensive against TeronDebugToolsDB not existing yet: SavedVariables are only injected right
-- before ADDON_LOADED fires for this addon, but ControlPanel.lua builds its module list at file
-- top-level (i.e. before that event has fired), so this can be called pre-init.
function TeronDebugTools:IsModuleEnabled(key)
	local mod = self:GetModule(key)
	if not mod then
		return false
	end
	if not TeronDebugToolsDB or not TeronDebugToolsDB.moduleEnabled or TeronDebugToolsDB.moduleEnabled[key] == nil then
		return mod.defaultEnabled
	end
	return TeronDebugToolsDB.moduleEnabled[key]
end

function TeronDebugTools:SetModuleEnabled(key, enabled)
	local mod = self:GetModule(key)
	if not mod then
		return
	end
	if not TeronDebugToolsDB then
		TeronDebugToolsDB = {}
	end
	if not TeronDebugToolsDB.moduleEnabled then
		TeronDebugToolsDB.moduleEnabled = {}
	end

	TeronDebugToolsDB.moduleEnabled[key] = enabled

	if enabled then
		EnableAddOn(mod.folderName)
		if not IsAddOnLoaded(mod.folderName) then
			local loaded, reason = LoadAddOn(mod.folderName)
			if not loaded then
				self:Print(mod.displayName .. " could not be loaded (" .. tostring(reason) .. "). It may need to be enabled from the character-select AddOns list first.")
			end
		end
	else
		DisableAddOn(mod.folderName)
		if IsAddOnLoaded(mod.folderName) then
			self:Print(mod.displayName .. " will unload after your next /reload.")
		end
	end

	if TeronDebugTools_ControlPanel and TeronDebugTools_ControlPanel.RefreshModuleTabs then
		TeronDebugTools_ControlPanel:RefreshModuleTabs()
	end
end

function TeronDebugTools:GetModuleStatusText(key)
	local mod = self:GetModule(key)
	if not mod then
		return ""
	end
	if IsAddOnLoaded(mod.folderName) then
		return "|cff33ff99Loaded|r"
	elseif self:IsModuleEnabled(key) then
		return "|cffffcc00Enabled (loads at next login)|r"
	else
		return "|cff999999Disabled|r"
	end
end

-- Called once at PLAYER_LOGIN. LoadOnDemand addons never auto-load just because they're
-- "enabled" in the client's addon list - something has to explicitly call LoadAddOn.
function TeronDebugTools:LoadEnabledModules()
	local i
	for i = 1, table.getn(self.modules) do
		local mod = self.modules[i]
		if self:IsModuleEnabled(mod.key) and not IsAddOnLoaded(mod.folderName) then
			local loaded, reason = LoadAddOn(mod.folderName)
			if not loaded and reason then
				self:Print(mod.displayName .. " did not load (" .. tostring(reason) .. ").")
			end
		end
	end
end
