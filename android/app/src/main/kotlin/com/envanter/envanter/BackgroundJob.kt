package com.envanter.envanter

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Uygulama kapalıyken ara ara çalışan iş (Android'in iş zamanlayıcısı; ek
 * kütüphane yok). İki telefonun eşitlenmesi için ikisinin de uygulamayı aynı
 * anda açık tutması gerekiyordu; evde bu nadiren oluyor.
 *
 * - "sync": yarım saatte bir, yalnızca Wi-Fi'de (ölçülmeyen ağ). Açık
 *   envanter paylaşılıyorsa kısa bir eşitleme turu.
 * - "daily": günde bir, ağ gerekmez. Tarih bildirimlerinin planı ileri
 *   kayar (uygulama uzun süre açılmasa da bildirimler bitmesin), vakti
 *   gelen otomatik yedek yazılır.
 *
 * Uygulamanın motoru yaşıyorsa (arka planda da olsa) iş ona devredilir:
 * veritabanı zaten onda açık. Yoksa ayrı bir Flutter motoru açılır ve Dart'taki
 * `backgroundMain` çalışır. Uygulama bu sırada açılırsa önce bu iş durur
 * ([whenIdle]): iki motor aynı veritabanına aynı anda yazmasın.
 */
class BackgroundJob : JobService() {
    companion object {
        private const val SYNC_ID = 4701
        private const val DAILY_ID = 4702

        /** Şu an kendi motoruyla çalışan iş. */
        private var running: BackgroundJob? = null
        private val waiters = mutableListOf<() -> Unit>()

        /** Açılışta; kurulu işe dokunmaz (her açılışta süre baştan başlamasın). */
        fun schedule(context: Context) {
            val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
            val pending = scheduler.allPendingJobs.map { it.id }.toSet()
            val component = ComponentName(context, BackgroundJob::class.java)
            if (SYNC_ID !in pending) {
                scheduler.schedule(
                    JobInfo.Builder(SYNC_ID, component)
                        .setPeriodic(30 * 60 * 1000L)
                        .setRequiredNetworkType(JobInfo.NETWORK_TYPE_UNMETERED)
                        .setPersisted(true)
                        .build()
                )
            }
            if (DAILY_ID !in pending) {
                scheduler.schedule(
                    JobInfo.Builder(DAILY_ID, component)
                        .setPeriodic(24 * 60 * 60 * 1000L)
                        .setPersisted(true)
                        .build()
                )
            }
        }

        /** Uygulama açılırken: arka plandaki iş veritabanını bırakınca [done]. */
        fun whenIdle(done: () -> Unit) {
            val job = running ?: return done()
            waiters.add(done)
            job.requestStop()
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var params: JobParameters? = null

    override fun onStartJob(p: JobParameters): Boolean {
        val task = if (p.jobId == SYNC_ID) "sync" else "daily"
        MainActivity.live?.let { activity ->
            activity.runBackgroundTask(task) { jobFinished(p, false) }
            return true
        }
        if (running != null) return false
        return try {
            start(p, task)
            true
        } catch (e: Exception) {
            running = null
            false
        }
    }

    private fun start(p: JobParameters, task: String) {
        running = this
        params = p
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        val e = FlutterEngine(applicationContext)
        channel = MethodChannel(e.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when {
                    call.method == "backgroundDone" -> {
                        result.success(null)
                        handler.post { finish() }
                    }
                    // Arka planda uygulama açılmıyor: bekleyen iş yok.
                    call.method == "waitBackgroundIdle" -> result.success(null)
                    !PlatformCalls.handle(applicationContext, call, result) -> result.notImplemented()
                }
            }
        }
        engine = e
        e.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "backgroundMain"),
            listOf(task),
        )
        // Takılırsa: Android'in süresi dolmadan kendimiz bırakalım.
        handler.postDelayed({ requestStop() }, 4 * 60 * 1000L)
    }

    /** Dart tarafı işi bırakıp veritabanını kapatsın; yanıt gelmezse yine de biter. */
    fun requestStop() {
        channel?.invokeMethod("stop", null)
        handler.postDelayed({ finish() }, 10_000L)
    }

    private fun finish() {
        if (running !== this) return
        handler.removeCallbacksAndMessages(null)
        engine?.destroy()
        engine = null
        channel = null
        running = null
        PlatformCalls.setMulticastLock(applicationContext, false)
        params?.let { jobFinished(it, false) }
        params = null
        val done = waiters.toList()
        waiters.clear()
        done.forEach { it() }
    }

    // Ağ değişince çağrılır (Android 14+); ağ yoksa tur zaten kendi kendine biter.
    // Boş bile olsa yazılmalı: yazılmayınca her değişimde günlüğe uyarı düşüyor.
    override fun onNetworkChanged(params: JobParameters) {}

    override fun onStopJob(p: JobParameters): Boolean {
        if (running === this) {
            requestStop()
        } else {
            MainActivity.live?.requestStop()
        }
        return true
    }
}
