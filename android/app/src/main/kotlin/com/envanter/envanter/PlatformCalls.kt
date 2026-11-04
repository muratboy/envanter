package com.envanter.envanter

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.pdf.PdfRenderer
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import kotlin.math.roundToInt
import zxingcpp.BarcodeReader

/**
 * Etkinlik gerektirmeyen yerel işler: hem uygulamanın kendi motoru
 * ([MainActivity]) hem de uygulama kapalıyken arka planda açılan motor
 * ([BackgroundJob]) aynı kanaldan kullanır. Yayın kilidi süreç başına tek.
 */
object PlatformCalls {
    private var multicastLock: WifiManager.MulticastLock? = null
    private val main = Handler(Looper.getMainLooper())

    /** Galeriden alınan fotoğraflar birkaç tane birden küçültülür (her biri ayrı bir çekirdekte). */
    private val imports = Executors.newFixedThreadPool(3)

    /** Tarayıcının kareleri tek tek okunur: Dart bir sonrakini ancak yanıt gelince yollar. */
    private val scans = Executors.newSingleThreadExecutor()

    /** Kanal çağrısını karşıladıysa true. */
    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "setMulticastLock" -> {
                setMulticastLock(context, call.arguments as? Boolean ?: false)
                result.success(null)
            }
            "writeBackup" -> {
                // Dosya kopyalama ana iş parçacığını tutmasın.
                val uri = call.argument<String>("uri")
                val path = call.argument<String>("path")
                val name = call.argument<String>("name")
                val keep = call.argument<Int>("keep") ?: 4
                Thread {
                    val ok = uri != null && path != null && name != null &&
                        writeBackup(context, Uri.parse(uri), File(path), name, keep)
                    main.post { result.success(ok) }
                }.start()
            }
            "updateShoppingWidget" -> {
                (call.arguments as? String)?.let { ShoppingWidget.save(context.applicationContext, it) }
                result.success(true)
            }
            // Ekin küçük resmi: videonun bir karesi ya da PDF'in ilk sayfası.
            "thumbnail" -> {
                val path = call.argument<String>("path")
                val mime = call.argument<String>("mime") ?: ""
                val out = call.argument<String>("out")
                val size = call.argument<Int>("size") ?: 320
                Thread {
                    val ok = path != null && out != null && thumbnail(File(path), mime, File(out), size)
                    main.post { result.success(ok) }
                }.start()
            }
            // Seri ekleme: galeriden seçilen fotoğraf küçültülüp envanterin klasörüne.
            "importImage" -> {
                val uri = call.argument<String>("uri")
                val out = call.argument<String>("out")
                val max = call.argument<Int>("max") ?: 1800
                val quality = call.argument<Int>("quality") ?: 88
                imports.execute {
                    val ok = uri != null && out != null && importImage(context, Uri.parse(uri), File(out), max, quality)
                    main.post { result.success(ok) }
                }
            }
            // Tarayıcı: kameranın bir karesindeki kodlar.
            "readBarcodes" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val width = call.argument<Int>("width") ?: 0
                val height = call.argument<Int>("height") ?: 0
                val stride = call.argument<Int>("stride") ?: width
                val rotation = call.argument<Int>("rotation") ?: 0
                val formats = call.argument<List<String>>("formats") ?: emptyList()
                scans.execute {
                    val found = bytes?.let { readBarcodes(it, width, height, stride, rotation, formats) } ?: emptyList()
                    main.post { result.success(found) }
                }
            }
            // Saat ağdan mı geliyor: eşitlemede yanlış saatli telefonu bulmak için.
            "autoTime" -> result.success(
                Settings.Global.getInt(context.contentResolver, Settings.Global.AUTO_TIME, 1) == 1,
            )
            else -> return false
        }
        return true
    }

    // ------------------------------------------------------------ yayın kilidi

    /**
     * Ortak kullanım açıkken Wi-Fi yayın kilidi. Pek çok Wi-Fi yongası güç
     * tasarrufunda yayın/çoklu yayın paketlerini süzüyor; kilit tutulmazsa
     * ağdaki envanterlerin duyuruları uygulamaya hiç ulaşmayabilir.
     */
    fun setMulticastLock(context: Context, held: Boolean) {
        if (held) {
            if (multicastLock?.isHeld == true) return
            val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("envanter-paylasim").apply {
                setReferenceCounted(false)
                acquire()
            }
        } else {
            multicastLock?.takeIf { it.isHeld }?.release()
            multicastLock = null
        }
    }

    // ------------------------------------------------------------ ek küçük resmi

    /** Videonun ilk saniyesinden bir kare ya da PDF'in ilk sayfası; [out]'a JPEG. */
    private fun thumbnail(file: File, mime: String, out: File, size: Int): Boolean {
        return try {
            val bitmap = when {
                mime.startsWith("video/") -> {
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(file.absolutePath)
                        retriever.getFrameAtTime(1_000_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                            ?: retriever.frameAtTime
                    } finally {
                        retriever.release()
                    }
                }
                mime == "application/pdf" -> {
                    ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                        PdfRenderer(fd).use { pdf ->
                            if (pdf.pageCount == 0) return false
                            pdf.openPage(0).use { page ->
                                val scale = size.toFloat() / maxOf(page.width, page.height)
                                val w = maxOf(1, (page.width * scale).toInt())
                                val h = maxOf(1, (page.height * scale).toInt())
                                // Sayfalar saydam zeminli gelir; kâğıt beyazı üstüne çizilir.
                                Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also { b ->
                                    Canvas(b).drawColor(Color.WHITE)
                                    page.render(b, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                }
                            }
                        }
                    }
                }
                else -> null
            } ?: return false
            val longest = maxOf(bitmap.width, bitmap.height)
            val scaled = if (longest > size) {
                val k = size.toFloat() / longest
                Bitmap.createScaledBitmap(bitmap, maxOf(1, (bitmap.width * k).toInt()), maxOf(1, (bitmap.height * k).toInt()), true)
            } else bitmap
            out.parentFile?.mkdirs()
            out.outputStream().use { scaled.compress(Bitmap.CompressFormat.JPEG, 82, it) }
            true
        } catch (_: Exception) {
            false
        } catch (_: OutOfMemoryError) {
            false
        }
    }

    // ------------------------------------------------------------ galeriden fotoğraf

    /**
     * Fotoğrafı en uzun kenarı en çok [max] olacak şekilde [out]'a JPEG yazar (image_picker'ın tek
     * fotoğraftaki 1800 px / %88'iyle aynı). Fotoğraf baştan küçük açılır (2'nin kuvvetiyle örnekleme):
     * image_picker her fotoğrafı tam boyutta açıyordu (örnekleme oranını boyutunu okumadan hesaplıyor,
     * hep 1 çıkıyor), 12 MP'lik fotoğrafta gerekenin dört katı iş. Yön (EXIF) piksellere uygulanır.
     * Yarım dosya kalmasın diye önce `.part`'a yazılır (açılışta silinir).
     */
    private fun importImage(context: Context, uri: Uri, out: File, max: Int, quality: Int): Boolean {
        val part = File(out.path + ".part")
        return try {
            val decoded = decodeSampled(context, uri, max) ?: return false
            val longest = maxOf(decoded.width, decoded.height)
            var bitmap = if (longest > max) {
                val k = max.toFloat() / longest
                Bitmap.createScaledBitmap(
                    decoded,
                    maxOf(1, (decoded.width * k).roundToInt()),
                    maxOf(1, (decoded.height * k).roundToInt()),
                    true,
                )
            } else decoded
            if (bitmap.hasAlpha()) {
                // Saydam zemin (PNG) JPEG'de siyah olurdu: kâğıt beyazı üstüne.
                val flat = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
                Canvas(flat).apply {
                    drawColor(Color.WHITE)
                    drawBitmap(bitmap, 0f, 0f, null)
                }
                bitmap = flat
            }
            out.parentFile?.mkdirs()
            part.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, quality, it) }
            part.renameTo(out) || run {
                part.delete()
                false
            }
        } catch (_: Exception) {
            part.delete()
            false
        } catch (_: OutOfMemoryError) {
            part.delete()
            false
        }
    }

    /** Dik ve en uzun kenarı [max]'ın altına düşmeden olabildiğince küçük açar. */
    private fun decodeSampled(context: Context, uri: Uri, max: Int): Bitmap? {
        val resolver = context.contentResolver
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // ImageDecoder EXIF yönünü kendisi uygular, HEIF'i de açar. Örnekleme oranı yönden bağımsız:
            // hedef boyut verilseydi yönü dönmüş fotoğrafta en ile boyun karışma tehlikesi vardı.
            try {
                return ImageDecoder.decodeBitmap(ImageDecoder.createSource(resolver, uri)) { decoder, info, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    decoder.setTargetSampleSize(sampleFor(info.size.width, info.size.height, max))
                }
            } catch (_: Exception) {
                // Açamadığı bir sağlayıcı ya da biçim: aşağıdaki eski yoldan bir kez daha denenir.
            }
        }
        // Yalnızca boyut okunur (bu çağrı hep null döner, sonucu boyuttadır).
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        (resolver.openInputStream(uri) ?: return null).use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val options = BitmapFactory.Options().apply { inSampleSize = sampleFor(bounds.outWidth, bounds.outHeight, max) }
        val bitmap = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) } ?: return null
        val orientation = try {
            resolver.openInputStream(uri)?.use {
                ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            }
        } catch (_: Exception) {
            null
        } ?: ExifInterface.ORIENTATION_NORMAL
        // Glide'ın TransformationUtils'indeki eşleme.
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> {
                matrix.setRotate(180f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.setRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.setRotate(-90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    /** [w]×[h]'yi en uzun kenarı [max]'ın altına düşürmeden küçülten en büyük 2'nin kuvveti. */
    private fun sampleFor(w: Int, h: Int, max: Int): Int {
        var sample = 1
        while (maxOf(w, h) / (sample * 2) >= max) sample *= 2
        return sample
    }

    // ------------------------------------------------------------ kod okuma

    /** Okuyucu ve kare tamponları yalnızca [scans] iş parçacığında; okuyucu biçimler değişince kurulur. */
    private var reader: BarcodeReader? = null
    private var readerFormats: List<String> = emptyList()
    private var frame: Bitmap? = null
    private var frameRows: ByteBuffer? = null

    /**
     * Bir karedeki kodlar (zxing-cpp; önceki tarayıcının ML Kit'i kapalı kaynaktı). Kare, kameranın parlaklık
     * düzlemi (YUV'nin Y'si): gri tonlu (ALPHA_8) bir bitmap'e kopyalanır, zxing-cpp onu gri ton olarak okur.
     * [rotation] telefon dikken kareyi dikleştirir; yatık tutulan barkodu okuyucu kendisi döndürüp dener.
     * QR mı ürün barkodu mu, biçim kodunun son baytından ('Q'): kütüphane hep ailenin belirli bir türüyle
     * döner (QR_CODE_MODEL_2, CODE_39_STD...), aile adıyla değil.
     */
    private fun readBarcodes(
        bytes: ByteArray,
        width: Int,
        height: Int,
        stride: Int,
        rotation: Int,
        formats: List<String>,
    ): List<Map<String, Any>> {
        if (width <= 0 || height <= 0 || stride < width) return emptyList()
        if (bytes.size < stride * (height - 1) + width) return emptyList()
        return try {
            val bitmap = frame?.takeIf { it.width == width && it.height == height }
                ?: Bitmap.createBitmap(width, height, Bitmap.Config.ALPHA_8).also { frame = it }
            val rowBytes = bitmap.rowBytes
            val size = rowBytes * height
            // Satır payı aynıysa kare olduğu gibi kopyalanır; değilse satır satır (son satırda pay olmayabilir).
            val rows = if (stride == rowBytes && bytes.size >= size) ByteBuffer.wrap(bytes, 0, size) else {
                val packed = frameRows?.takeIf { it.capacity() == size }
                    ?: ByteBuffer.allocate(size).also { frameRows = it }
                packed.clear()
                for (y in 0 until height) {
                    packed.position(y * rowBytes)
                    packed.put(bytes, y * stride, width)
                }
                packed.rewind()
                packed
            }
            bitmap.copyPixelsFromBuffer(rows)
            readerFor(formats).read(bitmap, Rect(), rotation).mapNotNull { code ->
                code.text?.let { mapOf("text" to it, "qr" to ((code.format.value and 0xFF) == 'Q'.code)) }
            }
        } catch (_: Exception) {
            emptyList()
        } catch (_: OutOfMemoryError) {
            emptyList()
        } catch (_: UnsatisfiedLinkError) {
            emptyList()
        }
    }

    private fun readerFor(formats: List<String>): BarcodeReader {
        reader?.takeIf { formats == readerFormats }?.let { return it }
        val chosen = formats.mapNotNull { name -> BarcodeReader.Format.entries.firstOrNull { it.name == name } }.toSet()
        // Okuyucunun hız için kapalı gelen denemeleri açılır: zor kodu daha çok uğraşarak arar, yatık barkodu
        // döndürüp dener, yakından tutulan büyük kodu küçültüp bulur. Ters renkli kod (koyu üstüne açık)
        // aranmaz: iş iki katına çıkar, etiketlerde hemen hiç yok.
        val created = BarcodeReader(
            BarcodeReader.Options(formats = chosen, tryHarder = true, tryRotate = true, tryDownscale = true),
        )
        reader = created
        readerFormats = formats
        return created
    }

    // ------------------------------------------------------------ otomatik yedek

    /**
     * Yedeği klasöre yazar; aynı envanterin zip'lerinden en yeni [keep] tanesi kalır.
     * Envanter adın tarihten önceki kısmından bilinir ("envanter-2026-…" ilk envanter,
     * "envanter-atolye-2026-…" Atölye): aynı klasöre yedeklenen başka envanterin
     * dosyalarına dokunulmaz.
     */
    private fun writeBackup(context: Context, tree: Uri, file: File, name: String, keep: Int): Boolean {
        val resolver = context.contentResolver
        return try {
            val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            val created = DocumentsContract.createDocument(resolver, parent, "application/zip", name)
                ?: return false
            resolver.openOutputStream(created)?.use { out -> file.inputStream().use { it.copyTo(out) } }
                ?: return false
            pruneBackups(context, tree, keep, name.takeWhile { !it.isDigit() })
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun pruneBackups(context: Context, tree: Uri, keep: Int, prefix: String) {
        val resolver = context.contentResolver
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val backups = mutableListOf<Pair<String, String>>() // (ad, belge kimliği)
        resolver.query(
            children,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_DOCUMENT_ID),
            null, null, null
        )?.use { c ->
            while (c.moveToNext()) {
                val n = c.getString(0) ?: continue
                val ours = n.startsWith(prefix) && n.getOrNull(prefix.length)?.isDigit() == true
                if (ours && n.endsWith(".zip")) backups.add(n to c.getString(1))
            }
        }
        // Adlar tarih-saatle başlıyor: ada göre sıralamak zamana göre sıralamaktır.
        for ((_, id) in backups.sortedByDescending { it.first }.drop(keep)) {
            try {
                DocumentsContract.deleteDocument(resolver, DocumentsContract.buildDocumentUriUsingTree(tree, id))
            } catch (_: Exception) {
                // Silinemeyen eski yedek kalır; yeni yedek yine yazıldı.
            }
        }
    }
}
