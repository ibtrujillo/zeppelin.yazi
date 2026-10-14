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

print("zeppelin: ok")
