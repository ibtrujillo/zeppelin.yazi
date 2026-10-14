local M = {}

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

return M
