# Lumen

A spotlight-search launcher with an in-UI browser overlay: a small floating
"Search" button opens a centered search card (filter-as-you-type over a demo
result list), and picking a result opens a full in-window "browser" panel
with a header, back button, and a scrollable content page — all built from
plain `Frame`/`TextButton`/`ScrollingFrame` instances and animated with
[spr](https://github.com/Fraktality/spr) springs. Zero external
dependencies once installed.

This library was exported from a UI built in Roblox Studio with
[Plopacle](https://www.npmjs.com/package/plopacle-mcp) (`ui-fb2efa`,
internal slug `lumen`). It has no dependency on Plopacle at runtime — drop
the folder into any place and it works.

## Install

**Studio (paste):**

1. Create a `Folder` (or `ModuleScript` container) anywhere reachable by
   client code — `ReplicatedStorage` is a good default.
2. Create two `ModuleScript`s inside it named `Library` and `spr`, and paste
   in `Library.luau` and `spr.luau` respectively.
3. Put `Example.client.luau` as a `LocalScript` under `StarterPlayerScripts`
   (or wherever your client entry points live), and point its `require` at
   wherever you put `Library` in step 2.

**Rojo:**

```
ReplicatedStorage/
  Lumen/
    init.luau        -- rename Library.luau to init.luau, or reference it directly
    spr.luau
StarterPlayer/
  StarterPlayerScripts/
    LumenExample.client.luau   -- Example.client.luau
```

`Library.luau` requires `spr` **relatively** (`require(script.Parent.spr)`),
so the two files must stay siblings in the same folder — no
`ReplicatedStorage/Plopacle` assumption anywhere.

## Quick start

```lua
local Library = require(path.to.Library)

local handles = Library.create(playerGui)   -- builds the UI, returns named refs
local controller = Library.bind(handles)     -- wires interaction + motion

-- that's it — the launcher button in the bottom-center is now live.
-- Optionally trigger it yourself:
controller.open()
```

## API reference

### `Library.create(parent: Instance): Handles`

Builds the entire Lumen UI (launcher button, search overlay, results list,
in-UI browser) under `parent` as a single `ScreenGui` named `"Lumen"`, and
returns a table of named references to every element a caller is likely to
need (see **Handles** below). Pure construction: no event connections, no
running state, no side effects — safe to call at `require` time or any
time after.

### `Library.bind(handles: Handles): Controller`

Wires every interaction the original UI had — launcher hover/press/click,
the `/` keyboard shortcut, live search filtering, ↑/↓ row navigation,
opening a result into the browser panel, `Esc` closing the topmost open
layer — and reproduces the UI's actual runtime starting state (overlay
hidden, background scrim fully transparent; the *built* tree from
`create()` is edit-time-static and starts fully opaque/visible, matching
what you'd see in Studio). Call once, right after `create()`, before
showing the UI to the player. Returns a small `Controller` table for
programmatic control:

```lua
type Controller = {
	open: () -> (),                          -- opens the search overlay
	close: () -> (),                         -- closes it (and the browser, if open)
	openBrowser: (entry: Entry) -> (),       -- opens the browser panel on a given entry
	closeBrowser: (refocus: boolean) -> (),  -- closes the browser panel back to search
}
```

`Entry` is `{ title: string, sub: string, tag: string, url: string, icon: {string | number}, paras: {string} }`
— see **Customization points** for the demo `DATA` table this drives.

## Handles

The table `Library.create` returns:

| Key | Points at |
|---|---|
| `root` | The `ScreenGui` |
| `launcherHolder`, `launcher`, `launcherScale`, `launcherIcon`, `launcherLabel` | The bottom-center "Search" pill button and its parts |
| `overlay`, `scrim` | The full-screen layer that opens over everything, and its dimming click-catcher |
| `searchShadow`, `searchCard`, `searchScale`, `searchRing`, `searchIcon`, `input` | The centered search card and its drop shadow |
| `resultsShadow`, `resultsCard`, `resultsRing`, `section`, `emptyLabel`, `rowTemplate` | The results list card below the search card (`rowTemplate` is the hidden template `bind()` clones per data entry) |
| `browserShadow`, `browser`, `browserScale`, `browserRing`, `header`, `divider`, `backBtn`, `urlText`, `page` | The in-UI "browser" panel opened when a result is picked |

## Animations

All motion is spring-driven (spr, damping/frequency pairs — no TweenService).
This UI predates Plopacle's TUNING convention, so the values are fixed
constants inside `Library.bind`, not an overridable table; to change the
feel, edit the constants block at the top of `Library.luau` (`SCRIM_REST`,
`OPEN_SCALE`, `CLOSE_SCALE`, the `OPEN_*`/`CLOSE_*` timing offsets, and the
per-call `spr.target(inst, damping, frequency, {...})` values throughout
`Library.bind`).

- **Launcher hover/press** — a `UIScale` bump on mouse enter/leave/down.
- **Open/close overlay** (`controller.open()` / `controller.close()`) —
  blur ramps in on `Lighting`, the scrim fades to 42% opacity, the launcher
  fades out, and the search card springs up with its results list, all in
  one phased sequence documented at the top of `Library.luau` under "MOTION
  CONTRACT".
- **Open/close browser** (`controller.openBrowser(entry)` /
  `controller.closeBrowser(refocus)`) — a strictly-phased sequence: the
  search column leaves fast, the browser window scales out from its
  center and fades in, then its content blocks fade in and drop down
  8px each, staggered. Closing reverses the phases. See the same "MOTION
  CONTRACT" comment for why the phases can't overlap (translucency
  compositing artifacts if they do).
- **Row hover/selection** — background/icon-tint springs driven by
  `applySelection()` inside `Library.bind`.
- **Result list reflow** — as the search text changes, matching rows
  spring into their new slot position (staggered on first appearance,
  immediate on subsequent filters); non-matching rows fade and slide out.

## Customization points

- **Replace the demo content**: the `DATA: {Entry}` table and `ICON` asset
  table near the top of `Library.luau` are the whole "app". Swap in your
  own entries — each just needs `title`, `sub`, `tag`, `url`, an `icon`
  (`{assetId, rectOffsetX, rectOffsetY, rectSize}`), and `paras` (the
  browser page's body paragraphs).
- **Reuse the sub-builders directly**: `createKbd`, `createShadow`,
  `createLauncher`, `createSearchCard`, `createResultsRow`,
  `createResultsCard`, and `createBrowser` are local functions in
  `Library.luau` — copy the ones you want into your own module if you only
  need, say, the search card without the browser.
- **Safe prop overrides after `create()`**: anything not driven by
  `Library.bind`'s springs is safe to set directly on the returned
  `Handles` — e.g. `handles.launcherLabel.Text = "Find"`,
  `handles.root.DisplayOrder = 10`, or re-parenting `handles.root`.
- **The embedded `Controller` LocalScript** under the built `ScreenGui` is
  a disabled structural placeholder only (it exists so tooling that expects
  the original's script layout still finds a same-named node) — the real
  behavior lives entirely in `Library.bind`. Deleting the placeholder
  instance after `create()` is safe if you don't need it.
