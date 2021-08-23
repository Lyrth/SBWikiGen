---
--- Generated by Luanalysis
--- Created by lyrthras.
--- DateTime: 24/08/2021 4:06 AM
---

--- Codices
---@class Codex : Item
---@field race string
---@field pages string[]

local base = require "readers.item".read

local function read(path, json)
  ---@type Codex
  local item = base(path, json)

  item.race = json.species
  item.pages = json.contentPages

  item.rarity = item.rarity or json.itemConfig.rarity
  item.price = item.price or json.itemConfig.price

  return item
end

return {read = read}
