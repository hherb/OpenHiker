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

class PausedMsAfterResumeTest {

    private val pauseStart = 1_700_000_000_000L

    @Test
    fun `first pause is added to an empty total`() {
        assertEquals(30_000L, pausedMsAfterResume(0L, pauseStart, pauseStart + 30_000))
    }

    @Test
    fun `later pauses accumulate`() {
        assertEquals(150_000L, pausedMsAfterResume(120_000L, pauseStart, pauseStart + 30_000))
    }

    @Test
    fun `missing pause start leaves the total unchanged`() {
        assertEquals(120_000L, pausedMsAfterResume(120_000L, null, pauseStart))
    }

    @Test
    fun `clock stepping back during the pause adds nothing`() {
        assertEquals(120_000L, pausedMsAfterResume(120_000L, pauseStart, pauseStart - 5_000))
    }

    @Test
    fun `resumed total keeps elapsed time where the pause froze it`() {
        // Record 100 s, pause 50 s, resume: elapsed must still read 100 s.
        val start = pauseStart - 100_000
        val resumeAt = pauseStart + 50_000
        val frozen = recordingElapsedSeconds(start, resumeAt, 0L, currentPauseStartMs = pauseStart)
        val total = pausedMsAfterResume(0L, pauseStart, resumeAt)
        assertEquals(frozen, recordingElapsedSeconds(start, resumeAt, total, null), 0.0)
        assertEquals(100.0, frozen, 0.0)
    }
}
