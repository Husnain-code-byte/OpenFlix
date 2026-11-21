package com.lagradost.cloudstream3.utils

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import androidx.preference.PreferenceManager
import com.lagradost.cloudstream3.CloudStreamApp.Companion.getKeyClass
import com.lagradost.cloudstream3.CloudStreamApp.Companion.removeKey
import com.lagradost.cloudstream3.CloudStreamApp.Companion.setKeyClass
import com.lagradost.cloudstream3.InternalAPI
import com.lagradost.cloudstream3.mvvm.logError
import com.lagradost.cloudstream3.utils.AppUtils.parseJson
import com.lagradost.cloudstream3.utils.AppUtils.toJsonLiteral
import kotlin.reflect.KClass
import kotlin.reflect.KProperty

const val PREFERENCES_NAME = "openflix_cs3_datastore"
const val USER_SELECTED_HOMEPAGE_API = "home_api_used"
const val USER_PROVIDER_API = "user_custom_sites"

class PreferenceDelegate<T : Any>(
    val key: String,
    val default: T,
) {
    private val klass: KClass<out T> = default::class
    private var cache: T? = null

    operator fun getValue(self: Any?, property: KProperty<*>): T =
        cache ?: getKeyClass(key, klass.java).also { cache = it } ?: default

    operator fun setValue(self: Any?, property: KProperty<*>, t: T?) {
        cache = t
        if (t == null) {
            removeKey(key)
        } else {
            setKeyClass(key, t)
        }
    }
}

data class Editor(val editor: SharedPreferences.Editor) {
    fun <T> setKeyRaw(path: String, value: T) {
        @Suppress("UNCHECKED_CAST")
        if (value is Set<*> && value.all { it is String }) {
            editor.putStringSet(path, value as Set<String>)
        } else {
            when (value) {
                is Boolean -> editor.putBoolean(path, value)
                is Int -> editor.putInt(path, value)
                is String -> editor.putString(path, value)
                is Float -> editor.putFloat(path, value)
                is Long -> editor.putLong(path, value)
            }
        }
    }

    fun apply() {
        editor.apply()
    }
}

@OptIn(InternalAPI::class)
object DataStore {
    @Suppress("unused")
    val mapper get() = com.lagradost.cloudstream3.mapper

    private fun getPreferences(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun Context.getSharedPrefs(): SharedPreferences = getPreferences(this)

    fun Context.getDefaultSharedPrefs(): SharedPreferences =
        PreferenceManager.getDefaultSharedPreferences(this)

    fun getFolderName(folder: String, path: String): String = "$folder/$path"

    fun editor(context: Context, isEditingAppSettings: Boolean = false): Editor {
        val spEditor = if (isEditingAppSettings) {
            context.getDefaultSharedPrefs().edit()
        } else {
            context.getSharedPrefs().edit()
        }
        return Editor(spEditor)
    }

    fun Context.getKeys(folder: String): List<String> {
        val fixedFolder = folder.trimEnd('/') + "/"
        return getSharedPrefs().all.keys.filter { it.startsWith(fixedFolder) }
    }

    fun Context.containsKey(folder: String, path: String): Boolean =
        containsKey(getFolderName(folder, path))

    fun Context.containsKey(path: String): Boolean = getSharedPrefs().contains(path)

    fun Context.removeKey(folder: String, path: String) {
        removeKey(getFolderName(folder, path))
    }

    fun Context.removeKey(path: String) {
        try {
            val prefs = getSharedPrefs()
            if (prefs.contains(path)) {
                prefs.edit { remove(path) }
            }
        } catch (e: Exception) {
            logError(e)
        }
    }

    fun Context.removeKeys(folder: String): Int {
        val keys = getKeys("$folder/")
        return try {
            getSharedPrefs().edit {
                keys.forEach { remove(it) }
            }
            keys.size
        } catch (e: Exception) {
            logError(e)
            0
        }
    }

    fun <T> Context.setKey(path: String, value: T) {
        try {
            getSharedPrefs().edit {
                putString(path, value?.toJsonLiteral())
            }
        } catch (e: Exception) {
            logError(e)
        }
    }

    fun <T> Context.setKey(folder: String, path: String, value: T) {
        setKey(getFolderName(folder, path), value)
    }

    fun <T : Any> Context.getKey(path: String, valueType: Class<T>): T? = try {
        val json = getSharedPrefs().getString(path, null) ?: return null
        parseJson(json, valueType.kotlin)
    } catch (_: Exception) {
        null
    }

    inline fun <reified T : Any> String.toKotlinObject(): T = parseJson(this)

    fun <T : Any> String.toKotlinObject(valueType: Class<T>): T =
        parseJson(this, valueType.kotlin)

    inline fun <reified T : Any> Context.getKey(path: String, defVal: T?): T? = try {
        val json = getSharedPrefs().getString(path, null) ?: return defVal
        parseJson<T>(json)
    } catch (_: Exception) {
        null
    }

    inline fun <reified T : Any> Context.getKey(path: String): T? = getKey(path, null)

    inline fun <reified T : Any> Context.getKey(folder: String, path: String): T? =
        getKey(getFolderName(folder, path), null)

    inline fun <reified T : Any> Context.getKey(folder: String, path: String, defVal: T?): T? =
        getKey(getFolderName(folder, path), defVal) ?: defVal
}
