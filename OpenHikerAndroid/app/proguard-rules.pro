# OpenHiker - Offline Hiking Navigation
# Copyright (C) 2024 - 2026 Dr Horst Herb
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# =============================================================================
# OpenHiker ProGuard/R8 Rules
# =============================================================================

# -----------------------------------------------------------------------------
# Kotlinx Serialization
# -----------------------------------------------------------------------------
# Retain annotations and inner classes needed by the serialization runtime.
# Keep Companion objects and generated serializer() methods for all
# serializable model classes in both :core and :app modules.

-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Core module serializable classes
-keep,includedescriptorclasses class com.openhiker.core.**$$serializer { *; }
-keepclassmembers class com.openhiker.core.** {
    *** Companion;
}
-keepclasseswithmembers class com.openhiker.core.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# App module serializable classes
-keep,includedescriptorclasses class com.openhiker.android.**$$serializer { *; }
-keepclassmembers class com.openhiker.android.** {
    *** Companion;
}
-keepclasseswithmembers class com.openhiker.android.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# -----------------------------------------------------------------------------
# Hilt (Dagger) - Dependency Injection
# -----------------------------------------------------------------------------
# Keep all Hilt-generated component classes, module bindings, and injected
# constructors so the DI graph survives minification.

-keep class dagger.hilt.** { *; }
-keep class dagger.hilt.android.** { *; }
-keep class * extends dagger.hilt.android.internal.managers.ViewComponentManager$FragmentContextWrapper { *; }
-keepclasseswithmembernames class * {
    @dagger.hilt.* <fields>;
}
-keepclasseswithmembernames class * {
    @javax.inject.* <fields>;
}
-keepclasseswithmembernames class * {
    @javax.inject.* <init>(...);
}

# -----------------------------------------------------------------------------
# Room - Database Entities, DAOs, and Generated Implementations
# -----------------------------------------------------------------------------
# Room generates implementations at compile time via KSP. Keep entity classes
# (with their column annotations) and DAO interfaces so R8 does not strip them.

-keep class com.openhiker.android.data.db.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keepclassmembers class * {
    @androidx.room.* <fields>;
    @androidx.room.* <methods>;
}

# -----------------------------------------------------------------------------
# MapLibre - Native Map Rendering
# -----------------------------------------------------------------------------
# MapLibre uses JNI calls into native C++ code. All native method declarations
# and classes referenced from the native side must be preserved exactly.

-keep class org.maplibre.android.** { *; }
-keepclassmembers class org.maplibre.android.** {
    native <methods>;
}
-dontwarn org.maplibre.android.**

# Keep classes loaded via JNI from the native library
-keep class org.maplibre.android.maps.NativeMapView { *; }
-keep class org.maplibre.android.geometry.** { *; }
-keep class org.maplibre.android.style.** { *; }

# -----------------------------------------------------------------------------
# OkHttp - HTTP Client
# -----------------------------------------------------------------------------
# OkHttp uses reflection for its internal public-suffix database and platform
# detection. Suppress warnings for optional dependencies (Conscrypt, OpenJSSE).

-dontwarn okhttp3.**
-dontwarn okio.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase
-keep class okhttp3.internal.platform.** { *; }
-keepnames interface okhttp3.** { *; }
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# -----------------------------------------------------------------------------
# Retrofit - REST Client
# -----------------------------------------------------------------------------
# Keep annotated HTTP interface methods so Retrofit can generate proxy
# implementations at runtime via reflection.

-keepattributes Signature
-keepattributes Exceptions
-keepclassmembers,allowshrinking,allowobfuscation interface * {
    @retrofit2.http.* <methods>;
}
-dontwarn retrofit2.**
-keep,allowobfuscation,allowshrinking class retrofit2.Response

# -----------------------------------------------------------------------------
# Kotlin Coroutines
# -----------------------------------------------------------------------------
# Coroutines use internal classes that should not be removed or renamed by R8.
# The debug agent and stack-frame metadata classes must be retained for proper
# exception stack traces and structured concurrency.

-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}
-keepclassmembernames class kotlinx.** {
    volatile <fields>;
}
-dontwarn kotlinx.coroutines.flow.**
-keep class kotlinx.coroutines.android.AndroidDispatcherFactory { *; }
-keep class kotlinx.coroutines.android.AndroidExceptionPreHandler { *; }

# ServiceLoader support for coroutines
-keep class * implements kotlinx.coroutines.internal.MainDispatcherFactory { *; }
-keep class * implements kotlinx.coroutines.CoroutineExceptionHandler { *; }

# -----------------------------------------------------------------------------
# Standard Android Rules
# -----------------------------------------------------------------------------
# Keep Android framework callback classes that are referenced by name in
# manifests, layouts, or the system.

-keep public class * extends android.app.Activity
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider
-keep public class * extends android.app.Application

# Keep View constructors invoked from XML layouts
-keepclasseswithmembers class * {
    public <init>(android.content.Context, android.util.AttributeSet);
}
-keepclasseswithmembers class * {
    public <init>(android.content.Context, android.util.AttributeSet, int);
}

# Keep Parcelable implementations
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# Keep enum values (used by serialization and savedInstanceState)
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep R class fields (resource IDs referenced by reflection in some libraries)
-keepclassmembers class **.R$* {
    public static <fields>;
}

# Suppress warnings for missing optional annotation processors
-dontwarn javax.annotation.**
-dontwarn kotlin.reflect.jvm.internal.**
