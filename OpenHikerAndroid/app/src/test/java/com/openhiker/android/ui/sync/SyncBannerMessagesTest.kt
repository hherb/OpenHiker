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

package com.openhiker.android.ui.sync

import com.openhiker.android.data.sync.SyncState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Unit tests for [syncBannerMessages] and [canRetry]. */
class SyncBannerMessagesTest {

    @Test
    fun `nothing to show before the state is read or after a clean sync`() {
        assertEquals(emptyList<String>(), syncBannerMessages(null, null))
        assertEquals(emptyList<String>(), syncBannerMessages(SyncState(), null))
    }

    @Test
    fun `errors come under a heading, then the reset notice, then an action error`() {
        val state = SyncState(lastErrors = listOf("Waypoints: boom"), stateWasReset = true)
        assertEquals(
            listOf(SYNC_FAILED_HEADING, "Waypoints: boom", STATE_RESET_NOTICE, "Sync failed: x"),
            syncBannerMessages(state, "Sync failed: x")
        )
    }

    @Test
    fun `the reset notice shows without a heading when the last sync was clean`() {
        assertEquals(
            listOf(STATE_RESET_NOTICE),
            syncBannerMessages(SyncState(stateWasReset = true), null)
        )
    }

    @Test
    fun `retry shows only after a failed sync, with sync on and a folder set`() {
        val failed = SyncState(lastErrors = listOf("boom"))
        assertTrue(canRetry(failed, syncEnabled = true, folderUri = "content://f"))
        assertFalse(canRetry(null, syncEnabled = true, folderUri = "content://f"))
        assertFalse(canRetry(failed, syncEnabled = true, folderUri = null))
        assertFalse(canRetry(failed, syncEnabled = false, folderUri = "content://f"))
        assertFalse(
            canRetry(SyncState(stateWasReset = true), syncEnabled = true, folderUri = "content://f")
        )
    }
}
