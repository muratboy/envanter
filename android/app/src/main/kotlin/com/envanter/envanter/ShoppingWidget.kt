package com.envanter.envanter

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import org.json.JSONException
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Ana ekrandaki alışveriş listesi. Veriyi uygulama yazar (lib/services/
 * shopping_widget.dart → MainActivity → [save]); widget uygulama kapalıyken de
 * o veriden çizilir. Metinler uygulamanın dilinde hazır gelir.
 *
 * Tarihi geçenler "şu günden itibaren" (`from`) diye gelir: gün dönünce
 * uygulama açılmadan da listeye girsinler diye widget saatte bir tazelenir
 * (res/xml/shopping_widget_info.xml). Satıra ya da başlığa dokununca uygulama
 * alışveriş listesinde açılır (kısayollarla aynı yol: "shopping").
 */
class ShoppingWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        // Saatlik tazeleme: satırlar bugünün tarihiyle yeniden süzülsün.
        refresh(context, manager, ids)
    }

    /** Görünen bir satır. */
    data class Row(val id: String, val name: String, val note: String, val kind: String)

    companion object {
        private const val PREFS = "envanter_widget"
        private const val KEY = "shopping"

        /** Uygulamadan gelen yeni liste: saklanır, bütün widget'lar yenilenir. */
        fun save(context: Context, json: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, json).apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, ShoppingWidget::class.java))
            if (ids.isNotEmpty()) refresh(context, manager, ids)
        }

        /**
         * Sıra önemli: önce görünüm (başlık, sayı, liste bağdaştırıcısı) konur, SONRA
         * listeye "veri değişti" denir. Tersi olunca yeni görünüm bağdaştırıcının eski
         * satırlarıyla kalıyordu: başlıkta "1" yazarken liste "Alınacak bir şey yok"
         * diyordu (sayı her seferinde baştan hesaplanıyor, satırlar değil).
         */
        private fun refresh(context: Context, manager: AppWidgetManager, ids: IntArray) {
            for (id in ids) update(context, manager, id)
            manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
        }

        private fun load(context: Context): JSONObject? {
            val text = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return null
            return try {
                JSONObject(text)
            } catch (_: JSONException) {
                null
            }
        }

        /** Bugün görünen satırlar: vakti gelmemiş "tarihi geçti"ler ve aynı eşyanın ikinci satırı düşer. */
        fun rows(context: Context): List<Row> {
            val items = load(context)?.optJSONArray("items") ?: return emptyList()
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
            val seen = HashSet<String>()
            val rows = ArrayList<Row>()
            for (i in 0 until items.length()) {
                val o = items.optJSONObject(i) ?: continue
                val from = o.optString("from", "")
                if (from.isNotEmpty() && today < from) continue
                val id = o.optString("id", "")
                if (!seen.add(id)) continue
                rows.add(Row(id, o.optString("name", ""), o.optString("note", ""), o.optString("kind", "")))
            }
            return rows
        }

        /** Uygulamayı alışveriş listesinde açan niyet. */
        private fun openIntent(context: Context) = Intent(context, MainActivity::class.java).apply {
            action = SHORTCUT_ACTION
            putExtra("shortcut", "shopping")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        private fun update(context: Context, manager: AppWidgetManager, id: Int) {
            val data = load(context)
            val count = rows(context).size
            val views = RemoteViews(context.packageName, R.layout.widget_shopping)
            views.setTextViewText(
                R.id.widget_title,
                data?.optString("title")?.takeIf { it.isNotEmpty() } ?: context.getString(R.string.widget_shopping_label),
            )
            views.setTextViewText(R.id.widget_count, count.toString())
            views.setViewVisibility(R.id.widget_count, if (count > 0) View.VISIBLE else View.GONE)
            // Uygulama henüz hiç açılmadıysa liste yok: "açınca gelir" denir.
            views.setTextViewText(
                R.id.widget_empty,
                data?.optString("empty")?.takeIf { it.isNotEmpty() } ?: context.getString(R.string.widget_shopping_open),
            )

            val adapter = Intent(context, ShoppingWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                // Widget başına ayrı bağdaştırıcı (niyetler eşit sayılmasın).
                setData(Uri.parse(toUri(Intent.URI_INTENT_SCHEME)))
            }
            views.setRemoteAdapter(R.id.widget_list, adapter)
            views.setEmptyView(R.id.widget_list, R.id.widget_empty)

            val open = PendingIntent.getActivity(
                context, 0, openIntent(context),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_header, open)
            views.setOnClickPendingIntent(R.id.widget_empty, open)
            // Satırlar bu şablonu doldurur; doldurulabilsin diye değiştirilebilir olmalı.
            val template = PendingIntent.getActivity(
                context, 1, openIntent(context),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
            views.setPendingIntentTemplate(R.id.widget_list, template)
            manager.updateAppWidget(id, views)
        }
    }
}
