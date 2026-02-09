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

package com.openhiker.android.service.community

import android.util.Log
import com.openhiker.android.di.GeneralClient
import com.openhiker.core.community.RouteIndex
import com.openhiker.core.community.RouteSlugifier
import com.openhiker.core.community.SharedRoute
import com.openhiker.core.community.TokenObfuscator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.util.Base64
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Service for browsing and uploading community routes via the OpenHikerRoutes
 * GitHub repository.
 *
 * Browse operations:
 * - Fetch the route index (index.json) from raw.githubusercontent.com
 * - Fetch a full route detail (route.json) by repository path
 *
 * Upload operations (8-step Git API flow):
 * 1. Fetch latest commit SHA on main branch
 * 2. Create a new branch from that SHA
 * 3. Create a blob for route.json
 * 4. Get the existing tree SHA
 * 5. Create a new tree with the route blob
 * 6. Create a commit on the new tree
 * 7. Update the branch ref to point to the new commit
 * 8. Create a pull request
 *
 * All network calls use exponential backoff retry (up to [MAX_RETRIES] attempts).
 * The route index is cached in memory with a [INDEX_CACHE_TTL_MS] TTL.
 *
 * @param httpClient General-purpose OkHttp client with User-Agent header.
 */
@Singleton
class GitHubRouteService @Inject constructor(
    @GeneralClient private val httpClient: OkHttpClient
) {
    private val json = Json {
        ignoreUnknownKeys = true
        prettyPrint = true
    }

    /** Cached route index and its fetch timestamp. */
    private var cachedIndex: RouteIndex? = null
    private var cacheTimestamp: Long = 0L

    /**
     * Fetches the community route index from the GitHub repository.
     *
     * Returns a cached copy if the cache is less than [INDEX_CACHE_TTL_MS]
     * old. Otherwise performs a network fetch with retry.
     *
     * @param forceRefresh If true, bypasses the cache and fetches fresh data.
     * @return The route index, or null if the fetch fails after retries.
     */
    suspend fun fetchRouteIndex(forceRefresh: Boolean = false): RouteIndex? {
        if (!forceRefresh) {
            val cached = cachedIndex
            if (cached != null && (System.currentTimeMillis() - cacheTimestamp) < INDEX_CACHE_TTL_MS) {
                return cached
            }
        }

        val url = "$RAW_BASE_URL/index.json"
        val body = fetchWithRetry(url) ?: return null

        return try {
            val index = json.decodeFromString<RouteIndex>(body)
            cachedIndex = index
            cacheTimestamp = System.currentTimeMillis()
            index
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse route index", e)
            null
        }
    }

    /**
     * Fetches a full community route by its repository path.
     *
     * @param path Repository-relative path (e.g., "routes/US/mount-tamalpais").
     * @return The full shared route, or null if the fetch fails.
     */
    suspend fun fetchRoute(path: String): SharedRoute? {
        val url = "$RAW_BASE_URL/$path/route.json"
        val body = fetchWithRetry(url) ?: return null

        return try {
            json.decodeFromString<SharedRoute>(body)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse route at $path", e)
            null
        }
    }

    /**
     * Uploads a route to the community repository via a pull request.
     *
     * Executes the 8-step Git API flow:
     * 1. Get latest main branch SHA
     * 2. Create a feature branch
     * 3. Create a blob with the route JSON
     * 4. Get the existing tree SHA
     * 5. Create a new tree with the route file
     * 6. Create a commit
     * 7. Update branch ref
     * 8. Create a pull request
     *
     * @param route The shared route to upload.
     * @return The pull request URL on success, or null on failure.
     */
    suspend fun uploadRoute(route: SharedRoute): String? = withContext(Dispatchers.IO) {
        val token = getToken() ?: run {
            Log.e(TAG, "No GitHub token configured for upload")
            return@withContext null
        }

        try {
            // Step 1: Get latest commit SHA on main
            val mainSha = getMainBranchSha(token) ?: return@withContext null

            // Step 2: Create branch
            val slug = RouteSlugifier.slugify(route.name)
            val branchName = "community/$slug-${route.id.take(BRANCH_ID_LENGTH)}"
            createBranch(token, branchName, mainSha) ?: return@withContext null

            // Step 3: Create blob with route JSON
            val routeJson = json.encodeToString(route)
            val blobSha = createBlob(token, routeJson) ?: return@withContext null

            // Step 4: Get existing tree SHA from main
            val treeSha = getTreeSha(token, mainSha) ?: return@withContext null

            // Step 5: Create new tree with route file
            val routePath = "routes/${route.region.country}/$slug/route.json"
            val newTreeSha = createTree(token, treeSha, routePath, blobSha)
                ?: return@withContext null

            // Step 6: Create commit
            val commitMessage = "Add route: ${route.name} (${route.region.country}/${route.region.area})"
            val commitSha = createCommit(token, commitMessage, newTreeSha, mainSha)
                ?: return@withContext null

            // Step 7: Update branch ref
            updateBranchRef(token, branchName, commitSha) ?: return@withContext null

            // Step 8: Create pull request
            val prTitle = "Add route: ${route.name}"
            val prBody = buildPrBody(route)
            createPullRequest(token, prTitle, prBody, branchName)
        } catch (e: Exception) {
            Log.e(TAG, "Route upload failed", e)
            null
        }
    }

    /**
     * Clears the cached route index, forcing a fresh fetch on next access.
     */
    fun clearCache() {
        cachedIndex = null
        cacheTimestamp = 0L
    }

    // ── GitHub API helpers ──────────────────────────────────────

    /** Gets the SHA of the latest commit on the main branch. */
    private suspend fun getMainBranchSha(token: String): String? {
        val url = "$API_BASE_URL/git/ref/heads/main"
        val body = apiGet(url, token) ?: return null
        return try {
            json.parseToJsonElement(body).jsonObject["object"]
                ?.jsonObject?.get("sha")?.jsonPrimitive?.content
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse main branch SHA", e)
            null
        }
    }

    /** Creates a new branch from the given SHA. */
    private suspend fun createBranch(token: String, branchName: String, sha: String): String? {
        val url = "$API_BASE_URL/git/refs"
        val payload = """{"ref":"refs/heads/$branchName","sha":"$sha"}"""
        return apiPost(url, token, payload)
    }

    /** Creates a blob (file content) and returns its SHA. */
    private suspend fun createBlob(token: String, content: String): String? {
        val url = "$API_BASE_URL/git/blobs"
        val encoded = Base64.getEncoder().encodeToString(content.toByteArray(Charsets.UTF_8))
        val payload = """{"content":"$encoded","encoding":"base64"}"""
        val body = apiPost(url, token, payload) ?: return null
        return try {
            json.parseToJsonElement(body).jsonObject["sha"]?.jsonPrimitive?.content
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse blob SHA", e)
            null
        }
    }

    /** Gets the tree SHA for a given commit. */
    private suspend fun getTreeSha(token: String, commitSha: String): String? {
        val url = "$API_BASE_URL/git/commits/$commitSha"
        val body = apiGet(url, token) ?: return null
        return try {
            json.parseToJsonElement(body).jsonObject["tree"]
                ?.jsonObject?.get("sha")?.jsonPrimitive?.content
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse tree SHA", e)
            null
        }
    }

    /** Creates a new tree with the given file blob at the specified path. */
    private suspend fun createTree(
        token: String, baseTreeSha: String, filePath: String, blobSha: String
    ): String? {
        val url = "$API_BASE_URL/git/trees"
        val payload = """{
            "base_tree":"$baseTreeSha",
            "tree":[{"path":"$filePath","mode":"100644","type":"blob","sha":"$blobSha"}]
        }""".trimIndent()
        val body = apiPost(url, token, payload) ?: return null
        return try {
            json.parseToJsonElement(body).jsonObject["sha"]?.jsonPrimitive?.content
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse new tree SHA", e)
            null
        }
    }

    /** Creates a commit pointing to the given tree, parented on the given commit. */
    private suspend fun createCommit(
        token: String, message: String, treeSha: String, parentSha: String
    ): String? {
        val url = "$API_BASE_URL/git/commits"
        val escapedMessage = message.replace("\"", "\\\"")
        val payload = """{"message":"$escapedMessage","tree":"$treeSha","parents":["$parentSha"]}"""
        val body = apiPost(url, token, payload) ?: return null
        return try {
            json.parseToJsonElement(body).jsonObject["sha"]?.jsonPrimitive?.content
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse commit SHA", e)
            null
        }
    }

    /** Updates a branch ref to point to the given commit. */
    private suspend fun updateBranchRef(
        token: String, branchName: String, commitSha: String
    ): String? {
        val url = "$API_BASE_URL/git/refs/heads/$branchName"
        val payload = """{"sha":"$commitSha","force":false}"""
        return apiPatch(url, token, payload)
    }

    /** Creates a pull request and returns the PR URL. */
    private suspend fun createPullRequest(
        token: String, title: String, body: String, branchName: String
    ): String? {
        val url = "$API_BASE_URL/pulls"
        val escapedTitle = title.replace("\"", "\\\"")
        val escapedBody = body.replace("\"", "\\\"").replace("\n", "\\n")
        val payload = """{
            "title":"$escapedTitle",
            "body":"$escapedBody",
            "head":"$branchName",
            "base":"main"
        }""".trimIndent()
        val responseBody = apiPost(url, token, payload) ?: return null
        return try {
            json.parseToJsonElement(responseBody).jsonObject["html_url"]?.jsonPrimitive?.content
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse PR URL", e)
            null
        }
    }

    /** Builds a descriptive PR body from route metadata. */
    private fun buildPrBody(route: SharedRoute): String {
        val distKm = "%.1f".format(route.stats.distanceMeters / METRES_PER_KM)
        val elevM = "%.0f".format(route.stats.elevationGainMeters)
        return """
            ## New Community Route: ${route.name}

            **Author:** ${route.author}
            **Region:** ${route.region.area}, ${route.region.country}
            **Activity:** ${route.activityType.name.lowercase()}
            **Distance:** $distKm km
            **Elevation Gain:** $elevM m

            ${route.description}

            *Uploaded from OpenHiker Android*
        """.trimIndent()
    }

    // ── HTTP helpers with retry ─────────────────────────────────

    /** Performs a GET request to the GitHub API with authentication. */
    private suspend fun apiGet(url: String, token: String): String? {
        val request = Request.Builder()
            .url(url)
            .header("Authorization", "Bearer $token")
            .header("Accept", "application/vnd.github.v3+json")
            .build()
        return executeWithRetry(request)
    }

    /** Performs a POST request to the GitHub API with authentication. */
    private suspend fun apiPost(url: String, token: String, jsonBody: String): String? {
        val request = Request.Builder()
            .url(url)
            .header("Authorization", "Bearer $token")
            .header("Accept", "application/vnd.github.v3+json")
            .post(jsonBody.toRequestBody(JSON_MEDIA_TYPE))
            .build()
        return executeWithRetry(request)
    }

    /** Performs a PATCH request to the GitHub API with authentication. */
    private suspend fun apiPatch(url: String, token: String, jsonBody: String): String? {
        val request = Request.Builder()
            .url(url)
            .header("Authorization", "Bearer $token")
            .header("Accept", "application/vnd.github.v3+json")
            .patch(jsonBody.toRequestBody(JSON_MEDIA_TYPE))
            .build()
        return executeWithRetry(request)
    }

    /**
     * Fetches a URL with exponential backoff retry (no auth, for raw content).
     *
     * @param url The URL to fetch.
     * @return Response body string, or null after all retries exhausted.
     */
    private suspend fun fetchWithRetry(url: String): String? {
        val request = Request.Builder().url(url).build()
        return executeWithRetry(request)
    }

    /**
     * Executes an OkHttp request with exponential backoff retry.
     *
     * Retries up to [MAX_RETRIES] times with delays of 2s, 4s, 8s, 16s.
     * Only retries on IOExceptions and 5xx server errors.
     *
     * @param request The OkHttp request to execute.
     * @return Response body string, or null after all retries exhausted.
     */
    private suspend fun executeWithRetry(request: Request): String? {
        var lastException: Exception? = null

        for (attempt in 0 until MAX_RETRIES) {
            try {
                val response = httpClient.executeAsync(request)
                if (response.isSuccessful) {
                    return response.body?.string()
                }

                val code = response.code
                response.close()

                if (code in SERVER_ERROR_RANGE) {
                    Log.w(TAG, "Server error $code for ${request.url}, retrying ($attempt)")
                    delay(retryDelayMs(attempt))
                    continue
                }

                Log.e(TAG, "HTTP $code for ${request.url}")
                return null
            } catch (e: IOException) {
                lastException = e
                Log.w(TAG, "IO error for ${request.url}, retrying ($attempt)", e)
                delay(retryDelayMs(attempt))
            }
        }

        Log.e(TAG, "All retries exhausted for ${request.url}", lastException)
        return null
    }

    /**
     * Calculates exponential backoff delay for a given retry attempt.
     *
     * @param attempt Zero-based attempt number.
     * @return Delay in milliseconds (2000, 4000, 8000, 16000).
     */
    private fun retryDelayMs(attempt: Int): Long =
        INITIAL_RETRY_DELAY_MS * (1L shl attempt)

    /**
     * Executes an OkHttp request as a suspending coroutine.
     *
     * Wraps OkHttp's async [Call.enqueue] in a [suspendCancellableCoroutine]
     * for structured concurrency support.
     *
     * @return The HTTP response.
     * @throws IOException On network failures.
     */
    private suspend fun OkHttpClient.executeAsync(request: Request): Response =
        suspendCancellableCoroutine { continuation ->
            val call = newCall(request)
            continuation.invokeOnCancellation { call.cancel() }

            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (continuation.isActive) {
                        continuation.resumeWithException(e)
                    }
                }

                override fun onResponse(call: Call, response: Response) {
                    if (continuation.isActive) {
                        continuation.resume(response)
                    }
                }
            })
        }

    /**
     * Retrieves the GitHub PAT for upload operations.
     *
     * Uses the obfuscated token embedded in the app binary. The token
     * is deobfuscated at runtime using [TokenObfuscator].
     *
     * @return The deobfuscated token string, or null if not configured.
     */
    private fun getToken(): String? {
        if (OBFUSCATED_TOKEN.isEmpty()) return null
        return try {
            TokenObfuscator.deobfuscate(OBFUSCATED_TOKEN)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to deobfuscate token", e)
            null
        }
    }

    companion object {
        private const val TAG = "GitHubRouteSvc"

        /** GitHub repository owner and name. */
        private const val REPO_OWNER = "hherb"
        private const val REPO_NAME = "OpenHikerRoutes"

        /** Base URL for fetching raw file content (no auth required for public repos). */
        private const val RAW_BASE_URL =
            "https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main"

        /** Base URL for the GitHub REST API v3. */
        private const val API_BASE_URL =
            "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME"

        /** JSON media type for API request bodies. */
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()

        /** Cache TTL for the route index: 5 minutes. */
        private const val INDEX_CACHE_TTL_MS = 300_000L

        /** Maximum number of retry attempts for network requests. */
        private const val MAX_RETRIES = 4

        /** Initial retry delay in milliseconds (doubles each attempt). */
        private const val INITIAL_RETRY_DELAY_MS = 2_000L

        /** HTTP status code range for server errors. */
        private val SERVER_ERROR_RANGE = 500..599

        /** Length of route ID prefix used in branch names. */
        private const val BRANCH_ID_LENGTH = 8

        /** Metres per kilometre for distance formatting. */
        private const val METRES_PER_KM = 1000.0

        /**
         * Obfuscated GitHub PAT for community route uploads.
         *
         * To generate: `TokenObfuscator.obfuscate("ghp_your_token_here")`
         * Replace this placeholder with the actual obfuscated hex string.
         *
         * The real security gate is the repository's branch protection rules
         * and PR approval requirement — not this obfuscation.
         */
        private const val OBFUSCATED_TOKEN = "" // TODO: Replace with obfuscated PAT
    }
}
