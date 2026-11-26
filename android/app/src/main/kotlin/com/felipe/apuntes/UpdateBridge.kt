package com.felipe.apuntes

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import androidx.core.content.pm.PackageInfoCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class UpdateFileProvider : FileProvider()

class UpdateBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val packages = activity.packageManager
    private val packageName = activity.packageName

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "installedVersion" -> installedVersion(result)
            "install" -> install(call, result)
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun installedVersion(result: MethodChannel.Result) {
        val version = try {
            packages.getPackageInfo(packageName, 0).versionName
        } catch (error: Exception) {
            Log.w(TAG, "Could not read the installed version", error)
            null
        }
        if (version.isNullOrBlank()) {
            result.error("VERSION_UNAVAILABLE", "No se pudo leer la versión de Nala.", null)
        } else {
            result.success(version)
        }
    }

    @Suppress("DEPRECATION")
    private fun install(call: MethodCall, result: MethodChannel.Result) {
        try {
            val apk = validatedApk(call.argument<String>("path"), call.argument<String>("version"))
            val canInstall = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packages.canRequestPackageInstalls()
            val intent = if (canInstall) {
                val uri = FileProvider.getUriForFile(activity, "$packageName.nala.update", apk)
                Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                    setDataAndType(uri, APK_TYPE)
                    clipData = ClipData.newRawUri("Nala", uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            } else {
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.fromParts("package", packageName, null))
            }
            val target = packages.queryIntentActivities(
                intent,
                PackageManager.MATCH_DEFAULT_ONLY or PackageManager.MATCH_SYSTEM_ONLY
            ).firstOrNull { it.activityInfo.exported }?.activityInfo
                ?: throw UpdateFailure(
                    "INSTALL_UNAVAILABLE",
                    if (canInstall) "Android no encontró el instalador de aplicaciones."
                    else "Android no pudo abrir el permiso para instalar Nala."
                )
            intent.setClassName(target.packageName, target.name)

            activity.runOnUiThread {
                try {
                    if (activity.isFinishing || activity.isDestroyed) throw ActivityNotFoundException()
                    activity.startActivity(intent)
                    result.success(canInstall)
                } catch (error: Exception) {
                    reportInstallError(result, error)
                }
            }
        } catch (error: Exception) {
            reportInstallError(result, error)
        }
    }

    @Suppress("DEPRECATION")
    private fun validatedApk(path: String?, version: String?): File {
        val candidate = path?.let(::File)
        if (candidate?.isAbsolute != true) throw invalidApk()
        val apk = candidate.canonicalFile
        val updatesDirectory = File(activity.cacheDir.canonicalFile, "nala-updates")
        if (apk.parentFile != updatesDirectory || apk.extension != "apk" || !apk.isFile || apk.length() == 0L) {
            throw invalidApk()
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) PackageManager.GET_SIGNING_CERTIFICATES
            else PackageManager.GET_SIGNATURES
        val update = packages.getPackageArchiveInfo(apk.path, flags) ?: throw invalidApk()
        if (update.packageName != packageName) {
            throw UpdateFailure("WRONG_PACKAGE", "El archivo no corresponde a Nala.")
        }
        if (version.isNullOrBlank() || update.versionName != version) {
            throw UpdateFailure("WRONG_VERSION", "El APK no coincide con la versión publicada.")
        }
        val installed = packages.getPackageInfo(packageName, flags)
        val installedSigners = installed.currentSigners()
        if (installedSigners.isEmpty() || update.currentSigners() != installedSigners) {
            throw UpdateFailure("WRONG_SIGNATURE", "El archivo tiene una firma distinta a la de Nala en este dispositivo.")
        }
        if (PackageInfoCompat.getLongVersionCode(update) <= PackageInfoCompat.getLongVersionCode(installed)) {
            throw UpdateFailure("OLD_VERSION", "El archivo no contiene una compilación más reciente de Nala.")
        }
        return apk
    }

    @Suppress("DEPRECATION")
    private fun PackageInfo.currentSigners(): Set<Signature> {
        val signers = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) signingInfo?.apkContentsSigners
            else signatures
        return signers?.toSet().orEmpty()
    }

    private fun invalidApk() = UpdateFailure("INVALID_APK", "El archivo de actualización está dañado o no es válido.")

    private fun reportInstallError(result: MethodChannel.Result, error: Exception) {
        val failure = when (error) {
            is UpdateFailure -> error
            is ActivityNotFoundException -> UpdateFailure("INSTALL_UNAVAILABLE", "Android no pudo abrir el instalador o la pantalla de permisos.")
            is SecurityException -> UpdateFailure("INSTALL_BLOCKED", "Android bloqueó la instalación de Nala.")
            else -> UpdateFailure("INSTALL_FAILED", "No se pudo preparar la instalación de Nala.")
        }
        if (error !is UpdateFailure) Log.w(TAG, "Could not open the update installer", error)
        result.error(failure.code, failure.message, null)
    }

    private class UpdateFailure(val code: String, override val message: String) : Exception(message)

    private companion object {
        const val TAG = "NalaUpdate"
        const val APK_TYPE = "application/vnd.android.package-archive"
    }
}
