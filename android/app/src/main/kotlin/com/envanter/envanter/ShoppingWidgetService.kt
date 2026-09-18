package com.envanter.envanter

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import androidx.core.content.ContextCompat

/**
 * Widget'taki kaydırılabilir liste. Android 12'den eski sürümlerde liste
 * satırları ancak böyle bir hizmetten gelebiliyor; veri [ShoppingWidget.rows].
 */
class ShoppingWidgetService : RemoteViewsService() {

    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = Factory(applicationContext)

    private class Factory(private val context: Context) : RemoteViewsFactory {
        private var rows: List<ShoppingWidget.Row> = emptyList()

        override fun onCreate() {}

        override fun onDataSetChanged() {
            rows = ShoppingWidget.rows(context)
        }

        override fun onDestroy() {}

        override fun getCount(): Int = rows.size

        override fun getViewAt(position: Int): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_shopping_row)
            val row = rows.getOrNull(position) ?: return views
            views.setTextViewText(R.id.row_name, row.name)
            views.setTextViewText(R.id.row_note, row.note)
            // Uygulamadaki damgaların renkleri: tükendi kiremit, azaldı hardal,
            // tarihi geçti kırmızı; yalnızca elle eklenen soluk.
            val color = when (row.kind) {
                "low" -> R.color.widget_low
                "expired" -> R.color.widget_expired
                "wanted" -> R.color.widget_muted
                else -> R.color.widget_accent
            }
            views.setTextColor(R.id.row_dot, ContextCompat.getColor(context, color))
            views.setOnClickFillInIntent(R.id.row_root, Intent())
            return views
        }

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount(): Int = 1

        override fun getItemId(position: Int): Long = position.toLong()

        override fun hasStableIds(): Boolean = false
    }
}
