# TyaLin

Public release repository for TyaLin.

This repository intentionally contains only the loader and the built,
obfuscated payload. The readable source lives in a private repository.

## Run

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Fajartya/TyaLin-FishIt/main/dist/payload.lua"))()
```

## Files

- `loader.lua` — fetches and runs `dist/payload.lua`
- `dist/payload.lua` — built artifact (minified, string encrypted)

The payload is downloaded and executed by the client, so anybody can copy it.
Keep the meaningful checks on a server you control.
