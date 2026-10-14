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

  local dir = path:gsub("%.rar$", "")
  if fs.cha(Url(dir)) then
    return ya.notify { title = "Extract", content = dir .. " already exists", level = "error", timeout = 5 }
  end

  local out = Command("rar")
    :arg({ "x", "-y", "-idq", pwd, path, dir .. "/" })
    :stdin(Command.NULL)
    :stdout(Command.NULL)
    :stderr(Command.PIPED)
    :output()

  if not out then
    ya.notify { title = "Extract", content = "Failed to start rar", level = "error", timeout = 5 }
  elseif not out.status.success then
    ya.notify { title = "Extract", content = out.stderr, level = "error", timeout = 10 }
  end
end

return M
