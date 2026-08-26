package com.ygen.mfuns_flutter

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : AudioServiceActivity() {
    private data class PendingSave(
        val bytes: ByteArray,
        val name: String,
        val mimeType: String,
        val result: MethodChannel.Result,
    )

    private var pendingSave: PendingSave? = null

    private data class PendingExportSave(
        val source: File,
        val fileName: String,
        val directory: String,
        val relativePath: String,
        val mimeType: String,
        val result: MethodChannel.Result,
    )

    private var pendingExportSave: PendingExportSave? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mfuns/gallery")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveImage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                saveImage(call, result)
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mfuns/export")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                saveExportFile(call, result)
            }
    }

    private fun saveImage(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val name = call.argument<String>("name")
        val mimeType = call.argument<String>("mimeType")
        if (bytes == null || name.isNullOrBlank() || mimeType.isNullOrBlank()) {
            result.error("invalid_arguments", "缺少图片保存参数", null)
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingSave = PendingSave(bytes, name, mimeType, result)
            requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), savePermissionRequestCode)
            return
        }
        writeImage(bytes, name, mimeType, result)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == exportPermissionRequestCode) {
            val request = pendingExportSave ?: return
            pendingExportSave = null
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                writeExportFile(
                    request.source,
                    request.fileName,
                    request.directory,
                    request.relativePath,
                    request.mimeType,
                    request.result,
                )
            } else {
                request.result.error("permission_denied", "没有存储写入权限", null)
            }
            return
        }
        if (requestCode != savePermissionRequestCode) return
        val request = pendingSave ?: return
        pendingSave = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            writeImage(request.bytes, request.name, request.mimeType, request.result)
        } else {
            request.result.error("permission_denied", "没有相册写入权限", null)
        }
    }

    /// 文章导出保存：把已生成的文件写入内部存储
    /// `Pictures/Mfuns Flutter`（图片）或 `Documents/Mfuns Flutter`（Markdown）。
    private fun saveExportFile(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val fileName = call.argument<String>("fileName")
        val directory = call.argument<String>("directory") ?: "Documents"
        val relativePath = call.argument<String>("relativePath") ?: ""
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
            result.error("invalid_arguments", "缺少导出保存参数", null)
            return
        }
        val source = File(sourcePath)
        if (!source.exists() || !source.isFile) {
            result.error("source_missing", "导出文件不存在", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            pendingExportSave =
                PendingExportSave(source, fileName, directory, relativePath, mimeType, result)
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                exportPermissionRequestCode,
            )
            return
        }
        writeExportFile(source, fileName, directory, relativePath, mimeType, result)
    }

    private fun writeExportFile(
        source: File,
        fileName: String,
        directory: String,
        relativePath: String,
        mimeType: String,
        result: MethodChannel.Result,
    ) {
        try {
            val location = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                writeExportMediaStore(source, fileName, directory, relativePath, mimeType)
            } else {
                writeExportLegacy(source, fileName, directory, relativePath, mimeType)
            }
            result.success(location)
        } catch (error: Exception) {
            result.error("save_failed", error.message, null)
        }
    }

    /// Android 10+：通过 MediaStore 写入，无需存储权限。
    private fun writeExportMediaStore(
        source: File,
        fileName: String,
        directory: String,
        relativePath: String,
        mimeType: String,
    ): String {
        val root = if (directory == "Pictures") {
            Environment.DIRECTORY_PICTURES
        } else {
            Environment.DIRECTORY_DOCUMENTS
        }
        val fullRelative = listOf("Mfuns Flutter", relativePath)
            .filter { it.isNotBlank() }
            .joinToString("/")
        val relativePathValue = "$root/$fullRelative"
        val collection = if (directory == "Pictures") {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
        // 同名旧文件先删除，避免重复导出堆积。
        deleteExisting(collection, fileName, relativePathValue)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePathValue)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(collection, values)
            ?: throw IllegalStateException("无法创建导出文件")
        try {
            contentResolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("无法写入导出文件")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
        } catch (error: Exception) {
            contentResolver.delete(uri, null, null)
            throw error
        }
        return displayPathOf(uri) ?: "/storage/emulated/0/$relativePathValue/$fileName"
    }

    /// Android 9-：直接写入公共目录（需 WRITE_EXTERNAL_STORAGE）。
    private fun writeExportLegacy(
        source: File,
        fileName: String,
        directory: String,
        relativePath: String,
        mimeType: String,
    ): String {
        val rootDir = if (directory == "Pictures") {
            Environment.DIRECTORY_PICTURES
        } else {
            Environment.DIRECTORY_DOCUMENTS
        }
        val folder = File(
            Environment.getExternalStoragePublicDirectory(rootDir),
            "Mfuns Flutter/$relativePath",
        )
        if (!folder.exists() && !folder.mkdirs()) {
            throw IllegalStateException("无法创建导出目录")
        }
        val target = File(folder, fileName)
        source.copyTo(target, overwrite = true)
        MediaScannerConnection.scanFile(this, arrayOf(target.path), arrayOf(mimeType), null)
        return target.absolutePath
    }

    private fun deleteExisting(collection: Uri, fileName: String, relativePath: String) {
        val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND " +
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ?"
        contentResolver.delete(collection, selection, arrayOf(fileName, relativePath))
    }

    private fun displayPathOf(uri: Uri): String? {
        return contentResolver.query(
            uri,
            arrayOf(MediaStore.MediaColumns.DATA),
            null,
            null,
            null,
        )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
    }

    private fun writeImage(
        bytes: ByteArray,
        name: String,
        mimeType: String,
        result: MethodChannel.Result,
    ) {
        try {
            val location = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Mfuns")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: throw IllegalStateException("无法创建相册文件")
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("无法写入相册文件")
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                uri.toString()
            } else {
                val folder = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                    "Mfuns",
                )
                if (!folder.exists() && !folder.mkdirs()) {
                    throw IllegalStateException("无法创建图片目录")
                }
                val file = File(folder, name)
                FileOutputStream(file).use { it.write(bytes) }
                MediaScannerConnection.scanFile(this, arrayOf(file.path), arrayOf(mimeType), null)
                Uri.fromFile(file).toString()
            }
            result.success(location)
        } catch (error: Exception) {
            result.error("save_failed", error.message, null)
        }
    }

    private companion object {
        const val savePermissionRequestCode = 7314
        const val exportPermissionRequestCode = 7315
    }
}
