/*
 * OpenHiker - Offline Hiking Navigation
 * Copyright (C) 2024 - 2026 Dr Horst Herb
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package com.openhiker.android.di

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import okhttp3.Dispatcher
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import java.util.concurrent.TimeUnit
import javax.inject.Qualifier
import javax.inject.Singleton

/**
 * Qualifier for the tile download OkHttp client.
 * Uses a separate client with higher concurrency limits for batch tile downloads.
 */
@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class TileDownloadClient

/**
 * Qualifier for the general-purpose OkHttp client.
 * Used for API calls (GitHub, Overpass, elevation data).
 */
@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class GeneralClient

/** User-Agent header value identifying OpenHiker to tile servers. */
private const val USER_AGENT =
    "OpenHiker-Android/1.0 (hiking app; https://github.com/hherb/OpenHiker)"

/** Maximum concurrent requests for tile downloads. */
private const val TILE_MAX_REQUESTS = 6

/** Maximum concurrent requests per host for tile downloads. */
private const val TILE_MAX_REQUESTS_PER_HOST = 6

/** Connection timeout in seconds for general HTTP calls. */
private const val CONNECT_TIMEOUT_SECONDS = 30L

/** Read timeout in seconds for general HTTP calls. */
private const val READ_TIMEOUT_SECONDS = 60L

/**
 * Hilt module providing network-related dependencies.
 *
 * Provides two OkHttp clients:
 * - [TileDownloadClient]: Optimized for concurrent tile downloads with higher limits
 * - [GeneralClient]: Standard client for API calls with logging
 *
 * Both clients include the OpenHiker User-Agent header for tile server compliance.
 */
@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    /**
     * Provides an OkHttp client configured for batch tile downloads.
     *
     * Has increased concurrency limits (6 requests, 6 per host) to
     * download tiles efficiently while respecting server limits.
     * Rate limiting (50ms delay between requests) is handled at the
     * download service layer, not the HTTP client.
     */
    @Provides
    @Singleton
    @TileDownloadClient
    fun provideTileDownloadClient(): OkHttpClient {
        val dispatcher = Dispatcher().apply {
            maxRequests = TILE_MAX_REQUESTS
            maxRequestsPerHost = TILE_MAX_REQUESTS_PER_HOST
        }

        return OkHttpClient.Builder()
            .dispatcher(dispatcher)
            .connectTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .addInterceptor { chain ->
                val request = chain.request().newBuilder()
                    .header("User-Agent", USER_AGENT)
                    .build()
                chain.proceed(request)
            }
            .build()
    }

    /**
     * Provides a general-purpose OkHttp client for API calls.
     *
     * Includes debug logging interceptor and standard timeout configuration.
     * Used for GitHub API, Overpass API, and elevation data downloads.
     */
    @Provides
    @Singleton
    @GeneralClient
    fun provideGeneralClient(): OkHttpClient {
        val loggingInterceptor = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BASIC
        }

        return OkHttpClient.Builder()
            .connectTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .addInterceptor { chain ->
                val request = chain.request().newBuilder()
                    .header("User-Agent", USER_AGENT)
                    .build()
                chain.proceed(request)
            }
            .addInterceptor(loggingInterceptor)
            .build()
    }
}
