import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/node.dart';
import '../../services/qr_service.dart';
import '../../state/inventory_store.dart';
import '../../core/theme.dart';
import '../../core/palette.dart';

/// Karta ozel QR kodu gösterir ve resim olarak paylasilmasini saglar.
class QrSheet extends StatefulWidget {
  const QrSheet({super.key, required this.node});

  final Node node;

  @override
  State<QrSheet> createState() => _QrSheetState();
}

class _QrSheetState extends State<QrSheet> {
  final _boundaryKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    final label = InventoryScope.read(context).nameOf(widget.node);
    setState(() => _sharing = true);
    try {
      await QrService.shareBoundary(
        _boundaryKey,
        fileName: 'envanter_${QrService.safeFileName(label)}',
        text: label,
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = InventoryScope.of(context);
    final s = store.strings;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 22),
            // Paylasilan resim tam olarak bu alanin görüntüsü.
            RepaintBoundary(
              key: _boundaryKey,
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0x14000000)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QrImageView(
                      data: QrService.payloadFor(widget.node),
                      version: QrVersions.auto,
                      size: 220,
                      backgroundColor: Colors.white,
                      eyeStyle: QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        // Pastel kart rengi beyazda okunmaz; koyulaştırılır.
                        color: Color.lerp(canonicalCardColor(widget.node.color), kInk, 0.55)!,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: kInk,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      store.nameOf(widget.node),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: kInk,
                        fontFamily: kDisplayFont,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      widget.node.isContainer ? s.container : s.item,
                      style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.ios_share_rounded),
                label: Text(_sharing ? s.preparing : s.shareAsImage),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.qrHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
