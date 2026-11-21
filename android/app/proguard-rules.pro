# Keep CloudStream 3 runtime, Kotlin stdlib/coroutines, & plugin host APIs intact
# so dynamically loaded .cs3 Dalvik bytecode never hits NoClassDefFoundError / NoSuchMethodError.
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-keep class com.lagradost.** { *; }
-keep class org.jsoup.** { *; }
-keep class com.fasterxml.jackson.** { *; }
-keep class com.google.gson.** { *; }
-keep class me.xdrop.** { *; }
-keep class org.mozilla.javascript.** { *; }
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-keep class org.schabi.newpipe.** { *; }
-keep class com.fleeksoft.ksoup.** { *; }
-keep class io.ktor.** { *; }
-keep class androidx.** { *; }
-keep class com.example.pixel.** { *; }
-keep class app.openflix.client.** { *; }

# Keep media_kit / libmpv native JNI bridge & video surface classes intact
-keep class com.alexmercerind.media_kit_video.** { *; }
-keep class com.alexmercerind.media_kit_libs_android_video.** { *; }
-keep class is.xyz.mpv.** { *; }

# Keep Flutter plugins (url_launcher, package_info_plus, shared_preferences) intact
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Keep JSON serialization annotations & reflection metadata intact
-keepattributes Signature,InnerClasses,EnclosingMethod,RuntimeVisibleAnnotations,*Annotation*
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
    @com.fasterxml.jackson.annotation.JsonProperty <fields>;
}

-dontwarn org.mozilla.javascript.**
-dontwarn com.fasterxml.jackson.**
-dontwarn org.schabi.newpipe.**
-dontwarn io.ktor.**
-dontwarn com.lagradost.**
