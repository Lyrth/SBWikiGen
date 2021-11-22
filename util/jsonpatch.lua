---
--- Generated by Luanalysis
--- Created by lyrthras.
--- DateTime: 30/10/2021 12:37 AM
---


--[[

A Lua implementation of rfc6902 (json patch), with default support
for 'extended' JSON patch (used by Starbound). A call to the table
returned by `require` can be used to set the implementation to use
strict rfc6902 instead of the extended variant.

Also included is rfc6901 (json pointer) support.

TODO: null value support.

References:
-- https://github.com/json-patch/json-patch-tests/blob/master/tests.json
-- https://datatracker.ietf.org/doc/html/rfc6901
-- https://datatracker.ietf.org/doc/html/rfc6902

--]]


--region -- Util --

-- http://lua-users.org/wiki/CopyTable --
local function deepCopy(t, cp)
  if type(t) == 'table' then
    cp = cp or {}
    if cp[t] ~= nil then
      return cp[t]
    else
      cp[t] = {}
      for k, v in next, t, nil do
        cp[t][deepCopy(k, cp)] = deepCopy(v, cp)
      end
      return setmetatable(cp[t], deepCopy(getmetatable(t), cp))
    end
  else
    return t
  end
end

-- no need for deeper compare since JSON does not allow complex keys.
local function compare(t1, t2)
  if t1 == t2 then return true end
  if type(t1) ~= type(t2) then return false end
  if type(t1) ~= 'table' then return false end

  for k,v in next, t1, nil do
    if not compare(v, t2[k]) then return false end
  end
  for k,v in next, t2, nil do
    if not compare(v, t1[k]) then return false end
  end

  return true
end

--endregion -- Util --


--region -- JSON Path --

local function pathEscape(path)
  assert(type(path) == 'string', "path should be a string")
  return path:gsub('~', "~0"):gsub('/', "~1")
end

local function pathUnescape(path)
  assert(type(path) == 'string', "path should be a string")
  return path:gsub("~1", '/'):gsub("~0", '~')
end

---@return any|nil, nil|string
local function getNode(obj, path)
  assert(type(path) == 'string', "path should be a string")
  if obj == nil then
    return nil, nil
  end
  if path == '' then
    return obj, nil
  end
  assert(type(obj) == 'table', "obj should be a table")
  if #path ~= 0 and path:sub(1,1) ~= '/' then
    return nil, "invalid path supplied"
  end

  local ref = obj
  for name in path:gmatch("/([^/]*)") do
    if ref == nil then
      return nil, nil
    elseif type(ref) ~= 'table' then
      return nil, "part of the path tree is not a table"
    end

    local u = pathUnescape(name)
    local n = (u == '0' or u:match("^[1-9][0-9]*$")) and (tonumber(u) + 1)
    ref = ref[n or u]
  end

  return ref, nil
end

--- Note: Replaces in place (obj table overwritten)
---@return boolean, nil|string
local function setNode(obj, path, value, arrayInsert)
  assert(type(path) == 'string', "path should be a string")
  if path == '' then
    return false, "cannot replace whole document"
  end
  assert(type(obj) == 'table', "obj should be a table")
  if path:sub(1,1) ~= '/' then
    return false, "invalid path supplied"
  end

  local ppos, child = path:match("()/([^/]*)$")
  local parent = path:sub(1, ppos-1)

  local container, err = getNode(obj, parent)
  if container == nil then
    return false, err
  elseif type(container) ~= 'table' then
    return false, "part of the path tree is not a table"
  end

  local u = pathUnescape(child)
  local n = (u == '0' or u:match("^[1-9][0-9]*$")) and (tonumber(u) + 1)

  -- if ambiguous, make array
  if container[1] ~= nil or (next(container) == nil and (n or u == '-')) then   -- container is an array
    if u == '-' then
      container[#container + 1] = value
      return true, nil
    else
      if not n then
        return false, "invalid key for array"
      end
      if n > #container+1 then
        return false, "array index out of range"
      end

      if arrayInsert then
        (value == nil and table.remove or table.insert)(container, n, value)
      else
        container[n] = value
      end
      return true, nil
    end
  else    -- container is an object
    container[u] = value
    return true, nil
  end
end

--endregion -- JSON Path --


--region -- JSON Patch --

local ops = {}
local opsExt = {}
setmetatable(ops, {__index = function(t,_) return t._invalid end})

-- rfc6902 without the extensions
local function applyPatchStrict(obj, patch)
  assert(type(patch) == 'table', "patch should be a table")
  assert(not next(patch) or patch[1], "patch must be an array and not an object")

  local new = deepCopy(obj)
  for i = 1,#patch do
    local v = patch[i]
    if not (type(v) == 'table' and v.op and v.path) then
      return obj, false, "! #"..i..": invalid patch operation: should be a table, and contain 'op' and 'path' members"
    end

    local assertSuccess, assertMsgOrNewVal, normSuccess, normMsg = pcall(ops[v.op], new, v)
    if not assertSuccess then
      return obj, false, "! #"..i..": "..assertMsgOrNewVal
    elseif not normSuccess then
      return obj, false, "#"..i..": "..normMsg
    end

    new = assertMsgOrNewVal
  end

  return new, true, nil
end

-- supports nested patches, modified `test` behavior
-- array if:
--   empty : next(t) == nil, or
--   not empty : patch[1] ~= nil
local function applyPatchExtended(obj, patch)
  assert(type(patch) == 'table', "patch should be a table")
  assert(not next(patch) or patch[1], "patch must be an array and not an object")

  local new = deepCopy(obj)
  for i = 1,#patch do
    local v = patch[i]

    if not next(v) or v[1] then     -- an array: nested patch
      local o, _, m = applyPatchExtended(obj, v)
      if m:sub(1,1) == '!' then
        return obj, false, "! #"..i..":"..m:sub(2)
      end
      new = o
    end

    if not (type(v) == 'table' and v.op and v.path) then
      return obj, false, "! #"..i..": invalid patch operation: should be a table, and contain 'op' and 'path' members"
    end

    local assertSuccess, assertMsgOrNewVal, normSuccess, normMsg = pcall(opsExt[v.op] or ops[v.op], new, v)
    if not assertSuccess then
      return obj, false, "! #"..i..": "..assertMsgOrNewVal
    elseif not normSuccess then
      return obj, false, "#"..i..": "..normMsg
    end

    new = assertMsgOrNewVal
  end

  return new, true, nil
end


--region -- -- Operations -- --

function ops._invalid(_, opData)
  error("invalid operation "..opData.op)
end

function ops.add(obj, opData)
  if opData.path == '' then
    return opData.value, true, nil
  end

  return obj, setNode(obj, opData.path, opData.value, true)
end

function ops.remove(obj, opData)
  if opData.path == '' then
    return nil, true, nil
  end

  return obj, setNode(obj, opData.path, nil, true)
end

function ops.replace(obj, opData)
  if opData.path == '' then
    return opData.value, true, nil
  end

  -- check if exists
  local v, m = getNode(obj, opData.path)
  if v == nil then
    return obj, false, m
  end

  return obj, setNode(obj, opData.path, opData.value, false)
end

function ops.move(obj, opData)
  assert(opData.from, "move: 'from' member missing")

  if opData.path == opData.from then
    return obj, true, nil
  end
  if opData.path:find(opData.from) == 1 then
    return obj, false, "move: cannot move parent to child"
  end

  local val, m = getNode(obj, opData.from)
  if val == nil then
    return obj, false, m
  end

  local s
  s, m = setNode(obj, opData.from, nil, true)
  if not s then
    return obj, false, m
  end

  if opData.path == '' then
    return val, true, nil
  end

  return obj, setNode(obj, opData.path, val, true)
end

function ops.copy(obj, opData)
  assert(opData.from, "copy: 'from' member missing")

  if opData.path == opData.from then
    return obj, true, nil
  end

  local val, m = getNode(obj, opData.from)
  if val == nil then
    return obj, false, m
  end

  if opData.path == '' then
    return val, true, nil
  end

  return obj, setNode(obj, opData.path, val, true)
end

function ops.test(obj, opData)
  assert(opData.value, "test: 'value' member missing")

  local val, m = getNode(obj, opData.path)
  if val == nil then
    return obj, false, m
  end

  return obj, compare(opData.value, val), nil
end

-- Extension

function opsExt.test(obj, opData)
  opData.inverse = opData.inverse and true or false

  local val, m = getNode(obj, opData.path)
  if opData.value == nil then
    return obj, opData.inverse == (val == nil), nil
  else
    if val == nil then
      return obj, opData.inverse ~= false, m
    end

    return obj, opData.inverse ~= compare(opData.value, val), nil
  end
end

--endregion -- -- Operations -- --

--endregion -- JSON Patch --


return setmetatable({
  pathEscape = pathEscape,
  getNode = getNode,
  setNode = setNode,
  applyPatch = applyPatchExtended
}, {
  __call = function(t,rfcStrict)
    if rfcStrict then
      t.applyPatch = applyPatchStrict
    else
      t.applyPatch = applyPatchExtended
    end
    return t
  end
})