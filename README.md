# Deadbeat

**One neat bar for WoW: Forever that every addon can sit on**, in the spirit of Titan Panel. Deadbeat draws the bar,
its tooltip and one settings console; modules bring the content: your gold and bags, fishing, instance lockouts, and
the launchers of the addons you already use.

## For players

- **One bar**, compact in the top middle or full-width on the top or bottom edge (gear → Bar → Layout).
- **Items in groups:** each addon's items sit together, a thin divider between addons. Hover for its details,
  click for its action, right-click for its settings.
- **Arrange it yourself:** right-click the gear (or gear → Edit bar) and drag; hidden items wait on the shelf.
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

Making your addon a module takes a few lines: register, offer a few items (an icon and a short value each), a tooltip,
a click and a settings page. The player arranges them. Addons with an LDB data object show up without any code.

```lua
if Deadbeat and Deadbeat.SPEC >= "2.0" then
    local m = Deadbeat.Register("MyAddon", { icon = "Interface\\Icons\\INV_Misc_Rune_01", spec = "2.0" })
    local score = m:Item("score", { name = "Score", icon = "Interface\\Icons\\INV_Misc_Coin_01" })
    score:Set("42", "good")
    m:Tooltip(function(tip, item) tip:AddLine("  the details") end)
    m:Click(function() print("hi") end, "say hi")
end
```

- **The design language:** [deadbeat-spec/DESIGN.md](https://github.com/manuelnagele/deadbeat-spec/blob/main/DESIGN.md)
- **The spec:** [deadbeat-spec/spec.md](https://github.com/manuelnagele/deadbeat-spec/blob/main/spec.md)
- **Building with an AI assistant:** [deadbeat-spec/AGENTS.md](https://github.com/manuelnagele/deadbeat-spec/blob/main/AGENTS.md)
- **Test outside the game:** the harness and an example module in [deadbeat-spec](https://github.com/manuelnagele/deadbeat-spec)

## Development

```
luajit tests/smoke.lua      # the hub against a stubbed WoW API
luajit tests/broker.lua     # the LibDataBroker bridge
```
The tests use the shared harness from [deadbeat-spec](https://github.com/manuelnagele/deadbeat-spec): clone it next to
this repo (`../deadbeat-spec`) or point `HARNESS` at its `harness/wowstub.lua`.
Releases: push a tag `vX.Y.Z` matching the TOC's version; CI packages the zip. `deploy/` is the author's Linux setup
that keeps a game install in sync with this repo (optional).

License: MIT.
