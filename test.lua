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

assert(P.archive_base("x.part01.rar") == "x")
assert(P.archive_base("c.rar") == "c")
assert(P.archive_base("a.7z.001") == "a")
assert(P.archive_base("d.zip.002") == "d")

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


assert(same(P.extract_args("unar", "/o/a", "pw", "/d/a.rar"), { "-q", "-o", "/o/a", "-p", "pw", "/d/a.rar" }))
assert(same(P.extract_args("7zz", "/o/a", nil, "/d/a.7z"), { "x", "-y", "-bd", "-o/o/a", "/d/a.7z" }))
assert(same(P.extract_args("7zz", "/o/a", "pw", "/d/a.7z"), { "x", "-y", "-bd", "-o/o/a", "-ppw", "/d/a.7z" }))

print("zeppelin: ok")
