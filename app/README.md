# app/ – Frontend

Mobiler Frontend-Code. **Bleibt leer, bis der UI-Stack entschieden ist**
(Flutter vs. Compose – `docs/architecture.md`, Entscheidung in `PROGRESS.md`).

Erwartet danach:
- Settings-UI dynamisch aus Orca-Profil-JSONs.
- 3D-Viewport + Preview.
- Engine-Bridge: Phase 0 HTTP-Client gegen `../server/`, Phase 1 Aufruf des
  gebündelten CLI-Binaries.
- Netzwerk-Modul mit `MoonrakerClient` / `ElegooClient`
  (`../docs/networking-cc2.md`).
