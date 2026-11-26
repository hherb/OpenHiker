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

package com.openhiker.android.testutil

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.job
import kotlinx.coroutines.runBlocking

/**
 * Collects the ViewModels a test creates and, in `@After`, ends their coroutines before the
 * test resets `Dispatchers.Main`.
 *
 * A ViewModel's file work runs on the IO dispatcher and resumes on Main. A test that is done
 * once the state it waits for is published can end before that resume; if Main is reset by
 * then, the resume throws and fails a later test with "uncaught exceptions before the test
 * started".
 */
class ViewModelScopes {
    private val viewModels = mutableListOf<ViewModel>()

    /**
     * Registers [viewModel] so [cancelAndJoinAll] waits for it.
     *
     * @return [viewModel], for use in an expression.
     */
    fun <T : ViewModel> track(viewModel: T): T = viewModel.also { viewModels.add(it) }

    /** Cancels every tracked ViewModel's scope and waits until its coroutines have ended. */
    fun cancelAndJoinAll() = runBlocking {
        viewModels.forEach { it.viewModelScope.coroutineContext.job.cancelAndJoin() }
    }
}
