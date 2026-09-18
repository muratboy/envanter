import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../data/node.dart';
import '../../services/location_service.dart';
import '../../state/inventory_store.dart';

/// Konum duzenlemesinin sonucu. [cleared] ise kayitli konum silinir.
class LocationEdit {
  const LocationEdit({this.lat, this.lng, this.label, this.cleared = false});
  const LocationEdit.cleared() : lat = null, lng = null, label = null, cleared = true;

  final double? lat;
  final double? lng;
  final String? label;
  final bool cleared;
}

class LocationSheet extends StatefulWidget {
  const LocationSheet({super.key, required this.node});

  final Node node;

  @override
  State<LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<LocationSheet> {
  late final _labelCtrl = TextEditingController(text: widget.node.locationLabel ?? '');
  late final _latCtrl =
      TextEditingController(text: widget.node.lat?.toStringAsFixed(6) ?? '');
  late final _lngCtrl =
      TextEditingController(text: widget.node.lng?.toStringAsFixed(6) ?? '');

  bool _busy = false;
  LocationFailure? _failure;
  bool _coordError = false;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  Future<void> _autoLocate() async {
    setState(() {
      _busy = true;
      _failure = null;
      _coordError = false;
    });
    try {
      final result = await LocationService.current();
      if (!mounted) return;
      setState(() {
        _latCtrl.text = result.lat.toStringAsFixed(6);
        _lngCtrl.text = result.lng.toStringAsFixed(6);
        if (result.label != null && _labelCtrl.text.trim().isEmpty) {
          _labelCtrl.text = result.label!;
        }
      });
    } on LocationFailure catch (e) {
      if (mounted) setState(() => _failure = e);
    } on Exception {
      if (mounted) setState(() => _failure = LocationFailure.unknown);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() {
    final lat = double.tryParse(_latCtrl.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(_lngCtrl.text.trim().replaceAll(',', '.'));
    final label = _labelCtrl.text.trim();

    if ((_latCtrl.text.trim().isNotEmpty || _lngCtrl.text.trim().isNotEmpty) &&
        (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180)) {
      setState(() {
        _coordError = true;
        _failure = null;
      });
      return;
    }
    if (lat == null && lng == null && label.isEmpty) {
      Navigator.of(context).pop(const LocationEdit.cleared());
      return;
    }
    Navigator.of(context).pop(
      LocationEdit(lat: lat, lng: lng, label: label.isEmpty ? null : label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = InventoryScope.of(context).strings;
    final error = _coordError
        ? s.invalidCoordinates
        : switch (_failure) {
            LocationFailure.serviceOff => s.locationServiceOff,
            LocationFailure.denied => s.locationDenied,
            LocationFailure.deniedForever => s.locationDeniedForever,
            LocationFailure.unknown => s.locationFailed,
            null => null,
          };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 18),
              Text(s.physicalLocation, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(s.physicalLocationHint, style: theme.textTheme.bodySmall),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _busy ? null : _autoLocate,
                icon: _busy
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_rounded),
                label: Text(_busy ? s.locating : s.autoLocate),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _labelCtrl,
                onTapOutside: dismissKeyboard,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: s.locationName,
                  hintText: s.locationNameHint,
                  prefixIcon: const Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latCtrl,
                      onTapOutside: dismissKeyboard,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]'))],
                      decoration: InputDecoration(labelText: s.latitude),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _lngCtrl,
                      onTapOutside: dismissKeyboard,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]'))],
                      decoration: InputDecoration(labelText: s.longitude),
                    ),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  if (widget.node.hasGeo || (widget.node.locationLabel ?? '').isNotEmpty)
                    TextButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(const LocationEdit.cleared()),
                      icon: const Icon(Icons.location_off_rounded),
                      label: Text(s.clear),
                    ),
                  const Spacer(),
                  FilledButton(onPressed: _save, child: Text(s.save)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
