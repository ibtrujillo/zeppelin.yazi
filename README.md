# zeppelin.yazi

Shared helper library for Yazi archive plugins: format detection, multi-volume
handling, password prompts and `7zz` / `tar` command planning. It has no UI of
its own; the other plugins call it with `require("zeppelin")`.

## Requirements

- Yazi 26.9.1 or newer
- `7zz` (7-Zip), plus `tar`, `gzip`, `xz`, `bzip2` and `zip` for the formats you use

## Installation

```sh
ya pkg add ibtrujillo/zeppelin.yazi
```

## Tests

```sh
lua test.lua
```

Standalone tests only; the plugin is loaded by the plugins listed above.
