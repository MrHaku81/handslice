# engine/ – Slicing-Engine (Build + Bridge)

- `OrcaSlicer/` – Git-Submodul, OrcaSlicer-Upstream, auf festen Tag gepinnt.
- `build-headless-x86.sh` – Schritt A (anzulegen)
- `build-deps-arm64.sh` – Schritt B (anzulegen)
- `build-cli-arm64.sh` – Schritt C (anzulegen)
- `bin/` – fertige Binaries, **nicht einchecken** (`.gitignore`), über
  Release-Assets verteilen.

Reihenfolge und Nachweise: `../docs/engine-integration.md`.

Submodul einrichten (Klaus oder Claude Code, Tag vorher absprechen):

```
git submodule add https://github.com/SoftFever/OrcaSlicer engine/OrcaSlicer
cd engine/OrcaSlicer && git checkout <tag>
```
