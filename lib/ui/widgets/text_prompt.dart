import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Metin sorulan pencerenin bir alanı.
class PromptField {
  const PromptField({
    required this.label,
    this.initial = '',
    this.hint,
    this.capitalization = TextCapitalization.sentences,
    this.keyboardType,
    this.selectAll = false,
  });

  final String label;
  final String initial;
  final String? hint;
  final TextCapitalization capitalization;
  final TextInputType? keyboardType;

  /// Başlangıç metni seçili gelsin: yazınca yerine geçer (ör. adet "1").
  /// Değilse imleç sonda durur.
  final bool selectAll;
}

/// Bir ya da birkaç metin soran pencere. Onaylanırsa alanların değerleri,
/// vazgeçilirse null döner.
///
/// Kontrolcüler pencerenin kendi yaşam döngüsünde yaşar. Çağıran taraf
/// onları pencere kapanır kapanmaz atarsa, kapanış animasyonu sırasında
/// uygulama yeniden çizildiğinde (ör. ayar kaydı) metin kutusu atılmış
/// kontrolcüye dokunup çöküyordu.
Future<List<String>?> showTextPrompt(
  BuildContext context, {
  required String title,
  String? message,
  required List<PromptField> fields,
  required String cancelLabel,
  required String confirmLabel,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: title,
      message: message,
      fields: fields,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.message,
    required this.fields,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final String title;
  final String? message;
  final List<PromptField> fields;
  final String cancelLabel;
  final String confirmLabel;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final List<TextEditingController> _controllers = [
    for (final f in widget.fields)
      TextEditingController.fromValue(TextEditingValue(
        text: f.initial,
        selection: f.selectAll
            ? TextSelection(baseOffset: 0, extentOffset: f.initial.length)
            : TextSelection.collapsed(offset: f.initial.length),
      )),
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _confirm() => Navigator.of(context).pop([for (final c in _controllers) c.text]);

  @override
  Widget build(BuildContext context) {
    final last = widget.fields.length - 1;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[
              Text(widget.message!, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 14),
            ],
            for (var i = 0; i < widget.fields.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              TextField(
                controller: _controllers[i],
                onTapOutside: dismissKeyboard,
                autofocus: i == 0,
                textCapitalization: widget.fields[i].capitalization,
                keyboardType: widget.fields[i].keyboardType,
                textInputAction: i == last ? TextInputAction.done : TextInputAction.next,
                onSubmitted: i == last ? (_) => _confirm() : null,
                decoration: InputDecoration(
                  labelText: widget.fields[i].label,
                  hintText: widget.fields[i].hint,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(widget.cancelLabel)),
        FilledButton(onPressed: _confirm, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
