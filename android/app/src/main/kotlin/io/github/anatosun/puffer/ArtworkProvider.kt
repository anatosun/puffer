package io.github.anatosun.puffer

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

/**
 * Lets Android Auto read the covers the app has stored, which it shows beside each album, playlist and song. Android Auto runs in a process of its own and cannot open the app's files, so the app gives it `content://io.github.anatosun.puffer.artwork/<path>` URIs (`lib/app/car_providers.dart`). Only files in the two artwork folders can be read, and nothing can be written.
 */
class ArtworkProvider : ContentProvider() {
    override fun onCreate() = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw SecurityException("Artwork is read-only")
        val context = context ?: throw FileNotFoundException()
        val file = File(uri.path ?: throw FileNotFoundException()).canonicalFile
        // The covers of downloads (getApplicationSupportDirectory()/artwork) and the cover cache (getTemporaryDirectory()/puffer-artwork, from flutter_cache_manager).
        val roots = listOf(
            File(context.filesDir, "artwork"),
            File(context.cacheDir, "puffer-artwork"),
        ).map { it.canonicalPath + File.separator }
        if (roots.none { file.path.startsWith(it) } || !file.isFile) {
            throw FileNotFoundException(uri.toString())
        }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri) = "image/*"

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ) = 0
}
