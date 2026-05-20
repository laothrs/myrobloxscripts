# myrobloxscripts

A curated collection of **standalone Roblox (Luau) modules** for portfolio and production reference. Each folder is self-contained: copy the scripts into the matching Roblox Studio services, read that folder’s README, and run.

No `.rbxl` place files are included — layout mirrors how code is organized in a live game.

**Language:** Luau (`--!strict` where noted)  
**Repository:** [github.com/laothrs/myrobloxscripts](https://github.com/laothrs/myrobloxscripts)

---

## Projects

| Project | Focus | Where it runs |
|---------|--------|----------------|
| [**DataManaging**](./DataManaging/) | Server-side player data: `UpdateAsync`, schema reconciliation, session cache, `BindToClose` saves | `ServerStorage` + `ServerScriptService` |
| [**ChunkRenderer**](./ChunkRenderer/) | Client-side map chunk streaming via reparenting (no clones), hysteresis, throttled distance checks | `StarterPlayerScripts` |

### [DataManaging](./DataManaging/) — Player data framework

Production-style persistence layer for experiences that cannot afford lost progress or racey writes.

- Typed defaults and **schema reconciliation** after updates  
- Per-player **session cache** with `Get` / `Set` / `Increment`  
- **`UpdateAsync` only** for saves; failed loads kick with a safe message  
- **`BindToClose`** and auto-save loop for shutdown safety  

→ [Full documentation](./DataManaging/README.md)

### [ChunkRenderer](./ChunkRenderer/) — Client map streaming

Keeps large worlds playable on client devices by loading only nearby map chunks into `Workspace`.

- **Reparent** between `ReplicatedStorage.MapAssets` and `Workspace.DynamicMap` (no `Clone()`)  
- **Hysteresis** (300 / 350 stud radii) to prevent border flicker  
- **0.5s throttle** on streaming passes to protect CPU  

→ [Full documentation](./ChunkRenderer/README.md)

---

## Repository layout

```
myrobloxscripts/
├── README.md                 ← you are here
├── DataManaging/
│   ├── README.md
│   ├── ServerStorage/
│   └── ServerScriptService/
└── ChunkRenderer/
    ├── README.md
    └── StarterPlayerScripts/
```

---

## How to use

1. Open the project folder you need (`DataManaging` or `ChunkRenderer`).
2. Follow the **Setup** section in that folder’s README.
3. Adjust constants (radii, save intervals, schema) for your game.

These modules are **building blocks**, not full games. Pair client streaming with appropriate server authority and Roblox platform features (`StreamingEnabled`, anti-cheat, etc.) as your title requires.

---

## Topics

`roblox` · `luau` · `datastore` · `game-development` · `client-optimization` · `portfolio`

---

## License

Free to use for learning and integration. Credit appreciated if you showcase this repository publicly.
