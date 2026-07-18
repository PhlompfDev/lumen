--!strict
-- Lumen: a spotlight-search launcher with an in-UI browser overlay.
-- Exported from Plopacle (source UI id ui-fb2efa) via the GUI-to-library
-- workflow — see docs.md. This UI predates the TUNING convention (the
-- original carries no PlopacleNode attributes), so the motion values below
-- are transcribed verbatim from the original's Controller script rather
-- than routed through a TUNING table (canon: export-guide.md).
--
-- MOTION CONTRACT (strictly phased — never cross-fade two layers):
--   OPEN PAGE   0) search column leaves fast (nothing may show through the window)
--               1) window scales out from centre (0.5,0.5 anchor) + fades in
--               2) elements inside fade in + drop down 8px, staggered
--   CLOSE PAGE  1) every element inside disappears, all at once
--               2) window shrinks inward toward centre + fades
--               3) search column returns
--
-- Four invariants keep it clean:
--   * spr keeps its own internal position and IGNORES a bare property write, so
--     every start value goes through stopSet() (spr.stop then write) or springs
--     launch from a stale position — that is what reads as a "jump".
--   * A translucent thing on top still shows what is behind it. Layers must not
--     fade in/out at the same time, or you see the other one through it.
--   * Stacked same-colour surfaces (white rows on a white card) can NOT be faded
--     as separate elements — two 50% whites composite to ~75% while the bare card
--     is 50%, so the card reads as gone while the rows still look solid. The
--     results card is a CanvasGroup and fades once via GroupTransparency.
--   * A UIStroke placed directly on a CanvasGroup is NOT covered by
--     GroupTransparency — Roblox composites the fill + descendants into the
--     offscreen buffer, but the group's own stroke renders as a separate pass on
--     top. The Ring must be sprung by hand alongside GroupTransparency; see
--     fadeResultsChrome().

local spr = loadstring(game:HttpGet("https://raw.githubusercontent.com/nyzuu/SprLib/refs/heads/main/spr.lua"))()

-- ================================================================ constants

local ASSET_SHADOW = "rbxassetid://126976986987654"
local ASSET_SEARCH_ICON = "rbxassetid://8445470189"
local ASSET_BACK_GLYPH = "rbxassetid://8445471499"
local ASSET_LOCK = "rbxassetid://8445472085"

local GOTHAM = "rbxasset://fonts/families/GothamSSm.json"
local fMedium = Font.new(GOTHAM, Enum.FontWeight.Medium)
local fSemi = Font.new(GOTHAM, Enum.FontWeight.SemiBold)
local fReg = Font.new(GOTHAM, Enum.FontWeight.Regular)

local C_TEXT = Color3.fromHex("26282E")
local C_BODY = Color3.fromHex("4A4E56")
local C_MUTED = Color3.fromHex("9CA1AA")
local C_ACCENT = Color3.fromHex("3E7BFA")
local C_ROW_REST = Color3.fromHex("FFFFFF")
local C_ROW_HOVER = Color3.fromHex("F6F7F9")
local C_ROW_SELECTED = Color3.fromHex("F3F7FF")
local C_ICONBOX = Color3.fromHex("F4F5F7")
local C_ICONBOX_SEL = Color3.fromHex("E8F0FE")
local C_GLYPH = Color3.fromHex("6B7078")
local C_KBD_TEXT = Color3.fromHex("8A8F98")

local SCRIM_REST = 0.42
local MAX_VISIBLE = 6
local ROW_H, ROW_GAP, LIST_TOP = 52, 4, 36

-- motion timing ---------------------------------------------------------
local CONTENT_DROP = 8        -- how far page elements fall in (subtle)
local CONTENT_STAGGER = 0.03
local OPEN_SCALE = 0.90       -- window starts here on open
local CLOSE_SCALE = 0.86      -- window shrinks to here on close (deep enough to read)
local OPEN_WINDOW_AT = 0.08   -- window starts after the search column has gone
local OPEN_CONTENT_AT = 0.05  -- elements start once the window reads as visible/sized,
                               -- not after its spring fully settles
local CLOSE_SHELL_AT = 0.05   -- window starts shrinking once elements are gone
local CLOSE_SEARCH_AT = 0.20  -- search returns once the window has mostly cleared
local CLOSE_HIDE_AT = 0.48

-- ---------------------------------------------------------------- app data
-- Demo content for the search/browse example. Replace with your own — see
-- docs.md "Customization points".
export type Entry = {
	title: string, sub: string, tag: string, url: string,
	icon: { string | number }, paras: { string },
}
local ICON = {
	Map = { "rbxassetid://8445471713", 304, 4, 96 },
	Wrench = { "rbxassetid://6764432408", 0, 850, 50 },
	Forum = { "rbxassetid://8445470559", 104, 304, 96 },
	Cloud = { "rbxassetid://8445470984", 504, 304, 96 },
	Mountain = { "rbxassetid://8445470017", 404, 864, 96 },
	Store = { "rbxassetid://8445470392", 104, 204, 96 },
	Bookmark = { "rbxassetid://8445470392", 204, 704, 96 },
	Account = { "rbxassetid://8445470984", 804, 804, 96 },
}
local DATA: { Entry } = {
	{ title = "Overkill Wiki", sub = "Weapon stats, maps & lore", tag = "Docs", url = "wiki.overkill.gg", icon = ICON.Map,
	  paras = {
		"The community wiki covers every weapon family, from the humble sidearm tier through the exotic finishers, with damage curves measured across all four test ranges.",
		"Map pages include callout diagrams, spawn rotations and a short history of each arena — Duels was originally a greybox called Quarry before the waterfall pass.",
	  } },
	{ title = "Armory Planner", sub = "Build & compare loadouts", tag = "App", url = "planner.overkill.gg", icon = ICON.Wrench,
	  paras = {
		"Drag any two loadouts side by side and the planner overlays their time-to-kill bands so you can see exactly where each build wins the trade.",
		"Saved builds sync to your account and can be shared with a short code — paste one into squad chat and teammates preview it inline.",
	  } },
	{ title = "Team Chat", sub = "Squad threads and DMs", tag = "Social", url = "chat.lumen.app", icon = ICON.Forum,
	  paras = {
		"Threads keep strategy talk out of the main channel; pin the ones that matter and they follow the squad into the lobby between matches.",
		"Direct messages support quick reactions and loadout-code previews, so a build shared mid-match is one tap from the planner.",
	  } },
	{ title = "Cloud Saves", sub = "Backups synced 2 min ago", tag = "System", url = "saves.lumen.app", icon = ICON.Cloud,
	  paras = {
		"Every settings profile, keybind layout and loadout snapshot is versioned — roll back to any point in the last thirty days from this page.",
		"Sync runs after each match and on every settings change; the badge in the corner shows the last completed backup.",
	  } },
	{ title = "Photo Vault", sub = "Highlights & screenshots", tag = "Media", url = "vault.lumen.app", icon = ICON.Mountain,
	  paras = {
		"Match highlights are clipped automatically around multi-elims and clutch rounds, then filed by map and mode for quick scrubbing.",
		"Screenshots taken with the in-game camera keep their depth data, so you can re-frame and re-light a shot long after the match ends.",
	  } },
	{ title = "Marketplace", sub = "Skins, charms & bundles", tag = "Shop", url = "market.overkill.gg", icon = ICON.Store,
	  paras = {
		"The rotating storefront refreshes daily at midnight UTC; wishlist any item and Lumen pings you the next time it cycles in.",
		"Bundle pages break out per-item pricing so you can see exactly what the discount is worth against pieces you already own.",
	  } },
	{ title = "Library", sub = "Guides you saved for later", tag = "Docs", url = "library.lumen.app", icon = ICON.Bookmark,
	  paras = {
		"Everything you bookmark across the wiki and the planner lands here, grouped by topic with your reading position remembered.",
		"Collections can be shared read-only — coaching a newer squadmate is one link instead of ten.",
	  } },
	{ title = "Account", sub = "Profile, privacy & linked apps", tag = "System", url = "account.lumen.app", icon = ICON.Account,
	  paras = {
		"Manage your display name, avatar crop and the privacy of your match history from a single page.",
		"Linked apps get scoped tokens — the planner can read loadouts without ever seeing chat, and every grant is revocable here.",
	  } },
}

-- ------------------------------------------------------------- spr helpers
-- Pure utilities, independent of any one built instance.
local function stopSet(inst: Instance, prop: string, value: any)
	spr.stop(inst, prop)
	;(inst :: any)[prop] = value
end

type FadeItem = { inst: Instance, prop: string, rest: number }
local function collectFade(root: Instance): { FadeItem }
	local out: { FadeItem } = {}
	local function grab(inst: Instance)
		if inst:IsA("GuiObject") then
			if inst.BackgroundTransparency < 1 then
				table.insert(out, { inst = inst, prop = "BackgroundTransparency", rest = inst.BackgroundTransparency })
			end
			if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
				table.insert(out, { inst = inst, prop = "TextTransparency", rest = (inst :: TextLabel).TextTransparency })
			end
			if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
				table.insert(out, { inst = inst, prop = "ImageTransparency", rest = (inst :: ImageLabel).ImageTransparency })
			end
		elseif inst:IsA("UIStroke") then
			table.insert(out, { inst = inst, prop = "Transparency", rest = inst.Transparency })
		end
		for _, c in inst:GetChildren() do grab(c) end
	end
	grab(root)
	return out
end
local function setHidden(items: { FadeItem })
	for _, it in items do stopSet(it.inst, it.prop, 1) end
end
local function springRest(items: { FadeItem }, d: number, f: number)
	for _, it in items do spr.target(it.inst, d, f, { [it.prop] = it.rest }) end
end
local function springHidden(items: { FadeItem }, d: number, f: number)
	for _, it in items do spr.target(it.inst, d, f, { [it.prop] = 1 }) end
end

-- ============================================================ sub-builders

-- A small rounded hint chip, e.g. "/" or "esc". Reused by the launcher, the
-- search card, and the browser header.
local function createKbd(parent: Instance, size: UDim2, position: UDim2, anchor: Vector2, text: string, textSize: number, zIndex: number?): Frame
	local kbd = Instance.new("Frame")
	kbd.Name = "Kbd"
	kbd.AnchorPoint = anchor
	kbd.Position = position
	kbd.BackgroundColor3 = C_ICONBOX
	kbd.BorderSizePixel = 0
	kbd.Size = size
	if zIndex then kbd.ZIndex = zIndex end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = kbd

	local label = Instance.new("TextLabel")
	label.Name = "TextLabel"
	label.FontFace = fMedium
	label.BackgroundTransparency = 1
	label.TextColor3 = C_KBD_TEXT
	label.BorderSizePixel = 0
	label.Text = text
	label.TextSize = textSize
	label.Size = UDim2.new(1, 0, 1, 0)
	if zIndex then label.ZIndex = zIndex end
	label.Parent = kbd

	kbd.Parent = parent
	return kbd
end

-- The soft drop-shadow image used behind every card/window (same asset,
-- tinted and sized per surface).
local function createShadow(parent: Instance, name: string, color: Color3, transparency: number, anchor: Vector2, position: UDim2, size: UDim2, zIndex: number?, visible: boolean?): ImageLabel
	local shadow = Instance.new("ImageLabel")
	shadow.Name = name
	shadow.ImageColor3 = color
	shadow.Image = ASSET_SHADOW
	shadow.ImageTransparency = transparency
	shadow.AnchorPoint = anchor
	shadow.BackgroundTransparency = 1
	shadow.Position = position
	shadow.BorderSizePixel = 0
	shadow.Size = size
	if zIndex then shadow.ZIndex = zIndex end
	if visible ~= nil then shadow.Visible = visible end
	shadow.Parent = parent
	return shadow
end

local function createLauncher(parent: Instance)
	local holder = Instance.new("Frame")
	holder.Name = "LauncherHolder"
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.new(0.5, 0, 1, -28)
	holder.BorderSizePixel = 0
	holder.Size = UDim2.new(0, 190, 0, 46)
	holder.Parent = parent

	createShadow(holder, "Shadow", Color3.fromHex("B9BDC7"), 0.55, Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, 8), UDim2.new(1.6, 0, 2.6, 0))

	local launcher = Instance.new("TextButton")
	launcher.Name = "Launcher"
	launcher.AnchorPoint = Vector2.new(0.5, 0.5)
	launcher.BackgroundColor3 = Color3.fromHex("FFFFFF")
	launcher.Position = UDim2.new(0.5, 0, 0.5, 0)
	launcher.AutoButtonColor = false
	launcher.Text = ""
	launcher.BorderSizePixel = 0
	launcher.Size = UDim2.new(1, 0, 1, 0)
	launcher.Parent = holder

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = launcher

	local ring = Instance.new("UIStroke")
	ring.Name = "Ring"
	ring.Color = Color3.fromHex("E8E9ED")
	ring.Parent = launcher

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromHex("FFFFFF"), Color3.fromHex("F7F8FA"))
	gradient.Rotation = 90
	gradient.Parent = launcher

	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = launcher

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.ImageColor3 = C_ACCENT
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.ImageRectOffset = Vector2.new(904, 504)
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.new(0, 16, 0.5, 0)
	icon.ImageRectSize = Vector2.new(96, 96)
	icon.Image = ASSET_SEARCH_ICON
	icon.BorderSizePixel = 0
	icon.Size = UDim2.new(0, 18, 0, 18)
	icon.Parent = launcher

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.FontFace = fMedium
	label.TextColor3 = C_BODY
	label.Text = "Search"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Position = UDim2.new(0, 44, 0.5, 0)
	label.BorderSizePixel = 0
	label.TextSize = 14
	label.Size = UDim2.new(0, 70, 0, 18)
	label.Parent = launcher

	createKbd(launcher, UDim2.new(0, 34, 0, 26), UDim2.new(1, -8, 0.5, 0), Vector2.new(1, 0.5), "/", 10)

	return holder, launcher, scale, icon, label
end

local function createSearchCard(parent: Instance)
	local card = Instance.new("Frame")
	card.Name = "SearchCard"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 0.21, 0)
	card.BackgroundColor3 = Color3.fromHex("FFFFFF")
	card.ZIndex = 3
	card.BorderSizePixel = 0
	card.Size = UDim2.new(0, 560, 0, 60)
	card.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = card

	local ring = Instance.new("UIStroke")
	ring.Name = "Ring"
	ring.Color = Color3.fromHex("E8E9ED")
	ring.Thickness = 1.2
	ring.Parent = card

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromHex("FFFFFF"), Color3.fromHex("F8F9FB"))
	gradient.Rotation = 90
	gradient.Parent = card

	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = card

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.ImageColor3 = C_MUTED
	icon.Image = ASSET_SEARCH_ICON
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.ImageRectOffset = Vector2.new(904, 504)
	icon.BackgroundTransparency = 1
	icon.ImageRectSize = Vector2.new(96, 96)
	icon.Position = UDim2.new(0, 22, 0.5, 0)
	icon.ZIndex = 3
	icon.BorderSizePixel = 0
	icon.Size = UDim2.new(0, 20, 0, 20)
	icon.Parent = card

	local input = Instance.new("TextBox")
	input.Name = "Input"
	input.FontFace = fMedium
	input.ClearTextOnFocus = false
	input.TextColor3 = C_TEXT
	input.Position = UDim2.new(0, 58, 0.5, 0)
	input.Text = ""
	input.TextSize = 16
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.AnchorPoint = Vector2.new(0, 0.5)
	input.BackgroundTransparency = 1
	input.PlaceholderColor3 = Color3.fromHex("A6ABB4")
	input.PlaceholderText = "Search apps, docs and people…"
	input.ZIndex = 3
	input.BorderSizePixel = 0
	input.Size = UDim2.new(1, -140, 0, 22)
	input.Parent = card

	createKbd(card, UDim2.new(0, 46, 0, 26), UDim2.new(1, -14, 0.5, 0), Vector2.new(1, 0.5), "esc", 10, 3)

	return card, scale, ring, icon, input
end

local function createResultsRow(parent: Instance): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = "RowTemplate"
	btn.Visible = false
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Position = UDim2.new(0.5, 0, 0, 62)
	btn.BackgroundColor3 = C_ROW_REST
	btn.ZIndex = 4
	btn.BorderSizePixel = 0
	btn.Size = UDim2.new(1, -16, 0, 52)
	btn.Parent = parent

	Instance.new("UICorner").Parent = btn

	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = btn

	local iconBox = Instance.new("Frame")
	iconBox.Name = "IconBox"
	iconBox.AnchorPoint = Vector2.new(0, 0.5)
	iconBox.Position = UDim2.new(0, 8, 0.5, 0)
	iconBox.BackgroundColor3 = C_ICONBOX
	iconBox.ZIndex = 4
	iconBox.BorderSizePixel = 0
	iconBox.Size = UDim2.new(0, 36, 0, 36)
	iconBox.Parent = btn

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 9)
	iconCorner.Parent = iconBox

	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Glyph"
	glyph.ImageColor3 = C_GLYPH
	glyph.BackgroundTransparency = 1
	glyph.Position = UDim2.new(0.5, 0, 0.5, 0)
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.ZIndex = 4
	glyph.BorderSizePixel = 0
	glyph.Size = UDim2.new(0, 18, 0, 18)
	glyph.Parent = iconBox

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.FontFace = fMedium
	title.TextColor3 = C_TEXT
	title.Text = "Title"
	title.Position = UDim2.new(0, 56, 0, 9)
	title.BackgroundTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.BorderSizePixel = 0
	title.ZIndex = 4
	title.TextSize = 14
	title.Size = UDim2.new(1, -200, 0, 17)
	title.Parent = btn

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.FontFace = fReg
	sub.TextColor3 = C_MUTED
	sub.Text = "Sub"
	sub.Position = UDim2.new(0, 56, 0, 27)
	sub.BackgroundTransparency = 1
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.BorderSizePixel = 0
	sub.ZIndex = 4
	sub.TextSize = 12
	sub.Size = UDim2.new(1, -200, 0, 14)
	sub.Parent = btn

	local tag = Instance.new("Frame")
	tag.Name = "Tag"
	tag.AnchorPoint = Vector2.new(1, 0.5)
	tag.Position = UDim2.new(1, -12, 0.5, 0)
	tag.BackgroundColor3 = Color3.fromHex("EEF3FE")
	tag.ZIndex = 4
	tag.BorderSizePixel = 0
	tag.Size = UDim2.new(0, 58, 0, 22)
	tag.Parent = btn

	local tagCorner = Instance.new("UICorner")
	tagCorner.CornerRadius = UDim.new(1, 0)
	tagCorner.Parent = tag

	local tagText = Instance.new("TextLabel")
	tagText.Name = "TagText"
	tagText.FontFace = fSemi
	tagText.TextColor3 = C_ACCENT
	tagText.Text = "Docs"
	tagText.BackgroundTransparency = 1
	tagText.BorderSizePixel = 0
	tagText.ZIndex = 4
	tagText.TextSize = 10
	tagText.Size = UDim2.new(1, 0, 1, 0)
	tagText.Parent = tag

	return btn
end

local function createResultsCard(parent: Instance)
	local card = Instance.new("CanvasGroup")
	card.Name = "ResultsCard"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0.21, 42)
	card.BackgroundColor3 = Color3.fromHex("FFFFFF")
	card.ZIndex = 3
	card.BorderSizePixel = 0
	card.Size = UDim2.new(0, 560, 0, 216)
	card.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card

	local ring = Instance.new("UIStroke")
	ring.Name = "Ring"
	ring.Color = Color3.fromHex("E8E9ED")
	ring.Parent = card

	local section = Instance.new("TextLabel")
	section.Name = "Section"
	section.FontFace = fSemi
	section.TextColor3 = Color3.fromHex("9DA2AB")
	section.Text = "Results"
	section.Position = UDim2.new(0, 16, 0, 12)
	section.BackgroundTransparency = 1
	section.TextXAlignment = Enum.TextXAlignment.Left
	section.BorderSizePixel = 0
	section.ZIndex = 3
	section.TextSize = 11
	section.Size = UDim2.new(0, 200, 0, 14)
	section.Parent = card

	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "Empty"
	emptyLabel.Visible = false
	emptyLabel.FontFace = fReg
	emptyLabel.TextColor3 = Color3.fromHex("A6ABB4")
	emptyLabel.Text = "Nothing matches that — try “docs” or “chat”"
	emptyLabel.AnchorPoint = Vector2.new(0.5, 0)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Position = UDim2.new(0.5, 0, 0, 52)
	emptyLabel.BorderSizePixel = 0
	emptyLabel.ZIndex = 3
	emptyLabel.TextSize = 13
	emptyLabel.Size = UDim2.new(1, -40, 0, 20)
	emptyLabel.Parent = card

	local rowTemplate = createResultsRow(card)

	return card, ring, section, emptyLabel, rowTemplate
end

local function createBrowser(parent: Instance)
	local browser = Instance.new("Frame")
	browser.Name = "Browser"
	browser.Visible = false
	browser.Active = true
	browser.AnchorPoint = Vector2.new(0.5, 0.5)
	browser.BackgroundColor3 = Color3.fromHex("FFFFFF")
	browser.Position = UDim2.new(0.5, 0, 0.5, 0)
	browser.ClipsDescendants = true
	browser.ZIndex = 6
	browser.BorderSizePixel = 0
	browser.Size = UDim2.new(0.62, 0, 0.68, 0)
	browser.Parent = parent

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(620, 400)
	sizeConstraint.MaxSize = Vector2.new(940, 580)
	sizeConstraint.Parent = browser

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = browser

	local ring = Instance.new("UIStroke")
	ring.Name = "Ring"
	ring.Color = Color3.fromHex("E5E6EA")
	ring.Thickness = 1.2
	ring.Parent = browser

	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = browser

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = Color3.fromHex("FFFFFF")
	header.ZIndex = 6
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, 54)
	header.Parent = browser

	local headerGradient = Instance.new("UIGradient")
	headerGradient.Color = ColorSequence.new(Color3.fromHex("FFFFFF"), Color3.fromHex("F8F9FB"))
	headerGradient.Rotation = 90
	headerGradient.Parent = header

	local back = Instance.new("TextButton")
	back.Name = "Back"
	back.BackgroundColor3 = C_ICONBOX
	back.AutoButtonColor = false
	back.BackgroundTransparency = 1
	back.Position = UDim2.new(0, 12, 0, 10)
	back.Text = ""
	back.ZIndex = 7
	back.BorderSizePixel = 0
	back.Size = UDim2.new(0, 34, 0, 34)
	back.Parent = header

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 9)
	backCorner.Parent = back

	local backGlyph = Instance.new("ImageLabel")
	backGlyph.Name = "Glyph"
	backGlyph.ImageColor3 = C_GLYPH
	backGlyph.Image = ASSET_BACK_GLYPH
	backGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
	backGlyph.ImageRectOffset = Vector2.new(504, 804)
	backGlyph.BackgroundTransparency = 1
	backGlyph.ImageRectSize = Vector2.new(96, 96)
	backGlyph.Position = UDim2.new(0.5, 0, 0.5, 0)
	backGlyph.ZIndex = 7
	backGlyph.BorderSizePixel = 0
	backGlyph.Size = UDim2.new(0, 16, 0, 16)
	backGlyph.Parent = back

	local urlPill = Instance.new("Frame")
	urlPill.Name = "UrlPill"
	urlPill.Position = UDim2.new(0, 58, 0, 13)
	urlPill.BackgroundColor3 = C_ICONBOX
	urlPill.ZIndex = 7
	urlPill.BorderSizePixel = 0
	urlPill.Size = UDim2.new(1, -130, 0, 28)
	urlPill.Parent = header

	local urlCorner = Instance.new("UICorner")
	urlCorner.CornerRadius = UDim.new(1, 0)
	urlCorner.Parent = urlPill

	local lockIcon = Instance.new("ImageLabel")
	lockIcon.Name = "LockIcon"
	lockIcon.ImageColor3 = C_MUTED
	lockIcon.Image = ASSET_LOCK
	lockIcon.AnchorPoint = Vector2.new(0, 0.5)
	lockIcon.ImageRectOffset = Vector2.new(4, 104)
	lockIcon.BackgroundTransparency = 1
	lockIcon.ImageRectSize = Vector2.new(96, 96)
	lockIcon.Position = UDim2.new(0, 11, 0.5, 0)
	lockIcon.ZIndex = 7
	lockIcon.BorderSizePixel = 0
	lockIcon.Size = UDim2.new(0, 12, 0, 12)
	lockIcon.Parent = urlPill

	local urlText = Instance.new("TextLabel")
	urlText.Name = "Url"
	urlText.FontFace = fReg
	urlText.TextColor3 = C_GLYPH
	urlText.Text = "lumen.app"
	urlText.Position = UDim2.new(0, 31, 0.5, 0)
	urlText.AnchorPoint = Vector2.new(0, 0.5)
	urlText.BackgroundTransparency = 1
	urlText.TextXAlignment = Enum.TextXAlignment.Left
	urlText.BorderSizePixel = 0
	urlText.ZIndex = 7
	urlText.TextSize = 12
	urlText.Size = UDim2.new(1, -40, 0, 16)
	urlText.Parent = urlPill

	createKbd(header, UDim2.new(0, 46, 0, 26), UDim2.new(1, -14, 0, 14), Vector2.new(1, 0), "esc", 10, 7)

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 14)
	headerCorner.Parent = header

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Position = UDim2.new(0, 0, 0, 54)
	divider.BackgroundColor3 = Color3.fromHex("ECEDEF")
	divider.ZIndex = 7
	divider.BorderSizePixel = 0
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.Parent = browser

	local page = Instance.new("ScrollingFrame")
	page.Name = "Page"
	page.ScrollBarImageColor3 = Color3.fromHex("D6D9DE")
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.ScrollBarThickness = 4
	page.BackgroundTransparency = 1
	page.Position = UDim2.new(0, 0, 0, 55)
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.ZIndex = 6
	page.BorderSizePixel = 0
	page.Size = UDim2.new(1, 0, 1, -55)
	page.Parent = browser

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 30)
	padding.PaddingTop = UDim.new(0, 26)
	padding.PaddingLeft = UDim.new(0, 32)
	padding.PaddingRight = UDim.new(0, 32)
	padding.Parent = page

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 14)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = page

	return browser, scale, ring, back, urlText, header, divider, page
end

-- ==================================================================== API

export type Handles = {
	root: ScreenGui,
	launcherHolder: Frame, launcher: TextButton, launcherScale: UIScale,
	launcherIcon: ImageLabel, launcherLabel: TextLabel,
	overlay: Frame, scrim: TextButton,
	searchShadow: ImageLabel, searchCard: Frame, searchScale: UIScale,
	searchRing: UIStroke, searchIcon: ImageLabel, input: TextBox,
	resultsShadow: ImageLabel,
	browserShadow: ImageLabel, browser: Frame, browserScale: UIScale,
	browserRing: UIStroke, backBtn: TextButton, urlText: TextLabel,
	header: Frame, divider: Frame, page: ScrollingFrame,
	resultsCard: CanvasGroup, resultsRing: UIStroke, section: TextLabel,
	emptyLabel: TextLabel, rowTemplate: TextButton,
}

local Library = {}
Library.animations = {}

--- Builds the whole Lumen UI under `parent` and returns named handles to
--- every element a caller might need (see docs.md "Handles"). Pure
--- construction — no connections, no state, no side effects beyond the new
--- instances. Call `Library.bind(handles)` separately to wire interaction.
function Library.create(parent: Instance): Handles
	local root = Instance.new("ScreenGui")
	root.Name = "Lumen"
	root.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	root.DisplayOrder = 50
	root.ResetOnSpawn = false
	root.IgnoreGuiInset = true
	root.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local launcherHolder, launcher, launcherScale, launcherIcon, launcherLabel = createLauncher(root)

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Parent = root

	local scrim = Instance.new("TextButton")
	scrim.Name = "Scrim"
	scrim.BackgroundTransparency = 0.95
	scrim.BackgroundColor3 = Color3.fromHex("000000")
	scrim.AutoButtonColor = false
	scrim.Text = ""
	scrim.BorderSizePixel = 0
	scrim.Size = UDim2.new(1, 0, 1, 0)
	scrim.Parent = overlay

	local searchShadow = createShadow(overlay, "SearchShadow", Color3.fromHex("B9BDC7"), 0.4, Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.21, 12), UDim2.new(0, 640, 0, 150), 2)

	local searchCard, searchScale, searchRing, searchIcon, input = createSearchCard(overlay)

	local resultsShadow = createShadow(overlay, "ResultsShadow", Color3.fromHex("B9BDC7"), 0.45, Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0.21, 30), UDim2.new(0, 650, 0, 320), 2)

	local browserShadow = createShadow(overlay, "BrowserShadow", Color3.fromHex("AFB4BF"), 0.38, Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, 26), UDim2.new(0.72, 0, 0.82, 0), 5, false)

	local browser, browserScale, browserRing, backBtn, urlText, header, divider, page = createBrowser(overlay)

	local resultsCard, resultsRing, section, emptyLabel, rowTemplate = createResultsCard(overlay)

	-- Structural placeholder: the original's Controller LocalScript is
	-- presence-only for verify_export (its behavior lives in this module's
	-- Library.bind, not in an embedded script). Disabled so a naive drop-in
	-- can never double-run logic.
	local controller = Instance.new("LocalScript")
	controller.Name = "Controller"
	controller.Enabled = false
	controller.Source = "-- Lumen's search/browse interaction and motion are provided by "
		.. "Library.bind(handles) in Library.luau, not by this script. See docs.md."
	controller.Parent = root

	root.Parent = parent

	return {
		root = root,
		launcherHolder = launcherHolder, launcher = launcher, launcherScale = launcherScale,
		launcherIcon = launcherIcon, launcherLabel = launcherLabel,
		overlay = overlay, scrim = scrim,
		searchShadow = searchShadow, searchCard = searchCard, searchScale = searchScale,
		searchRing = searchRing, searchIcon = searchIcon, input = input,
		resultsShadow = resultsShadow,
		browserShadow = browserShadow, browser = browser, browserScale = browserScale,
		browserRing = browserRing, backBtn = backBtn, urlText = urlText,
		header = header, divider = divider, page = page,
		resultsCard = resultsCard, resultsRing = resultsRing, section = section,
		emptyLabel = emptyLabel, rowTemplate = rowTemplate,
	}
end

export type Controller = {
	open: () -> (),
	close: () -> (),
	openBrowser: (entry: Entry) -> (),
	closeBrowser: (refocus: boolean) -> (),
}

--- Wires every interaction and motion the original UI had: launcher
--- hover/press/click, the "/" shortcut, search filtering, keyboard row
--- navigation, opening an entry into the in-UI browser, and Escape closing
--- the topmost layer. Also reproduces the original's runtime-only starting
--- state (overlay hidden, scrim fully transparent) — call this once, after
--- `create()`, before the UI is shown to a player.
function Library.bind(handles: Handles): Controller
	local launcherHolder, launcher, launcherScale = handles.launcherHolder, handles.launcher, handles.launcherScale
	local overlay, scrim = handles.overlay, handles.scrim
	local searchShadow, searchCard, searchScale, searchRing, searchIcon, input =
		handles.searchShadow, handles.searchCard, handles.searchScale, handles.searchRing, handles.searchIcon, handles.input
	local resultsShadow, resultsCard, resultsRing, section, emptyLabel, rowTemplate =
		handles.resultsShadow, handles.resultsCard, handles.resultsRing, handles.section, handles.emptyLabel, handles.rowTemplate
	local browserShadow, browser, browserScale, browserRing, header, divider, backBtn, urlText, page =
		handles.browserShadow, handles.browser, handles.browserScale, handles.browserRing, handles.header, handles.divider, handles.backBtn, handles.urlText, handles.page

	-- ResultsCard is a CanvasGroup; its Ring (a UIStroke on the group itself,
	-- not a descendant) is invisible to GroupTransparency — see the header
	-- note. Every browser-transition fade of the card must go through here so
	-- the ring tracks.
	local function fadeResultsChrome(alpha: number, d: number, f: number)
		spr.target(resultsCard, d, f, { GroupTransparency = alpha })
		spr.target(resultsRing, d, f, { Transparency = alpha })
	end

	-- ---------------------------------------------------------------- blur
	local blur = Instance.new("BlurEffect")
	blur.Name = "LumenBlur"
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = game:GetService("Lighting")

	-- ---------------------------------------------------------------- rows
	type Row = { btn: TextButton, scale: UIScale, iconBox: Frame, glyph: ImageLabel,
		fades: { FadeItem }, entry: Entry, shown: boolean }
	local rows: { Row } = {}
	for i, entry in DATA do
		local btn = rowTemplate:Clone()
		btn.Name = "Row" .. i
		btn.Visible = false
		local iconBox = btn:WaitForChild("IconBox") :: Frame
		local glyph = iconBox:WaitForChild("Glyph") :: ImageLabel
		glyph.Image = entry.icon[1] :: string
		glyph.ImageRectOffset = Vector2.new(entry.icon[2] :: number, entry.icon[3] :: number)
		glyph.ImageRectSize = Vector2.new(entry.icon[4] :: number, entry.icon[4] :: number)
		;(btn:WaitForChild("Title") :: TextLabel).Text = entry.title
		;(btn:WaitForChild("Sub") :: TextLabel).Text = entry.sub
		;((btn:WaitForChild("Tag") :: Frame):WaitForChild("TagText") :: TextLabel).Text = entry.tag
		btn.Parent = resultsCard
		rows[i] = { btn = btn, scale = btn:WaitForChild("Scale") :: UIScale, iconBox = iconBox, glyph = glyph,
			fades = collectFade(btn), entry = entry, shown = false }
	end

	-- ---------------------------------------------------------------- state
	local opened = false
	local browserOpen = false
	local gen = 0          -- results-population generation
	local browserGen = 0   -- browser open/close generation (cancels stale phases)
	local matched: { Row } = {}
	local selectedIndex = 1

	local searchFades = collectFade(searchCard)
	-- Only used when the overlay itself opens/closes; the browser transition fades
	-- the whole card via fadeResultsChrome instead (see the compositing note above).
	local resultsChromeFades = { table.unpack(collectFade(resultsRing)) }
	table.insert(resultsChromeFades, { inst = resultsCard, prop = "BackgroundTransparency", rest = 0 })
	table.insert(resultsChromeFades, { inst = section, prop = "TextTransparency", rest = 0 })

	-- The window is split so the phases can be driven independently:
	--   shell  = the surface that scales/fades as one object (bg, stroke, header band)
	--   chrome = the controls sitting on it (back, url pill, kbd, divider)
	local browserShellFades: { FadeItem } = {
		{ inst = browser, prop = "BackgroundTransparency", rest = browser.BackgroundTransparency },
		{ inst = browserRing, prop = "Transparency", rest = browserRing.Transparency },
		{ inst = header, prop = "BackgroundTransparency", rest = (header :: Frame).BackgroundTransparency },
	}
	local browserChromeFades: { FadeItem } = {}
	for _, item in collectFade(header) do
		if not (item.inst == header and item.prop == "BackgroundTransparency") then
			table.insert(browserChromeFades, item)
		end
	end
	for _, item in collectFade(divider) do table.insert(browserChromeFades, item) end

	local launcherFades = collectFade(launcherHolder)

	local function slotY(i: number): number
		return LIST_TOP + (i - 1) * (ROW_H + ROW_GAP) + ROW_H / 2
	end
	local function cardHeight(n: number): number
		if n == 0 then return LIST_TOP + 52 end
		return LIST_TOP + n * (ROW_H + ROW_GAP) - ROW_GAP + 14
	end

	-- ------------------------------------------------------------ selection
	local function applySelection()
		for i, row in matched do
			local sel = (i == selectedIndex)
			spr.target(row.btn, 1, 8, { BackgroundColor3 = sel and C_ROW_SELECTED or C_ROW_REST })
			spr.target(row.iconBox, 1, 8, { BackgroundColor3 = sel and C_ICONBOX_SEL or C_ICONBOX })
			spr.target(row.glyph, 1, 8, { ImageColor3 = sel and C_ACCENT or C_GLYPH })
		end
	end

	-- ------------------------------------------------------------- populate
	local function filter(q: string): { Row }
		q = string.lower(q)
		local out: { Row } = {}
		for _, row in rows do
			local hay = string.lower(row.entry.title .. " " .. row.entry.sub .. " " .. row.entry.tag)
			if q == "" or string.find(hay, q, 1, true) then
				table.insert(out, row)
				if #out >= MAX_VISIBLE then break end
			end
		end
		return out
	end

	local function populate(q: string, cascade: boolean)
		gen += 1
		local myGen = gen
		matched = filter(q)
		selectedIndex = 1
		section.Text = q == "" and "Quick access" or "Results"

		local inMatch: { [Row]: number } = {}
		for i, row in matched do inMatch[row] = i end

		for _, row in rows do
			local i = inMatch[row]
			if i then
				local target = UDim2.new(0.5, 0, 0, slotY(i))
				row.btn.Visible = true
				if cascade or not row.shown then
					stopSet(row.btn, "Position", UDim2.new(0.5, 0, 0, slotY(i) + 18))
					setHidden(row.fades)
					stopSet(row.scale, "Scale", 0.985)
					task.delay((i - 1) * 0.045, function()
						if gen ~= myGen or not row.btn.Visible then return end
						spr.target(row.btn, 0.82, 4.6, { Position = target })
						spr.target(row.scale, 0.8, 4.5, { Scale = 1 })
						springRest(row.fades, 1, 6)
					end)
				else
					spr.target(row.btn, 0.8, 4.5, { Position = target })
					springRest(row.fades, 1, 6)
				end
				row.shown = true
			elseif row.shown then
				springHidden(row.fades, 1, 7)
				spr.target(row.btn, 0.9, 5, { Position = row.btn.Position + UDim2.fromOffset(0, 10) })
				row.shown = false
				task.delay(0.18, function()
					if gen == myGen and not row.shown then row.btn.Visible = false end
				end)
			end
		end

		local h = cardHeight(#matched)
		spr.target(resultsCard, 0.88, 4.6, { Size = UDim2.fromOffset(560, h) })
		spr.target(resultsShadow, 0.88, 4.6, { Size = UDim2.fromOffset(650, h + 104) })
		emptyLabel.Visible = #matched == 0
		if #matched == 0 then
			stopSet(emptyLabel, "TextTransparency", 1)
			spr.target(emptyLabel, 1, 6, { TextTransparency = 0 })
		end
		applySelection()
	end

	-- ------------------------------------------------------------- page build
	-- Each block is a UIListLayout child holding an `inner` wrapper. The drop
	-- animates `inner.Position` — never the block — because the layout owns block
	-- Position, and a block left on AutomaticSize would resize as its inner moved
	-- and reflow the whole list. Heights are locked after one measure frame so the
	-- layout and AutomaticCanvasSize keep working untouched.
	type PageBlock = { frame: Frame, inner: Frame, fades: { FadeItem } }
	local pageBlocks: { PageBlock } = {}

	local function clearPage()
		for _, c in page:GetChildren() do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		pageBlocks = {}
	end

	local function block(order: number, fixedH: number?): (Frame, Frame)
		local b = Instance.new("Frame")
		b.Name = "Block" .. order
		b.BackgroundTransparency = 1
		b.Size = UDim2.new(1, 0, 0, 0)
		b.AutomaticSize = Enum.AutomaticSize.Y
		b.LayoutOrder = order
		b.Parent = page
		local inner = Instance.new("Frame")
		inner.Name = "Inner"
		inner.BackgroundTransparency = 1
		if fixedH then
			inner.Size = UDim2.new(1, 0, 0, fixedH)
		else
			inner.Size = UDim2.new(1, 0, 0, 0)
			inner.AutomaticSize = Enum.AutomaticSize.Y
		end
		inner.Parent = b
		return b, inner
	end

	local function buildPage(entry: Entry)
		clearPage()
		local blocks: { PageBlock } = {}

		local heroB, hero = block(1, 66)
		local tile = Instance.new("Frame")
		tile.Size = UDim2.fromOffset(56, 56)
		tile.Position = UDim2.fromOffset(0, 4)
		tile.BackgroundColor3 = C_ICONBOX_SEL
		tile.BorderSizePixel = 0
		Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 16)
		local g = Instance.new("ImageLabel")
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		g.Position = UDim2.fromScale(0.5, 0.5)
		g.Size = UDim2.fromOffset(26, 26)
		g.BackgroundTransparency = 1
		g.Image = entry.icon[1] :: string
		g.ImageRectOffset = Vector2.new(entry.icon[2] :: number, entry.icon[3] :: number)
		g.ImageRectSize = Vector2.new(entry.icon[4] :: number, entry.icon[4] :: number)
		g.ImageColor3 = C_ACCENT
		g.Parent = tile
		tile.Parent = hero
		local h1 = Instance.new("TextLabel")
		h1.BackgroundTransparency = 1
		h1.Position = UDim2.fromOffset(74, 6)
		h1.Size = UDim2.new(1, -74, 0, 28)
		h1.Text = entry.title
		h1.TextXAlignment = Enum.TextXAlignment.Left
		h1.TextSize = 23
		h1.TextColor3 = C_TEXT
		h1.FontFace = fSemi
		h1.Parent = hero
		local meta = Instance.new("TextLabel")
		meta.BackgroundTransparency = 1
		meta.Position = UDim2.fromOffset(74, 38)
		meta.Size = UDim2.new(1, -74, 0, 16)
		meta.Text = entry.tag .. "  ·  " .. entry.url
		meta.TextXAlignment = Enum.TextXAlignment.Left
		meta.TextSize = 12
		meta.TextColor3 = C_MUTED
		meta.FontFace = fReg
		meta.Parent = hero
		table.insert(blocks, { frame = heroB, inner = hero, fades = collectFade(hero) })

		local dvB, dv = block(2, 1)
		dv.BackgroundTransparency = 0
		dv.BackgroundColor3 = Color3.fromHex("EEEFF2")
		table.insert(blocks, { frame = dvB, inner = dv, fades = collectFade(dv) })

		for pi, text in entry.paras do
			local pB, p = block(2 + pi)
			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.Size = UDim2.new(1, 0, 0, 0)
			lbl.AutomaticSize = Enum.AutomaticSize.Y
			lbl.Text = text
			lbl.TextWrapped = true
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.TextYAlignment = Enum.TextYAlignment.Top
			lbl.TextSize = 14
			lbl.LineHeight = 1.45
			lbl.TextColor3 = C_BODY
			lbl.FontFace = fReg
			lbl.Parent = p
			table.insert(blocks, { frame = pB, inner = p, fades = collectFade(p) })
		end

		local galB, gal = block(10, 104)
		local tints = { { "EEF3FE", "DFEAFC" }, { "F2F4F8", "E7EAF0" }, { "F7F8FA", "ECEEF2" } }
		for t = 1, 3 do
			local tileF = Instance.new("Frame")
			tileF.Size = UDim2.new(1 / 3, -10, 1, 0)
			tileF.Position = UDim2.new((t - 1) / 3, t > 1 and 5 or 0, 0, 0)
			tileF.BackgroundColor3 = Color3.fromHex("FFFFFF")
			tileF.BorderSizePixel = 0
			Instance.new("UICorner", tileF).CornerRadius = UDim.new(0, 10)
			local grad = Instance.new("UIGradient")
			grad.Rotation = 90
			grad.Color = ColorSequence.new(Color3.fromHex(tints[t][1]), Color3.fromHex(tints[t][2]))
			grad.Parent = tileF
			local st = Instance.new("UIStroke")
			st.Color = Color3.fromHex("E8E9ED")
			st.Transparency = 0.4
			st.Parent = tileF
			tileF.Parent = gal
		end
		table.insert(blocks, { frame = galB, inner = gal, fades = collectFade(gal) })

		local ftB, ft = block(11, 20)
		local link = Instance.new("TextLabel")
		link.BackgroundTransparency = 1
		link.Size = UDim2.new(1, 0, 1, 0)
		link.Text = "Read more on " .. entry.url .. "  →"
		link.TextXAlignment = Enum.TextXAlignment.Left
		link.TextSize = 13
		link.TextColor3 = C_ACCENT
		link.FontFace = fMedium
		link.Parent = ft
		table.insert(blocks, { frame = ftB, inner = ft, fades = collectFade(ft) })

		pageBlocks = blocks
		for _, b in blocks do setHidden(b.fades) end
	end

	local function lockBlockHeights()
		for _, b in pageBlocks do
			local h = b.inner.AbsoluteSize.Y
			if h > 0 then
				b.inner.AutomaticSize = Enum.AutomaticSize.None
				b.inner.Size = UDim2.new(1, 0, 0, h)
				b.frame.AutomaticSize = Enum.AutomaticSize.None
				b.frame.Size = UDim2.new(1, 0, 0, h)
			end
		end
	end

	-- ------------------------------------------------------------- browser
	local openOverlay: () -> ()
	local closeOverlay: () -> ()
	local openBrowser: (entry: Entry) -> ()
	local closeBrowser: (refocus: boolean) -> ()

	function openBrowser(entry: Entry)
		if browserOpen then return end
		browserOpen = true
		browserGen += 1
		local myGen = browserGen
		input:ReleaseFocus()
		urlText.Text = entry.url .. "/" .. string.lower(string.gsub(entry.title, "%s+", "-"))

		-- PHASE 0 — search column leaves fast. It must be gone before the window
		-- fades in, or its rows show through the still-translucent window.
		springHidden(searchFades, 1, 9)
		-- one composited fade for card + rows together — fading them separately makes
		-- the white card look like it vanishes out from under the white rows
		fadeResultsChrome(1, 1, 9)
		spr.target(searchShadow, 1, 9, { ImageTransparency = 1 })
		spr.target(resultsShadow, 1, 9, { ImageTransparency = 1 })
		spr.target(searchScale, 1, 6, { Scale = 0.97 })

		buildPage(entry)          -- built hidden; browser is still Visible=false
		page.CanvasPosition = Vector2.zero

		task.spawn(function()
			-- Layout/AbsoluteSize is computed even while Visible=false, so text can
			-- wrap and be measured before anything is shown.
			game:GetService("RunService").Heartbeat:Wait()
			if browserGen ~= myGen then return end
			lockBlockHeights()
			for _, b in pageBlocks do
				stopSet(b.inner, "Position", UDim2.fromOffset(0, -CONTENT_DROP))
			end

			-- PHASE 1 — window scales out from its centre + fades in, still empty
			task.wait(OPEN_WINDOW_AT)
			if browserGen ~= myGen then return end
			browser.Visible = true
			browserShadow.Visible = true
			stopSet(browserScale, "Scale", OPEN_SCALE)
			setHidden(browserShellFades)
			setHidden(browserChromeFades)
			stopSet(browserShadow, "ImageTransparency", 1)
			spr.target(browserScale, 0.78, 4.4, { Scale = 1 })
			springRest(browserShellFades, 1, 5.5)
			spr.target(browserShadow, 1, 5, { ImageTransparency = 0.38 })

			-- PHASE 2 — the elements inside arrive: fade in + drop down, staggered.
			-- Starts while the shell is still finishing its spring (not after it
			-- fully settles) so content reads as arriving the moment the window
			-- looks visible and roughly its final size, not as a separate later beat.
			task.wait(OPEN_CONTENT_AT)
			if browserGen ~= myGen then return end
			springRest(browserChromeFades, 1, 6)
			for i, b in pageBlocks do
				task.delay((i - 1) * CONTENT_STAGGER, function()
					if browserGen ~= myGen then return end
					spr.target(b.inner, 0.65, 4.5, { Position = UDim2.fromOffset(0, 0) })
					springRest(b.fades, 1, 6)
				end)
			end
		end)
	end

	function closeBrowser(refocus: boolean)
		if not browserOpen then return end
		browserOpen = false
		browserGen += 1
		local myGen = browserGen

		-- PHASE 1 — everything inside goes first, all at once
		for _, b in pageBlocks do springHidden(b.fades, 1, 9) end
		springHidden(browserChromeFades, 1, 9)
		-- the Back button's fill is transparent at rest and only lit by hover, so it
		-- isn't in the chrome set; force it out or it lingers as a white square
		spr.target(backBtn, 1, 9, { BackgroundTransparency = 1 })

		-- PHASE 2 — the window shrinks toward its centre while fading. The scale is
		-- deliberately FASTER than the fade: if the fade leads, the window is already
		-- invisible before it has visibly moved and the shrink reads as a snap.
		task.delay(CLOSE_SHELL_AT, function()
			if browserGen ~= myGen then return end
			spr.target(browserScale, 1, 6, { Scale = CLOSE_SCALE })
			springHidden(browserShellFades, 1, 4.5)
			spr.target(browserShadow, 1, 4.5, { ImageTransparency = 1 })
		end)

		-- PHASE 3 — search column returns once the window has mostly cleared
		task.delay(CLOSE_SEARCH_AT, function()
			if browserGen ~= myGen or browserOpen or not opened then return end
			springRest(searchFades, 1, 5)
			fadeResultsChrome(0, 1, 5)
			spr.target(searchShadow, 1, 5, { ImageTransparency = 0.4 })
			spr.target(resultsShadow, 1, 5, { ImageTransparency = 0.45 })
			spr.target(searchScale, 0.75, 4.4, { Scale = 1 })
			applySelection()
			if refocus then
				task.delay(0.05, function()
					if opened and not browserOpen then input:CaptureFocus() end
				end)
			end
		end)

		task.delay(CLOSE_HIDE_AT, function()
			if browserGen ~= myGen or browserOpen then return end
			browser.Visible = false
			browserShadow.Visible = false
			clearPage()
		end)
	end

	-- ---------------------------------------------------------- open / close
	local ESCAPE_ACTION = "LumenEscapeOverride"
	local ContextActionService = game:GetService("ContextActionService")

	-- Roblox's own Escape-to-menu binding fires alongside a raw UserInputService
	-- listener, so Escape is bound through ContextActionService above the core
	-- scripts' priority and Sink-ed — that is what stops the menu also opening.
	local function onEscapeAction(_name: string, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			if browserOpen then closeBrowser(true)
			elseif opened then closeOverlay() end
		end
		return Enum.ContextActionResult.Sink
	end
	local function bindEscapeOverride()
		ContextActionService:BindActionAtPriority(ESCAPE_ACTION, onEscapeAction, false,
			Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.Escape)
	end
	local function unbindEscapeOverride()
		ContextActionService:UnbindAction(ESCAPE_ACTION)
	end

	function openOverlay()
		if opened then return end
		opened = true
		bindEscapeOverride()
		gen += 1
		overlay.Visible = true

		blur.Enabled = true
		stopSet(blur, "Size", 0)
		spr.target(blur, 1, 4, { Size = 16 })
		stopSet(scrim, "BackgroundTransparency", 1)
		spr.target(scrim, 1, 5, { BackgroundTransparency = SCRIM_REST })

		springHidden(launcherFades, 1, 7)

		input.Text = ""
		stopSet(searchScale, "Scale", 0.92)
		stopSet(searchCard, "Position", UDim2.new(0.5, 0, 0.21, -18))
		setHidden(searchFades)
		stopSet(searchShadow, "ImageTransparency", 1)
		spr.target(searchScale, 0.72, 4.4, { Scale = 1 })
		spr.target(searchCard, 0.78, 4.2, { Position = UDim2.new(0.5, 0, 0.21, 0) })
		springRest(searchFades, 1, 6)
		spr.target(searchShadow, 1, 5, { ImageTransparency = 0.4 })

		for _, row in rows do
			row.shown = false
			row.btn.Visible = false
		end
		stopSet(resultsCard, "GroupTransparency", 0)  -- group visible; chrome fades in below
		stopSet(resultsCard, "Size", UDim2.fromOffset(560, cardHeight(0)))
		for _, it in resultsChromeFades do
			stopSet(it.inst, it.prop, 1)
			spr.target(it.inst, 1, 6, { [it.prop] = it.rest })
		end
		stopSet(resultsShadow, "ImageTransparency", 1)
		spr.target(resultsShadow, 1, 5, { ImageTransparency = 0.45 })
		populate("", true)

		task.delay(0.08, function()
			if opened and not browserOpen then input:CaptureFocus() end
		end)
	end

	function closeOverlay()
		if not opened then return end
		opened = false
		unbindEscapeOverride()
		gen += 1
		browserGen += 1
		local myGen = browserGen
		input:ReleaseFocus()

		-- everything is leaving together here, so the browser exits in one pass
		if browserOpen then
			browserOpen = false
			for _, b in pageBlocks do springHidden(b.fades, 1, 9) end
			springHidden(browserChromeFades, 1, 9)
			spr.target(backBtn, 1, 9, { BackgroundTransparency = 1 })
			spr.target(browserScale, 1, 5.5, { Scale = CLOSE_SCALE })
			springHidden(browserShellFades, 1, 5)
			spr.target(browserShadow, 1, 5, { ImageTransparency = 1 })
		end

		spr.target(blur, 1, 4.5, { Size = 0 })
		spr.target(scrim, 1, 6, { BackgroundTransparency = 1 })
		spr.target(searchScale, 1, 5, { Scale = 0.95 })
		springHidden(searchFades, 1, 6)
		fadeResultsChrome(1, 1, 6)
		spr.target(searchShadow, 1, 6, { ImageTransparency = 1 })
		spr.target(resultsShadow, 1, 6, { ImageTransparency = 1 })
		springRest(launcherFades, 1, 5)

		task.delay(0.40, function()
			if not opened and browserGen == myGen then
				overlay.Visible = false
				browser.Visible = false
				browserShadow.Visible = false
				blur.Enabled = false
				clearPage()
				for _, row in rows do
					row.btn.Visible = false
					row.shown = false
				end
			end
		end)
	end

	-- ---------------------------------------------------------------- wiring
	launcher.MouseButton1Click:Connect(openOverlay)
	launcher.MouseEnter:Connect(function() spr.target(launcherScale, 0.7, 4, { Scale = 1.04 }) end)
	launcher.MouseLeave:Connect(function() spr.target(launcherScale, 0.7, 4, { Scale = 1 }) end)
	launcher.MouseButton1Down:Connect(function()
		stopSet(launcherScale, "Scale", 0.96)
		spr.target(launcherScale, 0.6, 5, { Scale = 1 })
	end)

	scrim.MouseButton1Click:Connect(function()
		if browserOpen then closeBrowser(true) else closeOverlay() end
	end)

	backBtn.MouseButton1Click:Connect(function() closeBrowser(true) end)
	backBtn.MouseEnter:Connect(function()
		if browserOpen then spr.target(backBtn, 1, 7, { BackgroundTransparency = 0 }) end
	end)
	backBtn.MouseLeave:Connect(function() spr.target(backBtn, 1, 7, { BackgroundTransparency = 1 }) end)

	for _, row in rows do
		row.btn.MouseEnter:Connect(function()
			if browserOpen then return end
			local idx = table.find(matched, row)
			if idx ~= selectedIndex then spr.target(row.btn, 1, 8, { BackgroundColor3 = C_ROW_HOVER }) end
		end)
		row.btn.MouseLeave:Connect(function()
			if not browserOpen then applySelection() end
		end)
		row.btn.MouseButton1Down:Connect(function()
			stopSet(row.scale, "Scale", 0.975)
			spr.target(row.scale, 0.6, 5, { Scale = 1 })
		end)
		row.btn.MouseButton1Click:Connect(function()
			if browserOpen then return end
			local idx = table.find(matched, row)
			if idx then selectedIndex = idx; applySelection() end
			openBrowser(row.entry)
		end)
	end

	input:GetPropertyChangedSignal("Text"):Connect(function()
		if opened and not browserOpen then populate(input.Text, false) end
	end)
	input.Focused:Connect(function()
		spr.target(searchIcon, 1, 6, { ImageColor3 = C_ACCENT })
		spr.target(searchRing, 1, 6, { Color = Color3.fromHex("C7D9FD") })
	end)
	input.FocusLost:Connect(function(enterPressed)
		spr.target(searchIcon, 1, 6, { ImageColor3 = C_MUTED })
		spr.target(searchRing, 1, 6, { Color = Color3.fromHex("E8E9ED") })
		if enterPressed and opened and not browserOpen and matched[selectedIndex] then
			openBrowser(matched[selectedIndex].entry)
		end
	end)

	-- "/" opens Lumen (Slack/Discord/GitHub convention) when no textbox is focused.
	game:GetService("UserInputService").InputBegan:Connect(function(io, _gp)
		if io.KeyCode == Enum.KeyCode.Slash then
			if not opened and game:GetService("UserInputService"):GetFocusedTextBox() == nil then openOverlay() end
			return
		end
		if not opened or browserOpen then return end
		if io.KeyCode == Enum.KeyCode.Down and #matched > 0 then
			selectedIndex = math.min(selectedIndex + 1, #matched)
			applySelection()
		elseif io.KeyCode == Enum.KeyCode.Up and #matched > 0 then
			selectedIndex = math.max(selectedIndex - 1, 1)
			applySelection()
		end
	end)

	-- initial state: closed (mirrors the original script's runtime-only start;
	-- the built tree above is edit-time-static and stays fully opaque/visible).
	overlay.Visible = false
	scrim.BackgroundTransparency = 1

	return {
		open = openOverlay,
		close = closeOverlay,
		openBrowser = openBrowser,
		closeBrowser = closeBrowser,
	}
end

return Library
