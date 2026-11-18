package studio.lafleur.lafleurmusic

import android.app.Activity
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Canal `studio.lafleur/device` : dossier des copies, sélecteur de dossier, place libre. */
class DeviceChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private var pending: MethodChannel.Result? = null
    private var pendingPermission: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, "studio.lafleur/device").setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "defaultRoot" -> {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
                    "LAFLEURMUSIC",
                )
                // Avant l'API 30 sans le droit d'écriture, mkdirs échoue : le chemin est rendu
                // quand même, le dossier se crée au premier téléchargement (après ensureAccess).
                dir.mkdirs()
                result.success(dir.path)
            }
            "pickFolder" -> pickFolder(result)
            "ensureAccess" -> ensureAccess(call.argument<Boolean>("readOthers") == true, result)
            "freeBytes" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("args", null, null)
                    return
                }
                try {
                    // Le dossier peut ne pas exister encore : on remonte au premier parent présent.
                    var f = File(path)
                    while (!f.exists() && f.parentFile != null) f = f.parentFile!!
                    result.success(StatFs(f.path).availableBytes)
                } catch (e: Exception) {
                    result.success(0L)
                }
            }
            "announce" -> {
                val path = call.argument<String>("path")
                if (path != null) MediaScannerConnection.scanFile(activity, arrayOf(path), null, null)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun pickFolder(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", null, null)
            return
        }
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        @Suppress("DEPRECATION")
        activity.startActivityForResult(intent, REQUEST_FOLDER)
    }

    /** Appelé par [MainActivity.onActivityResult] ; renvoie vrai si le résultat est le nôtre. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_FOLDER) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        val path = realPath(uri)
        if (path == null) {
            result.error("not_local", null, null)
            return true
        }
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (e: Exception) {
            // Pas de permission persistable : le chemin de fichier suffit avec l'accès au stockage.
        }
        val dir = File(path)
        if (!dir.isDirectory && !dir.mkdirs()) {
            result.error("not_local", null, null)
            return true
        }
        // Android 11+ refuse l'écriture de fichiers dans bien des dossiers (Download, racine SD…),
        // et dans Music tout fichier qui n'est pas de l'audio : l'essai est un .mp3, nom unique.
        var probe: File? = null
        val writable = try {
            probe = File.createTempFile("lafleur-probe", ".mp3", dir)
            true
        } catch (e: Exception) {
            false
        } finally {
            // effacé à part : un effacement refusé ne dit rien du droit d'écrire
            try {
                probe?.delete()
            } catch (e: Exception) {
            }
        }
        if (!writable) {
            result.error("not_writable", null, null)
            return true
        }
        result.success(mapOf("path" to path))
        return true
    }

    /**
     * Permissions de stockage : écriture (API <= 29 : l'API 29 garde l'ancien modèle avec
     * requestLegacyExternalStorage), lecture des autres fichiers si [readOthers].
     */
    private fun ensureAccess(readOthers: Boolean, result: MethodChannel.Result) {
        val needed = ArrayList<String>()
        if (Build.VERSION.SDK_INT <= 29) needed.add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        if (readOthers) {
            needed.add(
                if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO
                else Manifest.permission.READ_EXTERNAL_STORAGE,
            )
        }
        val missing = if (Build.VERSION.SDK_INT >= 23) {
            needed.filter { activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        } else {
            emptyList()
        }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.error("busy", null, null)
            return
        }
        pendingPermission = result
        activity.requestPermissions(missing.toTypedArray(), REQUEST_PERMISSIONS)
    }

    /** Appelé par [MainActivity.onRequestPermissionsResult]. */
    fun onPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_PERMISSIONS) return false
        val result = pendingPermission ?: return true
        pendingPermission = null
        result.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
        return true
    }

    /**
     * Chemin de fichiers d'un dossier choisi : `primary:Music/X` → stockage principal,
     * `1234-ABCD:Music` → `/storage/1234-ABCD/Music`. Cloud et autres : null.
     */
    private fun realPath(tree: Uri): String? {
        if (tree.authority != "com.android.externalstorage.documents") return null
        val docId = try {
            DocumentsContract.getTreeDocumentId(tree)
        } catch (e: Exception) {
            return null
        }
        val colon = docId.indexOf(':')
        if (colon < 0) return null
        val volume = docId.substring(0, colon)
        val rel = docId.substring(colon + 1)
        val base = if (volume == "primary") {
            Environment.getExternalStorageDirectory().path
        } else if (volume.matches(Regex("[A-Za-z0-9-]+"))) {
            "/storage/$volume"
        } else {
            return null
        }
        return if (rel.isEmpty()) base else "$base/$rel"
    }

    private companion object {
        const val REQUEST_FOLDER = 4711
        const val REQUEST_PERMISSIONS = 4712
    }
}
