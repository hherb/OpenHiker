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

package com.openhiker.android.service.navigation

import android.app.Application
import android.media.AudioManager
import android.media.ToneGenerator
import android.util.Log
import kotlinx.coroutines.delay
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Navigation events that trigger distinct audio cue patterns.
 *
 * Each event maps to a specific tone pattern played through [NavigationAudioCuePlayer]
 * to give the hiker audible feedback without needing to look at the screen.
 */
enum class NavigationCueEvent {
    /** The user is approaching a turn (typically within 100m). Single short beep. */
    APPROACHING_TURN,

    /** The user has reached the turn point. Double beep. */
    AT_TURN,

    /** The user has deviated from the planned route. Triple warning beep. */
    OFF_ROUTE,

    /** The user has arrived at the destination. Ascending three-tone pattern. */
    ARRIVED
}

/**
 * Plays simple audio tone patterns for navigation events using Android's [ToneGenerator].
 *
 * This avoids any dependency on audio files — all cues are synthesised on-device.
 * The [ToneGenerator] is created lazily and can fail on some devices or emulators
 * that lack the required audio hardware; failures are caught and logged rather
 * than crashing the app.
 *
 * Tone patterns per event:
 * - [NavigationCueEvent.APPROACHING_TURN] — single short beep ([ToneGenerator.TONE_PROP_BEEP])
 * - [NavigationCueEvent.AT_TURN] — double beep ([ToneGenerator.TONE_PROP_BEEP])
 * - [NavigationCueEvent.OFF_ROUTE] — triple warning beep ([ToneGenerator.TONE_PROP_BEEP2])
 * - [NavigationCueEvent.ARRIVED] — ascending three-tone melody
 *
 * Usage:
 * ```kotlin
 * audioCuePlayer.enabled = true
 * audioCuePlayer.playNavigationCue(NavigationCueEvent.APPROACHING_TURN)
 * ```
 *
 * @param application The application context, used only for logging the tag.
 */
@Singleton
class NavigationAudioCuePlayer @Inject constructor(
    private val application: Application
) {
    /** Whether audio cues are enabled. When `false`, [playNavigationCue] is a no-op. */
    var enabled: Boolean = false

    /**
     * Lazily-initialised [ToneGenerator] bound to the notification audio stream.
     *
     * Returns `null` if the device does not support tone generation (logged as a warning).
     */
    private val toneGenerator: ToneGenerator? by lazy {
        try {
            ToneGenerator(AudioManager.STREAM_NOTIFICATION, TONE_VOLUME_PERCENT)
        } catch (e: RuntimeException) {
            Log.w(TAG, "ToneGenerator unavailable on this device: ${e.message}")
            null
        }
    }

    /**
     * Plays the audio cue pattern associated with the given navigation event.
     *
     * This method is a no-op when [enabled] is `false` or when the [ToneGenerator]
     * could not be initialised. Each event triggers a distinct tone pattern so the
     * hiker can distinguish between them without looking at the screen.
     *
     * This is a **suspend** function because multi-tone patterns (double beep,
     * triple beep, ascending tones) require short delays between individual tones.
     *
     * @param event The navigation event that determines which tone pattern to play.
     */
    suspend fun playNavigationCue(event: NavigationCueEvent) {
        if (!enabled) return
        val generator = toneGenerator ?: return

        try {
            when (event) {
                NavigationCueEvent.APPROACHING_TURN -> {
                    generator.startTone(ToneGenerator.TONE_PROP_BEEP, BEEP_DURATION_MS)
                }

                NavigationCueEvent.AT_TURN -> {
                    generator.startTone(ToneGenerator.TONE_PROP_BEEP, BEEP_DURATION_MS)
                    delay(BEEP_GAP_MS)
                    generator.startTone(ToneGenerator.TONE_PROP_BEEP, BEEP_DURATION_MS)
                }

                NavigationCueEvent.OFF_ROUTE -> {
                    repeat(OFF_ROUTE_BEEP_COUNT) { index ->
                        generator.startTone(ToneGenerator.TONE_PROP_BEEP2, BEEP_DURATION_MS)
                        if (index < OFF_ROUTE_BEEP_COUNT - 1) {
                            delay(BEEP_GAP_MS)
                        }
                    }
                }

                NavigationCueEvent.ARRIVED -> {
                    generator.startTone(ARRIVED_TONE_LOW, ARRIVED_TONE_DURATION_MS)
                    delay(ARRIVED_TONE_GAP_MS)
                    generator.startTone(ARRIVED_TONE_MID, ARRIVED_TONE_DURATION_MS)
                    delay(ARRIVED_TONE_GAP_MS)
                    generator.startTone(ARRIVED_TONE_HIGH, ARRIVED_TONE_DURATION_MS)
                }
            }
        } catch (e: RuntimeException) {
            Log.w(TAG, "Failed to play navigation cue for $event: ${e.message}")
        }
    }

    /**
     * Releases the underlying [ToneGenerator] resources.
     *
     * Call this when the navigation session ends or when the service is destroyed
     * to free native audio resources promptly. After calling [release], the
     * [toneGenerator] lazy property will **not** be re-initialised — create a
     * new [NavigationAudioCuePlayer] instance if audio cues are needed again.
     */
    fun release() {
        try {
            toneGenerator?.release()
        } catch (e: RuntimeException) {
            Log.w(TAG, "Error releasing ToneGenerator: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "NavAudioCuePlayer"

        /** ToneGenerator volume as a percentage (0–100) of the stream volume. */
        private const val TONE_VOLUME_PERCENT = 80

        /** Duration of a single beep tone in milliseconds. */
        private const val BEEP_DURATION_MS = 150

        /** Gap between consecutive beeps in a multi-beep pattern, in milliseconds. */
        private const val BEEP_GAP_MS = 200L

        /** Number of warning beeps for the off-route cue. */
        private const val OFF_ROUTE_BEEP_COUNT = 3

        /** Duration of each tone in the arrival melody, in milliseconds. */
        private const val ARRIVED_TONE_DURATION_MS = 200

        /** Gap between ascending tones in the arrival melody, in milliseconds. */
        private const val ARRIVED_TONE_GAP_MS = 150L

        /**
         * Ascending tone sequence for the arrival cue.
         * Uses DTMF-adjacent tones for a recognisable ascending pattern.
         */
        private const val ARRIVED_TONE_LOW = ToneGenerator.TONE_DTMF_1
        private const val ARRIVED_TONE_MID = ToneGenerator.TONE_DTMF_5
        private const val ARRIVED_TONE_HIGH = ToneGenerator.TONE_DTMF_9
    }
}
