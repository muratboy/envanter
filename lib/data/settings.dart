import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/strings.dart';
import '../core/time_span.dart';
import 'database.dart';
import 'library.dart';

const _tipsVersion = '2';

/// Ayarlar iki yerde durur. Kişisel olanlar (dil, tema, ad, fotoğraf)
/// envanterden bağımsızdır: kütüphane dosyasında ([InventoryLibrary.global]),
/// hangi envanter açık olursa olsun aynıdır. Envantere ait olanlar (deste
/// düzeni, otomatik konum, son kullanma uyarısı, bildirim, sık kullanılanlar,
/// son seviye, özel kayıtlar, yedek) o envanterin veritabanındaki meta
/// tablosunda: kilerde 3 ay önceden uyarı, ilaç dolabında 1 ay; atölyenin
/// bildirimi kapalı olabilir. (Ortak kullanım ve onay biçimi de envanterin
/// kendi ayarı; `SharingConfig`, yine meta tablosunda.) Kütüphane yoksa
/// (testler) hepsi veritabanında; ilk açılışta kişisel ayarlar oradan okunup
/// kütüphaneye taşınır.
/// Destede/listede kayıtların gösterilme sırası. `manual` kullanıcının elle
/// dizdiği sıra (kayıtların `sortIndex`'i); ötekiler yalnızca gösterimi sıralar,
/// elle sıra olduğu gibi durur.
enum DeckSort { manual, name, newest, expiry }

/// Bir seviyedeki kayıtların görünümü: üst üste binen kartlar (deste), sık
/// satırlar (liste) ya da fotoğrafların öne çıktığı kareler (ızgara). Üçü de
/// aynı bileşenle kurulur; yalnızca ölçüler ve çizilen şey değişir.
enum DeckView { deck, list, grid }

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.language = AppLanguage.system,
    this.autoLocationOnCreate = false,
    this.userName = '',
    this.userAvatarPath,
    this.tipsSeen = false,
    this.groupKinds = true,
    this.deckView = DeckView.deck,
    this.deckSort = DeckSort.manual,
    this.favorites = const [],
    this.lastLevel,
    this.recent = const [],
    this.lastBackupAt,
    this.backupSnoozedAt,
    this.privateIds = const [],
    this.expiryWarning = defaultExpiryWarning,
    this.autoBackupUri,
    this.autoBackupFolder,
    this.autoBackupFailedAt,
    this.dateNotifications = true,
    this.notifyAsked = false,
    this.backupOffered = false,
    this.rotateScreen = true,
    this.syncClosed = true,
    this.notifyPending = true,
    this.currency,
  });

  static const defaultExpiryWarning = TimeSpan(3, SpanUnit.month);

  final ThemeMode themeMode;
  final AppLanguage language;

  /// Yeni klasör olustururken GPS konumunu kendiliğinden yakala.
  final bool autoLocationOnCreate;

  final String userName;
  final String? userAvatarPath;

  /// Ana ekrandaki ilk ipuçları kartı kapatıldı.
  final bool tipsSeen;

  /// Destede klasörler ve eşyalar ayrı gruplar halinde dursun. Kapalıyken
  /// hepsi tek sırada durur, sıralama da serbest olur.
  final bool groupKinds;

  /// Görünüm: deste, liste (ekrana daha çok kayıt sığar) ya da ızgara
  /// (fotoğraflar öne çıkar). Envantere ait (mutfak destede, kitaplık listede
  /// kalabilir), cihaza özel.
  final DeckView deckView;

  bool get listView => deckView == DeckView.list;

  /// Kayıtların gösterilme sırası; envantere ait, cihaza özel (eşitlenmez).
  final DeckSort deckSort;

  /// Sık kullanılanlar: kayıt kimlikleri, eklenme sırasıyla. Bu cihaza özel,
  /// ortak kullanımda karşıya geçmez (herkesin kendi kısayolu olur).
  final List<String> favorites;

  /// Uygulama kapanırken açık olan klasör; yeniden açılınca oraya dönülür.
  /// null ya da ana ekran: kökten başlanır. Bu da cihaza özeldir.
  final String? lastLevel;

  /// Bu cihazda son eklenen, düzenlenen ya da yeri değişen kayıtlar, en yeni
  /// önce. Boş aramada görünür. Cihaza özeldir, eşitlenmez ve yedeğe girmez.
  final List<String> recent;

  /// Son dışa aktarma (paylaşım penceresinde bir yer seçildiyse). Yedek
  /// hatırlatması buna bakar; cihaza özeldir.
  final DateTime? lastBackupAt;

  /// Hatırlatmaya "sonra" denen an; bir hafta susar.
  final DateTime? backupSnoozedAt;

  /// "Yalnızca bende": bu kayıtlar ve içlerindeki her şey başka cihazlara
  /// gönderilmez. İşaret kaydın kendisinde değil burada durur: kayıtta dursaydı
  /// eşitlemeyle karşıya gider, herkesin kaydı herkese özel olurdu. Yedek
  /// dosyasına girer (geri yüklenince özel kalsın), ortak kullanıma girmez.
  final List<String> privateIds;

  /// Son kullanma tarihine bu kadar kala uyarılır; eşya kendi süresini
  /// verebilir (bisküvi 1 ay). Kişisel tercih: cihazda kalır, eşitlenmez.
  final TimeSpan expiryWarning;

  /// Otomatik yedeğin yazıldığı klasör (Android'in kalıcı izin verdiği adres)
  /// ve görünen adı. null: otomatik yedek kapalı. Kişisel ve bütün envanterler
  /// için tek: her envanter aynı klasöre kendi adıyla yazılır; envanter başına
  /// açıp kapatmak, açılmadan unutulan envanteri yedeksiz bırakıyordu.
  final String? autoBackupUri;
  final String? autoBackupFolder;

  /// Son otomatik yedek yazılamadı (ör. klasör silindi, izin geri alındı).
  final DateTime? autoBackupFailedAt;

  /// Son kullanma ve garanti için telefon bildirimi. Cihaza özel.
  final bool dateNotifications;

  /// Bildirim izni bir kez soruldu (ilk tarihli eşya kaydedilince).
  final bool notifyAsked;

  /// Otomatik yedek bir kez önerildi (envanter büyüyünce). Kişisel.
  final bool backupOffered;

  /// Telefon yan çevrilince uygulama da dönsün. Kapalıyken telefonda hep dikey
  /// (tablet yine döner; bkz. `applyOrientation`). Kişisel.
  final bool rotateScreen;

  /// Paylaşılan ama açık olmayan envanterler de arka planda eşitlensin
  /// (bkz. `ClosedSync`). Varsayılan açık; kişisel (bütün envanterler için tek ayar).
  final bool syncClosed;

  /// Uygulama önde değilken onay bekleyen yeni değişiklik gelirse telefon bildirimi
  /// (bkz. `PendingNotice`). Varsayılan açık; kişisel.
  final bool notifyPending;

  /// Yeni fiyatların başladığı para birimi (ISO kodu); envantere ait, cihaza özel. Boşsa
  /// telefonun bölgesinden ([Money.localDefault]). Eşyanın kendi fiyatı birimiyle saklanır:
  /// bu ayar değişince eski fiyatlar değişmez.
  final String? currency;

  /// Arayüz Türkçeyse TRY: telefonun bölgesi çoğu zaman "en_US" gibi bir dil seçiminden gelir,
  /// Türkçe kullanan için doların varsayılan olması yanlış tahmin olurdu.
  String get defaultCurrency =>
      currency ?? (AppStrings.forLanguage(language) is TrStrings ? 'TRY' : Money.localDefault());

  AppSettings copyWith({
    ThemeMode? themeMode,
    AppLanguage? language,
    bool? autoLocationOnCreate,
    String? userName,
    String? userAvatarPath,
    bool clearAvatar = false,
    bool? tipsSeen,
    bool? groupKinds,
    bool? listView,
    DeckView? deckView,
    DeckSort? deckSort,
    List<String>? favorites,
    String? lastLevel,
    bool clearLastLevel = false,
    List<String>? recent,
    DateTime? lastBackupAt,
    DateTime? backupSnoozedAt,
    List<String>? privateIds,
    TimeSpan? expiryWarning,
    String? autoBackupUri,
    String? autoBackupFolder,
    bool clearAutoBackup = false,
    DateTime? autoBackupFailedAt,
    bool clearAutoBackupFailure = false,
    bool? dateNotifications,
    bool? notifyAsked,
    bool? backupOffered,
    bool? rotateScreen,
    bool? syncClosed,
    bool? notifyPending,
    String? currency,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        language: language ?? this.language,
        autoLocationOnCreate: autoLocationOnCreate ?? this.autoLocationOnCreate,
        userName: userName ?? this.userName,
        userAvatarPath: clearAvatar ? null : (userAvatarPath ?? this.userAvatarPath),
        tipsSeen: tipsSeen ?? this.tipsSeen,
        groupKinds: groupKinds ?? this.groupKinds,
        // `listView` eski iki durumlu ayarın kısayolu: liste ya da deste.
        deckView: deckView ?? (listView == null ? this.deckView : (listView ? DeckView.list : DeckView.deck)),
        deckSort: deckSort ?? this.deckSort,
        favorites: favorites ?? this.favorites,
        lastLevel: clearLastLevel ? null : (lastLevel ?? this.lastLevel),
        recent: recent ?? this.recent,
        lastBackupAt: lastBackupAt ?? this.lastBackupAt,
        backupSnoozedAt: backupSnoozedAt ?? this.backupSnoozedAt,
        privateIds: privateIds ?? this.privateIds,
        expiryWarning: expiryWarning ?? this.expiryWarning,
        autoBackupUri: clearAutoBackup ? null : (autoBackupUri ?? this.autoBackupUri),
        autoBackupFolder: clearAutoBackup ? null : (autoBackupFolder ?? this.autoBackupFolder),
        autoBackupFailedAt: clearAutoBackup || clearAutoBackupFailure
            ? null
            : (autoBackupFailedAt ?? this.autoBackupFailedAt),
        dateNotifications: dateNotifications ?? this.dateNotifications,
        notifyAsked: notifyAsked ?? this.notifyAsked,
        backupOffered: backupOffered ?? this.backupOffered,
        rotateScreen: rotateScreen ?? this.rotateScreen,
        syncClosed: syncClosed ?? this.syncClosed,
        notifyPending: notifyPending ?? this.notifyPending,
        currency: currency ?? this.currency,
      );

  /// Envanterden bağımsız ayarların anahtarları.
  static const globalKeys = {
    'theme_mode',
    'language',
    'user_name',
    'user_avatar',
    'tips_seen',
    'notify_asked',
    'auto_backup_uri',
    'auto_backup_folder',
    'backup_offered',
    'rotate_screen',
    'sync_closed',
    'notify_pending',
  };

  static Future<AppSettings> load() async {
    final db = AppDatabase.instance;
    final library = InventoryLibrary.current;
    // Kütüphanede yoksa (ilk açılış) eski yerinden: ilk envanterin meta tablosu.
    Future<String?> global(String key) async => library?.global[key] ?? await db.readMeta(key);
    // Envantere ait; bu envanterde henüz yoksa (yeni envanter ya da kısa süre
    // kişisel tutulmuş bir ayar) kütüphanedeki eski ortak değerden başlar.
    Future<String?> own(String key) async => await db.readMeta(key) ?? library?.global[key];
    final theme = await global('theme_mode');
    final auto = await own('auto_location');
    final lang = await global('language');
    final settings = AppSettings(
      themeMode: switch (theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      language: switch (lang) {
        'turkish' => AppLanguage.turkish,
        'english' => AppLanguage.english,
        _ => AppLanguage.system,
      },
      autoLocationOnCreate: auto == '1',
      userName: await global('user_name') ?? '',
      userAvatarPath: _text(await global('user_avatar')),
      // İpuçları değişince sürüm artar; herkes yenisini bir kez görür.
      tipsSeen: await global('tips_seen') == _tipsVersion,
      // Yokken varsayılan açık: eski kurulumlarda deste bugünkü gibi kalsın.
      groupKinds: await own('group_kinds') != '0',
      // Eski kurulumda yalnızca '0' / '1' (deste / liste) yazıyordu.
      deckView: switch (await own('list_view')) {
        '1' => DeckView.list,
        '2' => DeckView.grid,
        _ => DeckView.deck,
      },
      deckSort: switch (await own('deck_sort')) {
        'name' => DeckSort.name,
        'newest' => DeckSort.newest,
        'expiry' => DeckSort.expiry,
        _ => DeckSort.manual,
      },
      favorites: [
        for (final id in (await db.readMeta('favorites') ?? '').split(','))
          if (id.trim().isNotEmpty) id.trim(),
      ],
      lastLevel: switch ((await db.readMeta('last_level'))?.trim()) {
        final String id when id.isNotEmpty => id,
        _ => null,
      },
      recent: [
        for (final id in (await db.readMeta('recent') ?? '').split(','))
          if (id.trim().isNotEmpty) id.trim(),
      ],
      lastBackupAt: _time(await db.readMeta('last_backup')),
      backupSnoozedAt: _time(await db.readMeta('backup_snoozed')),
      privateIds: [
        for (final id in (await db.readMeta('private') ?? '').split(','))
          if (id.trim().isNotEmpty) id.trim(),
      ],
      expiryWarning: TimeSpan.parse(await own('expiry_warn')) ?? defaultExpiryWarning,
      autoBackupUri: _text(await global('auto_backup_uri')),
      autoBackupFolder: _text(await global('auto_backup_folder')),
      autoBackupFailedAt: _time(await db.readMeta('auto_backup_failed')),
      dateNotifications: await own('date_notify') != '0',
      notifyAsked: await global('notify_asked') == '1',
      backupOffered: await global('backup_offered') == '1',
      rotateScreen: await global('rotate_screen') != '0',
      syncClosed: await global('sync_closed') != '0',
      notifyPending: await global('notify_pending') != '0',
      currency: switch ((await own('currency'))?.trim()) {
        final String c when Money.validCurrency(c) => c,
        _ => null,
      },
    );
    // İlk açılış: kişisel ayarlar henüz kütüphanede değil, bu envanterden
    // okundu. Hemen taşınır; yoksa bir sonra açılan envanter (kendi
    // veritabanında bulamayınca) varsayılan dil ve temayla açılırdı.
    if (library != null && !globalKeys.every(library.global.containsKey)) {
      await library.writeGlobals(
        settings._globals()..removeWhere((key, _) => library.global.containsKey(key)),
      );
    }
    return settings;
  }

  static String? _text(String? v) => v == null || v.trim().isEmpty ? null : v;

  static DateTime? _time(String? ms) => switch (int.tryParse(ms ?? '')) {
        final int v when v > 0 => DateTime.fromMillisecondsSinceEpoch(v),
        _ => null,
      };

  Map<String, String> _globals() => {
        'theme_mode': themeMode.name,
        'language': language.name,
        'user_name': userName,
        'user_avatar': userAvatarPath ?? '',
        'tips_seen': tipsSeen ? _tipsVersion : '0',
        'notify_asked': notifyAsked ? '1' : '0',
        'auto_backup_uri': autoBackupUri ?? '',
        'auto_backup_folder': autoBackupFolder ?? '',
        'backup_offered': backupOffered ? '1' : '0',
        'rotate_screen': rotateScreen ? '1' : '0',
        'sync_closed': syncClosed ? '1' : '0',
        'notify_pending': notifyPending ? '1' : '0',
      };

  Future<void> persist() async {
    final db = AppDatabase.instance;
    final globals = _globals();
    final library = InventoryLibrary.current;
    if (library != null) {
      await library.writeGlobals(globals);
    } else {
      for (final e in globals.entries) {
        await db.writeMeta(e.key, e.value);
      }
    }
    await db.writeMeta('auto_location', autoLocationOnCreate ? '1' : '0');
    await db.writeMeta('group_kinds', groupKinds ? '1' : '0');
    await db.writeMeta('list_view', '${deckView.index}');
    await db.writeMeta('deck_sort', deckSort.name);
    await db.writeMeta('currency', currency ?? '');
    await db.writeMeta('expiry_warn', expiryWarning.encode());
    await db.writeMeta('date_notify', dateNotifications ? '1' : '0');
    await db.writeMeta('favorites', favorites.join(','));
    await db.writeMeta('last_level', lastLevel ?? '');
    await db.writeMeta('recent', recent.join(','));
    await db.writeMeta('last_backup', '${lastBackupAt?.millisecondsSinceEpoch ?? ''}');
    await db.writeMeta('backup_snoozed', '${backupSnoozedAt?.millisecondsSinceEpoch ?? ''}');
    await db.writeMeta('private', privateIds.join(','));
    await db.writeMeta('auto_backup_failed', '${autoBackupFailedAt?.millisecondsSinceEpoch ?? ''}');
  }
}
