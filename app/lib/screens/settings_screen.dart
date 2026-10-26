import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/filament_mapping.dart';
import '../settings/filament_overrides.dart';
import '../settings/profile_writer.dart';
import '../settings/settings_overrides.dart';
import '../settings/settings_schema.dart';
import '../state/printer_state.dart';
import '../theme/workshop_theme.dart';
import '../widgets/workshop_card.dart';

// Phase 4.2: Prozess-Einstellungen, vollstaendig, in allen drei Stufen.
// Datenquelle: assets/settings-schema.json (Phase 4.1,
// mechanisch aus Orca v2.4.2 erzeugt). UI ohne Hand-Pflege: Reiter,
// Gruppen, Options, Stufe, Label, Tooltip, Enum-Werte, min/max kommen
// alle aus dem Schema.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.schema,
    required this.overrides,
    required this.filamentOverrides,
    required this.printerState,
  });

  final SettingsSchema schema;
  final SettingsOverrides overrides;
  final FilamentOverrides filamentOverrides;
  final PrinterState printerState;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _SettingsArea { process, filament }

class _SettingsScreenState extends State<SettingsScreen> {
  SettingTier _tier = SettingTier.fortgeschritten;
  int _activePage = 0;
  int _activeTray = 3; // Default A4 (deckt sich mit PrinterState-Default)
  _SettingsArea _area = _SettingsArea.process;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    widget.overrides.addListener(_onOverridesChanged);
    widget.filamentOverrides.addListener(_onOverridesChanged);
    widget.printerState.addListener(_onOverridesChanged);
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q != _searchQuery) setState(() => _searchQuery = q);
    });
  }

  @override
  void dispose() {
    widget.overrides.removeListener(_onOverridesChanged);
    widget.filamentOverrides.removeListener(_onOverridesChanged);
    widget.printerState.removeListener(_onOverridesChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onOverridesChanged() {
    if (mounted) setState(() {});
  }

  List<SettingPage> get _pages {
    final area = _area == _SettingsArea.process ? 'print' : 'filament';
    return widget.schema.pagesFor(area);
  }

  // Overrides-Instanz des gerade aktiven Bereichs + Fachs.
  SettingsOverrides get _activeOverrides => _area == _SettingsArea.process
      ? widget.overrides
      : widget.filamentOverrides.forTray(_activeTray);

  Future<void> _saveAsProfile() async {
    final l = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: 'My Process');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.settingsSaveDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.settingsSaveDialogHint,
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(labelText: l.settingsProfileName),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.pairDialogCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.pairDialogSave)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      // Phase 4.3 speichert nur Prozess-Profile; Filament-Overrides
      // werden pro Fach direkt persistiert (siehe FilamentOverrides).
      final file = await const ProfileWriter().save(
        name: nameCtrl.text.trim(),
        baseInherits: '0.20mm Standard @Elegoo CC2 0.4 nozzle',
        type: 'process',
        overrides: widget.overrides.all,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.settingsProfileSaved(file.path.split('/').last))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.settingsProfileSaveFailed(e.toString()))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    final searching = _searchQuery.isNotEmpty;
    final visibleGroups = _computeVisibleGroups(locale, searching);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: ListView(
        children: [
          Text(l.settingsHeading, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            l.settingsSourceCaption(widget.schema.orcaVersion),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: WorkshopTokens.textMuted),
          ),
          const SizedBox(height: 12),

          _AreaToggle(
            value: _area,
            onChanged: (a) => setState(() { _area = a; _activePage = 0; }),
          ),
          const SizedBox(height: 10),

          if (_area == _SettingsArea.filament) ...[
            _TrayPicker(
              activeTray: _activeTray,
              slots: widget.printerState.slots,
              onChanged: (t) => setState(() => _activeTray = t),
            ),
            const SizedBox(height: 8),
            _FilamentBaseHint(
              tray: _activeTray,
              slots: widget.printerState.slots,
            ),
            const SizedBox(height: 10),
          ],

          Row(
            children: [
              Expanded(
                child: Text(
                  l.settingsOverridesCount(_activeOverrides.count),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _activeOverrides.isEmpty
                        ? WorkshopTokens.textMuted
                        : WorkshopTokens.accent,
                  ),
                ),
              ),
              if (_area == _SettingsArea.process)
                TextButton.icon(
                  onPressed:
                      widget.overrides.isEmpty ? null : _saveAsProfile,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(l.settingsSaveAsProfile),
                ),
            ],
          ),
          const SizedBox(height: 8),

          _TierToggle(
            value: _tier,
            onChanged: (t) => setState(() => _tier = t),
          ),

          const SizedBox(height: 10),
          _SearchBar(controller: _searchCtrl),

          if (!searching) ...[
            const SizedBox(height: 10),
            _PageChips(
              pages: _pages,
              locale: locale,
              activeIndex: _activePage,
              onChanged: (i) => setState(() => _activePage = i),
            ),
          ],

          const SizedBox(height: 12),
          ...visibleGroups.map((entry) {
            final page = entry.$1;
            final group = entry.$2;
            final opts = entry.$3;
            return _GroupCard(
              pageName: page.display(locale),
              groupName: group.display(locale),
              options: opts,
              overrides: _activeOverrides,
              locale: locale,
              showPageName: searching,
            );
          }),
          if (visibleGroups.isEmpty) ...[
            const SizedBox(height: 32),
            Center(
              child: Text(
                l.settingsNoMatches,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: WorkshopTokens.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Liefert die anzuzeigende Gruppen-Menge: entweder nur die aktive Seite
  /// (gefiltert auf Tier) oder bei Suche alle Treffer ueber alle Seiten.
  List<(SettingPage, SettingGroup, List<SettingOption>)> _computeVisibleGroups(
      String locale, bool searching) {
    final result = <(SettingPage, SettingGroup, List<SettingOption>)>[];
    final pages = searching ? _pages : [_pages[_activePage]];
    for (final page in pages) {
      for (final group in page.groups) {
        final opts = group.options.where((o) {
          if (!o.visibleIn(_tier)) return false;
          if (!searching) return true;
          return _matchesSearch(o, _searchQuery);
        }).toList();
        if (opts.isNotEmpty) result.add((page, group, opts));
      }
    }
    return result;
  }

  bool _matchesSearch(SettingOption o, String q) {
    return o.key.toLowerCase().contains(q) ||
        o.labelEn.toLowerCase().contains(q) ||
        o.labelDe.toLowerCase().contains(q) ||
        o.tooltipEn.toLowerCase().contains(q) ||
        o.tooltipDe.toLowerCase().contains(q);
  }
}

class _TierToggle extends StatelessWidget {
  const _TierToggle({required this.value, required this.onChanged});
  final SettingTier value;
  final ValueChanged<SettingTier> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final labels = {
      SettingTier.basis:           l.settingsTierBasis,
      SettingTier.fortgeschritten: l.settingsTierAdvanced,
      SettingTier.experte:         l.settingsTierExpert,
    };
    return Row(
      children: SettingTier.values.map((t) {
        final selected = t == value;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Focus(
              child: Builder(
                builder: (ctx) {
                  final focused = Focus.of(ctx).hasFocus;
                  return GestureDetector(
                    onTap: () => onChanged(t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? WorkshopTokens.accent.withValues(alpha: 0.18)
                            : null,
                        border: Border.all(
                          color: focused
                              ? WorkshopTokens.accent
                              : (selected
                                  ? WorkshopTokens.accent
                                  : WorkshopTokens.border),
                          width: focused ? 2 : 1,
                        ),
                        borderRadius:
                            BorderRadius.circular(WorkshopTokens.radiusMedium),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        labels[t]!,
                        style: TextStyle(
                          color: selected
                              ? WorkshopTokens.accent
                              : WorkshopTokens.text,
                          fontWeight:
                              selected ? FontWeight.w500 : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: l.settingsSearchHint,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(WorkshopTokens.radiusMedium),
        ),
      ),
    );
  }
}

class _PageChips extends StatelessWidget {
  const _PageChips({
    required this.pages,
    required this.locale,
    required this.activeIndex,
    required this.onChanged,
  });
  final List<SettingPage> pages;
  final String locale;
  final int activeIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: pages.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final selected = i == activeIndex;
          return Focus(
            child: Builder(
              builder: (ctx) {
                final focused = Focus.of(ctx).hasFocus;
                return GestureDetector(
                  onTap: () => onChanged(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? WorkshopTokens.accent.withValues(alpha: 0.18)
                          : null,
                      border: Border.all(
                        color: focused
                            ? WorkshopTokens.accent
                            : (selected
                                ? WorkshopTokens.accent
                                : WorkshopTokens.border),
                        width: focused ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(
                          WorkshopTokens.radiusMedium),
                    ),
                    child: Text(
                      pages[i].display(locale),
                      style: TextStyle(
                        color: selected
                            ? WorkshopTokens.accent
                            : WorkshopTokens.text,
                        fontWeight:
                            selected ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.pageName,
    required this.groupName,
    required this.options,
    required this.overrides,
    required this.locale,
    required this.showPageName,
  });

  final String pageName;
  final String groupName;
  final List<SettingOption> options;
  final SettingsOverrides overrides;
  final String locale;
  final bool showPageName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WorkshopCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: showPageName
                  ? Text('$pageName · $groupName',
                      style: theme.textTheme.bodySmall)
                  : Text(groupName, style: theme.textTheme.bodySmall),
            ),
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _OptionRow(
                option: options[i],
                overrides: overrides,
                locale: locale,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatefulWidget {
  const _OptionRow({
    required this.option,
    required this.overrides,
    required this.locale,
  });
  final SettingOption option;
  final SettingsOverrides overrides;
  final String locale;

  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
  bool _tooltipOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = widget.option;
    final hasOverride = widget.overrides.has(o.key);
    final rawValue = widget.overrides.get(o.key) ?? o.defaultSerialized;
    final label = o.label(widget.locale);
    final tooltip = o.tooltip(widget.locale);
    final hasTooltip = tooltip.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.isEmpty ? o.key : label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: hasOverride
                        ? WorkshopTokens.accent
                        : WorkshopTokens.text,
                    fontWeight: hasOverride
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                ),
              ),
              if (hasOverride)
                IconButton(
                  tooltip: AppLocalizations.of(context).settingsResetTooltip,
                  icon: const Icon(Icons.restore,
                      color: WorkshopTokens.accent),
                  onPressed: () => widget.overrides.reset(o.key),
                ),
              if (hasTooltip)
                IconButton(
                  icon: Icon(
                      _tooltipOpen ? Icons.info : Icons.info_outline,
                      color: WorkshopTokens.textMuted),
                  onPressed: () =>
                      setState(() => _tooltipOpen = !_tooltipOpen),
                ),
            ],
          ),
          _InputForType(
            option: o,
            rawValue: rawValue,
            onChanged: (v) {
              if (v == o.defaultSerialized) {
                widget.overrides.reset(o.key);
              } else {
                widget.overrides.set(o.key, v);
              }
            },
          ),
          if (_tooltipOpen && hasTooltip)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tooltip,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: WorkshopTokens.textMuted)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Text(o.key,
                    style: monoStyle(context,
                        fontSize: 11, color: WorkshopTokens.textMuted)),
                const SizedBox(width: 8),
                Text(o.mode,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: WorkshopTokens.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bedienelement passend zum Options-Typ.
class _InputForType extends StatelessWidget {
  const _InputForType({
    required this.option,
    required this.rawValue,
    required this.onChanged,
  });
  final SettingOption option;
  final String rawValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    switch (option.type) {
      case 'bool':
        return _BoolInput(value: rawValue == '1', onChanged: (v) {
          onChanged(v ? '1' : '0');
        });
      case 'enum':
        return _EnumInput(
          option: option,
          value: rawValue,
          onChanged: onChanged,
        );
      case 'int':
        return _NumberInput(
          value: rawValue,
          onChanged: onChanged,
          min: option.min,
          max: option.max,
          step: 1,
          integer: true,
          suffix: option.sidetext,
        );
      case 'percent':
        return _NumberInput(
          value: rawValue,
          onChanged: onChanged,
          min: option.min,
          max: option.max,
          step: 1,
          integer: false,
          suffix: '%',
        );
      case 'float_or_percent':
        return _NumberInput(
          value: rawValue,
          onChanged: onChanged,
          min: option.min,
          max: option.max,
          step: 0.05,
          integer: false,
          suffix: rawValue.endsWith('%') ? '%' : option.sidetext,
        );
      case 'float':
        return _NumberInput(
          value: rawValue,
          onChanged: onChanged,
          min: option.min,
          max: option.max,
          step: 0.05,
          integer: false,
          suffix: option.sidetext,
        );
      case 'string':
        return _StringInput(value: rawValue, onChanged: onChanged);
      // Vektor-Typen (floats, ints, points, …) sowie Experten-Spezialtypen
      // werden in dieser Etappe als rohe Textzeile angezeigt – lesbar,
      // aber ohne eigenes Widget. 4.3 kann das pro Typ hochziehen.
      default:
        return _StringInput(value: rawValue, onChanged: onChanged);
    }
  }
}

class _BoolInput extends StatelessWidget {
  const _BoolInput({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Switch(value: value, onChanged: onChanged),
      );
}

class _EnumInput extends StatelessWidget {
  const _EnumInput({
    required this.option,
    required this.value,
    required this.onChanged,
  });
  final SettingOption option;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String>>[];
    for (var i = 0; i < option.enumValues.length; i++) {
      final v = option.enumValues[i];
      final labelDe = i < option.enumLabelsDe.length ? option.enumLabelsDe[i] : '';
      final labelEn = i < option.enumLabels.length   ? option.enumLabels[i]   : v;
      final label = labelDe.isNotEmpty ? labelDe : labelEn;
      items.add(DropdownMenuItem(value: v, child: Text(label)));
    }
    final current =
        option.enumValues.contains(value) ? value : option.defaultSerialized;
    return DropdownButton<String>(
      isExpanded: true,
      value: option.enumValues.contains(current) ? current : null,
      items: items,
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _StringInput extends StatefulWidget {
  const _StringInput({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  State<_StringInput> createState() => _StringInputState();
}

class _StringInputState extends State<_StringInput> {
  late final TextEditingController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _StringInput old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _ctrl.text != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _ctrl,
        decoration: const InputDecoration(isDense: true),
        onSubmitted: widget.onChanged,
      );
}

/// Zahlfeld mit −/+-Steppern, Direkteingabe und min/max.
class _NumberInput extends StatefulWidget {
  const _NumberInput({
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    required this.step,
    required this.integer,
    required this.suffix,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final num? min;
  final num? max;
  final num step;
  final bool integer;
  final String suffix;

  @override
  State<_NumberInput> createState() => _NumberInputState();
}

class _NumberInputState extends State<_NumberInput> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _NumberInput old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _ctrl.text != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _asDouble(String s) => double.tryParse(s.replaceAll('%', '')) ?? 0;

  String _format(double v) {
    if (widget.integer) return v.toInt().toString();
    final s = v.toStringAsFixed(3);
    return s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
  }

  void _step(double delta) {
    var v = _asDouble(_ctrl.text) + delta;
    if (widget.min != null) {
      v = v < widget.min!.toDouble() ? widget.min!.toDouble() : v;
    }
    if (widget.max != null) {
      v = v > widget.max!.toDouble() ? widget.max!.toDouble() : v;
    }
    final hadPercent = _ctrl.text.endsWith('%');
    final out = _format(v) + (hadPercent ? '%' : '');
    _ctrl.text = out;
    widget.onChanged(out);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: () => _step(-widget.step.toDouble()),
        ),
        Expanded(
          child: TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              isDense: true,
              suffixText: widget.suffix.isEmpty ? null : widget.suffix,
            ),
            keyboardType: TextInputType.numberWithOptions(
              decimal: !widget.integer,
              signed: true,
            ),
            onSubmitted: widget.onChanged,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => _step(widget.step.toDouble()),
        ),
      ],
    );
  }
}

// Bereichsumschalter oben: Prozess | Filament. Fuer Filament kommt
// darunter noch der Fach-Umschalter.
class _AreaToggle extends StatelessWidget {
  const _AreaToggle({required this.value, required this.onChanged});
  final _SettingsArea value;
  final ValueChanged<_SettingsArea> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final labels = {
      _SettingsArea.process:  l.settingsAreaProcess,
      _SettingsArea.filament: l.settingsAreaFilament,
    };
    return Row(
      children: _SettingsArea.values.map((a) {
        final selected = a == value;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => onChanged(a),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? WorkshopTokens.accent.withValues(alpha: 0.18)
                      : null,
                  border: Border.all(
                    color: selected
                        ? WorkshopTokens.accent
                        : WorkshopTokens.border,
                  ),
                  borderRadius:
                      BorderRadius.circular(WorkshopTokens.radiusMedium),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[a]!,
                  style: TextStyle(
                    color: selected ? WorkshopTokens.accent : WorkshopTokens.text,
                    fontWeight:
                        selected ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// A1..A4-Umschalter. Zeigt pro Fach den Material-Namen aus dem
/// zuletzt empfangenen 2005 (oder "–"), damit klar ist, welches
/// Material belegt wird. State des Umschalters liegt im Parent.
class _TrayPicker extends StatelessWidget {
  const _TrayPicker({
    required this.activeTray,
    required this.slots,
    required this.onChanged,
  });
  final int activeTray;
  final List<dynamic> slots; // typed CanvasSlot aus printer_state
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(4, (i) {
        final selected = i == activeTray;
        final slot = slots.where((s) => s.trayId == i).toList();
        final label = slot.isNotEmpty ? (slot.first.filamentName as String) : '–';
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == 3 ? 0 : 6),
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? WorkshopTokens.accent.withValues(alpha: 0.18)
                      : null,
                  border: Border.all(
                    color: selected
                        ? WorkshopTokens.accent
                        : WorkshopTokens.border,
                  ),
                  borderRadius:
                      BorderRadius.circular(WorkshopTokens.radiusMedium),
                ),
                child: Column(
                  children: [
                    Text('A${i + 1}',
                        style: TextStyle(
                          color: selected
                              ? WorkshopTokens.accent
                              : WorkshopTokens.text,
                          fontWeight: FontWeight.w500,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: WorkshopTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Hinweiszeile unter dem Fach-Umschalter: welches Orca-Filamentprofil
/// als Ausgangspunkt genommen wird. Hebt sichtbar hervor, wenn ein
/// Fallback zum Einsatz kommt (Material aus 2005 nicht eindeutig).
class _FilamentBaseHint extends StatelessWidget {
  const _FilamentBaseHint({required this.tray, required this.slots});
  final int tray;
  final List<dynamic> slots;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final match = slots.where((s) => s.trayId == tray).toList();
    if (match.isEmpty) {
      return Text(l.settingsFilamentNoSlot,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: WorkshopTokens.textMuted));
    }
    final ref = const FilamentMapping().resolve(
      filamentName: match.first.filamentName as String,
      filamentType: match.first.filamentType as String,
    );
    final profile = ref.assetName.replaceAll('.json', '');
    final baseText = l.settingsFilamentBase(profile);
    if (ref.generic) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 14, color: Color(0xFFF2B241)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '$baseText — ${ref.fallbackReason}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: const Color(0xFFF2B241)),
            ),
          ),
        ],
      );
    }
    return Text(baseText,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: WorkshopTokens.textMuted));
  }
}
