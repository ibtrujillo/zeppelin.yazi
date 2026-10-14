local M = {}

local FORMATS = {
  ["tar.gz"] = { tar = "gzip" },
  ["tgz"] = { tar = "gzip" },
  ["tar.xz"] = { tar = "xz" },
  ["txz"] = { tar = "xz" },
  ["tar.bz2"] = { tar = "bzip2" },
  ["tbz2"] = { tar = "bzip2" },
  ["tar"] = {},
  ["gz"] = { single = true },
  ["zip"] = { password = true },
  ["7z"] = { password = true, header = true },
  ["rar"] = { password = true, header = true },
}

local function join(...)
  local t = {}
  for _, list in ipairs { ... } do
    for _, v in ipairs(list) do
      t[#t + 1] = v
    end
  end
  return t
end

local function encrypted(path)
  local out = Command("7zz")
    :arg({ "l", "-slt", "-sccUTF-8", path })
    :stdin(Command.NULL)
    :stdout(Command.PIPED)
    :stderr(Command.NULL)
    :output()
  return out ~= nil and (out.stdout:find("Enter password", 1, true) ~= nil or out.stdout:find("Encrypted = +", 1, true) ~= nil)
end

function M:peek(job)
  local out = Command("7zz")
    :arg({ "l", "-slt", "-sccUTF-8", tostring(job.file.path) })
    :stdin(Command.NULL)
    :stdout(Command.PIPED)
    :stderr(Command.NULL)
    :output()

  if out and out.stdout:find("Enter password", 1, true) then
    return ya.preview_widget(job, ui.Text(ui.Line { ui.Span("\u{f023} Filename(s) encrypted") }):area(job.area))
  end

  return require("archive"):peek(job)
end

function M:seek(job)
  require("archive"):seek(job)
end

local yanked = ya.sync(function()
  local items = {}
  for _, f in pairs(cx.yanked) do
    items[#items + 1] = { path = tostring(f.url), dir = f.cha.is_dir }
  end
  return { cwd = tostring(cx.active.current.cwd), items = items }
end)

local function common_dir(paths)
  local common
  for _, p in ipairs(paths) do
    local parts = {}
    for s in p:gmatch("[^/]+") do
      parts[#parts + 1] = s
    end
    table.remove(parts)
    if not common then
      common = parts
    else
      local n = 0
      while n < #common and n < #parts and common[n + 1] == parts[n + 1] do
        n = n + 1
      end
      common = table.move(common, 1, n, 1, {})
    end
  end
  return "/" .. table.concat(common or {}, "/")
end

local function ends_with_tar(base)
  for key, fmt in pairs(FORMATS) do
    if (key == "tar" or fmt.tar) and base:sub(-#key - 1) == "." .. key then
      return true
    end
  end
  return false
end

local function split_format(name)
  local best
  for key in pairs(FORMATS) do
    if #name > #key + 1 and name:sub(-#key - 1) == "." .. key and (not best or #key > #best) then
      best = key
    end
  end
  if not best then
    return
  end
  local base = name:sub(1, -#best - 2)
  if FORMATS[best].single and ends_with_tar(base) then
    return
  end
  return base, best
end

local function unique_path(cwd, base, suffix)
  local name, n = base .. suffix, 0
  while fs.cha(Url(cwd .. "/" .. name)) do
    n = n + 1
    name = base .. "_" .. n .. suffix
  end
  return cwd .. "/" .. name
end

local function compress_command(key, out, items, pwd, header)
  local enc = pwd and { "-p" .. pwd } or {}
  if FORMATS[key].tar then
    local script = '7zz a -ttar -so x.tar "${@:2}" | 7zz a -t' .. FORMATS[key].tar .. ' -si "$1"'
    return Command("bash"):arg(join({ "-o", "pipefail", "-c", script, "_", out }, items))
  elseif key == "zip" then
    return Command("7zz"):arg(join({ "a", "-tzip" }, pwd and { "-mem=AES256" } or {}, enc, { out }, items))
  elseif key == "7z" then
    return Command("7zz"):arg(join({ "a" }, header and { "-mhe=on" } or {}, enc, { out }, items))
  elseif key == "tar" then
    return Command("7zz"):arg(join({ "a", "-ttar", out }, items))
  elseif key == "gz" then
    return Command("7zz"):arg(join({ "a", "-tgzip", out }, items))
  elseif key == "rar" then
    return Command("rar"):arg(join({ "a" }, pwd and { (header and "-hp" or "-p") .. pwd } or {}, { out }, items))
  end
end

-- shortcut: confirm body has no scroll view, shows CONFIRM_MAX_LINES lines and "… N more"; replace with native scroll when yazi offers one for ya.confirm
local CONFIRM_MAX_LINES = 11

local function confirm_list(sel)
  local lines = {}
  local total = #sel.items
  local shown = total > CONFIRM_MAX_LINES and CONFIRM_MAX_LINES - 1 or total
  for i = 1, shown do
    local it = sel.items[i]
    local icon = th.icon:match(File { url = Url(it.path), cha = Cha { mode = tonumber(it.dir and "40700" or "100644", 8) } })
    lines[#lines + 1] = ui.Line { ui.Span("  "), icon and ui.Span(icon.text .. " "):style(icon.style) or ui.Span("  "), ui.Span(it.path) }:align(ui.Align.LEFT)
  end
  if total > shown then
    lines[#lines + 1] = ui.Line { ui.Span(string.format("  \u{2026} %d more", total - shown)) }:align(ui.Align.LEFT)
  end
  return ya.confirm {
    pos = { "center", w = 80, h = math.min(#lines + 4, 30) },
    title = string.format("Compress %d selected files?", #sel.items),
    body = ui.Text(lines):align(ui.Align.LEFT),
  }
end

local function compress()
  local sel = yanked()
  if #sel.items == 0 then
    ya.notify { title = "Compress", content = "Nothing yanked: select with space, then y", level = "warn", timeout = 5 }
    return
  end

  local paths = {}
  for _, it in ipairs(sel.items) do
    if not fs.cha(Url(it.path)) then
      ya.notify { title = "Compress", content = "Yanked item missing: " .. it.path .. " (yank again)", level = "error", timeout = 10 }
      return
    end
    paths[#paths + 1] = it.path
  end

  if not confirm_list(sel) then
    return
  end

  local default = sel.cwd:match("[^/]+$") or "archive"
  local name, event = ya.input { pos = { "top-center", y = 2, w = 50 }, title = "Archive name:", value = default .. ".zip" }
  if event ~= 1 or name == "" then
    return
  end
  local base, key = split_format(name)
  if not key then
    ya.notify { title = "Compress", content = "Unknown archive format", level = "error", timeout = 10 }
    return
  end

  local pwd, header
  local fmt = FORMATS[key]
  if fmt.password then
    local value, pevent = ya.input { pos = { "top-center", y = 2, w = 50 }, title = "Password (empty = none):", obscure = true }
    if pevent ~= 1 then
      return
    end
    if value ~= "" then
      pwd = value
      if fmt.header then
        header = ya.confirm {
          pos = { "center", w = 60, h = 8 },
          title = "Encrypt file names?",
          body = ui.Text("Without this, file names stay visible without the password."),
        }
      end
    end
  end

  local origin = common_dir(paths)
  local out = unique_path(sel.cwd, base, "." .. key)
  local items = {}
  local prefix = origin == "/" and "/" or origin .. "/"
  for _, p in ipairs(paths) do
    items[#items + 1] = p:sub(#prefix + 1)
  end

  local cmd = compress_command(key, out, items, pwd, header)
  local res = cmd and cmd:cwd(origin):stdin(Command.NULL):stdout(Command.NULL):stderr(Command.PIPED):output()

  ya.emit("escape", {})
  if res and res.status.success then
    return
  end
  if fs.cha(Url(out)) then
    fs.remove("file", Url(out))
  end
  local msg = "Failed to start compressor"
  if res then
    msg = res.stderr:find("Incorrect password", 1, true) and "Incorrect password" or res.stderr:match("[^\r\n]+") or "compressor failed"
  end
  ya.notify { title = "Compress", content = msg, level = "error", timeout = 10 }
end

function M:entry(job)
  if job.args[1] == "compress" then
    return compress()
  end

  local path = job.args[1]
  if not path then
    return
  end

  local pwd = "-p-"
  if encrypted(path) then
    local value, event = ya.input { pos = { "top-center", y = 2, w = 50 }, title = "Password:", obscure = true }
    if event ~= 1 or value == "" then
      return
    end
    pwd = "-p" .. value
  end

  local base = path:gsub("%.rar$", "")
  local dir, n = base, 0
  while fs.cha(Url(dir)) do
    n = n + 1
    dir = base .. "_" .. n
  end

  local out = Command("rar")
    :arg({ "x", "-y", "-idq", pwd, path, dir .. "/" })
    :stdin(Command.NULL)
    :stdout(Command.NULL)
    :stderr(Command.PIPED)
    :output()

  if out and out.status.success then
    return
  end
  fs.remove("dir_all", Url(dir))
  local msg = "Failed to start rar"
  if out then
    msg = out.stderr:find("Incorrect password", 1, true) and "Incorrect password" or out.stderr:match("[^\r\n]+") or "rar failed"
  end
  ya.notify { title = "Extract", content = msg, level = "error", timeout = 10 }
end

return M
