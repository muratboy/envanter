import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Uygulamanın tasarım dili: kağıt, mürekkep ve kiremit. Kartoteks ya da bir
/// arşiv dolabı hissi; renkli olan kartların kendisi, çerçeve sakin kalır.
@immutable
class Tones extends ThemeExtension<Tones> {
  const Tones({
    required this.paper,
    required this.surface,
    required this.raised,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.lost,
    required this.success,
    required this.danger,
    required this.shadow,
  });

  /// Zemin.
  final Color paper;

  /// Panel, sayfa, çekmece.
  final Color surface;

  /// Panel içinde bir kat yukarı (giriş kutuları, çipler).
  final Color raised;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color line;

  /// Kiremit: ana eylem (+), bildirim, seçili durum. Az kullanılır.
  final Color accent;
  final Color onAccent;

  /// Kayıp: hardal.
  final Color lost;
  final Color success;
  final Color danger;
  final Color shadow;

  static const light = Tones(
    paper: Color(0xFFF2EDE4),
    surface: Color(0xFFFBF9F5),
    raised: Color(0xFFEDE7DC),
    ink: Color(0xFF1E1B18),
    muted: Color(0xFF6E665C),
    faint: Color(0xFFA0978B),
    line: Color(0xFFE0D8CA),
    accent: Color(0xFFC4552F),
    onAccent: Color(0xFFFFFFFF),
    lost: Color(0xFFD69A12),
    success: Color(0xFF3E8E5E),
    danger: Color(0xFFC0392B),
    shadow: Color(0xFF3B2F22),
  );

  static const dark = Tones(
    paper: Color(0xFF14120F),
    surface: Color(0xFF1D1A16),
    raised: Color(0xFF29251F),
    ink: Color(0xFFF2ECE2),
    muted: Color(0xFFB2A99C),
    faint: Color(0xFF7D766B),
    line: Color(0xFF342F28),
    accent: Color(0xFFE5835F),
    onAccent: Color(0xFF1E1B18),
    lost: Color(0xFFE9B43A),
    success: Color(0xFF6CC08E),
    danger: Color(0xFFF0877A),
    shadow: Color(0xFF000000),
  );

  static Tones of(BuildContext context) => Theme.of(context).extension<Tones>()!;

  @override
  Tones copyWith() => this;

  @override
  Tones lerp(Tones? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Tones(
      paper: l(paper, other.paper),
      surface: l(surface, other.surface),
      raised: l(raised, other.raised),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      faint: l(faint, other.faint),
      line: l(line, other.line),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      lost: l(lost, other.lost),
      success: l(success, other.success),
      danger: l(danger, other.danger),
      shadow: l(shadow, other.shadow),
    );
  }
}

/// Başlık yazı ailesi (serif).
const kDisplayFont = 'Fraunces';

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final t = dark ? Tones.dark : Tones.light;
  final scheme = ColorScheme.fromSeed(seedColor: t.accent, brightness: brightness).copyWith(
    primary: t.ink,
    onPrimary: t.surface,
    primaryContainer: t.raised,
    onPrimaryContainer: t.ink,
    secondary: t.accent,
    onSecondary: t.onAccent,
    secondaryContainer: Color.alphaBlend(t.accent.withValues(alpha: 0.16), t.surface),
    onSecondaryContainer: t.ink,
    tertiary: t.accent,
    onTertiary: t.onAccent,
    tertiaryContainer: Color.alphaBlend(t.accent.withValues(alpha: 0.16), t.surface),
    onTertiaryContainer: t.ink,
    error: t.danger,
    onError: dark ? t.paper : Colors.white,
    errorContainer: Color.alphaBlend(t.danger.withValues(alpha: 0.16), t.surface),
    onErrorContainer: t.ink,
    surface: t.paper,
    onSurface: t.ink,
    onSurfaceVariant: t.muted,
    surfaceContainerLowest: t.surface,
    surfaceContainerLow: t.surface,
    surfaceContainer: t.surface,
    surfaceContainerHigh: t.raised,
    surfaceContainerHighest: t.raised,
    surfaceTint: Colors.transparent,
    outline: t.faint,
    outlineVariant: t.line,
    inverseSurface: t.ink,
    onInverseSurface: t.paper,
    inversePrimary: t.accent,
    shadow: t.shadow,
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Manrope',
    visualDensity: VisualDensity.standard,
  );
  final text = base.textTheme;
  TextStyle? display(TextStyle? s, double size, {FontWeight weight = FontWeight.w600}) => s?.copyWith(
        fontFamily: kDisplayFont,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: -0.2,
        height: 1.15,
        color: t.ink,
      );

  final textTheme = text.copyWith(
    displaySmall: display(text.displaySmall, 34),
    headlineLarge: display(text.headlineLarge, 30),
    headlineMedium: display(text.headlineMedium, 26),
    headlineSmall: display(text.headlineSmall, 23),
    titleLarge: display(text.titleLarge, 21),
    titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: t.ink),
    titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: t.ink),
    bodyLarge: text.bodyLarge?.copyWith(color: t.ink),
    bodyMedium: text.bodyMedium?.copyWith(color: t.ink),
    bodySmall: text.bodySmall?.copyWith(color: t.muted, height: 1.35),
    labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    labelMedium: text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: t.muted),
  );

  const stadium = StadiumBorder();
  const buttonText = TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700, fontSize: 15);

  return base.copyWith(
    extensions: [t],
    scaffoldBackgroundColor: t.paper,
    canvasColor: t.surface,
    textTheme: textTheme,
    iconTheme: IconThemeData(color: t.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      toolbarHeight: 64,
      titleTextStyle: textTheme.headlineSmall,
      iconTheme: IconThemeData(color: t.ink),
      actionsIconTheme: IconThemeData(color: t.ink),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: t.line),
      ),
      margin: EdgeInsets.zero,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      iconColor: t.muted,
      titleTextStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: t.ink, fontSize: 15.5),
      subtitleTextStyle: text.bodySmall?.copyWith(color: t.muted, height: 1.35),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: textTheme.headlineSmall,
      contentTextStyle: text.bodyMedium?.copyWith(color: t.muted, height: 1.45),
    ),
    // Sayfalar kendi tutamaçlarını çiziyor.
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      modalBackgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(28))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: t.line)),
      textStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: t.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.ink,
        foregroundColor: t.surface,
        shape: stadium,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        side: BorderSide(color: t.line, width: 1.2),
        shape: stadium,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: t.ink, textStyle: buttonText, shape: stadium),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: t.ink),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 0,
      highlightElevation: 0,
      backgroundColor: t.accent,
      foregroundColor: t.onAccent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: t.accent,
      textColor: t.onAccent,
      textStyle: const TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w800, fontSize: 11),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: stadium,
      side: BorderSide(color: t.line),
      backgroundColor: t.surface,
      labelStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: t.ink),
    ),
    dividerTheme: DividerThemeData(color: t.line, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.raised,
      hintStyle: TextStyle(color: t.faint, fontWeight: FontWeight.w500),
      labelStyle: TextStyle(color: t.muted, fontWeight: FontWeight.w600),
      floatingLabelStyle: TextStyle(color: t.ink, fontWeight: FontWeight.w700),
      prefixIconColor: t.muted,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: t.ink, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.ink,
      actionTextColor: t.accent,
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentTextStyle: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: t.paper),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: t.ink, borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(color: t.paper, fontWeight: FontWeight.w600, fontSize: 12),
    ),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? const Icon(Icons.check_rounded, size: 16) : null,
      ),
      trackOutlineColor: WidgetStatePropertyAll(t.line),
    ),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent),
    expansionTileTheme: ExpansionTileThemeData(iconColor: t.muted, collapsedIconColor: t.muted),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
  );
}

/// Geniş ekranlarda okunabilir satır uzunluğu: ayar ve liste sayfaları
/// tablette ortada, bu genişlikte durur.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child, this.maxWidth = 720});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    // Yatayda sistem çubuğu ve kamera çentiği yanlara geçer: içerik onların
    // iç tarafında kalan alana ortalanır.
    final pad = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.only(left: pad.left, right: pad.right),
      child: Align(
        alignment: Alignment.topCenter,
        // Yükseklik içeriği kadar; yoksa alt çubukta tüm ekranı kaplıyordu.
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// Liste sayfalarının iç boşluğu; geniş ekranda içerik [maxWidth]'i aşmasın
/// diye yanlar büyür.
EdgeInsets readableInsets(BuildContext context, EdgeInsets base, {double maxWidth = 720}) {
  // Yatayda yanlardaki sistem çubuğu ve çentik düşülür, içerik kalan alana ortalanır.
  final pad = MediaQuery.paddingOf(context);
  final width = MediaQuery.sizeOf(context).width - pad.left - pad.right;
  final extra = ((width - maxWidth) / 2).clamp(0.0, double.infinity);
  return base.copyWith(
    left: base.left + extra + pad.left,
    right: base.right + extra + pad.right,
    bottom: base.bottom + bottomInset(context),
  );
}

/// Yazı alanının dışına dokununca yazma biter: imleç ve klavye kaybolur.
/// Flutter telefonda dışarı dokunmayı yok sayıyor; imleç ve klavye kalıyordu.
/// Her yazı alanının `onTapOutside`'ı.
void dismissKeyboard(PointerDownEvent _) => FocusManager.instance.primaryFocus?.unfocus();

/// Parmakla kaydırma başlayınca da yazma biter (uygulamanın kökünde dinlenir):
/// imlecin tutamacı içerikle kayıp ortada kalıyordu. Çok satırlı bir alanın
/// kendi içinde kaydırılması yazmayı bitirmez.
bool dismissKeyboardOnDrag(ScrollNotification n) {
  if (n is ScrollStartNotification && n.dragDetails != null) {
    final inField = n.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (!inField) FocusManager.instance.primaryFocus?.unfocus();
  }
  return false;
}

/// Yatay düzen: ekran enine ve yeterince geniş (yatay telefon, yatay tablet).
/// Dikey düzeni yan yatırmak yerine: başlık tek satır, alttaki arama ve artı
/// sol kenarda dikey şeritte, sağ paneller desteyi örtmeden yanında açılır,
/// kartlar kısalır. Dikeyde bir şey değişmez.
/// Sabit boydaki yüzeylerde (kart, liste satırı, başlık) yazı büyütmesinin üst
/// sınırı. Telefonun yazı boyutu bundan çok büyütülmüşse bu yüzeyler taşıyordu;
/// kayan sayfalar (düzenleyici, ayarlar, listeler) sınırsız büyür.
const double kFixedTextScale = 1.3;

bool landscapeLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width > size.height && size.width >= 600;
}

/// Ekran yönü: "Ekranı döndür" kapalıysa telefonda hep dikey. Açıkken (ve
/// tablette hep) telefonun kendi otomatik döndürme ayarına uyulur: boş liste
/// sistemin varsayılanı demek. Dört yönü birden vermek Android'de "tam
/// algılayıcı" oluyor ve döndürme kilidini yok sayıyordu: kilitli telefonda da
/// uygulama yan çevrilince dönüyordu.
Future<void> applyOrientation({required bool rotate}) {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  final tablet = views.isNotEmpty && views.first.physicalSize.shortestSide / views.first.devicePixelRatio >= 600;
  return SystemChrome.setPreferredOrientations(
    rotate || tablet ? const <DeviceOrientation>[] : const [DeviceOrientation.portraitUp],
  );
}

/// Kenardan kenara çizimde alttaki sistem çubuğunun (jest çubuğu ya da üç
/// düğme) yüksekliği: listenin sonu onun altında kalmasın. Üç düğmeli
/// gezinmede çubuk yüksek, son satır yarıya kadar altında kalıyordu. Bir
/// SafeArea'nın içindeyse sıfırdır (iki kez sayılmaz).
double bottomInset(BuildContext context) => MediaQuery.paddingOf(context).bottom;
