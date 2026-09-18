package com.envanter.envanter

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

/** Eklerin başka uygulamalara verildiği sağlayıcı (res/xml/attachment_paths.xml). */
class AttachmentProvider : FileProvider()

/**
 * Flutter'ın doğrudan yapamadığı birkaç yerel iş:
 *
 * 1. Kamera izni. QR okuyucu CAMERA iznini tanımladığı için image_picker'ın
 *    kamera akışı da iznin verilmiş olmasını bekliyor.
 *
 * 2. Ortak kullanım açıkken Wi-Fi yayın kilidi. Pek çok Wi-Fi yongası güç
 *    tasarrufunda yayın/çoklu yayın paketlerini süzüyor; kilit tutulmazsa
 *    ağdaki envanterlerin duyuruları uygulamaya hiç ulaşmayabilir.
 *
 * 3. Yedek dosyası seçme. Kullanıcının seçtiği dosya (SAF) önbelleğe
 *    kopyalanır ve yolu Flutter'a verilir.
 *
 * 4. Sağ kenardaki çekmece hareketi, Android'in kenar "geri" hareketiyle
 *    aynı şeride düşüyor; kenarın bir bölümünü hareket dışı bırakmayı
 *    istiyoruz. Bu istek her Android sürümünde geri hareketi için
 *    karşılanmıyor, bu yüzden Flutter tarafındaki kulp dokunmayla da açılır.
 *
 * 5. Ana ekran kısayolları (res/xml/shortcuts.xml). Hangi kısayola basıldığı
 *    saklanır, Flutter hazır olunca alır: soğuk açılışta Dart tarafı henüz
 *    dinlemiyor olabilir.
 *
 * 6. Otomatik yedek klasörü: kullanıcı bir kez klasör seçer (SAF), izin kalıcı
 *    alınır; yedek oraya yazılır, en eski fazlalar silinir.
 *
 * 7. Ana ekrandaki alışveriş listesi widget'ının verisi ([ShoppingWidget]).
 *    Widget'a dokunmak da bir kısayol gibi gelir ("shopping").
 *
 * 8. Arka plan işi ([BackgroundJob]): açılışta kurulur; uygulama yaşarken iş
 *    bu motora devredilir ("backgroundTask"). Açılışta Dart, arka planda açılmış
 *    bir motor varsa veritabanını bırakmasını bekler ("waitBackgroundIdle").
 *
 * 9. Ekler: kullanıcının seçtiği belgeler (SAF) envanterin klasörüne kopyalanır;
 *    bir ek, telefonda o türü açan uygulamaya [AttachmentProvider] üzerinden
 *    yalnızca okuma izniyle verilir; bağlantı tarayıcıda açılır.
 *
 * 10. Seri ekleme için galeriden birden çok fotoğraf: yalnızca adresleri ve adları
 *    döner, fotoğraflar sonra tek tek alınır ([PlatformCalls] "importImage").
 *
 * Etkinlik gerektirmeyen işler (yayın kilidi, yedek yazma, widget, saat)
 * [PlatformCalls]'ta: arka plan motoru da onları kullanır.
 */
/** Kısayolların ve widget'ın niyet eylemi (res/xml/shortcuts.xml ile aynı). */
const val SHORTCUT_ACTION = "com.envanter.envanter.SHORTCUT"

/** Dart ile konuşulan kanal (uygulamanın ve arka plan işinin motorunda). */
const val CHANNEL = "envanter/platform"

class MainActivity : FlutterActivity() {

    private var permissionResult: MethodChannel.Result? = null
    private var pickResult: MethodChannel.Result? = null
    private var folderResult: MethodChannel.Result? = null
    private var documentsResult: MethodChannel.Result? = null
    private var documentsDir: String? = null
    private var documentsMax = Long.MAX_VALUE
    private var imagesResult: MethodChannel.Result? = null
    private var channel: MethodChannel? = null

    /** Basılan kısayol ("scan", "search", "new_item", widget'tan "shopping"); Flutter alınca silinir. */
    private var pendingShortcut: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Süreç yeniden kurulurken ya da son uygulamalardan dönülürken aynı niyet
        // yeniden gelir; kısayol yalnızca basıldığında bir kez çalışsın.
        val fromHistory = (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        if (savedInstanceState == null && !fromHistory) pendingShortcut = shortcutOf(intent)
        super.onCreate(savedInstanceState)
        BackgroundJob.schedule(this)
    }

    /** Arka plan işi uygulama yaşarken bu motorda çalışır; bitince [done]. */
    fun runBackgroundTask(task: String, done: () -> Unit) {
        val ch = channel ?: return done()
        ch.invokeMethod("backgroundTask", task, object : MethodChannel.Result {
            override fun success(result: Any?) = done()
            override fun error(code: String, message: String?, details: Any?) = done()
            override fun notImplemented() = done()
        })
    }

    fun requestStop() {
        channel?.invokeMethod("stop", null)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val shortcut = shortcutOf(intent) ?: return
        pendingShortcut = shortcut
        // Uygulama zaten açık: Flutter'a haber ver, kısayolu o alsın.
        channel?.invokeMethod("shortcut", null)
    }

    private fun shortcutOf(intent: Intent?): String? =
        if (intent?.action == SHORTCUT_ACTION) intent.getStringExtra("shortcut") else null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        live = this
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                if (PlatformCalls.handle(applicationContext, call, result)) return@setMethodCallHandler
                when (call.method) {
                    "ensureCamera" -> ensureCamera(result)
                    // Arka planda açılmış motor veritabanını bıraksın, sonra açılış sürsün.
                    "waitBackgroundIdle" -> BackgroundJob.whenIdle { result.success(null) }
                    "pickFile" -> pickFile(result)
                    "pickFolder" -> pickFolder(result)
                    "pickDocuments" -> pickDocuments(
                        call.argument<String>("dir"),
                        call.argument<Number>("max")?.toLong() ?: Long.MAX_VALUE,
                        result,
                    )
                    "pickImages" -> pickImages(result)
                    "openFile" -> result.success(
                        openFile(call.argument<String>("path"), call.argument<String>("mime"), call.argument<String>("name")),
                    )
                    "openUrl" -> result.success(openUrl(call.argument<String>("url")))
                    "releaseFolder" -> {
                        releaseFolder(call.argument<String>("uri"))
                        result.success(null)
                    }
                    "takeShortcut" -> {
                        result.success(pendingShortcut)
                        pendingShortcut = null
                    }
                    // Sağ kenardaki kulpların ekrandaki yeri (mantıksal piksel).
                    "setEdgeExclusion" -> {
                        edgeTop = call.argument<Double>("top")
                        edgeBottom = call.argument<Double>("bottom")
                        applyEdgeGestureExclusion()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        if (live === this) live = null
        PlatformCalls.setMulticastLock(applicationContext, false)
        super.onDestroy()
    }

    // ------------------------------------------------------------ kamera izni

    private fun ensureCamera(result: MethodChannel.Result) {
        val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(true)
            return
        }
        permissionResult = result
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), CAMERA_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CAMERA_REQUEST) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        permissionResult?.success(granted)
        permissionResult = null
    }

    // ------------------------------------------------------------ dosya seçme

    private fun pickFile(result: MethodChannel.Result) {
        // Bekleyen bir istek varsa (kullanıcı geri geldiyse) boş dönsün.
        pickResult?.success(null)
        pickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/zip", "application/octet-stream"))
        }
        try {
            startActivityForResult(intent, PICK_REQUEST)
        } catch (e: Exception) {
            pickResult = null
            result.error("no_picker", e.message, null)
        }
    }

    // ------------------------------------------------------------ yedek klasörü

    private fun pickFolder(result: MethodChannel.Result) {
        folderResult?.success(null)
        folderResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        try {
            startActivityForResult(intent, FOLDER_REQUEST)
        } catch (e: Exception) {
            folderResult = null
            result.error("no_picker", e.message, null)
        }
    }

    private fun onFolderPicked(resultCode: Int, data: Intent?) {
        val result = folderResult ?: return
        folderResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            // Uygulama yeniden açıldığında da yazabilelim.
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            val docId = DocumentsContract.getTreeDocumentId(uri)
            val docUri = DocumentsContract.buildDocumentUriUsingTree(uri, docId)
            val name = contentResolver.query(docUri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
                ?.use { c -> if (c.moveToFirst()) c.getString(0) else null } ?: docId
            result.success(mapOf("uri" to uri.toString(), "name" to name))
        } catch (e: Exception) {
            result.error("no_permission", e.message, null)
        }
    }

    private fun releaseFolder(uri: String?) {
        if (uri == null) return
        try {
            contentResolver.releasePersistableUriPermission(
                Uri.parse(uri),
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (_: Exception) {
            // Zaten bırakılmış.
        }
    }

    // ------------------------------------------------------------ ekler

    /** Kullanıcı bir ya da birkaç dosya seçer; [dir]'e kopyalanıp adları, türleri, boyutları döner. */
    private fun pickDocuments(dir: String?, max: Long, result: MethodChannel.Result) {
        if (dir == null) return result.success(null)
        documentsResult?.success(null)
        documentsResult = result
        documentsDir = dir
        documentsMax = max
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        try {
            startActivityForResult(intent, DOCUMENTS_REQUEST)
        } catch (e: Exception) {
            documentsResult = null
            result.error("no_picker", e.message, null)
        }
    }

    private fun onDocumentsPicked(resultCode: Int, data: Intent?) {
        val result = documentsResult ?: return
        documentsResult = null
        val dir = documentsDir
        val uris = mutableListOf<Uri>()
        data?.clipData?.let { clip -> for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let(uris::add) }
        if (uris.isEmpty()) data?.data?.let(uris::add)
        if (resultCode != RESULT_OK || uris.isEmpty() || dir == null) {
            result.success(null)
            return
        }
        val max = documentsMax
        // Kopyalama ana iş parçacığını tutmasın (kılavuz onlarca MB olabilir).
        Thread {
            val picked = uris.map { copyDocument(it, File(dir), max) }
            runOnUiThread { result.success(picked) }
        }.start()
    }

    /** Dosyayı [dir]'e rastgele bir adla kopyalar. Çok büyükse ya da okunamazsa `file` boş döner. */
    private fun copyDocument(uri: Uri, dir: File, max: Long): Map<String, Any?> {
        var name = "dosya"
        var size = -1L
        try {
            contentResolver.query(uri, null, null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val n = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (n >= 0 && !c.isNull(n)) name = c.getString(n)
                    val s = c.getColumnIndex(OpenableColumns.SIZE)
                    if (s >= 0 && !c.isNull(s)) size = c.getLong(s)
                }
            }
        } catch (_: Exception) {
            // Adı ve boyutu vermeyen sağlayıcı: dosya yine kopyalanır.
        }
        val mime = contentResolver.getType(uri)
        if (size > max) return mapOf("name" to name, "tooLarge" to true)
        // Uzantı: adından, yoksa türünden; yolda yalnızca harf ve rakam.
        val fromName = name.substringAfterLast('.', "").lowercase()
        val ext = (if (fromName.matches(Regex("[a-z0-9]{1,8}"))) fromName
        else MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: "bin")
        val out = File(dir, "${UUID.randomUUID()}.$ext")
        return try {
            dir.mkdirs()
            var total = 0L
            var tooLarge = false
            (contentResolver.openInputStream(uri) ?: throw IllegalStateException("dosya açılamadı")).use { input ->
                out.outputStream().use { output ->
                    val buffer = ByteArray(256 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > max) {
                            tooLarge = true
                            break
                        }
                        output.write(buffer, 0, read)
                    }
                }
            }
            if (tooLarge) {
                out.delete()
                mapOf("name" to name, "tooLarge" to true)
            } else {
                mapOf(
                    "name" to name,
                    "file" to out.name,
                    "size" to total,
                    "mime" to (mime ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)),
                )
            }
        } catch (e: Exception) {
            out.delete()
            mapOf("name" to name, "failed" to true)
        }
    }

    // ------------------------------------------------------------ galeriden fotoğraflar

    /**
     * Seri ekleme: galeriden birden çok fotoğraf. image_picker seçilenlerin hepsini önce tam boyutta
     * açıp küçültüyor, bitene dek hiçbir şey döndürmüyordu (200 fotoğrafta dakikalarca, ilerlemesiz).
     * Burada yalnızca adresler ve adlar döner; her fotoğraf sonra "importImage" ile küçük açılarak
     * alınır, arayüz ilerlemeyi gösterir. Seçici image_picker'ınkiyle aynı niyet (200 seçilebiliyordu).
     */
    private fun pickImages(result: MethodChannel.Result) {
        imagesResult?.success(null)
        imagesResult = result
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "image/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        try {
            startActivityForResult(intent, IMAGES_REQUEST)
        } catch (e: Exception) {
            imagesResult = null
            result.error("no_picker", e.message, null)
        }
    }

    private fun onImagesPicked(resultCode: Int, data: Intent?) {
        val result = imagesResult ?: return
        imagesResult = null
        val uris = mutableListOf<Uri>()
        data?.clipData?.let { clip -> for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let(uris::add) }
        if (uris.isEmpty()) data?.data?.let(uris::add)
        if (resultCode != RESULT_OK || uris.isEmpty()) {
            result.success(null)
            return
        }
        // Adlar sağlayıcıya tek tek sorulur: yüzlercesi ana iş parçacığını tutmasın.
        Thread {
            val picked = uris.map { mapOf("uri" to it.toString(), "name" to displayName(it)) }
            runOnUiThread { result.success(picked) }
        }.start()
    }

    private fun displayName(uri: Uri): String? = try {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst() && !c.isNull(0)) c.getString(0) else null
        }
    } catch (_: Exception) {
        null
    }

    /**
     * Eki, o türü açan uygulamaya verir (yalnızca okuma izniyle). Açan yoksa false.
     * [name]: açan uygulamada görünen ad; diskteki ad rastgele bir kimlik
     * olduğu için başlıkta o yazıyordu.
     */
    private fun openFile(path: String?, mime: String?, name: String?): Boolean {
        if (path == null) return false
        return try {
            val file = File(path)
            val uri = if (name.isNullOrBlank()) FileProvider.getUriForFile(this, "$packageName.files", file)
            else FileProvider.getUriForFile(this, "$packageName.files", file, name)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime ?: contentResolver.getType(uri) ?: "*/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun openUrl(url: String?): Boolean {
        if (url == null) return false
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
            true
        } catch (_: Exception) {
            false
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == FOLDER_REQUEST) return onFolderPicked(resultCode, data)
        if (requestCode == DOCUMENTS_REQUEST) return onDocumentsPicked(resultCode, data)
        if (requestCode == IMAGES_REQUEST) return onImagesPicked(resultCode, data)
        if (requestCode != PICK_REQUEST) return
        val result = pickResult ?: return
        pickResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        // İçerik sağlayıcıdaki dosyayı doğrudan okuyamayız; önbelleğe alınır.
        // Ayrı iş parçacığında: ekli (videolu) bir yedek yüzlerce MB olabilir,
        // ana iş parçacığında kopyalamak uygulamayı "yanıt vermiyor" yapardı.
        channel?.invokeMethod("copying", null)
        Thread {
            try {
                val name = contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (column >= 0 && cursor.moveToFirst()) cursor.getString(column) else null
                } ?: "envanter.zip"
                // Eski yarım kalmış geçici kopyaları temizle.
                cacheDir.listFiles()?.filter { it.name.startsWith("alinan-") }?.forEach { it.delete() }
                val out = File(cacheDir, "alinan-${System.currentTimeMillis()}-${name.takeLast(64)}")
                contentResolver.openInputStream(uri)?.use { input ->
                    out.outputStream().use { input.copyTo(it) }
                } ?: throw IllegalStateException("dosya açılamadı")
                runOnUiThread { result.success(out.absolutePath) }
            } catch (e: Exception) {
                runOnUiThread { result.error("read_failed", e.message, null) }
            }
        }.start()
    }

    // ------------------------------------------------------------ kenar hareketi

    /** Kulpların üst ve alt sınırı (Flutter bildirir, mantıksal piksel); bilinmiyorsa null. */
    private var edgeTop: Double? = null
    private var edgeBottom: Double? = null
    private var layoutListener = false

    override fun onResume() {
        super.onResume()
        applyEdgeGestureExclusion()
        // Etkinlik dönüşte yeniden kurulmuyor (configChanges): şerit, ekran dönünce
        // ya da boyutu değişince de yeniden hesaplanmalı. Yoksa dikeydeki yerinde
        // kalıyor, yatayda sağ kenarın tamamı geri hareketine gidiyordu.
        if (!layoutListener && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            layoutListener = true
            window.decorView.addOnLayoutChangeListener { _, l, t, r, b, ol, ot, orr, ob ->
                if (r - l != orr - ol || b - t != ob - ot) applyEdgeGestureExclusion()
            }
        }
    }

    private fun applyEdgeGestureExclusion() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val root = window.decorView
        root.post {
            val density = resources.displayMetrics.density
            val width = root.width
            val height = root.height
            if (width == 0 || height == 0) return@post

            // Flutter tarafındaki kulplarla aynı yer: sağ kenarda, kulpların
            // ortasında. Android kenar başına en fazla 200dp tanır. Kulpların
            // yeri henüz bildirilmediyse ekranın ortası.
            val stripWidth = (44 * density).toInt()
            val top = edgeTop
            val bottom = edgeBottom
            val center = if (top != null && bottom != null) ((top + bottom) / 2 * density).toInt() else height / 2
            val wanted = if (top != null && bottom != null) ((bottom - top) * density).toInt() else Int.MAX_VALUE
            val stripHeight = minOf((200 * density).toInt(), wanted, height)
            val stripTop = (center - stripHeight / 2).coerceIn(0, height - stripHeight)

            root.systemGestureExclusionRects = listOf(
                Rect(width - stripWidth, stripTop, width, stripTop + stripHeight)
            )
        }
    }

    companion object {
        /** Motoru yaşayan etkinlik: arka plan işi ona devredilir. */
        var live: MainActivity? = null
        private const val CAMERA_REQUEST = 4711
        private const val PICK_REQUEST = 4712
        private const val FOLDER_REQUEST = 4713
        private const val DOCUMENTS_REQUEST = 4714
        private const val IMAGES_REQUEST = 4715
    }
}
