local M = {}

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

function M:entry(job)
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
