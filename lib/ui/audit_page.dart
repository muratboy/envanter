import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/strings.dart';
import '../core/theme.dart';
import '../data/node.dart';
import '../services/qr_service.dart';
import '../state/inventory_store.dart';
import 'actions.dart';
import 'scan_page.dart';
import 'shell.dart';
import 'widgets/ink_art.dart';
import 'widgets/paper.dart';
import 'widgets/text_prompt.dart';
import 'widgets/tree_picker.dart';

/// Sayım sırasındaki durum.
enum AuditStatus {
  /// Henüz kontrol edilmedi.
  uncounted,

  /// Sayıldı ve beklenen adetle tam eşleşti.
  verified,

  /// Sayıldı ancak adet farkı tespit edildi.
  discrepancy,

  /// Eşya bulunamadı / eksik işaretlendi.
  missing,

  /// Bu klasörün listesinde yoktu ama burada bulundu.
  unexpected,
}

/// Sayımdaki tek bir eşyanın durumu.
class AuditItemRecord {
  AuditItemRecord({
    required this.node,
    required this.expectedQuantity,
    this.countedQuantity = 0,
    this.status = AuditStatus.uncounted,
    this.originalParentId,
  });

  final Node node;
  final int expectedQuantity;
  int countedQuantity;
  AuditStatus status;
  final String? originalParentId;

  bool get isCounted => status != AuditStatus.uncounted;
  bool get hasDiscrepancy =>
      status == AuditStatus.discrepancy || status == AuditStatus.missing;
}

enum _AuditFilter { all, pending, verified, discrepancy, unexpected }

/// Hızlı Sayım & Denetim Sihirbazı sayfası.
class AuditPage extends StatefulWidget {
  const AuditPage({
    super.key,
    required this.containerId,
    required this.containerName,
    this.initialIncludeSubfolders = true,
    @visibleForTesting this.scan,
  });

  final String containerId;
  final String containerName;
  final bool initialIncludeSubfolders;

  /// Kamerasız sınama için okutmanın yerine geçer (verilmezse tarayıcı açılır).
  final Future<ScannedCode?> Function()? scan;

  /// Sayım başlatıcı yardımcı: Klasör verilmişse doğrudan açar; verilmemişse
  /// kapsamı (Tüm Envanter veya belirli bir klasör) sorup başlatır.
  static Future<void> start(BuildContext context, {Node? container}) async {
    final nav = Navigator.of(context);
    final store = InventoryScope.read(context);
    final s = store.strings;

    if (container != null) {
      await nav.push(
        MaterialPageRoute(
          builder: (_) => AuditPage(
            containerId: container.id,
            containerName: store.nameOf(container),
          ),
        ),
      );
      return;
    }

    // Hedef kapsam seçimi: Tüm Envanter ya da Belirli bir klasör
    final choice = await showModalBottomSheet<String>(
      context: nav.context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 12),
                  child: Text(
                    s.auditScopePrompt,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(s.auditEntireInventory),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onTap: () => Navigator.of(sheetContext).pop(Roots.home),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(s.container),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onTap: () async {
                    Navigator.of(sheetContext).pop('pick');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (choice == null || !nav.mounted) return;

    if (choice == Roots.home) {
      await nav.push(
        MaterialPageRoute(
          builder: (_) => AuditPage(
            containerId: Roots.home,
            containerName: s.auditEntireInventory,
          ),
        ),
      );
    } else if (choice == 'pick') {
      // Taşıma seçicisi değil (taşınan kayıt yok): boş listeyle açılınca çöküyor, ekran boş kalıyordu.
      final pickedId = await pickFolder(nav.context, title: s.auditPickFolder, confirm: s.auditCountHere);
      if (pickedId == null || !nav.mounted) return;
      final targetNode = store.byId(pickedId);
      final targetName = switch (pickedId) {
        Roots.home => s.auditEntireInventory,
        Roots.drawer => s.drawer,
        _ => targetNode != null ? store.nameOf(targetNode) : s.container,
      };
      await nav.push(
        MaterialPageRoute(
          builder: (_) => AuditPage(
            containerId: pickedId,
            containerName: targetName,
          ),
        ),
      );
    }
  }

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  late final bool _includeSubfolders = widget.initialIncludeSubfolders;
  final List<AuditItemRecord> _records = [];
  _AuditFilter _filter = _AuditFilter.all;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecords();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _loadRecords() {
    final store = InventoryScope.read(context);
    final isHome = widget.containerId == Roots.home;

    final items = <Node>[];
    void collect(String parentId) {
      for (final child in store.childrenOf(parentId)) {
        if (!store.isLive(child)) continue;
        if (!child.isContainer) {
          items.add(child);
        } else if (_includeSubfolders || isHome) {
          collect(child.id);
        }
      }
    }

    collect(widget.containerId);

    setState(() {
      _records.clear();
      for (final item in items) {
        _records.add(
          AuditItemRecord(
            node: item,
            expectedQuantity: item.quantity ?? 1,
            countedQuantity: 0,
            status: AuditStatus.uncounted,
          ),
        );
      }
    });
  }

  void _verify(AuditItemRecord record) {
    HapticFeedback.lightImpact();
    setState(() {
      record.countedQuantity = record.expectedQuantity;
      record.status = AuditStatus.verified;
    });
  }

  void _increment(AuditItemRecord record) {
    HapticFeedback.lightImpact();
    setState(() {
      record.countedQuantity++;
      if (record.status == AuditStatus.unexpected) return;
      if (record.countedQuantity == record.expectedQuantity) {
        record.status = AuditStatus.verified;
      } else {
        record.status = AuditStatus.discrepancy;
      }
    });
  }

  void _decrement(AuditItemRecord record) {
    HapticFeedback.lightImpact();
    setState(() {
      if (record.countedQuantity > 0) record.countedQuantity--;
      if (record.status == AuditStatus.unexpected) {
        if (record.countedQuantity == 0) {
          _records.remove(record);
        }
        return;
      }
      if (record.countedQuantity == record.expectedQuantity) {
        record.status = AuditStatus.verified;
      } else if (record.countedQuantity > 0) {
        record.status = AuditStatus.discrepancy;
      } else {
        record.status = AuditStatus.missing;
      }
    });
  }

  Future<void> _setExact(AuditItemRecord record) async {
    final s = AppStrings.of(context);
    final values = await showTextPrompt(
      context,
      title: record.node.unit != null ? '${s.quantity} (${record.node.unit})' : s.quantity,
      fields: [
        PromptField(
          label: s.quantity,
          initial: '${record.countedQuantity}',
          keyboardType: TextInputType.number,
        ),
      ],
      cancelLabel: s.cancel,
      confirmLabel: s.save,
    );
    if (values == null || !mounted) return;
    final parsed = int.tryParse(values.first.trim());
    if (parsed == null || parsed < 0) return;

    setState(() {
      record.countedQuantity = parsed;
      if (record.status == AuditStatus.unexpected) return;
      if (parsed == record.expectedQuantity) {
        record.status = AuditStatus.verified;
      } else if (parsed > 0) {
        record.status = AuditStatus.discrepancy;
      } else {
        record.status = AuditStatus.missing;
      }
    });
  }

  void _markMissing(AuditItemRecord record) {
    HapticFeedback.mediumImpact();
    setState(() {
      record.countedQuantity = 0;
      record.status = AuditStatus.missing;
    });
  }

  void _reset(AuditItemRecord record) {
    setState(() {
      if (record.status == AuditStatus.unexpected) {
        _records.remove(record);
        return;
      }
      record.countedQuantity = 0;
      record.status = AuditStatus.uncounted;
    });
  }

  Future<void> _scanBarcode() async {
    final code = await (widget.scan?.call() ??
        Navigator.of(context).push<ScannedCode>(
          MaterialPageRoute(builder: (_) => const ScanPage()),
        ));
    if (code == null || !mounted) return;

    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);

    // 1. Barkod ya da QR kimliği
    final barcodeText = code.barcode;
    final idText = code.id;

    AuditItemRecord? matched;
    if (barcodeText != null) {
      matched = _records.where((r) => r.node.barcode == barcodeText).firstOrNull;
    }
    if (matched == null && idText.isNotEmpty) {
      matched = _records.where((r) => r.node.id == idText).firstOrNull;
    }

    if (matched != null) {
      // Bu klasörde beklenen eşya bulundu
      if (matched.node.tracksQuantity) {
        _increment(matched);
      } else {
        _verify(matched);
      }
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(s.auditItemCountedSuccess(store.nameOf(matched.node), matched.countedQuantity)),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // 2. Kapsam dışında ama envanterde var mı?
    Node? outsideNode;
    if (barcodeText != null) {
      final hits = store.byBarcode(barcodeText);
      if (hits.isNotEmpty) outsideNode = hits.first;
    }
    if (outsideNode == null && idText.isNotEmpty) {
      outsideNode = store.byId(idText);
    }

    if (outsideNode != null && store.isLive(outsideNode) && !outsideNode.isContainer) {
      // Başka klasörden gelen eşya
      final alreadyAdded = _records.where((r) => r.node.id == outsideNode!.id).firstOrNull;
      if (alreadyAdded != null) {
        _increment(alreadyAdded);
      } else {
        final rec = AuditItemRecord(
          node: outsideNode,
          expectedQuantity: outsideNode.quantity ?? 1,
          countedQuantity: 1,
          status: AuditStatus.unexpected,
          originalParentId: outsideNode.parentId,
        );
        setState(() => _records.add(rec));
      }
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(s.auditItemFoundOtherFolder(
            store.nameOf(outsideNode),
            store.pathLabel(outsideNode.parentId ?? Roots.home),
          )),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (outsideNode != null && outsideNode.isContainer) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('${s.container}: ${store.nameOf(outsideNode)}')),
      );
      return;
    }

    // 3. Bilinmeyen barkod
    if (barcodeText != null) {
      final kind = await showDialog<NodeKind>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.barcodeUnknown),
          content: Text('${s.barcodeUnknownBody}\n\n$barcodeText'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.cancel)),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(NodeKind.container),
              child: Text(s.newContainerWithBarcode),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(NodeKind.item),
              child: Text(s.newItemWithBarcode),
            ),
          ],
        ),
      );

      if (kind != null && mounted) {
        final created = await NodeActions.create(
          context,
          parentId: widget.containerId == Roots.home ? Roots.home : widget.containerId,
          kind: kind,
          barcode: barcodeText,
        );
        // Okutulup kaydedilen eşya burada: sayılmış olarak listeye girer. Liste baştan kurulunca
        // (_loadRecords) o ana kadarki bütün sayım sıfırlanıyordu.
        final fresh = created == null || !mounted ? null : InventoryScope.read(context).byId(created.id);
        if (fresh != null && !fresh.isContainer && _records.every((r) => r.node.id != fresh.id)) {
          setState(() => _records.add(AuditItemRecord(
                node: fresh,
                expectedQuantity: fresh.quantity ?? 1,
                countedQuantity: fresh.quantity ?? 1,
                status: AuditStatus.verified,
              )));
        }
      }
    }
  }

  Future<void> _showReconciliation() async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final tones = Tones.of(context);

    final verified = _records.where((r) => r.status == AuditStatus.verified).toList();
    final discrepancies = _records.where((r) => r.status == AuditStatus.discrepancy).toList();
    final missing = _records.where((r) => r.status == AuditStatus.missing || r.status == AuditStatus.uncounted).toList();
    final unexpected = _records.where((r) => r.status == AuditStatus.unexpected).toList();

    bool applyQuantities = true;
    String missingAction = 'none'; // none, lost, shopping, drawer
    bool moveFoundHere = true;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      s.auditSummaryTitle,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    // İstatistik kutusu
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: tones.raised,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: tones.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: tones.success, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text(s.auditVerifiedSummary(verified.length))),
                            ],
                          ),
                          if (discrepancies.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: tones.lost, size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: Text(s.auditDiscrepancySummary(discrepancies.length))),
                              ],
                            ),
                          ],
                          if (missing.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.cancel_outlined, color: tones.danger, size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: Text(s.auditMissingSummary(missing.length))),
                              ],
                            ),
                          ],
                          if (unexpected.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.add_location_alt_outlined, color: tones.accent, size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: Text(s.auditUnexpectedSummary(unexpected.length))),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Eylemler
                    if (discrepancies.isNotEmpty)
                      CheckboxListTile(
                        value: applyQuantities,
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.auditApplyQuantityChanges),
                        onChanged: (v) => setSheetState(() => applyQuantities = v ?? true),
                      ),
                    if (missing.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(s.auditMarkMissingActionLabel, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                      RadioListTile<String>(
                        value: 'none',
                        // ignore: deprecated_member_use
                        groupValue: missingAction,
                        title: Text(s.auditMissingDoNothing),
                        contentPadding: EdgeInsets.zero,
                        // ignore: deprecated_member_use
                        onChanged: (v) => setSheetState(() => missingAction = v ?? 'none'),
                      ),
                      RadioListTile<String>(
                        value: 'lost',
                        // ignore: deprecated_member_use
                        groupValue: missingAction,
                        title: Text(s.auditMarkMissingAsLost),
                        contentPadding: EdgeInsets.zero,
                        // ignore: deprecated_member_use
                        onChanged: (v) => setSheetState(() => missingAction = v ?? 'lost'),
                      ),
                      RadioListTile<String>(
                        value: 'shopping',
                        // ignore: deprecated_member_use
                        groupValue: missingAction,
                        title: Text(s.auditAddMissingToShopping),
                        contentPadding: EdgeInsets.zero,
                        // ignore: deprecated_member_use
                        onChanged: (v) => setSheetState(() => missingAction = v ?? 'shopping'),
                      ),
                      RadioListTile<String>(
                        value: 'drawer',
                        // ignore: deprecated_member_use
                        groupValue: missingAction,
                        title: Text(s.auditMoveMissingToDrawer),
                        contentPadding: EdgeInsets.zero,
                        // ignore: deprecated_member_use
                        onChanged: (v) => setSheetState(() => missingAction = v ?? 'drawer'),
                      ),
                    ],
                    if (unexpected.isNotEmpty && widget.containerId != Roots.home)
                      CheckboxListTile(
                        value: moveFoundHere,
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.auditMoveFoundHere),
                        onChanged: (v) => setSheetState(() => moveFoundHere = v ?? true),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: Text(s.auditApplyAndFinish),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;

    // Mutabakatı veritabanına uygula
    // 1. Adet farkları
    if (applyQuantities) {
      for (final rec in discrepancies) {
        // Kaydın o anki hali, paket kuralıyla: sayımın başındaki kopya yazılınca paketli eşyada toplam
        // bozuluyor, sayım sürerken karşıdan gelen değişiklikler de eziliyordu.
        await store.setQuantity(rec.node.id, rec.countedQuantity);
      }
    }

    // 2. Eksikler
    for (final rec in missing) {
      if (missingAction == 'lost') {
        await store.markLost(rec.node.id);
      } else if (missingAction == 'shopping') {
        await store.setWanted(rec.node.id, true);
      } else if (missingAction == 'drawer') {
        await store.move(rec.node.id, Roots.drawer);
      }
    }

    // 3. Başka yerden gelenler
    if (moveFoundHere && widget.containerId != Roots.home) {
      for (final rec in unexpected) {
        await store.move(rec.node.id, widget.containerId);
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.auditCompletedNotice)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    final theme = Theme.of(context);

    // İlerleme hesabı
    final total = _records.length;
    final counted = _records.where((r) => r.isCounted).length;
    final progress = total == 0 ? 0.0 : (counted / total).clamp(0.0, 1.0);

    // Filtreleme
    final filtered = _records.where((r) {
      switch (_filter) {
        case _AuditFilter.all:
          break;
        case _AuditFilter.pending:
          if (r.status != AuditStatus.uncounted) return false;
        case _AuditFilter.verified:
          if (r.status != AuditStatus.verified) return false;
        case _AuditFilter.discrepancy:
          if (!r.hasDiscrepancy) return false;
        case _AuditFilter.unexpected:
          if (r.status != AuditStatus.unexpected) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final name = store.nameOf(r.node).toLowerCase();
        final barcode = r.node.barcode?.toLowerCase() ?? '';
        final q = _searchQuery.toLowerCase();
        if (!name.contains(q) && !barcode.contains(q)) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: ShellHeader(
        title: widget.containerId == Roots.home ? s.auditInventory : widget.containerName,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: s.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: s.scanBarcode,
            onPressed: _scanBarcode,
          ),
        ],
        // Kapsülün dışında, düzenleyicideki "Kaydet" gibi; kısa adla. Kapsülün içinde uzun adıyla
        // 411 dp'lik telefonda başlığa sığmıyor, sağdan kesiliyordu.
        trailing: Tooltip(
          message: s.finishAudit,
          child: FilledButton.icon(
            onPressed: _records.isEmpty ? null : _showReconciliation,
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: Text(s.finishAuditShort),
          ),
        ),
      ),
      body: Column(
        children: [
          // İlerleme şeridi
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: tones.surface,
              border: Border(bottom: BorderSide(color: tones.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      s.auditItemProgress(counted, total),
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '%${(progress * 100).toInt()}',
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: tones.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: tones.line,
                    valueColor: AlwaysStoppedAnimation(progress == 1.0 ? tones.success : tones.accent),
                  ),
                ),
              ],
            ),
          ),
          // Arama ve Filtre Çipleri
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: s.searchHint,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: tones.raised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _filterChip(_AuditFilter.all, '${s.auditFilterAll} (${_records.length})'),
                const SizedBox(width: 8),
                _filterChip(
                  _AuditFilter.pending,
                  '${s.auditFilterPending} (${_records.where((r) => r.status == AuditStatus.uncounted).length})',
                ),
                const SizedBox(width: 8),
                _filterChip(
                  _AuditFilter.verified,
                  '${s.auditFilterVerified} (${_records.where((r) => r.status == AuditStatus.verified).length})',
                  toneColor: tones.success,
                ),
                const SizedBox(width: 8),
                _filterChip(
                  _AuditFilter.discrepancy,
                  '${s.auditFilterDiscrepancy} (${_records.where((r) => r.hasDiscrepancy).length})',
                  toneColor: tones.danger,
                ),
                if (_records.any((r) => r.status == AuditStatus.unexpected)) ...[
                  const SizedBox(width: 8),
                  _filterChip(
                    _AuditFilter.unexpected,
                    '${s.auditFilterUnexpected} (${_records.where((r) => r.status == AuditStatus.unexpected).length})',
                    toneColor: tones.accent,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          // Eşya Listesi
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: EmptyState(
                        art: InkArtKind.box,
                        title: s.auditEmptyScope,
                        body: s.auditScanBarcodePrompt,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _AuditItemTile(
                        record: item,
                        onVerify: () => _verify(item),
                        onIncrement: () => _increment(item),
                        onDecrement: () => _decrement(item),
                        onSetExact: () => _setExact(item),
                        onMarkMissing: () => _markMissing(item),
                        onReset: () => _reset(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(_AuditFilter filter, String label, {Color? toneColor}) {
    final selected = _filter == filter;
    final tones = Tones.of(context);
    return FilterChip(
      label: Text(label),
      selected: selected,
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        color: selected ? Colors.white : (toneColor ?? tones.ink),
      ),
      backgroundColor: tones.raised,
      selectedColor: toneColor ?? tones.accent,
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: selected ? Colors.transparent : tones.line),
      onSelected: (_) => setState(() => _filter = filter),
    );
  }
}

/// Tek bir denetim satırı.
class _AuditItemTile extends StatelessWidget {
  const _AuditItemTile({
    required this.record,
    required this.onVerify,
    required this.onIncrement,
    required this.onDecrement,
    required this.onSetExact,
    required this.onMarkMissing,
    required this.onReset,
  });

  final AuditItemRecord record;
  final VoidCallback onVerify;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onSetExact;
  final VoidCallback onMarkMissing;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    final theme = Theme.of(context);
    final node = record.node;

    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (record.status) {
      case AuditStatus.uncounted:
        statusColor = tones.muted;
        statusIcon = Icons.radio_button_unchecked_rounded;
        statusText = s.auditFilterPending;
      case AuditStatus.verified:
        statusColor = tones.success;
        statusIcon = Icons.check_circle_rounded;
        statusText = s.auditFilterVerified;
      case AuditStatus.discrepancy:
        statusColor = tones.lost;
        statusIcon = Icons.warning_rounded;
        statusText = '${s.auditFilterDiscrepancy} (${record.countedQuantity}/${record.expectedQuantity})';
      case AuditStatus.missing:
        statusColor = tones.danger;
        statusIcon = Icons.cancel_rounded;
        statusText = s.markMissingAction;
      case AuditStatus.unexpected:
        statusColor = tones.accent;
        statusIcon = Icons.add_circle_outline_rounded;
        statusText = s.auditFilterUnexpected;
    }

    final path = store.pathLabelForParent(node.parentId, inDrawer: node.inDrawer);

    return Material(
      color: tones.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: record.status == AuditStatus.verified
              ? tones.success.withValues(alpha: 0.4)
              : (record.hasDiscrepancy ? tones.danger.withValues(alpha: 0.5) : tones.line),
          width: record.isCounted ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            RecordThumb(node: node, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    store.nameOf(node),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      decoration: record.status == AuditStatus.missing ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Dar yerde kısalır: sağdaki düğmeler yer alınca taşıyordu.
                  Row(
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor),
                        ),
                      ),
                      if (node.tracksQuantity && record.status != AuditStatus.unexpected) ...[
                        Text(' · ', style: TextStyle(color: tones.muted)),
                        Flexible(
                          child: Text(
                            s.expectedQuantity(record.expectedQuantity, node.unit),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: tones.muted),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (path.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(path, style: TextStyle(fontSize: 11, color: tones.muted)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Hızlı butonlar
            if (!record.isCounted) ...[
              FilledButton.tonal(
                onPressed: onVerify,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(0, 36),
                ),
                child: Text(s.verifyAction),
              ),
            ] else ...[
              // Adet Stepper: - [Sayı] +
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_rounded, size: 18),
                    onPressed: onDecrement,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                  InkWell(
                    onTap: onSetExact,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        '${record.countedQuantity}',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, size: 18),
                    onPressed: onIncrement,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ],
            PopupMenuButton<void>(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              tooltip: s.moreActions,
              itemBuilder: (_) => [
                PopupMenuItem(
                  onTap: onVerify,
                  child: ListTile(
                    leading: const Icon(Icons.check_rounded),
                    title: Text(s.verifyAction),
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  onTap: onMarkMissing,
                  child: ListTile(
                    leading: const Icon(Icons.cancel_outlined),
                    title: Text(s.markMissingAction),
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  onTap: onReset,
                  child: ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: Text(s.resetCountAction),
                    dense: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
