---
--- Generated by Luanalysis
--- Created by lyrthras.
--- DateTime: 25/08/2021 11:25 PM
---


local log = require "log"

--[[
[
  { "op": "image", "value": "/path/to/image.png" },       // apply image
  { "op": "image", "value": [                             // frames processing etc
    { "op": "image", "value": "/path/to/image2.png" },
    { "op": "crop", "value": [0, 0, 16, 16] }
  ]},
  { "op": "trim" },                                       // trim out transparent edges

  // SB directives
  { "op": "setcolor", "value": "1000b8" },
  { "op": "replace", "value": { "ababab": "2d2d2d" } },   // color swaps
  { "op": "hueshift", "value": -30 },                     // 0 ~ 360
  { "op": "brightness", "value": -10 },                   // -100 ~ 100
  { "op": "saturation", "value": 30 },                    // -100 ~ 100
  { "op": "crop", "value": [0, 0, 16, 16] },              // [x1, y1, x2, y2] upper left origin
  { "op": "flipx" }, { "op": "flipy" }, { "op": "flipxy" },
  { "op": "fade", "value": 0.8 }                          // 0 ~ 1
]
--]]


--[[
for a,b,c in ("abcd.png:ee.ff?g;10=2?hh:e;10=3"):gmatch("([^:?]+):?([^?]*)(.*)") do print(a,b,c) end
abcd.png        ee.ff   g;10=2?hh:e;10=3
--]]


local directiveParsers = {
  setcolor = function(s)
    local col = s:match("=(%x+)")
    return col ~= "" and col or nil
  end,
  replace = function(s)
    local map = {}
    for from,to in s:gmatch(";(%x+)=(%x+)") do
      map[from] = to
    end
    return #map > 0 and map or nil
  end,
  hueshift = function(s) return tonumber(s:match("=(-?%d+)")) end,
  brightness = function(s) return tonumber(s:match("=(-?%d+)")) end,
  saturation = function(s) return tonumber(s:match("=(-?%d+)")) end,
  crop = function(s)
    local x1, y1, x2, y2 = s:match("=(%d+);(%d+);(%d+);(%d+)")
    x1, y1, x2, y2 = tonumber(x1), tonumber(y1), tonumber(x2), tonumber(y2)
    return (x1 and y1 and x2 and y2) and { x1, y1, x2, y2 } or nil
  end,
  flipx = function(s) return 1 end,
  flipy = function(s) return 1 end,
  flipxy = function(s) return 1 end,
  fade = function(s)
    local col, amt = s:match("=(%x+)=([0-9.]+)")
    return tonumber(amt)      -- NOTE: no color fading for now
  end
}


---@param def string
local function getDefParts(def)

  local filename, frame, directives_s = def:match("([^:?]+):?([^?]*)(.*)")
  local directives = {}
  local unknowns = {}
  if directives_s ~= "" then
    for name, params in directives_s:gmatch("?(%a+)([^?]+)") do
      if directiveParsers[name] then
        local v = directiveParsers[name](params)
        if v ~= nil then
          directives[#directives+1] = { op = name, value = v }
        end
      else
        unknowns[#unknowns+1] = name
      end
    end
  end

  return filename, frame ~= "" and frame or nil, directives, unknowns
end


-- returns [x1, y1, x2, y2]
local function getFrameBounds(frame, frames)
  while frames.aliases and frames.aliases[frame] and frames.aliases[frame] ~= frame do
    frame = frames.aliases[frame]
  end

  if frames.frameList and frames.frameList[frame] then
    return frames.frameList[frame]
  elseif frames.frameGrid then
    local fg = frames.frameGrid
    for y = 1, #fg.names do
      for x = 1, #fg.names[y] do
        if fg.names[y][x] == frame then
          return {
            fg.size[1]*(x-1), fg.size[2]*(y-1),
            fg.size[1]*x,     fg.size[2]*y
          }
        end
      end
    end
  end

  return nil
end


-- frames is frames file json
-- image path is from content root already, /items/active/.../thing.png
--- image string or table, frames frames file json if any
--- returns array of processables
local function getProcessable(image, frames)
  if type(image) == "string" then
    image = image
        :gsub("<frame>|<variant>", "1")
        :gsub("<paletteSwaps>|<.*[Dd]irectives>", "")
        :gsub("<.+>", "default")

    local filename, frame, directives, unknowns = getDefParts(image)

    if #unknowns > 0 then
      log.warn("Unknown directive(s) [%s] for image [%s]", table.concat(unknowns, ", "), image)
    end

    local proc = {
      { op = "image", value = filename }
    }

    if frame then
      if frames then
        local bounds = getFrameBounds(frame, frames)
        if bounds then
          table.insert(proc, { op = "crop", value = bounds })
        else
          log.error("Missing frame [%s] for image [%s]! Using whole image...", frame, image)
        end
      else
        log.error("No frames file found for image [%s]. Using whole image...", image)
      end
    end

    for _, directive in pairs(directives) do
      proc[#proc+1] = directive
    end

    return proc
  end
end


return { getProcessable = getProcessable }