--!strict
-- Lumen — usage example.
--
-- Drop this LocalScript under StarterPlayer/StarterPlayerScripts (or any
-- client entry point), point the require below at wherever you installed
-- the Library/spr ModuleScripts (see docs.md "Install"), and hit Play: the
-- "Search" launcher appears bottom-center, exactly as it looked in Studio.
--
-- This is deliberately the whole integration — three calls. Everything
-- else (the search filtering, the browser panel, all motion) is already
-- wired by Library.bind; you only need this file if you want to trigger
-- Lumen from your own code (a hotkey, a HUD button, ...) or replace its
-- demo content.

local Players = game:GetService("Players")

-- EDIT ME: point this at wherever you placed the Library ModuleScript.
-- If you followed docs.md's Studio install, this is the default location.
local Library = require(game:GetService("ReplicatedStorage"):WaitForChild("Lumen"):WaitForChild("Library"))

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- 1) Build the UI. `handles` gives you a named reference to every part of
--    the tree (see docs.md "Handles") if you want to reach in and tweak
--    something after the fact.
local handles = Library.create(playerGui)

-- 2) Wire interaction + motion. This is what makes the launcher clickable,
--    binds the "/" shortcut, Escape-to-close, search filtering, and all the
--    open/close animation phases. `controller` is returned for cases where
--    you want to trigger Lumen from outside a click — see below.
local controller = Library.bind(handles)

-- That's the whole integration. Everything below is optional.

-- Optional: also open Lumen from a custom keybind (Ctrl+K), in addition to
-- the built-in "/" shortcut and clicking the launcher button.
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.K and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
		controller.open()
	end
end)

-- Optional: jump straight to a specific result's browser page programmatically
-- (e.g. from a notification toast) instead of waiting for the player to
-- search for it. `Library.DATA` isn't exported (it's private demo content —
-- see docs.md "Customization points" for swapping it out for your own),
-- so this constructs an ad-hoc Entry instead:
--
-- controller.open()
-- controller.openBrowser({
-- 	title = "Patch Notes", sub = "What changed today", tag = "Docs",
-- 	url = "lumen.app/patch-notes",
-- 	icon = { "rbxassetid://8445470559", 104, 304, 96 },
-- 	paras = { "Balance changes, bug fixes, and one new map." },
-- })
