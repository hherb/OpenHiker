# OpenHiker ProGuard/R8 Rules
# Copyright (C) 2024 - 2026 Dr Horst Herb - AGPL-3.0

# Keep Kotlinx Serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

-keep,includedescriptorclasses class com.openhiker.core.**$$serializer { *; }
-keepclassmembers class com.openhiker.core.** {
    *** Companion;
}
-keepclasseswithmembers class com.openhiker.core.** {
    kotlinx.serialization.KSerializer serializer(...);
}

-keep,includedescriptorclasses class com.openhiker.android.**$$serializer { *; }
-keepclassmembers class com.openhiker.android.** {
    *** Companion;
}
-keepclasseswithmembers class com.openhiker.android.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Keep Room entities
-keep class com.openhiker.android.data.db.** { *; }

# Keep Hilt generated classes
-keep class dagger.hilt.** { *; }

# MapLibre
-keep class org.maplibre.android.** { *; }
-dontwarn org.maplibre.android.**

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# Retrofit
-keepattributes Signature
-keepattributes Exceptions
-keepclassmembers,allowshrinking,allowobfuscation interface * {
    @retrofit2.http.* <methods>;
}
-dontwarn retrofit2.**
