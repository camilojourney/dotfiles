-- Compatibility shim. Some obsidian.nvim builds require
-- `obsidian.picker._snacks` while the shipped file is `snacks.lua`.
return require('obsidian.picker.snacks')
