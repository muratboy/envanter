# Envanter

Ev, atölye, depo ya da küçük bir kütüphane için görsel envanter uygulaması.
Flutter ile yazıldı, şu an Android'de çalışıyor. Sunucu yok: veriler cihazda tutulur,
istenirse aynı Wi-Fi'deki kişilerle ortak kullanılır.
Arayüz Türkçe ve İngilizce; Ayarlar'dan seçilir ya da cihaz dilini izler.
Telefonda ve tablette, dikey ve yatay çalışır.

## Temel fikir

Her şey tek bir ağaçta yaşayan **kayıt** (`Node`): klasör ya da eşya.
Klasörler içlerine hem eşya hem başka klasör alır, derinlik sınırı yoktur.
Bir eşyayı klasöre çevirmek (ya da tersi) tek dokunuşluk iş.

## Tasarım dili

Bir kartoteks ya da arşiv dolabı: renkli olan yalnızca kartların kendisi,
çerçeve sakin kalır.

- **Renk:** sıcak kağıt zemin (koyu temada neredeyse siyah kahve), mürekkep yazı ve
  az kullanılan tek bir vurgu rengi, kiremit (yeni kayıt düğmesi, bildirimler).
  Kart paleti pastel kağıt ve klasör tonları; kartların üstünde yazı koyu
  mürekkeple durur. Eski sürümün doygun renkleri kayıtlara dokunmadan, gösterirken
  aynı sıradaki yeni renge çevrilir (`canonicalCardColor`).
- **Yazı:** başlıklar ve kart adları serif (Fraunces), arayüz metinleri Manrope.
  Bölüm başlıkları küçük, harf aralıklı büyük harflerle.
- **Biçim:** klasör gerçekten bir klasör (sekmeli), eşya kütüphane fiş kartı (başlığın altında kiremit bir
  çizgi, soluk satır çizgileri); fotoğraflar bantlı ya da raptiyeli baskı. Boş
  ekranlarda mürekkep çizimler (`InkArt`); görsel dosyası kullanılmaz.
- **Düzen:** her sayfada aynı başlık (üst satırda yer/sayı, altında serif başlık,
  eylemler sağda tek kapsülde); altta arama kutusu ve yanında "+". Ayarlar ve
  düzenleyici başlıklı kağıt panellerde.
- **Simge:** kiremit zemin üzerinde kağıt bir kutu, içinden iki kart çıkıyor (öndeki bir
  fotoğraf baskısı). Telefonun simge biçimine uyar (daire, yuvarlak kare...); Android 13+ tema
  simgesi için tek renkli katmanı var, bildirim çubuğundaki küçük simge de aynı biçim. Açılış
  ekranı kağıt zemin rengindedir.

## Neler var

**Kartlar ve deste**
- Kartlar üst üste binen bir deste halinde durur; parmakla yukarı aşağı kaydırınca
  odaktaki kart tümüyle açılır, diğerleri altında şerit olarak bekler.
- Geniş ekranda (tablet, yatay telefon) deste 2–4 sütuna yayılır; kart genişliği
  ~320dp'nin altına düşmez (yatay telefonda ~270dp). Kısa ekranda kartlar da kısalır.
- **"Bugün" şeridi:** envanterin ana ekranında, kartların üstünde damga gibi küçük etiketler
  ilgi isteyenleri tek satırda toplar: **tarihi geçti**, **tarihi yaklaşıyor**, **bakım zamanı**,
  **alınacak**, **yerleştirilecek**, **kayıp**, **çekmecede**. Yalnızca sayısı sıfırdan büyük
  olanlar görünür; dokununca yeri açılır (tarihler sayfası, alışveriş listesi, kayıp ya da
  çekmece paneli).
  Hiçbiri yoksa şerit de yoktur; klasörlerin içinde ve yatay telefonda gösterilmez (orada
  aynı sayılar başlıktaki düğmelerde durur).
- **Klasör kapağı:** fotoğrafı olmayan klasör, içindekilerin fotoğraflarını gösterir: kartta
  üst üste konmuş en çok üç küçük baskı, liste satırında telefonun klasör simgesi gibi küçük
  bir ızgara (üç gözde fotoğraf, dördüncüde klasörün kendi simgesi). Önce klasörün kendi
  seviyesindeki kayıtlara, yetmezse alt klasörlere bakılır: yalnızca klasör tutan "Mutfak" da
  içini gösterir. Klasöre kendi fotoğrafı verilirse kapak odur (bantlı, büyük baskı); içinde
  fotoğraflı kayıt yoksa kart eskisi gibi sade kalır.
- **Küçük hareketler:** içerik değişince yenisi hafifçe kayarak yerine oturur: görünüm
  (deste ↔ liste) ya da sıralama değişince, sürükleyerek inilen klasörden geri dönünce,
  ayarlarda sekme değişince. "Bugün" şeridi belirirken deste zıplamaz, kayar; kartın − / +
  düğmesine basınca sayı kısa bir an büyür. Sürükleme sırasında hiçbir şey kıpırdamaz;
  telefonda "animasyonları kaldır" açıksa hareketler de yapılmaz.
- **Sıralama:** arama çubuğundaki ⇅ düğmesi (yatayda soldaki şeritte): **Benim sıram** (elle
  dizdiğin, varsayılan), **Ada göre (A–Z)** ("Adsız 2", "Adsız 10"dan önce), **Son eklenen üstte**,
  **Tarihi en yakın üstte** (son kullanma tarihi olanlar önce). Klasörler yine eşyalardan önce
  durur. Elle dizdiğin sıra silinmez: "Benim sıram"a dönünce aynen gelir. Başka bir sıralama
  seçiliyken düğme kiremit rengindedir ve kartlar sürüklenerek dizilemez (klasöre taşıma
  çalışır); araya bırakınca nedenini söyleyen bildirimdeki **Benim sıram** tek dokunuşla geri
  döndürür. Seçim her envanter için ayrı hatırlanır, bu cihaza özeldir.
- **Liste görünümü:** kalabalık bir klasörde aranan şeyi bir bakışta görmek için kartlar
  sık satırlara döner. Arama çubuğundaki QR'ın yanındaki **görünüm düğmesi** (yatayda soldaki
  şeritte) her dokunuşta sıradaki görünüme geçer: deste → liste → ızgara → deste; düğmenin
  simgesi dokununca geçilecek görünümü gösterir. Üçünden birini doğrudan seçmek için:
  Ayarlar → Bu envanter → Deste → **Görünüm**. Telefonda aynı ekrana destedekinin iki katına
  yakın kayıt sığar; geniş ekranda satırlar 2–4 sütun olur. Klasör satırı küçük bir klasör
  biçimindedir (solunda sekme), eşya satırı düz. Satırda kartın rengi, simgesi ya da
  fotoğrafının küçüğü, adı, alt satırı (yeri / içindeki sayı / son kullanma), en önemli damgası,
  ek sayısı, adet − / + ve ⋯ durur; not ve fotoğraf baskısı kartta kalır. Her şey aynı çalışır:
  dokunma, uzun basıp sürükleme (klasöre koyma, sıralama, çekmece), yana kaydırma, toplu seçim.
  Görünüm her envanter için ayrı hatırlanır (mutfak destede, kitaplık listede), bu cihaza özeldir;
  çekmece ve sık kullanılanlar panelleri de aynı görünüme uyar.
- **Izgara görünümü:** aynı düğmeyle (listeden sonraki dokunuş) kayıtlar yan yana karelere
  döner: üstte fotoğraf, altında ad. Fotoğraflı envanterde aranan şey adından önce resminden
  bulunur; telefonda üç sütun (dar telefonda iki, geniş ekranda daha çok) ve aynı ekrana
  destedekinin birkaç katı kayıt sığar. Klasör karosu klasör biçimindedir; fotoğrafı yoksa
  içindekilerin fotoğraflarını gösterir. Karoda en önemli damga, adet (yalnızca sayı; − / +
  dokununca açılan kartta), yıldız ve ⋯ durur. Dokunma, uzun basıp sürükleme ve toplu seçim
  aynı çalışır; sıralarken kart karonun sol yarısına bırakılırsa önüne, sağ yarısına
  bırakılırsa arkasına girer. Izgarada yana kaydırma (çöp / çekmece) yoktur: dar karoda kısa
  bir fiske yanlışlıkla çöpe atardı.
- **Yatay ekran ve tablet kendi düzeninde** (dikeyi yan yatırmak yerine):
  - Başlık tek satır ("1 · Ana ekran · 16 kayıt"), bütün sayfalarda.
  - Arama, QR ve **+** alttaki çubuk yerine sol kenarda dikey bir şeritte; alt çubuk yatayda
    destenin yarısını kapatıyordu.
  - Sağ kenar kulpları (kayıp, sık kullanılanlar, tarihi geçenler) başlıkta sayılı simgeler olur;
    çekmece simgesi zaten orada.
  - Çekmece ve öteki paneller desteyi karartmadan yanında açılır, deste daralır: kart desteden
    panele ya da panelden desteye doğrudan sürüklenir, panel sürüklerken açık kalır.
  - Kartlar kısa kalır: aynı ekrana dikey düzenin yatay halinin iki katı kayıt sığar. Kartın
    fotoğrafı başlık çizgisinin altına sıkışmaz, kartın boyunca uzanır (⋯ ve + sütununun solunda).
  - Düzenleyici iki sütun: solda canlı kart önizlemesi ve ad sabit, sağda bölümler kayar.
- **Ekranı döndür** (Ayarlar → Görünüm, kişisel, varsayılan açık): açıkken telefonun kendi
  otomatik döndürme ayarına uyulur (döndürmesi kilitli telefonda uygulama da dönmez; eskiden
  kilidi yok sayıp dönüyordu). Kapalıyken telefonda hep dikey; tablette yine döner.
- Klasör kartının sol üstünde sekmesi vardır; destede yalnızca üst şeridi
  görünse bile eşyadan ayrılır. Aynı seviyede klasörler önce, eşyalar
  "Eşyalar" etiketiyle ayrı bir grupta gelir; geniş ekranda eşyalar yeni satırdan başlar.
  Bu ayrım zorunlu değil: **Ayarlar → Bu envanter → Deste → "Klasörleri ve eşyaları ayır"**
  kapatılırsa hepsi tek sırada, senin dizdiğin sırayla durur.
- Klasör kartının altında içindekilerin küçük önizlemeleri, sağ üstünde (ortak
  kullanımda) sorumlusunun baş harfi durur.
- **Dolu işareti:** bir klasöre artık bir şey sığmıyorsa ⋯ → *Dolu işaretle*
  (ya da düzenleyicide *Yeri* panelindeki anahtar). Kartın başlık satırında —
  destede hep açık duran tek yerde — turuncu **Dolu** damgası çıkar, böylece yeni
  bir eşyaya yer ararken o klasörü elemek bir bakışta mümkün olur. İşaret
  kayıt sayısından bağımsızdır (kaydı olmayan eşyalarla da dolabilir); işaretliyken
  kartta "boş" yazmaz. Ortak kullanımda "doluluk" değişikliği olarak eşitlenir.
- Fotoğraf kartın düzenini değiştirmez: ad, simgeler, ⋯ ve + fotoğrafsız karttaki
  yerlerindedir. Fotoğraf kartın sağına, başlık satırının altından yapıştırılmış
  büyük, beyaz kenarlı bir baskı gibi durur; hafif eğiktir, üstünde yarı saydam kağıt
  bant (ortada tek ya da iki köşede çapraz; hangisi olduğu ve eğimi karta göre
  sabittir). Üst üste gelirlerse yazı ve düğmeler önde kalır.
- **Not** kartın üstünde yazar: eşyada fiş kartının satır çizgilerine oturur,
  klasörde başlığın altında durur. Kaç satır sığıyorsa o kadar gösterilir,
  gerisi "…" ile biter.
- **Adet:** bir eşyadan birden fazla varsa düzenleyicide adet tutulur (− / +, sayıya
  dokununca yazarak). Adet tutulan eşyanın kartında sağ altta − adet + durur; kart
  açılmadan sayı değişir. Adet 0 olunca kayıt silinmez, "Tükendi" yazar: sarf
  malzemesinin yeri kaybolmaz, stok gelince aynı kayıttan artırılır. Silmek
  isteyen ⋯ → Çöp kutusuna at der. Adet ortak kullanımda da eşitlenir ("adet"
  değişikliği olarak onaya düşer); aramada da görünür.
- **Yanlış dokunmaya karşı:** kartta − / + her dokunuştan sonra kısa bir bildirim çıkar,
  "Pil: 4 → 3 · Geri al" (art arda dokunuşlar tek bildirimde toplanır). Deste kayarken
  gelen − / + dokunuşu yok sayılır.
- **En az adet:** adet tutulan eşyada düzenleyicinin Adet panelinde **Azalınca listeye
  ekle** (− / +, sayıya dokununca yazarak). Adet o sayıya ya da altına inince kartta
  hardal renkli **Azaldı** damgası çıkar ve eşya alışveriş listesinin **Azalanlar**
  bölümüne girer. **Sınırı kaldır** ile kapatılır; adet tutmayı bırakmak onu da kaldırır.
- Klasör kartına dokununca kart büyüyerek içini kaplar.
- **Klasörler arasında gezinme:** klasörün içinde başlıktaki adına (yanında küçük bir ⌄ durur)
  dokununca üstündeki klasörler kökten başlayarak sırayla açılır: Ana ekran, Mutfak, Üst dolap…
  Birine dokununca doğrudan oraya gidilir; aradaki ekranlar kapanır, geri tuşu oradan yine birer
  birer yukarı çıkar. Aramadan, QR'dan ya da sık kullanılanlardan açılan klasörde de çalışır:
  ana ekrandan oraya kadar klasörler yeniden açılır, her destede gelinen yoldaki klasör öne gelir.
  Klasör çekmecedeyse listede çekmece de durur; dokununca ana ekranda çekmece paneli açılır.
- **Başka klasöre git…:** aynı menünün en altında. Klasör ağacı bulunulan klasörde açılır (taşırken
  çıkanın aynısı: üstte Ana ekran / Çekmece ve yol, klasöre dokununca içine girilir); **Buraya git**
  doğrudan oraya götürür. Başka daldaki bir klasöre (Mutfak › Üst dolap'tan Garaj › Raf 2'ye) ana
  ekrana dönmeden ve adını aramadan geçilir; ortak üst klasörlerin ekranları yerinde kalır, geri tuşu
  yeni yolda birer birer yukarı çıkar.
- **Geri okuna basılı tut:** derindeki bir klasörden tek hareketle ana ekrana dönülür (kısa
  dokunuş yine bir üst seviyeye çıkar).
- Her kartın sağ üstündeki **⋯** seçenekleri açar: kart öne çıkar. Hemen altında yan yana
  **dört hızlı eylem** durur: **Düzenle**, **Taşı** (yerini değiştir), **Sık kullanılan** ve
  eşyada **Listeye ekle** (alışveriş listesi), klasörde **QR kod**; açık olan (sık kullanılan,
  listede) kiremit renginde görünür. Onların altında kısa bir liste: seç, yerinde yok ve
  **Diğer**; en altta çöpe at. Seyrek kullanılanlar (eşyada QR kod, dolu işaretle, yalnızca
  bende tut, ek ekle) "Diğer"e dokununca yerinde açılır. Eşya kartına dokunmak da aynı
  katmanı açar.
- Ardışık kartlar dalga gibi dizilir: her kart bir öncekinden 4 dp kayık, 4 kart
  boyunca sağa, sonra 4 kart boyunca sola. Hepsi aynı hizada olunca kartlar
  birbirinden ayrı algılanmıyordu.

**Kayıt oluşturma / düzenleme**
- Boş ekrandaki artı kartı ilk klasörü açar; klasör adı boş bırakılırsa
  aynı seviyede sıradaki sayıyı alır (1, 2, 3...).
- Adı boş bırakılan eşya **Adsız 1, Adsız 2, Adsız 3…** diye kaydedilir (bütün envanterde);
  boşalan en küçük numara yeniden kullanılır: Adsız 2 silindiyse yenisi Adsız 2 olur,
  sonrakiler 4, 5 diye devam eder. Eskiden adsız kalmış eşya ilk düzenlemede numara alır.
- Klasör kartının üzerindeki artı doğrudan içine bir eşya kaydı başlatır.
- Düzenleyicide üstte canlı kart önizlemesi; **ad kartın başlığında, yerinde yazılır**
  (ayrı ad kutusu yok: başlığa dokununca klavye açılır, yeni eşyada kendiliğinden). Ad boşken
  alacağı ad silik görünür ("Adsız 3", klasörde sıradaki sayı). Kartın solundaki simgeye
  dokununca simge seçilir. Yazı alanının dışına dokununca ya da sayfayı kaydırınca yazma biter
  (imleç ve klavye kapanır). Kartın hemen altında **not** (kartta görünen şey o). Sonra hep açık
  duran iki panel: **Görünüm** (fotoğraf, **simge** — kategorilere ayrılmış ~110 simge —, satır
  içi renk seçici) ve **Yeri** (durduğu klasör, klasörde GPS konumu). Sağ üstteki **Kaydet**
  (tik) kaydeder.
- **Düzenleyici sade açılır.** Her kayıtta girilmeyen bölümler — **Adet**, **Alışveriş listesi**,
  **Tarihler**, **Ekler**, **Diğer** (eşya/klasör, yalnızca bende, QR kod, sorumlu) — en altta
  **Daha fazlası** başlığında birer düğme olarak durur; dokununca bölüm açılır ve görünür yere
  gelir. İçinde bilgi olan bölüm açık gelir (adedi tutulan eşyada Adet, tarihi olanda Tarihler,
  eki olanda Ekler). Yeni eşya yedi bölüm yerine kart, not, görünüm ve yerle açılır.
- Alttaki **+** eşya mı klasör mü diye sorar (iki küçük kart: fiş ve klasör).
- **Seri ekle** (aynı pencerenin üçüncü seçeneği): koli boşaltırken, oda dizerken birçok eşyayı
  birden eklemek için. Önce fotoğrafların nereden geleceği sorulur:
  - **Fotoğraf çek**: kamera açık kalır, eşyaları art arda çekersin; çekilenler altta küçük pullar
    olarak birikir. **Bitti**'de her pula yalnızca ad yazılır.
  - **Galeriden seç**: galeriden birden çok fotoğraf seçersin; her fotoğraf, adı fotoğrafın dosya
    adından (uzantısız) gelen bir eşya olur ("Vida kutusu.jpg" → "Vida kutusu"). Liste adlarıyla
    hemen açılır, fotoğraflar arkadan alınırken üstte ilerleme çubuğu görünür ("Fotoğraflar
    alınıyor: 34 / 200"); alınamayan olursa listeden düşer ve sayısı söylenir. Adlar eklemeden önce
    değiştirilebilir; **Galeriden ekle** ile yenileri eklenir.

  Boş kalan ad "Adsız N" olur, istersen hedef klasör değiştirilir, **N eşyayı ekle** ile hepsi o
  klasöre girer. Kart rengi fotoğrafın tonundan, görüntüyle arama izi arka planda hazırlanır;
  eklerken bitmeyen hazırlık altta ilerleme çubuğuyla gösterilir ("Hazırlanıyor: 120 / 200").
  Çıkarılan ya da vazgeçilen fotoğrafın kopyası silinir (galerideki asıl fotoğrafa dokunulmaz).
- Alttaki arama kutusunun sağındaki simge QR'ı doğrudan okutur.
- Fotoğraf seçilince kart rengi, rengi elle seçilmediyse fotoğrafın baskın tonuna
  en yakın palet rengine ayarlanır.
- **Fotoğrafa dokununca tam ekran açılır** (destedeki kartta, karta dokununca açılan
  büyük kartta ve düzenleyicinin önizlemesinde): iki parmakla büyütülür ve kaydırılır,
  çift dokunuş dokunulan yere yakınlaşır ya da geri döner, tek dokunuş üst çubuğu
  gizler; geri tuşu ya da ✕ kapatır. Toplu seçim açıkken dokunuş seçimi değiştirir.
- Konum: klasörde dünyadaki yeri (GPS, otomatik ya da elle); eşyada ise hangi
  klasörde durduğu (yer seçiciden seçilir, aşağıda).
- **Ölçü birimi:** Adet bölümünde isteğe bağlı ölçü birimi seçilebilir (adet, kg, g, lt, m,
  cm, kutu, paket vb. ya da elle yazılan özel birim). Kartlarda, odak görünümünde ve dökümlerde
  sayıyla birlikte görünür ("5 kg", "12 paket").
- **Periyodik bakım ve servis geçmişi:** Alet, cihaz ya da araç için (klasörde de olur: araba,
  akvaryum) düzenleyicide "Daha fazlası" → **Bakım**: döngü ("3 ayda bir"), ne yapılacağı ("Filtreyi
  temizle") ve son bakım günü (döngü kurulurken bugün önerilir, değiştirilebilir). Sonraki bakım
  günü bundan hesaplanır. Zamanı yaklaşınca (döngünün dörtte biri kadar önce, en çok bir hafta)
  ana ekrandaki **Bugün** şeridinde "bakım zamanı" etiketi çıkar (gecikmişse kırmızı), bakım günü
  sabah 9'da telefon bildirimi gelir, **Tarihi yaklaşanlar** sayfasında "Bakım zamanı" ve "Bakım
  takvimi" bölümleri durur. Karta dokununca açılan büyük kartta ve o sayfada **Bakım yapıldı**
  tek dokunuştur: son bakım bugün olur, geçmişe bir satır girer, bildirimden geri alınır. Satın
  alma, son kullanma ve garanti tarihlerine dokunmaz. Geçmiş düzenleyicide: eski bir bakım **Kayıt
  ekle** ile günü ve isteğe bağlı notuyla ("Servis: Ahmet usta, 1500 ₺") girilir, yanlış kayıt
  silinir. Döngüsü olmayan eşyada da geçmiş tutulabilir (onarım kaydı). Ortak kullanımda eşitlenir:
  biri döngüyü değiştirirken öteki "bakım yapıldı" derse ikisi de kalır.
- **Emanet ve ödünç takibi:** Bir eşya başkasına verildiğinde kartın ⋯ menüsünden, odak ekranından
  veya düzenleyiciden "Emanet ver" seçilebilir. Kime verildiği (daha önce verilen kişiler listelenir)
  ve isteğe bağlı teslim tarihi belirlenir. Eşya fiziksel ağaçtaki yerinde kalır; kartında ve odak
  görünümünde kime verildiği damgalanır (vadesi geçmişse kırmızı uyarı). Sol menüden açılan
  **Emanettekiler** sayfasında veya "Bugün" şeridinde gecikenler ve aktif emanetler takip edilir,
  tek dokunuşla geri alınır.
- **Değer, sigorta ve taşınma dökümü:** Eşyayı düzenlerken "Daha fazlası" → **Değer** ile bir
  tanesinin fiyatını (alış bedeli ya da biçtiğin değer) ve para birimini, ayrıca cihazın **seri /
  model numarasını** yazarsın. Tutar "1.250,50" de "1250.5" de yazılabilir; adet tutulan eşyada
  toplam adetle çarpılır. Klasörün odak görünümünde içindekilerin değeri, sol menüdeki **Değer**
  sayfasında envanterin toplamı, yerlere (en üstteki klasörlere) göre dağılım, en değerli eşyalar
  ve fiyatı girilmemiş eşyalar görünür. **Değer dökümü (PDF)** sigorta ve taşınma için eşyaları
  yerleri, adetleri, birim fiyatları, tutarları, seri numaraları ve alış tarihleriyle listeler; yer
  yer ara toplam ve genel toplam verir, fiyatı olmayanları ayrıca sayar. Tek bir klasörün dökümü o
  klasörün dışa aktarma menüsünden alınır; CSV dökümünde de fiyat, tutar, birim ve seri no
  sütunları var. Para birimleri ayrı toplanır, kur çevrimi yapılmaz (sunucu yok). Yeni fiyatların
  birimi: Ayarlar → Bu envanter → Değer (boşsa arayüz Türkçeyse TRY, değilse telefonun
  bölgesinden). Fiyat ve seri no ortak kullanımda eşitlenir; seri no aramada da bulunur.

**Taşıma**
- Karta uzun basmak taşıma modudur: titreşimle kart parmağın altında kalkar ve
  üstünde "Taşımak için sürükle" yazar; parmak kıpırdayınca "Bir klasörün
  üzerine bırak" olur. Kıpırdamadan bırakmak taşımayı iptal eder.
- Bir klasörün üzerinde kısa bir süre beklersen o klasörün içine inilir;
  daha derine aynı şekilde devam edebilirsin. Ekranın boş zeminine bırakmak o an
  açık olan klasöre koyar.
- **Her taşıma geri alınır:** kart başka bir yere gidince çıkan bildirimde **Geri al** durur
  (5 sn); kart eski yerine ve eski sırasına döner. Klasöre, seviyenin zeminine, "Üst seviye"ye,
  çekmece ve kayıp kulbuna bırakmada, "Yerini değiştir"de ve klasörün içindekileri aktarmada
  aynı. (Aynı seviyede sıra değiştirmek bildirim çıkarmaz.)
- Sağ kenarda **Çekmece** kulbu (yeri henüz belli olmayanlar) durur; kayıp eşya varsa
  altında **Kayıp**, sık kullanılan varsa **Sık kullanılanlar** kulbu da çıkar. Sürüklerken kenar ikiye bölünür (çekmece ve kayıp);
  karta hangisine bırakırsan oraya gider. Çekmeceyi üst çubuktaki simge de açar ve
  kapatır. Üst çubukta yalnızca bu simge ve (ortak kullanımda) zil durur; tarihi
  yaklaşanlar, alışveriş listesi ve ortak kullanım sol menüde.
- **Çekmecenin içinde düzenleme.** Çekmecedeki bir kartı sürüklemeye başlayınca
  çekmece **açık kalır**: kartları kendi aralarında sıralayabilir, çekmecedeki bir
  klasörün üzerine bırakabilirsin. Kartı asıl yerine götürmek istediğinde sol
  kenardaki ince şeride (arkadaki destenin göründüğü yer) taşı — çekmece kenara
  çekilir. Fikrini değiştirirsen sağ kenardaki **Çekmece** kulbunda bir an bekle,
  panel yeniden açılır; kart hâlâ elinde olur.
- **Klasör bırakınca sorulur.** İçinde kayıt olan bir klasörü başka bir klasöre
  ya da çekmeceye bıraktığında — kartın üstüne, aralığa, klasörün *içine girip*
  zemine ya da "Üst seviye" noktasına, fark etmez — iki seçenek çıkar: *Klasörü taşı* (klasör
  içindekilerle birlikte gider) ya da *Yalnızca içindekileri aktar* (kayıtlar
  geçer, klasör **boş olarak** yerinde kalır; sıraları korunur). Boş klasör
  sormadan taşınır.
- **Sıralama:** sürüklediğin kartı bir kartın **üst kenarına** getirirsen araya
  girecek yeri gösteren kiremit bir çizgi çıkar; bıraktığın yerde durur. Eşya
  kartının üst yarısı önüne, alt yarısı arkasına; klasör kartının ince üst/alt
  şeridi sıralama, ortası "içine koy" olarak kalır. Klasörler ve eşyalar ayrı
  gruplanıyorsa kart yalnızca kendi grubunda sıralanır (ayrım kapalıyken her yere).
  Başka bir seviyeden gelen kart da önce oraya taşınır, sonra bıraktığın sıraya girer.
- Sürüklenen kart destenin **üst ya da alt kenarında** tutulursa deste kendiliğinden
  o yöne kayar (yavaş başlar, hızlanır): o an ekranda görünmeyen bir klasöre de
  ulaşılır. Kenarda beklerken altından geçen klasörün içine girilmez; kaydırma
  durunca üzerinde beklemek yine içine sokar.
- Sürüklerken ekranın altında iki nokta belirir:
  - **✕ Vazgeç** — kart oraya bırakılınca hiçbir şey taşınmaz, kayıt yerinde kalır.
    İstemeden bir klasöre girildiğinde çıkış yolu budur.
  - **↑ Üst seviye** — altında hangi seviyeye çıkılacağı yazar. Üzerinde beklemek
    sürükleme bozulmadan bir üst seviyeye çıkarır (üst üste beklersen kök seviyeye
    kadar); bırakmak kaydı doğrudan o seviyeye taşır.

**Toplu seçim**
- Birden çok kartı birlikte taşımak, çöpe atmak ya da etiketini basmak için: bir
  kartın ⋯ menüsünden **Seç** (ya da klasör ekranının ⋮ menüsünden **Seç**).
- Seçim açıkken kartlara dokunmak onları seçer ya da seçimden çıkarır; seçili kartın
  tür simgesinin yerinde kiremit bir tik, kenarında kiremit çerçeve olur. Sürükleme,
  yana kaydırma ve kartın ⋯ / + düğmeleri bu sırada çalışmaz.
- Başlıkta kaç kayıt seçildiği, sağda **Tümünü seç** (hepsi seçiliyken seçimi
  boşaltır); soldaki ✕ ya da geri tuşu seçimi bitirir.
- Alt çubuğun yerinde dört eylem: **Taşı** (yer seçiciden, aşağıda),
  **Çekmeceye**, **Etiket** (seçilenlerin QR etiket sayfası) ve **Çöpe**. Taşıma ve
  çöpe atma bildirimdeki **Geri al** ile geri alınır.
- Seçilen bir klasörün içinden de kayıt seçildiyse o kayıt klasörüyle birlikte
  gider, klasörden çıkarılmaz. Klasör kendi içine taşınamaz; o klasör atlanır.
- Taşınanlar hedefte kendi aralarındaki destedeki sırayı korur (hangisine önce
  dokunduğun fark etmez). **Geri al** her kaydı eski yerine ve eski sırasına koyar;
  kayıp olan yeniden kayıp olur.

**Yer seçici** (Taşı, Yerini değiştir, Yerini biliyorum, düzenleyicideki Yeri)
- Dosya yöneticilerindeki "taşı" gibi çalışır: kayıtların durduğu klasörde açılır
  (kayıp eşya son görüldüğü yerde). Üstte yol yazar ("Ana ekran › 1 › Dolap");
  **↑** bir üst klasöre çıkarır, yolun herhangi bir parçasına dokunmak doğrudan
  oraya çıkarır. **Ana ekran** ve **Çekmece** iki düğme olarak hep üstte.
- Listede bakılan yerin klasörleri durur (alt klasörü olanın altında "3 klasör"
  yazar); dokununca içine girilir. Taşımak için alttaki **Buraya taşı**. Kayıtlar
  zaten oradaysa düğme "Zaten burada" der ve basılmaz; taşınan klasörlerin kendisi
  ve içi listede görünmez (kendi içine taşınamaz).

**Kartı yana kaydırma**
- Kartı **sola** kaydırmak çöp kutusuna atar, **sağa** kaydırmak yeri belirsizlerin
  beklediği çekmeceye alır (e-posta kutularındaki gibi). Kart parmakla birlikte
  kayar, arkasından eylemin renkli paneli çıkar; kartın genişliğinin ~%30'u
  geçilince titrer ve bırakınca çalışır, yetmezse kart yerine döner. Hızlı bir
  fiske de yeter.
- İkisi de geri alınabilir: bildirimde **Geri al** çöpten çıkarır ya da kaydı eski
  yerine (kayıpsa kayıp durumuna) döndürür.
- Zaten çekmecede duran kart sağa kaydırılmaz (gidecek yeri yok); o yönde kart
  biraz oynar ama gitmez.
- Uzun basıp sürükleme bozulmaz: kısa ve yatay hareket kaydırmadır, parmağı
  kıpırdatmadan beklemek taşımayı başlatır.

**Sık kullanılanlar**
- İç içe klasörlerin dibindeki bir eşyaya ya da klasöre her seferinde tek tek
  girmemek için: ⋯ → **Sık kullanılanlara ekle**. Kartın başlık satırında küçük bir
  yıldız belirir.
- Sağ kenarda (çekmece ve varsa kayıbın altında) yıldızlı, adaçayı yeşili bir kulp
  çıkar — yalnızca en az bir kayıt eklendiyse; çekmecenin kağıt tonundan ve kayıbın
  hardalından ayrılır ama göz almaz. Kulp tek dokunuşla paneli açar; sol menünün üstündeki
  **Sık kullanılan** düğmesi de açar.
- Panelde kartlar kendi renk ve fotoğraflarıyla durur, alt yazılarında nerede
  oldukları yazar ("Ana ekran / Mutfak"). Karta dokunmak klasörü doğrudan açar;
  ⋯, adet − / + ve sürükleyip taşıma da buradan çalışır.
- Sürüklenen bir kartı panelin üstüne bırakmak da sık kullanılanlara ekler.
- **Liste bu cihaza özeldir.** Kayıtların kendisinde değil, cihazın ayarlarında
  durur; eşitleme yükünde (kayıtlar + silme izleri + üyeler) ve dışa aktarılan yedek
  dosyasında yer almaz. Yani ortak kullanım başlatıldığında ya da yeni biri
  katıldığında kimse senin kısayollarını görmez, herkesin kendi listesi olur.
  Panelin üstünde de "yalnızca bu cihazda" yazar.
- Sık kullanılan bir kayıt çöpe atılırsa listede görünmez ama kimliği durur (geri
  alınabilir); kalıcı silinince listeden de düşer.

**Kayıp çekmecesi**
- Bir eşya yerinde yoksa ⋯ → **Yerinde yok**: *Kayıp olarak bildir* ya da *Çöpe at*.
- Kayıp eşya kayıp çekmecesine gider, son yeri saklanır ("Son yeri: Mutfak / Üst dolap"),
  kartında turuncu soru rozeti olur; sağ kenarda sayısıyla hardal renkli **Kayıp**
  kulbu çıkar (sol menüde de sayı durur).
- Ortak kullanımda kayıp bildirimi onay beklemeden herkese ulaşır ve bildirim
  olarak görünür. Yerini bilen **Yerini biliyorum** ile bir klasör seçer (ya da
  kartı kayıp çekmecesinden bir klasöre sürükler); "buldu" haberi de herkese gider.

**QR**
- Her kayda özel `envanter://container/<id>` ya da `envanter://item/<id>` kodu üretilir.
- Kod resim olarak paylaşılabilir; yazdırıp kutunun üzerine yapıştırmak için.
- **QR etiket sayfası:** klasör ekranının ⋮ menüsünden **QR etiketleri** (ya da toplu
  seçimde **Etiket**) bir A4 PDF hazırlar: her etikette QR, kaydın adı, yeri ve
  kart renginde ince bir şerit; etiketler arasında kesik kesim çizgisi. Üç boy var:
  küçük (sayfada 24), orta (12), büyük (6); yandaki küçük sayfa önizlemesi boyu
  gösterir. Klasörden açılınca klasörün kendisi ve alt klasörleri gelir, istenirse
  **Eşyalar da**. PDF paylaşım penceresiyle yazıcıya, Drive'a ya da e-postaya gider.
  QR vektör çizilir, baskıda keskin kalır; Türkçe harfler için uygulamanın kendi
  yazı tipleri PDF'e gömülür.
- **Koli ve içerik dökümü:** Klasörün ⋮ menüsünden ya da odak katmanından **İçerik dökümü**
  seçilerek koli veya odanın tüm içeriği yazdırılabilir A4 PDF tablosu (kolinin QR kodu, adı
  ve içindeki eşyaların adet/birim/durum listesi) ya da Excel uyumlu UTF-8 CSV dökümü olarak
  dışa aktarılabilir.
- **Envanterler arası aktarma / kopyalama:** Odak katmanından veya toplu seçim çubuğundan
  **Aktar** seçeneğiyle seçilen kayıtlar, bağlı fotoğrafları ve ekleriyle birlikte başka bir
  envantere taşınabilir ya da kopyalanabilir. Kopya ayrı bir kayıttır: aynı klasörü ikinci kez
  kopyalamak öncekine dokunmaz. Taşınan kayıt kimliğini korur, basılı QR etiketi yeni yerinde de
  çalışır (hedef envanter kapalıyken de bulunur); kaynakta "Son silinenler"de 30 gün durur.
- Aramadaki **QR okut** ile: klasör kodu o klasörü açıp içini gösterir; eşya
  kodu klasörü açmadan eşyanın kartını öne çıkarır. Başka bir envanterin etiketiyse
  ("Ev" açıkken Atölye'deki kutu) o envantere geçilir ve kayıt gösterilir.
- **Ürün ve klasör barkodu:** aynı tarayıcı ürünlerin ve kutuların/kolilerin barkodunu da okur (EAN-13, EAN-8, UPC, Code 128,
  Code 39). Eşyaya veya klasöre barkod kaydetmek: düzenle → **Barkod** (satıra dokununca elle
  yazılır, kamera düğmesiyle okutulur). Sonra barkodu okutmak kaydı bulur ve öne çıkarır;
  aynı barkod birkaç kayıtta varsa yerleriyle listelenir, birini
  seçersin. Başka bir envanterdeyse oraya geçilir. Hiçbir yerde kayıtlı değilse **Bu barkodla
  yeni eşya** veya **Bu barkodla yeni klasör** önerilir: düzenleyici barkodu yazılmış olarak, tarayıcıyı açtığın klasörde
  açılır. Barkodun rakamlarını aramaya yazmak da kaydı bulur. Ürün adı internetten
  çekilmez (uygulama sunucusuzdur); adı sen verirsin. Barkod ortak kullanımda eşitlenir.
- **Seri sayım modu:** Aramadaki tarayıcının üst çubuğundaki liste simgesiyle açılır. Sayfadan
  çıkmadan barkodlar art arda okutulabilir; kayıtlı eşyanın stoğu her okutuşta anında 1 artırılır
  (kartın + düğmesi gibi: paketli eşyada en yeni pakete, adedi tutulmayan eşyada 1'den başlar),
  ekranda güncel adet ve eşya adı gösterilir. Klasörün ve çöpteki kaydın adedi değişmez. Sayımın ve
  düzenleyicinin tarayıcısında bu düğme yok.
- **Hızlı sayım & denetim sihirbazı:** Klasörün ⋮ menüsünden, ana ekran üst menüsünden ya da
  sol çekmeceden **Sayım / denetim** seçilerek başlatılır. Belirli bir klasör (açılan seçicide
  klasöre girip **Burayı say**) veya tüm envanter kapsamında beklenen eşyalar listelenir. Kamera ile
  barkod okutularak ya da ekrandaki tek dokunuşlu "Doğrula" / adet stepper butonlarıyla sayım
  yapılır. Başka bir klasörden çıkan eşyalar otomatik tespit edilir. Kayıtlı olmayan bir barkoddan
  yeni eşya eklenirse sayılmış olarak listeye girer; o ana kadarki sayım yerinde kalır. Sayım sonunda
  başlıktaki **Tamamla** ile mutabakat ekranı açılır: adet sapmaları kaydın o anki haline uygulanır
  (paketli eşyada en eski paketten düşülür; sayım sürerken başka telefondan gelen değişiklik ezilmez),
  eksik eşyalar (kayıp olarak işaretleme, alışveriş listesine ekleme veya çekmeceye kaldırma) topluca
  yönetilir, başka yerden çıkan eşyalar ise sayılan klasöre taşınır.
- Tarayıcı kamerayı kendi yönetir: ekrandan çıkarken kamerayı bırakır, uygulama
  arka plandan dönünce yeniden açar, bir sonraki tarama önceki ekranın kamerayı
  bırakmasını bekler. Açılamazsa ham hata yerine kısa bir açıklama ve **Yeniden
  dene** çıkar.

**Görüntüyle arama**
- Aramadaki **Görüntüyle ara**: elindeki eşyanın fotoğrafını çekersin (ya da
  galeriden seçersin), envanterdeki kart resimleriyle karşılaştırılır; yeterince
  benzeyen yoksa "bulunamadı" der.
- Sayfa açılır açılmaz kamera açılmaz: önce ne yapacağın sorulur, istersen geri
  dönersin. Kamera beklenirken de **Vazgeç** vardır; kameradan vazgeçmek seni
  sayfadan atmaz, seçim ekranına döndürür.
- Arama fotoğrafı envanterin parçası değildir: karşılaştırma biter bitmez diskten
  silinir, sonuç ekranındaki önizleme bellekteki kopyadan çizilir.
- Model ya da internet kullanmaz, tamamen cihazda çalışır. Kayıtlı her resimden bir
  renk düzeni ızgarası çıkarılır; bu ızgara çekilen fotoğrafın içinde farklı boyut ve
  konumlarda aranır ve ışıktan etkilenmeyen normalize korelasyonla puanlanır.
- Aynı eşyanın benzer yönden çekilmiş fotoğraflarında iyi çalışır. Çok farklı bir
  açı ya da eşyanın büyük kısmının örtülmesi onu yanıltır.

**Ortak kullanım (yerel ağ)**
- Sol menü ya da Ayarlar → **Ortak kullanım** sayfası (menüdeki satırda ağdaki üye
  sayısı yazar). Varsayılan olarak kapalı.
- Açıkken envanter aynı Wi-Fi ağında adıyla görünür. Katılmak isteyen, sayfadaki
  **Ağı tara** ile ağdaki envanterleri bulur ve **Katıl** der. Ağ sürekli taranmaz;
  tarama birkaç saniye sürer.
- İstek, envanterin sahibine (ya da bir ana kullanıcıya) hangi ekranda olursa olsun
  sorulur. Kabul edilirse envanter katılana onaysız gelir.
- **Katılırken ayrı envanter:** açık envanterinde kayıt varsa **Yeni envanter olarak
  katıl** önerilir: boş bir envanter açılır (adı katılınan envanterin adı), istek
  oradan gider, buradaki kayıtların karışmaz. Kabul edilmezse o boş envanter silinir,
  öncekine dönülür. İstenirse **Bununla birleştir**: kayıtların ortak envantere eklenir.
- Aynı sayfada üyeler (ağda mı değil mi, kim yönetici, kim varis, kim ana kullanıcı, kim
  nerenin sorumlusu), son eşitleme ve "Ortaklıktan ayrıl". Ağda olmayan üyenin satırında
  onunla en son ne zaman eşitlenildiği yazar ("en son 3 gün önce eşitlendi"). Bir üyeyle
  eşitleme olmuyorsa satırında nedeni yazar: "Son eşitleme olmadı: cihaza ulaşılamadı"
  (ya da yanıt gelmedi, istek reddedildi, karşı cihazda bir hata oluştu). Eşitleme yarım
  dakikada bir yeniden denenir; geçici bir kopukluk kendiliğinden düzelir.
- **Üye çıkarma:** ana kullanıcı, ana kullanıcı olmayan bir üyeyi satırındaki ⋮ →
  **Ortak kullanımdan çıkar** ile çıkarır. Çıkarılan cihaz ağdaysa hemen, değilse bir
  sonraki eşitleme denemesinde öğrenir: "Ortak kullanımdan çıkarıldın" der, kendi
  envanterine döner; kayıtları onda kalır ama artık eşitlenmez. Yeniden katılmak
  isterse istek yine onaya düşer. Çıkarma bilgisi üye listesiyle bütün cihazlara yayılır.
- **Ayrılma:** herkes (yönetici ve ana kullanıcılar da) **Ortaklıktan ayrıl** diyebilir;
  ağdaki üyelere son bir eşitlemeyle bildirilir, ağda olmayanlar sonra öğrenir. Yönetici
  ayrılırken (ya da paylaşılan envanteri silerken) envanteri kimin yöneteceğini seçer;
  varis listede en üstte durur. Diğerlerine "Ayşe envanteri sildi" / "ayrıldı" haberi gider,
  onların kopyası yerinde kalır.
- **Değişiklikler onayla gelir.** Başkasının yaptığı değişiklik hemen uygulanmaz:
  üst çubuktaki zilde sayı olarak görünür, kısa bir bildirim çıkar, değişen kartta
  turuncu bir nokta belirir. Zile dokununca liste açılır ("Ayşe taşıdı: Mutfak →
  Balkon", "eski adı: Blender"...). Tek tek ya da **Tümünü kabul et**; reddedilen
  değişiklikte senin sürümün kalır ve diğerlerine de gönderilir (reddedilen yeni
  kayıt çöpe gider). Birlikte eklenen bir klasör ve içindekiler tek satırdır.
- **Değişiklikleri otomatik kabul et** (ayarlarda ve ortak kullanım sayfasında) açılırsa
  onay sorulmaz. Yine de başkasının **kalıcı silmesi** (sende görünen bir kaydın) ve tek
  eşitlemede **5 ya da daha çok kaydın çöpe gitmesi** (dolu klasör içindekileriyle sayılır)
  her zaman sorulur, ana kullanıcıdan gelse de: biri yanlışlıkla çöpü boşaltınca ya da bir
  klasörü atınca herkesin telefonundan anında gitmesin. Zaten çöpte olanın kalıcı silinmesi
  sorulmaz (aşağıda: Son silinenler).
- **Kişi bazında güven:** üye satırındaki ⋮ → **Değişiklikleri sormadan gelsin**: o kişinin
  değişiklikleri onay beklemez (bu cihazın kararı, satırında "sormadan" yazar). Kalıcı ve
  toplu silmeler yine sorulur. Ana kullanıcınınkiler zaten sormadan gelir.
- **Adet ve alışveriş listesi sormadan gelsin** (onaylı modda, varsayılan açık): yalnızca
  adedi (paketleriyle) ya da alışveriş listesindeki yeri değişen kayıt onay beklemez; her
  birini onaylamak yoruyordu, sonunda "Tümünü kabul et"e basılıyordu.
- **Reddedilen değişikliğin haberi:** reddettiğin değişikliği yapan kişinin telefonunda
  "Ali, “Kalem” kaydındaki değişikliğini geri çevirdi" çıkar; o an ağda değilse sonraki
  eşitlemede (haber üye listesi gibi herkese yayılır, yalnızca yapanda görünür, 14 gün sonra
  düşer). Yoksa aynı değişikliği tekrar tekrar yapardı.
- **Yanlış saat:** birleşmede son yazan kazandığı için saati yanlış bir telefon değişikliği
  yanlış sıraya koyar. Eşitlemede saatler karşılaştırılır: saati otomatik olmayan (elle
  ayarlanmış) telefon, saati otomatik olan bir üyeyle eşitlenirken farkı öğrenir ve kendi
  değişikliklerini düzeltilmiş saatle kaydeder. 2 dakikadan büyük fark bir kez söylenir
  ("Bu telefonun saati 12 dk geri; eşitlemede Ayşe'nin saatine göre düzeltiliyor") ve üye
  satırında "saat farkı 12 dk" yazar. Farkı öğrenmeden önce yazılanlar olduğu gibi kalır.
  Saatler çok farklı olsa da (5 dakikadan fazla) eşitlenir: istekler karşının saatine göre
  yeniden imzalanır. Eskiden böyle iki telefon ortaklık kurabiliyor ama envanter hiç
  gitmiyordu; iki telefonda da bu sürüm (1.3.2+18) ya da yenisi olmalı.
- **Uygulama kapalıyken de eşitlenir.** Android yarım saatte bir, telefon Wi-Fi'deyken
  kısa bir eşitleme turu yapar (40 saniyeye kadar; açık envanter paylaşılıyorsa): iki
  telefonun uygulamayı aynı anda açık tutması gerekmez, biri açıkken öteki arka planda
  eşitlenir. Uygulama o sırada açılırsa tur yarıda kalır, uygulama beklemez. Kapalı
  (açık olmayan) envanterler arka planda da eşitlenmez.
- **Roller.** Envanteri kuran **yönetici**dir. Yönetici üyeleri **ana kullanıcı** yapabilir,
  bir **varis** seçebilir ve yöneticiliği **devredebilir** (üye satırındaki ⋮); devreden
  otomatik olarak yeni yöneticinin varisi olur. Varis ana kullanıcı yetkisindedir:
  değişiklikleri onaylar, katılma isteklerini kabul eder, üye çıkarır, sorumlu atar, başkasını
  ana kullanıcı yapar; ama yönetici olana dek kendisi varis seçemez. Yönetici kimseyi
  seçmeden ayrılırsa yönetim varise geçer. Yönetici olan cihaz bunu açıkça söyler, ötekiler
  kısa bir bildirim görür. Bir klasöre **sorumlu** atanabilir (düzenleyicide "Sorumlu ata"; ör. Mutfak → Ayşe).
  Ana kullanıcının her yerde, sorumlunun kendi klasöründe ve içinde yaptığı
  değişiklikler diğerlerine onaysız uygulanır ve "yetkili olduğu için uygulandı"
  diye bildirilir. Sorumlunun bir değişikliği reddetmesi de herkese geçer; yani o
  klasörde son söz ondadır. Ana kullanıcılar katılma isteklerini de onaylayabilir.
- Fotoğraflar yalnızca karşıda yoksa aktarılır; onay bekleyen değişikliğin yeni
  fotoğrafı listede önizlenebilsin diye önceden alınır.
- **Aynı kayıt iki tarafta değiştiyse alan alan birleşir:** Ayşe adedi, Ali adı
  değiştirdiyse ikisi de kalır. Aynı alan (ör. ikisi de adı) değiştiyse son yazan
  kazanır. Kaydın yeri (klasörü, çekmece, sırası, kayıp işareti) tek parça sayılır;
  eşya iki yerde birden olmaz. Onay listesinde yalnızca gerçekten karşıdan gelen
  alanlar görünür; aynı kayda gelen birkaç değişiklik tek satırda toplanır. Ret
  yalnızca reddedilen alanları geri çevirir. Kalıcı silmeler iz olarak
  taşınır. Birleşme sonrası yeri kaybolan ya da çapraz taşımayla döngüye giren
  kayıtlar kaybolmaz, çekmeceye alınır.
- **Farklı sürümdeki uygulamalar eşitlenmez.** Eski uygulama yeni alanları (tarihler,
  "Ayşe'de") tanımaz; o kaydı değiştirirse kaydın bütünü geri gider ve bu alanlar
  herkeste silinirdi. Bu yüzden her cihaz duyurusunda ve her eşitleme isteğinde veri
  sürümünü söyler; sürümler farklıysa durum ne verilir ne alınır. Bildirim ve üye
  satırı kimin güncellemesi gerektiğini söyler ("Ali'nin uygulaması eski sürüm");
  güncellenince eşitleme kendiliğinden sürer. Bu denetimden önceki sürümler (1.1 ve
  öncesi) sürüm söylemediği için eski sayılır.
- **Değişmeyen konuşulmaz.** Her cihaz duyurusunda envanterinin küçük bir özetini
  (kayıt sayısı, kayıtların kimlik+zaman karmaları, silme izleri, üyeler/roller)
  taşır. İki tarafın özeti son eşitlemedekiyle aynıysa envanter boşuna gidip
  gelmez; bir şey değişince özet de değişir ve eşitleme kendiliğinden başlar.
  Eksik fotoğrafı olan taraf yine konuşur.
- Durum yalnızca **kabul edilmiş üyelerle** paylaşılır: duyurular imzasız olduğu
  için ağdaki herkes envanter kimliğini görebilir, ama üye listesinde olmayan bir
  cihaza envanter gönderilmez. Zaten üye olan bir cihazın yeniden katılma isteği de
  ortak anahtarla imzalanmadıkça onaysız kabul edilmez.

**Tarihler: satın alma, son kullanma, garanti**
- Eşyanın düzenleyicisinde **Tarihler** bölümü: satın alma tarihi, son kullanma tarihi,
  raf ömrü, son kullanmaya kala uyar, garanti bitiş tarihi ve garanti süresi. Tarihler
  takvimden seçilir; süreler gün / hafta / ay / yıl olarak (sık kullanılanlar tek dokunuş:
  1 hafta, 1 ay, 3 ay, 6 ay, 1 yıl, 2 yıl). Dolu bir tarih ✕ ile silinir.
- **Son kullanma tarihi yazmayanlar** (muz, elma): son kullanma tarihi boş bırakılıp raf
  ömrü girilir; son kullanma = satın alma tarihi + raf ömrü. Satır hesaplananı gösterir
  ("Hesaplanan: 27 Eyl 2026"). Paketteki tarih girilirse o geçer.
- **Farklı tarihli paketler** (6 yoğurt: 2'si 5 Eki, 4'ü 12 Eki): adet tutulan, tarihli
  eşyada Tarihler bölümündeki **Farklı tarihli paket ekle** (kaç tane, sonra tarih). Her
  paket kendi satırında adediyle durur; tarihe dokununca değişir, adedi 0 olan paket kalkar.
  Adet paketlerin toplamıdır; kartta en yakın tarih yazar, yanında "+1 tarih".
  - Kartta **−** tarihi geçmemiş en eski paketten düşer (önce o açılır); bozulmuş olan
    "kullanıldı" sayılmaz, o **Tarihi geçenleri at** ile gider (hepsi geçmişse − yine de
    ondan düşer). **+** en yeni
    pakete girer; çıkan bildirimdeki **Başka tarih** ile farklıysa düzeltilir. Raf ömrü
    olan eşyada eklenen bugün alınmış sayılır, tarihi ondan hesaplanır.
  - Alışveriş listesinde **Yerleştir**: kaç tane alındıktan sonra yenilerin tarihi sorulur,
    ayrı paket olur (eldekiler kendi tarihinde kalır).
  - Bir kısmının tarihi geçince kartta **"2 tanesi geçti"** damgası çıkar, eşya **Tarihi
    geçenler**'de işaretlenir; kartın ⋯ menüsündeki **Tarihi geçenleri at** yalnızca onları
    atar. Yenisini almak gerekiyor (alışveriş listesi) ancak hepsinin tarihi geçince sayılır:
    5 yoğurdun biri bozulduysa gerisi duruyor; azalınca en az adet haber verir.
  - Her paketin tarihi ayrı bildirilir. Tek tarih kalınca eşya yine tek tarihli görünür.
- **Garanti**: bitiş tarihi verilmediyse satın alma tarihi + garanti süresi.
- **Uyarı**: genel olarak son kullanma tarihine en çok **3 ay** kala uyarılır; Ayarlar →
  Tarihler → **Son kullanma uyarısı** ile değişir (bu tercih cihazda kalır). Kısa ömürlüde
  uyarı ömrünün **dörtte biri** kala gelir (ömür: alındığı, bilinmiyorsa eklendiği günden son
  tarihe): bugün alınan 10 günlük yoğurt son 3 gününde, 1 yıllık konserve yine 3 ay kala.
  Yoksa süt alındığı gün "SKT yaklaştı" olur, Tarihi yaklaşanlar hep dolu dururdu. Her eşyada
  ayrıca verilebilir: bisküvide 1 ay dersen yalnızca o 1 ay kala uyarır. "Genel ayarı kullan"
  eşyanın kendi süresini kaldırır.
- Uyarı zamanı gelen eşyanın kartında hardal **SKT yaklaştı**, tarihi geçende kırmızı
  **SKT geçti** damgası çıkar; alt yazıda tarih yazar ("SKT 12 Eki 2026"). Menü
  düğmesinde nokta, sol menüde **Tarihi yaklaşanlar** satırı sayıyla görünür. O sayfada
  süresi geçenler, yaklaşanlar, bakımı gelenler, garantiler (en erken biten önce, "40 gün kaldı")
  ve bakım takvimi durur; her satırdan eşyaya ya da yerine gidilir.
- Tükenen (adedi 0) eşya uyarı vermez; çöpteki de. Tarihler eşyanın bilgisidir, ortak
  kullanımda eşitlenir ("tarihler" değişikliği olarak onaya düşer).
- **Telefon bildirimi** (Ayarlar → Tarihler, varsayılan açık): uyarı süresine girildiği
  gün, son kullanma günü, garantinin bitmesine bir ay kala ve bakım gününde sabah 9'da bildirim
  gelir; uygulama kapalıyken de (alarmlar Android'e önceden verilir, telefon yeniden
  başlarsa yeniden kurulur). Aynı güne düşenler tek bildirimde toplanır ("3 eşyanın
  tarihi yaklaştı"); dokununca **Tarihi yaklaşanlar** açılır. Android 13 ve üstünde
  izin, ilk tarihli eşya kaydedilince (ya da ayar açılınca) sorulur; verilmediyse
  ayar satırında yazar. Tam zamanlı alarm izni istenmez: bildirim dokuzla on arasında
  gelebilir. Önümüzdeki en fazla 30 gün planlanır; liste her değişiklikte, açılışta ve
  uygulama hiç açılmasa da günde bir (Android'in arka plan işi) yenilenir, bildirimler
  bitmez.

**Alışveriş listesi**
- Sol menüde **Alışveriş listesi** (listedekilerin sayısıyla). Listeye **kendiliğinden bir
  şey girmez**: kartın ⋯ menüsünden **Alışveriş listesine ekle** (çıkarmak da oradan),
  listedeki **Önerilenler**'den **Ekle**, ya da kartta adet 0'a ya da en az adede inince
  çıkan bildirimdeki **Listeye ekle**.
- **Önerilenler:** tükenen, azalan ya da son kullanma tarihi geçip hâlâ evde olan ama
  listede olmayan eşyalar; eklenmedikçe listeye girmez.
- **Listeye kendiliğinden ekle** eşyanın kendi ayarıdır (düzenleyicideki "Alışveriş listesi"
  bölümü; oluştururken ya da sonra, varsayılan kapalı). Açık olan eşya bitince, en az adedine
  inince ya da son kullanma tarihi geçince listeye kendiliğinden girer (kartta adet
  düşünce "… tükendi. Alışveriş listesine eklendi." der), alınınca kendiliğinden düşer.
- Liste ortak kullanımda da ortaktır: birinin eklediği ya da aldığı herkese geçer.
- **Markette Aldım, evde Yerleştir.** Markette **Aldım** yalnızca işaretler: adet ya da tarih
  girilecek eşya listeden düşer, **Yerleştirilecek** bölümüne geçer (her biri için adet ve
  tarih girmek markette yoruyordu). Evde **Yerleştir**: kaç tane alındığı sorulur, elde
  kalanın üstüne eklenir (2 kalmışken 6 alınınca 8), tarihliyse yenilerin tarihi de. Kartta
  + ile eklemek de yerleştirmiş sayılır. Yanlışlıkla işaretlenen ↶ ile listeye döner. Adet
  tutulmayan, tarihsiz eşyada Aldım listeden düşürür. Tarihi geçende **Yenisini aldım**:
  satın alma tarihi bugün olur, paketteki eski tarih silinir; raf ömrü varsa (muz) yeni
  tarih ondan hesaplanır, yoksa bildirimdeki **Tarih gir** düzenleyiciyi açar. Hepsi
  bildirimden geri alınabilir; elle eklenen ✕ ile listeden çıkarılır.
- **Alıyorum:** paylaşılan listede her satırda ✋ var; evden çıkmadan "ben alıyorum" denir,
  ötekiler satırda "Ayşe alıyor" görür, iki kişi aynı şeyi almaz. İşaret bir gün geçerli,
  alınınca kalkar. (Markette ağ olmadığı için liste orada güncellenmez; işaret evden çıkmadan
  konmalı.)
- **Öteki envanterlerin listeleri** de sayfanın altında durur (Ev ile Yazlık'ı birlikte
  kullanan tek sayfada görsün); dokununca o envantere geçilir, listesi açılır. Kapalı
  envanterin listesi, envanter kapanırken saklanandır.
- Üstteki paylaş düğmesi listeyi düz metin olarak gönderir (mesaj, not):
  "Alışveriş listesi · 27 Eyl 2026" ve altında madde madde adlar (azalanda "2 kaldı").
- **Ana ekran widget'ı:** telefonun ana ekranında boş bir yere uzun bas → Widget'lar →
  Envanter → **Alışveriş listesi**. Listedekiler renkli noktayla (tükendi, azaldı, tarihi
  geçti ya da elle eklendi) ve sayısıyla görünür; öteki envanterlerin listeleri de
  (notunda envanterin adıyla); uygulamada bir şey değişince hemen
  güncellenir. Otomatik ekleme açıksa son kullanma tarihi gece geçen eşya uygulama
  açılmadan da (en geç bir saat içinde) listeye girer. Satıra ya da başlığa dokununca uygulama alışveriş listesinde açılır. Widget
  uygulamanın dilinde, telefonun açık/koyu temasında çizilir; boyutu değiştirilebilir.

**Tarihi geçenler**
- Son kullanma tarihi geçip hâlâ yerinde duran eşyalar sağ kenardaki kırmızı kulpta
  (yalnızca varken) ve sol menünün üstündeki **Tarihi geçen** düğmesinde toplanır. Sık
  kullanılanlar gibi bir işarettir: eşya yerinden kıpırdamaz, kartına dokununca yerine gidilir.
- Eşya yerinden çıkarılınca buradan düşer: çöpe atılınca, çekmeceye alınınca, kayıp
  bildirilince ya da adedi 0'a inince. "Listeye kendiliğinden ekle" açıksa o sırada zaten
  alışveriş listesindedir; kapalıysa listede önerilir.

**Ekler: belge, fotoğraf, video, bağlantı**
- Her kayda (eşyaya da klasöre de) ek iliştirilebilir: matkabın **kullanım kılavuzu** (PDF),
  **garanti belgesinin fotoğrafı**, çalışırken gösterdiği bir sorunun **videosu**, nasıl
  kullanıldığını anlatan bir videonun **bağlantısı**, fatura...
- **Eklemek:** düzenleyicide **Ekler** bölümü → **Ek ekle**: *Belge ya da dosya* (telefondaki
  herhangi bir dosya; birden çok seçilebilir), *Fotoğraf çek*, *Video çek*, *Galeriden fotoğraf
  ya da video*, *Bağlantı* (adres ve isteğe bağlı başlık; "youtube.com/…" gibi yazılana
  `https://` eklenir). Düzenleyiciye girmeden de eklenir: karta dokununca açılan görünümde
  eki olan kayıtta şeridin sonundaki **+**, olmayanda **Diğer → Ek ekle**.
- **Açmak:** karta dokununca açılan görünümde ekler kartın altında yan yana durur (fotoğrafın
  kendisi, videonun bir karesi, PDF'in ilk sayfası küçük resim olarak). Dokununca fotoğraf
  uygulamanın içinde tam ekran açılır (büyütülür); belge ve video telefonda o türü açan
  uygulamada, bağlantı tarayıcıda (ya da YouTube gibi kendi uygulamasında) açılır.
- Eki olan kartın altında **ataş ve ek sayısı** görünür. Ekin satırındaki ⋮: **Adını değiştir**,
  **Paylaş** (dosyayı ya da adresi başka uygulamaya gönderir), **Adresi kopyala**, **Eki kaldır**.
- **Dosyalar uygulamanın içine kopyalanır:** galerideki ya da İndirilenler'deki özgün dosya
  silinse de ek durur. Bir ek en fazla **500 MB**, bir kayıtta en fazla 40 ek olabilir.
- **Ortak kullanımda** ekler de eşitlenir: kayıt hemen gelir, dosyası arkadan iner (büyük bir
  video sürebilir; inene kadar ekin altında "henüz inmedi", inerken "iniyor, %40" yazar ve
  küçük görüntüsünün yerinde ilerleme halkası döner). **Yedeğe** de girerler;
  video çoksa yedek dosyası büyür.
- **Ekler tek tek birleşir:** iki kişi aynı kayda ayrı cihazlarda (eşitlenmeden) ek koyarsa
  ikisi de kalır. Birinin çıkardığı ek, onu hâlâ tutan cihazla eşitlenince geri gelmez; adı
  değişen ekte son verilen ad kalır. Onaylı modda reddedilen bir ek değişikliğinde reddedenin
  listesi geçerli olur (karşıdaki ek kalkar, çıkarılan geri gelir). Ekler her cihazda
  eklenme sırasıyla durur. Bir kayda 40'tan fazla ek eklenemez; iki cihazın ekleri birleşince
  bu sayı aşılabilir, o zaman hepsi durur.
- **Arama** eklerin adlarına da bakar: "kılavuz" yazınca kılavuzu olan eşyalar çıkar.
- **Kapladığı yer:** Ayarlar → Envanter → **Fotoğraflar ve ekler** satırında toplam boyut yazar;
  dokununca fotoğrafların ve ek dosyalarının ayrı ayrı ne kadar tuttuğu ve **en büyük ekler**
  (hangi kayıtta olduklarıyla) listelenir. Satıra dokununca kaydı açılır; ek oradan kaldırılır.
  Yedek dosyası da yaklaşık bu kadar olur.

**Envanterler (Obsidian'daki kasalar gibi)**
- Sol menünün başlığındaki envanter adına (ya da yanındaki ⇕'ye) dokun: bu cihazdaki envanterler,
  her birinin kayıt sayısı ve son açılışı. Dokununca o envantere geçilir; uygulama o
  envanterin ana ekranından (ya da orada kaldığın klasörden) açılır.
- **Yeni envanter** sıfırdan boş bir envanter açar (Ev, Atölye, Kütüphane...). Her
  envanterin kendi kayıtları, fotoğrafları, ortak kullanımı (başka kişilerle paylaşılabilir),
  sık kullanılanları, çekmecesi, çöpü ve yedeği vardır; birbirine karışmaz.
- Aynı anda bir envanter açıktır; ötekiler açılınca kaldığı yerden devam eder.
- **Kapalı envanterler de eşitlenir:** "Ev"i eşinle paylaşıp günlerce "Atölye"yi açık
  tutsan da "Ev" arka planda eşitlenmeye devam eder: uygulama önde değilken (arkada ya da
  kapalı), Wi-Fi'de, yaklaşık yarım saatte bir. Karşıdan gelenler o envanterin onay kuralına
  uyar; onay bekleyen değişiklik varsa envanter listesinde o envanterin altında
  **"N değişiklik onay bekliyor"** yazar ve sol menünün başlığındaki ⇕'de nokta çıkar.
  Alışveriş listesi, widget, tarih bildirimleri ve öteki envanterlerde arama da böylece
  güncel kalır. Uygulamayı kullanırken yalnızca açık envanter eşitlenir. İstemezsen:
  Ayarlar → Bana ait → Ortak kullanım → **Kapalı envanterleri de eşitle** (varsayılan açık).
- **Onay bekleyenler için bildirim:** uygulama önde değilken (açık ya da kapalı bir
  envanterde) onayını bekleyen yeni bir değişiklik gelirse telefon bildirimi çıkar
  ("Ev — 2 değişiklik onay bekliyor"). Dokununca o envanterin değişiklikleri açılır;
  birkaç envanterde bekleyen varsa envanter listesi. Aynı değişiklik ikinci kez
  bildirilmez, uygulamada zaten gördüklerin de. Kapatmak için: Ayarlar → Bana ait →
  Ortak kullanım → **Onay bekleyenleri bildir** (varsayılan açık; bildirim izni ortak
  kullanımı ilk açtığında sorulur).
- Öteki envanterlerde de aranır ve QR okutulur (kapanırken yazılan küçük bir dizinden):
  sonuç "Diğer envanterlerde" başlığı altında envanterin adıyla çıkar, dokununca o
  envantere geçilir ve kayıt yerinde gösterilir. Hiç açılıp kapanmamış envanter o zamana
  dek aranamaz (aramada söylenir).
- **Her envanterin kendi ayarları var:** biri paylaşılırken öteki paylaşılmayabilir, ikisi
  farklı kişilerle paylaşılabilir; birinde değişiklikler otomatik, ötekinde onayla gelir.
  Deste düzeni, yeni klasöre otomatik konum, son kullanma uyarı süresi (kilerde 3 ay,
  ilaç dolabında 1 ay) ve telefon bildirimi de envanter başına. Ayarlar sayfasında
  "Bu envanter: …" başlığının altındakiler açık envanterin ayarlarıdır.
- Kişisel ayarlar (dil, tema, adın ve fotoğrafın, otomatik yedek klasörü) bütün
  envanterlerde aynıdır.
- **Adı sonradan değişir:** listede açık envanterin kartına dokun (ya da herhangi birinin
  ⋮ → Yeniden adlandır), veya Ayarlar'da "Bu envanter: …" başlığının yanındaki kalem.
  Envanteri paylaşan yöneticiysen ağda görünen adı da değişir (Ortak kullanım sayfasındaki
  "Envanterin adı" da aynı adı değiştirir). Başlıkta ve menüde yeni ad görünür.
- **Renk ve amblem:** her envantere kart paletinden bir renk ve simgelerden bir amblem
  seçilebilir (Envanterler → ⋮ → Renk ve amblem, ya da açık envanterin simgesine dokun).
  Seçim hemen uygulanır; amblem envanter listesinde, ana ekranın başlığında adın önünde ve
  sol menünün başında durur: "Ev" ile "Atölye" adı okunmadan ayrılır. Seçilmezse görünüm
  eskisi gibidir. Yalnızca bu cihazda saklanır; paylaşılan envanterde herkes kendi rengini
  seçer.
- ⋮ ile silinir; açık olan da (önce en son açılan başka envantere geçilir, hiç yoksa boş
  bir envanter açılır). Silinen envanter fotoğraflarıyla birlikte **Silinenler**'e gider:
  listenin altında 30 gün durur ("12 gün kaldı"), **Geri getir** ile döner, ⋮ → **Kalıcı
  olarak sil** ile hemen gider; 30 gün dolunca kendiliğinden silinir.
- **Paylaşılan envanteri silmek:** önce diğerlerine haber verilir; yöneticiysen envanteri
  kimin yöneteceğini seçersin (varis en üstte). Kapalı bir paylaşılan envanter bunun için
  önce açılır. Diğer cihazlardaki kopyalar kalır.
- Listede her envanterin **son yedeği** yazar; içi dolu ve hiç yedeklenmemişse kırmızıyla
  "yedeği yok". Otomatik yedek açıkken yedeği eksik kalan kapalı envanterler için üstte
  **Şimdi yedekle** çıkar: sırayla açılıp kapatılır, kapanırken yedeklenir.
- **Açılamayan envanter:** veritabanı bozulmuşsa uygulama takılmaz: bozuk dosya
  Silinenler'e ayrı bir kopya olarak ("… (açılamayan kopya)") alınır, envanter boş açılır
  ve yedekten geri yüklemek için **İçe aktar** önerilir.
- Birden çok envanter varken başlıkta açık olanın adı durur; tarih bildirimleri **bütün**
  envanterlerden gelir ("Süt · Ev: son gün"), alışveriş widget'ı açık envanterin listesini
  adıyla gösterir, otomatik yedeğin dosya adında envanterin adı olur
  (`envanter-atolye-2026-…zip`) ve eski yedekler silinirken başka envanterinkilere dokunulmaz.

**Yalnızca bende (özel kayıtlar)**
- Ortak kullanımda herkesin kendine ait eşyaları ve alanları olabilir: bir klasörün ya
  da eşyanın ⋯ menüsünden **Yalnızca bende tut**. Yeni kayıtta düzenleyicinin
  "Diğer" panelindeki **Yalnızca bende** anahtarıyla daha kaydederken işaretlenir.
- Özel kaydın kartında küçük bir kilit durur. Özel bir klasörün içindeki her şey de
  özeldir; içine konan eşya kendiliğinden özel olur, dışarı taşınan yeniden
  eşitlenir. İçerideki bir kaydın kilidi tek başına açılmaz, klasörün kendisinden açılır.
- Özel kayıtlar ve fotoğrafları başka cihazlara **hiç gönderilmez**; "sendeki N kayıt
  da eklenecek" sayısına da girmez. Başka bir cihazdan o kayda gelen düzenleme, taşıma
  ya da silme yok sayılır.
- **Ortak bir eşya özel alana girerse** (özel bir klasöre konursa ya da kendisi özel
  yapılırsa): herkesin eriştiği eşya diğerlerinde silinmez ama eski yerinde de kalmaz.
  Cihaz onu son bir kez gönderir; diğerlerinin **çekmecesine** iner, kartında sahibinin
  baş harfi ve alt yazısında "Ayşe'de" yazar. Böylece kimse onu garajda aramaz. Bu son
  haber kayıp bildirimi gibi onay beklemez. Özel bir klasörün tamamı özel yapılırsa
  klasör çekmeceye iner, içindekiler onun içinde kalır.
- Sonrası gitmez: Ayşe eşyayı kendi alanında düzenlerse diğerleri görmez; diğerlerinin
  o eşyada yaptığı değişiklik de Ayşe'ye ulaşmaz. Biri eşyayı bir yere koyarsa "Ayşe'de"
  işareti kalkar (bu sıradan bir taşıma, onaya düşer). Ayşe eşyayı yeniden ortak bir
  yere koyar ya da ⋯ → **Diğer cihazlarla paylaş** derse gerçek yeri herkese gider,
  işaret kalkar.
- "Ortak eşya" sayılan: özel olduğu anda son eşitlemeden önce var olan kayıt. Özel
  klasörde doğan ya da son eşitlemeden sonra oluşturulup hemen özel alana konan kayıt
  için kimseye haber gitmez.
- İşaret kaydın kendisinde değil, bu cihazın ayarlarında durur (kayıtta dursaydı
  eşitlemeyle karşıya giderdi). Yedek dosyasına girer: geri yüklenince özel kalır.

**Yedek: dışa ve içe aktarma**
- Ayarlar → Envanter → **Dışa aktar**: bütün kayıtlar (çöptekiler dahil),
  fotoğraflar ve ekler tek bir `.zip` dosyasına konur, paylaşım penceresi açılır — dosyayı
  buluta kaydedebilir, kendine gönderebilir ya da bilgisayara alabilirsin.
- Dışa ve içe aktarma sürerken ilerleme çubuklu bir pencere durur; iş arka planda yürür,
  video ekli büyük bir yedekte de uygulama donmaz.
- **İçe aktar**: dosya seçilir ve envanter geri yüklenir. Yeni kurulan uygulamaya
  taşımanın yolu budur.
- İçe aktarma **birleştirmedir**, silme değil: var olan kayıtlar durur, aynı kaydın
  iki sürümü varsa daha yeni düzenlenmiş olan kalır (ortak kullanımdaki kuralın
  aynısı). Aynı dosyayı iki kez almak kopya oluşturmaz. Fotoğraflar yalnızca
  eksikse yazılır.
- Dosyanın içi açıktır: `envanter.json` (kayıtlar + kalıcı silme izleri) ve
  `images/`. Dışarıdan gelen veri ağdan gelenle aynı süzgeçten geçer; bozuk kayıtlar
  ve güvensiz dosya yolları alınmaz.
- Sık kullanılanlar, son dokunulanlar ve ortak kullanım anahtarı gibi **cihaza özel
  ayarlar dosyaya girmez**; yedek envanterin kendisidir. İstisna "yalnızca bende"
  işaretleri: yedekte özel kayıtlar da, işaretleri de durur.
- **Otomatik yedek.** Ayarlar → **Yedek** → **Otomatik yedek** (kişisel ayar, bütün
  envanterler için): bir kez klasör seçilir (Android'in klasör seçicisi; izin kalıcıdır),
  açık envanterin ilk yedeği hemen yazılır; öteki envanterler için bildirimdeki **Şimdi
  yedekle**. Sonra her envanter aynı klasöre kendi adıyla yazılır: son yedekten bir hafta
  geçmiş ve o arada bir şey değişmişse (açılışta, öne gelişte ya da günde bir arka planda),
  bir de değişen envanterden çıkarken (başka envantere geçerken). Her envanterin en yeni 4
  yedeği kalır. Yazılamazsa (klasör silindi, izin geri alındı) Ayarlar'da kırmızı uyarı
  çıkar, telefona da bildirim gelir (günde en çok bir kez) ve hatırlatma yeniden devreye
  girer.
- **Yedek önerisi:** otomatik yedek kapalıyken envanter 20 kayda ulaşınca bir kez sorulur
  ("Yedek alalım mı?"); **Klasör seç** ya da **Şimdi değil**. Telefon kaybolunca da işe yaraması için
  buluta eşitlenen (Syncthing, Nextcloud…) ya da bilgisayara aktarılan bir klasör
  seçilmeli; Google Drive'ın kendi uygulaması klasör seçiciye her sürümde çıkmıyor.
- **Yedek hatırlatması.** Sunucu olmadığı için telefon kaybolursa envanter de gider.
  Hiç yedek alınmadıysa ilk kayıttan bir hafta sonra, alındıysa son yedekten bir ay
  sonra — ve o arada bir şey değiştiyse — sol menünün başında sakin bir not çıkar
  ("Son yedekten bu yana 23 kayıt değişti"), menü düğmesinde küçük bir kiremit nokta
  belirir. **Şimdi yedekle** dışa aktarmayı açar, **Sonra** bir hafta susturur. Beş
  kayıttan küçük envanterde hiç çıkmaz. Paylaşım penceresinde bir hedef seçilince
  yedek alınmış sayılır (pencereyi kapatmak saymaz); Ayarlar'daki **Dışa aktar**
  satırında "Son yedek: 12 gün önce" yazar. Son yedek zamanı da cihaza özeldir.

**Arama**
- Alt ortadaki **Ara** ile ad, konum adı, not ve ek adlarında arama; QR ve görüntüyle arama da orada.
- **Harf farkı gözetilmez:** büyük/küçük harf, Türkçe'nin noktalı/noktasız i'si ve
  ç ğ ö ş ü (ayrıca â, é gibi şapkalı harfler) düz harf sayılır: "cekic" Çekiç'i,
  "isitici" ISITICI'yı, "sarj" Şarj aletini bulur.
- **Birden çok kelime** yazılabilir; her biri kaydın adında, notunda ya da konum
  adında geçmeli ("kırmızı kalem" → adı Kalem, notu "kırmızı" olan). Sıra: adı tam
  tutan, adı öyle başlayan, bütün kelimeleri adında geçen, sonra yalnızca notunda
  geçenler; aynı derecede klasörler önce.
- Sonuçlarda aranan kelime fosforlu kalemle çizilmiş gibi vurgulanır. Kayıt adında
  geçmeyen bir kelimeyle bulunduysa ikinci satırda notun o parçası ("Notta: …") ya
  da konum adı durur: neden çıktığı görünür.
- Çöpe atılan bir klasörün içindekiler aramada çıkmaz (eskiden çıkıyordu).
- **Filtre çipleri:** Arama kutusunun altındaki yatay filtre şeridiyle sonuçlar tek dokunuşla
  süzülebilir: **Tümü**, **Klasörler**, **Eşyalar**, **Tarihli**, **Fotoğraflı**, **Bitenler** ve **Ekli**.
- **Sonuç yoksa** ne denenebileceği yazar ve altında **QR okut** ile **Görüntüyle ara** durur:
  adı hatırlanmayan eşya etiketinden ya da fotoğrafından bulunur.
- **Öteki envanterlerde de** (bkz. Envanterler): sonuçların altında "Diğer envanterlerde".
- **Son dokundukların:** arama kutusu boşken kestirmelerin altında bu cihazda son
  eklenen, düzenlenen ya da yeri değişen kayıtlar durur, en yenisi üstte ("dün bir
  şey koydum, neredeydi"). Yalnızca sırası değişenler ve karşıdan gelen değişiklikler
  girmez; liste sık kullanılanlar gibi cihaza özeldir.

**Ana ekran kısayolları**
- Uygulama simgesine uzun basınca üç kısayol: **QR okut**, **Ara** ve **Yeni eşya**
  (açık olan klasöre, alttaki + gibi). Uygulama kapalıysa önce kaldığı klasör açılır,
  kısayol onun üstünde çalışır; geri tuşu yine oraya döner. Kısayolların adı cihaz
  diline göre Türkçe ya da İngilizce. Android 7.1 ve üstü.
- Android sabit kısayolla açarken uygulamanın ekranını baştan kurar (uygulama açık
  olsa bile): bir an açılış ekranı görünür, sonra kaldığın yer ve kısayol açılır.

**Diğer**
- Sol üstteki menü: başlıkta açık envanterin adı (dokununca Envanterler), kullanıcı bilgisi;
  altında tek satırda dört panel düğmesi (**Çekmece**, **Kayıp**, **Sık kullanılan**,
  **Tarihi geçen**; sayıları köşede, sağ kenardaki kulplarla aynı panelleri açar); sonra
  tarihi yaklaşanlar, alışveriş listesi, emanettekiler, değer, sayım, ortak kullanım,
  değişiklikler (ortak kullanımda), çöp kutusu ve ayarlar. Telefonda kaydırmadan sığar.
- Silinen kayıtlar çöp kutusuna gider; geri alınabilir ya da kalıcı silinebilir.
  **Kalıcı silinenler** (çöpü boşaltmak, kalıcı sil; başkasının kalıcı silmesi de) çöp
  sayfasının altında **Son silinenler**'de 30 gün fotoğraflarıyla durur; **Geri getir** ile
  yerine döner (çöpe değil; yeri yoksa çekmeceye), klasörle silinenler onunla gelir.
  Paylaşılıyorsa diğerlerinde de geri gelir. Bu liste cihaza özeldir.
- **30 gün beklemeden tamamen silmek:** kalıcı silerken (tek kayıt ya da **Boşalt**) onay
  penceresindeki **"30 gün bekletme, hemen tamamen sil"** kutusu işaretlenirse kayıt Son
  silinenler'e girmez; fotoğrafları ve ekleri de hemen silinir, yer açılır. Son silinenler'de
  bekleyenler de satırdaki kırmızı düğmeyle tek tek ya da bölümün **Temizle** düğmesiyle hepsi
  birden tamamen silinir. Geri getirilemez. Ortak kullanımda silme yine öteki cihazlara gider
  (onlarda onaya düşer); onların Son silinenler listesi kendilerine aittir.
- İlk kullanımda ana ekranda bir ipuçları kartı çıkar.
- **Ayarlar iki sekme:** **Bana ait** (görünüm, dil, otomatik yedek: bütün envanterlerde aynı)
  ve **Bu envanter** (deste, konum, tarihler, ortak kullanım, kayıt sayıları, kapladığı yer,
  dışa/içe aktarma: yalnızca açık envanterin). Sekmeler kaydırırken yerinde durur; ayarlara
  yeniden girince son bakılan sekme açılır.
- **Büyük yazı:** telefonun yazı boyutu büyütülünce sayfalar (düzenleyici, ayarlar, listeler,
  menüler) onunla birlikte büyür; kart, liste satırı ve üst başlık gibi sabit boydaki yerler en
  çok 1,3 kat büyür ki taşmasın. Dar ekranda sığmayan damga ve düğmeler küçülür.
- **Kaldığın yerden devam:** uygulama kapanırken açık olan klasör hatırlanır;
  yeniden açınca doğrudan orası açılır ve geri tuşu üstündeki seviyelere çıkar
  (ana ekran → ... → o klasör). Klasör silinmişse ana ekranda başlanır. Bu
  bilgi de cihazda kalır.

## Çalıştırma

```bash
flutter pub get
flutter run                          # bağlı cihaz ya da emülatörde
flutter test                         # birim ve arayüz testleri
flutter build apk --release          # tek APK (üç ABI birlikte, ~77 MB)
flutter build apk --split-per-abi    # cihaz başına daha küçük APK'lar
```

Bu makinede araçlar şuraya kuruldu; PATH'e eklemen gerekir:

```bash
export PATH="$HOME/development/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk"
export JAVA_HOME="$HOME/development/jdk-21"   # Temurin 21; flutter config --jdk-dir da bunu gösteriyor
```

Test için `envanter_test` adında bir Android 35 emülatörü hazır. Kamerası sanal
bir oda gösterir; QR ya da görüntüyle aramayı denemek için odaya kendi resmini asabilirsin:

```bash
$ANDROID_HOME/emulator/emulator -avd envanter_test -camera-back virtualscene \
  -virtualscene-poster wall=/yol/qr_ya_da_foto.png
adb emu automation play $ANDROID_HOME/emulator/resources/macros/Walk_to_image_room
```

Emülatörde denerken `flutter run` yerine release APK kurmak daha sağlam:
`flutter run` yarıda kesilirse uygulamanın önbelleğinde bozuk bir kod dosyası
kalıyor ve uygulama açılış ekranında takılıyor (`adb shell run-as
com.envanter.envanter rm -rf code_cache/*` ya da yeniden kurulum düzeltir).
Tablet görünümü için: `adb shell wm size 1600x2560; adb shell wm density 320`
(geri almak için `reset`).

## Kod düzeni

```
lib/
  core/        tema ve renk belirteçleri (Tones), palet, simge kataloğu, metinler (TR/EN), yollar,
               aramanın harf katlaması (text_match)
  data/        Node modeli, sqflite şeması (sürüm 16), paketler (lots), ayarlar, envanter kütüphanesi (library)
  services/    resim seçme ve tonu, konum, QR üretme/çözme, QR etiket sayfası (PDF),
               görüntü parmak izi
  state/       InventoryStore — tüm ağacı bellekte tutan tek kaynak; bekleyen değişiklikler;
               InventoryHost — açık envanter ve envanterler arası geçiş
  sync/        ortak kullanım: birleştirme, inceleme, ağda bulma, HTTP, imza, servis
  ui/          ekranlar ve widget'lar; ui/sharing: ortak kullanım, değişiklikler, roller
               widgets/paper.dart: kağıt panel, satır, kayıt satırı; ink_art.dart: çizimler
assets/fonts/  Manrope (arayüz) ve Fraunces (başlık), OFL lisanslı sabit kopyalar
tool/
  lan_peer_sim.dart  emülatörle denemek için bilgisayarda çalışan ikinci "telefon"
```

`InventoryStore` bütün ağacı bellekte tutar ve `ChangeNotifier` olarak yayınlar;
ev ölçeğindeki kayıt sayısında en hızlı ve ağaç işlemlerini (yol, alt ağaç,
döngü kontrolü) en basit yol bu. Yazma işlemleri önce sqflite'a, sonra belleğe gider.

Silme yumuşaktır (`deleted_at`): bir klasör çöpe gidince alt ağacı ayrıca
işaretlenmez, atası çöpte olduğu için zaten görünmez olur; geri alınca hepsi döner.
Kayıp da bir durumdur (`lost_at`, `lost_from`): kayıt kökte, kayıp çekmecesinde durur.

Birkaç yer beklenmedik görünebilir, hepsi bilerek:

- **Kayıtlar `INSERT OR REPLACE` ile yazılmaz.** SQLite onu "sil + ekle" olarak
  yapıyor ve `ON DELETE CASCADE` yüzünden düzenlenen bir klasörün içindekiler
  veritabanından siliniyordu (hata ancak uygulama yeniden açılınca görünüyordu).
  Bunun yerine önce `UPDATE`, sonra `INSERT OR IGNORE`; aynı toplu yazımda üst kayıt
  alttakinden sonra gelebildiği için yabancı anahtarlar işlem sonunda denetlenir.
- **Sürüklerken klasöre inmek route açmaz.** Flutter'ın `Navigator`'ı route
  değişiminde aktif işaretçileri iptal ediyor, yani `Navigator.push` sürüklemeyi
  yarıda keserdi. Kabuk (`InventoryShell`) kendi içinde bir "iniş yığını" tutuyor.
- **Sağ paneller `Scaffold.endDrawer` değil.** Kabuğun içinde hep ağaçta duran,
  kapalıyken ekran dışına ötelenen paneller. Stack'teki çocukları anahtarlı: perde
  eklenip çıkınca panel yeniden kurulsaydı içindeki kartın bağlamı ölür, sürükleme
  ve "yerini biliyorum" akışı kesilirdi.
- **Ortak kullanım sayfasındaki durum kartında gradyan yok.** Orada gradyan
  kullanılınca Android emülatörünün GPU katmanı (swiftshader) SIGSEGV ile
  kapanıyordu; kartlardaki ışık halkaları gibi düz renkli çizim kullanılıyor.
- **Eylemli bildirimlerde `persist: false` açıkça veriliyor.** Flutter'da eylemi
  olan SnackBar varsayılan olarak ekranda kalıyor.
- **Metin soran pencereler `showTextPrompt` ile açılıyor.** Kontrolcüleri pencerenin
  kendi yaşam döngüsünde tutuluyor; aksi halde kapanış animasyonunda çöküyordu.

`MainActivity` birkaç küçük yerel iş yapıyor: kamera iznini istemek, ortak kullanım
açıkken Wi-Fi yayın kilidini tutmak, yedek dosyasını seçtirmek, sağ kenarın bir
bölümünü sistemin geri hareketinden hariç tutmak ve ana ekran kısayolundan
gelindiyse hangisi olduğunu saklamak (Flutter hazır olunca `takeShortcut` ile alır).
Kısayol niyeti bir veri adresiyle değil özel bir eylemle (`com.envanter.envanter.SHORTCUT`)
gelir: Flutter'ın derin bağlantı desteği adresi bir route sanıp açmaya kalkmasın.

### Ortak kullanımın iç yapısı

Katmanlar, alttan üste:

- `sync/fields.dart` — alan grupları: her kayıt grup başına son değişme anını
  (`field_times`) taşır; `mergeNode` aynı kaydın iki sürümünü grup grup birleştirir.
- `sync/merge.dart` — saf birleştirme: kayıtlar `mergeNode` ile, silme izleri, ağaç onarımı.
- `sync/review.dart` — saf inceleme: gelen durumdan neyin onay bekleyeceği, neyin
  sessizce alınacağı (yalnızca zamanı değişmiş kayıtlar; kayıp bildirimi, bulunma ve
  "Ayşe'de" haberinin yer kısmı), değişikliğin tarifi ("taşıdı", "adı değişti"...) ve gruplama.
- `sync/discovery.dart` — UDP ile bulma (port 47810). Cihaz kendini 30 saniyede bir
  duyurur; "ağı tara" ya da uygulamanın açılışı bir soru yayınlar, duyan her cihaz
  hemen yanıt verir. Karşının adresi paketin geldiği yerden alınır.
- `sync/lan_peer.dart` — küçük bir HTTP sunucusu ve istemcisi: `/info`, `/join`,
  `/state`, `/image/…`. Eşitlemeyi başlatan taraf her şeyi yapar. İmza saat farkı yüzünden
  tutmazsa sunucu 401 yanıtında saatini söyler, istemci farkı öğrenip bir kez yeniden imzalar.
- `sync/wire.dart` — gelen verinin doğrulanması, üyeler (rol ve rol zamanı) ve
  istek imzası (HMAC-SHA256; anahtar kabul anında bir kez verilir).
- `sync/sharing_service.dart` — aç/kapat, tarama, katılma istekleri, roller,
  otomatik eşitleme. Uygulama arka plana geçince ağı durdurur.

Gelen durum `InventoryStore.mergeRemote(review: true)` ile birleşir. Değişikliği
yapan (kaydın `updated_by` alanı, yoksa gönderen cihaz) ana kullanıcıysa ya da
kaydın bulunduğu klasörün (veya bir atasının) sorumlusuysa değişiklik hemen
uygulanır; değilse bekleyen değişiklik olarak `meta` tablosunda saklanır. Bekleyen
bir değişiklik, kullanıcı aynı alanı kendisi değiştirince geçersiz sayılıp düşer;
başka bir alanı düzenlemesi onu düşürmez (kabul edilince ikisi birleşir).
Katılırken ilk eşitleme ve "otomatik kabul" açıkken inceleme yapılmaz.

Büyük envanterde (400 kayıttan çok) eşitlemenin ağır işleri ayrı bir iş parçacığında
yapılır: durumu metne çevirmek ve imza için özetini almak, gelen durumun imzasını doğrulamak,
çözmek ve her kaydı denetlemek. Bunlar ana iş parçacığında yapılırken binlerce kayıtlı bir
envanterde her eşitlemede arayüz kısa bir an takılıyordu. Küçük envanterde her şey eskisi
gibi yerinde yapılır.

Emülatörle deneme: emülatörler ağ olarak birbirini görmüyor. `tool/lan_peer_sim.dart`
bilgisayarda ikinci bir cihaz gibi çalışır:

```bash
adb emu redir add udp:47810:47810                   # duyurular emülatöre gitsin
SIM_MODE=owner flutter test tool/lan_peer_sim.dart  # "Ayşe": envanter sahibi, istekleri kabul eder
SIM_MODE=owner SIM_SCRIPT=1 flutter test tool/lan_peer_sim.dart
                                                     # katılımdan sonra Ayşe değişiklik yapar
                                                     # ve bir eşyayı kayıp bildirir
# ya da, uygulamanın sunucu portunu yönlendirip ona katılmak için:
adb forward tcp:47900 tcp:<uygulamanın portu>
SIM_MODE=joiner SIM_TARGET=http://127.0.0.1:47900 flutter test tool/lan_peer_sim.dart
# alan bazında birleştirme: Veli adı değiştirir, 20 sn içinde uygulamada adedi değiştir
SIM_MODE=joiner SIM_TARGET=http://127.0.0.1:47900 SIM_FIELD="Eşya adı" \
  SIM_CONFIG=build/sim_veli.json flutter test tool/lan_peer_sim.dart
```

`SIM_CONFIG` Veli'nin kimliğini ve anahtarını dosyada tutar: sonraki çalıştırmalar yeni
bir üye olarak değil aynı Veli olarak döner (üye çıkarma olmadığı için her denemede
listede yeni bir "Veli" birikiyordu). Uygulama arka plana gidip dönünce sunucusu yeni bir
porta açılır; simülatör "EŞİTLENEMEDİ" derse portu yeniden bulup `adb forward`'ı yenile.

## Bilinen sınırlar

- Android'de jest navigasyonu açıkken ekranın en sağındaki ~20dp'lik şerit sistemin
  "geri" hareketine ait; çekmece kulba dokunarak ya da üst çubuktaki simgeyle açılıyor.
- Görüntüyle arama bir tanıma modeli değil, resim karşılaştırması. Eşik
  (`kVisualMatchThreshold`) `test/fixtures/visual` altındaki fotoğraflarla ayarlandı.
- Ortak kullanım cihazlar aynı Wi-Fi ağındayken eşitler: uygulama açıkken sürekli, kapalıyken
  Android'in izin verdiği ölçüde yarım saatte bir (pil tasarrufu bunu geciktirebilir). İki
  telefon da uygulamayı kapalı tutuyorsa arka plan işlerinin aynı ana denk gelmesi gerekir;
  biri açıkken öteki arka planda eşitlenir. Cihazları birbirinden yalıtan (misafir) ağlarda
  cihazlar birbirini göremez. Markette (ev ağı dışında) liste güncellenmez.
- Alan grupları kabadır: iki kişi aynı notun farklı satırlarını değiştirirse not
  bütün olarak son yazanınki olur (metin içi birleştirme yok).
- Roller bir güven modelidir, zorlanan bir yetki değil: anahtar bütün üyelerde
  aynı olduğu için kötü niyetli değiştirilmiş bir uygulama kendini ana kullanıcı
  gösterebilir. Ev içi kullanım için tasarlandı.
- Üye çıkarma da bu güven modelinin içinde: anahtar değişmez, çıkarılan cihazın istekleri
  kimliğinden tanınıp reddedilir. Değiştirilmiş bir uygulama başka bir üyenin kimliğini
  taklit edebilir.
- Video uygulamanın içinde oynatılmaz; telefonun oynatıcısı açılır.
- Kapalı envanterler yalnızca arka planda eşitlenir (uygulama önde değilken, Wi-Fi'de,
  yaklaşık yarım saatte bir); uygulamayı kullanırken yalnızca açık olan envanter eşitlenir.

## Lisans

Telif hakkı © 2026 Murat Boy

Envanter özgür yazılımdır: Özgür Yazılım Vakfı'nın yayımladığı GNU Genel Kamu Lisansı'nın
3. sürümünün (GPL-3.0) koşullarıyla yeniden dağıtılabilir ve değiştirilebilir. Yararlı
olması umuduyla dağıtılır, ama hiçbir garantisi yoktur; satılabilirlik ya da belirli bir
amaca uygunluk garantisi de yoktur. Lisansın tam metni [LICENSE](LICENSE) dosyasında.

Uygulamayla gelen Manrope ve Fraunces yazı tipleri kendi lisanslarıyla, SIL Open Font
License 1.1 ile dağıtılır (`assets/fonts/*-OFL.txt`).
