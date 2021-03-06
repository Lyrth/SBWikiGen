---
--- Generated by Luanalysis
--- Created by lyrthras.
--- DateTime: 02/10/2021 4:25 PM
---

--- Status effects. Mainly used for effects that show up to the player
---@class StatusEffect : DbEntry
---@field name string|nil
---@field icon string|nil
---@field duration number|nil
---@field blockedBy string|nil  @ stat name (id) that blocks this effect

local function read(path, json)
  ---@type StatusEffect
  local effect = {
    id = json.name,
    name = json.label,
    icon = json.icon,
    duration = json.defaultDuration,
    blockedBy = json.blockingStat
  }

  return effect
end

return {read = read}
