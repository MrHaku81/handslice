// handslice-cli — Minimal headless CLI fuer OrcaSlicer libslic3r
//
// Hintergrund: OrcaSlicer v2.4.2 koppelt seine eingebaute CLI (src/OrcaSlicer.cpp)
// an wxWidgets + GLFW + slic3r/GUI (siehe docs/engine-integration.md, Blocker #1).
// Statt den Upstream zu patchen, lebt hier eine eigene Entry fuer den
// Schnittpunkt "Modell + Profil + Slicen + G-Code". Keine wxWidgets, kein
// GLFW, kein slic3r/GUI-Header. Nur die statisch gelinkten libslic3r_*-Libs.
//
// Umfang gemaess Projektvorgabe (Option F):
//   - STL und 3mf laden
//   - Profil-JSONs (machine/process/filament) laden, inherits-Kette aufloesen
//   - Modell auf Plattenmitte setzen (kein Arrange, kein PartPlate)
//   - Print::process() + export_gcode()
//   - Kennzahlen (Zeit, Filamentgewicht, Volumen) als JSON ausgeben
//
// Byte-Gleichheit mit dem Desktop-AppImage wird durch dieselbe Reihenfolge
// von Config-Merges und Modell-Positionierung angestrebt. Abweichungen aus
// PartPlate-Logik werden im Test separat dokumentiert.

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#include <boost/filesystem.hpp>
#include <boost/log/trivial.hpp>
#include <boost/log/core.hpp>
#include <boost/log/expressions.hpp>
#include <boost/log/utility/setup/common_attributes.hpp>
#include <boost/log/utility/setup/console.hpp>
#include <boost/nowide/args.hpp>

#include <tbb/global_control.h>

#include "nlohmann/json.hpp"

#include "libslic3r/libslic3r.h"
#include "libslic3r/Config.hpp"
#include "libslic3r/PrintConfig.hpp"
#include "libslic3r/Model.hpp"
#include "libslic3r/Print.hpp"
#include "libslic3r/Format/STL.hpp"
#include "libslic3r/Format/3mf.hpp"
#include "libslic3r/Format/bbs_3mf.hpp"
#include "libslic3r/GCode/GCodeProcessor.hpp"
#include "libslic3r/Utils.hpp"

using json = nlohmann::json;
namespace stdfs = std::filesystem;
using namespace Slic3r;

namespace {

struct Args {
    std::string machine;
    std::string process;
    std::vector<std::string> filaments;
    std::string resources_dir;
    std::string output_path;
    std::string input_path;
    bool quiet = false;
    bool no_center = false;
    int threads = 0;  // 0 = TBB-Default (alle Cores); >0 = Obergrenze
};

[[noreturn]] void die(const std::string& msg) {
    std::cerr << "handslice-cli: " << msg << "\n";
    std::exit(2);
}

void usage(std::ostream& os) {
    os <<
        "Usage: handslice-cli --machine <machine.json> --process <process.json>\n"
        "                     --filament <filament.json> [--filament ...]\n"
        "                     --resources <orca-resources-dir>\n"
        "                     --output <out.gcode> [--no-center] [--threads N]\n"
        "                     <input.stl|input.3mf>\n"
        "\n"
        "Minimaler Headless-Slicer gegen OrcaSlicer-libslic3r.\n"
        "Modellposition: Plattenmitte (abgeleitet aus printable_area) oder\n"
        "unveraendert mit --no-center.\n"
        "Kein Arrange, kein PartPlate, keine Thumbnails.\n"
        "\n"
        "--threads N  begrenzt die TBB-Parallelitaet auf N (N=1 serialisiert\n"
        "             alle parallel_for/parallel_reduce). Diagnostisch, um\n"
        "             TBB-reihenfolgebedingte Byte-Divergenzen auszuschliessen.\n";
}

Args parse_args(int argc, char** argv) {
    Args a;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        auto need_val = [&](const char* name) -> std::string {
            if (i + 1 >= argc) die(std::string(name) + " needs a value");
            return argv[++i];
        };
        if (arg == "--machine") a.machine = need_val("--machine");
        else if (arg == "--process") a.process = need_val("--process");
        else if (arg == "--filament") a.filaments.push_back(need_val("--filament"));
        else if (arg == "--resources") a.resources_dir = need_val("--resources");
        else if (arg == "--output") a.output_path = need_val("--output");
        else if (arg == "--quiet" || arg == "-q") a.quiet = true;
        else if (arg == "--no-center") a.no_center = true;
        else if (arg == "--threads") {
            const std::string v = need_val("--threads");
            try {
                a.threads = std::stoi(v);
            } catch (const std::exception&) {
                die("--threads needs a positive integer, got: " + v);
            }
            if (a.threads < 1) die("--threads must be >= 1");
        }
        else if (arg == "--help" || arg == "-h") { usage(std::cout); std::exit(0); }
        else if (!arg.empty() && arg[0] == '-') die("unknown flag: " + arg);
        else {
            if (!a.input_path.empty())
                die("multiple input files given; only one model supported");
            a.input_path = arg;
        }
    }
    if (a.machine.empty() || a.process.empty() || a.filaments.empty()
        || a.resources_dir.empty() || a.output_path.empty() || a.input_path.empty()) {
        usage(std::cerr);
        die("missing required argument");
    }
    return a;
}

// Resource-Index: (type, name) -> {paths…}. Scannt rekursiv die
// Vendor-Verzeichnisstruktur unter resources/profiles/<vendor>/{machine,
// process,filament}/. Liest nur die ersten paar Keys jedes JSON
// (type + name), ignoriert den Rest.
//
// Vendor-aware: Namen wie "fdm_filament_common" existieren in 40
// Vendors, mit unterschiedlichen Werten. inherits muss aus dem gleichen
// Vendor-Dir aufgeloest werden wie der Leaf, sonst zieht man z. B.
// Afinias filament_flow_ratio=1 statt Elegoos 0.98.
struct ResourceIndex {
    // Pro (type, name) alle gefundenen Pfade (mehrdeutig moeglich).
    std::unordered_map<std::string, std::vector<std::string>> map;

    static std::string make_key(const std::string& type, const std::string& name) {
        return type + std::string("\x1F") + name;
    }

    // Vendor = oberstes Verzeichnis unter resources/profiles/<X>/...
    static std::string vendor_of(const stdfs::path& p) {
        const std::string s = p.string();
        const std::string marker = "/profiles/";
        auto pos = s.find(marker);
        if (pos == std::string::npos) return {};
        pos += marker.size();
        auto end = s.find('/', pos);
        return end == std::string::npos ? std::string{} : s.substr(pos, end - pos);
    }

    void scan(const stdfs::path& root) {
        if (!stdfs::exists(root)) return;
        for (const auto& entry : stdfs::recursive_directory_iterator(root)) {
            if (!entry.is_regular_file()) continue;
            if (entry.path().extension() != ".json") continue;
            try {
                std::ifstream ifs(entry.path());
                json j;
                ifs >> j;
                if (!j.is_object()) continue;
                if (!j.contains("type") || !j.contains("name")) continue;
                const std::string type = j["type"].get<std::string>();
                const std::string name = j["name"].get<std::string>();
                map[make_key(type, name)].push_back(entry.path().string());
            } catch (...) {
                // Ignoriere nicht-Profile-JSONs (Theme, Hints, u.ä.)
            }
        }
    }

    // find() liefert den Pfad des Treffers, der im gleichen Vendor-Dir
    // wie `prefer_vendor` liegt; fehlt es dort, Fallback auf den ersten
    // gefundenen Pfad (deterministische sort-Reihenfolge).
    std::string find(const std::string& type,
                     const std::string& name,
                     const std::string& prefer_vendor) const {
        auto it = map.find(make_key(type, name));
        if (it == map.end() || it->second.empty()) return {};
        if (!prefer_vendor.empty()) {
            for (const auto& p : it->second)
                if (vendor_of(p) == prefer_vendor)
                    return p;
        }
        return it->second.front();
    }
};

// Laedt genau eine JSON-Datei in `cfg` ohne inherits-Aufloesung.
// Gibt den `inherits`-Parent-Namen zurueck, "" wenn kein Parent.
std::string load_single_profile(const std::string& path, DynamicPrintConfig& cfg) {
    ConfigSubstitutionContext subst_ctx{ ForwardCompatibilitySubstitutionRule::EnableSilent };
    std::map<std::string, std::string> key_values;
    std::string reason;
    const int rc = cfg.load_from_json(path, subst_ctx, /*load_inherits_in_config=*/false, key_values, reason);
    if (rc < 0)
        die("failed to parse config JSON " + path + ": " + reason);
    auto it = key_values.find("inherits");
    return it == key_values.end() ? std::string{} : it->second;
}

// Laedt die vollstaendige Vererbungs-Kette fuer `leaf_path`:
// Walkt die inherits-Namen bis zum Root, dann merged von Root -> Leaf in `out`.
// Reihenfolge ist wichtig: der naehere Nachfahre ueberschreibt den entfernteren
// Vorfahren, so wie Orca es ebenfalls tut.
void load_profile_chain(const std::string& type,
                        const std::string& leaf_path,
                        const ResourceIndex& index,
                        DynamicPrintConfig& out,
                        bool verbose) {
    // Vendor-Preferenz: dieselbe wie der Leaf. Vendor-common-Profile wie
    // "fdm_filament_common" gibt es 40x; wir brauchen die Elegoo-Variante
    // mit filament_flow_ratio=0.98, nicht die Afinia-Variante mit 1.
    const std::string leaf_vendor = ResourceIndex::vendor_of(leaf_path);

    // Kette von Leaf nach Root aufsammeln.
    std::vector<std::string> chain;
    chain.push_back(leaf_path);
    std::string current_path = leaf_path;
    for (int depth = 0; depth < 32; ++depth) {
        DynamicPrintConfig tmp;
        const std::string parent_name = load_single_profile(current_path, tmp);
        if (parent_name.empty()) break;
        const std::string parent_path = index.find(type, parent_name, leaf_vendor);
        if (parent_path.empty())
            die("cannot resolve inherits \"" + parent_name + "\" for type \"" + type
                + "\" (chain head: " + leaf_path + ")");
        chain.push_back(parent_path);
        current_path = parent_path;
    }
    if (verbose) {
        std::cerr << "chain [" << type << "] (root->leaf):\n";
        for (auto it = chain.rbegin(); it != chain.rend(); ++it)
            std::cerr << "  " << *it << "\n";
    }
    // Von Root (letztes Element im Vektor) nach Leaf (erstes Element) laden.
    for (auto it = chain.rbegin(); it != chain.rend(); ++it) {
        DynamicPrintConfig partial;
        load_single_profile(*it, partial);
        out.apply(partial, /*ignore_nonexistent=*/true);
    }
}

// Berechnet die Mitte des Druckbetts aus `printable_area` (ConfigOptionPoints,
// typisch viereckig; wir nehmen min+max/2 um auch nicht-rechteckige Betten
// pragmatisch zu zentrieren).
Vec3d compute_bed_center(const DynamicPrintConfig& cfg) {
    const ConfigOption* opt = cfg.option("printable_area");
    if (!opt) die("config has no printable_area – is the machine profile loaded?");
    auto* pts = dynamic_cast<const ConfigOptionPoints*>(opt);
    if (!pts || pts->values.empty())
        die("printable_area is empty or wrong type");
    Vec2d lo = pts->values.front(), hi = pts->values.front();
    for (const auto& p : pts->values) {
        lo.x() = std::min(lo.x(), p.x());
        lo.y() = std::min(lo.y(), p.y());
        hi.x() = std::max(hi.x(), p.x());
        hi.y() = std::max(hi.y(), p.y());
    }
    return Vec3d(0.5 * (lo.x() + hi.x()), 0.5 * (lo.y() + hi.y()), 0.0);
}

void setup_logging(bool quiet) {
    namespace logging = boost::log;
    logging::core::get()->set_filter(
        logging::trivial::severity >= (quiet ? logging::trivial::fatal : logging::trivial::warning));
}

json emit_statistics(const Print& print,
                     const GCodeProcessorResult& gcr,
                     const std::string& output_file) {
    const auto& stats = print.print_statistics();
    using ETM = PrintEstimatedStatistics::ETimeMode;
    const auto& modes = gcr.print_statistics.modes;

    json j;
    j["return_code"] = 0;
    j["output_file"] = output_file;
    j["estimated_time_s"] = modes.empty() ? 0.0 : modes[(int)ETM::Normal].time;
    j["estimated_time_fmt"] = stats.estimated_normal_print_time;
    j["total_filament_used_mm"] = stats.total_used_filament;
    j["total_filament_weight_g"] = stats.total_weight;
    j["total_extruded_volume_mm3"] = stats.total_extruded_volume;
    j["total_cost"] = stats.total_cost;
    j["total_toolchanges"] = stats.total_toolchanges;
    json per_filament = json::object();
    for (const auto& kv : stats.filament_stats)
        per_filament[std::to_string(kv.first)] = kv.second;
    j["filament_stats_mm"] = per_filament;
    return j;
}

}  // namespace

int main(int argc, char** argv) {
    boost::nowide::args a(argc, argv);
    Args args = parse_args(argc, argv);
    setup_logging(args.quiet);

    // TBB-Parallelitaet optional begrenzen. Muss vor dem ersten
    // parallel_for der Pipeline konstruiert werden und ueber die gesamte
    // Slice-Dauer am Leben bleiben; `global_control` ist stackbasiert.
    std::unique_ptr<tbb::global_control> tbb_limit;
    if (args.threads > 0) {
        tbb_limit = std::make_unique<tbb::global_control>(
            tbb::global_control::max_allowed_parallelism,
            static_cast<std::size_t>(args.threads));
        if (!args.quiet)
            std::cerr << "TBB max_allowed_parallelism = " << args.threads << "\n";
    }

    // Orca-Interna: Resource-Pfad bekannt machen (fuer system_paths-Default).
    set_resources_dir(args.resources_dir);

    // 1. Resource-Index aufbauen (fuer inherits-Aufloesung).
    ResourceIndex index;
    index.scan(args.resources_dir);
    if (!args.quiet)
        std::cerr << "indexed " << index.map.size() << " profile JSONs under "
                  << args.resources_dir << "\n";

    // 2. Konfig aus Full-Defaults bauen und Profile schichten.
    //    Reihenfolge wie OrcaSlicer: machine -> process -> filament.
    DynamicPrintConfig cfg;
    cfg.apply(FullPrintConfig::defaults(), /*ignore_nonexistent=*/true);
    load_profile_chain("machine", args.machine, index, cfg, !args.quiet);
    load_profile_chain("process", args.process, index, cfg, !args.quiet);
    for (const auto& fp : args.filaments)
        load_profile_chain("filament", fp, index, cfg, !args.quiet);

    // 3. Zwei Konfig-Nachsetzschritte, die Orca selbst ausserhalb von
    //    libslic3r erledigt (in Plater/OrcaSlicer.cpp), die wir hier aber
    //    nachbilden muessen, damit der G-Code mit dem GUI-Export matcht:
    //
    //    a) curr_bed_type (Enum) wird aus default_bed_type (String mit
    //       Integer-Wert) des Druckerprofils abgeleitet. Fallback btPEI,
    //       wie es Orcas Preset::get_default_bed_type auch tut.
    {
        BedType bt = BedType::btPEI;  // Default-Fallback wie Orca-GUI
        const ConfigOptionString* dbt = cfg.opt<ConfigOptionString>("default_bed_type");
        if (dbt && !dbt->value.empty()) {
            const int v = std::atoi(dbt->value.c_str());
            if (v > 0 && v < int(BedType::btCount))
                bt = BedType(v);
        }
        cfg.set_key_value("curr_bed_type", new ConfigOptionEnum<BedType>(bt));
    }

    // 4. Modell laden (STL oder 3mf).
    Model model;
    const std::string ext = stdfs::path(args.input_path).extension().string();
    if (boost::iequals(ext, ".stl")) {
        if (!load_stl(args.input_path.c_str(), &model, nullptr))
            die("failed to load STL: " + args.input_path);
        // STL hat per Design keine Instance -> eine anlegen.
        for (ModelObject* mo : model.objects)
            if (mo->instances.empty())
                mo->add_instance();
    } else if (boost::iequals(ext, ".3mf")) {
        ConfigSubstitutionContext subst_ctx{ ForwardCompatibilitySubstitutionRule::EnableSilent };
        bool is_bbl = false, is_orca = false;
        Semver file_version;
        PlateDataPtrs plates;
        if (!load_bbs_3mf(args.input_path.c_str(), nullptr, &subst_ctx, &model,
                          &plates, nullptr, &is_bbl, &is_orca, &file_version))
            die("failed to load 3mf: " + args.input_path);
    } else {
        die("unsupported input extension: " + ext + " (nur .stl/.3mf)");
    }

    // 5. Modell positionieren.
    //    Default: center_around_origin() verschiebt den BoundingBox-Mittel-
    //    punkt in den Ursprung – d. h. der Modell-Z-Mittelpunkt liegt auf
    //    z=0, nicht z_min. Danach: Instance-XY auf bed_center, Instance-Z =
    //    -min_z, damit der unterste Punkt auf z=0 landet.
    //    Mit --no-center bleibt das Modell exakt an seiner STL-Position –
    //    das ist der Pfad fuer Byte-Vergleich gegen AppImage --arrange 0.
    if (!args.no_center) {
        const Vec3d bed_center = compute_bed_center(cfg);
        for (ModelObject* mo : model.objects) {
            mo->center_around_origin(/*include_modifiers=*/true);
            const BoundingBoxf3 bb = mo->raw_mesh_bounding_box();
            const Vec3d offset(bed_center.x(), bed_center.y(), -bb.min.z());
            for (ModelInstance* mi : mo->instances)
                mi->set_offset(offset);
        }
    }

    // 6. Print aufbauen und slicen.
    //    Vendor-Flag: Orcas CLI/GUI setzen m_isBBLPrinter aus
    //    preset_bundle->is_bbl_vendor(). Fuer CC2 (Elegoo) ist das false.
    //    Default von m_isBBLPrinter in Print.hpp ist uninitialisiert –
    //    wir setzen es explizit. Ebenso GCodeProcessor::s_IsBBLPrinter
    //    (ein static mit Default true, das sonst Bambu-Stil-Marker ins
    //    G-Code wandern laesst: `; FEATURE:` statt `;TYPE:`, M624/M900
    //    statt SET_PRESSURE_ADVANCE).
    Print print;
    print.is_BBL_printer() = false;
    GCodeProcessor::s_IsBBLPrinter = false;
    print.apply(model, cfg);
    print.process();

    // 7. G-Code exportieren.
    GCodeProcessorResult gcr;
    const std::string written_path = print.export_gcode(args.output_path, &gcr, nullptr);
    if (written_path.empty())
        die("export_gcode returned empty path – nothing written");

    // 8. Kennzahlen als JSON auf stdout.
    const json out = emit_statistics(print, gcr, written_path);
    std::cout << out.dump(2) << "\n";
    return 0;
}
