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
        if (requestCode != savePermissionRequestCode) return
        val request = pendingSave ?: return
        pendingSave = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            writeImage(request.bytes, request.name, request.mimeType, request.result)
        } else {
            request.result.error("permission_denied", "没有相册写入权限", null)
        }
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
    }
}
