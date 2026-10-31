// Pflicht 6 / Variant C — software rasterizer impl.
//
// Pipeline per requested size:
//   1. collect world-space triangles with per-triangle colour.
//      Instance transforms are baked in. If simplified meshes
//      exist, we use them (they are already baked); otherwise
//      we fold the original `ModelVolume::mesh()` through the
//      instance + volume transforms.
//   2. build an orthographic view: camera up-and-right of the
//      plate centre looking down at the model centre. Scale so
//      the model fits with a small margin.
//   3. flat-shade each triangle with a single directional light.
//   4. scan-convert into an RGBA framebuffer, resolve by Z.
//
// Deliberately no perspective: predictable sampling for CI tests
// and byte-stable across x86/arm64.

#include "thumbnail_renderer.hpp"

#include <libslic3r/QuadricEdgeCollapse.hpp>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <string>
#include <vector>

namespace handslice {

namespace {

using Slic3r::DynamicPrintConfig;
using Slic3r::Model;
using Slic3r::ModelObject;
using Slic3r::ModelInstance;
using Slic3r::ModelVolume;
using Slic3r::ThumbnailData;
using Slic3r::ThumbnailsList;
using Slic3r::ThumbnailsParams;
using Slic3r::Vec2d;
using Slic3r::Vec3d;
using Slic3r::Vec3f;
using ::indexed_triangle_set;

struct Rgba { uint8_t r, g, b, a; };
struct Vec3  { float x, y, z; };

static Vec3  v3(float x, float y, float z) { return {x, y, z}; }
static Vec3  vadd(Vec3 a, Vec3 b) { return {a.x+b.x, a.y+b.y, a.z+b.z}; }
static Vec3  vsub(Vec3 a, Vec3 b) { return {a.x-b.x, a.y-b.y, a.z-b.z}; }
static Vec3  vscale(Vec3 a, float s) { return {a.x*s, a.y*s, a.z*s}; }
static float vdot(Vec3 a, Vec3 b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
static Vec3  vcross(Vec3 a, Vec3 b) {
    return {a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x};
}
static float vlen(Vec3 a) { return std::sqrt(vdot(a, a)); }
static Vec3  vnorm(Vec3 a) {
    const float L = vlen(a); return L > 1e-12f ? vscale(a, 1.0f/L) : v3(0,0,0);
}

// Parse "#RRGGBB" or "RRGGBB" → Rgba with alpha 255. Falls back to
// orange if the string is nonsense.
static Rgba parse_hex_colour(const std::string& hex) {
    const char* s = hex.c_str();
    if (!*s) return {0xF2, 0x75, 0x4E, 0xFF};
    if (*s == '#') ++s;
    if (std::strlen(s) != 6) return {0xF2, 0x75, 0x4E, 0xFF};
    auto nib = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    };
    int rh = nib(s[0]), rl = nib(s[1]);
    int gh = nib(s[2]), gl = nib(s[3]);
    int bh = nib(s[4]), bl = nib(s[5]);
    if (rh < 0 || rl < 0 || gh < 0 || gl < 0 || bh < 0 || bl < 0)
        return {0xF2, 0x75, 0x4E, 0xFF};
    return {uint8_t(rh*16 + rl), uint8_t(gh*16 + gl),
            uint8_t(bh*16 + bl), 0xFF};
}

struct Triangle3 {
    Vec3 v[3];
    Vec3 normal; // world-space, unit length
    Rgba colour;
};

static Vec3 to_v3(const Vec3f& v) { return {v.x(), v.y(), v.z()}; }
static Vec3 to_v3(const Vec3d& v) {
    return {float(v.x()), float(v.y()), float(v.z())};
}

// Expand an `indexed_triangle_set` into world-space triangles,
// applying a 4×3 matrix (world = M * v + T).
static void push_mesh_triangles(
    const indexed_triangle_set& its,
    const Slic3r::Transform3d&  world_from_mesh,
    Rgba                        colour,
    std::vector<Triangle3>&     out)
{
    out.reserve(out.size() + its.indices.size());
    for (const auto& face : its.indices) {
        Triangle3 t{};
        for (int i = 0; i < 3; ++i) {
            const auto& local = its.vertices[face[i]];
            const Vec3d world = world_from_mesh *
                Vec3d(local.x(), local.y(), local.z());
            t.v[i] = to_v3(world);
        }
        const Vec3 a = vsub(t.v[1], t.v[0]);
        const Vec3 b = vsub(t.v[2], t.v[0]);
        t.normal = vnorm(vcross(a, b));
        t.colour = colour;
        out.push_back(t);
    }
}

struct ViewMatrix {
    // View axes in world space + camera eye in world space.
    Vec3 right, up, forward, eye;
};

// Position the camera up-right-front of the model: diagonal view,
// slight downward tilt, similar in spirit to Orca's default
// thumbnail. `focus` is the model centre, `extent` is the max
// bounding-box dimension.
static ViewMatrix make_view(Vec3 focus, float extent) {
    const float dist = extent * 1.9f + 10.0f;
    // Camera direction (eye - target), normalised. Steeper Z so
    // the top face is clearly a top face and the front/right
    // faces diverge in brightness under lighting.
    const Vec3 dir   = vnorm({0.55f, -0.90f, 0.95f});
    const Vec3 eye   = vadd(focus, vscale(dir, dist));
    const Vec3 fwd   = vnorm(vsub(focus, eye));              // -z camera
    const Vec3 world_up = {0.0f, 0.0f, 1.0f};
    const Vec3 right = vnorm(vcross(fwd, world_up));
    const Vec3 up    = vnorm(vcross(right, fwd));
    return {right, up, fwd, eye};
}

// Project a world-space point to view space. z = signed distance
// along the camera's forward axis — positive for points in front
// of the camera, more positive the further away. The rasterizer
// below picks the smallest z per pixel (`z < depth`), so this
// convention makes the closest surface win. The earlier
// `-vdot(..., forward)` form inverted the sign and let the far
// side of the model occlude the near side — exact cause of the
// "cube rendered upside-down" bug from the device test.
static Vec3 to_view(const ViewMatrix& V, Vec3 w) {
    const Vec3 d = vsub(w, V.eye);
    return { vdot(d, V.right), vdot(d, V.up), vdot(d, V.forward) };
}

// Three-component shading so a white part reads as "white" at the
// top, mid-grey on the front and clearly darker on the side —
// which was the Klaus-reported deficit of the first version
// (everything one grey tone, model indistinguishable from
// silhouette). Mix:
//   - small ambient so backfaces don't go black,
//   - strong key light near-top-down, slight front-right tilt,
//   - weak fill from behind-left to lift the shadow side.
// Weights sum ~1.08 so a well-lit flat facing the key renders at
// full base colour (clamped to 255). This is deliberately NOT
// physically-based; it's tuned so the three visible faces of a
// 20 mm cube read as distinctly separate greys under a single
// base colour.
static Rgba shade(Vec3 normal, Rgba base, Vec3 key, Vec3 fill) {
    const float cosK = std::max(0.0f, vdot(normal, key));
    const float cosF = std::max(0.0f, vdot(normal, fill));
    const float ambient      = 0.20f;
    const float keyStrength  = 0.80f;
    const float fillStrength = 0.15f;
    float k = ambient + keyStrength * cosK + fillStrength * cosF;
    if (k > 1.0f) k = 1.0f;
    return {
        uint8_t(std::min(255.0f, base.r * k)),
        uint8_t(std::min(255.0f, base.g * k)),
        uint8_t(std::min(255.0f, base.b * k)),
        0xFF,
    };
}

// Draw a triangle into (framebuffer, depth) using an orthographic
// screen projection: v[i].{x,y} are already in [0..w)×[0..h), z
// is view-space depth (lower = closer).
static void raster_triangle(
    int w, int h,
    uint8_t* fb, float* depth,
    Vec3 a, Vec3 b, Vec3 c, Rgba col)
{
    const float min_x = std::floor(std::min({a.x, b.x, c.x}));
    const float max_x = std::ceil (std::max({a.x, b.x, c.x}));
    const float min_y = std::floor(std::min({a.y, b.y, c.y}));
    const float max_y = std::ceil (std::max({a.y, b.y, c.y}));
    const int xmin = std::max(0, int(min_x));
    const int xmax = std::min(w - 1, int(max_x));
    const int ymin = std::max(0, int(min_y));
    const int ymax = std::min(h - 1, int(max_y));
    if (xmin > xmax || ymin > ymax) return;

    // Edge-function coefficients for 2D barycentric test.
    const float denom = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y);
    if (std::abs(denom) < 1e-9f) return; // degenerate
    const float inv = 1.0f / denom;

    for (int py = ymin; py <= ymax; ++py) {
        const float fy = float(py) + 0.5f;
        for (int px = xmin; px <= xmax; ++px) {
            const float fx = float(px) + 0.5f;
            const float w0 = ((b.y - c.y) * (fx - c.x) + (c.x - b.x) * (fy - c.y)) * inv;
            const float w1 = ((c.y - a.y) * (fx - c.x) + (a.x - c.x) * (fy - c.y)) * inv;
            const float w2 = 1.0f - w0 - w1;
            if (w0 < 0.0f || w1 < 0.0f || w2 < 0.0f) continue;
            const float z = w0 * a.z + w1 * b.z + w2 * c.z;
            const int off = py * w + px;
            if (z < depth[off]) {
                depth[off] = z;
                uint8_t* p = fb + off * 4;
                p[0] = col.r; p[1] = col.g; p[2] = col.b; p[3] = col.a;
            }
        }
    }
}

// Default filament_colour list (one element per filament). If the
// config carries no `filament_colour`, fall back to Orca's default
// orange so the renderer never produces a black model.
static std::vector<Rgba> read_filament_colours(
    const DynamicPrintConfig& cfg)
{
    std::vector<Rgba> out;
    const auto* opt = cfg.option<Slic3r::ConfigOptionStrings>("filament_colour");
    if (opt) {
        for (const std::string& s : opt->values) {
            out.push_back(parse_hex_colour(s));
        }
    }
    if (out.empty()) out.push_back({0xF2, 0x75, 0x4E, 0xFF});
    return out;
}

} // anon

std::vector<std::vector<PreviewMesh>> build_preview_meshes(
    const Model&              model,
    const DynamicPrintConfig& print_cfg,
    uint32_t                  target_triangles)
{
    const auto palette = read_filament_colours(print_cfg);
    std::vector<std::vector<PreviewMesh>> out;
    out.reserve(model.objects.size());

    for (const ModelObject* mo : model.objects) {
        std::vector<PreviewMesh> volumes;
        for (const ModelInstance* mi : mo->instances) {
            const auto mat_i = mi->get_matrix();
            for (const ModelVolume* mv : mo->volumes) {
                if (!mv->is_model_part()) continue;
                PreviewMesh pm;
                // World-space mesh = instance * volume * local.
                const auto mat_v = mv->get_matrix();
                const auto full  = mat_i * mat_v;
                indexed_triangle_set its = mv->mesh().its;
                // Simplify in place if asked. Guard: skip if the
                // original already has <= target.
                if (target_triangles > 0 &&
                    its.indices.size() > target_triangles) {
                    // its_quadric_edge_collapse reads *max_error as
                    // the error budget and returns early if <= 0 –
                    // so passing nullptr (= float::max) is what we
                    // want here. The earlier `float max_err = 0.0f`
                    // silently no-op'd simplification for every
                    // caller that supplied an in/out slot.
                    Slic3r::its_quadric_edge_collapse(
                        its, target_triangles, nullptr, nullptr, nullptr);
                }
                // Bake transform.
                for (auto& v : its.vertices) {
                    const Vec3d w = full *
                        Vec3d(v.x(), v.y(), v.z());
                    v = Vec3f(float(w.x()), float(w.y()), float(w.z()));
                }
                pm.its = std::move(its);
                pm.filament_idx = uint32_t(
                    std::clamp(int(mv->config.has("extruder")
                                   ? mv->config.opt_int("extruder") - 1
                                   : 0),
                               0, int(palette.size()) - 1));
                volumes.push_back(std::move(pm));
            }
        }
        out.push_back(std::move(volumes));
    }
    return out;
}

ThumbnailsList render_handslice_thumbnails(
    const Model&              model,
    const DynamicPrintConfig& print_cfg,
    const ThumbnailsParams&   params,
    const std::vector<std::vector<PreviewMesh>>& simplified_meshes)
{
    ThumbnailsList out;
    out.reserve(params.sizes.size());

    const auto palette = read_filament_colours(print_cfg);

    // Choose source triangles once (shared across all requested
    // thumbnail sizes). Order: use simplified_meshes if the
    // length matches, otherwise bake originals on the fly.
    std::vector<Triangle3> tris;
    const bool use_simplified =
        !simplified_meshes.empty() &&
        simplified_meshes.size() == model.objects.size();
    if (use_simplified) {
        Slic3r::Transform3d identity = Slic3r::Transform3d::Identity();
        for (const auto& per_obj : simplified_meshes) {
            for (const auto& pm : per_obj) {
                Rgba col = pm.filament_idx < palette.size()
                           ? palette[pm.filament_idx]
                           : palette.front();
                push_mesh_triangles(pm.its, identity, col, tris);
            }
        }
    } else {
        for (const ModelObject* mo : model.objects) {
            for (const ModelInstance* mi : mo->instances) {
                const auto mat_i = mi->get_matrix();
                for (const ModelVolume* mv : mo->volumes) {
                    if (!mv->is_model_part()) continue;
                    const auto mat_v = mv->get_matrix();
                    const auto full  = mat_i * mat_v;
                    const uint32_t idx = uint32_t(
                        std::clamp(int(mv->config.has("extruder")
                                       ? mv->config.opt_int("extruder") - 1
                                       : 0),
                                   0, int(palette.size()) - 1));
                    push_mesh_triangles(mv->mesh().its, full,
                                        palette[idx], tris);
                }
            }
        }
    }

    if (tris.empty()) {
        // No geometry — still emit well-formed empty thumbnails
        // for each requested size, so the firmware parser is
        // happy. Fully transparent (clear alpha).
        for (const Vec2d& size : params.sizes) {
            ThumbnailData td;
            td.set(unsigned(std::lround(size.x())),
                   unsigned(std::lround(size.y())));
            for (size_t i = 0; i < td.pixels.size(); i += 4) {
                td.pixels[i+0] = 0; td.pixels[i+1] = 0;
                td.pixels[i+2] = 0; td.pixels[i+3] = 0;
            }
            out.push_back(std::move(td));
        }
        return out;
    }

    // World-space bounding box of all triangles.
    Vec3 mn{+std::numeric_limits<float>::infinity(),
            +std::numeric_limits<float>::infinity(),
            +std::numeric_limits<float>::infinity()};
    Vec3 mx{-std::numeric_limits<float>::infinity(),
            -std::numeric_limits<float>::infinity(),
            -std::numeric_limits<float>::infinity()};
    for (const auto& t : tris) for (int i = 0; i < 3; ++i) {
        mn.x = std::min(mn.x, t.v[i].x); mn.y = std::min(mn.y, t.v[i].y); mn.z = std::min(mn.z, t.v[i].z);
        mx.x = std::max(mx.x, t.v[i].x); mx.y = std::max(mx.y, t.v[i].y); mx.z = std::max(mx.z, t.v[i].z);
    }
    const Vec3 focus = vscale(vadd(mn, mx), 0.5f);
    const float extent = std::max(mx.x - mn.x,
                           std::max(mx.y - mn.y, mx.z - mn.z));

    const ViewMatrix V = make_view(focus, extent);
    // Two directional lights for the shader (see shade()).
    const Vec3 key_light  = vnorm({0.15f, -0.35f, 0.95f}); // near-top-down
    const Vec3 fill_light = vnorm({-0.60f,  0.40f, 0.20f}); // behind-left
    // Pre-project triangles to view space once; this is shared
    // across all requested sizes.
    //
    // Normal-orientation note: STLs don't guarantee a consistent
    // triangle winding, so our `vcross(a-v0, b-v0)` normals point
    // outward for some triangles and inward for others. Lambert
    // over the raw normal then kept half the surface in ambient
    // only — the exact "white model stays dark grey" bug from
    // the first device test. Fix: orient each triangle's normal
    // toward the camera (the visible side is by definition the
    // one facing us), so Lambert against the key light has
    // predictable sign.
    struct ViewTri {
        Vec3 v[3];
        float min_vx, max_vx, min_vy, max_vy;
        Rgba shaded;
    };
    std::vector<ViewTri> vtris;
    vtris.reserve(tris.size());
    float vxmin = +std::numeric_limits<float>::infinity();
    float vxmax = -std::numeric_limits<float>::infinity();
    float vymin = +std::numeric_limits<float>::infinity();
    float vymax = -std::numeric_limits<float>::infinity();
    for (const auto& t : tris) {
        ViewTri vt;
        for (int i = 0; i < 3; ++i) vt.v[i] = to_view(V, t.v[i]);
        vt.min_vx = std::min({vt.v[0].x, vt.v[1].x, vt.v[2].x});
        vt.max_vx = std::max({vt.v[0].x, vt.v[1].x, vt.v[2].x});
        vt.min_vy = std::min({vt.v[0].y, vt.v[1].y, vt.v[2].y});
        vt.max_vy = std::max({vt.v[0].y, vt.v[1].y, vt.v[2].y});
        // Orient the per-triangle normal to face the camera.
        const Vec3 tri_center = vscale(
            vadd(vadd(t.v[0], t.v[1]), t.v[2]), 1.0f / 3.0f);
        const Vec3 to_cam = vnorm(vsub(V.eye, tri_center));
        Vec3 oriented = t.normal;
        if (vdot(oriented, to_cam) < 0.0f) oriented = vscale(oriented, -1.0f);
        vt.shaded = shade(oriented, t.colour, key_light, fill_light);
        vtris.push_back(vt);
        vxmin = std::min(vxmin, vt.min_vx); vxmax = std::max(vxmax, vt.max_vx);
        vymin = std::min(vymin, vt.min_vy); vymax = std::max(vymax, vt.max_vy);
    }

    const float margin = 0.08f; // 8 % border on each side

    for (const Vec2d& size : params.sizes) {
        const int W = int(std::lround(size.x()));
        const int H = int(std::lround(size.y()));
        ThumbnailData td;
        td.set(unsigned(W), unsigned(H));
        std::vector<float> depth(W * H,
            std::numeric_limits<float>::infinity());

        // Background: fully transparent, same as Orca's GUI
        // export (see docs/preview-research.md "What a real CC2
        // G-code actually contains"). This lets the firmware /
        // display composite the thumbnail onto any theme, and
        // keeps bright models (white, light grey) distinguishable
        // from the display background.
        // NOTE: `ThumbnailData::set()` initialises the pixel
        // buffer with 0xFF (opaque white — Orca default); we
        // overwrite it here to transparent-black so background
        // pixels we never touch report alpha=0.
        for (int i = 0; i < W * H; ++i) {
            uint8_t* p = td.pixels.data() + i * 4;
            p[0] = 0; p[1] = 0; p[2] = 0; p[3] = 0;
        }

        // Orthographic scale: fit view bbox into (W, H) with
        // margin. Preserve aspect ratio by taking the min of X
        // and Y scales. Y screen axis grows downward.
        const float ex = vxmax - vxmin;
        const float ey = vymax - vymin;
        const float sx = (W * (1.0f - 2.0f * margin)) / std::max(ex, 1e-6f);
        const float sy = (H * (1.0f - 2.0f * margin)) / std::max(ey, 1e-6f);
        const float s  = std::min(sx, sy);
        const float cx = (vxmin + vxmax) * 0.5f;
        const float cy = (vymin + vymax) * 0.5f;

        for (const auto& vt : vtris) {
            // Pixel-buffer convention: `ThumbnailData::pixels` is
            // the glReadPixels layout (row 0 = BOTTOM of the
            // image). Orca's compress_thumbnail_* then flips the
            // buffer vertically before encoding to PNG/JPG/QOI
            // (Thumbnails.cpp:55/109/146 "flip the image
            // vertically"). We therefore map world-Y DIRECTLY to
            // pixel-Y (no inversion): higher world-Y → higher
            // pixel-Y → closer to the bottom-of-buffer that will
            // become top-of-image after Orca's flip.
            Vec3 a = { (vt.v[0].x - cx) * s + W * 0.5f,
                       (vt.v[0].y - cy) * s + H * 0.5f,
                       vt.v[0].z };
            Vec3 b = { (vt.v[1].x - cx) * s + W * 0.5f,
                       (vt.v[1].y - cy) * s + H * 0.5f,
                       vt.v[1].z };
            Vec3 c = { (vt.v[2].x - cx) * s + W * 0.5f,
                       (vt.v[2].y - cy) * s + H * 0.5f,
                       vt.v[2].z };
            raster_triangle(W, H, td.pixels.data(), depth.data(),
                            a, b, c, vt.shaded);
        }
        out.push_back(std::move(td));
    }
    return out;
}

} // namespace handslice
