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

package com.openhiker.android.ui.settings

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsToggleable
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import org.junit.Rule
import org.junit.Test

/**
 * Compose UI instrumentation tests for [SettingsScreen].
 *
 * These tests verify that all settings sections are visible and interactive.
 * They require an Android device or emulator to run as they use the Compose
 * test framework ([createComposeRule]).
 *
 * Note: These tests scaffold the UI test infrastructure. They will need a
 * Hilt test rule or manual ViewModel injection to run against the full
 * SettingsScreen with real ViewModels. For now they verify the composable
 * structure using test tags.
 */
class SettingsScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    @Test
    fun settingsScreen_displaysMapSection() {
        composeTestRule.setContent {
            SettingsScreen()
        }
        composeTestRule.onNodeWithText("Map").assertIsDisplayed()
        composeTestRule.onNodeWithTag("map_settings_card").assertIsDisplayed()
    }

    @Test
    fun settingsScreen_displaysGpsSection() {
        composeTestRule.setContent {
            SettingsScreen()
        }
        composeTestRule.onNodeWithText("GPS").assertIsDisplayed()
        composeTestRule.onNodeWithTag("gps_settings_card").assertIsDisplayed()
    }

    @Test
    fun settingsScreen_displaysNavigationSection() {
        composeTestRule.setContent {
            SettingsScreen()
        }
        composeTestRule.onNodeWithText("Navigation").assertIsDisplayed()
        composeTestRule.onNodeWithTag("navigation_settings_card").assertIsDisplayed()
    }

    @Test
    fun settingsScreen_displaysDownloadsSection() {
        composeTestRule.setContent {
            SettingsScreen()
        }
        composeTestRule.onNodeWithText("Downloads")
            .performScrollTo()
            .assertIsDisplayed()
        composeTestRule.onNodeWithTag("download_settings_card")
            .performScrollTo()
            .assertIsDisplayed()
    }

    @Test
    fun settingsScreen_displaysCloudSyncSection() {
        composeTestRule.setContent {
            SettingsScreen()
        }
        composeTestRule.onNodeWithText("Cloud Sync")
            .performScrollTo()
            .assertIsDisplayed()
        composeTestRule.onNodeWithTag("cloud_sync_card")
            .performScrollTo()
            .assertIsDisplayed()
    }

    @Test
    fun settingsScreen_displaysStorageSection() {
        composeTestRule.setContent {
            SettingsScreen()
        }
        composeTestRule.onNodeWithText("Storage")
            .performScrollTo()
            .assertIsDisplayed()
        composeTestRule.onNodeWithTag("storage_card")
            .performScrollTo()
            .assertIsDisplayed()
    }

    @Test
    fun settingsScreen_displaysAboutSection() {
        composeTestRule.setContent {
            SettingsScreen()
        }
        composeTestRule.onNodeWithText("About")
            .performScrollTo()
            .assertIsDisplayed()
        composeTestRule.onNodeWithTag("about_card")
            .performScrollTo()
            .assertIsDisplayed()
    }

    @Test
    fun settingsScreen_aboutCardShowsLicense() {
        composeTestRule.setContent {
            SettingsScreen()
        }
        composeTestRule.onNodeWithText("GNU Affero General Public License v3.0 (AGPL-3.0)", substring = true)
            .performScrollTo()
            .assertIsDisplayed()
    }

    @Test
    fun settingsScreen_aboutCardShowsCopyright() {
        composeTestRule.setContent {
            SettingsScreen()
        }
        composeTestRule.onNodeWithText("Dr Horst Herb", substring = true)
            .performScrollTo()
            .assertIsDisplayed()
    }

    @Test
    fun settingsScreen_hapticToggleExists() {
        composeTestRule.setContent {
            SettingsScreen()
        }
        composeTestRule.onNodeWithTag("haptic_toggle")
            .performScrollTo()
            .assertIsDisplayed()
    }

    @Test
    fun settingsScreen_audioCuesToggleExists() {
        composeTestRule.setContent {
            SettingsScreen()
        }
        composeTestRule.onNodeWithTag("audio_cues_toggle")
            .performScrollTo()
            .assertIsDisplayed()
    }

    @Test
    fun settingsScreen_syncToggleExists() {
        composeTestRule.setContent {
            SettingsScreen()
        }
        composeTestRule.onNodeWithTag("sync_toggle")
            .performScrollTo()
            .assertIsDisplayed()
    }
}
