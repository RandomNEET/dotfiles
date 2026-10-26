local wezterm = require("wezterm")
local config = {}

config.default_prog = { "nu.exe" }
config.font = wezterm.font("JetBrainsMono Nerd Font Mono")
config.color_scheme = "catppuccin-mocha"

return config
