local wezterm = require("wezterm")

local config = wezterm.config_builder()

-- Rose Pine Moon accents for the tab bar
local colors = {
  base = "#232136",
  overlay = "#393552",
  muted = "#6e6a86",
  text = "#e0def4",
  pine = "#3e8fb0",
  foam = "#9ccfd8",
  iris = "#c4a7e7",
}

config.color_scheme = "rose-pine-moon"
config.font = wezterm.font("Hack Nerd Font")
config.font_size = 15.0
config.window_background_opacity = 0.8
config.macos_window_background_blur = 50
config.inactive_pane_hsb = {
  saturation = 0.9,
  brightness = 0.62,
}
config.window_decorations = "RESIZE"

-- Always show a taller top tab bar with roomy tabs.
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
config.show_new_tab_button_in_tab_bar = true
config.window_frame = {
  font = wezterm.font({ family = "Hack Nerd Font", weight = "Bold" }),
  font_size = 18.0,
  active_titlebar_bg = colors.base,
  inactive_titlebar_bg = colors.base,
}
config.colors = {
  tab_bar = {
    background = colors.base,
    active_tab = {
      bg_color = colors.pine,
      fg_color = colors.base,
      intensity = "Bold",
    },
    inactive_tab = {
      bg_color = colors.overlay,
      fg_color = colors.muted,
    },
    inactive_tab_hover = {
      bg_color = colors.iris,
      fg_color = colors.base,
    },
    new_tab = {
      bg_color = colors.base,
      fg_color = colors.foam,
    },
    new_tab_hover = {
      bg_color = colors.foam,
      fg_color = colors.base,
    },
  },
}

wezterm.on("format-tab-title", function(tab, tabs, panes, conf, hover, max_width)
  local title = tab.tab_title
  if not title or #title == 0 then
    title = tab.active_pane.title
  end
  -- Extra padding so tabs read as bigger pills.
  local index = tab.tab_index + 1
  local label = string.format("  %d: %s  ", index, title)
  return {
    { Text = wezterm.truncate_right(label, math.max(max_width, 24)) },
  }
end)

-- Let the pane app (Herdr) receive modified arrow keys.
config.enable_kitty_keyboard = true

config.keys = {
  { key = "UpArrow", mods = "SHIFT", action = wezterm.action.ScrollByLine(-1) },
  { key = "DownArrow", mods = "SHIFT", action = wezterm.action.ScrollByLine(1) },
  -- Do not make Cmd+D a second shortcut language. Learn Herdr's default
  -- prefix model instead: Ctrl+B % splits left/right, Ctrl+B " splits top/bottom.
  { key = "d", mods = "CMD", action = wezterm.action.DisableDefaultAssignment },
  { key = "D", mods = "CMD", action = wezterm.action.DisableDefaultAssignment },
}

return config
