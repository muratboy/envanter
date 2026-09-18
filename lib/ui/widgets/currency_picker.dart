import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/strings.dart';
import '../../core/transitions.dart';
import 'text_prompt.dart';

/// Para birimi seçimi: sık kullanılanlar düğme, gerisi üç harfli kodla. Seçilen kod ya da
/// vazgeçilirse null. Düzenleyici (eşyanın fiyatı) ve ayarlar (yeni fiyatların birimi) ortak.
Future<String?> pickCurrency(BuildContext context, {required String selected}) async {
  final s = AppStrings.of(context);
  final choices = [...Money.common, if (!Money.common.contains(selected)) selected];
  final choice = await showAppSheet<String>(context, (sheetContext) {
    final theme = Theme.of(sheetContext);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.currency, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(s.currenciesSeparate, style: theme.textTheme.bodySmall),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final code in choices)
                  ChoiceChip(
                    label: Text(currencyLabel(code)),
                    selected: code == selected,
                    onSelected: (_) => Navigator.of(sheetContext).pop(code),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_note_rounded),
              title: Text(s.otherCurrency),
              subtitle: Text(s.currencyCodeHint),
              onTap: () => Navigator.of(sheetContext).pop('__other__'),
            ),
          ],
        ),
      ),
    );
  });
  if (choice != '__other__' || !context.mounted) return choice;
  final values = await showTextPrompt(
    context,
    title: s.otherCurrency,
    message: s.currencyCodeHint,
    fields: [
      PromptField(
        label: s.currency,
        initial: Money.common.contains(selected) ? '' : selected,
        capitalization: TextCapitalization.characters,
        keyboardType: TextInputType.visiblePassword,
      ),
    ],
    cancelLabel: s.cancel,
    confirmLabel: s.save,
  );
  final code = values?.single.trim().toUpperCase() ?? '';
  return Money.validCurrency(code) ? code : null;
}

/// "₺ TRY"; simgesi olmayan birimde yalnızca kod.
String currencyLabel(String code) {
  final symbol = Money.symbol(code);
  return symbol == code ? code : '$symbol $code';
}
