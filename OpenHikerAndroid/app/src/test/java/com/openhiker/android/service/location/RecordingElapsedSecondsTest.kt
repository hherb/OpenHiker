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

package com.openhiker.android.service.location

import org.junit.Assert.assertEquals
import org.junit.Test

class RecordingElapsedSecondsTest {

    private val start = 1_700_000_000_000L

    @Test
    fun `no pauses gives wall-clock time since start`() {
        assertEquals(90.0, recordingElapsedSeconds(start, start + 90_000, 0L, null), 0.0)
    }

    @Test
    fun `finished pauses are subtracted`() {
        val elapsed = recordingElapsedSeconds(start, start + 600_000, totalPausedMs = 120_000, null)
        assertEquals(480.0, elapsed, 0.0)
    }

    @Test
    fun `current pause is subtracted while paused`() {
        // Recorded 5 min, paused 1 min earlier, and paused again for the last 30 s.
        val now = start + 360_000
        val elapsed = recordingElapsedSeconds(start, now, 60_000, currentPauseStartMs = now - 30_000)
        assertEquals(270.0, elapsed, 0.0)
    }

    @Test
    fun `elapsed time stays constant while paused`() {
        val pauseStart = start + 100_000
        val early = recordingElapsedSeconds(start, pauseStart + 5_000, 0L, pauseStart)
        val late = recordingElapsedSeconds(start, pauseStart + 500_000, 0L, pauseStart)
        assertEquals(100.0, early, 0.0)
        assertEquals(early, late, 0.0)
    }

    @Test
    fun `keeps sub-second precision`() {
        assertEquals(1.5, recordingElapsedSeconds(start, start + 1_500, 0L, null), 0.0)
    }

    @Test
    fun `zero at the moment recording starts`() {
        assertEquals(0.0, recordingElapsedSeconds(start, start, 0L, null), 0.0)
    }
}
