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

package com.openhiker.android.service.sync

import androidx.work.ListenableWorker
import org.junit.Assert.assertEquals
import org.junit.Test

/** Unit tests for [SyncWorker.workResultFor]. */
class SyncWorkerResultTest {

    @Test
    fun `a clean sync succeeds`() {
        assertEquals(ListenableWorker.Result.success(), SyncWorker.workResultFor(SyncResult()))
    }

    @Test
    fun `errors that need someone to act fail without retrying`() {
        val result = SyncResult(errors = listOf("Waypoints: bad file"), retryable = false)
        assertEquals(ListenableWorker.Result.failure(), SyncWorker.workResultFor(result))
    }

    @Test
    fun `transient errors are retried`() {
        val result = SyncResult(errors = listOf("Waypoints: provider offline"))
        assertEquals(ListenableWorker.Result.retry(), SyncWorker.workResultFor(result))
    }
}
