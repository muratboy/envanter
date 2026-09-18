import 'package:flutter/widgets.dart';

import '../../sync/sharing_service.dart';

/// Ortak kullanım servisine ağacın her yerinden erişim.
class SharingScope extends InheritedNotifier<SharingService> {
  const SharingScope({super.key, required SharingService service, required super.child})
      : super(notifier: service);

  static SharingService of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SharingScope>()!.notifier!;

  static SharingService read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SharingScope>()!.notifier!;

  /// Ortak kullanımın olmadığı yerlerde (ör. testlerde) null.
  static SharingService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SharingScope>()?.notifier;
}
