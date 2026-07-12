local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.color_scheme = "rose-pine-moon"
config.font = wezterm.font("Hack Nerd Font")
config.font_size = 15.0
config.window_background_opacity = 0.8
config.macos_window_background_blur = 50
config.inactive_pane_hsb = {
  saturation = 0.9,
  brightness = 0.62,
}
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"

config.keys = {
  { key = "UpArrow", mods = "SHIFT", action = wezterm.action.ScrollByLine(-1) },
  { key = "DownArrow", mods = "SHIFT", action = wezterm.action.ScrollByLine(1) },
  -- Cmd+D: split right | Cmd+Shift+D: split bottom
  { key = "d", mods = "CMD", action = wezterm.action.SplitHorizontal { domain = "CurrentPaneDomain" } },
  { key = "d", mods = "CMD|SHIFT", action = wezterm.action.SplitVertical { domain = "CurrentPaneDomain" } },
  -- Cmd+W: close pane; if only one pane left, closes the tab
  { key = "w", mods = "CMD", action = wezterm.action.CloseCurrentPane { confirm = false } },
  { key = "LeftArrow", mods = "CMD|SHIFT", action = wezterm.action.ActivatePaneDirection "Left" },
  { key = "RightArrow", mods = "CMD|SHIFT", action = wezterm.action.ActivatePaneDirection "Right" },
  { key = "UpArrow", mods = "CMD|SHIFT", action = wezterm.action.ActivatePaneDirection "Up" },
  { key = "DownArrow", mods = "CMD|SHIFT", action = wezterm.action.ActivatePaneDirection "Down" },
}

return config
