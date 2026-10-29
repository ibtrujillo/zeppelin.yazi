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

-- shortcut: confirm body has no scroll view, shows CONFIRM_MAX_LINES lines and "… N more"; replace with native scroll when yazi offers one for ya.confirm
M.CONFIRM_MAX_LINES = 11

function M.join(...)
  local t = {}
  for _, list in ipairs { ... } do
    for _, v in ipairs(list) do
      t[#t + 1] = v
    end
  end
  return t
end

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

function M.first_volume(path, exists)
  local head
  local stem, n = path:match("^(.*)%.7z%.(%d+)$")
  if stem then
    head = stem .. ".7z." .. string.rep("0", #n - 1) .. "1"
  end
  stem, n = path:match("^(.*)%.part(%d+)%.rar$")
  if stem then
    head = stem .. ".part" .. string.rep("0", #n - 1) .. "1.rar"
  end
  stem, n = path:match("^(.*)%.zip%.(%d+)$")
  if stem then
    head = stem .. ".zip." .. string.rep("0", #n - 1) .. "1"
  end
  stem = path:match("^(.*)%.r%d%d+$")
  if stem then
    head = stem .. ".rar"
  end
  if head and exists(head) then
    return head
  end
  return path
end

function M.archive_base(path)
  local base = path:gsub("%.part0*1%.rar$", ""):gsub("%.rar$", ""):gsub("%.7z%.%d+$", ""):gsub("%.zip%.%d+$", "")
  return base
end

-- shortcut: 7zz takes -p in argv (visible in ps); no password-file or stdin form works for 7zz t, upgrade if 7zz gains one
function M.archive_command(key, out, items, pwd, header, vol)
  local enc = pwd and { "-p" .. pwd } or {}
  local split = vol and { "-v" .. vol } or {}
  local fmt = M.FORMATS[key]
  if fmt.tar then
    local script = '7zz a -ttar -so x.tar "${@:2}" | 7zz a -t' .. fmt.tar .. ' -si "$1"'
    return "bash", M.join({ "-o", "pipefail", "-c", script, "_", out }, items)
  elseif key == "zip" then
    return "7zz", M.join({ "a", "-tzip" }, pwd and { "-mem=AES256" } or {}, enc, split, { out }, items)
  elseif key == "7z" then
    return "7zz", M.join({ "a" }, header and { "-mhe=on" } or {}, enc, split, { out }, items)
  elseif key == "tar" then
    return "7zz", M.join({ "a", "-ttar", out }, items)
  elseif key == "gz" then
    return "7zz", M.join({ "a", "-tgzip", out }, items)
  elseif key == "rar" then
    return "rar", M.join({ "a" }, pwd and { (header and "-hp@" or "-p@") .. pwd } or {}, split, { out }, items)
  end
end

-- shortcut: 7zz takes -p in argv (visible in ps); no password-file or stdin form works for 7zz x, upgrade if 7zz gains one
function M.extract_args(tool, dir, pwd, path)
  if tool == "unar" then
    return M.join({ "-q", "-o", dir }, pwd and { "-p", pwd } or {}, { path })
  end
  return M.join({ "x", "-y", "-bd", "-o" .. dir }, pwd and { "-p" .. pwd } or {}, { path })
end

local function confirm_line(item)
  local mode = item.link and "120777" or item.dir and "40700" or "100644"
  local icon = th.icon:match(File { url = Url(item.path), cha = Cha { mode = tonumber(mode, 8) } })
  return ui.Line { ui.Span("  "), icon and ui.Span(icon.text .. " "):style(icon.style) or ui.Span("  "), ui.Span(item.path) }:align(ui.Align.LEFT)
end

function M.confirm_list(items, title)
  local lines = {}
  local total = #items
  local shown = total > M.CONFIRM_MAX_LINES and M.CONFIRM_MAX_LINES - 1 or total
  for i = 1, shown do
    lines[#lines + 1] = confirm_line(items[i])
  end
  if total > shown then
    lines[#lines + 1] = ui.Line { ui.Span(string.format("  \u{2026} %d more", total - shown)) }:align(ui.Align.LEFT)
  end
  return ya.confirm {
    pos = { "center", w = 80, h = math.min(#lines + 4, 30) },
    title = title,
    body = ui.Text(lines):align(ui.Align.LEFT),
  }
end

return M
