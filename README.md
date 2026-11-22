# Deadbeat

**One neat bar for WoW: Forever that every addon can sit on**, in the spirit of Titan Panel. Deadbeat draws the bar,
its tooltip and one settings console; modules bring the content: your gold and bags, fishing, instance lockouts, and
the launchers of the addons you already use.

## For players

- **One bar**, compact in the top middle or full-width on the top or bottom edge (gear → Bar → Layout).
- **It adapts** to where you are: farming, raid, dungeon, city, open world. Each badge can be switched per place
  (gear → Bar → What shows where).
- **Your other addons** that offer a LibDataBroker launcher or data source (DBM, Questie, AtlasLoot, OpenMap, WIM,
  BagBrother, …) appear in a tray on the bar; pin any of them as its own badge; their minimap buttons can go.
- **Every setting is a button** in one console: the gear at the bar's right end (or `/deadbeat`).
- Modules made for it: [Hearth](https://github.com/manuelnagele/hearth) (gold, bags, durability, world buffs, raid
  progress), [Lockout](https://github.com/manuelnagele/lockout) (Forever's 5 instances per hour),
  [Catch](https://github.com/manuelnagele/catch) (fishing).

Install: copy the `Deadbeat` folder into `World of Warcraft/_forever_/Interface/AddOns/`, or unzip a release there.

## For addon authors

Making your addon a module takes a few lines: register, put a field, a badge or a tooltip section on the bar, and add
a settings page. Addons with an LDB data object show up without any code.

```lua
if Deadbeat then
    local m = Deadbeat.Register("MyAddon", 70, { spec = "1.0" })
    m:Set("label", "Hello", 5)
    m:Section(function(tip) tip:AddLine("MyAddon") end)
end
```

- **The spec:** [deadbeat-spec/spec.md](https://github.com/manuelnagele/deadbeat-spec/blob/main/spec.md)
- **Building with an AI assistant:** [deadbeat-spec/AGENTS.md](https://github.com/manuelnagele/deadbeat-spec/blob/main/AGENTS.md)
- **Test outside the game:** the harness and an example module in [deadbeat-spec](https://github.com/manuelnagele/deadbeat-spec)

## Development

```
luajit tests/smoke.lua      # the hub against a stubbed WoW API
luajit tests/broker.lua     # the LibDataBroker bridge
```
Releases: push a tag `vX.Y.Z` matching the TOC's version; CI packages the zip. `deploy/` is the author's Linux setup
that keeps a game install in sync with this repo (optional).

License: MIT.
