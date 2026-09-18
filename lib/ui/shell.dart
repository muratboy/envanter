import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/palette.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../core/transitions.dart';
import '../data/node.dart';
import '../data/settings.dart';
import '../services/box_export.dart';
import '../services/platform_bridge.dart';
import '../state/inventory_store.dart';
import 'actions.dart';
import 'burst_add_page.dart';
import 'audit_page.dart';
import 'container_screen.dart';
import 'label_flows.dart';
import 'node_list_view.dart';
import 'search_page.dart';
import 'selection.dart';
import 'sharing/changes_page.dart';
import 'sharing/sharing_scope.dart';
import 'widgets/entrance.dart';
import 'widgets/left_drawer.dart';
import 'widgets/node_card.dart';
import 'widgets/tree_picker.dart';
import 'widgets/unsorted_drawer.dart';

/// Hangi ekranın önde olduğunu izler: üstteki ekran kapanınca alttaki kabuk
/// "kaldığımız yer burası" diye kendini yeniden yazar.
final inventoryRouteObserver = RouteObserver<PageRoute<void>>();

/// Sağ çekmece panelinin genişliği: telefonda ekranın çoğu, tablette sabit.
/// Yatay düzende deste yanında kalır: ekranın beşte ikisi kadar.
double unsortedPanelWidth(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return landscapeLayout(context) ? (width * 0.42).clamp(300.0, 440.0) : (width * 0.86).clamp(0.0, 440.0);
}

/// Yatay düzende soldaki dikey şeridin genişliği (ara, QR, yeni kayıt).
const double kSideRailWidth = 76;

/// Ana ekran ve klasör ekranı aynı kabuğu paylaşır: deste, sağ çekmece,
/// alttaki büyüteç ve artı.
class InventoryShell extends StatefulWidget {
  const InventoryShell({
    super.key,
    required this.parentId,
    required this.title,
    this.leading,
    this.actions,
    this.subtitle,
    this.highlightId,
    this.showLeftDrawer = false,
    this.banner,
    this.titleBadge,
  });

  final String parentId;
  final String title;

  /// Başlıkta adın önündeki küçük işaret (ana ekranda envanterin amblemi).
  /// Yalnızca kabuğun kendi seviyesinde: klasöre inilince başlık klasörün.
  final Widget? titleBadge;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final String? highlightId;
  final bool showLeftDrawer;

  /// Destenin üstünde duran bilgi kartı (ör. ilk açılış ipuçları).
  final Widget? banner;

  /// En yakın kabuğun sağ çekmecesini açar (üst çubuk, sol menü).
  static void openDrawerPanel(BuildContext context) =>
      context.findAncestorStateOfType<_InventoryShellState>()?._openPanel();

  static void openLostPanel(BuildContext context) =>
      context.findAncestorStateOfType<_InventoryShellState>()?._openLost();

  static void openFavoritesPanel(BuildContext context) =>
      context.findAncestorStateOfType<_InventoryShellState>()?._openFavorites();

  static void openExpiredPanel(BuildContext context) =>
      context.findAncestorStateOfType<_InventoryShellState>()?._openExpired();

  /// Yığındaki ekranları kapatıp doğrudan [level]'e gider: ana ekran, çekmece, kayıp ya da açık
  /// klasörün üstündeki bir klasör (başlıktaki yol menüsü, geri okuna uzun basmak).
  static void goToLevel(BuildContext context, String level) =>
      context.findAncestorStateOfType<_InventoryShellState>()?._goToLevel(level);

  /// Kart en yakın kabuğun açık seviyesinde mi? Toplu seçim yalnızca orada
  /// başlar; çekmece panelindeki ya da aramadaki bir karttan başlamaz.
  static bool canSelect(BuildContext context, Node node) {
    final shell = context.findAncestorStateOfType<_InventoryShellState>();
    return shell != null &&
        shell._panelsClosed &&
        InventoryScope.read(context).bucketKey(node) == shell._levelId;
  }

  /// En yakın kabukta toplu seçimi başlatır; [node] verilirse ilk seçilen odur.
  static void startSelection(BuildContext context, [Node? node]) =>
      context.findAncestorStateOfType<_InventoryShellState>()?._selection.start(node?.id);

  static final ValueNotifier<int> _lostRequests = ValueNotifier(0);

  /// Bağlamı olmayan yerlerden (bildirim) en üstteki kabuğun kayıp
  /// çekmecesini açtırır.
  static void requestLostPanel() => _lostRequests.value++;

  @override
  State<InventoryShell> createState() => _InventoryShellState();
}

class _InventoryShellState extends State<InventoryShell>
    with TickerProviderStateMixin, RouteAware {
  /// Sürüklerken bir klasörün üzerinde beklenince onun içine "yerinde"
  /// inilir. Navigator.push kullanılamaz: route değişimi aktif işaretçileri
  /// iptal ettiği için sürükleme yarıda kesilirdi.
  final List<String> _drill = [];

  /// Çekmece, Scaffold.endDrawer değil; ağaçta hep duran kayar bir panel.
  /// Kapanırken ağaçtan düşmediği için içinden başlayan sürükleme yaşar.
  late final AnimationController _panel = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// Kayıp çekmecesi; çekmeceyle aynı mantıkta ikinci panel.
  late final AnimationController _lostPanel = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// Sık kullanılanlar; aynı mantıkta üçüncü panel.
  late final AnimationController _favPanel = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  /// Tarihi geçenler; sık kullanılanlar gibi bir işaret listesi, dördüncü panel.
  late final AnimationController _expPanel = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  bool _closingForDrag = false;

  /// Hangi sürükleme için panel kararı verildi: karar bir kez verilir, yoksa
  /// her çizimde yeniden kapanır ve kenarda bekleyip paneli açmak imkânsız olur.
  String? _dragHandled;

  /// En son hatırlatılan seviye; her çizimde ayar yazmayalım.
  String? _remembered;

  /// Açık seviyedeki toplu seçim.
  final DeckSelection _selection = DeckSelection();

  /// Yatayda açık panelin genişliği kadar deste daralır (hangisi açıksa).
  late final Listenable _docked = Listenable.merge([_panel, _lostPanel, _favPanel, _expPanel]);

  double get _dockedValue =>
      [_panel.value, _lostPanel.value, _favPanel.value, _expPanel.value].reduce(math.max);

  bool get _panelsClosed =>
      _panel.isDismissed && _lostPanel.isDismissed && _favPanel.isDismissed && _expPanel.isDismissed;

  /// Sol menü açık mı. Geri tuşu menüyü kapatsın diye izlenir: menü, Scaffold'un
  /// sayfaya eklediği bir "yerel geçmiş" kaydıdır ve Android'in öngörülü geri
  /// hareketinde (manifest'te açık) Flutter "geriyi ben karşılarım" demedikçe
  /// sistem ona hiç sormadan etkinliği kapatır: menü açıkken geri, uygulamadan
  /// çıkarıyordu. Paneller gibi: açıkken [PopScope] geriyi tutar, menü kapanır.
  bool _menuOpen = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    // Geri tuşu açık paneli kapatsın: PopScope'un canPop'u panelin durumuyla
    // birlikte tazelenmeli.
    void refresh(AnimationStatus _) {
      if (mounted) setState(() {});
    }

    _panel.addStatusListener(refresh);
    _lostPanel.addStatusListener(refresh);
    _favPanel.addStatusListener(refresh);
    _expPanel.addStatusListener(refresh);
    InventoryShell._lostRequests.addListener(_onLostRequest);
    _selection.addListener(_onSelection);
  }

  void _onSelection() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      _route = route;
      _shells[route] = this;
      inventoryRouteObserver.subscribe(this, route);
    }
  }

  /// Bu kabuğun ekranı (üstte mi diye sormak için).
  PageRoute<void>? _route;

  /// Yığındaki ekranların kabukları: yol menüsü gidilecek seviyeyi gösteren ekranı arar
  /// ([_goToLevel]); bulursa üstündekileri kapatır, o ekranın destesi de kaldığı yerde durur.
  static final Map<Route<dynamic>, _InventoryShellState> _shells = {};

  /// Üstteki ekran kapandı, yine buradayız: açık seviye yeniden yazılsın.
  ///
  /// Ama hemen yerine başkası açılmış olabilir: aramadan ya da QR'dan "kayda
  /// git" önce üstteki ekranları kapatır, sonra kaydın klasörünü açar. O zaman
  /// açık seviye yeni ekranınkidir; bu kabuk kendini yazarsa (yenisinden sonra
  /// çizildiği için) son açık yer ana ekran diye kalıyor, uygulama yeniden
  /// açılınca kullanıcı kaldığı klasörde değil ana ekranda başlıyordu. Karar
  /// bu yüzden kare bitince verilir: hâlâ en üstteysek yazılır.
  @override
  void didPopNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(_route?.isCurrent ?? true)) return;
      setState(() => _remembered = null);
    });
  }

  @override
  void dispose() {
    if (identical(_shells[_route], this)) _shells.remove(_route);
    inventoryRouteObserver.unsubscribe(this);
    InventoryShell._lostRequests.removeListener(_onLostRequest);
    _selection
      ..removeListener(_onSelection)
      ..dispose();
    _panel.dispose();
    _lostPanel.dispose();
    _favPanel.dispose();
    _expPanel.dispose();
    super.dispose();
  }

  /// Bildirimden "Kayıplar": yalnızca en üstteki ekranın kabuğu açar.
  void _onLostRequest() {
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) _openLost();
  }

  String get _levelId => _drill.isEmpty ? widget.parentId : _drill.last;

  /// Seviye yerinde değişince yeni destenin geldiği yön: içeri inilince
  /// sağdan (+1), yukarı çıkılınca soldan (-1). Bkz. [Entrance].
  double _enterFrom = 1;

  void _drillInto(Node container) {
    if (_drill.isNotEmpty && _drill.last == container.id) return;
    setState(() {
      _enterFrom = 1;
      _drill.add(container.id);
    });
  }

  bool _popDrill() {
    if (_drill.isEmpty) return false;
    setState(() {
      _enterFrom = -1;
      _drill.removeLast();
    });
    return true;
  }

  /// Bir seviyenin görünen adı (ana ekran, çekmece ya da klasörün adı).
  String? _levelLabel(InventoryStore store, String? level) => switch (level) {
        null => null,
        Roots.home => store.strings.home,
        Roots.drawer => store.strings.drawer,
        Roots.lost => store.strings.lostDrawer,
        _ => store.byId(level) == null ? null : store.nameOf(store.byId(level)!),
      };

  /// Açık seviyenin bir üstü: klasörün durduğu yer. Ana ekranda yok.
  String? _parentLevel(InventoryStore store) {
    final level = _levelId;
    if (Roots.isVirtual(level)) return null;
    final node = store.byId(level);
    return node == null ? null : store.bucketKey(node);
  }

  /// Sürüklerken bir üst seviyeye çıkar. Route açılıp kapanmaz (sürükleme
  /// kesilirdi); yığına üst seviye eklenir, ya da zaten oradan inildiyse
  /// son iniş geri alınır.
  void _goUp() {
    final store = InventoryScope.read(context);
    final parent = _parentLevel(store);
    if (parent == null) return;
    final below = _drill.length >= 2 ? _drill[_drill.length - 2] : widget.parentId;
    HapticFeedback.selectionClick();
    setState(() {
      if (_drill.isNotEmpty && below == parent) {
        _drill.removeLast();
      } else {
        _drill.add(parent);
      }
    });
  }

  /// [level] bu kabukta mı görünüyor: kendi seviyesi ya da yerinde inilen yığında.
  bool _shows(String level) => widget.parentId == level || _drill.contains(level);

  /// Yol menüsünden ya da "ana ekran"dan buraya gelindi: yerinde inilen seviyeler [level]'e
  /// kadar kırpılır, açık paneller kapanır (çekmece ya da kayıp istendiyse o açılır).
  void _arrive(String level) {
    final keep = Roots.isVirtual(level) ? 0 : _drill.lastIndexOf(level) + 1;
    if (keep < _drill.length) {
      setState(() {
        _enterFrom = -1;
        _drill.removeRange(keep, _drill.length);
      });
    }
    switch (level) {
      case Roots.drawer:
        _openPanel();
      case Roots.lost:
        _openLost();
      default:
        for (final panel in [_panel, _lostPanel, _favPanel, _expPanel]) {
          panel.reverse();
        }
    }
  }

  /// Doğrudan [level]'e gider. O seviyeyi, yoksa en yakın üst klasörünü gösteren ekran yığındaysa
  /// üstündekiler kapanır; ana ekran, çekmece ve kayıp için bu hep en alttaki ekrandır (yerinde
  /// inilmiş bir sanal kök sayılmaz). Yığında olmayan klasörler (aramadan, QR'dan, sık
  /// kullanılanlardan açılmıştı ya da ağaçtan yan bir dal seçildi) oradan, hiçbiri yoksa ana
  /// ekrandan başlayarak açılır, "yerine git" gibi: geri tuşu oradan birer birer yukarı çıkar,
  /// her destede gelinen yoldaki klasör öne gelir.
  void _goToLevel(String level) {
    final store = InventoryScope.read(context);
    final navigator = Navigator.of(context);
    final from = _levelId;
    final target = store.byId(level);
    // Ana ekrandan hedefe kadar klasörler (sanal köklerde ve hedef artık yoksa boş).
    final chain = target == null || !store.isLive(target) ? const <Node>[] : [...store.ancestorsOf(level), target];
    // Kabuklu ekranlar açılış sırasıyla, alttan üste (kapanmakta olanlar etkin sayılmaz).
    final stack = [for (final route in _shells.keys) if (route.isActive) route];
    // Zincirde yığında görünen en derin klasör ve onu gösteren en üstteki ekran: yan dala geçerken
    // ortak üst klasörün ekranı kalır, destesi de kaldığı yerde durur.
    var depth = chain.length;
    Route<dynamic>? shown;
    while (shown == null && depth > 0) {
      depth--;
      shown = stack.where((route) => _shells[route]!._shows(chain[depth].id)).lastOrNull;
    }
    final destination = shown ?? stack.where((route) => route.isFirst).firstOrNull;
    final found = _shells[destination];
    if (destination == null || found == null || !found.mounted) return;
    // Açılacaklar ve destelerinde öne gelecek klasör: hedef gelinen klasörün atasıysa yol zincirden
    // sonra gelinen yolla sürer; değilse zincirin kendisi.
    final trail = [...store.ancestorsOf(from).map((n) => n.id), from];
    final path = trail.contains(level) ? trail : [for (final n in chain) n.id];
    final opening = [
      for (var i = shown == null ? 0 : depth + 1; i < chain.length; i++) (chain[i].id, path.elementAtOrNull(i + 1)),
    ];
    if (opening.isEmpty && destination != _route) {
      // Aradakiler sessizce kalkar, yalnızca bu ekran kapanırken görünür: hepsi birden
      // küçülürken üst üste binen sayfalar ve alt çubuklar görünüyordu.
      for (final route in stack.skipWhile((route) => route != destination).skip(1)) {
        if (route != _route) navigator.removeRoute(route);
      }
      navigator.popUntil((route) => route == destination);
    }
    found._arrive(shown == null ? level : chain[depth].id);
    if (opening.isEmpty) return;
    // O ekran örtülecek: kırpılan seviyesini son açık yer diye yazmasın (yeni açılanlardan sonra
    // çizildiği için onların yazdığını eziyordu); en üstteki yeni ekran yazar.
    found._remembered = found._levelId;
    // Yalnızca hedefin açılışı görünür: aradakiler onunla birlikte görünmeden açılır (_UnderRoute),
    // üstteki eski ekranlar hedef açılana dek yerinde durup sessizce kalkar (pushAndRemoveUntil).
    // Hepsi birden açılıp kapanırken sayfalar ve başlıklar üst üste biniyordu (ekran kaydında).
    for (final (i, (id, highlight)) in opening.indexed) {
      Widget page(BuildContext _) => ContainerScreen(containerId: id, highlightId: highlight);
      final screen = i == opening.length - 1 ? MaterialPageRoute<void>(builder: page) : _UnderRoute(builder: page);
      if (i == 0) {
        navigator.pushAndRemoveUntil(screen, (route) => route == destination);
      } else {
        navigator.push(screen);
      }
    }
  }

  /// Yol menüsünün son satırı: klasör ağacı bulunulan klasörde açılır, seçilen yere gidilir. Yan
  /// bir dala (Mutfak > Dolap'tan Garaj > Raf'a) ana ekrana dönmeden ve adını aramadan geçilir.
  Future<void> _browse() async {
    final s = InventoryScope.read(context).strings;
    final picked = await pickFolder(context, title: s.whichFolderToGo, confirm: s.goHere, from: _levelId);
    if (picked != null && mounted) _goToLevel(picked);
  }

  /// Başlıktaki ada dokununca: açık klasörün üstündeki seviyeler kökten başlayarak, en altta
  /// bulunulan klasör. Birine dokununca doğrudan oraya gidilir ([_goToLevel]); en sonda "Başka
  /// klasöre git…" ([_browse]).
  Future<void> _showPath(BuildContext anchor) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final tones = Tones.of(context);
    final here = store.byId(_levelId);
    if (here == null) return;
    final above = store.ancestorsOf(here.id);
    final root = store.bucketKey(above.firstOrNull ?? here);
    // Ana ekran hep başta; klasör çekmecede ya da kayıptaysa ardından o (paneli açılır).
    final levels = [
      (Roots.home, Icons.home_rounded, tones.ink, s.home),
      if (root == Roots.drawer) (Roots.drawer, Icons.inbox_rounded, tones.ink, s.drawer),
      if (root == Roots.lost) (Roots.lost, Icons.travel_explore_rounded, tones.ink, s.lostDrawer),
      for (final n in [...above, here]) (n.id, Icons.inventory_2_rounded, Color(n.color), store.nameOf(n)),
    ];
    // Menü adın hemen altında, soldan hizalı açılır.
    final box = anchor.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final under = Rect.fromPoints(
      box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(under, Offset.zero & overlay.size),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      items: [
        for (final (i, (id, icon, color, label)) in levels.indexed)
          PopupMenuItem(
            value: id,
            child: Row(
              children: [
                // Basamak basamak içeri: ağaçtaki yeri görünsün (derin yolda sınırlı).
                SizedBox(width: 14.0 * math.min(i, 5)),
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: id == here.id ? const TextStyle(fontWeight: FontWeight.w800) : null,
                  ),
                ),
                if (id == here.id) Icon(Icons.check_rounded, size: 18, color: tones.muted),
              ],
            ),
          ),
        // Yolun dışında bir yer: menü kapanınca ağaçtan seçilir.
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          onTap: _browse,
          child: Row(
            children: [
              Icon(Icons.account_tree_rounded, size: 20, color: tones.muted),
              const SizedBox(width: 12),
              Expanded(child: Text(s.otherFolder, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ],
    );
    if (picked != null && mounted) _goToLevel(picked);
  }

  /// İnilen klasörlerden biri silinmiş olabilir; zinciri kırpıyoruz.
  /// Sanal kökler (ana ekran, çekmece) her zaman geçerli.
  void _pruneDrill(InventoryStore store) {
    while (_drill.isNotEmpty) {
      final level = _drill.last;
      if (Roots.isVirtual(level)) break;
      final n = store.byId(level);
      if (n != null && n.isContainer && store.isLive(n)) break;
      _drill.removeLast();
    }
  }

  void _openPanel() {
    // Sürüklerken kenarda beklenip açıldıysa bekleyen "kapanıyor" geçersizdir.
    _closingForDrag = false;
    _lostPanel.reverse();
    _favPanel.reverse();
    _expPanel.reverse();
    _panel.forward();
  }

  void _closePanel() => _panel.reverse();

  void _openLost() {
    _panel.reverse();
    _favPanel.reverse();
    _expPanel.reverse();
    _lostPanel.forward();
  }

  void _closeLost() => _lostPanel.reverse();

  void _openFavorites() {
    _panel.reverse();
    _lostPanel.reverse();
    _expPanel.reverse();
    _favPanel.forward();
  }

  void _closeFavorites() => _favPanel.reverse();

  void _openExpired() {
    _panel.reverse();
    _lostPanel.reverse();
    _favPanel.reverse();
    _expPanel.forward();
  }

  void _closeExpired() => _expPanel.reverse();

  /// Sürükleme başlayınca panele ne olacağı — karar sürükleme başına bir kez.
  ///
  /// Çekmecedeki bir kart çekmecenin *içinde* düzenleniyor olabilir (sıralama,
  /// bir klasöre koyma): panel açık kalır. Kart panelin dışına çıkarılınca
  /// ([_pullOut]) kenara çekilir ve arkadaki desteye bırakılabilir. Başka her
  /// durumda panel hemen çekilir. Panel ağaçta kaldığı için sürükleme kesilmez.
  void _handleDragStart(InventoryStore store) {
    final id = store.draggingId;
    if (id == null) {
      _dragHandled = null;
      // Bayrak sürüklemeyle birlikte biter; takılı kalırsa panel bir daha
      // çekilmez.
      _closingForDrag = false;
      return;
    }
    if (id == _dragHandled) return;
    _dragHandled = id;
    if (_panelsClosed) return;
    // Yatayda panel desteyi örtmüyor: açık kalır, kart doğrudan ona bırakılır.
    // Tarihi geçenler bırakma almaz; o kapanır, kenar hedefleri çıkar.
    if (landscapeLayout(context) && _expPanel.isDismissed) return;
    // Çekmece paneli açık ve kart zaten çekmecede: kullanıcı burayı düzenliyor.
    final node = store.byId(id);
    if (!_panel.isDismissed && node != null && store.bucketKey(node) == Roots.drawer) return;
    _closePanelsForDrag();
  }

  void _closePanelsForDrag() {
    if (_panelsClosed || _closingForDrag) return;
    _closingForDrag = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lostPanel.reverse();
      _favPanel.reverse();
      _expPanel.reverse();
      _panel.reverse().whenComplete(() => _closingForDrag = false);
    });
  }

  /// Sürüklenen kart panelin solundaki şeride geçti: panel çekilsin ki
  /// arkadaki desteye bırakılabilsin. Şerit dardır ama arkadaki deste oradan
  /// göründüğü için "dışarı çıkar" hareketi kendini anlatır; yanlışlıkla
  /// tetiklenmesin diye panelin içi sayılmaz. Kenardaki hedefte beklenirse
  /// panel yeniden açılır ([_EdgeTarget.onHoverOpen]) — karar sürükleme başına
  /// bir kez verildiği için bu sefer açık kalır.
  void _pullOut(PointerMoveEvent e, InventoryStore store) {
    if (store.draggingId == null || _panelsClosed || _closingForDrag) return;
    // Yatayda panel desteyi örtmüyor: kart doğrudan desteye bırakılır.
    if (landscapeLayout(context)) return;
    // Panel, gövdeyle birlikte sağdaki sistem çubuğunun iç tarafında (yatayda).
    final left = MediaQuery.sizeOf(context).width - MediaQuery.paddingOf(context).right - unsortedPanelWidth(context);
    if (e.position.dx < left) _closePanelsForDrag();
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    _pruneDrill(store);
    _handleDragStart(store);
    // Uygulama kapanıp açılınca bu seviyeye dönülür.
    if (_remembered != _levelId) {
      _remembered = _levelId;
      unawaited(store.rememberLevel(_levelId));
    }

    // Yığındaki seviye bir klasör ya da (yukarı çıkılınca) sanal bir kök.
    final drilledLevel = _drill.isEmpty ? null : _drill.last;
    final drilled = drilledLevel == null ? null : store.byId(drilledLevel);
    final levelCount = store.childCount(_levelId);
    final title = drilledLevel == null
        ? widget.title
        : drilled != null
            ? store.nameOf(drilled)
            : switch (drilledLevel) {
                Roots.drawer => s.drawer,
                Roots.lost => s.lostDrawer,
                _ => s.appTitle,
              };
    final subtitle = drilledLevel == null
        ? widget.subtitle
        : drilled != null
            ? '${store.pathLabel(drilled.id)} · ${levelCount == 0 ? s.empty : s.recordCount(levelCount)}'
            : (levelCount == 0 ? s.nothingYet : s.itemsAtRoot(levelCount));
    final leading = drilledLevel == null
        ? widget.leading
        : LevelBackButton(onPressed: _popDrill);
    final levelActions = drilledLevel == null
        ? (widget.actions ?? const <Widget>[])
        : [if (drilled != null) ContainerMenu(node: drilled)];
    final sharing = SharingScope.of(context);
    final drawerCount = store.childrenOf(Roots.drawer).length;
    // Seçim açıkken başlık seçimi anlatır, alt çubuk seçilenlere uygulanır.
    final selecting = _selection.active;
    final levelNodes = store.childrenOf(_levelId);
    if (selecting) _selection.retain({for (final n in levelNodes) n.id});
    final allSelected = levelNodes.isNotEmpty && levelNodes.every((n) => _selection.contains(n.id));
    final wide = landscapeLayout(context);
    final lostCount = store.childrenOf(Roots.lost).length;
    // Yatayda gövdenin dışında kalan yan paylar (panellerin karartması oraya da taşar).
    final side = MediaQuery.paddingOf(context);
    final bleed = EdgeInsets.only(left: side.left, right: side.right);

    return PopScope(
      canPop: _drill.isEmpty && _panelsClosed && !selecting && !_menuOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_menuOpen) {
          _scaffoldKey.currentState?.closeDrawer();
          return;
        }
        if (selecting) {
          _selection.end();
          return;
        }
        if (!_panelsClosed) {
          _closeFavorites();
          _closeExpired();
          _closePanel();
          _closeLost();
          return;
        }
        _popDrill();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: widget.showLeftDrawer ? const LeftDrawer() : null,
        onDrawerChanged: (open) {
          if (open != _menuOpen && mounted) setState(() => _menuOpen = open);
        },
        appBar: selecting
            ? ShellHeader(
                title: s.selectedCount(_selection.count),
                eyebrow: _selection.count == 0 ? s.selectHint : title,
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: s.doneSelecting,
                  onPressed: _selection.end,
                ),
                actions: [
                  IconButton(
                    tooltip: s.selectAll,
                    icon: Icon(allSelected ? Icons.deselect_rounded : Icons.select_all_rounded),
                    onPressed: () => _selection.toggleAll(levelNodes.map((n) => n.id)),
                  ),
                ],
              )
            : ShellHeader(
                title: title,
                badge: drilledLevel == null ? widget.titleBadge : null,
                eyebrow: subtitle,
                leading: leading,
                compact: wide,
                // Klasörde ada dokununca üst seviyeler: derinden birer birer dönmek uzun sürüyordu.
                onTitleTap: store.byId(_levelId) == null ? null : _showPath,
                titleTooltip: s.parentFolders,
                actions: [
                  ...levelActions,
                  // Üst çubukta yalnızca zil ve çekmece: kayıp, sık kullanılanlar,
                  // ortak kullanım sol menüde (kayıp varsa sağ kenarda kulbu da çıkar).
                  if (sharing.enabled || store.pendingCount > 0) const ChangesBell(),
                  IconButton(
                    tooltip: s.drawer,
                    // Aç/kapat: panel açıkken dokunmak onu kapatır.
                    onPressed: () => _panel.isDismissed ? _openPanel() : _closePanel(),
                    icon: Badge(
                      isLabelVisible: drawerCount > 0,
                      backgroundColor: Tones.of(context).ink,
                      textColor: Tones.of(context).paper,
                      label: Text('$drawerCount'),
                      child: const Icon(Icons.inbox_rounded),
                    ),
                  ),
                  // Yatayda sağ kenar kulpları yok (kartların üstüne biniyordu):
                  // kayıp, sık kullanılanlar ve tarihi geçenler burada, varken.
                  if (wide) ...[
                    if (lostCount > 0)
                      _PanelButton(
                        tooltip: s.lostDrawer,
                        icon: Icons.question_mark_rounded,
                        count: lostCount,
                        color: Tones.of(context).lost,
                        open: () => _lostPanel.isDismissed ? _openLost() : _closeLost(),
                      ),
                    if (store.favorites.isNotEmpty)
                      _PanelButton(
                        tooltip: s.favorites,
                        icon: Icons.star_rounded,
                        count: store.favorites.length,
                        color: cardTone(kCardPalette[4].toARGB32(), Theme.of(context).brightness),
                        open: () => _favPanel.isDismissed ? _openFavorites() : _closeFavorites(),
                      ),
                    if (store.expiredItems.isNotEmpty)
                      _PanelButton(
                        tooltip: s.expiredPanel,
                        icon: Icons.event_busy_rounded,
                        count: store.expiredItems.length,
                        color: Tones.of(context).danger,
                        open: () => _expPanel.isDismissed ? _openExpired() : _closeExpired(),
                      ),
                  ],
                ],
              ),
        // Yatayda sistem çubuğu ve kamera çentiği yanlara geçer: deste, sağ
        // kenardaki kulplar ve paneller onların iç tarafında kalsın (kulplar
        // üç düğmenin altında, kartların bir kısmı çentiğin altında kalıyordu).
        // Sürüklerken seviye değişince kaynak kart ağaçtan düşüyor ve
        // Draggable.onDragEnd hiç çağrılmıyor; parmak kalkınca durumu
        // burada temizliyoruz.
        body: SafeArea(
          top: false,
          bottom: false,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerUp: (_) => store.setDragging(null),
            onPointerCancel: (_) => store.setDragging(null),
            onPointerMove: (e) => _pullOut(e, store),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  // Alttaki yüzen düğmeler destenin son kartını örtmesin. Yatayda
                  // düğmeler soldaki şeritte; açık panel de desteyi örtmez, deste
                  // onun yanına daralır.
                  child: AnimatedBuilder(
                    animation: _docked,
                    builder: (context, child) => Padding(
                      padding: wide
                          ? EdgeInsets.only(
                              left: kSideRailWidth,
                              right: _dockedValue * unsortedPanelWidth(context),
                              bottom: selecting ? 84 : 0,
                            )
                          : const EdgeInsets.only(bottom: 84),
                      child: child,
                    ),
                    child: Column(
                      children: [
                        if (drilledLevel == null && widget.banner != null) widget.banner!,
                        Expanded(
                          // Seviye yerinde değişince (sürükleyerek inilen klasörden geri
                          // dönüş) deste hafifçe kayarak belirir. Sürüklerken hareketsiz:
                          // parmağın altındaki hedefler kıpırdamasın.
                          child: Entrance(
                            trigger: _levelId,
                            enabled: store.draggingId == null,
                            offset: Offset(22 * _enterFrom, 0),
                            child: _LevelDropZone(
                            parentId: _levelId,
                            title: title,
                            child: NodeListView(
                              // Seviye değişince deste baştan kurulsun.
                              key: ValueKey(_levelId),
                              parentId: _levelId,
                              highlightId: drilledLevel == null ? widget.highlightId : null,
                              onHoverDrill: _drillInto,
                              selection: _selection,
                              // Dikeyde sağ kenarda kulplar durur (yatayda başlıktalar).
                              edgeInset: wide ? 0 : kEdgeHandleInset,
                            ),
                          ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Yatayda: arama, QR ve yeni kayıt soldaki dikey şeritte.
                if (wide)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: kSideRailWidth,
                    child: selecting ? const SizedBox.shrink() : _SideRail(parentId: _levelId),
                  ),
                Positioned(
                  top: 0,
                  right: 0,
                  // Kulplar alttaki düğmelerle çakışmasın; sürüklerken alt çubuk
                  // gizlendiği için hedefler tüm yüksekliği kullanır.
                  bottom: store.draggingId == null ? 90 + MediaQuery.paddingOf(context).bottom : 0,
                  // Seçerken paneller açılmaz; kulplar da yok.
                  child: selecting
                      ? const SizedBox.shrink()
                      : DrawerEdge(
                          panel: _panel,
                          lostPanel: _lostPanel,
                          favPanel: _favPanel,
                          expPanel: _expPanel,
                          onOpen: _openPanel,
                          onOpenLost: _openLost,
                          onOpenFavorites: _openFavorites,
                          onOpenExpired: _openExpired,
                          // Yatayda kulplar başlıkta; sürüklerken kenar hedefleri yine
                          // çıkar, ama açık panel varsa onun üstüne binmesin (bırakma
                          // doğrudan panele).
                          handles: !wide,
                          targets: !wide || _panelsClosed,
                        ),
                ),
                // Alt çubuğun arkasında kağıda doğru yumuşak bir geçiş: kaydırılan
                // kartlar çubuğun altına girerken sönükleşir. Gradyan yerine üst
                // üste binen saydam şeritler (emülatörün GPU katmanı gradyanlarda
                // sorun çıkarabiliyor).
                if (store.draggingId == null && !wide)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 96 + MediaQuery.paddingOf(context).bottom,
                    child: IgnorePointer(child: _PaperFade(color: Tones.of(context).paper)),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: selecting
                      ? SelectionBar(selection: _selection, levelId: _levelId)
                      : wide
                          ? const SizedBox.shrink()
                          : _BottomBar(parentId: _levelId),
                ),
                // Sürüklerken: vazgeçme ve bir üst seviyeye çıkma noktaları.
                if (store.draggingId != null)
                  Positioned(
                    left: wide ? kSideRailWidth : 0,
                    // Sağ kenardaki çekmece/kayıp hedefleri açık kalsın.
                    right: 84,
                    bottom: 0,
                    child: _DragDock(
                      parentLevel: _parentLevel(store),
                      parentLabel: _levelLabel(store, _parentLevel(store)),
                      onUp: _goUp,
                    ),
                  ),
                UnsortedPanel(controller: _panel, onClose: _closePanel, bleed: bleed, docked: wide),
                UnsortedPanel(
                  controller: _lostPanel,
                  onClose: _closeLost,
                  kind: PanelKind.lost,
                  bleed: bleed,
                  docked: wide,
                ),
                UnsortedPanel(
                  controller: _favPanel,
                  onClose: _closeFavorites,
                  kind: PanelKind.favorites,
                  bleed: bleed,
                  docked: wide,
                ),
                UnsortedPanel(
                  controller: _expPanel,
                  onClose: _closeExpired,
                  kind: PanelKind.expired,
                  bleed: bleed,
                  docked: wide,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Açık olan seviyenin zemini de bırakma hedefi. Bir klasörün üzerinde
/// bekleyip içine girdikten sonra kart boş alana bırakılınca o klasöre
/// düşüyor; ana ekranda ise kayıt köke çıkıyor.
class _LevelDropZone extends StatelessWidget {
  const _LevelDropZone({
    required this.parentId,
    required this.title,
    required this.child,
  });

  final String parentId;
  final String title;
  final Widget child;

  String _label(AppStrings s) => switch (parentId) {
        Roots.home => s.intoHome,
        Roots.drawer => s.intoDrawer,
        _ => s.intoContainer(title),
      };

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final scheme = Theme.of(context).colorScheme;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => store.canMove(details.data, parentId),
      onAcceptWithDetails: (details) async {
        final node = store.byId(details.data);
        final messenger = ScaffoldMessenger.of(context);
        store.setDragging(null);
        if (node == null) return;
        // Klasör bu seviyeye bırakıldı: kendisi mi gitsin, içindekiler mi?
        if (node.isContainer) {
          return NodeActions.dropFolder(context, folder: node, targetId: parentId);
        }
        final ok = await store.move(details.data, parentId);
        if (!ok) return;
        NodeActions.movedNotice(messenger, store, [node], s.movedTo(store.nameOf(node), store.pathLabel(node.id)));
      },
      builder: (context, candidate, _) => Stack(
        children: [
          Positioned.fill(child: child),
          if (candidate.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: 8,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.south_rounded, size: 16, color: scheme.onPrimary),
                        const SizedBox(width: 8),
                        Text(
                          '${s.dropHere}: ${_label(s)}',
                          style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Liste görünümünde satırların sağ kenardaki kulplardan uzak durması için
/// bırakılan pay: kulp 22dp eninde, satırlar zaten 16dp içeride; arada 6dp kalır.
const double kEdgeHandleInset = 12;

/// Sağ kenardaki şerit. Sürüklenmiyorken çekmece kulbu, kayıp varsa kayıp
/// kulbu, sık kullanılan varsa onun kulbu; sürüklerken iki bırakma hedefi
/// (çekmece ve kayıp).
class DrawerEdge extends StatelessWidget {
  const DrawerEdge({
    super.key,
    required this.panel,
    required this.lostPanel,
    required this.favPanel,
    required this.expPanel,
    required this.onOpen,
    required this.onOpenLost,
    required this.onOpenFavorites,
    required this.onOpenExpired,
    this.handles = true,
    this.targets = true,
  });

  /// Sürüklenmezken kulplar gösterilsin mi (yatayda başlıkta oldukları için yok).
  final bool handles;

  /// Sürüklerken kenar hedefleri gösterilsin mi.
  final bool targets;

  final AnimationController panel;
  final AnimationController lostPanel;
  final AnimationController favPanel;
  final AnimationController expPanel;
  final VoidCallback onOpen;
  final VoidCallback onOpenLost;
  final VoidCallback onOpenFavorites;
  final VoidCallback onOpenExpired;

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final lostCount = store.childrenOf(Roots.lost).length;
    final drawerCount = store.childrenOf(Roots.drawer).length;
    final favorites = store.favorites.length;
    final expired = store.expiredItems.length;
    final tones = Tones.of(context);

    if (store.draggingId == null) {
      if (!handles) return const SizedBox.shrink();
      // Yatay telefonda yükseklik az: kulplar kısalır.
      return LayoutBuilder(builder: (context, c) {
        final short = c.maxHeight < 330;
        return _EdgeExclusion(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _EdgeHandle(
                panel: panel,
                onOpen: onOpen,
                height: short ? 64 : 92,
                slack: short ? 12 : 36,
                icon: Icons.inbox_rounded,
                count: drawerCount,
              ),
              SizedBox(height: short ? 8 : 12),
              // Kayıp kulbu yalnızca kayıp varken: herkes görsün, yoksa kenar
              // boşuna kalabalık olmasın.
              if (lostCount > 0) ...[
                SizedBox(height: short ? 8 : 12),
                _EdgeHandle(
                  panel: lostPanel,
                  onOpen: onOpenLost,
                  height: short ? 52 : 70,
                  slack: short ? 12 : 36,
                  color: tones.lost,
                  icon: Icons.question_mark_rounded,
                  tooltip: s.lostDrawer,
                  count: lostCount,
                ),
              ],
              // Sık kullanılanlara tek dokunuş: sol menüden iki dokunuş fazla
              // geldi. Sık kullanılan yoksa kulp da yok.
              if (favorites > 0) ...[
                SizedBox(height: short ? 8 : 12),
                _EdgeHandle(
                  panel: favPanel,
                  onOpen: onOpenFavorites,
                  height: short ? 52 : 70,
                  slack: short ? 12 : 36,
                  // Kart paletinden adaçayı: çekmeceden ayrılsın ama kayıbın
                  // hardalı gibi dikkat çekmesin.
                  color: cardTone(kCardPalette[4].toARGB32(), Theme.of(context).brightness),
                  icon: Icons.star_rounded,
                  tooltip: s.favorites,
                  count: favorites,
                ),
              ],
              // Tarihi geçenler: yalnızca varken; yerinden kıpırdamayan bir işaret listesi.
              if (expired > 0) ...[
                SizedBox(height: short ? 8 : 12),
                _EdgeHandle(
                  panel: expPanel,
                  onOpen: onOpenExpired,
                  height: short ? 52 : 70,
                  slack: short ? 12 : 36,
                  color: tones.danger,
                  icon: Icons.event_busy_rounded,
                  tooltip: s.expiredPanel,
                  count: expired,
                ),
              ],
            ],
          ),
        );
      });
    }

    if (!targets) return const SizedBox.shrink();
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: _EdgeTarget(
            bucket: Roots.drawer,
            label: s.drawer,
            icon: Icons.inbox_rounded,
            onHoverOpen: onOpen,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          flex: 2,
          child: _EdgeTarget(
            bucket: Roots.lost,
            label: s.lostShort,
            icon: Icons.travel_explore_rounded,
            color: tones.lost,
          ),
        ),
      ],
    );
  }
}

/// Kulpların ekrandaki yerini yerel tarafa bildirir: jest gezinmesinde sağ
/// kenar Android'in "geri" hareketine ait, kulpların şeridi ondan muaf tutulur
/// (yoksa parmak biraz kayınca dokunuşu sistem alıyordu). Kulplar dikeyde
/// ortalanır; yer, ekran dönünce ya da kulp eklenip çıkınca değişir.
class _EdgeExclusion extends StatefulWidget {
  const _EdgeExclusion({required this.child});

  final Widget child;

  @override
  State<_EdgeExclusion> createState() => _EdgeExclusionState();
}

class _EdgeExclusionState extends State<_EdgeExclusion> {
  final _key = GlobalKey();

  /// Son bildirilen yer (bütün kabuklar için tek: ekran aynı).
  static (double, double)? _sent;

  void _report() {
    if (!mounted) return;
    // Üstte başka bir sayfa varken alttaki kabuğun kulpları bildirmesin.
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final global = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
    final rect = (global.top, global.bottom);
    if (rect == _sent) return;
    _sent = rect;
    unawaited(PlatformBridge.setEdgeExclusion(rect.$1, rect.$2));
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    // Genişlik kulp kadar (Center tam genişliğe yayılıp kulpları ortaya taşımasın).
    // Kısa ekranda (yatay telefon) bütün kulplar sığmazsa sütun orantılı küçülür:
    // taşan kulp çizilse de dokunuş almıyordu.
    return Center(
      widthFactor: 1,
      child: FittedBox(fit: BoxFit.scaleDown, child: KeyedSubtree(key: _key, child: widget.child)),
    );
  }
}

/// Kenara yapışık kulp; sol köşeleri yuvarlak, sağı düz. Android'in kenar
/// "geri" hareketi en dıştaki ~20dp'yi sahiplendiği için dokunma her
/// koşulda, çekme kulbun iç kısmından çalışır.
class _EdgeHandle extends StatelessWidget {
  const _EdgeHandle({
    required this.panel,
    required this.onOpen,
    required this.height,
    required this.icon,
    this.slack = 36,
    this.color,
    this.tooltip,
    this.count = 0,
  });

  final AnimationController panel;
  final VoidCallback onOpen;
  final double height;
  final IconData icon;

  /// Dokunma alanının kulbun üstünde ve altındaki payı (toplam).
  final double slack;
  final Color? color;
  final String? tooltip;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final width = unsortedPanelWidth(context);
    final fill = color ?? tones.surface;
    final ink = color == null ? tones.muted : kInk;

    final handle = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      onHorizontalDragUpdate: (d) => panel.value -= d.primaryDelta! / width,
      onHorizontalDragEnd: (d) {
        final fling = d.primaryVelocity ?? 0;
        // Birkaç piksel kayan dokunuş da açar: Android 8dp'den sonra sürükleme
        // sayıyor, yatayda başparmakla dokunurken kulp hiç açılmıyordu.
        final nudge = panel.value < 24 / width && fling.abs() < 800;
        if (fling < -250 || panel.value > 0.4 || nudge) {
          onOpen();
        } else {
          panel.reverse();
        }
      },
      // Dolap klasörlerinin kenardan taşan sekmeleri gibi.
      child: SizedBox(
        width: 28,
        height: height + slack,
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: 22,
            height: height,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
              border: Border(
                top: BorderSide(color: color ?? tones.line),
                left: BorderSide(color: color ?? tones.line),
                bottom: BorderSide(color: color ?? tones.line),
              ),
              boxShadow: [
                BoxShadow(color: tones.shadow.withValues(alpha: 0.10), blurRadius: 8, offset: const Offset(-2, 2)),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: ink),
                if (count > 0) ...[
                  const SizedBox(height: 4),
                  // Kulp 22dp eninde: sayı, yazı büyütülse de içine sığacak boyda kalır.
                  Text(
                    '$count',
                    textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: kFixedTextScale),
                    style: TextStyle(color: ink, fontSize: 10.5, fontWeight: FontWeight.w800),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? handle : Tooltip(message: tooltip!, child: handle);
  }
}

/// Sürüklerken kenardaki bırakma hedefi.
class _EdgeTarget extends StatefulWidget {
  const _EdgeTarget({
    required this.bucket,
    required this.label,
    required this.icon,
    this.color,
    this.onHoverOpen,
  });

  final String bucket;
  final String label;
  final IconData icon;
  final Color? color;

  /// Üzerinde beklenince paneli açar.
  final VoidCallback? onHoverOpen;

  @override
  State<_EdgeTarget> createState() => _EdgeTargetState();
}

class _EdgeTargetState extends State<_EdgeTarget> {
  Timer? _timer;
  bool _hot = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _enter() {
    if (_hot) return;
    setState(() => _hot = true);
    _timer?.cancel();
    final open = widget.onHoverOpen;
    if (open == null) return;
    _timer = Timer(const Duration(milliseconds: 700), () {
      if (mounted && _hot) open();
    });
  }

  void _leave() {
    _timer?.cancel();
    if (_hot && mounted) setState(() => _hot = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    final accent = widget.color ?? tones.ink;
    final onAccent = widget.color == null ? tones.paper : kInk;
    final lost = widget.bucket == Roots.lost;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final ok = store.canMove(details.data, widget.bucket);
        // Kart zaten çekmecedeyse bırakmak bir şeyi değiştirmez ("zaten orada"
        // diye canMove false döner) ama kullanıcının derdi paneli geri açmak
        // olabilir: bekleme, kabul edilmese de başlar.
        if (ok || widget.onHoverOpen != null) _enter();
        return ok;
      },
      onLeave: (_) => _leave(),
      onAcceptWithDetails: (details) async {
        _leave();
        final node = store.byId(details.data);
        final messenger = ScaffoldMessenger.of(context);
        store.setDragging(null);
        if (node == null) return;
        // Klasör çekmeceye bırakıldı: kendisi mi gitsin, içindekiler mi?
        if (node.isContainer && !lost) {
          await NodeActions.dropFolder(context, folder: node, targetId: widget.bucket);
          return;
        }
        if (!await store.move(details.data, widget.bucket)) return;
        NodeActions.movedNotice(
          messenger,
          store,
          [node],
          lost ? s.markedLost(store.nameOf(node)) : s.movedToDrawer(store.nameOf(node)),
        );
      },
      builder: (context, _, _) => Align(
        alignment: Alignment.centerRight,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: _hot ? 88 : 58,
          decoration: BoxDecoration(
            color: _hot ? accent : (widget.color ?? tones.surface).withValues(alpha: 0.94),
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
            border: widget.color == null && !_hot ? Border.all(color: tones.line) : null,
            boxShadow: [
              BoxShadow(color: tones.shadow.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(-4, 4)),
            ],
          ),
          child: Center(
            child: RotatedBox(
              quarterTurns: 3,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.icon,
                    color: _hot || widget.color != null ? onAccent : tones.ink,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontFamily: kDisplayFont,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: _hot || widget.color != null ? onAccent : tones.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Görünüm düğmesi (alttaki çubukta ve yatayda soldaki şeritte): her dokunuş
/// sıradaki görünüme geçer (deste → liste → ızgara → deste). Simge ve ipucu,
/// dokununca geçilecek görünümü gösterir. Üçünden birini doğrudan seçmek
/// Ayarlar → Bu envanter → Görünüm'de.
class ViewModeButton extends StatelessWidget {
  const ViewModeButton({super.key, this.dense = false});

  /// Alt çubukta: düğmeler sıkı dizilir.
  final bool dense;

  /// [view]'dan sonra gelen görünüm.
  static DeckView after(DeckView view) => DeckView.values[(view.index + 1) % DeckView.values.length];

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final next = after(store.settings.deckView);
    return IconButton(
      tooltip: s.showAs(viewLabel(s, next)),
      style: dense ? kDenseIcon : null,
      icon: Icon(viewIcon(next), color: Tones.of(context).ink),
      // Ayar o an okunur: art arda iki hızlı dokunuş aynı görünüme iki kez geçmesin.
      onPressed: () => store.updateSettings(store.settings.copyWith(deckView: after(store.settings.deckView))),
    );
  }
}

/// Alt çubuktaki sıkı simge düğmesi: 40dp eninde (varsayılan 48), boyu aynı
/// (48dp): üç düğme yan yana dururken arama yazısına yer kalsın, çubuk incelmesin
/// ve dokunma alanı küçülmesin.
final ButtonStyle kDenseIcon = IconButton.styleFrom(
  minimumSize: const Size(40, 48),
  maximumSize: const Size(40, 48),
  fixedSize: const Size(40, 48),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// Sıralama seçimi (alt çubukta ve yatayda soldaki şeritte): "Benim sıram"
/// (elle dizilen, varsayılan), ada göre, son eklenen, tarihi en yakın.
/// Varsayılandan farklıysa simge kiremit renginde durur: kartların neden
/// dizdiğin sırada olmadığı görülsün.
class SortButton extends StatelessWidget {
  const SortButton({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    final current = store.settings.deckSort;
    return IconButton(
      tooltip: s.sortTitle,
      style: dense ? kDenseIcon : null,
      icon: Icon(Icons.swap_vert_rounded, color: current == DeckSort.manual ? tones.ink : tones.accent),
      onPressed: () async {
        final box = context.findRenderObject()! as RenderBox;
        final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
        final picked = await showMenu<DeckSort>(
          context: context,
          position: RelativeRect.fromRect(
            box.localToGlobal(Offset.zero, ancestor: overlay) & box.size,
            Offset.zero & overlay.size,
          ),
          items: [
            for (final sort in DeckSort.values)
              CheckedPopupMenuItem(value: sort, checked: sort == current, child: Text(sortLabel(s, sort))),
          ],
        );
        if (picked != null && picked != current) {
          await store.updateSettings(store.settings.copyWith(deckSort: picked));
        }
      },
    );
  }
}

/// Alttaki + ve yatayda soldaki şeridin +'sı: eşya mı klasör mü sorulur; üçüncü seçenek
/// seri ekleme (birçok eşya art arda, kamerayla ya da galeriden; bkz. [BurstAddPage]).
Future<void> _addRecord(BuildContext context, String parentId) async {
  final choice = await showAppSheet<Object>(context, (context) => const _NewRecordSheet());
  if (choice == null || !context.mounted) return;
  if (choice == _NewRecordSheet.burst) {
    await BurstAddPage.start(context, parentId);
    return;
  }
  if (choice is NodeKind) await NodeActions.create(context, parentId: parentId, kind: choice);
}

/// Yatay düzende alttaki çubuğun yerine soldaki dikey şerit: ara, QR, yeni
/// kayıt. Alt çubuk yatayda destenin yarısını kapatıyordu.
class _SideRail extends StatelessWidget {
  const _SideRail({required this.parentId});

  final String parentId;

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    // Sürüklerken şerit de boşalır (alttaki çubuk gibi); deste yeri değişmez.
    if (store.draggingId != null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottomInset(context)),
      child: Column(
        children: [
          RoundSlot(
            child: IconButton(
              tooltip: s.search,
              icon: Icon(Icons.search_rounded, color: tones.ink),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
            ),
          ),
          const SizedBox(height: 12),
          RoundSlot(
            child: IconButton(
              tooltip: s.scanQr,
              icon: Icon(Icons.qr_code_scanner_rounded, color: tones.ink),
              onPressed: () => scanQrAndOpen(context, parentId: parentId),
            ),
          ),
          const SizedBox(height: 12),
          const RoundSlot(child: ViewModeButton()),
          const SizedBox(height: 12),
          const RoundSlot(child: SortButton()),
          const Spacer(),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(color: tones.accent.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8)),
              ],
            ),
            child: Material(
              color: tones.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _addRecord(context, parentId),
                child: Tooltip(
                  message: s.newRecord,
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(Icons.add_rounded, size: 28, color: tones.onAccent),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Yatay düzende başlıktaki panel düğmesi (kayıp, sık kullanılanlar, tarihi
/// geçenler): sağ kenar kulbunun yerine, rengi ve sayısıyla.
class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.tooltip,
    required this.icon,
    required this.count,
    required this.color,
    required this.open,
  });

  final String tooltip;
  final IconData icon;
  final int count;
  final Color color;
  final VoidCallback open;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: open,
        icon: Badge(
          backgroundColor: color,
          textColor: kInk,
          label: Text('$count'),
          child: Icon(icon),
        ),
      );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.parentId});

  final String parentId;

  Future<void> _add(BuildContext context) => _addRecord(context, parentId);

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    // Sürükleme sırasında alt bar yolu kapatmasın.
    if (store.draggingId != null) return const SizedBox.shrink();
    final narrow = MediaQuery.sizeOf(context).width < 340;
    final lift = [
      BoxShadow(color: tones.shadow.withValues(alpha: 0.14), blurRadius: 24, offset: const Offset(0, 10)),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SizedBox(
              height: 58,
              child: Row(
                children: [
                  // Arama kutusu gibi görünen düğme: dokununca arama açılır,
                  // sağındaki simge QR'ı doğrudan okutur.
                  Expanded(
                    child: DecoratedBox(
                      decoration: ShapeDecoration(shape: const StadiumBorder(), shadows: lift),
                      child: Material(
                        color: tones.surface,
                        shape: StadiumBorder(side: BorderSide(color: tones.line)),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SearchPage()),
                          ),
                          child: Tooltip(
                            message: s.search,
                            child: Row(
                              children: [
                                const SizedBox(width: 18),
                                Icon(Icons.search_rounded, size: 24, color: tones.ink),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: narrow
                                      ? const SizedBox.shrink()
                                      // Dar çubukta uzun yazı "Envan…" diye kesiliyordu: kısası yazar.
                                      : LayoutBuilder(
                                          builder: (context, box) => Text(
                                            box.maxWidth < 118 ? s.search : s.searchInventory,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: tones.muted,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15.5,
                                            ),
                                          ),
                                        ),
                                ),
                                Container(width: 1, height: 26, color: tones.line),
                                IconButton(
                                  tooltip: s.scanQr,
                                  onPressed: () => scanQrAndOpen(context, parentId: parentId),
                                  // Çubukta üç düğme var: sıkı dizilir ki arama yazısına yer kalsın.
                                  style: kDenseIcon,
                                  icon: Icon(Icons.qr_code_scanner_rounded, color: tones.ink),
                                ),
                                // Deste ↔ liste: kalabalık klasörde tek dokunuşla sık satırlar.
                                const ViewModeButton(dense: true),
                                // A–Z, son eklenen, tarihi en yakın; "Benim sıram" elle dizilen.
                                const SortButton(dense: true),
                                const SizedBox(width: 4),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: tones.accent.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Material(
                      color: tones.accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _add(context),
                        child: Tooltip(
                          message: s.newRecord,
                          child: SizedBox(
                            width: 58,
                            height: 58,
                            child: Icon(Icons.add_rounded, size: 30, color: tones.onAccent),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperFade extends StatelessWidget {
  const _PaperFade({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    const steps = 8;
    return Column(
      children: [
        for (var i = 0; i < steps; i++)
          Expanded(child: ColoredBox(color: color.withValues(alpha: math.min(1, (i + 1) / steps * 1.15)))),
      ],
    );
  }
}

/// Sürüklerken altta beliren iki bırakma noktası. Solda "vazgeç": kart
/// buraya bırakılırsa hiçbir şey taşınmaz. Sağda "bir üst seviye": üzerinde
/// beklenince bir üst seviyeye çıkılır (beklemeye devam edilirse daha yukarı),
/// doğrudan bırakılırsa kart bir üst seviyeye taşınır.
class _DragDock extends StatelessWidget {
  const _DragDock({required this.parentLevel, required this.parentLabel, required this.onUp});

  final String? parentLevel;
  final String? parentLabel;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final tones = Tones.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 0, 14),
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              Flexible(
                child: _DockTarget(
                  key: const ValueKey('dock_cancel'),
                  icon: Icons.close_rounded,
                  label: s.cancelDrag,
                  color: tones.ink,
                  onColor: tones.paper,
                  accepts: (_) => true,
                  onDrop: (_) async => HapticFeedback.lightImpact(),
                ),
              ),
              if (parentLevel != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _DockTarget(
                    key: const ValueKey('dock_up'),
                    icon: Icons.arrow_upward_rounded,
                    label: s.upOneLevel,
                    detail: parentLabel,
                    color: tones.accent,
                    onColor: tones.onAccent,
                    onHover: onUp,
                    accepts: (id) => InventoryScope.read(context).canMove(id, parentLevel!),
                    onDrop: (id) async {
                      final store = InventoryScope.read(context);
                      final messenger = ScaffoldMessenger.of(context);
                      final node = store.byId(id);
                      if (node == null) return;
                      if (node.isContainer) {
                        return NodeActions.dropFolder(
                          context,
                          folder: node,
                          targetId: parentLevel!,
                        );
                      }
                      final ok = await store.move(id, parentLevel!);
                      if (!ok) return;
                      NodeActions.movedNotice(
                        messenger,
                        store,
                        [node],
                        s.movedTo(store.nameOf(node), store.pathLabel(node.id)),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DockTarget extends StatefulWidget {
  const _DockTarget({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onColor,
    required this.accepts,
    required this.onDrop,
    this.detail,
    this.onHover,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final Color color;
  final Color onColor;

  /// Bu kart buraya bırakılabilir mi (üzerinde beklemek her zaman çalışır).
  final bool Function(String id) accepts;
  final Future<void> Function(String id) onDrop;

  /// Üzerinde beklenince aralıklarla çağrılır (bir üst seviyeye çıkmak).
  final VoidCallback? onHover;

  @override
  State<_DockTarget> createState() => _DockTargetState();
}

class _DockTargetState extends State<_DockTarget> {
  Timer? _timer;
  bool _hot = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _enter() {
    if (!_hot) {
      HapticFeedback.selectionClick();
      setState(() => _hot = true);
    }
    final hover = widget.onHover;
    if (hover == null || _timer != null) return;
    _timer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (mounted && _hot) hover();
    });
  }

  void _leave() {
    _timer?.cancel();
    _timer = null;
    if (_hot && mounted) setState(() => _hot = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final tones = Tones.of(context);
    final compact = widget.detail == null && widget.onHover == null;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        _enter();
        return widget.accepts(details.data);
      },
      onLeave: (_) => _leave(),
      onAcceptWithDetails: (details) async {
        _leave();
        store.setDragging(null);
        await widget.onDrop(details.data);
      },
      builder: (context, _, _) => AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: _hot ? 1.06 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 64,
          padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 14),
          decoration: BoxDecoration(
            color: _hot ? widget.color : tones.surface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: _hot ? widget.color : tones.line, width: 1.5),
            boxShadow: [
              BoxShadow(color: tones.shadow.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 8)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _hot ? widget.onColor.withValues(alpha: 0.18) : widget.color,
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, size: 20, color: widget.onColor),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: _hot ? widget.onColor : tones.ink,
                      ),
                    ),
                    if (widget.detail != null)
                      Text(
                        widget.detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: kDisplayFont,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: _hot ? widget.onColor.withValues(alpha: 0.85) : tones.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Yeni kayıt": eşya mı klasör mü. İki küçük kart; biri fiş kartı, biri
/// klasör, tıpkı destede göründükleri gibi.
class _NewRecordSheet extends StatelessWidget {
  const _NewRecordSheet();

  /// Seri ekleme seçeneğinin dönüş değeri (öteki iki seçenek [NodeKind] döner).
  static const burst = 'burst';

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final tones = Tones.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: tones.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Text(s.newRecord, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _KindOption(
                      kind: NodeKind.item,
                      color: kCardPalette[6],
                      title: s.addItem,
                      subtitle: s.addItemSubtitle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _KindOption(
                      kind: NodeKind.container,
                      color: kCardPalette[4],
                      title: s.addContainer,
                      subtitle: s.addContainerSubtitle,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Koli boşaltırken, oda dizerken: kamera açık kalır ya da galeriden toplu seçilir; sonra yalnızca
            // adlara bakılır.
            Material(
              color: tones.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: tones.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(Icons.burst_mode_outlined),
                title: Text(s.burstAdd),
                subtitle: Text(s.burstAddHint),
                onTap: () => Navigator.of(context).pop(burst),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindOption extends StatelessWidget {
  const _KindOption({
    required this.kind,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final NodeKind kind;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tone = cardTone(color.toARGB32(), Theme.of(context).brightness);
    final ink = onColorOf(tone);
    final container = kind == NodeKind.container;
    return Material(
      color: tone,
      shape: NodeCard.cardShape(kind),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(kind),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, container ? 22 : 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: container ? ink : ink.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(glyphFor(kind), size: 20, color: container ? tone : ink),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: TextStyle(fontFamily: kDisplayFont, fontSize: 19, fontWeight: FontWeight.w600, color: ink),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(fontSize: 12.5, height: 1.35, color: ink.withValues(alpha: 0.7))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sağdan kayan çekmece. Kapalıyken ekran dışına ötelenir ama ağaçta kalır;
/// içindeki kartlardan başlayan sürükleme bu sayede kesilmiyor.
class UnsortedPanel extends StatelessWidget {
  const UnsortedPanel({
    super.key,
    required this.controller,
    required this.onClose,
    this.kind = PanelKind.drawer,
    this.bleed = EdgeInsets.zero,
    this.docked = false,
  });

  final AnimationController controller;
  final VoidCallback onClose;

  /// Hangi panel: çekmece, kayıp ya da sık kullanılanlar.
  final PanelKind kind;

  /// Karartmanın gövdenin dışına taşacağı pay: yatayda gövde sistem çubuğunun
  /// ve çentiğin iç tarafında, karartma yine ekranın kenarına kadar.
  final EdgeInsets bleed;

  /// Yatay düzen: panel desteyi örtmez, yanında durur (karartma yok, deste
  /// daralır; kart panelden desteye ya da desteden panele doğrudan sürüklenir).
  final bool docked;

  @override
  Widget build(BuildContext context) {
    final width = unsortedPanelWidth(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = controller.value;
        final closed = t == 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Anahtarlar şart: perde eklenip çıkınca panel yeniden
            // kurulmasın, içindeki kartların bağlamı yaşasın.
            if (!closed && !docked)
              Positioned(
                left: -bleed.left,
                right: -bleed.right,
                top: 0,
                bottom: 0,
                key: const ValueKey('scrim'),
                child: IgnorePointer(
                  ignoring: closed,
                  child: GestureDetector(
                    onTap: onClose,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.5 * t),
                    ),
                  ),
                ),
              ),
            Positioned(
              key: const ValueKey('panel'),
              top: 0,
              bottom: 0,
              right: 0,
              width: width,
              // Kapalıyken Offstage: hiçbir şey boyanmaz ve dokunuş almaz (kenara
              // gölge düşmesin), ama ağaçta kalır; çekmecedeki bir karttan
              // başlamış sürükleme panel kapanınca kesilmez.
              child: Offstage(
                offstage: closed,
                child: Transform.translate(
                  offset: Offset(width * (1 - t), 0),
                  child: Material(
                    elevation: docked ? 0 : 16 * t,
                    color: Theme.of(context).colorScheme.surface,
                    shape: docked
                        ? Border(left: BorderSide(color: Tones.of(context).line))
                        : null,
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: GestureDetector(
        onHorizontalDragUpdate: (d) => controller.value -= d.primaryDelta! / width,
        onHorizontalDragEnd: (d) {
          final fling = d.primaryVelocity ?? 0;
          if (fling > 250 || controller.value < 0.6) {
            controller.reverse();
          } else {
            controller.forward();
          }
        },
        child: UnsortedDrawerBody(onClose: onClose, kind: kind),
      ),
    );
  }
}

/// Kabuğun üst kısmı: küçük harf aralıklı bir üst satır (yer ve sayı), altında
/// serif başlık; eylemler sağda tek bir kapsülde.
class ShellHeader extends StatelessWidget implements PreferredSizeWidget {
  const ShellHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.leading,
    this.actions = const [],
    this.trailing,
    this.compact,
    this.badge,
    this.onTitleTap,
    this.titleTooltip,
  });

  /// Adın önünde, aynı satırda duran küçük işaret (envanterin amblemi).
  final Widget? badge;

  /// Ada dokununca (klasörde: üst seviyeler menüsü). Verilirse adın yanında küçük bir ⌄ durur;
  /// menü adın altında açılsın diye adın bağlamı verilir.
  final ValueChanged<BuildContext>? onTitleTap;

  /// [onTitleTap]'in ipucu: ada uzun basınca görünür, ekran okuyucu da okur.
  final String? titleTooltip;

  /// Yatay düzen: tek satır, alçak (dikey yer yatayda değerli). Verilmezse
  /// ekranın yönüne göre ([landscape]).
  final bool? compact;

  /// Uygulamanın kökü ekran her değiştiğinde yazar (`app.dart`): başlığın
  /// yüksekliği ([preferredSize]) bağlam görmeden bilinmeli.
  static bool landscape = false;

  bool get _compact => compact ?? landscape;

  final String title;
  final String? eyebrow;
  final Widget? leading;
  final List<Widget> actions;

  /// Kapsül dışında, en sağda tek bir bileşen (ör. "Kaydet").
  final Widget? trailing;

  @override
  Size get preferredSize => Size.fromHeight(_compact ? 58 : 78);

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final theme = Theme.of(context);
    final s = AppStrings.of(context);
    final eyebrow = this.eyebrow;
    final badge = this.badge;
    // Ad kısalsa da işaret yerinde kalır; ikisi aynı satırda ortalı. Tek satırlık
    // başlıkta işaret, yazıları taban çizgisinde hizalayan satırın dışında durur
    // (içindeki simgenin de bir taban çizgisi var: hizayı o belirlerdi).
    Widget titled(Widget text) => badge == null
        ? text
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [badge, const SizedBox(width: 9), Flexible(child: text)],
          );
    // Ad değişince (seviye, seçim) yenisi kısa bir solmayla belirir.
    Widget fresh(Widget text) =>
        Entrance(trigger: title, fadeFrom: 0.3, duration: const Duration(milliseconds: 200), child: text);
    final onTitleTap = this.onTitleTap;
    final titleTooltip = this.titleTooltip;
    // Ada dokunulabiliyorsa (klasörde yol menüsü) yanında küçük bir ⌄ durur.
    final chevron = onTitleTap == null ? null : Icon(Icons.expand_more_rounded, size: 22, color: tones.muted);
    // Yalnızca yazının kapladığı yer dokunuş alır, başlığın boş kalan yeri değil. Tek satırlık
    // başlıkta satır alçak: dokunma payı üstten ve alttan verilir (yazı yerinden oynamaz).
    Widget tappable(Widget heading) {
      final button = Builder(
        builder: (anchor) => InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onTitleTap!(anchor),
          child: _compact ? Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: heading) : heading,
        ),
      );
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: titleTooltip == null ? button : Tooltip(message: titleTooltip, child: button),
      );
    }

    // Başlık sabit boyda (preferredSize bağlam görmez): telefonun yazı boyutu
    // çok büyütülünce iki satır başlığa sığmıyor, alttan taşıyordu. Büyütme
    // burada 1,3 katla sınırlı; sayfaların gövdesi sistemin ayarına uyar.
    return SafeArea(
      bottom: false,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: kFixedTextScale,
        child: SizedBox(
        height: preferredSize.height,
        child: Padding(
          padding: _compact ? const EdgeInsets.fromLTRB(12, 4, 12, 4) : const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: IconButtonTheme(
            data: IconButtonThemeData(
              style: IconButton.styleFrom(foregroundColor: tones.ink, visualDensity: VisualDensity.compact),
            ),
            child: Row(
              children: [
                if (leading != null) ...[
                  RoundSlot(child: leading!),
                  const SizedBox(width: 12),
                ] else
                  const SizedBox(width: 8),
                Expanded(
                  child: (onTitleTap == null ? (Widget heading) => heading : tappable)(_compact
                      // Tek satır: ad, yanında küçük harflerle yeri ve sayısı.
                      ? titled(Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: fresh(Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineMedium?.copyWith(fontSize: 22, height: 1.1),
                              )),
                            ),
                            ?chevron,
                            if (eyebrow != null && eyebrow.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  s.upper(eyebrow),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: tones.muted,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (eyebrow != null && eyebrow.isNotEmpty)
                              Text(
                                s.upper(eyebrow),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: tones.muted,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            const SizedBox(height: 1),
                            titled(Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: fresh(Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.headlineMedium?.copyWith(fontSize: 27, height: 1.1),
                                  )),
                                ),
                                ?chevron,
                              ],
                            )),
                          ],
                        )),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: tones.surface,
                      borderRadius: BorderRadius.circular(23),
                      border: Border.all(color: tones.line),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: actions),
                  ),
                ],
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// Başlıktaki tek düğmelik yuvarlak yuva (menü, geri).
class RoundSlot extends StatelessWidget {
  const RoundSlot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: tones.surface,
        shape: BoxShape.circle,
        border: Border.all(color: tones.line),
      ),
      child: Center(child: child),
    );
  }
}

/// Hedefe giden yolda, hedefle birlikte altına açılan klasör ([InventoryShell.goToLevel]): ilk açılışı
/// sürerken görünmez, yalnızca hedefin açılışı görünsün. Sonra sıradan bir sayfadır: geri tuşuyla
/// kapanırken her zamanki geçiş görünür. Sayfanın kendisi açılışta da kurulur (durumu korunur).
class _UnderRoute extends MaterialPageRoute<void> {
  _UnderRoute({required super.builder});

  bool _entered = false;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Rotanın kendi sayacına bakılır: Hero denetleyicisi açılan sayfayı ilk karede ölçmek için
    // gizlerken [animation] "tamamlandı" görünür.
    _entered = _entered || (controller?.isCompleted ?? true);
    if (!_entered) return Opacity(opacity: 0, child: child);
    return super.buildTransitions(context, animation, secondaryAnimation, child);
  }
}

/// Klasör ekranlarının geri oku: dokununca bir üst ekran, basılı tutunca doğrudan ana ekran
/// (derindeki bir klasörden birer birer dönmek uzun sürüyordu).
class LevelBackButton extends StatelessWidget {
  const LevelBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    // İpucu uzun basmada açılmaz (o hareket ana ekrana götürür); adı ekran okuyucuya yine gider.
    return Tooltip(
      message: s.back,
      triggerMode: TooltipTriggerMode.manual,
      child: Semantics(
        onLongPressHint: s.backHoldHint,
        child: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onPressed,
          onLongPress: () => InventoryShell.goToLevel(context, Roots.home),
        ),
      ),
    );
  }
}

/// Klasör ekranının ⋮ menüsü: düzenle, QR, toplu seçim ve etiket sayfası.
class ContainerMenu extends StatelessWidget {
  const ContainerMenu({super.key, required this.node});

  final Node node;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return PopupMenuButton<void>(
      tooltip: s.moreActions,
      icon: const Icon(Icons.more_vert_rounded),
      itemBuilder: (_) => [
        PopupMenuItem(
          onTap: () => NodeActions.edit(context, node),
          child: ListTile(leading: const Icon(Icons.edit_rounded), title: Text(s.edit), dense: true),
        ),
        PopupMenuItem(
          onTap: () => NodeActions.showQr(context, node),
          child: ListTile(leading: const Icon(Icons.qr_code_2_rounded), title: Text(s.qrCode), dense: true),
        ),
        PopupMenuItem(
          onTap: () => LabelFlows.forFolder(context, node),
          child: ListTile(leading: const Icon(Icons.print_rounded), title: Text(s.qrLabels), dense: true),
        ),
        PopupMenuItem(
          onTap: () => BoxExportService.showExportSheet(context, node),
          child: ListTile(leading: const Icon(Icons.description_outlined), title: Text(s.exportContent), dense: true),
        ),
        PopupMenuItem(
          onTap: () => AuditPage.start(context, container: node),
          child: ListTile(leading: const Icon(Icons.fact_check_outlined), title: Text(s.auditFolder), dense: true),
        ),
        PopupMenuItem(
          onTap: () => InventoryShell.startSelection(context),
          child: ListTile(leading: const Icon(Icons.checklist_rounded), title: Text(s.select), dense: true),
        ),
      ],
    );
  }
}
