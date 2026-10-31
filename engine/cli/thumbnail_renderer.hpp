// Pflicht 6 / Variant C — tiny software rasterizer for the G-code
// thumbnail. Flat-shaded, single directional light, Z-buffer. The
// renderer is intentionally minimal: pure CPU, no OpenGL/GLFW
// context (Block A ruled those out), and no dependency outside
// libslic3r's own types.
//
// Signature mirrors Orca's `ThumbnailsGeneratorCallback`: give it
// the finalised `Model` (positioned/dropped-to-bed), the active
// print config (for `filament_colour` and the bed dimensions),
// and the `ThumbnailsParams` from Orca's export pipeline; receive
// a `ThumbnailsList` with one `ThumbnailData` per requested size.
//
// Optionally takes a parallel `preview_meshes`:
//   if non-empty and the same length as `model.objects`, those
//   simplified meshes are rendered instead of the originals.
//   This is the `--simplify` path from `handslice-cli` — it must
//   never affect the slicing path (that path reads
//   `model.objects[i].volumes[j].mesh()` directly).

#pragma once

#include <libslic3r/Model.hpp>
#include <libslic3r/PrintConfig.hpp>
#include <libslic3r/GCode/ThumbnailData.hpp>
#include <libslic3r/TriangleMesh.hpp>

namespace handslice {

// Simplified pre-rendered mesh for one `ModelObject` (world space,
// instance transforms already baked in). Multiple entries per
// object are rendered in sequence — one per `ModelVolume`, each
// with the resolved filament colour.
struct PreviewMesh {
    ::indexed_triangle_set its;
    uint32_t filament_idx = 0; // index into `filament_colour`
};

// Produce one or more thumbnails for the fully-arranged model.
// `simplified_meshes` is per-object. If empty, the renderer uses
// the originals from `model`.
Slic3r::ThumbnailsList render_handslice_thumbnails(
    const Slic3r::Model&              model,
    const Slic3r::DynamicPrintConfig& print_cfg,
    const Slic3r::ThumbnailsParams&   params,
    const std::vector<std::vector<PreviewMesh>>& simplified_meshes);

// Build simplified `PreviewMesh`es for `model`, targeting
// `target_triangles` triangles per volume. Instance transforms
// are baked in. Returns one `vector<PreviewMesh>` per
// `model.objects[i]`; empty inner vector means that object had no
// volumes.
std::vector<std::vector<PreviewMesh>> build_preview_meshes(
    const Slic3r::Model&              model,
    const Slic3r::DynamicPrintConfig& print_cfg,
    uint32_t                          target_triangles);

} // namespace handslice
