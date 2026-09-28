local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.color_scheme = "rose-pine-moon"

-- Copy-mode selection highlight, matched to herdr's default (catppuccin)
-- selection colors so both tools look the same when selecting text.
config.colors = {
  selection_fg = "#cdd6f4", -- catppuccin mocha "text"
  selection_bg = "#313244", -- catppuccin mocha "surface0"
}

config.font = wezterm.font("Hack Nerd Font")

-- I keep this terminal 100% keyboard driven by disabling mouse actions.
-- Select everything in the pane. This WezTerm version has no SelectAll action,
-- so Ctrl+Shift+A jumps to the top of the scrollback in copy mode; then press
-- Space -> G -> y to select everything and copy. Plain Ctrl+A stays free for the
-- shell (start of line).
-- Ctrl+Shift+Up/Down reverts to WezTerm's default: moving between panes.
config.keys = {
  { key = 'A', mods = 'CTRL|SHIFT', action = wezterm.action.Multiple{
    wezterm.action.ActivateCopyMode,
    wezterm.action.CopyMode('MoveToScrollbackTop'),
  } },
  -- Cmd+D creates a side-by-side pane (a vertical divider); Cmd+Shift+D
  -- creates a stacked pane.
  { key = 'd', mods = 'CMD', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'd', mods = 'CMD|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
}

-- Scroll in copy mode: Shift+[ moves up, Shift+] moves down, 3 lines per
-- press. 1 line felt uncontrollable when held, since the OS key-repeat rate
-- (KeyRepeat in nix/configuration.nix) is very fast; 3 lines per repeat
-- event is a calmer step while still covering ground quickly when held.
-- These live in the copy_mode key table (not config.keys) so Shift+[/] only
-- do this while copy mode is already active - previously they were global and
-- swallowed every literal {/[/]/} keystroke typed in the normal shell too.
local copy_mode = wezterm.gui.default_key_tables().copy_mode
table.insert(copy_mode, { key = '{', mods = 'SHIFT', action = wezterm.action.Multiple({
  wezterm.action.CopyMode('MoveUp'),
  wezterm.action.CopyMode('MoveUp'),
  wezterm.action.CopyMode('MoveUp'),
}) })
table.insert(copy_mode, { key = '}', mods = 'SHIFT', action = wezterm.action.Multiple({
  wezterm.action.CopyMode('MoveDown'),
  wezterm.action.CopyMode('MoveDown'),
  wezterm.action.CopyMode('MoveDown'),
}) })
config.key_tables = { copy_mode = copy_mode }
config.font_size = 15.0
config.window_background_opacity = 0.8
config.macos_window_background_blur = 50

-- Make the active pane stand out when a window contains many panels. WezTerm
-- applies these HSB multipliers only to panes that do not have focus.
config.inactive_pane_hsb = {
  saturation = 0.82,
  brightness = 0.72,
}

config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"

-- Dim unfocused windows so the focused one is obvious at a glance.
local UNFOCUSED_FOREGROUND_TEXT_HSB = { hue = 1.0, saturation = 0.25, brightness = 0.45 }
local UNFOCUSED_WINDOW_BACKGROUND_OPACITY = 0.62

-- get_config_overrides() hands back a copy, so the current value is never the
-- same table we last stored; compare the fields instead of the identity.
local function same_text_hsb(actual, expected)
	if actual == nil or expected == nil then
		return actual == expected
	end
	return actual.hue == expected.hue
		and actual.saturation == expected.saturation
		and actual.brightness == expected.brightness
end

wezterm.on("window-focus-changed", function(window)
	local overrides = window:get_config_overrides() or {}
	local text_hsb, opacity
	if not window:is_focused() then
		text_hsb = UNFOCUSED_FOREGROUND_TEXT_HSB
		opacity = UNFOCUSED_WINDOW_BACKGROUND_OPACITY
	end

	-- Only write when one of the two values we own actually changes; a redundant
	-- set_config_overrides() call would trigger another config reload.
	if same_text_hsb(overrides.foreground_text_hsb, text_hsb) and overrides.window_background_opacity == opacity then
		return
	end

	overrides.foreground_text_hsb = text_hsb
	overrides.window_background_opacity = opacity
	window:set_config_overrides(overrides)
end)

return config
