import 'package:flutter/material.dart';

import '../../state/inventory_store.dart';
import '../../sync/sharing_service.dart';
import 'sharing_flows.dart';

/// Bir klasörün sorumlularını seçtirir; vazgeçilirse null.
Future<List<String>?> pickManagers(
  BuildContext context, {
  required SharingService sharing,
  required List<String> current,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _ManagerPicker(sharing: sharing, current: current),
  );
}

class _ManagerPicker extends StatefulWidget {
  const _ManagerPicker({required this.sharing, required this.current});

  final SharingService sharing;
  final List<String> current;

  @override
  State<_ManagerPicker> createState() => _ManagerPickerState();
}

class _ManagerPickerState extends State<_ManagerPicker> {
  late final Set<String> _selected = {...widget.current};

  @override
  Widget build(BuildContext context) {
    final s = InventoryScope.of(context).strings;
    final theme = Theme.of(context);
    final c = widget.sharing.config;
    final members = [
      for (final m in c.members)
        (id: m.deviceId, name: widget.sharing.memberName(m.deviceId) ?? s.user),
    ];

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Text(s.chooseManagers, style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(s.managerHint, style: theme.textTheme.bodySmall),
          ),
          if (members.length < 2)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(s.noOneToAssign),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final m in members)
                    CheckboxListTile(
                      value: _selected.contains(m.id),
                      onChanged: (v) => setState(() => v == true ? _selected.add(m.id) : _selected.remove(m.id)),
                      secondary: NameAvatar(name: m.name),
                      title: Text(m.name),
                      subtitle: m.id == c.deviceId ? Text(s.thisDevice) : null,
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop([
                for (final m in members)
                  if (_selected.contains(m.id)) m.id,
              ]),
              child: Text(s.save),
            ),
          ),
        ],
      ),
    );
  }
}
