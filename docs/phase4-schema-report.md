# Phase 4.1 – Einstellungsbaum: Schema-Report

- OrcaSlicer-Version (aus `--dump-schema`): `02.06.00.51`
- Options-Definitionen gesamt (print_config_def.options): **751**
- Layout-Quelle: `src/slic3r/GUI/Tab.cpp` (Tag `v2.4.2`)
- Uebersetzungs-Quelle: `OrcaSlicer_de.po` mit **5491** Eintraegen

## Zuordnung aus Tab.cpp (mechanisch extrahiert)

| Bereich | Reiter | Gruppen | Options (einzigartig) |
|---|---|---|---|
| print | 6 | 41 | 337 |
| filament | 7 | 22 | 83 |
| printer | 4 | 29 | 73 |

### Reiter + Gruppen je Bereich

**print**
- Quality (de: Qualität)  _Tab.cpp:2317_
  - Layer height (de: Schichthöhe)  — 2 keys  _:2318_
  - Line width (de: Breite der Linie)  — 9 keys  _:2322_
  - Seam (de: Naht)  — 18 keys  _:2333_
  - Precision (de: Präzision)  — 13 keys  _:2354_
  - Ironing (de: Glätten)  — 7 keys  _:2369_
  - Z contouring (de: Z-Konturierung)  — 4 keys  _:2378_
  - Wall generator (de: Wandgenerator)  — 11 keys  _:2386_
  - Walls and surfaces (de: Wände und Oberflächen)  — 22 keys  _:2399_
  - Bridging (de: Brücken)  — 9 keys  _:2429_
  - Overhangs (de: Überhänge)  — 8 keys  _:2440_
- Strength (de: Struktur)  _Tab.cpp:2450_
  - Walls (de: Wände)  — 3 keys  _:2451_
  - Top/bottom shells (de: Obere/Untere Schichten)  — 9 keys  _:2456_
  - Infill (de: Füllung)  — 28 keys  _:2468_
  - Advanced (de: Erweiterte Einstellungen)  — 10 keys  _:2498_
- Speed (de: Geschwindigkeit)  _Tab.cpp:2510_
  - First layer speed (de: Geschwindigkeit der ersten Schicht)  — 4 keys  _:2511_
  - Other layers speed (de: Geschwindigkeit der restlichen Schichten)  — 11 keys  _:2516_
  - Overhang speed (de: Überhanggeschwindigkeit)  — 8 keys  _:2528_
  - Travel speed (de: Fahrgeschwindigkeit)  — 1 keys  _:2545_
  - Acceleration (de: Beschleunigung)  — 12 keys  _:2548_
  - Junction Deviation (de: Junction-Deviation)  — 1 keys  _:2562_
  - Jerk(XY) (de: Jerk(XY))  — 8 keys  _:2565_
  - Advanced (de: Erweiterte Einstellungen)  — 3 keys  _:2575_
- Support (de: Stützen)  _Tab.cpp:2580_
  - Support (de: Stützen)  — 10 keys  _:2581_
  - Raft (de: Druckbasis (Raft))  — 2 keys  _:2594_
  - Support filament (de: Supportfilament)  — 3 keys  _:2598_
  - Support ironing (de: Unterstützungs-Glätten)  — 4 keys  _:2603_
  - Advanced (de: Erweiterte Einstellungen)  — 17 keys  _:2612_
  - Tree supports (de: Baumstützen)  — 12 keys  _:2633_
- Multimaterial (de: Multimaterial)  _Tab.cpp:2647_
  - Prime tower (de: Reinigungsturm)  — 21 keys  _:2648_
  - Filament for Features (de: Filament für Funktionen)  — 7 keys  _:2671_
  - Ooze prevention (de: Ooze-Prävention)  — 4 keys  _:2680_
  - Flush options (de: Optionen für die Düsenreinigung)  — 3 keys  _:2686_
  - Advanced (de: Erweiterte Einstellungen)  — 9 keys  _:2690_
- Others (de: Sonstiges)  _Tab.cpp:2701_
  - Skirt (de: Saum)  — 9 keys  _:2702_
  - Brim (de: Umrandung)  — 8 keys  _:2713_
  - Special mode (de: Spezialmodus)  — 10 keys  _:2723_
  - Fuzzy Skin (de: Fuzzy Skin)  — 12 keys  _:2736_
  - G-code output (de: G-Code-Ausgabe)  — 5 keys  _:2750_
  - Change extrusion role G-code (de: Ändere den G-Code der Extrusionsart)  — 0 keys  _:2763_
  - Post-processing Scripts (de: Nachbearbeitungsskripte)  — 0 keys  _:2774_
  - Notes (de: Notizen)  — 0 keys  _:2781_

**filament**
- Filament (de: Filament)  _Tab.cpp:3897_
  - Basic information (de: Grundlegende Informationen)  — 16 keys  _:3899_
  - Flow ratio and Pressure Advance (de: Flussverhältnis und Pressure Advance)  — 7 keys  _:3936_
  - Print chamber temperature (de: Druckkammertemperatur)  — 3 keys  _:3955_
  - Print temperature (de: Drucktemperatur)  — 0 keys  _:3981_
  - Bed temperature (de: Druckbetttemperatur)  — 12 keys  _:3988_
  - Volumetric speed limitation (de: Volumetrische Geschwindigkeitsbegrenzung)  — 2 keys  _:4059_
- Cooling (de: Kühlung)  _Tab.cpp:4070_
  - Cooling for specific layer (de: Kühlung für eine bestimmte Schicht)  — 2 keys  _:4078_
  - Part cooling fan (de: Bauteillüfter)  — 14 keys  _:4082_
  - Auxiliary part cooling fan (de: Hilfslüfter)  — 1 keys  _:4105_
  - Exhaust fan (de: Abluftventilator)  — 5 keys  _:4108_
- Advanced (de: Erweiterte Einstellungen)  _Tab.cpp:4131_
  - Filament start G-code (de: Filament Start G-Code)  — 0 keys  _:4132_
  - Change extrusion role G-code (de: Ändere den G-Code der Extrusionsart)  — 0 keys  _:4143_
  - Filament end G-code (de: Filament End G-Code)  — 0 keys  _:4154_
- Multimaterial (de: Multimaterial)  _Tab.cpp:4165_
  - Wipe tower parameters (de: Reinigungsturm-Parameter)  — 6 keys  _:4166_
  - Multi Filament (de: Multi-Filament)  — 2 keys  _:4174_
  - Tool change parameters with single extruder MM printers (de: Toolchange-Parameter bei Single-Extruder-MM-Druckern)  — 10 keys  _:4180_
  - Tool change parameters with multi extruder MM printers (de: Toolchange-Parameter bei Multi-Extruder-MM-Druckern)  — 3 keys  _:4210_
- Dependencies (de: Abhängigkeiten)  _Tab.cpp:4215_
  - Compatible printers (de: Kompatible Drucker)  — 0 keys  _:4216_
  - Compatible process profiles (de: Kompatible Prozessprofile)  — 0 keys  _:4225_
- Notes (de: Notizen)  _Tab.cpp:4234_
  - Notes (de: Notizen)  — 0 keys  _:4235_
- Setting Overrides (de: Überschreiben der Einstellungen)  _Tab.cpp:3623_
  - Retraction (de: Rückzug)  — 0 keys  _:3627_
  - Ironing (de: Glätten)  — 0 keys  _:3685_

**printer**
- Basic information (de: Grundlegende Informationen)  _Tab.cpp:4475_
  - Printable space (de: Druckbarer Raum)  — 6 keys  _:4476_
  - Advanced (de: Erweiterte Einstellungen)  — 11 keys  _:4493_
  - Cooling Fan (de: Kühlung)  — 4 keys  _:4551_
  - Extruder Clearance (de: Freiraum des Extruders)  — 3 keys  _:4561_
  - Adaptive bed mesh (de: Adaptives Bett Gitter)  — 4 keys  _:4566_
  - Accessory (de: Zubehör)  — 5 keys  _:4572_
- Machine G-code (de: Maschinen G-Code)  _Tab.cpp:4583_
  - File header G-code (de: Datei Header G-Code)  — 0 keys  _:4584_
  - Machine start G-code (de: Maschinen Start G-Code)  — 0 keys  _:4595_
  - Machine end G-code (de: Maschine Ende G-Code)  — 0 keys  _:4606_
  - Printing by object G-code (de: Drucken nach Objekt G-Code)  — 0 keys  _:4617_
  - Before layer change G-code (de: G-Code vor dem Schichtwechsel)  — 0 keys  _:4629_
  - Layer change G-code (de: Schichtwechsel G-Code)  — 0 keys  _:4640_
  - Timelapse G-code (de: Zeitraffer G-Code)  — 0 keys  _:4651_
  - Clumping Detection G-code (de: Klumpenerkennungs-G-Code)  — 0 keys  _:4662_
  - Change filament G-code (de: Filamentwechsel G-Code)  — 0 keys  _:4673_
  - Change extrusion role G-code (de: Ändere den G-Code der Extrusionsart)  — 0 keys  _:4684_
  - Pause G-code (de: Pausen G-Code)  — 0 keys  _:4695_
  - Template Custom G-code (de: Vorlage Benutzerdefinierter G-Code)  — 0 keys  _:4705_
- Notes (de: Notizen)  _Tab.cpp:4715_
  - Notes (de: Notizen)  — 0 keys  _:4716_
- Multimaterial (de: Multimaterial)  _Tab.cpp:4964_
  - Single extruder multi-material setup (de: Single-Extruder-Multimaterial-Einstellung)  — 3 keys  _:4965_
  - Wipe tower (de: Reinigungsturm)  — 4 keys  _:5052_
  - Single extruder multi-material parameters (de: Single-Extruder-Multimaterial-Parameter)  — 5 keys  _:5059_
  - Advanced (de: Erweiterte Einstellungen)  — 3 keys  _:5066_
  - Basic information (de: Grundlegende Informationen)  — 3 keys  _:5082_
  - Layer height limits (de: Höhenbegrenzungen für Schichten)  — 2 keys  _:5130_
  - Position (de: Position)  — 1 keys  _:5134_
  - Retraction (de: Rückzug)  — 9 keys  _:5138_
  - Z-Hop (de: Z-Hop)  — 6 keys  _:5149_
  - Retraction when switching material (de: Rückzug bei Materialwechsel)  — 4 keys  _:5157_

## Verteilung nach Stufe (ConfigOptionMode)

Werte aus `libslic3r/Config.hpp:199-204`: `comSimple=0, comAdvanced=1, comExpert=2, comDevelop=3`.

| Bereich | Simple | Advanced | Expert | Develop | Σ |
|---|---:|---:|---:|---:|---:|
| print | 50 | 274 | 11 | 2 | 337 |
| filament | 38 | 43 | 0 | 2 | 83 |
| printer | 5 | 63 | 0 | 5 | 73 |

## Nicht zuordenbare Optionen (im Schema, nicht im Tab.cpp-Layout)

Gesamt: **258** von 751.

### Unbenutzt in Tab.cpp (printer_technology=FFF, category='')  (91)
  adaptive_pressure_advance_model, additional_fan_full_speed_layer, bbl_calib_mark_logo, close_additional_fan_first_x_layers, compatible_printers, compatible_printers_condition, compatible_prints, compatible_prints_condition, curr_bed_type, default_bed_type, default_filament_profile, default_nozzle_volume_type, default_print_profile, enable_filament_dynamic_map, extruder_ams_count, extruder_colour, extruder_type, extruder_variant_list, filament_colour, filament_cooling_before_tower, … (+71)

### SLA-only (nicht FFF)  (76)
  absolute_correction, area_fill, bottle_cost, bottle_volume, bottle_weight, default_sla_material_profile, default_sla_print_profile, display_height, display_mirror_x, display_mirror_y, display_orientation, display_pixels_x, display_pixels_y, display_width, elefant_foot_min_width, exposure_time, faded_layers, fast_tilt_time, gamma_correction, hollowing_closing_distance, … (+56)

### Ohne Label (interne/legacy option)  (40)
  calib_flowrate_topinfill_special_order, compatible_machine_expression_group, compatible_process_expression_group, different_settings_to_system, enable_long_retraction_when_cut, enforce_support_layers, filament_colour_type, filament_ids, filament_multi_colour, filament_settings_id, has_scarf_joint_seam, inherits_group, machine_max_acceleration_e, machine_max_acceleration_extruding, machine_max_acceleration_retracting, machine_max_acceleration_travel, machine_max_acceleration_x, machine_max_acceleration_y, machine_max_acceleration_z, machine_max_jerk_e, … (+20)

### Unbenutzt in Tab.cpp (printer_technology=any, category='')  (20)
  bed_custom_model, bed_custom_texture, bed_exclude_area, extruder_printable_area, flashforge_serial_number, parallel_printheads_bed_exclude_areas, preset_names, print_host, print_host_webui, printable_area, printer_agent, printer_technology, printhost_apikey, printhost_authorization_type, printhost_cafile, printhost_password, printhost_port, printhost_ssl_ignore_revoke, printhost_user, support_parallel_printheads

### G-Code-Templates (gehen separat in Drucker-Reiter)  (17)
  before_layer_change_gcode, change_extrusion_role_gcode, change_filament_gcode, emit_machine_limits_to_gcode, filament_change_extrusion_role_gcode, filament_end_gcode, filament_start_gcode, file_start_gcode, layer_change_gcode, machine_end_gcode, machine_pause_gcode, machine_start_gcode, printing_by_object_gcode, process_change_extrusion_role_gcode, template_custom_gcode, time_lapse_gcode, wrapping_detection_gcode

### Unbenutzt in Tab.cpp (printer_technology=FFF, category='Quality')  (6)
  filament_ironing_flow, filament_ironing_inset, filament_ironing_spacing, first_layer_sequence_choice, ironing_expansion, other_layers_sequence_choice

### Unbenutzt in Tab.cpp (printer_technology=FFF, category='Support')  (3)
  raft_expansion, support_interface_loop_pattern, tree_support_with_infill

### Thumbnails (werden ueber 3mf-Pipeline erzeugt, nicht als Nutzer-Setting)  (2)
  thumbnails, thumbnails_format

### Brim (ggf. hinter Toggle in UI, nicht als Page)  (1)
  brim_ears

### Unbenutzt in Tab.cpp (printer_technology=FFF, category='Extruders')  (1)
  extruder

### Unbenutzt in Tab.cpp (printer_technology=FFF, category='Speed')  (1)
  filament_ironing_speed

## Uebersetzungsabdeckung Deutsch

Nur Options, die im Tab.cpp-Layout verwendet werden (= im App-UI sichtbar).

| Bereich | Label (de/en) | Tooltip (de/en) | Reiter-Namen (de/en) | Gruppen-Namen (de/en) |
|---|---|---|---|---|
| print | 333/337 (99%) | 333/333 (100%) | 6/6 (100%) | 41/41 (100%) |
| filament | 80/81 (99%) | 78/79 (99%) | 7/7 (100%) | 22/22 (100%) |
| printer | 71/72 (99%) | 70/71 (99%) | 4/4 (100%) | 29/29 (100%) |

## Gruppen ohne Keys (Tab.cpp fuehrt die Felder nicht per `append_single_option_line`)

Betrifft die G-Code-Textfeld-Gruppen im Drucker-Reiter und analoge
Gruppen im Filament-Reiter (Change extrusion role G-code, Post-
processing Scripts, Notes). Dort werden Textboxen ueber einen
eigenen Code-Pfad in Tab.cpp aufgebaut (nicht ueber den normalen
Options-Pfad). Fuer die App-UI in Phase 4.2/4.3 brauchen wir diese
Felder spaeter explizit – sie sind nicht verloren, sondern bewusst
in einer anderen Zelle in Tab.cpp verdrahtet.

**print**: 3 Gruppe(n) ohne Keys
- Others > Change extrusion role G-code  _:2763_
- Others > Post-processing Scripts  _:2774_
- Others > Notes  _:2781_

**filament**: 9 Gruppe(n) ohne Keys
- Filament > Print temperature  _:3981_
- Advanced > Filament start G-code  _:4132_
- Advanced > Change extrusion role G-code  _:4143_
- Advanced > Filament end G-code  _:4154_
- Dependencies > Compatible printers  _:4216_
- Dependencies > Compatible process profiles  _:4225_
- Notes > Notes  _:4235_
- Setting Overrides > Retraction  _:3627_
- Setting Overrides > Ironing  _:3685_

**printer**: 13 Gruppe(n) ohne Keys
- Machine G-code > File header G-code  _:4584_
- Machine G-code > Machine start G-code  _:4595_
- Machine G-code > Machine end G-code  _:4606_
- Machine G-code > Printing by object G-code  _:4617_
- Machine G-code > Before layer change G-code  _:4629_
- Machine G-code > Layer change G-code  _:4640_
- Machine G-code > Timelapse G-code  _:4651_
- Machine G-code > Clumping Detection G-code  _:4662_
- Machine G-code > Change filament G-code  _:4673_
- Machine G-code > Change extrusion role G-code  _:4684_
- Machine G-code > Pause G-code  _:4695_
- Machine G-code > Template Custom G-code  _:4705_
- Notes > Notes  _:4716_

## Options-Zahl im Layout vs. Schema

- Schema (print_config_def.options): **751**
- Im Layout verwendet (einzigartige Keys ueber alle Bereiche): **493**
- Nicht zuordenbar: **258** (Gruende: siehe Abschnitt oben)
