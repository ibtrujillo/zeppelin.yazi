local P = dofile("main.lua")

local function same(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

local cases = {
  { P.volume_bytes("5.5MB", 100e6), "5500000b" },
  { P.volume_bytes("4", 1000), "250b" },
  { P.volume_bytes("89kiB", 1e6), "91136b" },
  { P.volume_bytes("999", 1e6), "1002b" },
  { P.volume_bytes("1", 1000), nil },
  { P.volume_bytes("1000", 1e6), nil },
  { P.volume_bytes("2000b", 1000), nil },
  { P.volume_bytes("x", 1000), nil },
  { P.volume_number("a.7z.002"), 2 },
  { P.volume_number("a.zip.010"), 10 },
  { P.volume_number("a.part01.rar"), 1 },
  { P.volume_number("a.r00"), 2 },
  { P.volume_number("a.zip"), nil },
}

for i, c in ipairs(cases) do
  assert(c[1] == c[2], "volume case " .. i .. ": got " .. tostring(c[1]))
end

local b, k = P.split_format("a.tar.gz")
assert(b == "a" and k == "tar.gz")
b, k = P.split_format("b.gz")
assert(b == "b" and k == "gz")
b, k = P.split_format("c.zip")
assert(b == "c" and k == "zip")
assert(P.split_format("zip") == nil)
assert(P.split_format("a.unknown") == nil)
assert(P.split_format("a.tar") == "a")

assert(same(P.entry_names({ "/x/a/file", "/x/b/file" }), { "a/file", "b/file" }))
assert(same(P.entry_names({ "/x/a", "/y/c" }), { "a", "c" }))

assert(same(P.drop_nested({ "/x", "/x/a", "/y" }), { "/x", "/y" }))

local function only(list)
  local set = {}
  for _, p in ipairs(list) do
    set[p] = true
  end
  return function(p)
    return set[p] == true
  end
end

assert(P.first_volume("/d/a.7z.002", only { "/d/a.7z.001" }) == "/d/a.7z.001")
assert(P.first_volume("/d/a.7z.002", only {}) == "/d/a.7z.002")
assert(P.first_volume("/d/a.part02.rar", only { "/d/a.part01.rar" }) == "/d/a.part01.rar")
assert(P.first_volume("/d/a.r05", only { "/d/a.rar" }) == "/d/a.rar")
assert(P.first_volume("/d/a.zip.003", only { "/d/a.zip.001" }) == "/d/a.zip.001")
assert(P.first_volume("/d/a.zip", only { "/d/a.zip" }) == "/d/a.zip")

local function route(path, tool, base, pwd)
  local r = P.extract_route(path)
  assert(r, "no route: " .. path)
  assert(r.tool == tool and r.base == base and r.password == pwd, path .. ": tool=" .. tostring(r.tool) .. " base=" .. tostring(r.base) .. " pwd=" .. tostring(r.password))
end

route("/d/x.tar.gz", "unar", "/d/x", nil)
route("/d/x.TGZ", "unar", "/d/x", nil)
route("/d/pkg x.tar.xz", "unar", "/d/pkg x", nil)
route("/d/p.tar.bz2", "unar", "/d/p", nil)
route("/d/p.tbz2", "unar", "/d/p", nil)
route("/d/p.txz", "unar", "/d/p", nil)
route("/d/p.tar", "unar", "/d/p", nil)
route("/d/s.gz", "unar", "/d/s", nil)
route("/d/s.bz2", "unar", "/d/s", nil)
route("/d/s.xz", "unar", "/d/s", nil)
route("/d/x.tar.gz.zip", "7zz", "/d/x.tar.gz", true)
route("/d/a.part01.rar", "unar", "/d/a", true)
route("/d/a.part1.rar", "unar", "/d/a", true)
route("/d/a.PART02.RAR", "unar", "/d/a", true)
route("/d/a.rar", "unar", "/d/a", true)
route("/d/a.r05", "unar", "/d/a", true)
route("/d/a.7z", "7zz", "/d/a", true)
route("/d/a.7z.001", "7zz", "/d/a", true)
route("/d/a.zip", "7zz", "/d/a", true)
route("/d/a.zip.003", "7zz", "/d/a", true)
route("/d/-leading.zip", "7zz", "/d/-leading", true)
route('/d/quo"te $HOME `x`.zip', "7zz", '/d/quo"te $HOME `x`', true)
route("/d/ñ ü.7z", "7zz", "/d/ñ ü", true)
route("/my dir/a b.tar.gz", "unar", "/my dir/a b", nil)
route("/d/wild*card?[1].zip", "7zz", "/d/wild*card?[1]", true)
assert(P.extract_route("/d/.zip") == nil)
assert(P.extract_route("/d/zip") == nil)
route("/d/.tar.gz", "unar", "/d/.tar", nil)
assert(P.extract_route("/d/a.txt") == nil)
assert(P.extract_route("/d/a.zst") == nil)
assert(P.extract_route("/d/dir/") == nil)

local prog, args = P.archive_command("zip", "/o/a.zip", { "f1" }, "pw", nil, "5000b")
assert(prog == "7zz")
assert(same(args, { "a", "-tzip", "-mem=AES256", "-ppw", "-v5000b", "/o/a.zip", "f1" }))

prog, args = P.archive_command("rar", "/o/a.rar", { "f1" }, "/tmp/d/pw", true, "10b")
assert(prog == "rar")
assert(same(args, { "a", "-hp@/tmp/d/pw", "-v10b", "/o/a.rar", "f1" }))

prog, args = P.archive_command("7z", "/o/a.7z", { "f1" }, nil, nil, nil)
assert(prog == "7zz" and same(args, { "a", "/o/a.7z", "f1" }))

prog, args = P.archive_command("tar.gz", "/o/a.tar.gz", { "f1", "d/f2" }, nil, nil, nil)
assert(prog == "bash" and args[1] == "-o" and args[2] == "pipefail" and args[3] == "-c")
assert(args[4]:find("-tgzip", 1, true) and args[5] == "_" and args[6] == "/o/a.tar.gz" and args[7] == "f1" and args[8] == "d/f2")


local function plan(path, pwd)
  local r = P.extract_route(path)
  return { P.extract_plan(r, "/o/a", pwd, path) }
end

local t = plan("/d/a b.rar")
assert(t[1] == "unar" and same(t[2], { "-q", "-o", "/o/a", "--", "/d/a b.rar" }))
t = plan("/d/a.rar", "pw")
assert(t[1] == "unar" and same(t[2], { "-q", "-o", "/o/a", "-p", "pw", "--", "/d/a.rar" }))
t = plan("/d/a.tar.gz")
assert(t[1] == "unar" and same(t[2], { "-q", "-o", "/o/a", "--", "/d/a.tar.gz" }))
t = plan("/d/a.7z")
assert(t[1] == "7zz" and same(t[2], { "x", "-y", "-bd", "--", "/d/a.7z" }))
t = plan("/d/-x.zip", "pw")
assert(t[1] == "7zz" and same(t[2], { "x", "-y", "-bd", "-ppw", "--", "/d/-x.zip" }))
t = plan("/d/*[1].zip")
assert(t[1] == "7zz" and same(t[2], { "x", "-y", "-bd", "--", "/d/*[1].zip" }))

local function jobs(list, files)
  local set = {}
  for _, p in ipairs(files) do
    set[p] = true
  end
  return P.extract_jobs(list, function(p)
    return set[p] == true
  end)
end

local js = jobs({ "/d/a.part02.rar", "/d/a.part01.rar" }, { "/d/a.part01.rar", "/d/a.part02.rar" })
assert(#js == 1 and js[1].path == "/d/a.part01.rar")
js = jobs({ "/d/a.r00", "/d/a.rar" }, { "/d/a.rar" })
assert(#js == 1 and js[1].path == "/d/a.rar")
js = jobs({ "/d/a.txt", "/d/b.zip", "/d/c.tar.gz", "/d/dir.zip" }, { "/d/b.zip", "/d/c.tar.gz" })
assert(#js == 2 and js[1].path == "/d/b.zip" and js[2].path == "/d/c.tar.gz")
js = jobs({ "/d/a.7z.002" }, { "/d/a.7z.001", "/d/a.7z.002" })
assert(#js == 1 and js[1].path == "/d/a.7z.001")
js = jobs({ "/d/a.part02.rar" }, { "/d/a.part02.rar" })
assert(#js == 1 and js[1].path == "/d/a.part02.rar")
js = jobs({ "/d/x.zip", "/d/y.zip", "/d/x.zip" }, { "/d/x.zip", "/d/y.zip" })
assert(#js == 2)
assert(#jobs({}, {}) == 0)
assert(#jobs({ "/d/notes.txt" }, { "/d/notes.txt" }) == 0)

assert(P.needs_password("Enter password:"))
assert(P.needs_password("This archive requires a password to unpack."))
assert(not P.needs_password("Wrong checksum"))
assert(not P.needs_password(""))

assert(P.failure_message("x", true) == "Wrong password or damaged archive")
assert(P.failure_message("7-Zip 26\n\nERROR: errno=2 : No such file or directory\n/x", false) == "ERROR: errno=2 : No such file or directory")
assert(P.failure_message("Extraction to directory \"/o\" failed (1 file failed.)", false) == "Extraction to directory \"/o\" failed (1 file failed.)")
assert(P.failure_message("", false) == "Extraction failed")
assert(P.failure_message("only line", false) == "only line")
assert(P.failure_message("\n   ERROR: x\n", false) == "ERROR: x")

print("zeppelin: ok")
