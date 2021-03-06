---
--- Generated by Luanalysis
--- Created by lyrthras.
--- DateTime: 24/08/2021 9:13 PM
---

--- Thrown items
---@class ThrownItem : Item
---@field windupTime number
---@field cooldown number

local base = require "readers.item".read

local function read(path, json)
  ---@type ThrownItem
  local item = base(path, json)

  item.windupTime = json.windupTime
  item.cooldown = json.cooldown

  return item
end

return {read = read}
