import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../state/inventory_store.dart';
import 'money.dart';
import 'time_span.dart';

enum AppLanguage { system, turkish, english }

/// Uygulamanın tüm metinleri. Kod üretimi gerektirmeyen, elle yazılmış
/// küçük bir sözlük; iki dil için fazlası gereksizdi.
abstract class AppStrings {
  const AppStrings();

  static AppStrings of(BuildContext context) => InventoryScope.of(context).strings;

  /// "Sistemle aynı" seçiliyken telefonun dili Türkçe mi. Arayüzü olmayan bir
  /// yalıtımda (kapalı envanterlerin arka plan eşitlemesi) telefonun dili
  /// okunamaz; orada uygulamanın gördüğü değer buraya yazılır.
  static bool? systemIsTurkish;

  static bool get systemTurkish =>
      systemIsTurkish ?? PlatformDispatcher.instance.locale.languageCode == 'tr';

  static AppStrings forLanguage(AppLanguage language) {
    final resolved = language == AppLanguage.system
        ? (systemTurkish ? AppLanguage.turkish : AppLanguage.english)
        : language;
    return resolved == AppLanguage.turkish ? const TrStrings() : const EnStrings();
  }

  Locale get locale;

  /// Dart'ın toUpperCase'i dilden bağımsız çalışıyor ve Türkçe'nin noktalı
  /// İ'sini bilmiyor ("dil" -> "DIL"). Başlıklar bu yüzden buradan geçiyor.
  String upper(String text);

  // Genel
  String get appTitle;
  String get home;
  String get drawer;
  String get container;
  String get item;
  String get unnamed;
  String get empty;
  String recordCount(int n);
  String get back;
  String get backHoldHint;
  String get parentFolders;
  String get otherFolder;
  String get whichFolderToGo;
  String get goHere;
  String get youAreHere;
  String get cancel;
  String get save;
  String get delete;
  String get undo;
  String get close;
  String get edit;
  String get qrCode;
  String get menu;
  String get search;
  String get newRecord;
  String get clear;

  // Ana ekran
  String get nothingYet;
  String itemsAtRoot(int n);
  String get createFirstContainer;
  String get createFirstContainerHint;
  String get addFirstItem;
  String get addFirstItemHint;
  String get addInside;

  // Ekleme menüsü
  String get addItem;
  String get addItemSubtitle;
  String get addContainer;
  String get addContainerSubtitle;

  // Editör
  String get newContainer;
  String get newItem;
  String get editRecord;
  String get name;
  String get itemNameHint;
  String get photo;
  String get takePhoto;
  String get pickFromGallery;
  String get removePhoto;
  String get replacePhoto;
  String get photoFailed;
  String get cardColor;
  String get location;
  String get containerHasChildren;
  String get noteOptional;

  // Konum
  String get physicalLocation;
  String get physicalLocationHint;
  String get autoLocate;
  String get locating;
  String get locationName;
  String get locationNameHint;
  String get latitude;
  String get longitude;
  String get invalidCoordinates;
  String get locationFailed;
  String get locationServiceOff;
  String get locationDenied;
  String get locationDeniedForever;

  // Öne çıkan kart
  String get changePlacement;
  String get moveToTrash;

  // Taşıma
  String whereShouldGo(String name);
  String currentlyAt(String path);
  String get currentPlace;
  String get drawerWithHint;
  String movedTo(String name, String path);
  String get moveNotPossible;
  String get cannotMoveIntoItself;
  String movedInto(String name, String target);
  String get dropHere;
  String get intoHome;
  String get intoDrawer;
  String intoContainer(String name);
  String movedToDrawer(String name);

  // QR
  String get shareAsImage;
  String get preparing;
  String get qrHint;
  String get scanQr;
  String get scanQrHint;
  String get qrNotRecognized;
  String get barcode;
  String get barcodeHint;
  String get containerBarcodeHint;
  String get scanBarcode;
  String get scanBarcodeHint;
  String get barcodeUnknown;
  String get barcodeUnknownBody;
  String get newItemWithBarcode;
  String get newContainerWithBarcode;
  String barcodeMatches(int count);
  String barcodeAlsoOn(String name);
  String get fieldBarcode;
  String get qrRecordMissing;
  String get cameraPermissionNeeded;

  // Görüntüyle arama
  String get visualSearch;
  String get visualSearchHint;
  String get visualSearchRunning;
  String get visualSearchNoMatch;
  String get visualSearchNoImages;
  String get visualSearchTake;
  String get visualSearchFromGallery;
  String get visualSearchOpening;
  String get cameraBusy;
  String get retry;
  String visualSearchResult(int n);
  String similarity(int percent);
  String get searchAgain;

  // Arama
  String get searchHint;
  String get searchInInventory;
  String get searchInInventoryHint;
  String noResultFor(String query);
  String get goToPlace;

  // Çekmece
  String get drawerSubtitle;
  String drawerWaiting(int n);
  String get drawerEmpty;
  String get drawerEmptyHint;
  String get newRecordToDrawer;

  // Çöp kutusu
  String get trash;
  String get emptyTrash;
  String get emptyTrashQuestion;
  String get emptyTrashWarning;
  String get trashEmpty;
  String insideCount(int n);
  String get singleRecord;
  String get deleteForever;
  String deleteForeverQuestion(String name);
  String deleteForeverWarning(int n);
  String get purgeRecoverable;
  String get recentlyPurged;
  String get recentlyPurgedHint;
  String get deleteNowOption;
  String get deleteNowWarning;
  String get deleteNow;
  String deleteNowQuestion(String name);
  String get clearPurged;
  String get clearPurgedQuestion;
  String clearPurgedWarning(int n);
  String trashedWithChildren(String name, int n);
  String trashedSingle(String name);

  // Ortak kullanım
  String get sharing;
  String get sharingNeedsNameTitle;
  String get sharingNeedsNameHint;
  String get inventoryNameLabel;
  String get inventories;
  String get deckSection;
  String thisInventoryTitle(String name);
  String get thisInventoryHint;
  String get inventoriesHint;
  String get newInventory;
  String get newInventoryHint;
  String get create;
  String get switchInventory;
  String get menuFavorites;
  String get menuExpired;
  String get openNow;
  String lastOpened(String when);
  String get renameInventory;
  String get inventoryLook;
  String get inventoryLookHint;
  String get lookColor;
  String get lookEmblem;
  String get lookNoColor;
  String deleteInventoryQuestion(String name);
  String deleteInventoryBody(int count);
  String get deleteSharedNote;
  String get deleteSharedClosedNote;
  String unopenedCopy(String name);
  String get deletedInventories;
  String get deletedInventoriesHint;
  String get restoreInventory;
  String get purgeInventory;
  String purgeInventoryQuestion(String name);
  String get purgeInventoryBody;
  String inventoryDeleted(String name);
  String lastBackupOn(String when);
  String get noBackup;
  String unbackedInventories(int count);
  String get backingUp;
  String backingUpAll(int done, int total);
  String get backupSection;
  String get recoveryTitle;
  String recoveryBody(String name);
  String get backupOfferTitle;
  String backupOfferBody(int count);
  String get chooseFolder;
  String get notNow;
  String get inventoryNameHint;
  String get members;
  String get thisDevice;
  String get online;
  String get offline;
  String lastSynced(String when);
  String syncedAgo(String when);
  String rejectedNotice(String who, String name, String kind);
  String quantityChanged(String name, int from, int to);
  String switchedTo(String inventory);
  String inOtherInventories(int n);
  String notSearchedYet(String names);
  String get otherListsSection;
  String get otherListsHint;
  String get otherDatesSection;
  String get otherDatesHint;
  String get openContainer;
  String get discardChangesQuestion;
  String get discardChangesAction;
  String get keepEditing;
  String get rotateTitle;
  String get openPhoto;
  String get rotateHint;
  String inCart(String name);
  String get putAwaySection;
  String get putAwayHint;
  String get putAway;
  String get backToList;
  String boughtWhen(String when);
  String get imBuying;
  String get notBuying;
  String get youAreBuying;
  String isBuying(String who);
  String clockSpan(int minutes);
  String clockGap(String span);
  String syncFailed(String reason);
  String get failUnreachable;
  String get failTimeout;
  String get failRejected;
  String get failServer;
  String get failOther;
  String clockMineWrong(String who, String span, bool behind);
  String clockTheirsWrong(String who, String span, bool ahead);
  String clockUnknown(String who, String span);
  String rejectedNoticeMany(String who, int n);
  String get neverSyncedWith;
  String get trustMember;
  String get untrustMember;
  String get trustedTag;
  String get quickSmallTitle;
  String get quickSmallSubtitle;
  String get neverSynced;
  String get syncNow;
  String get syncing;
  String get inventoriesOnNetwork;
  String get noInventoriesOnNetwork;
  String ownerLabel(String name);
  String joinQuestion(String inventory);
  String joinOwnerLine(String owner);
  String joinMergeWarning(int n);
  String get sendRequest;
  String get joinAsNew;
  String get joinIntoCurrent;
  String joinSeparateHint(int n);
  String waitingForApproval(String owner);
  String joinedMessage(String inventory);
  String get joinRejected;
  String get joinUnreachable;
  String get joinTimeout;
  String get joinRequestTitle;
  String joinRequestBody(String name, String inventory);
  String get reject;
  String get accept;
  String get leaveSharing;
  String get leaveSharingQuestion;
  String get leaveSharingBody;
  String get leave;
  String get sharingLimits;
  String sharingOnline(int n);

  // Ortak kullanım sayfası
  String get sharingOffTitle;
  String get sharingOffBody;
  String get turnOnSharing;
  String sharingVisibleAs(String name);
  String sharingJoinedAs(String inventory);
  String get howItWorks;
  List<String> get howItWorksSteps;
  String get searchingNetwork;
  String get joinHint;
  String get join;
  String get owner;
  String get you;
  String get noMembersYet;
  String get changes;
  String get autoAcceptTitle;
  String get autoAcceptSubtitle;
  String pendingChanges(int n);
  String get noPendingChanges;
  String get noPendingChangesBody;
  String get changesHint;
  String get acceptAll;
  String get rejectAll;
  String get rejectAllQuestion;
  String get rejectBody;
  String get someone;
  String changeAdded(String who);
  String changeEdited(String who);
  String changeMoved(String who);
  String changeReordered(String who);
  String changeTrashed(String who);
  String changeRestored(String who);
  String changeDeleted(String who);
  String renamedFrom(String old);
  String andInside(int n);
  String reorderedIn(String place);
  String changedFields(List<String> fields);
  String get fieldPhoto;
  String get fieldColor;
  String get fieldNote;
  String get fieldKind;
  String get fieldLocation;
  String get justNow;
  String minutesAgo(int n);
  String hoursAgo(int n);
  String get changesAccepted;
  String get changesRejected;
  String newChangesFrom(String who, int n);
  String get show;
  String get pendingMarkTooltip;


  // Kayıp çekmecesi
  String get lostDrawer;
  String get lostShort;
  String get lostSubtitle;
  String lostWaiting(int n);
  String get lostEmpty;
  String get lostEmptyHint;
  String get notThere;
  String get iKnowWhere;
  String notThereQuestion(String name);
  String get reportLost;
  String get reportLostHint;
  String get trashInstead;
  String get trashInsteadHint;
  String markedLost(String name);
  String lastSeenIn(String path);
  String lostReported(String who, String name);
  String foundReported(String who, String name, String path);
  String changeLost(String who);
  String changeFound(String who);
  String get lostItems;

  /// Destede eşya grubunun etiketi.
  String get items;
  String get searchInventory;
  String get moreActions;
  String get cancelDrag;
  String get upOneLevel;
  String get quantity;
  String get quantityHint;
  String get quantityTrackedHint;
  String get stopCounting;
  String get outOfStock;
  String quantityShort(int n);
  String get lowStockShort;
  String get minQuantityOff;
  String get minQuantityOffHint;
  String minQuantityOn(int n);
  String minQuantityOnHint(int n);
  String get removeMinQuantity;
  String get fieldMinQuantity;
  String get increase;
  String get decrease;
  String get fieldQuantity;

  // Klasörün doluluğu
  String get fullShort;
  String get markFull;
  String get markNotFull;
  String get fullHint;
  String markedFull(String name);
  String markedNotFull(String name);
  String get fieldFull;

  // Sık kullanılanlar
  String get favorites;
  String get addFavorite;
  String get removeFavorite;
  String favoriteAdded(String name);
  String favoriteRemoved(String name);
  String get favoritesSubtitle;
  String get favoritesEmpty;
  String get favoritesEmptyHint;

  // Klasör bırakma: klasörün kendisi mi, içindekiler mi
  String folderDropTitle(String name);
  String get dropMoveFolder;
  String dropMoveFolderHint(String place);
  String get dropContentsOnly;
  String dropContentsHint(int n, String place);
  String contentsMoved(int n, String place);

  // Deste sırası
  String get groupKindsTitle;
  String get groupKindsHint;

  // Kartı yana kaydırma
  String get qrShortcutHint;
  String get photoShortcutHint;
  String resultCount(int n);
  String get placeSection;
  String get kindLabel;
  String get gpsLocation;
  String get gpsLocationHint;
  String get useCurrentLocation;
  String get placementHint;
  String get options;
  String get icon;
  String get chooseIcon;
  String get defaultIcon;
  String get fieldIcon;
  String get adminRole;
  String get makeAdmin;
  String get removeAdmin;
  String get removeFromSharing;
  String removeMemberQuestion(String name);
  String removeMemberBody(String name);
  String get remove;
  String memberRemoved(String name);
  String get chooseSuccessorTitle;
  String get chooseSuccessorBody;
  String get heirRole;
  String get heirSuffix;
  String get makeHeir;
  String get removeHeir;
  String get transferOwnership;
  String transferQuestion(String name);
  String transferBody(String name);
  String get transfer;
  String get youAreOwnerTitle;
  String youAreOwnerBody(String previous);
  String newOwnerIs(String name);
  String heirToYou(String name);
  String heirSet(String name);
  String get heirCleared;
  String memberLeft(String name);
  String memberDeletedInventory(String name);
  String get removedFromSharingTitle;
  String removedFromSharingBody(String inventory);
  String get adminHint;
  String managersLabel(String names);
  String get assignManager;
  String get chooseManagers;
  String get managerHint;
  String get noOneToAssign;
  String managesPlaces(String places);
  String appliedByAuthority(String who, int n);
  String get fieldManagers;
  String get scanNetwork;
  String get scanAgain;
  String get scanPrompt;
  String get noInventoriesFound;
  String get dragHintStill;
  String get dragHintMoving;

  // Ana ekran
  String get tipTitle;
  String get tipBody;
  String get gotIt;

  // Ayarlar / sol çekmece
  String get settings;
  String get appearance;
  String get systemTheme;
  String get lightTheme;
  String get darkTheme;
  String get language;
  String get languageSystem;
  String get autoLocationTitle;
  String get autoLocationSubtitle;
  String get inventory;
  String get recordTotal;
  String get inTrash;

  // Yedekleme (dışa / içe aktarma)
  String get backup;
  String get exportTitle;
  String get exportHint;
  String get exportShareText;
  String get exporting;
  String exportFailed(String reason);
  String get importTitle;
  String get importHint;
  String get importing;
  String get importNothing;
  String importDone(int added, int updated, int photos);
  String get importFailed;
  String get importNotOurs;
  String get importNewerVersion;
  String get localOnly;
  String get user;
  String get userNameTitle;
  String get yourName;
  String get localInventory;
  String get editName;
  String get totalRecords;

  // Arama: son dokunulanlar ve eşleşmenin yeri
  String get recentTitle;
  String get inNote;

  // Yedek hatırlatması
  String lastBackup(String when);
  String get neverBackedUp;
  String get today;
  String daysAgo(int n);
  String get backupReminderTitle;
  String backupReminderBody(int changes, {required bool never});
  String get backupNow;
  String get later;

  // Toplu seçim
  String get select;
  String get selectHint;
  String selectedCount(int n);
  String get selectAll;
  String get doneSelecting;
  String get moveShort;
  String get toDrawerShort;
  String get labelsShort;
  String get trashShort;
  String whereShouldGoMany(int n);
  String movedMany(int n, String place);
  String trashedMany(int n);

  // QR etiket sayfası
  String get qrLabels;
  String get labelsTitle;
  String get labelsHint;
  String get labelSize;
  String get labelSmall;
  String get labelMedium;
  String get labelLarge;
  String perPage(int n);
  String get labelsWhich;
  String get labelScopeFolders;
  String get labelScopeAll;
  String labelCount(int labels, int pages);
  String get createPdf;
  String get labelsShareText;
  String labelsFailed(String reason);

  // Yer seçici
  String get moveHere;
  String get alreadyHere;
  String get noFoldersHere;
  String get noFoldersInside;
  String get noFoldersWhereYouAre;
  String folderCount(int n);

  // Yalnızca bende
  String get keepPrivate;
  String get makeShared;
  String get privateHint;
  String get privateInherited;
  String markedPrivate(String name, {required bool wasShared});
  String markedShared(String name);
  String get privateSwitchTitle;
  String get privateSwitchHint;
  String heldAt(String who);
  String heldHint(String who);

  // Tarihler: satın alma, son kullanma, garanti
  String get datesSection;
  String get purchaseDate;
  String get expiryDate;
  String get shelfLife;
  String get shelfLifeHint;
  String get warnBeforeExpiry;
  String defaultWarn(String span);
  String get warrantyEnd;
  String get warrantyPeriod;
  String get warrantyPeriodHint;
  String get notSet;
  String calculated(String date);
  String get needsPurchaseDate;
  String get dateOverrides;
  String get clearValue;
  String get useDefault;
  String get done;
  String get amount;
  String spanText(TimeSpan span);
  String unitLabel(SpanUnit unit);
  List<String> get monthsShort;
  String formatDate(DateTime d) => '${d.day} ${monthsShort[d.month - 1]} ${d.year}';
  String get expiredShort;
  String someExpired(int k);
  String moreDates(int n);
  String discardExpiredAction(int k);
  String discardedExpired(String name, int k);
  String addedWithDate(String date);
  String get otherDate;
  String get newLotsDate;
  String get expiryDates;
  String get addLotButton;
  String get expiringShort;
  String expiryOn(String date);
  String daysLeft(int n);
  String get lastDayToday;
  String expiredAgo(int n);
  String warrantyUntil(String date);
  String get warrantyEnded;
  String get expiryWarnSetting;
  String expiryWarnSettingHint(String span);
  String expiryWarnGeneralHint(String span);
  String get datesPage;
  String get expiredSection;
  String get expiringSection;
  String get warrantySection;
  String get noDatesSoon;
  String get noDatesSoonHint;
  String get fieldDates;

  // Farklı sürümdeki uygulamalar
  String peerOutdated(String who);
  String selfOutdated(String who);
  String get memberOutdated;
  String get thisOutdated;
  String get joinIncompatible;

  // Otomatik yedek
  String get autoBackupTitle;
  String get autoBackupHint;
  String autoBackupOn(String folder);
  String get autoBackupFailed;
  String autoBackupWritten(String folder);

  // Telefon bildirimleri
  String get notifyChannel;
  String get notifyChannelHint;
  String notifyExpiring(String date, int daysLeft);
  String get notifyLastDay;
  String notifyWarranty(String date);
  String notifyManyTitle(int n);
  String get notifySetting;
  String get notifySettingHint;
  String get notifyDenied;

  // Alışveriş listesi
  String get shoppingList;
  String get outOfStockSection;
  String get replaceSection;
  String get lowSection;
  String get autoShopTitle;
  String get autoShopHint;
  String get nowOnShoppingList;
  String get expiredPanel;
  String get expiredSubtitle;
  String get expiredEmpty;
  String get expiredEmptyHint;
  String get toBuySection;
  String get suggestionsSection;
  String get suggestionsHint;
  String get addToShopping;
  String get removeFromShopping;
  String get addShort;
  String get addToListShort;
  String addedToShopping(String name);
  String removedFromShopping(String name);
  String ranOut(String name);
  String runningLow(String name);
  String get fieldShopping;
  String get outOfStockNote;
  String lowLeft(int left, int min);
  String lowNote(int left);
  String get bought;
  String get boughtNew;
  String get howManyBought;
  String restocked(String name, int n);
  String replacedWithDate(String name, String date);
  String replacedEnterDate(String name);
  String get enterDate;
  String get shoppingEmpty;
  String get shoppingEmptyHint;
  String get shareList;
  String shoppingHeader(String date);
  String get pastDateNote;

  // Ekler: belge, fotoğraf, video, bağlantı
  String get attachments;
  String get fieldAttachments;
  String get addAttachment;
  String get attachmentsHint;
  String get attachDocument;
  String get attachDocumentHint;
  String get attachRecordVideo;
  String get attachFromGallery;
  String get attachLink;
  String get attachLinkHint;
  String get linkAddress;
  String get linkTitleOptional;
  String get linkInvalid;
  String get attachmentPhoto;
  String get attachmentVideo;
  String get attachmentDocument;
  String get attachmentName;
  String attachmentTooLarge(String names);
  String get attachmentFailed;
  String get attachmentNotHere;
  String get attachmentNotHereShort;
  String attachmentDownloading(int percent);
  String get noAppToOpen;
  String get cannotOpenLink;
  String get renameAttachment;
  String get removeAttachment;
  String get shareAttachment;
  String get copyLink;
  String get linkCopied;
  String attachmentCount(int n);
  String attachmentsAdded(int n);
  String get attachmentLimit;
  String fileSize(int bytes);

  // Kaplanan yer
  String get storageTitle;
  String get storageMeasuring;
  String storageSummary(int photos, int files);
  String get storagePhotos;
  String get storageFiles;
  String storageCount(int n);
  String get storageLargest;
  String get storageNote;
  String get storageNoFiles;
  String get storageInTrash;

  // Boş durumlar
  String get noResultHint;
  String get trashEmptyHint;

  // Karta dokununca açılan hızlı eylemler (kısa adlar)
  String get quickMove;
  String get quickFavorite;
  String get quickShop;
  String get quickShopOn;

  // Ana ekrandaki "bugün" şeridi
  String todayExpired(int n);
  String todaySoon(int n);
  String todayToBuy(int n);
  String todayToPutAway(int n);
  String todayLost(int n);
  String todayInDrawer(int n);

  // Ayarlar sekmeleri
  String get settingsMine;
  String get settingsInventory;

  // Düzenleyici
  String get moreFields;

  // Sıralama
  String get sortTitle;
  String get sortManual;
  String get sortName;
  String get sortNewest;
  String get sortExpiry;
  String sortedNoManual(String mode);

  // Liste görünümü
  String get viewTitle;
  String get viewHint;
  String get viewDeck;
  String get viewList;
  String get viewGrid;
  String showAs(String view);
  String get syncClosedTitle;
  String get syncClosedHint;
  String pendingInInventory(int count);
  String get notifyPendingTitle;
  String get notifyPendingHint;
  String get pendingChannel;
  String get pendingChannelHint;
  String get pendingNoticeTitle;

  // Envanterler arası aktarma / kopyalama
  String get transferToOtherInventory;
  String get transferOrCopyTitle;
  String get transferAction;
  String get copyAction;
  String get selectTargetInventory;
  String get cannotTransferToSame;
  String transferredTo(String name, String inventory);
  String copiedTo(String name, String inventory);
  String transferredMany(int n, String inventory);
  String copiedMany(int n, String inventory);

  // Periyodik bakım döngüsü
  String get maintenanceDone;
  String maintained(String name);
  String maintainedWithNext(String name, String nextDate);
  String get serviceCycle;
  String get serviceCycleHint;
  String get serviceSection;
  String serviceEveryText(TimeSpan span);
  String get serviceTaskTitle;
  String get serviceTaskHint;
  String get lastService;
  String nextServiceOn(String date);
  String get serviceNeedsLast;
  String get serviceHistory;
  String get serviceHistoryEmpty;
  String get serviceAddEntry;
  String get serviceEntryNote;
  String get serviceEntryNoteHint;
  String serviceShowAll(int n);
  String get serviceRemoveEntry;
  String get serviceDueToday;
  String serviceLate(int days);
  String get serviceDueSection;
  String get serviceScheduleSection;
  String todayService(int n);
  String notifyService(String? task);
  String get fieldService;
  String fieldServiced(String date);

  // Arama filtre çipleri
  String get allFilter;
  String get foldersOnly;
  String get itemsOnly;
  String get withDatesOnly;
  String get withPhotosOnly;
  String get outOfStockOnly;
  String get withAttachmentsOnly;

  // Koli ve içerik dökümü
  String get exportContent;
  String get exportPdfList;
  String get exportCsvList;
  String get boxContentList;
  String get itemIndexCol;
  String get itemNameCol;
  String get itemQuantityCol;
  String get itemLocationCol;
  String get itemNoteCol;
  String get itemBarcodeCol;

  // Ölçü birimi desteği
  String get unit;
  String get unitHint;
  String get unitPiece;
  String get unitPackage;
  String get unitKg;
  String get unitGram;
  String get unitMeter;
  String get unitCm;
  String get unitLiter;
  String get unitBox;
  String get unitPair;
  String get unitRoll;
  String get customUnit;

  // Seri barkod / QR sayım modu
  String get serialScanMode;
  String get serialScanHint;
  String stockCounted(String name, int quantity);
  String get unknownBarcodeScan;
  String serialFolderSkipped(String name);
  String get scanBatchFinished;

  // Emanet & Ödünç Takibi
  String get borrowedPageTitle;
  String get borrowAction;
  String get borrowDetailsTitle;
  String get borrower;
  String get borrowerHint;
  String get borrowedAt;
  String get returnDueDate;
  String get noReturnDueDate;
  String get markReturned;
  String borrowedToStamp(String name);
  String get borrowOverdueShort;
  String todayOverdueBorrow(int n);
  String todayBorrowed(int n);
  String fieldBorrowed(String name);
  String get fieldReturned;
  String get filterBorrowed;
  String get noBorrowedItems;
  String get noBorrowedHint;
  String get overdueSection;
  String get activeBorrowSection;
  String borrowSuccess(String item, String to);
  String returnSuccess(String item);
  String get pickReturnDate;
  String get inOneWeek;
  String get inTwoWeeks;
  String get inOneMonth;
  String get clearDate;
  String get quickBorrow;
  String get borrowerRequired;

  // Sayım / Denetim
  String get auditInventory;
  String get auditFolder;
  String get auditScopePrompt;
  String get auditPickFolder;
  String get auditCountHere;
  String get auditEntireInventory;
  String get auditThisFolder;
  String get auditIncludeSubfolders;
  String get startAudit;
  String get auditProgress;
  String auditItemProgress(int counted, int total);
  String get auditFilterAll;
  String get auditFilterPending;
  String get auditFilterVerified;
  String get auditFilterDiscrepancy;
  String get auditFilterUnexpected;
  String get verifyAction;
  String get markMissingAction;
  String get resetCountAction;
  String expectedQuantity(int count, [String? unit]);
  String countedQuantity(int count, [String? unit]);
  String get finishAudit;
  String get finishAuditShort;
  String get auditSummaryTitle;
  String auditVerifiedSummary(int n);
  String auditDiscrepancySummary(int n);
  String auditMissingSummary(int n);
  String auditUnexpectedSummary(int n);
  String get auditApplyQuantityChanges;
  String get auditMarkMissingAsLost;
  String get auditAddMissingToShopping;
  String get auditMoveMissingToDrawer;
  String get auditMoveFoundHere;
  String get auditApplyAndFinish;
  String get auditCompletedNotice;
  String get auditEmptyScope;
  String get auditScanBarcodePrompt;
  String auditItemCountedSuccess(String name, int count);
  String auditItemFoundOtherFolder(String name, String folder);
  String get auditNoChanges;
  String get auditMarkMissingActionLabel;
  String get auditMissingDoNothing;

  // Değer: fiyat, seri numarası, toplamlar, değer dökümü
  String money(Money m);
  String moneyTotals(MoneyTotals t);
  String get fieldPrice;
  String get fieldSerial;
  String get valueSection;
  String get priceTitle;
  String get priceHint;
  String priceEach(String price);
  String valueTimes(int count, String price, String total);
  String get priceInvalid;
  String get currency;
  String get currencyHint;
  String get otherCurrency;
  String get currencyCodeHint;
  String get serialTitle;
  String get serialHint;
  String get serialCopied;
  String contentsValue(String value);
  String itemValue(String value);
  String get valuePageTitle;
  String get totalValue;
  String get valueByPlace;
  String get mostValuable;
  String unpricedItems(int n);
  String get unpricedHint;
  String get noValueYet;
  String get noValueHint;
  String get currenciesSeparate;
  String get valueReport;
  String get valueReportTitle;
  String get valueReportHint;
  String get colUnitPrice;
  String get colAmount;
  String get colSerial;
  String get colPurchased;
  String reportDate(String date);
  String reportCounts(int priced, int unpriced);
  String get subtotal;
  String get grandTotal;
  String get unpricedSection;

  // Seri ekleme: kamera açık kalır, art arda çekilir, sonra adlar yazılır
  String get burstAdd;
  String get burstAddHint;
  String get burstCameraHint;
  String get burstGalleryHint;
  String get burstMoreFromGallery;
  String burstImporting(int done, int total);
  String burstImportFailed(int n);
  String burstPreparing(int done, int total);
  String burstShots(int n);
  String get burstDone;
  String get burstTakeMore;
  String burstAddItems(int n);
  String get burstNameHint;
  String burstAdded(int n, String place);
  String burstDiscardQuestion(int n);
  String get burstDiscard;
  String get burstKeep;
  String get burstCameraFailed;
  String get burstEmpty;
  String get burstSaving;
  String burstTarget(String place);
  String get burstRemoveShot;
}

class TrStrings extends AppStrings {
  const TrStrings();

  /// Özel ada iyelik eki, ünlü uyumuyla: Ayşe'nin, Burak'ın, Nur'un, Ömür'ün.
  static String possessive(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return trimmed;
    const vowels = 'aıoueiöü';
    final lower = trimmed.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
    final last = lower.split('').lastWhere(vowels.contains, orElse: () => 'e');
    final suffix = switch (last) {
      'a' || 'ı' => 'ın',
      'o' || 'u' => 'un',
      'ö' || 'ü' => 'ün',
      _ => 'in',
    };
    final endsWithVowel = vowels.contains(lower[lower.length - 1]);
    return "$trimmed'${endsWithVowel ? 'n' : ''}$suffix";
  }

  /// Özel ada bulunma eki, son ünlüye ve son sese göre: Ayşe'de, Ahmet'te, Murat'ta, Pınar'da. Sabit 'de
  /// "Ahmet'de", "Murat'de" yazıyordu.
  static String locative(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return trimmed;
    const vowels = 'aıoueiöü';
    final lower = trimmed.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
    final last = lower.split('').lastWhere(vowels.contains, orElse: () => 'e');
    final hard = 'fstkçşhp'.contains(lower[lower.length - 1]);
    return "$trimmed'${hard ? 't' : 'd'}${'aıou'.contains(last) ? 'a' : 'e'}";
  }

  @override
  Locale get locale => const Locale('tr');

  @override
  String upper(String text) => text.replaceAll('i', 'İ').toUpperCase();

  @override
  String get appTitle => 'Envanter';
  @override
  String get home => 'Ana ekran';
  @override
  String get drawer => 'Çekmece';
  @override
  String get container => 'Klasör';
  @override
  String get item => 'Eşya';
  @override
  String get unnamed => 'Adsız';
  @override
  String get empty => 'boş';
  @override
  String recordCount(int n) => '$n kayıt';
  @override
  String get back => 'Geri';
  @override
  String get backHoldHint => 'ana ekrana dönmek';
  @override
  String get parentFolders => 'Üst klasörlere git';
  @override
  String get otherFolder => 'Başka klasöre git…';
  @override
  String get whichFolderToGo => 'Hangi klasöre gidilsin?';
  @override
  String get goHere => 'Buraya git';
  @override
  String get youAreHere => 'Buradasın';
  @override
  String get cancel => 'Vazgeç';
  @override
  String get save => 'Kaydet';
  @override
  String get delete => 'Sil';
  @override
  String get undo => 'Geri al';
  @override
  String get close => 'Kapat';
  @override
  String get edit => 'Düzenle';
  @override
  String get qrCode => 'QR kod';
  @override
  String get menu => 'Menü';
  @override
  String get search => 'Ara';
  @override
  String get newRecord => 'Yeni kayıt';
  @override
  String get clear => 'Temizle';

  @override
  String get nothingYet => 'Henüz boş';
  @override
  String itemsAtRoot(int n) => '$n klasör/eşya';
  @override
  String get createFirstContainer => 'İlk klasörü oluştur';
  @override
  String get createFirstContainerHint =>
      'Dolap, kutu, raf... içine eşya ve başka klasörler koyabilirsin.';
  @override
  String get addFirstItem => 'İlk eşyayı ekle';
  @override
  String get addFirstItemHint =>
      'İçine eşya koy ya da kutu simgesiyle bir klasör oluştur.';
  @override
  String get addInside => 'İçine yeni kayıt';

  @override
  String get addItem => 'Eşya ekle';
  @override
  String get addItemSubtitle => 'Tek bir nesne';
  @override
  String get addContainer => 'Klasör ekle';
  @override
  String get addContainerSubtitle => 'İçine eşya ve başka klasörler alır';

  @override
  String get newContainer => 'Yeni klasör';
  @override
  String get newItem => 'Yeni eşya';
  @override
  String get editRecord => 'Düzenle';
  @override
  String get name => 'Ad';
  @override
  String get itemNameHint => 'Örn. tornavida seti';
  @override
  String get photo => 'Fotoğraf';
  @override
  String get takePhoto => 'Fotoğraf çek';
  @override
  String get pickFromGallery => 'Galeriden seç';
  @override
  String get removePhoto => 'Resmi kaldır';
  @override
  String get replacePhoto => 'Resmi değiştir';
  @override
  String get photoFailed => 'Resim alınamadı. İzinleri kontrol et.';
  @override
  String get cardColor => 'Kart rengi';
  @override
  String get location => 'Konum';
  @override
  String get containerHasChildren => 'İçinde kayıt olan klasör eşyaya çevrilemez.';
  @override
  String get noteOptional => 'Not (isteğe bağlı)';

  @override
  String get physicalLocation => 'Fiziksel konum';
  @override
  String get physicalLocationHint =>
      'Bu kaydın dünyadaki yeri. Otomatik alabilir ya da elle yazabilirsin.';
  @override
  String get autoLocate => 'Otomatik konum al';
  @override
  String get locating => 'Konum alınıyor...';
  @override
  String get locationName => 'Konum adı';
  @override
  String get locationNameHint => 'Örn. Garaj, yazlık, depo';
  @override
  String get latitude => 'Enlem';
  @override
  String get longitude => 'Boylam';
  @override
  String get invalidCoordinates => 'Koordinatlar geçerli değil.';
  @override
  String get locationFailed => 'Konum alınamadı.';
  @override
  String get locationServiceOff => 'Cihazın konum servisi kapalı.';
  @override
  String get locationDenied => 'Konum izni verilmedi.';
  @override
  String get locationDeniedForever =>
      'Konum izni kalıcı olarak reddedilmiş. Ayarlardan açabilirsin.';

  @override
  String get changePlacement => 'Yerini değiştir';
  @override
  String get moveToTrash => 'Çöp kutusuna at';

  @override
  String whereShouldGo(String name) => '"$name" nereye gitsin?';
  @override
  String currentlyAt(String path) => 'Şu an: $path';
  @override
  String get currentPlace => 'şu anki yeri';
  @override
  String get drawerWithHint => 'Çekmece (yeri belirsizler)';
  @override
  String movedTo(String name, String path) => '"$name" taşındı: $path';
  @override
  String get moveNotPossible => 'Bu taşıma yapılamaz.';
  @override
  String get cannotMoveIntoItself => 'Bir klasör kendi içine taşınamaz.';
  @override
  String movedInto(String name, String target) => '"$name" → "$target"';
  @override
  String get dropHere => 'Bırak';
  @override
  String get intoHome => 'ana ekrana';
  @override
  String get intoDrawer => 'çekmeceye';
  @override
  String intoContainer(String name) => '"$name" içine';
  @override
  String movedToDrawer(String name) => '"$name" çekmeceye alındı';

  @override
  String get shareAsImage => 'Resim olarak paylaş';
  @override
  String get preparing => 'Hazırlanıyor...';
  @override
  String get qrHint =>
      'Kod bu kayda özeldir; yazdırıp kutunun üzerine yapıştırabilirsin.';
  @override
  String get scanQr => 'QR okut';
  @override
  String get scanQrHint =>
      'Klasör kodu içini açar, eşya kodu kartı öne çıkarır. Ürünün barkodu da okunur: kayıtlı eşya bulunur.';
  @override
  String get qrNotRecognized => 'Bu kod bu envantere ait değil.';
  @override
  String get barcode => 'Barkod';
  @override
  String get barcodeHint => 'Ürünün üstündeki barkod: okutunca bu eşya bulunur.';
  @override
  String get containerBarcodeHint => 'Klasörün / kolinin üstündeki barkod: okutunca bu klasör açılır.';
  @override
  String get scanBarcode => 'Barkod okut';
  @override
  String get scanBarcodeHint => 'Ürünün barkodunu çerçeveye getir.';
  @override
  String get barcodeUnknown => 'Bu barkod kayıtlı değil';
  @override
  String get barcodeUnknownBody =>
      'Yeni bir eşya olarak ekleyebilirsin. Var olan bir eşyaya bağlamak için: eşyayı düzenle → Diğer → Barkod.';
  @override
  String get newItemWithBarcode => 'Bu barkodla yeni eşya';
  @override
  String get newContainerWithBarcode => 'Bu barkodla yeni klasör';
  @override
  String barcodeMatches(int count) => 'Bu barkodla $count kayıt var';
  @override
  String barcodeAlsoOn(String name) => '"$name" de bu barkodu taşıyor.';
  @override
  String get fieldBarcode => 'barkod';
  @override
  String get qrRecordMissing => 'Koddaki kayıt bulunamadı; silinmiş olabilir.';
  @override
  String get cameraPermissionNeeded => 'Kamera izni gerekiyor.';

  @override
  String get visualSearch => 'Görüntüyle ara';
  @override
  String get visualSearchHint =>
      'Elindeki eşyanın fotoğrafını çek; envanterdeki resimlerle karşılaştırayım.';
  @override
  String get visualSearchRunning => 'Envanter taranıyor...';
  @override
  String get visualSearchNoMatch =>
      'Bu görüntüye yeterince benzeyen bir kayıt bulunamadı.';
  @override
  String get visualSearchNoImages =>
      'Karşılaştırılacak resim yok. Önce kartlara fotoğraf ekle.';
  @override
  String get visualSearchTake => 'Fotoğraf çek';
  @override
  String get visualSearchFromGallery => 'Galeriden seç';
  @override
  String get visualSearchOpening => 'Kamera açılıyor…';
  @override
  String get cameraBusy => 'Kamera hazırlanamadı. Başka bir uygulamada açık olabilir.';
  @override
  String get retry => 'Yeniden dene';
  @override
  String visualSearchResult(int n) => '$n olası eşleşme';
  @override
  String similarity(int percent) => '%$percent benzerlik';
  @override
  String get searchAgain => 'Yeniden çek';

  @override
  String get searchHint => 'Ada göre ara...';
  @override
  String get searchInInventory => 'Envanterde ara';
  @override
  String get searchInInventoryHint =>
      'Ad, konum adı ya da notlarda geçen bir kelime yaz. Ya da QR okut, fotoğrafla ara.';
  @override
  String noResultFor(String query) => '"$query" için kayıt bulunamadı.';
  @override
  String get goToPlace => 'Yerine git';

  @override
  String get drawerSubtitle => 'Yeri belli olmayanlar burada bekler';
  @override
  String drawerWaiting(int n) => '$n kayıt yer bekliyor';
  @override
  String get drawerEmpty => 'Çekmece boş';
  @override
  String get drawerEmptyHint =>
      'Bir kartı basılı tutup sağ kenara sürükleyince buraya bırakabilirsin. '
      'Sonra yerini rahatça belirlersin.';
  @override
  String get newRecordToDrawer => 'Çekmeceye yeni kayıt';

  @override
  String get trash => 'Çöp kutusu';
  @override
  String get emptyTrash => 'Boşalt';
  @override
  String get emptyTrashQuestion => 'Çöp kutusu boşaltılsın mı?';
  @override
  String get emptyTrashWarning =>
      'Buradaki kayıtlar ve içindekiler çöpten silinir. Yanlışlıkla olursa 30 gün içinde "Son silinenler"den '
      'geri getirebilirsin.';
  @override
  String get trashEmpty => 'Çöp kutusu boş';
  @override
  String insideCount(int n) => 'İçinde $n kayıt var';
  @override
  String get singleRecord => 'Tek kayıt';
  @override
  String get deleteForever => 'Kalıcı sil';
  @override
  String deleteForeverQuestion(String name) => '"$name" kalıcı silinsin mi?';
  @override
  String deleteForeverWarning(int n) =>
      'İçindeki $n kayıt da silinir. 30 gün içinde "Son silinenler"den geri getirilebilir.';
  @override
  String get purgeRecoverable => '30 gün içinde "Son silinenler"den geri getirilebilir.';
  @override
  String get recentlyPurged => 'Son silinenler';
  @override
  String get recentlyPurgedHint =>
      'Kalıcı silinenler 30 gün burada durur. Geri getirilen kayıt, paylaşılıyorsa diğerlerinde de geri gelir.';
  @override
  String get deleteNowOption => '30 gün bekletme, hemen tamamen sil';
  @override
  String get deleteNowWarning =>
      'Fotoğrafları ve ekleriyle bu telefondan hemen silinir, yer açılır. Geri getirilemez.';
  @override
  String get deleteNow => 'Tamamen sil';
  @override
  String deleteNowQuestion(String name) => '"$name" tamamen silinsin mi?';
  @override
  String get clearPurged => 'Temizle';
  @override
  String get clearPurgedQuestion => 'Son silinenler temizlensin mi?';
  @override
  String clearPurgedWarning(int n) =>
      'Buradaki $n kayıt fotoğrafları ve ekleriyle bu telefondan hemen silinir, yer açılır. Geri getirilemez.';
  @override
  String trashedWithChildren(String name, int n) =>
      '"$name" ve içindeki $n kayıt çöp kutusunda';
  @override
  String trashedSingle(String name) => '"$name" çöp kutusunda';

  @override
  String get sharing => 'Ortak kullanım';
  @override
  String get sharingNeedsNameTitle => 'Ağda nasıl görünsün?';
  @override
  String get sharingNeedsNameHint =>
      'Adın, katılma isteklerinde ve üye listesinde görünür.';
  @override
  String get inventoryNameLabel => 'Envanterin adı';
  @override
  String get inventories => 'Envanterler';
  @override
  String get deckSection => 'Deste';
  @override
  String thisInventoryTitle(String name) => 'Bu envanter: $name';
  @override
  String get thisInventoryHint =>
      'Aşağıdakiler yalnızca bu envanterin ayarları. Her envanterin kendi deste düzeni, tarih uyarısı, '
      'bildirimi ve ortak kullanımı (kimlerle, onaylı mı otomatik mi) var.';
  @override
  String get inventoriesHint =>
      'Her envanterin kendi kayıtları, fotoğrafları ve ortak kullanımı var. Aynı anda biri açıktır; '
      'paylaşılan ötekiler arka planda ya da açılınca eşitlenir.';
  @override
  String get newInventory => 'Yeni envanter';
  @override
  String get newInventoryHint => 'Boş bir envanter açılır; diğerleriyle karışmaz, ayrı paylaşılabilir.';
  @override
  String get create => 'Oluştur';
  @override
  String get switchInventory => 'Envanteri değiştir';
  @override
  String get menuFavorites => 'Sık kullanılan';
  @override
  String get menuExpired => 'Tarihi geçen';
  @override
  String get openNow => 'Açık';
  @override
  String lastOpened(String when) => 'son açılış $when';
  @override
  String get renameInventory => 'Yeniden adlandır';
  @override
  String get inventoryLook => 'Renk ve amblem';
  @override
  String get inventoryLookHint => 'Başlıkta, menüde ve envanter listesinde görünür. Yalnızca bu cihazda.';
  @override
  String get lookColor => 'Renk';
  @override
  String get lookEmblem => 'Amblem';
  @override
  String get lookNoColor => 'Renk yok';
  @override
  String deleteInventoryQuestion(String name) => '"$name" silinsin mi?';
  @override
  String deleteInventoryBody(int count) =>
      'Envanter ve içindeki $count kayıt, fotoğraflarıyla birlikte Silinenler\'e taşınır. 30 gün içinde '
      'geri getirebilirsin; sonra kalıcı olarak silinir.';
  @override
  String get deleteSharedNote =>
      'Bu envanter paylaşılıyor: diğerlerine sildiğin haber verilir, onların kopyası yerinde kalır. '
      'Yöneticiysen önce yönetimi kime bırakacağını seçersin.';
  @override
  String get deleteSharedClosedNote =>
      'Bu envanter paylaşılıyor: diğerlerine haber verilebilsin diye önce açılır.';
  @override
  String unopenedCopy(String name) => '$name (açılamayan kopya)';
  @override
  String get deletedInventories => 'Silinenler';
  @override
  String get deletedInventoriesHint => 'Silinen envanterler 30 gün burada durur, sonra kalıcı olarak silinir.';
  @override
  String get restoreInventory => 'Geri getir';
  @override
  String get purgeInventory => 'Kalıcı olarak sil';
  @override
  String purgeInventoryQuestion(String name) => '"$name" kalıcı olarak silinsin mi?';
  @override
  String get purgeInventoryBody => 'Kayıtları ve fotoğrafları bu cihazdan tamamen silinir; geri alınamaz.';
  @override
  String inventoryDeleted(String name) => '"$name" Silinenler\'e taşındı.';
  @override
  String lastBackupOn(String when) => 'son yedek $when';
  @override
  String get noBackup => 'yedeği yok';
  @override
  String unbackedInventories(int count) => '$count envanterin yedeği eksik.';
  @override
  String get backingUp => 'Yedekleniyor…';
  @override
  String backingUpAll(int done, int total) => 'Envanterler yedekleniyor ($done/$total)…';
  @override
  String get backupSection => 'Yedek';
  @override
  String get recoveryTitle => 'Envanter açılamadı';
  @override
  String recoveryBody(String name) =>
      '"$name" veritabanı açılamadı; bozuk dosya Silinenler\'e ayrı bir kopya olarak alındı ve envanter '
      'boş açıldı. Yedeğin varsa içe aktararak geri yükleyebilirsin.';
  @override
  String get backupOfferTitle => 'Yedek alalım mı?';
  @override
  String backupOfferBody(int count) =>
      'Envanterinde $count kayıt var. Sunucu olmadığı için telefon kaybolur ya da bozulursa hepsi gider. '
      'Buluta eşitlenen bir klasör seçersen bütün envanterlerin haftada bir oraya yedeklenir.';
  @override
  String get chooseFolder => 'Klasör seç';
  @override
  String get notNow => 'Şimdi değil';
  @override
  String get inventoryNameHint => 'Örn. Ev, Atölye, Kütüphane';
  @override
  String get members => 'Üyeler';
  @override
  String get thisDevice => 'bu cihaz';
  @override
  String get online => 'ağda';
  @override
  String get offline => 'ağda değil';
  @override
  String lastSynced(String when) => 'Son eşitleme: $when';
  @override
  String syncedAgo(String when) => 'en son $when eşitlendi';
  @override
  String rejectedNotice(String who, String name, String kind) => switch (kind) {
        'added' => '$who, eklediğin “$name” kaydını geri çevirdi.',
        'deleted' => '$who, “$name” kaydını silmeni geri çevirdi.',
        'trashed' => '$who, “$name” kaydını çöpe atmanı geri çevirdi.',
        'moved' => '$who, “$name” kaydını taşımanı geri çevirdi.',
        _ => '$who, “$name” kaydındaki değişikliğini geri çevirdi.',
      };
  @override
  String rejectedNoticeMany(String who, int n) => '$who, $n değişikliğini geri çevirdi.';
  @override
  String switchedTo(String inventory) => '“$inventory” envanterine geçildi.';
  @override
  String inOtherInventories(int n) => 'Diğer envanterlerde $n';
  @override
  String notSearchedYet(String names) => '$names henüz aranamıyor: bir kez açılıp kapanınca aranır.';
  @override
  String get otherListsSection => 'Diğer envanterler';
  @override
  String get otherListsHint => 'Dokununca o envantere geçilir, listesi açılır.';
  @override
  String get otherDatesSection => 'Diğer envanterlerde tarihi yaklaşanlar';
  @override
  String get otherDatesHint => 'Dokununca o envantere geçilir, tarihleri açılır.';
  @override
  String get openContainer => 'Klasörü aç';
  @override
  String get discardChangesQuestion => 'Değişikliklerden vazgeçilsin mi?';
  @override
  String get discardChangesAction => 'Vazgeç';
  @override
  String get keepEditing => 'Düzenlemeye devam et';
  @override
  String get rotateTitle => 'Ekranı döndür';
  @override
  String get openPhoto => 'Fotoğrafı aç';
  @override
  String get rotateHint =>
      'Açıkken telefonun otomatik döndürme ayarına uyar: telefon yan çevrilince yatay düzene geçer. Kapalıyken '
      'telefonda hep dikey kalır; tablette yine döner.';
  @override
  String inCart(String name) => '$name alındı; adedini evde “Yerleştirilecek”ten gir.';
  @override
  String get putAwaySection => 'Yerleştirilecek';
  @override
  String get putAwayHint => 'Markette işaretlenenler: yerine koyarken adedi ve tarihi gir.';
  @override
  String get putAway => 'Yerleştir';
  @override
  String get backToList => 'Listeye geri koy';
  @override
  String boughtWhen(String when) => 'alındı $when';
  @override
  String get imBuying => 'Ben alıyorum';
  @override
  String get notBuying => 'Almıyorum';
  @override
  String get youAreBuying => 'sen alıyorsun';
  @override
  String isBuying(String who) => '$who alıyor';
  @override
  String quantityChanged(String name, int from, int to) => '$name: $from → $to';
  @override
  String clockSpan(int minutes) => minutes < 120
      ? '$minutes dk'
      : minutes < 2880
          ? '${minutes ~/ 60} sa'
          : '${minutes ~/ 1440} gün';
  @override
  String clockGap(String span) => 'saat farkı $span';
  @override
  String syncFailed(String reason) => 'Son eşitleme olmadı: $reason';
  @override
  String get failUnreachable => 'cihaza ulaşılamadı';
  @override
  String get failTimeout => 'yanıt gelmedi';
  @override
  String get failRejected => 'istek reddedildi; iki telefonun saatine ve uygulama sürümüne bak';
  @override
  String get failServer => 'karşı cihazda bir hata oluştu';
  @override
  String get failOther => 'beklenmeyen bir hata';
  @override
  String clockMineWrong(String who, String span, bool behind) =>
      'Bu telefonun saati $span ${behind ? 'geri' : 'ileri'}; eşitlemede ${TrStrings.possessive(who)} saatine '
      'göre düzeltiliyor. Ayarlar\'dan otomatik tarih ve saati açman iyi olur.';
  @override
  String clockTheirsWrong(String who, String span, bool ahead) =>
      '${TrStrings.possessive(who)} telefonunun saati $span ${ahead ? 'ileri' : 'geri'}; eşitlemede onun '
      'telefonunda düzeltiliyor. Otomatik tarih ve saati açması iyi olur.';
  @override
  String clockUnknown(String who, String span) =>
      '${TrStrings.possessive(who)} telefonuyla saatler $span farklı; değişiklikler yanlış sırada '
      'birleşebilir. Saati otomatik olmayan telefonda otomatik tarih ve saat açılmalı.';
  @override
  String get neverSyncedWith => 'henüz eşitlenmedi';
  @override
  String get trustMember => 'Değişiklikleri sormadan gelsin';
  @override
  String get untrustMember => 'Değişiklikleri onayıma düşsün';
  @override
  String get trustedTag => 'sormadan';
  @override
  String get quickSmallTitle => 'Adet ve alışveriş listesi sormadan gelsin';
  @override
  String get quickSmallSubtitle =>
      'Onay beklerken de adet değişiklikleri ve listeye ekleme/çıkarma hemen uygulanır.';
  @override
  String get neverSynced => 'Henüz eşitlenmedi';
  @override
  String get syncNow => 'Şimdi eşitle';
  @override
  String get syncing => 'Eşitleniyor...';
  @override
  String get inventoriesOnNetwork => 'Ağdaki envanterler';
  @override
  String get noInventoriesOnNetwork =>
      'Karşı tarafta da ortak kullanım açık olmalı ve aynı Wi-Fi ağında olmalısınız.';
  @override
  String ownerLabel(String name) => 'Sahibi: $name';
  @override
  String joinQuestion(String inventory) => '"$inventory" envanterine katılma isteği gönderilsin mi?';
  @override
  String joinOwnerLine(String owner) => 'Sahibi $owner. Kabul ederse envanter bu cihaza gelir.';
  @override
  String joinMergeWarning(int n) => 'Sendeki $n kayıt da ortak envantere eklenecek.';
  @override
  String get sendRequest => 'İstek gönder';
  @override
  String get joinAsNew => 'Yeni envanter olarak katıl';
  @override
  String get joinIntoCurrent => 'Bununla birleştir';
  @override
  String joinSeparateHint(int n) =>
      'Ayrı bir envanter açılır, buradaki $n kayıt karışmaz. "Bununla birleştir" dersen kayıtların '
      'ortak envantere eklenir.';
  @override
  String waitingForApproval(String owner) => '${possessive(owner)} onayı bekleniyor...';
  @override
  String joinedMessage(String inventory) => '"$inventory" envanterine katıldın; eşitleniyor.';
  @override
  String get joinRejected => 'İstek kabul edilmedi.';
  @override
  String get joinUnreachable => 'Cihaza ulaşılamadı. Aynı Wi-Fi ağında mısınız?';
  @override
  String get joinTimeout => 'Yanıt gelmedi.';
  @override
  String get joinRequestTitle => 'Katılma isteği';
  @override
  String joinRequestBody(String name, String inventory) =>
      '$name, "$inventory" envanterine katılmak istiyor. Kabul edersen envanterin '
      'tamamını görüp düzenleyebilecek.';
  @override
  String get reject => 'Reddet';
  @override
  String get accept => 'Kabul et';
  @override
  String get leaveSharing => 'Ortaklıktan ayrıl';
  @override
  String get leaveSharingQuestion => 'Ortaklıktan ayrılınsın mı?';
  @override
  String get leaveSharingBody =>
      'Kayıtlar bu cihazda kalır ama artık diğerleriyle eşitlenmez.';
  @override
  String get leave => 'Ayrıl';
  @override
  String get sharingLimits =>
      'Eşitleme cihazlar aynı Wi-Fi ağındayken çalışır; uygulama kapalıyken arka planda, yaklaşık '
      'yarım saatte bir.';
  @override
  String sharingOnline(int n) => n == 0 ? 'Ortak kullanım açık' : 'Ortak kullanım: $n kişi ağda';

  @override
  String get sharingOffTitle => 'Ortak kullanım kapalı';
  @override
  String get sharingOffBody =>
      'Açınca aynı Wi-Fi ağındaki kişiler envanterini adıyla görür ve katılma isteği '
      'gönderebilir; sen de ağdaki envanterleri görüp katılabilirsin.';
  @override
  String get turnOnSharing => 'Ortak kullanımı aç';
  @override
  String sharingVisibleAs(String name) => 'Ağda "$name" adıyla görünüyorsun';
  @override
  String sharingJoinedAs(String inventory) => '"$inventory" envanterini ortak kullanıyorsun';
  @override
  String get howItWorks => 'Nasıl çalışır?';
  @override
  List<String> get howItWorksSteps => const [
        'Herkes kendi telefonunda ortak kullanımı açar; telefonlar aynı Wi-Fi ağında olmalı.',
        'Katılmak isteyen, "Ağdaki envanterler" listesinde envanteri adıyla görür ve istek gönderir.',
        'Envanterin yöneticisi isteği onaylar; artık envanter iki telefonda birlikte kullanılır.',
        'Birinin yaptığı değişiklik diğerlerine zil simgesinde bildirim olarak gelir; onaylanınca uygulanır.',
        'Yönetici üyeleri ana kullanıcı yapabilir, bir varis seçebilir ya da bir klasöre sorumlu atayabilir '
            '(ör. Mutfak → Ayşe). '
            'Onların yetkili oldukları yerdeki değişiklikleri onay beklemez.',
      ];
  @override
  String get searchingNetwork => 'Ağ taranıyor...';
  @override
  String get joinHint => 'Katılmak için dokun; sahibi onaylayınca birlikte kullanmaya başlarsınız.';
  @override
  String get join => 'Katıl';
  @override
  String get owner => 'yönetici';
  @override
  String get you => 'sen';
  @override
  String get noMembersYet =>
      'Henüz kimse katılmadı. Aynı ağdaki biri bu sayfadan envanterini görüp istek gönderebilir.';
  @override
  String get changes => 'Değişiklikler';
  @override
  String get autoAcceptTitle => 'Değişiklikleri otomatik kabul et';
  @override
  String get autoAcceptSubtitle =>
      'Açıkken diğerlerinin yaptığı değişiklikler sormadan hemen uygulanır; kalıcı silmeler ve toplu çöpe '
      'atmalar yine sorulur.';
  @override
  String pendingChanges(int n) => n == 0 ? 'Bekleyen değişiklik yok' : '$n bekleyen değişiklik';
  @override
  String get noPendingChanges => 'Her şey güncel';
  @override
  String get noPendingChangesBody =>
      'Ortak kullananların yaptığı değişiklikler burada onayını bekler.';
  @override
  String get changesHint =>
      'Kabul ettiğin değişiklik senin telefonunda da uygulanır. Reddedersen senin '
      'sürümün geçerli kalır ve diğerlerine de gönderilir.';
  @override
  String get acceptAll => 'Tümünü kabul et';
  @override
  String get rejectAll => 'Tümünü reddet';
  @override
  String get rejectAllQuestion => 'Tüm değişiklikler reddedilsin mi?';
  @override
  String get rejectBody =>
      'Senin sürümün geçerli kalır ve diğerlerine de gönderilir. Reddedilen yeni kayıtlar çöp kutusuna gider.';
  @override
  String get someone => 'Biri';
  @override
  String changeAdded(String who) => '$who ekledi';
  @override
  String changeEdited(String who) => '$who düzenledi';
  @override
  String changeMoved(String who) => '$who taşıdı';
  @override
  String changeReordered(String who) => '$who sıralamayı değiştirdi';
  @override
  String changeTrashed(String who) => '$who çöpe attı';
  @override
  String changeRestored(String who) => '$who çöpten geri aldı';
  @override
  String changeDeleted(String who) => '$who kalıcı olarak sildi';
  @override
  String renamedFrom(String old) => 'eski adı: $old';
  @override
  String andInside(int n) => 've içindeki $n kayıt';
  @override
  String reorderedIn(String place) => '$place içindeki sıra';
  @override
  String changedFields(List<String> fields) => fields.join(', ');
  @override
  String get fieldPhoto => 'fotoğraf';
  @override
  String get fieldColor => 'renk';
  @override
  String get fieldNote => 'not';
  @override
  String get fieldKind => 'tür';
  @override
  String get fieldLocation => 'konum';
  @override
  String get justNow => 'az önce';
  @override
  String minutesAgo(int n) => '$n dk önce';
  @override
  String hoursAgo(int n) => '$n sa önce';
  @override
  String get changesAccepted => 'Değişiklik uygulandı';
  @override
  String get changesRejected => 'Senin sürümün korundu';
  @override
  String newChangesFrom(String who, int n) =>
      n == 1 ? '$who bir değişiklik yaptı' : '$who $n değişiklik yaptı';
  @override
  String get show => 'Göster';
  @override
  String get pendingMarkTooltip => 'Onay bekleyen değişiklik var';
  @override
  String get tipTitle => 'Küçük ipuçları';
  @override
  String get tipBody =>
      'Karttaki ⋯ düğmesi seçenekleri açar. Taşımak için karta basılı tut ve sürükle; bir '
      'klasörün üzerinde bekleyince içine girersin. Kartı sola kaydırırsan çöp kutusuna, sağa '
      'kaydırırsan çekmeceye gider. Sürüklerken bir kartın üst kenarına gelirsen kart '
      'oraya sıralanır. Sık girdiklerini ⋯ menüsünden sık kullanılanlara ekle; yeri belli '
      'olmayanlar sağdaki çekmecede, yerinde bulunamayanlar kayıpta durur. Derindeki bir '
      'klasörden çıkmak için geri okuna basılı tut: doğrudan ana ekrana dönersin.';
  @override
  String get gotIt => 'Anladım';
  @override
  String get items => 'Eşyalar';
  @override
  String get searchInventory => 'Envanterde ara';
  @override
  String get moreActions => 'Diğer';
  @override
  String get cancelDrag => 'Vazgeç';
  @override
  String get upOneLevel => 'Üst seviye';
  @override
  String get quantity => 'Adet';
  @override
  String get quantityHint => 'Birden fazlaysa sayısını tut; kartta − / + ile değişir.';
  @override
  String get quantityTrackedHint => '0 olunca kayıt silinmez; yeri durur, stok gelince artırırsın.';
  @override
  String get stopCounting => 'Adet tutmayı bırak';
  @override
  String get outOfStock => 'Tükendi';
  @override
  String quantityShort(int n) => '$n adet';
  @override
  String get lowStockShort => 'Azaldı';
  @override
  String get minQuantityOff => 'En az adet';
  @override
  String get minQuantityOffHint => 'Adet bu sayıya inince kartta "Azaldı" yazar ve alışveriş listesine önerilir.';
  @override
  String minQuantityOn(int n) => 'En az $n adet';
  @override
  String minQuantityOnHint(int n) => '$n ya da daha az kalınca "Azaldı" sayılır.';
  @override
  String get removeMinQuantity => 'Sınırı kaldır';
  @override
  String get fieldMinQuantity => 'en az adet';
  @override
  String get increase => 'Bir artır';
  @override
  String get decrease => 'Bir azalt';
  @override
  String get fieldQuantity => 'adet';
  @override
  String get fullShort => 'Dolu';
  @override
  String get markFull => 'Dolu işaretle';
  @override
  String get markNotFull => 'Dolu işaretini kaldır';
  @override
  String get fullHint => 'Yeni bir şey sığmıyorsa işaretle; yer ararken kartında görünür.';
  @override
  String markedFull(String name) => '"$name" dolu olarak işaretlendi.';
  @override
  String markedNotFull(String name) => '"$name" artık dolu değil.';
  @override
  String get fieldFull => 'doluluk';
  @override
  String get favorites => 'Sık kullanılanlar';
  @override
  String get addFavorite => 'Sık kullanılanlara ekle';
  @override
  String get removeFavorite => 'Sık kullanılanlardan çıkar';
  @override
  String favoriteAdded(String name) => '"$name" sık kullanılanlara eklendi.';
  @override
  String favoriteRemoved(String name) => '"$name" sık kullanılanlardan çıkarıldı.';
  @override
  String get favoritesSubtitle => 'Sık girdiklerin burada';
  @override
  String get favoritesEmpty => 'Sık kullanılan yok';
  @override
  String get favoritesEmptyHint =>
      'Sık girdiğin bir klasörü ya da eşyayı ⋯ menüsünden buraya ekle; iç içe '
      'klasörlere her seferinde tek tek girmeden ulaşırsın. Bu liste yalnızca bu '
      'cihazda kalır, ortak kullananlara geçmez.';
  @override
  String folderDropTitle(String name) => '"$name" klasörü';
  @override
  String get dropMoveFolder => 'Klasörü taşı';
  @override
  String dropMoveFolderHint(String place) => 'Yeni yeri: $place';
  @override
  String get dropContentsOnly => 'Yalnızca içindekileri aktar';
  @override
  String dropContentsHint(int n, String place) =>
      '$n kayıt $place içine geçer, klasör boş olarak yerinde kalır';
  @override
  String contentsMoved(int n, String place) => '$n kayıt taşındı: $place';
  @override
  String get groupKindsTitle => 'Klasörleri ve eşyaları ayır';
  @override
  String get groupKindsHint =>
      'Açıkken klasörler üstte, eşyalar ayrı bir grupta durur. Kapalıyken hepsi tek '
      'sırada, senin dizdiğin gibi.';
  @override
  String get qrShortcutHint => 'Kutunun üstündeki kodu okut, içini aç';
  @override
  String get photoShortcutHint => 'Elindekinin fotoğrafını çek, yerini bul';
  @override
  String resultCount(int n) => '$n sonuç';
  @override
  String get placeSection => 'Yeri';
  @override
  String get kindLabel => 'Tür';
  @override
  String get gpsLocation => 'Dünyadaki konumu';
  @override
  String get gpsLocationHint => 'İsteğe bağlı; haritadaki yeri (GPS)';
  @override
  String get useCurrentLocation => 'Şu anki konumu ekle';
  @override
  String get placementHint => 'Durduğu klasör';
  @override
  String get options => 'Seçenekler';
  @override
  String get icon => 'Simge';
  @override
  String get chooseIcon => 'Simge seç';
  @override
  String get defaultIcon => 'Varsayılan';
  @override
  String get fieldIcon => 'simge';
  @override
  String get adminRole => 'ana kullanıcı';
  @override
  String get makeAdmin => 'Ana kullanıcı yap';
  @override
  String get removeAdmin => 'Ana kullanıcılığı kaldır';
  @override
  String get removeFromSharing => 'Ortak kullanımdan çıkar';
  @override
  String removeMemberQuestion(String name) => '$name çıkarılsın mı?';
  @override
  String removeMemberBody(String name) =>
      '$name artık bu envanterle eşitlenmez; cihazındaki kayıtlar onda kalır. Yeniden katılmak '
      'isterse isteği bir ana kullanıcının onayına düşer.';
  @override
  String get remove => 'Çıkar';
  @override
  String memberRemoved(String name) => '$name ortak kullanımdan çıkarıldı.';
  @override
  String get chooseSuccessorTitle => 'Envanteri kim yönetsin?';
  @override
  String get chooseSuccessorBody =>
      'Sen ayrılınca yönetici o olur: değişiklikleri onaylar, kişi ekleyip çıkarır, görev yeri atar '
      've bir varis seçer. Diğerlerine haber gider.';
  @override
  String get heirRole => 'varis';
  @override
  String get heirSuffix => '(varis)';
  @override
  String get makeHeir => 'Varis yap';
  @override
  String get removeHeir => 'Varisliği kaldır';
  @override
  String get transferOwnership => 'Yöneticiliği devret';
  @override
  String transferQuestion(String name) => 'Yöneticiliği $name devralsın mı?';
  @override
  String transferBody(String name) =>
      '$name yönetici olur; sen onun varisi olursun: o ayrılır ya da envanteri silerse yönetim sana döner.';
  @override
  String get transfer => 'Devret';
  @override
  String get youAreOwnerTitle => 'Artık yöneticisin';
  @override
  String youAreOwnerBody(String previous) =>
      '$previous envanteri bıraktı ya da yönetimi sana devretti. Değişiklikleri onaylayabilir, kişi ekleyip '
      'çıkarabilir, görev yeri atayabilir ve bir varis seçebilirsin.';
  @override
  String newOwnerIs(String name) => 'Yönetici artık $name.';
  @override
  String heirToYou(String name) => '$name seni varis seçti: yönetici ayrılırsa envanteri sen yönetirsin.';
  @override
  String heirSet(String name) => '$name artık varis.';
  @override
  String get heirCleared => 'Varis kaldırıldı.';
  @override
  String memberLeft(String name) => '$name ortak kullanımdan ayrıldı.';
  @override
  String memberDeletedInventory(String name) => '$name envanteri kendi cihazından sildi; sizde sürüyor.';
  @override
  String get removedFromSharingTitle => 'Ortak kullanımdan çıkarıldın';
  @override
  String removedFromSharingBody(String inventory) =>
      '"$inventory" envanterinin bir ana kullanıcısı seni çıkardı. Kayıtların bu cihazda duruyor ama '
      'artık eşitlenmiyor.';
  @override
  String get adminHint =>
      'Yönetici bir varis seçer; yönetici ayrılır ya da envanteri silerse varis yönetici olur. Varisin ve '
      'ana kullanıcıların değişiklikleri herkese onaysız uygulanır; katılma isteklerini onaylar, kişi '
      'çıkarır, başkalarını ana kullanıcı yapar ve klasörlere sorumlu atarlar.';
  @override
  String managersLabel(String names) => 'Sorumlu: $names';
  @override
  String get assignManager => 'Sorumlu ata';
  @override
  String get chooseManagers => 'Bu klasörün sorumluları';
  @override
  String get managerHint =>
      'Sorumlunun bu klasörde ve içindekilerde yaptığı değişiklikler herkese onaysız '
      'uygulanır; başkalarının değişiklikleri hakkındaki kararı da herkese geçer.';
  @override
  String get noOneToAssign => 'Önce birinin envantere katılması gerekir.';
  @override
  String managesPlaces(String places) => 'Sorumlu olduğu yerler: $places';
  @override
  String appliedByAuthority(String who, int n) =>
      n == 1 ? '$who bir değişiklik yaptı; yetkili olduğu için uygulandı' : '$who $n değişiklik yaptı; yetkili olduğu için uygulandı';
  @override
  String get fieldManagers => 'sorumlu';
  @override
  String get scanNetwork => 'Ağı tara';
  @override
  String get scanAgain => 'Tekrar tara';
  @override
  String get scanPrompt =>
      'Katılmak istediğin envanteri bulmak için ağı tara. Tarama birkaç saniye sürer; ağ sürekli taranmaz.';
  @override
  String get noInventoriesFound => 'Envanter bulunamadı';
  @override
  String get dragHintStill => 'Taşımak için sürükle';
  @override
  String get dragHintMoving => 'Bir klasörün üzerine bırak';

  @override
  String get lostDrawer => 'Kayıp';
  @override
  String get lostShort => 'Kayıp';
  @override
  String get lostSubtitle => 'Yerinde bulunamayanlar; yerini bilen buradan bildirir';
  @override
  String lostWaiting(int n) => '$n kayıp eşya aranıyor';
  @override
  String get lostEmpty => 'Kayıp eşya yok';
  @override
  String get lostEmptyHint =>
      'Bir eşya yerinde yoksa kartına basılı tut ve "Yerinde yok" de. Buraya gelir, '
      'ortak kullananlara da bildirilir.';
  @override
  String get notThere => 'Yerinde yok';
  @override
  String get iKnowWhere => 'Yerini biliyorum';
  @override
  String notThereQuestion(String name) => '"$name" yerinde yok mu?';
  @override
  String get reportLost => 'Kayıp olarak bildir';
  @override
  String get reportLostHint =>
      'Kayıp çekmecesine alınır; ortak kullananlara bildirim gider, yerini bilen düzeltir.';
  @override
  String get trashInstead => 'Çöpe at';
  @override
  String get trashInsteadHint => 'Artık yoksa. Çöp kutusundan geri alınabilir.';
  @override
  String markedLost(String name) => '"$name" kayıp çekmecesinde';
  @override
  String lastSeenIn(String path) => 'Son yeri: $path';
  @override
  String lostReported(String who, String name) => '$who: "$name" yerinde yok, kayıplara alındı';
  @override
  String foundReported(String who, String name, String path) => '$who "$name" eşyasını buldu: $path';
  @override
  String changeLost(String who) => '$who kayıp bildirdi';
  @override
  String changeFound(String who) => '$who buldu';
  @override
  String get lostItems => 'Kayıp eşyalar';

  @override
  String get settings => 'Ayarlar';
  @override
  String get appearance => 'Görünüm';
  @override
  String get systemTheme => 'Sistemle aynı';
  @override
  String get lightTheme => 'Açık tema';
  @override
  String get darkTheme => 'Koyu tema';
  @override
  String get language => 'Dil';
  @override
  String get languageSystem => 'Sistemle aynı';
  @override
  String get autoLocationTitle => 'Yeni klasöre otomatik konum';
  @override
  String get autoLocationSubtitle =>
      'Klasör oluştururken GPS konumu kendiliğinden eklenir.';
  @override
  String get inventory => 'Envanter';
  @override
  String get recordTotal => 'Kayıt sayısı';
  @override
  String get inTrash => 'Çöp kutusundaki kayıt';
  @override
  String get backup => 'Yedek';
  @override
  String get exportTitle => 'Dışa aktar';
  @override
  String get exportHint =>
      'Bütün kayıtlar, fotoğraflar ve ekler tek bir dosyaya konur; istediğin yere kaydedebilir '
      'ya da gönderebilirsin.';
  @override
  String get exportShareText => 'Envanter yedeği';
  @override
  String get exporting => 'Dışa aktarılıyor…';
  @override
  String exportFailed(String reason) => 'Dışa aktarılamadı: $reason';
  @override
  String get importTitle => 'İçe aktar';
  @override
  String get importHint =>
      'Daha önce dışa aktarılmış bir dosyayı geri yükler. Var olan kayıtlar silinmez; '
      'aynı kaydın iki sürümü varsa yeni olan kalır.';
  @override
  String get importing => 'İçe aktarılıyor…';
  @override
  String get importNothing => 'Yeni kayıt yok; her şey zaten güncel.';
  @override
  String importDone(int added, int updated, int photos) => [
        if (added > 0) '$added kayıt eklendi',
        if (updated > 0) '$updated kayıt güncellendi',
        if (photos > 0) '$photos fotoğraf',
      ].join(', ');
  @override
  String get importFailed => 'Dosya okunamadı.';
  @override
  String get importNotOurs => 'Bu dosya bir envanter yedeği değil.';
  @override
  String get importNewerVersion => 'Dosya uygulamanın yeni bir sürümünden; önce güncelle.';
  @override
  String get localOnly =>
      'Veriler hiçbir sunucuya gönderilmez; bu cihazda ve ortak kullandığın cihazlarda saklanır.';
  @override
  String get user => 'Kullanıcı';
  @override
  String get userNameTitle => 'Kullanıcı adı';
  @override
  String get yourName => 'Adın';
  @override
  String get localInventory => 'Bu cihazda yerel envanter';
  @override
  String get editName => 'Adı düzenle';
  @override
  String get totalRecords => 'Toplam kayıt';
  @override
  String get recentTitle => 'Son dokundukların';
  @override
  String get inNote => 'Notta';
  @override
  String lastBackup(String when) => 'Son yedek: $when';
  @override
  String get neverBackedUp => 'Henüz yedek alınmadı.';
  @override
  String get today => 'bugün';
  @override
  String daysAgo(int n) => n == 1 ? 'dün' : '$n gün önce';
  @override
  String get backupReminderTitle => 'Yedek alma zamanı';
  @override
  String backupReminderBody(int changes, {required bool never}) => never
      ? 'Envanterin yalnızca bu telefonda duruyor; bir kopyasını kenara koy.'
      : 'Son yedekten bu yana $changes kayıt değişti.';
  @override
  String get backupNow => 'Şimdi yedekle';
  @override
  String get later => 'Sonra';
  @override
  String get select => 'Seç';
  @override
  String get selectHint => 'Seçmek için kartlara dokun';
  @override
  String selectedCount(int n) => '$n seçili';
  @override
  String get selectAll => 'Tümünü seç';
  @override
  String get doneSelecting => 'Seçimi bitir';
  @override
  String get moveShort => 'Taşı';
  @override
  String get toDrawerShort => 'Çekmeceye';
  @override
  String get labelsShort => 'Etiket';
  @override
  String get trashShort => 'Çöpe';
  @override
  String whereShouldGoMany(int n) => '$n kayıt nereye gitsin?';
  @override
  String movedMany(int n, String place) => '$n kayıt taşındı: $place';
  @override
  String trashedMany(int n) => '$n kayıt çöp kutusuna atıldı';
  @override
  String get qrLabels => 'QR etiketleri';
  @override
  String get labelsTitle => 'QR etiket sayfası';
  @override
  String get labelsHint =>
      'A4 kağıda yazdır, kes ve kutulara yapıştır. Okutunca kayıt açılır.';
  @override
  String get labelSize => 'Etiket boyu';
  @override
  String get labelSmall => 'Küçük';
  @override
  String get labelMedium => 'Orta';
  @override
  String get labelLarge => 'Büyük';
  @override
  String perPage(int n) => 'sayfada $n';
  @override
  String get labelsWhich => 'Hangileri';
  @override
  String get labelScopeFolders => 'Klasörler';
  @override
  String get labelScopeAll => 'Eşyalar da';
  @override
  String labelCount(int labels, int pages) => '$labels etiket · $pages sayfa';
  @override
  String get createPdf => 'PDF oluştur ve paylaş';
  @override
  String get labelsShareText => 'Envanter QR etiketleri';
  @override
  String labelsFailed(String reason) => 'Etiketler hazırlanamadı: $reason';
  @override
  String get moveHere => 'Buraya taşı';
  @override
  String get alreadyHere => 'Zaten burada';
  @override
  String get noFoldersHere => 'Burada klasör yok. İstersen buraya taşı ya da ↑ ile yukarı çık.';
  @override
  String get noFoldersInside => 'Burada alt klasör yok. Burayı seçebilir ya da ↑ ile yukarı çıkabilirsin.';
  @override
  String get noFoldersWhereYouAre => 'Bulunduğun klasörde alt klasör yok. ↑ ile yukarı çıkıp başka bir klasör seç.';
  @override
  String folderCount(int n) => '$n klasör';
  @override
  String get keepPrivate => 'Yalnızca bende tut';
  @override
  String get makeShared => 'Diğer cihazlarla paylaş';
  @override
  String get privateHint => 'Yalnızca bu cihazda; eşitlenmez';
  @override
  String get privateInherited => 'Klasörü yalnızca bende tutuluyor; bu da eşitlenmez.';
  @override
  String markedPrivate(String name, {required bool wasShared}) => wasShared
      ? '$name yalnızca bu cihazda; artık eşitlenmez. Daha önce gönderilen kopyası diğer cihazlarda kalır.'
      : '$name yalnızca bu cihazda; eşitlenmez.';
  @override
  String markedShared(String name) => '$name artık diğer cihazlarla eşitlenir.';
  @override
  String get privateSwitchTitle => 'Yalnızca bende';
  @override
  String get privateSwitchHint =>
      'Ortak kullanımda başka cihazlara gönderilmez; içine konan her şey de özel olur.';
  @override
  String heldAt(String who) => locative(who);
  @override
  String heldHint(String who) =>
      '$who bunu kendi özel alanına aldı; bundan sonraki değişiklikleri gelmez. Bir yere koyarsan işaret kalkar.';
  @override
  String get datesSection => 'Tarihler';
  @override
  String get purchaseDate => 'Satın alma tarihi';
  @override
  String get expiryDate => 'Son kullanma tarihi';
  @override
  String get shelfLife => 'Raf ömrü';
  @override
  String get shelfLifeHint => 'Son kullanma tarihi yazmayanlar için (muz, elma): satın alma tarihine eklenir.';
  @override
  String get warnBeforeExpiry => 'Son kullanmaya kala uyar';
  @override
  String defaultWarn(String span) => 'Genel ayar ($span)';
  @override
  String get warrantyEnd => 'Garanti bitiş tarihi';
  @override
  String get warrantyPeriod => 'Garanti süresi';
  @override
  String get warrantyPeriodHint => 'Bitiş tarihi verilmediyse satın alma tarihine eklenir.';
  @override
  String get notSet => 'Belirtilmedi';
  @override
  String calculated(String date) => 'Hesaplanan: $date';
  @override
  String get needsPurchaseDate => 'Satın alma tarihi girilince hesaplanır.';
  @override
  String get dateOverrides => 'Tarih verildiği için kullanılmıyor.';
  @override
  String get clearValue => 'Kaldır';
  @override
  String get useDefault => 'Genel ayarı kullan';
  @override
  String get done => 'Tamam';
  @override
  String get amount => 'Süre';
  @override
  String spanText(TimeSpan span) => '${span.amount} ${switch (span.unit) {
        SpanUnit.day => 'gün',
        SpanUnit.week => 'hafta',
        SpanUnit.month => 'ay',
        SpanUnit.year => 'yıl',
      }}';
  @override
  String unitLabel(SpanUnit unit) => switch (unit) {
        SpanUnit.day => 'Gün',
        SpanUnit.week => 'Hafta',
        SpanUnit.month => 'Ay',
        SpanUnit.year => 'Yıl',
      };
  @override
  List<String> get monthsShort =>
      const ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
  @override
  String get expiredShort => 'SKT geçti';
  @override
  String someExpired(int k) => '$k tanesi geçti';
  @override
  String moreDates(int n) => '+$n tarih';
  @override
  String discardExpiredAction(int k) => 'Tarihi geçenleri at ($k)';
  @override
  String discardedExpired(String name, int k) => '$name: tarihi geçen $k tane atıldı.';
  @override
  String addedWithDate(String date) => '1 tane eklendi · SKT $date';
  @override
  String get otherDate => 'Başka tarih';
  @override
  String get newLotsDate => 'Yenilerin son kullanma tarihi';
  @override
  String get expiryDates => 'Son kullanma tarihleri';
  @override
  String get addLotButton => 'Farklı tarihli paket ekle';
  @override
  String get expiringShort => 'SKT yaklaştı';
  @override
  String expiryOn(String date) => 'SKT $date';
  @override
  String daysLeft(int n) => '$n gün kaldı';
  @override
  String get lastDayToday => 'bugün son gün';
  @override
  String expiredAgo(int n) => n == 1 ? 'dün bitti' : '$n gün önce bitti';
  @override
  String warrantyUntil(String date) => 'Garanti $date';
  @override
  String get warrantyEnded => 'Garanti bitti';
  @override
  String get expiryWarnSetting => 'Son kullanma uyarısı';
  @override
  String expiryWarnSettingHint(String span) =>
      'Son kullanma tarihine $span kala kartta uyarı çıkar. Her eşyada ayrıca değiştirilebilir.';
  @override
  String expiryWarnGeneralHint(String span) =>
      'Son kullanma tarihine en çok $span kala kartta uyarı çıkar; kısa ömürlülerde (yoğurt, süt) ömrünün '
      'dörtte biri kala. Her eşyada ayrıca değiştirilebilir.';
  @override
  String get datesPage => 'Tarihi yaklaşanlar';
  @override
  String get expiredSection => 'Süresi geçenler';
  @override
  String get expiringSection => 'Yaklaşanlar';
  @override
  String get warrantySection => 'Garantiler';
  @override
  String get noDatesSoon => 'Yaklaşan son kullanma tarihi yok';
  @override
  String get noDatesSoonHint =>
      'Eşyanın düzenleyicisindeki Tarihler bölümünden satın alma, son kullanma ve garanti eklenir.';
  @override
  String get fieldDates => 'tarihler';
  @override
  String peerOutdated(String who) =>
      "${TrStrings.possessive(who)} uygulaması eski sürüm; güncellenene kadar onunla eşitlenmiyor.";
  @override
  String selfOutdated(String who) =>
      "Bu uygulama ${TrStrings.possessive(who)} uygulamasından eski; güncellenene kadar eşitlenmiyor.";
  @override
  String get memberOutdated => 'Uygulaması eski; güncellenene kadar eşitlenmiyor';
  @override
  String get thisOutdated => 'Bu uygulama ondan eski; güncelle';
  @override
  String get joinIncompatible =>
      'Katıldın ama iki uygulamanın sürümü farklı; güncel olmayan güncellenince envanter gelir.';
  @override
  String get autoBackupTitle => 'Otomatik yedek';
  @override
  String get autoBackupHint =>
      'Bütün envanterler seçtiğin klasöre kendi adlarıyla yedeklenir: haftada bir ve değişen envanterden '
      'çıkarken. Her birinin en yeni 4 yedeği kalır. Telefon kaybolursa da işe yaraması için buluta '
      'eşitlenen ya da bilgisayara aktardığın bir klasör seç.';
  @override
  String autoBackupOn(String folder) =>
      'Bütün envanterler “$folder” klasörüne: haftada bir ve değişen envanterden çıkarken. Her birinin en '
      'yeni 4 yedeği kalır.';
  @override
  String get autoBackupFailed => 'Son otomatik yedek yazılamadı; klasörü yeniden seç.';
  @override
  String autoBackupWritten(String folder) => 'Yedek “$folder” klasörüne yazıldı.';
  @override
  String get notifyChannel => 'Son kullanma, garanti ve bakım';
  @override
  String get notifyChannelHint => 'Son kullanma tarihi yaklaşan eşyalar, biten garantiler ve bakım günleri';
  @override
  String notifyExpiring(String date, int daysLeft) => 'Son kullanma $date · $daysLeft gün kaldı';
  @override
  String get notifyLastDay => 'Bugün son kullanma günü';
  @override
  String notifyWarranty(String date) => 'Garanti $date tarihinde bitiyor';
  @override
  String notifyManyTitle(int n) => '$n eşyanın tarihi yaklaştı';
  @override
  String get notifySetting => 'Telefon bildirimi';
  @override
  String get notifySettingHint =>
      'Uyarı süresine girince, son gün, garantinin bitmesine bir ay kala ve bakım gününde sabah 9\'da '
      'bildirim gelir; uygulama kapalıyken de.';
  @override
  String get notifyDenied => 'Bildirim izni verilmedi; açmak için dokun.';
  @override
  String get shoppingList => 'Alışveriş listesi';
  @override
  String get outOfStockSection => 'Tükenenler';
  @override
  String get replaceSection => 'Tarihi geçenler';
  @override
  String get lowSection => 'Azalanlar';
  @override
  String get autoShopTitle => 'Listeye kendiliğinden ekle';
  @override
  String get autoShopHint => 'Bitince, azalınca ya da son kullanma tarihi geçince alışveriş listesine girer.';
  @override
  String get nowOnShoppingList => 'Alışveriş listesine eklendi.';
  @override
  String get expiredPanel => 'Tarihi geçenler';
  @override
  String get expiredSubtitle => 'Yerinde duranlar';
  @override
  String get expiredEmpty => 'Tarihi geçen yok';
  @override
  String get expiredEmptyHint =>
      'Son kullanma tarihi geçen eşyalar burada işaretli durur, yerlerinden kıpırdamaz. Çöpe atınca, '
      'çekmeceye alınca ya da bitince buradan düşer.';
  @override
  String get toBuySection => 'Alınacaklar';
  @override
  String get suggestionsSection => 'Önerilenler';
  @override
  String get suggestionsHint => 'Tükenen, azalan ya da tarihi geçen ama listende olmayanlar.';
  @override
  String get addToShopping => 'Alışveriş listesine ekle';
  @override
  String get removeFromShopping => 'Alışveriş listesinden çıkar';
  @override
  String get addShort => 'Ekle';
  @override
  String get addToListShort => 'Listeye ekle';
  @override
  String addedToShopping(String name) => '$name alışveriş listesine eklendi.';
  @override
  String removedFromShopping(String name) => '$name alışveriş listesinden çıkarıldı.';
  @override
  String ranOut(String name) => '$name tükendi.';
  @override
  String runningLow(String name) => '$name azaldı.';
  @override
  String get fieldShopping => 'alışveriş listesi';
  @override
  String get outOfStockNote => 'tükendi';
  @override
  String lowLeft(int left, int min) => '$left kaldı · en az $min';
  @override
  String lowNote(int left) => '$left kaldı';
  @override
  String get bought => 'Aldım';
  @override
  String get boughtNew => 'Yenisini aldım';
  @override
  String get howManyBought => 'Kaç tane aldın?';
  @override
  String restocked(String name, int n) => '$name: $n adet';
  @override
  String replacedWithDate(String name, String date) => '$name yenilendi; yeni son kullanma $date.';
  @override
  String replacedEnterDate(String name) => '$name yenilendi; paketteki son kullanma tarihini girmeyi unutma.';
  @override
  String get enterDate => 'Tarih gir';
  @override
  String get shoppingEmpty => 'Alınacak bir şey yok';
  @override
  String get shoppingEmptyHint =>
      'Kartın ⋯ menüsünden "Alışveriş listesine ekle" ile eklersin; aldıkça listeden düşer. Bitince, '
      'azalınca ya da tarihi geçince kendiliğinden girsin istediğin eşyada, düzenlerken "Listeye '
      'kendiliğinden ekle"yi aç.';
  @override
  String get shareList => 'Listeyi paylaş';
  @override
  String shoppingHeader(String date) => 'Alışveriş listesi · $date';
  @override
  String get pastDateNote => 'tarihi geçti';

  @override
  String get attachments => 'Ekler';
  @override
  String get fieldAttachments => 'ekler';
  @override
  String get addAttachment => 'Ek ekle';
  @override
  String get attachmentsHint => 'Kullanım kılavuzu, garanti belgesi, fatura, bir video ya da bağlantı.';
  @override
  String get attachDocument => 'Belge ya da dosya';
  @override
  String get attachDocumentHint => 'PDF kılavuz, fatura, telefondaki herhangi bir dosya';
  @override
  String get attachRecordVideo => 'Video çek';
  @override
  String get attachFromGallery => 'Galeriden fotoğraf ya da video';
  @override
  String get attachLink => 'Bağlantı';
  @override
  String get attachLinkHint => 'Bir videonun ya da internet sayfasının adresi';
  @override
  String get linkAddress => 'Adres';
  @override
  String get linkTitleOptional => 'Başlık (isteğe bağlı)';
  @override
  String get linkInvalid => 'Bu adres açılamaz. "youtube.com/…" ya da "https://…" gibi bir adres yaz.';
  @override
  String get attachmentPhoto => 'Fotoğraf';
  @override
  String get attachmentVideo => 'Video';
  @override
  String get attachmentDocument => 'Belge';
  @override
  String get attachmentName => 'Ekin adı';
  @override
  String attachmentTooLarge(String names) => '$names çok büyük: bir ek en fazla 500 MB olabilir.';
  @override
  String get attachmentFailed => 'Dosya eklenemedi.';
  @override
  String get attachmentNotHere =>
      'Bu dosya henüz bu cihaza gelmedi. Ekleyen cihazla aynı ağda olunca kendiliğinden iner.';
  @override
  String get attachmentNotHereShort => 'henüz inmedi';
  @override
  String attachmentDownloading(int percent) => 'iniyor, %$percent';
  @override
  String get noAppToOpen => 'Telefonda bu dosyayı açacak bir uygulama yok.';
  @override
  String get cannotOpenLink => 'Bağlantı açılamadı.';
  @override
  String get renameAttachment => 'Adını değiştir';
  @override
  String get removeAttachment => 'Eki kaldır';
  @override
  String get shareAttachment => 'Paylaş';
  @override
  String get copyLink => 'Adresi kopyala';
  @override
  String get linkCopied => 'Adres kopyalandı.';
  @override
  String attachmentCount(int n) => '$n ek';
  @override
  String attachmentsAdded(int n) => n == 1 ? 'Ek eklendi.' : '$n ek eklendi.';
  @override
  String get attachmentLimit => 'Bir kayda en fazla 40 ek eklenebilir.';
  @override
  String fileSize(int bytes) => _fileSize(bytes, ',');
  @override
  String get storageTitle => 'Fotoğraflar ve ekler';
  @override
  String get storageMeasuring => 'Hesaplanıyor…';
  @override
  String storageSummary(int photos, int files) => '$photos fotoğraf · $files ek dosyası';
  @override
  String get storagePhotos => 'Fotoğraflar';
  @override
  String get storageFiles => 'Ek dosyaları';
  @override
  String storageCount(int n) => '$n dosya';
  @override
  String get storageLargest => 'En büyük ekler';
  @override
  String get storageNote =>
      'Bu envanterin bu cihazda kapladığı yer; yedek dosyası da yaklaşık bu kadar olur. Yer açmak için büyük bir eki '
      'kaydın düzenleyicisinden kaldır: çöp kutusu ve "Son silinenler" boşalana dek dosyası durur.';
  @override
  String get storageNoFiles => 'Henüz dosya eki yok. Kayıtlara belge, fotoğraf ya da video eklenince burada görünür.';
  @override
  String get storageInTrash => 'çöp kutusunda';
  @override
  String get noResultHint =>
      'Daha kısa ya da başka bir kelime dene: ad, not, konum ve ek adlarında aranır. Çöp kutusundakiler çıkmaz.';
  @override
  String get trashEmptyHint =>
      'Çöpe attığın kayıtlar burada bekler: geri alabilir ya da kalıcı silebilirsin. Kalıcı silinenler 30 gün '
      '"Son silinenler"de durur; istersen beklemeden tamamen de silebilirsin.';
  @override
  String get quickMove => 'Taşı';
  @override
  String get quickFavorite => 'Sık kullanılan';
  @override
  String get quickShop => 'Listeye ekle';
  @override
  String get quickShopOn => 'Listede';
  @override
  String todayExpired(int n) => '$n tarihi geçti';
  @override
  String todaySoon(int n) => '$n tarihi yaklaşıyor';
  @override
  String todayToBuy(int n) => '$n alınacak';
  @override
  String todayToPutAway(int n) => '$n yerleştirilecek';
  @override
  String todayLost(int n) => '$n kayıp';
  @override
  String todayInDrawer(int n) => '$n çekmecede';
  @override
  String get settingsMine => 'Bana ait';
  @override
  String get settingsInventory => 'Bu envanter';
  @override
  String get moreFields => 'Daha fazlası';
  @override
  String get sortTitle => 'Sırala';
  @override
  String get sortManual => 'Benim sıram';
  @override
  String get sortName => 'Ada göre (A–Z)';
  @override
  String get sortNewest => 'Son eklenen üstte';
  @override
  String get sortExpiry => 'Tarihi en yakın üstte';
  @override
  String sortedNoManual(String mode) => '"$mode" sıralıyken kartlar elle dizilmez.';
  @override
  String get viewTitle => 'Görünüm';
  @override
  String get viewHint =>
      'Deste: üst üste kartlar. Liste: sık satırlar, ekrana daha çok kayıt sığar. Izgara: fotoğraflar öne çıkar. '
      'Arama çubuğunun yanındaki düğme de sırayla bunlar arasında geçer.';
  @override
  String get viewDeck => 'Deste';
  @override
  String get viewList => 'Liste';
  @override
  String get viewGrid => 'Izgara';
  @override
  String showAs(String view) => '$view olarak göster';
  @override
  String get syncClosedTitle => 'Kapalı envanterleri de eşitle';
  @override
  String get syncClosedHint =>
      'Paylaştığın envanterler açık olmasalar da arka planda eşitlenir (Wi-Fi\'de, uygulama önde değilken).';
  @override
  String pendingInInventory(int count) => '$count değişiklik onay bekliyor';
  @override
  String get notifyPendingTitle => 'Onay bekleyenleri bildir';
  @override
  String get notifyPendingHint =>
      'Uygulama önde değilken onay bekleyen yeni bir değişiklik gelirse telefon bildirimi gösterilir.';
  @override
  String get pendingChannel => 'Onay bekleyen değişiklikler';
  @override
  String get pendingChannelHint => 'Ortak kullanımda başkalarının yaptığı, onayını bekleyen değişiklikler';
  @override
  String get pendingNoticeTitle => 'Onay bekleyen değişiklikler var';

  // Envanterler arası aktarma / kopyalama
  @override
  String get transferToOtherInventory => 'Başka envantere aktar';
  @override
  String get transferOrCopyTitle => 'Envanterler arası aktar';
  @override
  String get transferAction => 'Taşı';
  @override
  String get copyAction => 'Kopyala';
  @override
  String get selectTargetInventory => 'Hedef envanteri seç';
  @override
  String get cannotTransferToSame => 'Hedef envanter açık olanla aynı olamaz';
  @override
  String transferredTo(String name, String inventory) => '$name $inventory envanterine taşındı';
  @override
  String copiedTo(String name, String inventory) => '$name $inventory envanterine kopyalandı';
  @override
  String transferredMany(int n, String inventory) => '$n kayıt $inventory envanterine taşındı';
  @override
  String copiedMany(int n, String inventory) => '$n kayıt $inventory envanterine kopyalandı';

  // Periyodik bakım döngüsü
  @override
  String get maintenanceDone => 'Bakım yapıldı';
  @override
  String maintained(String name) => '$name için bakım kaydedildi';
  @override
  String maintainedWithNext(String name, String nextDate) => '$name için bakım yapıldı · Sonraki: $nextDate';
  @override
  String get serviceCycle => 'Bakım döngüsü';
  @override
  String get serviceCycleHint => 'Periyodik bakım ve servis süresi (örn. 6 ay, 1 yıl)';
  @override
  String get serviceSection => 'Bakım';
  // "3 ayda bir", "haftada bir", "2 yılda bir".
  @override
  String serviceEveryText(TimeSpan span) {
    final unit = switch (span.unit) {
      SpanUnit.day => 'günde',
      SpanUnit.week => 'haftada',
      SpanUnit.month => 'ayda',
      SpanUnit.year => 'yılda',
    };
    return span.amount == 1 ? '$unit bir' : '${span.amount} $unit bir';
  }
  @override
  String get serviceTaskTitle => 'Ne yapılacak';
  @override
  String get serviceTaskHint => 'Örn. yağla, filtreyi değiştir, servise götür';
  @override
  String get lastService => 'Son bakım';
  @override
  String nextServiceOn(String date) => 'Sonraki bakım: $date';
  @override
  String get serviceNeedsLast => 'Sonraki bakımın hesaplanması için son bakımın gününü gir';
  @override
  String get serviceHistory => 'Bakım geçmişi';
  @override
  String get serviceHistoryEmpty => 'Henüz kayıt yok: "Bakım yapıldı" ya da "Kayıt ekle" ile girer.';
  @override
  String get serviceAddEntry => 'Kayıt ekle';
  @override
  String get serviceEntryNote => 'Not';
  @override
  String get serviceEntryNoteHint => 'Ne yapıldı, kim yaptı, ne tuttu (isteğe bağlı)';
  @override
  String serviceShowAll(int n) => 'Tümünü göster ($n)';
  @override
  String get serviceRemoveEntry => 'Kaydı sil';
  @override
  String get serviceDueToday => 'bakım günü bugün';
  @override
  String serviceLate(int days) => 'bakım $days gün gecikti';
  @override
  String get serviceDueSection => 'Bakım zamanı';
  @override
  String get serviceScheduleSection => 'Bakım takvimi';
  @override
  String todayService(int n) => '$n bakım zamanı';
  @override
  String notifyService(String? task) => task == null ? 'Bakım zamanı' : 'Bakım zamanı: $task';
  @override
  String get fieldService => 'bakım';
  @override
  String fieldServiced(String date) => 'bakım yapıldı ($date)';

  // Arama filtre çipleri
  @override
  String get allFilter => 'Tümü';
  @override
  String get foldersOnly => 'Klasörler';
  @override
  String get itemsOnly => 'Eşyalar';
  @override
  String get withDatesOnly => 'Tarihliler';
  @override
  String get withPhotosOnly => 'Fotoğraflılar';
  @override
  String get outOfStockOnly => 'Tükenenler';
  @override
  String get withAttachmentsOnly => 'Ekleri olanlar';

  // Koli ve içerik dökümü
  @override
  String get exportContent => 'İçerik dökümü';
  @override
  String get exportPdfList => 'PDF olarak paylaş (yazdır)';
  @override
  String get exportCsvList => 'CSV tablosu olarak paylaş';
  @override
  String get boxContentList => 'Koli ve içerik dökümü';
  @override
  String get itemIndexCol => 'No';
  @override
  String get itemNameCol => 'Kayıt / eşya adı';
  @override
  String get itemQuantityCol => 'Adet / miktar';
  @override
  String get itemLocationCol => 'Konum / yer';
  @override
  String get itemNoteCol => 'Not / durum';
  @override
  String get itemBarcodeCol => 'Barkod';

  // Ölçü birimi desteği
  @override
  String get unit => 'Birim';
  @override
  String get unitHint => 'Adet, paket, kg, metre...';
  @override
  String get unitPiece => 'adet';
  @override
  String get unitPackage => 'paket';
  @override
  String get unitKg => 'kg';
  @override
  String get unitGram => 'g';
  @override
  String get unitMeter => 'm';
  @override
  String get unitCm => 'cm';
  @override
  String get unitLiter => 'lt';
  @override
  String get unitBox => 'kutu';
  @override
  String get unitPair => 'çift';
  @override
  String get unitRoll => 'rulo';
  @override
  String get customUnit => 'Başka bir birim yaz';

  // Seri barkod / QR sayım modu
  @override
  String get serialScanMode => 'Seri sayım modu';
  @override
  String get serialScanHint => 'Barkodları art arda okut; adetler anında güncellenir';
  @override
  String stockCounted(String name, int quantity) => '$name sayıldı · Yeni adet: $quantity';
  @override
  String get unknownBarcodeScan => 'Barkod kayıtlı değil';
  @override
  String serialFolderSkipped(String name) => '$name bir klasör: adedi sayılmaz';
  @override
  String get scanBatchFinished => 'Sayım tamamlandı';

  // Emanet & Ödünç Takibi
  @override
  String get borrowedPageTitle => 'Emanettekiler';
  @override
  String get borrowAction => 'Emanet ver';
  @override
  String get borrowDetailsTitle => 'Emanet bilgisi';
  @override
  String get borrower => 'Kime verildi';
  @override
  String get borrowerHint => 'Örn. Ahmet Yılmaz';
  @override
  String get borrowedAt => 'Verilme tarihi';
  @override
  String get returnDueDate => 'Beklenen iade tarihi';
  @override
  String get noReturnDueDate => 'İade tarihi belirtilmedi';
  @override
  String get markReturned => 'Geri alındı';
  @override
  String borrowedToStamp(String name) => locative(name);
  @override
  String get borrowOverdueShort => 'Gecikti';
  @override
  String todayOverdueBorrow(int n) => '$n emanet gecikti';
  @override
  String todayBorrowed(int n) => '$n emanette';
  @override
  String fieldBorrowed(String name) => 'Emanet verildi: $name';
  @override
  String get fieldReturned => 'Emanetten geri alındı';
  @override
  String get filterBorrowed => 'Emanettekiler';
  @override
  String get noBorrowedItems => 'Emanette eşya yok';
  @override
  String get noBorrowedHint => 'Başkalarına ödünç verdiğin eşyaları buradan takip edebilirsin.';
  @override
  String get overdueSection => 'Gecikenler';
  @override
  String get activeBorrowSection => 'Emanette olanlar';
  @override
  String borrowSuccess(String item, String to) => '$item, $to kişisine emanet verildi';
  @override
  String returnSuccess(String item) => '$item geri alındı';
  @override
  String get pickReturnDate => 'İade tarihi seç';
  @override
  String get inOneWeek => '1 hafta sonra';
  @override
  String get inTwoWeeks => '2 hafta sonra';
  @override
  String get inOneMonth => '1 ay sonra';
  @override
  String get clearDate => 'Tarihi kaldır';
  @override
  String get quickBorrow => 'Emanet';
  @override
  String get borrowerRequired => 'Kişinin adını yaz';

  @override
  String get auditInventory => 'Sayım / denetim';
  @override
  String get auditFolder => 'Sayım / denetim';
  @override
  String get auditScopePrompt => 'Nerede sayım yapılacak?';
  @override
  String get auditPickFolder => 'Hangi klasör sayılsın?';
  @override
  String get auditCountHere => 'Burayı say';
  @override
  String get auditEntireInventory => 'Tüm envanter';
  @override
  String get auditThisFolder => 'Yalnızca bu klasör';
  @override
  String get auditIncludeSubfolders => 'Alt klasörler dahil';
  @override
  String get startAudit => 'Sayımı başlat';
  @override
  String get auditProgress => 'Sayım ilerlemesi';
  @override
  String auditItemProgress(int counted, int total) => '$counted / $total sayıldı';
  @override
  String get auditFilterAll => 'Tümü';
  @override
  String get auditFilterPending => 'Bekleyenler';
  @override
  String get auditFilterVerified => 'Doğrulananlar';
  @override
  String get auditFilterDiscrepancy => 'Farklı / eksik';
  @override
  String get auditFilterUnexpected => 'Beklenmeyenler';
  @override
  String get verifyAction => 'Doğrula';
  @override
  String get markMissingAction => 'Bulunamadı';
  @override
  String get resetCountAction => 'Sıfırla';
  @override
  String expectedQuantity(int count, [String? unit]) => 'Beklenen: $count${unit != null ? " $unit" : ""}';
  @override
  String countedQuantity(int count, [String? unit]) => 'Sayılan: $count${unit != null ? " $unit" : ""}';
  @override
  String get finishAudit => 'Sayımı tamamla';
  @override
  String get finishAuditShort => 'Tamamla';
  @override
  String get auditSummaryTitle => 'Sayım ve mutabakat özeti';
  @override
  String auditVerifiedSummary(int n) => '$n kayıt doğrulandı ve eksiksiz.';
  @override
  String auditDiscrepancySummary(int n) => '$n kayıtta adet farkı var.';
  @override
  String auditMissingSummary(int n) => '$n kayıt bulunamadı.';
  @override
  String auditUnexpectedSummary(int n) => '$n beklenmeyen eşya burada bulundu.';
  @override
  String get auditApplyQuantityChanges => 'Adet farklarını kayıtlara güncelle';
  @override
  String get auditMarkMissingAsLost => 'Bulunamayanları "Kayıp" olarak işaretle';
  @override
  String get auditAddMissingToShopping => 'Bulunamayanları alışveriş listesine ekle';
  @override
  String get auditMoveMissingToDrawer => 'Bulunamayanları çekmeceye taşı';
  @override
  String get auditMoveFoundHere => 'Başka yerden bulunanları bu klasöre taşı';
  @override
  String get auditApplyAndFinish => 'Mutabakatı uygula ve bitir';
  @override
  String get auditCompletedNotice => 'Sayım başarıyla tamamlandı ve kayıtlar güncellendi.';
  @override
  String get auditEmptyScope => 'Bu klasörde sayılacak eşya bulunmuyor.';
  @override
  String get auditScanBarcodePrompt => 'Barkod okutarak hızlı sayım yapabilirsin.';
  @override
  String auditItemCountedSuccess(String name, int count) => '$name sayıldı ($count)';
  @override
  String auditItemFoundOtherFolder(String name, String folder) => '$name normalde "$folder" klasöründe; buraya eklendi.';
  @override
  String get auditNoChanges => 'Herhangi bir fark bulunmadı, her şey eksiksiz.';
  @override
  String get auditMarkMissingActionLabel => 'Bulunamayan eşyalar ne yapılsın?';
  @override
  String get auditMissingDoNothing => 'Değişiklik yapma (yerinde kalsın)';

  @override
  String money(Money m) => m.format(turkish: true);
  @override
  String moneyTotals(MoneyTotals t) => t.format(turkish: true);
  @override
  String get fieldPrice => 'fiyat';
  @override
  String get fieldSerial => 'seri no';
  @override
  String get valueSection => 'Değer';
  @override
  String get priceTitle => 'Fiyatı';
  @override
  String get priceHint => 'Bir tanesinin alış bedeli ya da biçtiğin değer; sigorta ve taşınma dökümünde toplanır.';
  @override
  String priceEach(String price) => '$price / tanesi';
  @override
  String valueTimes(int count, String price, String total) => '$count × $price = $total';
  @override
  String get priceInvalid => 'Tutar anlaşılmadı; örneğin 1250 ya da 1.250,50 yaz.';
  @override
  String get currency => 'Para birimi';
  @override
  String get currencyHint => 'Yeni fiyatlar bu birimle başlar. Farklı birimler ayrı toplanır, kur çevrimi yapılmaz.';
  @override
  String get otherCurrency => 'Başka bir birim';
  @override
  String get currencyCodeHint => 'Üç harfli kod, örneğin GBP';
  @override
  String get serialTitle => 'Seri / model no';
  @override
  String get serialHint => 'Cihazın etiketinden ya da faturadan; sigorta ve garanti başvurusunda istenir.';
  @override
  String get serialCopied => 'Seri no kopyalandı';
  @override
  String contentsValue(String value) => 'İçindekilerin değeri: $value';
  @override
  String itemValue(String value) => 'Değeri: $value';
  @override
  String get valuePageTitle => 'Değer';
  @override
  String get totalValue => 'Toplam değer';
  @override
  String get valueByPlace => 'Yerlere göre';
  @override
  String get mostValuable => 'En değerliler';
  @override
  String unpricedItems(int n) => '$n eşyanın fiyatı yok';
  @override
  String get unpricedHint => 'Döküm eksik kalmasın: dokun, fiyatı olmayanları gör.';
  @override
  String get noValueYet => 'Henüz fiyatı girilmiş eşya yok';
  @override
  String get noValueHint =>
      'Eşyayı düzenlerken "Daha fazlası" → Değer ile fiyatını yaz. Burada klasör klasör toplanır; sigorta ve '
      'taşınma için döküm alınır.';
  @override
  String get currenciesSeparate => 'Farklı para birimleri ayrı toplanır; kur çevrimi yapılmaz.';
  @override
  String get valueReport => 'Değer dökümü (PDF)';
  @override
  String get valueReportTitle => 'Değer dökümü';
  @override
  String get valueReportHint => 'Sigorta ve taşınma için: eşyalar, yerleri, seri numaraları, tutarlar';
  @override
  String get colUnitPrice => 'Birim fiyat';
  @override
  String get colAmount => 'Tutar';
  @override
  String get colSerial => 'Seri no';
  @override
  String get colPurchased => 'Alış';
  @override
  String reportDate(String date) => 'Hazırlanma: $date';
  @override
  String reportCounts(int priced, int unpriced) =>
      unpriced == 0 ? '$priced eşya' : '$priced eşya · $unpriced eşyanın fiyatı yok';
  @override
  String get subtotal => 'Ara toplam';
  @override
  String get grandTotal => 'Genel toplam';
  @override
  String get unpricedSection => 'Fiyatı olmayanlar';

  @override
  String get burstAdd => 'Seri ekle';
  @override
  String get burstAddHint => 'Art arda çek ya da galeriden toplu seç; her fotoğraf bir eşya olur';
  @override
  String get burstCameraHint => 'Kamera açık kalır; sonra yalnızca adlarını yazarsın';
  @override
  String get burstGalleryHint => 'Birden çok fotoğraf seç; her biri fotoğrafın adıyla bir eşya olur';
  @override
  String get burstMoreFromGallery => 'Galeriden ekle';
  @override
  String burstImporting(int done, int total) => 'Fotoğraflar alınıyor: $done / $total';
  @override
  String burstImportFailed(int n) => '$n fotoğraf alınamadı';
  @override
  String burstPreparing(int done, int total) => 'Hazırlanıyor: $done / $total';
  @override
  String burstShots(int n) => '$n fotoğraf';
  @override
  String get burstDone => 'Bitti';
  @override
  String get burstTakeMore => 'Daha çek';
  @override
  String burstAddItems(int n) => '$n eşyayı ekle';
  @override
  String get burstNameHint => 'Adı (boş kalırsa Adsız)';
  @override
  String burstAdded(int n, String place) => '$n eşya eklendi: $place';
  @override
  String burstDiscardQuestion(int n) => 'Çekilen $n fotoğraf silinsin mi?';
  @override
  String get burstDiscard => 'Sil ve çık';
  @override
  String get burstKeep => 'Devam et';
  @override
  String get burstCameraFailed => 'Kamera açılamadı. İzni ya da başka bir uygulamanın kamerayı kullanıp kullanmadığını kontrol et.';
  @override
  String get burstEmpty => 'Eşyayı kadraja al ve düğmeye dokun; kamera açık kalır.';
  @override
  String get burstSaving => 'Ekleniyor…';
  @override
  String burstTarget(String place) => 'Nereye: $place';
  @override
  String get burstRemoveShot => 'Bu fotoğrafı çıkar';
}

class EnStrings extends AppStrings {
  const EnStrings();

  @override
  Locale get locale => const Locale('en');

  @override
  String upper(String text) => text.toUpperCase();

  @override
  String get appTitle => 'Inventory';
  @override
  String get home => 'Home';
  @override
  String get drawer => 'Drawer';
  @override
  String get container => 'Folder';
  @override
  String get item => 'Item';
  @override
  String get unnamed => 'Unnamed';
  @override
  String get empty => 'empty';
  @override
  String recordCount(int n) => n == 1 ? '1 record' : '$n records';
  @override
  String get back => 'Back';
  @override
  String get backHoldHint => 'go to the home screen';
  @override
  String get parentFolders => 'Go to a parent folder';
  @override
  String get otherFolder => 'Go to another folder…';
  @override
  String get whichFolderToGo => 'Which folder to go to?';
  @override
  String get goHere => 'Go here';
  @override
  String get youAreHere => 'You\'re here';
  @override
  String get cancel => 'Cancel';
  @override
  String get save => 'Save';
  @override
  String get delete => 'Delete';
  @override
  String get undo => 'Undo';
  @override
  String get close => 'Close';
  @override
  String get edit => 'Edit';
  @override
  String get qrCode => 'QR code';
  @override
  String get menu => 'Menu';
  @override
  String get search => 'Search';
  @override
  String get newRecord => 'New record';
  @override
  String get clear => 'Clear';

  @override
  String get nothingYet => 'Nothing yet';
  @override
  String itemsAtRoot(int n) => n == 1 ? '1 folder/item' : '$n folders/items';
  @override
  String get createFirstContainer => 'Create your first folder';
  @override
  String get createFirstContainerHint =>
      'A cupboard, a box, a shelf... it can hold items and other folders.';
  @override
  String get addFirstItem => 'Add the first item';
  @override
  String get addFirstItemHint =>
      'Put an item inside, or use the box icon to create a folder.';
  @override
  String get addInside => 'New record inside';

  @override
  String get addItem => 'Add item';
  @override
  String get addItemSubtitle => 'A single object';
  @override
  String get addContainer => 'Add folder';
  @override
  String get addContainerSubtitle => 'Holds items and other folders';

  @override
  String get newContainer => 'New folder';
  @override
  String get newItem => 'New item';
  @override
  String get editRecord => 'Edit';
  @override
  String get name => 'Name';
  @override
  String get itemNameHint => 'e.g. screwdriver set';
  @override
  String get photo => 'Photo';
  @override
  String get takePhoto => 'Take a photo';
  @override
  String get pickFromGallery => 'Pick from gallery';
  @override
  String get removePhoto => 'Remove photo';
  @override
  String get replacePhoto => 'Replace photo';
  @override
  String get photoFailed => 'Could not get the image. Check permissions.';
  @override
  String get cardColor => 'Card colour';
  @override
  String get location => 'Location';
  @override
  String get containerHasChildren =>
      'A folder with records inside cannot become an item.';
  @override
  String get noteOptional => 'Note (optional)';

  @override
  String get physicalLocation => 'Physical location';
  @override
  String get physicalLocationHint =>
      'Where this record sits in the world. Capture it or type it in.';
  @override
  String get autoLocate => 'Get current location';
  @override
  String get locating => 'Getting location...';
  @override
  String get locationName => 'Location name';
  @override
  String get locationNameHint => 'e.g. garage, cabin, storage';
  @override
  String get latitude => 'Latitude';
  @override
  String get longitude => 'Longitude';
  @override
  String get invalidCoordinates => 'Those coordinates are not valid.';
  @override
  String get locationFailed => 'Could not get the location.';
  @override
  String get locationServiceOff => 'Location services are turned off.';
  @override
  String get locationDenied => 'Location permission was not granted.';
  @override
  String get locationDeniedForever =>
      'Location permission is permanently denied. You can enable it in settings.';

  @override
  String get changePlacement => 'Change placement';
  @override
  String get moveToTrash => 'Move to trash';

  @override
  String whereShouldGo(String name) => 'Where should "$name" go?';
  @override
  String currentlyAt(String path) => 'Currently: $path';
  @override
  String get currentPlace => 'current place';
  @override
  String get drawerWithHint => 'Drawer (placement unknown)';
  @override
  String movedTo(String name, String path) => '"$name" moved to $path';
  @override
  String get moveNotPossible => 'That move is not possible.';
  @override
  String get cannotMoveIntoItself => 'A folder cannot go inside itself.';
  @override
  String movedInto(String name, String target) => '"$name" → "$target"';
  @override
  String get dropHere => 'Drop';
  @override
  String get intoHome => 'on the home screen';
  @override
  String get intoDrawer => 'in the drawer';
  @override
  String intoContainer(String name) => 'into "$name"';
  @override
  String movedToDrawer(String name) => '"$name" moved to the drawer';

  @override
  String get shareAsImage => 'Share as image';
  @override
  String get preparing => 'Preparing...';
  @override
  String get qrHint => 'This code belongs to this record; print it and stick it on the box.';
  @override
  String get scanQr => 'Scan QR';
  @override
  String get scanQrHint =>
      'A folder code opens it; an item code brings its card forward. Product barcodes work too: the saved item is found.';
  @override
  String get qrNotRecognized => 'This code does not belong to this inventory.';
  @override
  String get barcode => 'Barcode';
  @override
  String get barcodeHint => 'The barcode on the product: scanning it finds this item.';
  @override
  String get containerBarcodeHint => 'The barcode on the folder or box: scanning it opens this folder.';
  @override
  String get scanBarcode => 'Scan barcode';
  @override
  String get scanBarcodeHint => 'Point at the barcode on the product.';
  @override
  String get barcodeUnknown => 'This barcode is not saved';
  @override
  String get barcodeUnknownBody =>
      'You can add it as a new item. To link it to an existing item: edit the item → More → Barcode.';
  @override
  String get newItemWithBarcode => 'New item with this barcode';
  @override
  String get newContainerWithBarcode => 'New folder with this barcode';
  @override
  String barcodeMatches(int count) => '$count records have this barcode';
  @override
  String barcodeAlsoOn(String name) => '"$name" has this barcode too.';
  @override
  String get fieldBarcode => 'barcode';
  @override
  String get qrRecordMissing => 'The record behind this code is gone; it may be deleted.';
  @override
  String get cameraPermissionNeeded => 'Camera permission is required.';

  @override
  String get visualSearch => 'Search by photo';
  @override
  String get visualSearchHint =>
      'Photograph the object in your hand and I will compare it with the photos in your inventory.';
  @override
  String get visualSearchRunning => 'Scanning the inventory...';
  @override
  String get visualSearchNoMatch => 'Nothing in the inventory looks close enough to this.';
  @override
  String get visualSearchNoImages =>
      'There are no photos to compare against. Add photos to your cards first.';
  @override
  String get visualSearchTake => 'Take a photo';
  @override
  String get visualSearchFromGallery => 'Pick from gallery';
  @override
  String get visualSearchOpening => 'Opening the camera…';
  @override
  String get cameraBusy => 'The camera could not start. Another app may be using it.';
  @override
  String get retry => 'Try again';
  @override
  String visualSearchResult(int n) => n == 1 ? '1 possible match' : '$n possible matches';
  @override
  String similarity(int percent) => '$percent% similar';
  @override
  String get searchAgain => 'Take another';

  @override
  String get searchHint => 'Search by name...';
  @override
  String get searchInInventory => 'Search the inventory';
  @override
  String get searchInInventoryHint =>
      'Type a word from a name, a location or a note. Or scan a QR code, or search by photo.';
  @override
  String noResultFor(String query) => 'Nothing found for "$query".';
  @override
  String get goToPlace => 'Go to its place';

  @override
  String get drawerSubtitle => 'Things without a place wait here';
  @override
  String drawerWaiting(int n) =>
      n == 1 ? '1 record waiting for a place' : '$n records waiting for a place';
  @override
  String get drawerEmpty => 'The drawer is empty';
  @override
  String get drawerEmptyHint =>
      'Hold a card and drag it to the right edge to drop it here. '
      'You can decide where it belongs later.';
  @override
  String get newRecordToDrawer => 'New record in the drawer';

  @override
  String get trash => 'Trash';
  @override
  String get emptyTrash => 'Empty';
  @override
  String get emptyTrashQuestion => 'Empty the trash?';
  @override
  String get emptyTrashWarning =>
      'These records and everything inside them leave the trash. If it was a mistake, you can bring them back '
      'from "Recently deleted" within 30 days.';
  @override
  String get trashEmpty => 'The trash is empty';
  @override
  String insideCount(int n) => n == 1 ? '1 record inside' : '$n records inside';
  @override
  String get singleRecord => 'Single record';
  @override
  String get deleteForever => 'Delete for good';
  @override
  String deleteForeverQuestion(String name) => 'Delete "$name" for good?';
  @override
  String deleteForeverWarning(int n) =>
      n == 1 ? 'The 1 record inside goes too. It can be brought back from "Recently deleted" within 30 days.'
             : 'The $n records inside go too. They can be brought back from "Recently deleted" within 30 days.';
  @override
  String get purgeRecoverable => 'It can be brought back from "Recently deleted" within 30 days.';
  @override
  String get recentlyPurged => 'Recently deleted';
  @override
  String get recentlyPurgedHint =>
      'Records deleted for good stay here for 30 days. A restored record also comes back for the others if shared.';
  @override
  String get deleteNowOption => "Don't wait 30 days, delete completely now";
  @override
  String get deleteNowWarning =>
      'Removed from this phone right away with its photos and attachments, freeing space. It cannot be brought back.';
  @override
  String get deleteNow => 'Delete completely';
  @override
  String deleteNowQuestion(String name) => 'Delete "$name" completely?';
  @override
  String get clearPurged => 'Clear';
  @override
  String get clearPurgedQuestion => 'Clear recently deleted?';
  @override
  String clearPurgedWarning(int n) => n == 1
      ? 'The 1 record here is removed from this phone right away with its photos and attachments. '
          'It cannot be brought back.'
      : 'The $n records here are removed from this phone right away with their photos and attachments. '
          'They cannot be brought back.';
  @override
  String trashedWithChildren(String name, int n) =>
      n == 1 ? '"$name" and 1 record inside are in the trash'
             : '"$name" and $n records inside are in the trash';
  @override
  String trashedSingle(String name) => '"$name" is in the trash';

  @override
  String get sharing => 'Sharing';
  @override
  String get sharingNeedsNameTitle => 'How should you appear?';
  @override
  String get sharingNeedsNameHint => 'Your name shows in join requests and the member list.';
  @override
  String get inventoryNameLabel => 'Inventory name';
  @override
  String get inventories => 'Inventories';
  @override
  String get deckSection => 'Deck';
  @override
  String thisInventoryTitle(String name) => 'This inventory: $name';
  @override
  String get thisInventoryHint =>
      'The settings below belong to this inventory only. Each inventory has its own deck layout, date '
      'warning, notifications and sharing (with whom, approval or automatic).';
  @override
  String get inventoriesHint =>
      'Each inventory has its own records, photos and sharing. One is open at a time; the other '
      'shared ones sync in the background or when you open them.';
  @override
  String get newInventory => 'New inventory';
  @override
  String get newInventoryHint => 'Opens an empty inventory; it stays separate and can be shared on its own.';
  @override
  String get create => 'Create';
  @override
  String get switchInventory => 'Switch inventory';
  @override
  String get menuFavorites => 'Favorites';
  @override
  String get menuExpired => 'Expired';
  @override
  String get openNow => 'Open';
  @override
  String lastOpened(String when) => 'last opened $when';
  @override
  String get renameInventory => 'Rename';
  @override
  String get inventoryLook => 'Colour and emblem';
  @override
  String get inventoryLookHint => 'Shown in the header, the menu and the inventory list. On this device only.';
  @override
  String get lookColor => 'Colour';
  @override
  String get lookEmblem => 'Emblem';
  @override
  String get lookNoColor => 'No colour';
  @override
  String deleteInventoryQuestion(String name) => 'Delete "$name"?';
  @override
  String deleteInventoryBody(int count) =>
      'The inventory and its $count records move to Deleted together with their photos. You can bring it '
      'back within 30 days; after that it is deleted for good.';
  @override
  String get deleteSharedNote =>
      'This inventory is shared: the others are told you deleted it, and their copies stay. If you manage '
      'it, you first choose who manages it after you.';
  @override
  String get deleteSharedClosedNote => 'This inventory is shared: it opens first so the others can be told.';
  @override
  String unopenedCopy(String name) => '$name (copy that would not open)';
  @override
  String get deletedInventories => 'Deleted';
  @override
  String get deletedInventoriesHint => 'Deleted inventories stay here for 30 days, then they are deleted for good.';
  @override
  String get restoreInventory => 'Restore';
  @override
  String get purgeInventory => 'Delete for good';
  @override
  String purgeInventoryQuestion(String name) => 'Delete "$name" for good?';
  @override
  String get purgeInventoryBody => 'Its records and photos are removed from this device; this can\'t be undone.';
  @override
  String inventoryDeleted(String name) => '"$name" moved to Deleted.';
  @override
  String lastBackupOn(String when) => 'last backup $when';
  @override
  String get noBackup => 'no backup';
  @override
  String unbackedInventories(int count) =>
      count == 1 ? '1 inventory has no current backup.' : '$count inventories have no current backup.';
  @override
  String get backingUp => 'Backing up…';
  @override
  String backingUpAll(int done, int total) => 'Backing up inventories ($done/$total)…';
  @override
  String get backupSection => 'Backup';
  @override
  String get recoveryTitle => 'The inventory could not be opened';
  @override
  String recoveryBody(String name) =>
      'The database of "$name" could not be opened; the damaged file was moved to Deleted as a separate copy '
      'and the inventory opened empty. If you have a backup, import it to restore.';
  @override
  String get backupOfferTitle => 'Set up a backup?';
  @override
  String backupOfferBody(int count) =>
      'Your inventory has $count records. There is no server, so if the phone is lost or breaks, all of it '
      'is gone. Choose a folder that syncs to the cloud and all your inventories are backed up there weekly.';
  @override
  String get chooseFolder => 'Choose folder';
  @override
  String get notNow => 'Not now';
  @override
  String get inventoryNameHint => 'e.g. Home, Workshop, Library';
  @override
  String get members => 'Members';
  @override
  String get thisDevice => 'this device';
  @override
  String get online => 'on the network';
  @override
  String get offline => 'not on the network';
  @override
  String lastSynced(String when) => 'Last synced: $when';
  @override
  String syncedAgo(String when) => 'last synced $when';
  @override
  String rejectedNotice(String who, String name, String kind) => switch (kind) {
        'added' => '$who turned down “$name”, which you added.',
        'deleted' => '$who turned down your deleting “$name”.',
        'trashed' => '$who turned down your moving “$name” to the trash.',
        'moved' => '$who turned down your moving “$name”.',
        _ => '$who turned down your change to “$name”.',
      };
  @override
  String rejectedNoticeMany(String who, int n) => '$who turned down $n of your changes.';
  @override
  String switchedTo(String inventory) => 'Switched to “$inventory”.';
  @override
  String inOtherInventories(int n) => 'In other inventories: $n';
  @override
  String notSearchedYet(String names) => '$names can\'t be searched yet: open and close it once.';
  @override
  String get otherListsSection => 'Other inventories';
  @override
  String get otherListsHint => 'Tapping switches to that inventory and opens its list.';
  @override
  String get otherDatesSection => 'Expiring in other inventories';
  @override
  String get otherDatesHint => 'Tapping switches to that inventory and opens its dates.';
  @override
  String get openContainer => 'Open folder';
  @override
  String get discardChangesQuestion => 'Discard changes?';
  @override
  String get discardChangesAction => 'Discard';
  @override
  String get keepEditing => 'Keep editing';
  @override
  String get rotateTitle => 'Rotate the screen';
  @override
  String get openPhoto => 'Open photo';
  @override
  String get rotateHint =>
      'When on, follows the phone\'s auto-rotate setting: turned sideways, the app switches to its landscape '
      'layout. When off, it stays upright on phones; tablets still rotate.';
  @override
  String inCart(String name) => '$name bought; enter the count at home under “To put away”.';
  @override
  String get putAwaySection => 'To put away';
  @override
  String get putAwayHint => 'Ticked off at the store: enter the count and date as you put them away.';
  @override
  String get putAway => 'Put away';
  @override
  String get backToList => 'Back to the list';
  @override
  String boughtWhen(String when) => 'bought $when';
  @override
  String get imBuying => 'I\'m getting it';
  @override
  String get notBuying => 'Not getting it';
  @override
  String get youAreBuying => 'you\'re getting it';
  @override
  String isBuying(String who) => '$who is getting it';
  @override
  String quantityChanged(String name, int from, int to) => '$name: $from → $to';
  @override
  String clockSpan(int minutes) => minutes < 120
      ? '$minutes min'
      : minutes < 2880
          ? '${minutes ~/ 60} h'
          : '${minutes ~/ 1440} days';
  @override
  String clockGap(String span) => 'clocks $span apart';
  @override
  String syncFailed(String reason) => 'Last sync failed: $reason';
  @override
  String get failUnreachable => 'device not reachable';
  @override
  String get failTimeout => 'no response';
  @override
  String get failRejected => 'request rejected; check both phones\' clock and app version';
  @override
  String get failServer => 'error on the other device';
  @override
  String get failOther => 'unexpected error';
  @override
  String clockMineWrong(String who, String span, bool behind) =>
      'This phone\'s clock is $span ${behind ? 'behind' : 'ahead'}; sync corrects it to $who\'s clock. '
      'Turning on automatic date and time in Settings is better.';
  @override
  String clockTheirsWrong(String who, String span, bool ahead) =>
      '$who\'s phone clock is $span ${ahead ? 'ahead' : 'behind'}; sync corrects it on their phone. They '
      'should turn on automatic date and time.';
  @override
  String clockUnknown(String who, String span) =>
      'Your clock and $who\'s are $span apart; changes may merge in the wrong order. Turn on automatic date '
      'and time on the phone that doesn\'t use it.';
  @override
  String get neverSyncedWith => 'not synced yet';
  @override
  String get trustMember => 'Take their changes without asking';
  @override
  String get untrustMember => 'Ask me about their changes';
  @override
  String get trustedTag => 'no asking';
  @override
  String get quickSmallTitle => 'Counts and shopping list without asking';
  @override
  String get quickSmallSubtitle =>
      'Even while approval is on, count changes and shopping-list additions/removals apply right away.';
  @override
  String get neverSynced => 'Not synced yet';
  @override
  String get syncNow => 'Sync now';
  @override
  String get syncing => 'Syncing...';
  @override
  String get inventoriesOnNetwork => 'Inventories on the network';
  @override
  String get noInventoriesOnNetwork =>
      'Sharing must be on at the other end too, and you must be on the same Wi-Fi.';
  @override
  String ownerLabel(String name) => 'Owner: $name';
  @override
  String joinQuestion(String inventory) => 'Send a request to join "$inventory"?';
  @override
  String joinOwnerLine(String owner) => '$owner owns it. If they accept, it comes to this device.';
  @override
  String joinMergeWarning(int n) =>
      n == 1 ? 'Your 1 record will be added to the shared inventory too.'
             : 'Your $n records will be added to the shared inventory too.';
  @override
  String get sendRequest => 'Send request';
  @override
  String get joinAsNew => 'Join as a new inventory';
  @override
  String get joinIntoCurrent => 'Merge with this one';
  @override
  String joinSeparateHint(int n) =>
      'A separate inventory is opened; the $n records here stay apart. If you choose "Merge with this one", '
      'your records are added to the shared inventory.';
  @override
  String waitingForApproval(String owner) => 'Waiting for $owner to accept...';
  @override
  String joinedMessage(String inventory) => 'You joined "$inventory"; syncing.';
  @override
  String get joinRejected => 'The request was not accepted.';
  @override
  String get joinUnreachable => 'Could not reach the device. Are you on the same Wi-Fi?';
  @override
  String get joinTimeout => 'No answer.';
  @override
  String get joinRequestTitle => 'Join request';
  @override
  String joinRequestBody(String name, String inventory) =>
      '$name wants to join "$inventory". If you accept, they can see and edit the whole inventory.';
  @override
  String get reject => 'Reject';
  @override
  String get accept => 'Accept';
  @override
  String get leaveSharing => 'Leave the shared inventory';
  @override
  String get leaveSharingQuestion => 'Leave the shared inventory?';
  @override
  String get leaveSharingBody => 'The records stay on this device but no longer sync.';
  @override
  String get leave => 'Leave';
  @override
  String get sharingLimits =>
      'Syncing works while the devices are on the same Wi-Fi; with the app closed it runs in the '
      'background about every half hour.';
  @override
  String sharingOnline(int n) => n == 0 ? 'Sharing is on' : 'Sharing: $n on the network';

  @override
  String get sharingOffTitle => 'Sharing is off';
  @override
  String get sharingOffBody =>
      'When it is on, people on the same Wi-Fi see your inventory by name and can ask to '
      'join; you can also see and join inventories on the network.';
  @override
  String get turnOnSharing => 'Turn on sharing';
  @override
  String sharingVisibleAs(String name) => 'Visible on the network as "$name"';
  @override
  String sharingJoinedAs(String inventory) => 'You are sharing "$inventory"';
  @override
  String get howItWorks => 'How does it work?';
  @override
  List<String> get howItWorksSteps => const [
        'Everyone turns sharing on on their own phone; the phones must be on the same Wi-Fi.',
        'Whoever wants to join sees the inventory by name under "Inventories on the network" and sends a request.',
        'The inventory\'s owner approves the request; from then on the inventory is used on both phones.',
        'Changes someone makes arrive at the others as a notification on the bell; they apply once approved.',
        'The owner can make members main users, choose an heir or put someone in charge of a folder '
            '(e.g. Kitchen → Ayşe). '
            'Their changes where they are in charge need no approval.',
      ];
  @override
  String get searchingNetwork => 'Looking around the network...';
  @override
  String get joinHint => 'Tap to join; once the owner approves you use it together.';
  @override
  String get join => 'Join';
  @override
  String get owner => 'owner';
  @override
  String get you => 'you';
  @override
  String get noMembersYet =>
      'Nobody has joined yet. Someone on the same network can find your inventory on this page and ask to join.';
  @override
  String get changes => 'Changes';
  @override
  String get autoAcceptTitle => 'Accept changes automatically';
  @override
  String get autoAcceptSubtitle =>
      'When on, changes made by others apply right away without asking; permanent deletions and bulk trashing '
      'are still asked about.';
  @override
  String pendingChanges(int n) =>
      n == 0 ? 'No pending changes' : (n == 1 ? '1 pending change' : '$n pending changes');
  @override
  String get noPendingChanges => 'All caught up';
  @override
  String get noPendingChangesBody => 'Changes made by the people you share with wait here for your approval.';
  @override
  String get changesHint =>
      'Accepted changes are applied on your phone too. If you reject one, your version '
      'stays and is sent to the others as well.';
  @override
  String get acceptAll => 'Accept all';
  @override
  String get rejectAll => 'Reject all';
  @override
  String get rejectAllQuestion => 'Reject all changes?';
  @override
  String get rejectBody =>
      'Your version stays and is sent to the others. Rejected new records go to the trash.';
  @override
  String get someone => 'Someone';
  @override
  String changeAdded(String who) => 'Added by $who';
  @override
  String changeEdited(String who) => 'Edited by $who';
  @override
  String changeMoved(String who) => 'Moved by $who';
  @override
  String changeReordered(String who) => '$who changed the order';
  @override
  String changeTrashed(String who) => 'Moved to trash by $who';
  @override
  String changeRestored(String who) => 'Restored from trash by $who';
  @override
  String changeDeleted(String who) => 'Deleted for good by $who';
  @override
  String renamedFrom(String old) => 'was: $old';
  @override
  String andInside(int n) => 'and $n inside';
  @override
  String reorderedIn(String place) => 'Order in $place';
  @override
  String changedFields(List<String> fields) => fields.join(', ');
  @override
  String get fieldPhoto => 'photo';
  @override
  String get fieldColor => 'color';
  @override
  String get fieldNote => 'note';
  @override
  String get fieldKind => 'type';
  @override
  String get fieldLocation => 'location';
  @override
  String get justNow => 'just now';
  @override
  String minutesAgo(int n) => '$n min ago';
  @override
  String hoursAgo(int n) => '$n h ago';
  @override
  String get changesAccepted => 'Change applied';
  @override
  String get changesRejected => 'Your version was kept';
  @override
  String newChangesFrom(String who, int n) =>
      n == 1 ? '$who made a change' : '$who made $n changes';
  @override
  String get show => 'Show';
  @override
  String get pendingMarkTooltip => 'A change is waiting for approval';
  @override
  String get tipTitle => 'A few tips';
  @override
  String get tipBody =>
      'The ⋯ button on a card opens its options. To move a card, press, hold and drag it; wait over '
      'a folder to go inside. Swipe a card left for the trash, right for the drawer. Drop a card on '
      "another card's top edge to order it there, and add the ones you open often to favorites from "
      "the ⋯ menu. Things without a place wait in the drawer on the right, missing ones in Lost. "
      'Hold the back arrow inside a folder to jump straight to the home screen.';
  @override
  String get gotIt => 'Got it';
  @override
  String get items => 'Items';
  @override
  String get searchInventory => 'Search the inventory';
  @override
  String get moreActions => 'More';
  @override
  String get cancelDrag => 'Cancel';
  @override
  String get upOneLevel => 'Up a level';
  @override
  String get quantity => 'Quantity';
  @override
  String get quantityHint => 'If there are several, keep count; change it on the card with − / +.';
  @override
  String get quantityTrackedHint => 'At 0 the record is kept with its place; add to it when you restock.';
  @override
  String get stopCounting => 'Stop counting';
  @override
  String get outOfStock => 'Out of stock';
  @override
  String quantityShort(int n) => n == 1 ? '1 piece' : '$n pieces';
  @override
  String get lowStockShort => 'Low';
  @override
  String get minQuantityOff => 'Minimum quantity';
  @override
  String get minQuantityOffHint => 'At this count the card says "Low" and the item is suggested for the shopping list.';
  @override
  String minQuantityOn(int n) => 'Keep at least $n';
  @override
  String minQuantityOnHint(int n) => 'Counts as low at $n or fewer.';
  @override
  String get removeMinQuantity => 'Remove limit';
  @override
  String get fieldMinQuantity => 'minimum quantity';
  @override
  String get increase => 'Add one';
  @override
  String get decrease => 'Remove one';
  @override
  String get fieldQuantity => 'quantity';
  @override
  String get fullShort => 'Full';
  @override
  String get markFull => 'Mark as full';
  @override
  String get markNotFull => 'Clear the full mark';
  @override
  String get fullHint => 'Mark it when nothing else fits; it shows on the card while you look for a place.';
  @override
  String markedFull(String name) => '"$name" is marked full.';
  @override
  String markedNotFull(String name) => '"$name" is no longer full.';
  @override
  String get fieldFull => 'fullness';
  @override
  String get favorites => 'Favorites';
  @override
  String get addFavorite => 'Add to favorites';
  @override
  String get removeFavorite => 'Remove from favorites';
  @override
  String favoriteAdded(String name) => '"$name" added to favorites.';
  @override
  String favoriteRemoved(String name) => '"$name" removed from favorites.';
  @override
  String get favoritesSubtitle => 'The ones you open often';
  @override
  String get favoritesEmpty => 'No favorites yet';
  @override
  String get favoritesEmptyHint =>
      'Add a folder or item you open often from its ⋯ menu; you reach it without '
      'walking through nested folders every time. This list stays on this device; '
      'the people you share with never see it.';
  @override
  String folderDropTitle(String name) => 'Folder "$name"';
  @override
  String get dropMoveFolder => 'Move the folder';
  @override
  String dropMoveFolderHint(String place) => 'New place: $place';
  @override
  String get dropContentsOnly => 'Move only its contents';
  @override
  String dropContentsHint(int n, String place) =>
      '$n records go into $place; the folder stays where it is, empty';
  @override
  String contentsMoved(int n, String place) => '$n records moved: $place';
  @override
  String get groupKindsTitle => 'Keep folders and items apart';
  @override
  String get groupKindsHint =>
      'On: folders come first, items in their own group. Off: everything in one row, '
      'in the order you arrange it.';
  @override
  String get qrShortcutHint => 'Scan the code on a box to open it';
  @override
  String get photoShortcutHint => 'Photograph what you hold, find its place';
  @override
  String resultCount(int n) => n == 1 ? '1 result' : '$n results';
  @override
  String get placeSection => 'Place';
  @override
  String get kindLabel => 'Type';
  @override
  String get gpsLocation => 'Location in the world';
  @override
  String get gpsLocationHint => 'Optional; where it is on a map (GPS)';
  @override
  String get useCurrentLocation => 'Add current location';
  @override
  String get placementHint => 'The folder it sits in';
  @override
  String get options => 'Options';
  @override
  String get icon => 'Icon';
  @override
  String get chooseIcon => 'Choose an icon';
  @override
  String get defaultIcon => 'Default';
  @override
  String get fieldIcon => 'icon';
  @override
  String get adminRole => 'main user';
  @override
  String get makeAdmin => 'Make main user';
  @override
  String get removeAdmin => 'Remove main user role';
  @override
  String get removeFromSharing => 'Remove from sharing';
  @override
  String removeMemberQuestion(String name) => 'Remove $name?';
  @override
  String removeMemberBody(String name) =>
      '$name will no longer sync with this inventory; the records on their device stay there. If they '
      'want to join again, a main user has to approve the request.';
  @override
  String get remove => 'Remove';
  @override
  String memberRemoved(String name) => '$name was removed from sharing.';
  @override
  String get chooseSuccessorTitle => 'Who will manage the inventory?';
  @override
  String get chooseSuccessorBody =>
      'Once you leave they become the owner: they approve changes, add and remove people, assign folders '
      'and pick an heir. The others are told.';
  @override
  String get heirRole => 'heir';
  @override
  String get heirSuffix => '(heir)';
  @override
  String get makeHeir => 'Make heir';
  @override
  String get removeHeir => 'Remove as heir';
  @override
  String get transferOwnership => 'Hand over ownership';
  @override
  String transferQuestion(String name) => 'Hand ownership to $name?';
  @override
  String transferBody(String name) =>
      '$name becomes the owner and you become their heir: if they leave or delete the inventory, it comes '
      'back to you.';
  @override
  String get transfer => 'Hand over';
  @override
  String get youAreOwnerTitle => 'You are now the owner';
  @override
  String youAreOwnerBody(String previous) =>
      '$previous left the inventory or handed it over to you. You can approve changes, add and remove '
      'people, assign folders and pick an heir.';
  @override
  String newOwnerIs(String name) => '$name is now the owner.';
  @override
  String heirToYou(String name) => '$name made you the heir: if the owner leaves, you manage the inventory.';
  @override
  String heirSet(String name) => '$name is now the heir.';
  @override
  String get heirCleared => 'Heir removed.';
  @override
  String memberLeft(String name) => '$name left the shared inventory.';
  @override
  String memberDeletedInventory(String name) => '$name deleted the inventory on their device; it goes on for you.';
  @override
  String get removedFromSharingTitle => 'You were removed from sharing';
  @override
  String removedFromSharingBody(String inventory) =>
      'A main user of "$inventory" removed you. Your records stay on this device but no longer sync.';
  @override
  String get adminHint =>
      'The owner picks an heir; if the owner leaves or deletes the inventory, the heir becomes the owner. '
      'Changes by the heir and main users apply without approval; they approve join requests, remove '
      'people, make others main users and assign people to folders.';
  @override
  String managersLabel(String names) => 'In charge: $names';
  @override
  String get assignManager => 'Put someone in charge';
  @override
  String get chooseManagers => 'Who is in charge of this folder';
  @override
  String get managerHint =>
      'Changes made by the person in charge here and inside apply for everyone without '
      'approval; their decisions on others\' changes apply for everyone too.';
  @override
  String get noOneToAssign => 'Someone has to join the inventory first.';
  @override
  String managesPlaces(String places) => 'In charge of: $places';
  @override
  String appliedByAuthority(String who, int n) =>
      n == 1 ? '$who made a change; applied since they are in charge' : '$who made $n changes; applied since they are in charge';
  @override
  String get fieldManagers => 'person in charge';
  @override
  String get scanNetwork => 'Scan the network';
  @override
  String get scanAgain => 'Scan again';
  @override
  String get scanPrompt =>
      'Scan the network to find the inventory you want to join. It takes a few seconds; the network is not scanned all the time.';
  @override
  String get noInventoriesFound => 'No inventory found';
  @override
  String get dragHintStill => 'Drag to move';
  @override
  String get dragHintMoving => 'Drop it on a folder';

  @override
  String get lostDrawer => 'Lost';
  @override
  String get lostShort => 'Lost';
  @override
  String get lostSubtitle => 'Not where they should be; whoever knows can set the place';
  @override
  String lostWaiting(int n) => n == 1 ? '1 missing item' : '$n missing items';
  @override
  String get lostEmpty => 'Nothing is missing';
  @override
  String get lostEmptyHint =>
      'If something is not where it should be, press and hold its card and choose "Not there". '
      'It comes here and the people you share with are told.';
  @override
  String get notThere => 'Not there';
  @override
  String get iKnowWhere => 'I know where it is';
  @override
  String notThereQuestion(String name) => 'Is "$name" missing?';
  @override
  String get reportLost => 'Report as lost';
  @override
  String get reportLostHint =>
      'Moves to the lost drawer; the people you share with are told and whoever knows can fix it.';
  @override
  String get trashInstead => 'Move to trash';
  @override
  String get trashInsteadHint => 'If it is gone for good. It can be restored from the trash.';
  @override
  String markedLost(String name) => '"$name" is in the lost drawer';
  @override
  String lastSeenIn(String path) => 'Last seen: $path';
  @override
  String lostReported(String who, String name) => '$who: "$name" is missing, moved to lost';
  @override
  String foundReported(String who, String name, String path) => '$who found "$name": $path';
  @override
  String changeLost(String who) => 'Reported lost by $who';
  @override
  String changeFound(String who) => 'Found by $who';
  @override
  String get lostItems => 'Lost items';

  @override
  String get settings => 'Settings';
  @override
  String get appearance => 'Appearance';
  @override
  String get systemTheme => 'Match system';
  @override
  String get lightTheme => 'Light';
  @override
  String get darkTheme => 'Dark';
  @override
  String get language => 'Language';
  @override
  String get languageSystem => 'Match system';
  @override
  String get autoLocationTitle => 'Auto location for new folders';
  @override
  String get autoLocationSubtitle =>
      'GPS position is captured automatically when you create a folder.';
  @override
  String get inventory => 'Inventory';
  @override
  String get recordTotal => 'Records';
  @override
  String get inTrash => 'Records in trash';
  @override
  String get backup => 'Backup';
  @override
  String get exportTitle => 'Export';
  @override
  String get exportHint =>
      'Puts every record, photo and attachment into a single file you can keep anywhere or send.';
  @override
  String get exportShareText => 'Inventory backup';
  @override
  String get exporting => 'Exporting…';
  @override
  String exportFailed(String reason) => 'Export failed: $reason';
  @override
  String get importTitle => 'Import';
  @override
  String get importHint =>
      'Restores a file you exported earlier. Nothing here is deleted; if a record exists '
      'on both sides, the newer one wins.';
  @override
  String get importing => 'Importing…';
  @override
  String get importNothing => 'Nothing new; everything is already up to date.';
  @override
  String importDone(int added, int updated, int photos) => [
        if (added > 0) '$added records added',
        if (updated > 0) '$updated updated',
        if (photos > 0) '$photos photos',
      ].join(', ');
  @override
  String get importFailed => 'The file could not be read.';
  @override
  String get importNotOurs => 'This file is not an inventory backup.';
  @override
  String get importNewerVersion => 'The file comes from a newer version of the app; update first.';
  @override
  String get localOnly =>
      'Your data never goes to a server; it stays on this device and the devices you share with.';
  @override
  String get user => 'User';
  @override
  String get userNameTitle => 'User name';
  @override
  String get yourName => 'Your name';
  @override
  String get localInventory => 'Local inventory on this device';
  @override
  String get editName => 'Edit name';
  @override
  String get totalRecords => 'Total records';
  @override
  String get recentTitle => 'Recently touched';
  @override
  String get inNote => 'In note';
  @override
  String lastBackup(String when) => 'Last backup: $when';
  @override
  String get neverBackedUp => 'No backup yet.';
  @override
  String get today => 'today';
  @override
  String daysAgo(int n) => n == 1 ? 'yesterday' : '$n days ago';
  @override
  String get backupReminderTitle => 'Time for a backup';
  @override
  String backupReminderBody(int changes, {required bool never}) => never
      ? 'Your inventory only lives on this phone; keep a copy somewhere safe.'
      : (changes == 1
          ? '1 record changed since the last backup.'
          : '$changes records changed since the last backup.');
  @override
  String get backupNow => 'Back up now';
  @override
  String get later => 'Later';
  @override
  String get select => 'Select';
  @override
  String get selectHint => 'Tap cards to select them';
  @override
  String selectedCount(int n) => '$n selected';
  @override
  String get selectAll => 'Select all';
  @override
  String get doneSelecting => 'Done selecting';
  @override
  String get moveShort => 'Move';
  @override
  String get toDrawerShort => 'To drawer';
  @override
  String get labelsShort => 'Labels';
  @override
  String get trashShort => 'Trash';
  @override
  String whereShouldGoMany(int n) => n == 1 ? 'Where should 1 record go?' : 'Where should $n records go?';
  @override
  String movedMany(int n, String place) => n == 1 ? 'Moved 1 record to $place' : 'Moved $n records to $place';
  @override
  String trashedMany(int n) => n == 1 ? '1 record moved to trash' : '$n records moved to trash';
  @override
  String get qrLabels => 'QR labels';
  @override
  String get labelsTitle => 'QR label sheet';
  @override
  String get labelsHint => 'Print on A4, cut out and stick on boxes. Scanning opens the record.';
  @override
  String get labelSize => 'Label size';
  @override
  String get labelSmall => 'Small';
  @override
  String get labelMedium => 'Medium';
  @override
  String get labelLarge => 'Large';
  @override
  String perPage(int n) => '$n per page';
  @override
  String get labelsWhich => 'Which';
  @override
  String get labelScopeFolders => 'Folders';
  @override
  String get labelScopeAll => 'Items too';
  @override
  String labelCount(int labels, int pages) =>
      '${labels == 1 ? '1 label' : '$labels labels'} · ${pages == 1 ? '1 page' : '$pages pages'}';
  @override
  String get createPdf => 'Create and share PDF';
  @override
  String get labelsShareText => 'Inventory QR labels';
  @override
  String labelsFailed(String reason) => 'Could not prepare labels: $reason';
  @override
  String get moveHere => 'Move here';
  @override
  String get alreadyHere => 'Already here';
  @override
  String get noFoldersHere => 'No folders here. Move here, or go up with ↑.';
  @override
  String get noFoldersInside => 'No folders inside. Choose this one, or go up with ↑.';
  @override
  String get noFoldersWhereYouAre => 'No folders inside the one you\'re in. Go up with ↑ and choose another folder.';
  @override
  String folderCount(int n) => n == 1 ? '1 folder' : '$n folders';
  @override
  String get keepPrivate => 'Keep on this device only';
  @override
  String get makeShared => 'Share with other devices';
  @override
  String get privateHint => 'Only on this device; not synced';
  @override
  String get privateInherited => 'Its folder is kept on this device, so this is not synced either.';
  @override
  String markedPrivate(String name, {required bool wasShared}) => wasShared
      ? '$name stays on this device and is no longer synced. Copies sent earlier remain on other devices.'
      : '$name stays on this device and is not synced.';
  @override
  String markedShared(String name) => '$name is synced with other devices again.';
  @override
  String get privateSwitchTitle => 'Only on this device';
  @override
  String get privateSwitchHint => 'Never sent to other devices when sharing; anything put inside stays private too.';
  @override
  String heldAt(String who) => 'With $who';
  @override
  String heldHint(String who) =>
      '$who moved this into their private area; further changes will not arrive. Put it somewhere to clear this.';
  @override
  String get datesSection => 'Dates';
  @override
  String get purchaseDate => 'Purchase date';
  @override
  String get expiryDate => 'Expiry date';
  @override
  String get shelfLife => 'Shelf life';
  @override
  String get shelfLifeHint => 'For things with no date printed (bananas, apples): added to the purchase date.';
  @override
  String get warnBeforeExpiry => 'Warn before expiry';
  @override
  String defaultWarn(String span) => 'General setting ($span)';
  @override
  String get warrantyEnd => 'Warranty end date';
  @override
  String get warrantyPeriod => 'Warranty period';
  @override
  String get warrantyPeriodHint => 'If no end date is given, added to the purchase date.';
  @override
  String get notSet => 'Not set';
  @override
  String calculated(String date) => 'Calculated: $date';
  @override
  String get needsPurchaseDate => 'Calculated once a purchase date is set.';
  @override
  String get dateOverrides => 'Not used: a date is given.';
  @override
  String get clearValue => 'Remove';
  @override
  String get useDefault => 'Use general setting';
  @override
  String get done => 'Done';
  @override
  String get amount => 'Amount';
  @override
  String spanText(TimeSpan span) {
    final word = switch (span.unit) {
      SpanUnit.day => 'day',
      SpanUnit.week => 'week',
      SpanUnit.month => 'month',
      SpanUnit.year => 'year',
    };
    return '${span.amount} $word${span.amount == 1 ? '' : 's'}';
  }
  @override
  String unitLabel(SpanUnit unit) => switch (unit) {
        SpanUnit.day => 'Days',
        SpanUnit.week => 'Weeks',
        SpanUnit.month => 'Months',
        SpanUnit.year => 'Years',
      };
  @override
  List<String> get monthsShort =>
      const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  @override
  String get expiredShort => 'Expired';
  @override
  String someExpired(int k) => '$k past date';
  @override
  String moreDates(int n) => '+$n more';
  @override
  String discardExpiredAction(int k) => 'Throw out expired ($k)';
  @override
  String discardedExpired(String name, int k) => '$name: threw out $k past their date.';
  @override
  String addedWithDate(String date) => 'Added 1 · expires $date';
  @override
  String get otherDate => 'Other date';
  @override
  String get newLotsDate => 'Expiry date of the new ones';
  @override
  String get expiryDates => 'Expiry dates';
  @override
  String get addLotButton => 'Add a package with another date';
  @override
  String get expiringShort => 'Expires soon';
  @override
  String expiryOn(String date) => 'Exp. $date';
  @override
  String daysLeft(int n) => n == 1 ? '1 day left' : '$n days left';
  @override
  String get lastDayToday => 'last day today';
  @override
  String expiredAgo(int n) => n == 1 ? 'expired yesterday' : 'expired $n days ago';
  @override
  String warrantyUntil(String date) => 'Warranty until $date';
  @override
  String get warrantyEnded => 'Warranty ended';
  @override
  String get expiryWarnSetting => 'Expiry warning';
  @override
  String expiryWarnSettingHint(String span) =>
      'Cards show a warning $span before the expiry date. Each item can override this.';
  @override
  String expiryWarnGeneralHint(String span) =>
      'Cards show a warning at most $span before the expiry date; for short-lived food (yogurt, milk) when a '
      'quarter of its life is left. Each item can override this.';
  @override
  String get datesPage => 'Coming up';
  @override
  String get expiredSection => 'Expired';
  @override
  String get expiringSection => 'Expiring soon';
  @override
  String get warrantySection => 'Warranties';
  @override
  String get noDatesSoon => 'Nothing expiring soon';
  @override
  String get noDatesSoonHint => 'Add purchase, expiry and warranty dates in the Dates section of an item\'s editor.';
  @override
  String get fieldDates => 'dates';
  @override
  String peerOutdated(String who) => "$who's app is out of date; not syncing with them until it is updated.";
  @override
  String selfOutdated(String who) => "This app is older than $who's; not syncing until it is updated.";
  @override
  String get memberOutdated => 'App out of date; not syncing until updated';
  @override
  String get thisOutdated => 'This app is older; update it';
  @override
  String get joinIncompatible =>
      'Joined, but the two apps are different versions; the inventory arrives once the older one is updated.';
  @override
  String get autoBackupTitle => 'Automatic backup';
  @override
  String get autoBackupHint =>
      'All inventories are backed up to a folder you choose, each under its own name: weekly and when you '
      'leave an inventory that changed. The newest 4 of each are kept. Pick a folder that syncs to the cloud '
      'or that you copy to a computer, so it helps even if the phone is lost.';
  @override
  String autoBackupOn(String folder) =>
      'All inventories to “$folder”: weekly and when you leave an inventory that changed. The newest 4 of '
      'each are kept.';
  @override
  String get autoBackupFailed => 'The last automatic backup could not be written; choose the folder again.';
  @override
  String autoBackupWritten(String folder) => 'Backup written to “$folder”.';
  @override
  String get notifyChannel => 'Expiry, warranty and maintenance';
  @override
  String get notifyChannelHint => 'Items nearing their expiry date, warranties ending and maintenance days';
  @override
  String notifyExpiring(String date, int daysLeft) =>
      'Expires $date · ${daysLeft == 1 ? '1 day' : '$daysLeft days'} left';
  @override
  String get notifyLastDay => 'Last day today';
  @override
  String notifyWarranty(String date) => 'Warranty ends on $date';
  @override
  String notifyManyTitle(int n) => '$n items have dates coming up';
  @override
  String get notifySetting => 'Phone notification';
  @override
  String get notifySettingHint =>
      'At 9 am when the warning period starts, on the last day, a month before a warranty ends and on '
      'maintenance days; even when the app is closed.';
  @override
  String get notifyDenied => 'Notification permission denied; tap to allow.';
  @override
  String get shoppingList => 'Shopping list';
  @override
  String get outOfStockSection => 'Out of stock';
  @override
  String get replaceSection => 'Past their date';
  @override
  String get lowSection => 'Running low';
  @override
  String get autoShopTitle => 'Add to the list by itself';
  @override
  String get autoShopHint => 'Goes on the shopping list when it runs out, runs low or passes its expiry date.';
  @override
  String get nowOnShoppingList => 'Added to the shopping list.';
  @override
  String get expiredPanel => 'Past their date';
  @override
  String get expiredSubtitle => 'Still in place';
  @override
  String get expiredEmpty => 'Nothing past its date';
  @override
  String get expiredEmptyHint =>
      'Items past their expiry date are marked here and stay where they are. They drop off when you trash '
      'them, move them to the drawer or use them up.';
  @override
  String get toBuySection => 'To buy';
  @override
  String get suggestionsSection => 'Suggested';
  @override
  String get suggestionsHint => 'Out of stock, running low or past their date, but not on your list.';
  @override
  String get addToShopping => 'Add to shopping list';
  @override
  String get removeFromShopping => 'Remove from shopping list';
  @override
  String get addShort => 'Add';
  @override
  String get addToListShort => 'Add to list';
  @override
  String addedToShopping(String name) => '$name added to the shopping list.';
  @override
  String removedFromShopping(String name) => '$name removed from the shopping list.';
  @override
  String ranOut(String name) => '$name ran out.';
  @override
  String runningLow(String name) => '$name is running low.';
  @override
  String get fieldShopping => 'shopping list';
  @override
  String get outOfStockNote => 'out of stock';
  @override
  String lowLeft(int left, int min) => '$left left · min $min';
  @override
  String lowNote(int left) => '$left left';
  @override
  String get bought => 'Bought';
  @override
  String get boughtNew => 'Bought new';
  @override
  String get howManyBought => 'How many did you buy?';
  @override
  String restocked(String name, int n) => '$name: $n';
  @override
  String replacedWithDate(String name, String date) => '$name replaced; new expiry $date.';
  @override
  String replacedEnterDate(String name) => "$name replaced; don't forget the expiry date on the pack.";
  @override
  String get enterDate => 'Enter date';
  @override
  String get shoppingEmpty => 'Nothing to buy';
  @override
  String get shoppingEmptyHint =>
      'Add things from a card\'s ⋯ menu with "Add to shopping list"; they drop off as you buy them. For an '
      'item that should go on by itself when it runs out, runs low or passes its date, turn on "Add to the '
      'list by itself" in its editor.';
  @override
  String get shareList => 'Share list';
  @override
  String shoppingHeader(String date) => 'Shopping list · $date';
  @override
  String get pastDateNote => 'past its date';

  @override
  String get attachments => 'Attachments';
  @override
  String get fieldAttachments => 'attachments';
  @override
  String get addAttachment => 'Add attachment';
  @override
  String get attachmentsHint => 'A user manual, warranty card, receipt, a video or a link.';
  @override
  String get attachDocument => 'Document or file';
  @override
  String get attachDocumentHint => 'A PDF manual, a receipt, any file on the phone';
  @override
  String get attachRecordVideo => 'Record a video';
  @override
  String get attachFromGallery => 'Photo or video from gallery';
  @override
  String get attachLink => 'Link';
  @override
  String get attachLinkHint => 'The address of a video or a web page';
  @override
  String get linkAddress => 'Address';
  @override
  String get linkTitleOptional => 'Title (optional)';
  @override
  String get linkInvalid => 'This address cannot be opened. Type one like "youtube.com/…" or "https://…".';
  @override
  String get attachmentPhoto => 'Photo';
  @override
  String get attachmentVideo => 'Video';
  @override
  String get attachmentDocument => 'Document';
  @override
  String get attachmentName => 'Attachment name';
  @override
  String attachmentTooLarge(String names) => '$names is too large: an attachment can be 500 MB at most.';
  @override
  String get attachmentFailed => 'Could not add the file.';
  @override
  String get attachmentNotHere =>
      'This file has not reached this device yet. It downloads by itself when the device that added it is on the same network.';
  @override
  String get attachmentNotHereShort => 'not downloaded yet';
  @override
  String attachmentDownloading(int percent) => 'downloading, $percent%';
  @override
  String get noAppToOpen => 'No app on this phone can open this file.';
  @override
  String get cannotOpenLink => 'Could not open the link.';
  @override
  String get renameAttachment => 'Rename';
  @override
  String get removeAttachment => 'Remove attachment';
  @override
  String get shareAttachment => 'Share';
  @override
  String get copyLink => 'Copy address';
  @override
  String get linkCopied => 'Address copied.';
  @override
  String attachmentCount(int n) => n == 1 ? '1 attachment' : '$n attachments';
  @override
  String attachmentsAdded(int n) => n == 1 ? 'Attachment added.' : '$n attachments added.';
  @override
  String get attachmentLimit => 'A record can have at most 40 attachments.';
  @override
  String fileSize(int bytes) => _fileSize(bytes, '.');
  @override
  String get storageTitle => 'Photos and attachments';
  @override
  String get storageMeasuring => 'Measuring…';
  @override
  String storageSummary(int photos, int files) =>
      '$photos ${photos == 1 ? 'photo' : 'photos'} · $files attachment ${files == 1 ? 'file' : 'files'}';
  @override
  String get storagePhotos => 'Photos';
  @override
  String get storageFiles => 'Attachment files';
  @override
  String storageCount(int n) => n == 1 ? '1 file' : '$n files';
  @override
  String get storageLargest => 'Largest attachments';
  @override
  String get storageNote =>
      'The space this inventory takes on this device; a backup file is about the same size. To free space, remove a '
      'large attachment in its record\'s editor: its file stays until the trash and "Recently deleted" are emptied.';
  @override
  String get storageNoFiles => 'No file attachments yet. Documents, photos or videos added to records show up here.';
  @override
  String get storageInTrash => 'in the trash';
  @override
  String get noResultHint =>
      'Try a shorter or different word: names, notes, places and attachment names are searched. Records in the trash are not.';
  @override
  String get trashEmptyHint =>
      'Records you trash wait here: restore them or delete them for good. Permanently deleted ones stay 30 more days '
      'under "Recently deleted", unless you delete them completely right away.';
  @override
  String get quickMove => 'Move';
  @override
  String get quickFavorite => 'Favorite';
  @override
  String get quickShop => 'Add to list';
  @override
  String get quickShopOn => 'On the list';
  @override
  String todayExpired(int n) => '$n expired';
  @override
  String todaySoon(int n) => '$n expiring soon';
  @override
  String todayToBuy(int n) => '$n to buy';
  @override
  String todayToPutAway(int n) => '$n to put away';
  @override
  String todayLost(int n) => '$n lost';
  @override
  String todayInDrawer(int n) => '$n in the drawer';
  @override
  String get settingsMine => 'Mine';
  @override
  String get settingsInventory => 'This inventory';
  @override
  String get moreFields => 'More';
  @override
  String get sortTitle => 'Sort';
  @override
  String get sortManual => 'My order';
  @override
  String get sortName => 'By name (A–Z)';
  @override
  String get sortNewest => 'Newest first';
  @override
  String get sortExpiry => 'Soonest date first';
  @override
  String sortedNoManual(String mode) => 'Cards cannot be arranged by hand while sorted "$mode".';
  @override
  String get viewTitle => 'View';
  @override
  String get viewHint =>
      'Deck: stacked cards. List: compact rows, more records fit on screen. Grid: photos first. '
      'The button next to the search bar cycles through them too.';
  @override
  String get viewDeck => 'Deck';
  @override
  String get viewList => 'List';
  @override
  String get viewGrid => 'Grid';
  @override
  String showAs(String view) => 'Show as ${view.toLowerCase()}';
  @override
  String get syncClosedTitle => 'Sync closed inventories too';
  @override
  String get syncClosedHint =>
      'Shared inventories sync in the background even when not open (on Wi-Fi, while the app is off screen).';
  @override
  String pendingInInventory(int count) =>
      count == 1 ? '1 change is waiting for approval' : '$count changes are waiting for approval';
  @override
  String get notifyPendingTitle => 'Notify about pending changes';
  @override
  String get notifyPendingHint =>
      'Shows a phone notification when a new change arrives for approval while the app is off screen.';
  @override
  String get pendingChannel => 'Changes waiting for approval';
  @override
  String get pendingChannelHint => 'Changes made by others in a shared inventory that wait for your approval';
  @override
  String get pendingNoticeTitle => 'Changes are waiting for approval';

  // Envanterler arası aktarma / kopyalama
  @override
  String get transferToOtherInventory => 'Transfer to other inventory';
  @override
  String get transferOrCopyTitle => 'Transfer between inventories';
  @override
  String get transferAction => 'Move';
  @override
  String get copyAction => 'Copy';
  @override
  String get selectTargetInventory => 'Select target inventory';
  @override
  String get cannotTransferToSame => 'Target inventory cannot be the active one';
  @override
  String transferredTo(String name, String inventory) => '$name moved to $inventory';
  @override
  String copiedTo(String name, String inventory) => '$name copied to $inventory';
  @override
  String transferredMany(int n, String inventory) => '$n records moved to $inventory';
  @override
  String copiedMany(int n, String inventory) => '$n records copied to $inventory';

  // Periyodik bakım döngüsü
  @override
  String get maintenanceDone => 'Maintenance done';
  @override
  String maintained(String name) => 'Maintenance recorded for $name';
  @override
  String maintainedWithNext(String name, String nextDate) => 'Maintenance recorded for $name · Next: $nextDate';
  @override
  String get serviceCycle => 'Service cycle';
  @override
  String get serviceCycleHint => 'Periodic maintenance and service interval (e.g. 6 months, 1 year)';
  @override
  String get serviceSection => 'Maintenance';
  @override
  String serviceEveryText(TimeSpan span) {
    final word = switch (span.unit) {
      SpanUnit.day => 'day',
      SpanUnit.week => 'week',
      SpanUnit.month => 'month',
      SpanUnit.year => 'year',
    };
    return span.amount == 1 ? 'every $word' : 'every ${span.amount} ${word}s';
  }
  @override
  String get serviceTaskTitle => 'What to do';
  @override
  String get serviceTaskHint => 'E.g. oil it, change the filter, take it in for service';
  @override
  String get lastService => 'Last maintenance';
  @override
  String nextServiceOn(String date) => 'Next maintenance: $date';
  @override
  String get serviceNeedsLast => 'Enter the date of the last maintenance to plan the next one';
  @override
  String get serviceHistory => 'Maintenance history';
  @override
  String get serviceHistoryEmpty => 'No entries yet: "Maintenance done" or "Add entry" adds one.';
  @override
  String get serviceAddEntry => 'Add entry';
  @override
  String get serviceEntryNote => 'Note';
  @override
  String get serviceEntryNoteHint => 'What was done, by whom, what it cost (optional)';
  @override
  String serviceShowAll(int n) => 'Show all ($n)';
  @override
  String get serviceRemoveEntry => 'Remove entry';
  @override
  String get serviceDueToday => 'maintenance due today';
  @override
  String serviceLate(int days) => days == 1 ? 'maintenance 1 day overdue' : 'maintenance $days days overdue';
  @override
  String get serviceDueSection => 'Maintenance due';
  @override
  String get serviceScheduleSection => 'Maintenance schedule';
  @override
  String todayService(int n) => '$n maintenance due';
  @override
  String notifyService(String? task) => task == null ? 'Maintenance due' : 'Maintenance due: $task';
  @override
  String get fieldService => 'maintenance';
  @override
  String fieldServiced(String date) => 'maintenance done ($date)';

  // Arama filtre çipleri
  @override
  String get allFilter => 'All';
  @override
  String get foldersOnly => 'Folders';
  @override
  String get itemsOnly => 'Items';
  @override
  String get withDatesOnly => 'With dates';
  @override
  String get withPhotosOnly => 'With photos';
  @override
  String get outOfStockOnly => 'Out of stock';
  @override
  String get withAttachmentsOnly => 'With attachments';

  // Koli ve içerik dökümü
  @override
  String get exportContent => 'Export contents';
  @override
  String get exportPdfList => 'Share as PDF (printable)';
  @override
  String get exportCsvList => 'Share as CSV table';
  @override
  String get boxContentList => 'Box contents list';
  @override
  String get itemIndexCol => '#';
  @override
  String get itemNameCol => 'Item name';
  @override
  String get itemQuantityCol => 'Quantity';
  @override
  String get itemLocationCol => 'Location';
  @override
  String get itemNoteCol => 'Note / status';
  @override
  String get itemBarcodeCol => 'Barcode';

  // Ölçü birimi desteği
  @override
  String get unit => 'Unit';
  @override
  String get unitHint => 'Piece, pack, kg, meter...';
  @override
  String get unitPiece => 'pcs';
  @override
  String get unitPackage => 'pack';
  @override
  String get unitKg => 'kg';
  @override
  String get unitGram => 'g';
  @override
  String get unitMeter => 'm';
  @override
  String get unitCm => 'cm';
  @override
  String get unitLiter => 'L';
  @override
  String get unitBox => 'box';
  @override
  String get unitPair => 'pair';
  @override
  String get unitRoll => 'roll';
  @override
  String get customUnit => 'Type custom unit';

  // Seri barkod / QR sayım modu
  @override
  String get serialScanMode => 'Serial stocktake mode';
  @override
  String get serialScanHint => 'Scan barcodes consecutively; stock counts update instantly';
  @override
  String stockCounted(String name, int quantity) => '$name counted · New count: $quantity';
  @override
  String get unknownBarcodeScan => 'Barcode not registered';
  @override
  String serialFolderSkipped(String name) => '$name is a folder: it has no count';
  @override
  String get scanBatchFinished => 'Stocktake finished';

  // Emanet & Ödünç Takibi
  @override
  String get borrowedPageTitle => 'Lent & Borrowed';
  @override
  String get borrowAction => 'Lend item';
  @override
  String get borrowDetailsTitle => 'Lending details';
  @override
  String get borrower => 'Borrower';
  @override
  String get borrowerHint => 'e.g. John Doe';
  @override
  String get borrowedAt => 'Date lent';
  @override
  String get returnDueDate => 'Expected return date';
  @override
  String get noReturnDueDate => 'No return date specified';
  @override
  String get markReturned => 'Mark returned';
  @override
  String borrowedToStamp(String name) => 'With $name';
  @override
  String get borrowOverdueShort => 'Overdue';
  @override
  String todayOverdueBorrow(int n) => '$n lent overdue';
  @override
  String todayBorrowed(int n) => '$n lent out';
  @override
  String fieldBorrowed(String name) => 'Lent to: $name';
  @override
  String get fieldReturned => 'Returned from lending';
  @override
  String get filterBorrowed => 'Lent Out';
  @override
  String get noBorrowedItems => 'No lent items';
  @override
  String get noBorrowedHint => 'Track items you\'ve lent out to others here.';
  @override
  String get overdueSection => 'Overdue';
  @override
  String get activeBorrowSection => 'Currently lent';
  @override
  String borrowSuccess(String item, String to) => '$item lent to $to';
  @override
  String returnSuccess(String item) => '$item marked as returned';
  @override
  String get pickReturnDate => 'Pick return date';
  @override
  String get inOneWeek => 'In 1 week';
  @override
  String get inTwoWeeks => 'In 2 weeks';
  @override
  String get inOneMonth => 'In 1 month';
  @override
  String get clearDate => 'Clear date';
  @override
  String get quickBorrow => 'Lend';
  @override
  String get borrowerRequired => 'Please enter a borrower name';

  @override
  String get auditInventory => 'Audit / count';
  @override
  String get auditFolder => 'Audit / count';
  @override
  String get auditScopePrompt => 'Where to run audit?';
  @override
  String get auditPickFolder => 'Which folder to count?';
  @override
  String get auditCountHere => 'Count here';
  @override
  String get auditEntireInventory => 'Entire inventory';
  @override
  String get auditThisFolder => 'Only this folder';
  @override
  String get auditIncludeSubfolders => 'Include subfolders';
  @override
  String get startAudit => 'Start audit';
  @override
  String get auditProgress => 'Audit progress';
  @override
  String auditItemProgress(int counted, int total) => '$counted / $total counted';
  @override
  String get auditFilterAll => 'All';
  @override
  String get auditFilterPending => 'Pending';
  @override
  String get auditFilterVerified => 'Verified';
  @override
  String get auditFilterDiscrepancy => 'Discrepancies';
  @override
  String get auditFilterUnexpected => 'Unexpected';
  @override
  String get verifyAction => 'Verify';
  @override
  String get markMissingAction => 'Missing';
  @override
  String get resetCountAction => 'Reset';
  @override
  String expectedQuantity(int count, [String? unit]) => 'Expected: $count${unit != null ? " $unit" : ""}';
  @override
  String countedQuantity(int count, [String? unit]) => 'Counted: $count${unit != null ? " $unit" : ""}';
  @override
  String get finishAudit => 'Finish audit';
  @override
  String get finishAuditShort => 'Finish';
  @override
  String get auditSummaryTitle => 'Audit and reconciliation summary';
  @override
  String auditVerifiedSummary(int n) => '$n records verified and complete.';
  @override
  String auditDiscrepancySummary(int n) => '$n records have quantity differences.';
  @override
  String auditMissingSummary(int n) => '$n records were not found.';
  @override
  String auditUnexpectedSummary(int n) => '$n unexpected items found here.';
  @override
  String get auditApplyQuantityChanges => 'Update quantities to counted amounts';
  @override
  String get auditMarkMissingAsLost => 'Mark missing items as "Lost"';
  @override
  String get auditAddMissingToShopping => 'Add missing items to shopping list';
  @override
  String get auditMoveMissingToDrawer => 'Move missing items to drawer';
  @override
  String get auditMoveFoundHere => 'Move items found here into this folder';
  @override
  String get auditApplyAndFinish => 'Apply reconciliation and finish';
  @override
  String get auditCompletedNotice => 'Audit completed and records updated successfully.';
  @override
  String get auditEmptyScope => 'No items to audit in this folder.';
  @override
  String get auditScanBarcodePrompt => 'Scan barcodes to quickly verify items.';
  @override
  String auditItemCountedSuccess(String name, int count) => '$name counted ($count)';
  @override
  String auditItemFoundOtherFolder(String name, String folder) => '$name is usually in "$folder"; included here.';
  @override
  String get auditNoChanges => 'No discrepancies found, all items match.';
  @override
  String get auditMarkMissingActionLabel => 'What to do with missing items?';
  @override
  String get auditMissingDoNothing => 'Do nothing (leave in place)';

  @override
  String money(Money m) => m.format(turkish: false);
  @override
  String moneyTotals(MoneyTotals t) => t.format(turkish: false);
  @override
  String get fieldPrice => 'price';
  @override
  String get fieldSerial => 'serial no';
  @override
  String get valueSection => 'Value';
  @override
  String get priceTitle => 'Price';
  @override
  String get priceHint => 'What one of it cost or is worth; added up in insurance and moving lists.';
  @override
  String priceEach(String price) => '$price each';
  @override
  String valueTimes(int count, String price, String total) => '$count × $price = $total';
  @override
  String get priceInvalid => 'Could not read the amount; type e.g. 1250 or 1,250.50.';
  @override
  String get currency => 'Currency';
  @override
  String get currencyHint =>
      'New prices start in this currency. Different currencies are totalled separately, without conversion.';
  @override
  String get otherCurrency => 'Another currency';
  @override
  String get currencyCodeHint => 'Three-letter code, e.g. GBP';
  @override
  String get serialTitle => 'Serial / model no';
  @override
  String get serialHint => 'From the device label or the invoice; asked for in insurance and warranty claims.';
  @override
  String get serialCopied => 'Serial number copied';
  @override
  String contentsValue(String value) => 'Contents worth $value';
  @override
  String itemValue(String value) => 'Worth $value';
  @override
  String get valuePageTitle => 'Value';
  @override
  String get totalValue => 'Total value';
  @override
  String get valueByPlace => 'By place';
  @override
  String get mostValuable => 'Most valuable';
  @override
  String unpricedItems(int n) => n == 1 ? '1 item has no price' : '$n items have no price';
  @override
  String get unpricedHint => 'Keep the list complete: tap to see the items without a price.';
  @override
  String get noValueYet => 'No prices entered yet';
  @override
  String get noValueHint =>
      'When editing an item, open More → Value and enter its price. Totals per folder appear here, and you '
      'can export a list for insurance or moving.';
  @override
  String get currenciesSeparate => 'Different currencies are totalled separately, without conversion.';
  @override
  String get valueReport => 'Value report (PDF)';
  @override
  String get valueReportTitle => 'Value report';
  @override
  String get valueReportHint => 'For insurance and moving: items, places, serial numbers, amounts';
  @override
  String get colUnitPrice => 'Unit price';
  @override
  String get colAmount => 'Amount';
  @override
  String get colSerial => 'Serial no';
  @override
  String get colPurchased => 'Purchased';
  @override
  String reportDate(String date) => 'Prepared on $date';
  @override
  String reportCounts(int priced, int unpriced) {
    final items = priced == 1 ? '1 item' : '$priced items';
    return unpriced == 0 ? items : '$items · $unpriced without a price';
  }

  @override
  String get subtotal => 'Subtotal';
  @override
  String get grandTotal => 'Grand total';
  @override
  String get unpricedSection => 'Without a price';

  @override
  String get burstAdd => 'Add a series';
  @override
  String get burstAddHint => 'Shoot one after another or pick many from the gallery; each photo becomes an item';
  @override
  String get burstCameraHint => 'The camera stays open; afterwards you just type the names';
  @override
  String get burstGalleryHint => 'Pick several photos; each becomes an item named after the photo';
  @override
  String get burstMoreFromGallery => 'Add from gallery';
  @override
  String burstImporting(int done, int total) => 'Importing photos: $done / $total';
  @override
  String burstImportFailed(int n) => n == 1 ? '1 photo could not be imported' : '$n photos could not be imported';
  @override
  String burstPreparing(int done, int total) => 'Preparing: $done / $total';
  @override
  String burstShots(int n) => n == 1 ? '1 photo' : '$n photos';
  @override
  String get burstDone => 'Done';
  @override
  String get burstTakeMore => 'Take more';
  @override
  String burstAddItems(int n) => n == 1 ? 'Add 1 item' : 'Add $n items';
  @override
  String get burstNameHint => 'Name (blank: Unnamed)';
  @override
  String burstAdded(int n, String place) => n == 1 ? '1 item added to $place' : '$n items added to $place';
  @override
  String burstDiscardQuestion(int n) => n == 1 ? 'Discard the photo you took?' : 'Discard the $n photos you took?';
  @override
  String get burstDiscard => 'Discard and leave';
  @override
  String get burstKeep => 'Keep going';
  @override
  String get burstCameraFailed => 'Could not open the camera. Check the permission, or whether another app is using it.';
  @override
  String get burstEmpty => 'Frame the item and tap the button; the camera stays open.';
  @override
  String get burstSaving => 'Adding…';
  @override
  String burstTarget(String place) => 'Into: $place';
  @override
  String get burstRemoveShot => 'Remove this photo';
}

/// Dosya boyutu ("840 KB", "3,2 MB"); ondalık ayırıcı dile göre.
String _fileSize(int bytes, String decimal) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  // "3,2 MB" ama "3 MB": tam sayıda ",0" yazılmaz.
  final fixed = value >= 100 || unit == 0 ? value.round().toString() : value.toStringAsFixed(1);
  final text = fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed.replaceAll('.', decimal);
  return '$text ${units[unit]}';
}
