import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../engine/slicer.dart';
import '../l10n/app_localizations.dart';
import '../settings/filament_mapping.dart';
import '../settings/filament_overrides.dart';
import '../settings/profile_reader.dart';
import '../settings/settings_overrides.dart';
import '../state/printer_state.dart';
import '../state/project_state.dart';
import '../theme/workshop_theme.dart';
import '../widgets/build_info_badge.dart';
import '../widgets/printer_panel.dart';
import '../widgets/workshop_card.dart';
import '../widgets/workshop_row.dart';

class ProjectScreen extends StatefulWidget {
  const ProjectScreen({
    super.key,
    required this.slicer,
    required this.projectState,
    required this.printerState,
    required this.overrides,
    required this.filamentOverrides,
  });

  final SlicerService slicer;
  final ProjectState projectState;
  final PrinterState printerState;
  final SettingsOverrides overrides;
  final FilamentOverrides filamentOverrides;

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  List<SavedProfile> _profiles = const [];

  @override
  void initState() {
    super.initState();
    widget.projectState.addListener(_onStateChanged);
    _reloadProfiles();
  }

  @override
  void dispose() {
    widget.projectState.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reloadProfiles() async {
    final list = await const ProfileReader().list();
    if (!mounted) return;
    setState(() => _profiles = list);
    // Beim ersten Build: falls ein Profil als aktiv gespeichert ist,
    // dessen Overrides in `SettingsOverrides` einspielen – aber nur,
    // wenn die aktuellen Overrides leer sind (sonst wuerde man einen
    // laufenden Nutzer-Zustand ueberschreiben).
    final slug = widget.projectState.activeProfileSlug;
    if (slug != null && slug.isNotEmpty && widget.overrides.isEmpty) {
      final match = list.where((p) => _slugify(p.name) == slug).toList();
      if (match.isNotEmpty) _applyProfile(match.first);
    }
  }

  // Muss exakt mit ProfileWriter._slugify uebereinstimmen.
  static String _slugify(String s) {
    final down = s.toLowerCase();
    final out = StringBuffer();
    for (final cu in down.runes) {
      final c = String.fromCharCode(cu);
      if (RegExp(r'[a-z0-9]').hasMatch(c)) {
        out.write(c);
      } else if (RegExp(r'[\s_\-\.]').hasMatch(c)) {
        out.write('-');
      }
    }
    final cleaned = out.toString().replaceAll(RegExp(r'-+'), '-');
    return cleaned.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  void _applyProfile(SavedProfile p) {
    // applyProfile setzt Baseline + Werte in einem Rutsch (Orca-Verhalten):
    // "N Ueberschreibungen" ist danach 0, Reset zeigt auf Profil-Wert.
    widget.overrides.applyProfile(p.overrides);
  }

  String _activeProfileLabel(AppLocalizations l) {
    final slug = widget.projectState.activeProfileSlug;
    if (slug == null || slug.isEmpty) {
      return '0.20mm Standard @Elegoo CC2 0.4 nozzle';
    }
    final match = _profiles.where((p) => _slugify(p.name) == slug).toList();
    if (match.isEmpty) {
      return l.projectProfileMissing(slug);
    }
    return match.first.name;
  }

  Future<void> _openProfilePicker() async {
    await _reloadProfiles(); // frischen Stand holen, falls jemand gespeichert hat
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final current = widget.projectState.activeProfileSlug;
    final chosen = await showDialog<_PickerResult>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: Text(l.projectProfilePickTitle),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx,
                  const _PickerResult(reset: true)),
              child: Row(
                children: [
                  Icon(current == null ? Icons.radio_button_checked
                                        : Icons.radio_button_unchecked, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l.projectProfileStandard)),
                ],
              ),
            ),
            if (_profiles.isNotEmpty) const Divider(height: 0),
            for (final p in _profiles)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, _PickerResult(profile: p)),
                child: Row(
                  children: [
                    Icon(_slugify(p.name) == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(p.name)),
                    Text('${p.overrides.length}',
                        style: Theme.of(ctx).textTheme.bodySmall),
                  ],
                ),
              ),
            if (_profiles.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Text(l.projectProfilePickEmpty,
                    style: Theme.of(ctx).textTheme.bodySmall),
              ),
          ],
        );
      },
    );
    if (chosen == null || !mounted) return;
    if (chosen.reset) {
      widget.overrides.clearProfile();
      await widget.projectState.setActiveProfileSlug(null);
    } else if (chosen.profile != null) {
      _applyProfile(chosen.profile!);
      await widget.projectState.setActiveProfileSlug(_slugify(chosen.profile!.name));
    }
  }

  Future<void> _pickModel() async {
    // file_picker 13.x: statische pickFile(), liefert PlatformFile? direkt.
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['stl', '3mf', 'STL', '3MF'],
    );
    if (!mounted || f == null || f.path == null) return;
    widget.projectState.setModel(f.path!);
  }

  Future<void> _slice() async {
    final state = widget.projectState;
    if (state.modelPath == null) return;
    final dir = await getApplicationSupportDirectory();
    final outPath = '${dir.path}/handslice_project.gcode';
    _lastOutPath = outPath;

    // Phase 4.4: Fach → Filamentprofil-Pfad + Fach-spezifische Overrides.
    final tray = widget.printerState.trayAssignmentForTool0;
    final slot = widget.printerState.slots
        .where((s) => s.trayId == tray)
        .toList();
    String? filamentRelative;
    if (slot.isNotEmpty) {
      final ref = const FilamentMapping().resolve(
        filamentName: slot.first.filamentName,
        filamentType: slot.first.filamentType,
      );
      filamentRelative = 'profiles/Elegoo/filament/ECC2/${ref.assetName}';
    }
    final filamentOv = widget.filamentOverrides.forTray(tray);

    await state.slice(
      widget.slicer,
      outPath,
      overrides: widget.overrides,
      filamentOverrides: filamentOv,
      filamentProfileRelative: filamentRelative,
    );
  }

  String? _lastOutPath;

  Future<void> _cancel() async {
    await widget.projectState.cancelSlice(cleanupOutputPath: _lastOutPath);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = widget.projectState;

    final modelName = state.modelPath == null
        ? l.projectEmptyModel
        : state.modelPath!.split('/').last;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: ListView(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(l.projectHeading,
                    style: theme.textTheme.headlineMedium),
              ),
              const BuildInfoBadge(),
            ],
          ),
          const SizedBox(height: 12),

          WorkshopCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WorkshopRow(label: l.projectModelFile, value: modelName, mono: true),
                const Divider(),
                WorkshopRow(
                  label: l.projectPrinter,
                  value: 'Elegoo Centauri Carbon 2 — 0.4 nozzle',
                ),
                const Divider(),
                InkWell(
                  onTap: _openProfilePicker,
                  borderRadius: BorderRadius.circular(WorkshopTokens.radiusSmall),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.projectProfile,
                                  style: theme.textTheme.bodySmall),
                              const SizedBox(height: 4),
                              Text(
                                _activeProfileLabel(l),
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.projectPlate, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 6),
                      _PlateChooser(
                        value: state.bedType,
                        onChanged: state.setBedType,
                        textured: l.projectPlateTextured,
                        smooth: l.projectPlateSmooth,
                      ),
                    ],
                  ),
                ),
                const Divider(),
                _ZOffsetRow(state: state),
              ],
            ),
          ),

          const SizedBox(height: 12),
          PrinterPanel(printer: widget.printerState),

          if (state.isSlicing) ...[
            const SizedBox(height: 12),
            _SlicingProgress(
              startedAt: state.sliceStartedAt,
              cancelRequested: state.cancelRequested,
              onCancel: _cancel,
            ),
          ],
          if (state.lastError != null) ...[
            const SizedBox(height: 12),
            _ErrorBox(message: _formatSliceError(context, state.lastError!)),
          ],
          if (state.lastSlice != null) ...[
            const SizedBox(height: 12),
            _SliceSummary(result: state.lastSlice!),
          ],

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isSlicing ? null : _pickModel,
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(l.projectOpenModel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (state.modelPath == null || state.isSlicing)
                      ? null
                      : _slice,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(l.projectSliceButton),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatSliceError(BuildContext context, String raw) {
  final l = AppLocalizations.of(context);
  if (raw == 'slice.oom') return l.sliceErrorOom;
  if (raw.startsWith('slice.error:')) {
    final parts = raw.split(':');
    return l.sliceErrorExit(parts.length > 1 ? parts[1] : '?',
        parts.length > 2 ? parts.sublist(2).join(':') : '');
  }
  return raw;
}

class _SlicingProgress extends StatefulWidget {
  const _SlicingProgress({
    required this.startedAt,
    required this.cancelRequested,
    required this.onCancel,
  });
  final DateTime? startedAt;
  final bool cancelRequested;
  final VoidCallback onCancel;

  @override
  State<_SlicingProgress> createState() => _SlicingProgressState();
}

class _SlicingProgressState extends State<_SlicingProgress> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final secs = widget.startedAt == null
        ? 0
        : DateTime.now().difference(widget.startedAt!).inSeconds;
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    return WorkshopCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.cancelRequested
                        ? l.sliceCancelling
                        : l.sliceInProgress(mm, ss),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed:
                      widget.cancelRequested ? null : widget.onCancel,
                  icon: const Icon(Icons.cancel_outlined),
                  label: Text(l.sliceCancel),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

String _formatZ(double mm) {
  final sign = mm >= 0 ? '+' : '−';
  return '$sign${mm.abs().toStringAsFixed(2)} mm';
}

class _ZOffsetRow extends StatelessWidget {
  const _ZOffsetRow({required this.state});

  final ProjectState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final value = state.zOffsetFor(state.bedType);
    final atMin = value <= ProjectState.zOffsetMin + 1e-9;
    final atMax = value >= ProjectState.zOffsetMax - 1e-9;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.projectZOffset, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Row(
            children: [
              _ZStepper(
                icon: Icons.remove,
                tooltip: l.projectZOffsetDecrement,
                enabled: !atMin,
                onTap: () => state.nudgeZOffset(
                  state.bedType,
                  -ProjectState.zOffsetStep,
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _formatZ(value),
                    style: monoStyle(context,
                        fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              _ZStepper(
                icon: Icons.add,
                tooltip: l.projectZOffsetIncrement,
                enabled: !atMax,
                onTap: () => state.nudgeZOffset(
                  state.bedType,
                  ProjectState.zOffsetStep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l.projectZOffsetHint,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: WorkshopTokens.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ZStepper extends StatelessWidget {
  const _ZStepper({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: enabled,
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          final color = enabled ? WorkshopTokens.text : WorkshopTokens.textMuted;
          return Semantics(
            label: tooltip,
            button: true,
            enabled: enabled,
            child: GestureDetector(
              onTap: enabled ? onTap : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: WorkshopTokens.minTapTarget,
                height: WorkshopTokens.minTapTarget,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: focused
                        ? WorkshopTokens.accent
                        : WorkshopTokens.border,
                    width: focused ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(WorkshopTokens.radiusMedium),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: color, size: 22),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PlateChooser extends StatelessWidget {
  const _PlateChooser({
    required this.value,
    required this.onChanged,
    required this.textured,
    required this.smooth,
  });

  final BedType value;
  final ValueChanged<BedType> onChanged;
  final String textured;
  final String smooth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PlateButton(
            label: textured,
            selected: value == BedType.texturedA,
            onTap: () => onChanged(BedType.texturedA),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PlateButton(
            label: smooth,
            selected: value == BedType.smoothB,
            onTap: () => onChanged(BedType.smoothB),
          ),
        ),
      ],
    );
  }
}

class _PlateButton extends StatelessWidget {
  const _PlateButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Focus(
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              constraints: const BoxConstraints(minHeight: WorkshopTokens.minTapTarget),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? WorkshopTokens.accent.withValues(alpha: 0.18) : null,
                border: Border.all(
                  color: focused
                      ? WorkshopTokens.accent
                      : selected
                          ? WorkshopTokens.accent
                          : WorkshopTokens.border,
                  width: focused ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(WorkshopTokens.radiusMedium),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? WorkshopTokens.accent : WorkshopTokens.text,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SliceSummary extends StatelessWidget {
  const _SliceSummary({required this.result});

  final SliceResult result;

  @override
  Widget build(BuildContext context) {
    return WorkshopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkshopRow(
              label: 'G-Code', value: result.gcodePath.split('/').last, mono: true),
          const Divider(),
          WorkshopRow(label: 'Groesse', value: '${result.sizeBytes} B', mono: true),
          const Divider(),
          WorkshopRow(
            label: 'Geschaetzte Zeit',
            value: result.estimatedTimeFmt,
            mono: true,
          ),
          const Divider(),
          WorkshopRow(
            label: 'Filament',
            value:
                '${result.filamentUsedMm.toStringAsFixed(0)} mm — ${result.filamentWeightG.toStringAsFixed(2)} g',
            mono: true,
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(WorkshopTokens.radiusSmall),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFFFF6B6B))),
    );
  }
}

class _PickerResult {
  const _PickerResult({this.profile, this.reset = false});
  final SavedProfile? profile;
  final bool reset;
}
