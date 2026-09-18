import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../state/inventory_store.dart';
import '../../sync/discovery.dart';
import '../../sync/sharing_service.dart';
import '../../sync/wire.dart';
import 'changes_page.dart';
import 'sharing_flows.dart';
import 'sharing_scope.dart';
import '../widgets/paper.dart';
import '../shell.dart';

/// Ortak kullanımın tek adresi: aç/kapat, ağdaki envanterler ve katılma,
/// üyeler, değişiklikler, ayrılma.
class SharingPage extends StatelessWidget {
  const SharingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sharing = SharingScope.of(context);
    final store = InventoryScope.of(context);
    final s = store.strings;
    final on = sharing.enabled;

    return Scaffold(
      appBar: ShellHeader(
        eyebrow: on ? sharing.inventoryName : null,
        title: s.sharing,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: s.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(0, 4, 0, 32 + bottomInset(context)),
        children: [
          ReadableWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _StatusCard(),
                if (!on) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: FilledButton.icon(
                      onPressed: () => SharingFlows.toggle(context, true),
                      icon: const Icon(Icons.wifi_tethering_rounded),
                      label: Text(s.turnOnSharing),
                    ),
                  ),
                  const _HowItWorks(initiallyExpanded: true),
                ] else ...[
                  const _MembersSection(),
                  const _ChangesSection(),
                  const _NetworkSection(),
                  // Herkes ayrılabilir; son ana kullanıcı yetkiyi birine bırakarak.
                  if (sharing.config.isShared)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () => SharingFlows.leave(context),
                        icon: const Icon(Icons.logout_rounded),
                        label: Text(s.leaveSharing),
                      ),
                    ),
                  const _HowItWorks(initiallyExpanded: false),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Text(
                      s.sharingLimits,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Üstteki renkli durum kartı: açık mı, ağda hangi adla görünüyor.
class _StatusCard extends StatelessWidget {
  const _StatusCard();

  @override
  Widget build(BuildContext context) {
    final sharing = SharingScope.of(context);
    final s = InventoryScope.of(context).strings;
    final tones = Tones.of(context);
    final text = Theme.of(context).textTheme;
    final on = sharing.enabled;
    final c = sharing.config;
    final online = sharing.onlineMembers.length;

    final title = !on
        ? s.sharingOffTitle
        : c.isOwner
        ? s.sharingVisibleAs(sharing.inventoryName)
        : s.sharingJoinedAs(sharing.inventoryName);
    final subtitle = !on ? s.sharingOffBody : s.sharingOnline(online);
    // Açıkken mürekkep kart, kapalıyken kağıt.
    final fg = on ? tones.paper : tones.ink;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      // Düz renk + yumuşak ışık halkaları. Gradyan burada Android
      // emülatörünün GPU katmanını düşürüyordu (SIGSEGV); kartlardaki halka
      // çizimi ise her yerde sorunsuz.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: on ? tones.ink : tones.surface,
          border: on ? null : Border.all(color: tones.line),
          boxShadow: on
              ? [BoxShadow(color: tones.shadow.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 10))]
              : null,
        ),
        child: CustomPaint(
          painter: on ? _HaloPainter(tones.accent) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Beacon(active: on, color: fg),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: text.titleLarge?.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: text.bodyMedium?.copyWith(
                              color: fg.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: on,
                      onChanged: (v) => SharingFlows.toggle(context, v),
                    ),
                  ],
                ),
                if (on && c.isOwner)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 60),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: fg),
                      onPressed: () => SharingFlows.rename(context),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(s.inventoryNameLabel),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  const _HaloPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final paint = Paint()..color = const Color(0x12FFFFFF);
    canvas.drawCircle(Offset(size.width - h * 0.1, -h * 0.15), h * 0.75, paint);
    paint.color = accent.withValues(alpha: 0.22);
    canvas.drawCircle(Offset(size.width * 0.15, h * 1.25), h * 0.7, paint);
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.accent != accent;
}

/// Açıkken yayılan halkalar: cihaz ağda kendini duyuruyor.
class _Beacon extends StatefulWidget {
  const _Beacon({required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  State<_Beacon> createState() => _BeaconState();
}

class _BeaconState extends State<_Beacon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(_Beacon old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _RingsPainter(widget.active ? _c.value : -1, widget.color),
          child: Icon(
            widget.active
                ? Icons.wifi_tethering_rounded
                : Icons.wifi_tethering_off_rounded,
            color: widget.color,
            size: 26,
          ),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final base = size.shortestSide / 2;
    canvas.drawCircle(
      center,
      base,
      Paint()..color = color.withValues(alpha: 0.14),
    );
    if (t < 0) return;
    for (final phase in [0.0, 0.5]) {
      final p = (t + phase) % 1;
      canvas.drawCircle(
        center,
        base * (1 + p * 0.9),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.45 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t || old.color != color;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) =>
      PaperSection(title: title, trailing: trailing, children: children);
}

enum _MemberAction { makeAdmin, removeAdmin, remove, makeHeir, removeHeir, transfer, trust, untrust }

class _MembersSection extends StatelessWidget {
  const _MembersSection();

  @override
  Widget build(BuildContext context) {
    final sharing = SharingScope.of(context);
    final store = InventoryScope.of(context);
    final s = store.strings;
    final theme = Theme.of(context);
    final c = sharing.config;
    final online = {for (final p in sharing.onlineMembers) p.info.deviceId};
    final others = [
      for (final m in c.members)
        if (m.deviceId != c.deviceId) m,
    ];

    // Kimin hangi klasörün sorumlusu olduğu.
    final places = <String, List<String>>{};
    for (final n in store.allContainers) {
      for (final id in n.managers) {
        (places[id] ??= []).add(store.nameOf(n));
      }
    }

    // Kendin en üstte, sonra sahibi, sonra diğerleri.
    final members = [...c.members]
      ..sort((a, b) {
        int rank(String id) =>
            id == c.deviceId ? 0 : (id == c.ownerDeviceId ? 1 : 2);
        return rank(a.deviceId).compareTo(rank(b.deviceId));
      });

    return _Section(
      title: s.members,
      children: [
        for (final m in members)
          () {
            final me = m.deviceId == c.deviceId;
            final name = me
                ? sharing.displayName()
                : (m.name.isEmpty ? s.user : m.name);
            final isOnline = me || online.contains(m.deviceId);
            return ListTile(
              leading: NameAvatar(name: name, online: isOnline),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (me) _Tag(s.you),
                  if (m.deviceId == c.ownerDeviceId)
                    _Tag(s.owner, strong: true)
                  else if (m.deviceId == c.heir)
                    _Tag(s.heirRole, strong: true)
                  else if (m.admin)
                    _Tag(s.adminRole, strong: true)
                  else if (c.trusted.contains(m.deviceId))
                    _Tag(s.trustedTag),
                ],
              ),
              subtitle: Text(
                [
                  // Çevrimdışıyken en son ne zaman: "eşitlemiyor" sanılmasın, ne kadar eski belli olsun.
                  me
                      ? s.thisDevice
                      : isOnline
                          ? s.online
                          : [
                              s.offline,
                              switch (c.syncedWith[m.deviceId]) {
                                final int at => s.syncedAgo(
                                    SharingFlows.ago(context, DateTime.fromMillisecondsSinceEpoch(at))),
                                _ => s.neverSyncedWith,
                              },
                            ].join(' · '),
                  // Veri sürümü farklı: kim güncellemeli, açıkça.
                  if (sharing.incompatibleVersion(m.deviceId) case final v?)
                    v < kDataVersion ? s.memberOutdated : s.thisOutdated,
                  if (places[m.deviceId] case final p?) s.managesPlaces(p.join(', ')),
                  // Yanlış saat değişiklikleri yanlış sırada birleştirir: görünür olsun.
                  if (!me && sharing.clockIssue(m.deviceId) != null)
                    s.clockGap(s.clockSpan(sharing.clockIssue(m.deviceId)!.skewMs.abs() ~/ 60000)),
                  // Son deneme olmadıysa nedeni: yoksa "çevrimiçi" görünüp hiç eşitlenmiyordu.
                  if (sharing.failureWith(m.deviceId) case final failure?)
                    s.syncFailed(switch (failure) {
                      SyncFailure.unreachable => s.failUnreachable,
                      SyncFailure.timeout => s.failTimeout,
                      SyncFailure.rejected => s.failRejected,
                      SyncFailure.server => s.failServer,
                      SyncFailure.other => s.failOther,
                    }),
                ].join('\n'),
              ),
              isThreeLine: places.containsKey(m.deviceId) ||
                  sharing.incompatibleVersion(m.deviceId) != null ||
                  (!me && sharing.clockIssue(m.deviceId) != null) ||
                  sharing.failureWith(m.deviceId) != null,
              // Yönetici varis seçer ve yöneticiliği devreder; ana kullanıcılar
              // (varis de) başkalarını ana kullanıcı yapar, ana kullanıcı
              // olmayanları ortak kullanımdan çıkarır. Herkes, ana kullanıcı
              // olmayan birinin değişikliklerini sormadan almayı seçebilir.
              trailing: !me && (c.isAdmin && m.deviceId != c.ownerDeviceId || !c.isAdminDevice(m.deviceId))
                  ? PopupMenuButton<_MemberAction>(
                      tooltip: s.options,
                      onSelected: (action) => switch (action) {
                        _MemberAction.makeAdmin => sharing.setAdmin(m.deviceId, true),
                        _MemberAction.removeAdmin => sharing.setAdmin(m.deviceId, false),
                        _MemberAction.remove => SharingFlows.removeMember(context, m.deviceId, name),
                        _MemberAction.makeHeir => SharingFlows.setHeir(context, m.deviceId, name),
                        _MemberAction.removeHeir => SharingFlows.setHeir(context, null, name),
                        _MemberAction.transfer => SharingFlows.transferOwnership(context, m.deviceId, name),
                        _MemberAction.trust => sharing.setTrusted(m.deviceId, true),
                        _MemberAction.untrust => sharing.setTrusted(m.deviceId, false),
                      },
                      itemBuilder: (_) => [
                        // Ana kullanıcınınkiler zaten sormadan gelir.
                        if (!c.isAdminDevice(m.deviceId))
                          PopupMenuItem(
                            value: c.trusted.contains(m.deviceId) ? _MemberAction.untrust : _MemberAction.trust,
                            child: Text(c.trusted.contains(m.deviceId) ? s.untrustMember : s.trustMember),
                          ),
                        if (c.isAdmin && m.deviceId != c.ownerDeviceId) ...[
                        if (c.isOwner) ...[
                          PopupMenuItem(
                            value: m.deviceId == c.heir ? _MemberAction.removeHeir : _MemberAction.makeHeir,
                            child: Text(m.deviceId == c.heir ? s.removeHeir : s.makeHeir),
                          ),
                          PopupMenuItem(value: _MemberAction.transfer, child: Text(s.transferOwnership)),
                        ],
                        // Varis zaten ana kullanıcı yetkisinde: ayrıca verilip alınmaz.
                        if (m.deviceId != c.heir)
                          PopupMenuItem(
                            value: m.admin ? _MemberAction.removeAdmin : _MemberAction.makeAdmin,
                            child: Text(m.admin ? s.removeAdmin : s.makeAdmin),
                          ),
                        if (!c.isAdminDevice(m.deviceId))
                          PopupMenuItem(
                            value: _MemberAction.remove,
                            child: Text(
                              s.removeFromSharing,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        ],
                      ],
                    )
                  : null,
            );
          }(),
        if (others.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(s.noMembersYet, style: theme.textTheme.bodySmall),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(s.adminHint, style: theme.textTheme.bodySmall),
          ),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            leading: sharing.syncing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: Padding(
                      padding: EdgeInsets.all(2),
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : const Icon(Icons.sync_rounded),
            title: Text(sharing.syncing ? s.syncing : s.syncNow),
            subtitle: Text(SharingFlows.lastSyncLabel(context, c.lastSyncAt)),
            enabled: !sharing.syncing && online.isNotEmpty,
            onTap: sharing.syncNow,
          ),
        ],
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.strong = false});

  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: strong
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: strong ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ChangesSection extends StatelessWidget {
  const _ChangesSection();

  @override
  Widget build(BuildContext context) {
    final sharing = SharingScope.of(context);
    final store = InventoryScope.of(context);
    final s = store.strings;
    final n = store.pendingCount;

    return _Section(
      title: s.changes,
      children: [
        ListTile(
          leading: Badge(
            isLabelVisible: n > 0,
            label: Text('$n'),
            child: Icon(
              n > 0
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
            ),
          ),
          title: Text(s.changes),
          subtitle: Text(s.pendingChanges(n)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const ChangesPage())),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.bolt_rounded),
          value: sharing.config.autoAccept,
          onChanged: (v) => SharingFlows.setAutoAccept(context, v),
          title: Text(s.autoAcceptTitle),
          subtitle: Text(s.autoAcceptSubtitle),
        ),
        if (!sharing.config.autoAccept)
          SwitchListTile(
            secondary: const Icon(Icons.exposure_rounded),
            value: sharing.config.quickSmall,
            onChanged: sharing.setQuickSmall,
            title: Text(s.quickSmallTitle),
            subtitle: Text(s.quickSmallSubtitle),
          ),
      ],
    );
  }
}

class _NetworkSection extends StatelessWidget {
  const _NetworkSection();

  @override
  Widget build(BuildContext context) {
    final sharing = SharingScope.of(context);
    final s = InventoryScope.of(context).strings;
    final theme = Theme.of(context);
    // Ağ yalnızca istenince taranır; taramadan önce liste gösterilmez.
    final scanned = sharing.lastScanAt != null;
    final peers = scanned || sharing.scanning ? sharing.joinableInventories : const <DiscoveredPeer>[];

    Widget scanButton({required bool again}) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: sharing.scanning ? null : sharing.scan,
              icon: const Icon(Icons.radar_rounded),
              label: Text(again ? s.scanAgain : s.scanNetwork),
            ),
          ),
        );

    return _Section(
      title: s.inventoriesOnNetwork,
      trailing: sharing.scanning
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      children: [
        if (peers.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: Row(
              children: [
                _Radar(active: sharing.scanning),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (sharing.scanning || scanned)
                        Text(
                          sharing.scanning ? s.searchingNetwork : s.noInventoriesFound,
                          style: theme.textTheme.titleSmall,
                        ),
                      const SizedBox(height: 4),
                      Text(
                        scanned || sharing.scanning ? s.noInventoriesOnNetwork : s.scanPrompt,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!sharing.scanning) scanButton(again: scanned),
        ]
        else ...[
          for (final peer in peers)
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.inventory_2_rounded,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(
                peer.info.inventoryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                s.ownerLabel(
                  peer.info.deviceName.isEmpty ? s.user : peer.info.deviceName,
                ),
              ),
              trailing: FilledButton.tonal(
                onPressed: () => SharingFlows.join(context, peer),
                child: Text(s.join),
              ),
              onTap: () => SharingFlows.join(context, peer),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(s.joinHint, style: theme.textTheme.bodySmall),
          ),
          if (!sharing.scanning) scanButton(again: true),
        ],
      ],
    );
  }
}

/// Ağ taranırken dönen radar.
class _Radar extends StatefulWidget {
  const _Radar({required this.active});

  /// Tarama sürerken döner; durunca sakin bir halka olarak kalır.
  final bool active;

  @override
  State<_Radar> createState() => _RadarState();
}

class _RadarState extends State<_Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(_Radar old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 48,
      height: 48,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) =>
            CustomPaint(painter: _RadarPainter(_c.value, color)),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withValues(alpha: 0.35);
    canvas.drawCircle(c, r, ring);
    canvas.drawCircle(c, r * 0.6, ring);
    // Tarayan dilim düz renkli parçalardan: gradyan gölgelendiricisi bazı
    // GPU sürücülerinde (ve emülatörde) sorun çıkarıyor.
    const slices = 12;
    const step = math.pi / 2 / slices;
    final head = t * 2 * math.pi;
    final rect = Rect.fromCircle(center: c, radius: r);
    for (var k = 0; k < slices; k++) {
      final paint = Paint()
        ..color = color.withValues(alpha: 0.5 * (1 - k / slices));
      canvas.drawArc(rect, head - (k + 1) * step, step + 0.01, true, paint);
    }
    canvas.drawCircle(c, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.t != t;
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks({required this.initiallyExpanded});

  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final s = InventoryScope.of(context).strings;
    final theme = Theme.of(context);
    final steps = s.howItWorksSteps;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Tones.of(context).surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Tones.of(context).line),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: const Icon(Icons.lightbulb_outline_rounded),
          title: Text(s.howItWorks),
          shape: const Border(),
          collapsedShape: const Border(),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: theme.colorScheme.primary,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(steps[i], style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
