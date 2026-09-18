import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/time_span.dart';
import '../../core/transitions.dart';

/// "40 gün kaldı", "bugün son gün", "3 gün önce bitti".
String dueText(AppStrings s, DateTime end, [DateTime? today]) {
  final d = daysBetween(today ?? DateTime.now(), end);
  if (d < 0) return s.expiredAgo(-d);
  if (d == 0) return s.lastDayToday;
  return s.daysLeft(d);
}

/// Bakım günü için: "5 gün kaldı", "bakım günü bugün", "bakım 3 gün gecikti" (son kullanmanın
/// "bitti" sözü bakıma uymuyor).
String serviceDueText(AppStrings s, DateTime next, [DateTime? today]) {
  final d = daysBetween(today ?? DateTime.now(), next);
  if (d < 0) return s.serviceLate(-d);
  if (d == 0) return s.serviceDueToday;
  return s.daysLeft(d);
}

/// Gün seçtirir (Android'in takvimi, uygulamanın dilinde). Vazgeçilirse null.
Future<DateTime?> pickDay(BuildContext context, {DateTime? initial, String? help}) async {
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    helpText: help,
    initialDate: initial ?? now,
    firstDate: DateTime(now.year - 30),
    lastDate: DateTime(now.year + 30),
  );
  return picked == null ? null : dateOnly(picked);
}

/// Süre seçiminin sonucu: [span] null ise kaldır (ya da genel ayarı kullan).
class SpanChoice {
  const SpanChoice(this.span);

  final TimeSpan? span;
}

/// Süre seçtirir: sayı ve birim, altında sık kullanılan süreler. Vazgeçilirse
/// null; "kaldır" ya da [clearLabel] seçilirse boş [SpanChoice].
Future<SpanChoice?> pickSpan(
  BuildContext context, {
  required String title,
  TimeSpan? current,
  String? hint,
  String? clearLabel,
  bool allowClear = true,
}) =>
    showAppSheet<SpanChoice>(
      context,
      (_) => _SpanSheet(
        title: title,
        current: current,
        hint: hint,
        clearLabel: clearLabel,
        allowClear: allowClear,
      ),
    );

class _SpanSheet extends StatefulWidget {
  const _SpanSheet({required this.title, this.current, this.hint, this.clearLabel, this.allowClear = true});

  final String title;
  final TimeSpan? current;
  final String? hint;
  final String? clearLabel;

  /// Genel ayar gibi boş kalamayan sürelerde "kaldır" yok.
  final bool allowClear;

  @override
  State<_SpanSheet> createState() => _SpanSheetState();
}

class _SpanSheetState extends State<_SpanSheet> {
  // Denetleyici pencerenin kendi yaşam döngüsünde: kapanış animasyonunda
  // yok edilmiş bir denetleyiciye dokunulmasın (showTextPrompt'taki gibi).
  late final TextEditingController _amount =
      TextEditingController(text: '${widget.current?.amount ?? 1}');
  late SpanUnit _unit = widget.current?.unit ?? SpanUnit.month;

  static const _quick = [
    TimeSpan(1, SpanUnit.week),
    TimeSpan(1, SpanUnit.month),
    TimeSpan(3, SpanUnit.month),
    TimeSpan(6, SpanUnit.month),
    TimeSpan(1, SpanUnit.year),
    TimeSpan(2, SpanUnit.year),
  ];

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  TimeSpan? get _value {
    final n = int.tryParse(_amount.text.trim());
    return n == null || n <= 0 ? null : TimeSpan(n, _unit);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final tones = Tones.of(context);
    final value = _value;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: tones.line, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 18),
              Text(widget.title, style: theme.textTheme.headlineSmall),
              if (widget.hint != null) ...[
                const SizedBox(height: 4),
                Text(widget.hint!, style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  SizedBox(
                    width: 84,
                    child: TextField(
                      controller: _amount,
                      onTapOutside: dismissKeyboard,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(labelText: s.amount),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedButton<SpanUnit>(
                      showSelectedIcon: false,
                      segments: [
                        for (final u in SpanUnit.values) ButtonSegment(value: u, label: Text(s.unitLabel(u))),
                      ],
                      selected: {_unit},
                      onSelectionChanged: (v) => setState(() => _unit = v.single),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final q in _quick)
                    ActionChip(
                      label: Text(s.spanText(q)),
                      onPressed: () => Navigator.of(context).pop(SpanChoice(q)),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (widget.allowClear && (widget.clearLabel != null || widget.current != null))
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(const SpanChoice(null)),
                      child: Text(widget.clearLabel ?? s.clearValue),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: value == null ? null : () => Navigator.of(context).pop(SpanChoice(value)),
                    child: Text(value == null ? s.done : '${s.done} · ${s.spanText(value)}'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
