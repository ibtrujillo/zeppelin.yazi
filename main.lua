local M = {}

M.FORMATS = {
  ["tar.gz"] = { tar = "gzip" },
  ["tgz"] = { tar = "gzip" },
  ["tar.xz"] = { tar = "xz" },
  ["txz"] = { tar = "xz" },
  ["tar.bz2"] = { tar = "bzip2" },
  ["tbz2"] = { tar = "bzip2" },
  ["tar"] = {},
  ["gz"] = { single = true },
  ["zip"] = { password = true, split = true },
  ["7z"] = { password = true, header = true, split = true },
  ["rar"] = { password = true, header = true, split = true },
}

local UNITS = { b = 1, k = 1e3, kb = 1e3, kib = 1024, m = 1e6, mb = 1e6, mib = 1024 ^ 2, g = 1e9, gb = 1e9, gib = 1024 ^ 3 }

local MAX_PARTS = 999

function M.temp_dir()
  local res = Command("mktemp"):arg({ "-d" }):stdout(Command.PIPED):stderr(Command.NULL):output()
  if res and res.status.success then
    return (res.stdout:gsub("\n$", ""))
  end
end

function M.password_file(pwd)
  local dir = M.temp_dir()
  if not dir then
    return
  end
  if not fs.write(Url(dir .. "/pw"), pwd) then
    Command("rm"):arg({ "-rf", dir }):output()
    return
  end
  return dir
end

function M.volume_number(path)
  local n = path:match("%.7z%.(%d+)$") or path:match("%.zip%.(%d+)$") or path:match("%.part(%d+)%.rar$")
  if n then
    return tonumber(n)
  end
  n = path:match("%.r(%d%d+)$")
  if n then
    return tonumber(n) + 2
  end
end

local function ends_with_tar(base)
  for key, fmt in pairs(M.FORMATS) do
    if (key == "tar" or fmt.tar) and base:sub(-#key - 1) == "." .. key then
      return true
    end
  end
  return false
end

function M.split_format(name)
  local best
  for key in pairs(M.FORMATS) do
    if #name > #key + 1 and name:sub(-#key - 1) == "." .. key and (not best or #key > #best) then
      best = key
    end
  end
  if not best then
    return
  end
  local base = name:sub(1, -#best - 2)
  if M.FORMATS[best].single and ends_with_tar(base) then
    return
  end
  return base, best
end

function M.entry_names(paths)
  local segs, names = {}, {}
  for i, p in ipairs(paths) do
    segs[i] = {}
    for s in p:gmatch("[^/]+") do
      segs[i][#segs[i] + 1] = s
    end
  end
  local function tail(s, d)
    return table.concat(s, "/", #s - d + 1, #s)
  end
  for i, s in ipairs(segs) do
    local d = 1
    while d < #s do
      local clash = false
      for j, t in ipairs(segs) do
        if j ~= i and #t >= d and tail(t, d) == tail(s, d) then
          clash = true
          break
        end
      end
      if not clash then
        break
      end
      d = d + 1
    end
    names[i] = tail(s, d)
  end
  return names
end

function M.drop_nested(paths)
  local kept = {}
  for _, p in ipairs(paths) do
    local nested = false
    for _, q in ipairs(paths) do
      if p:sub(1, #q + 1) == q .. "/" then
        nested = true
        break
      end
    end
    if not nested then
      kept[#kept + 1] = p
    end
  end
  return kept
end

function M.volume_bytes(spec, total)
  local bytes
  local num, unit = spec:match("^(%d*%.?%d+)%s*(%a+)$")
  if num then
    local mult = UNITS[unit:lower()]
    bytes = mult and math.floor(tonumber(num) * mult)
  else
    local parts = tonumber(spec:match("^%d+$") or "")
    if parts and parts >= 2 and parts <= MAX_PARTS then
      bytes = math.ceil(total / parts)
    end
  end
  if not bytes or bytes < 1 or bytes >= total or math.ceil(total / bytes) > MAX_PARTS then
    return nil, "Invalid volume: " .. spec .. " (needs 2-999 parts)"
  end
  return string.format("%db", bytes)
end

return M
