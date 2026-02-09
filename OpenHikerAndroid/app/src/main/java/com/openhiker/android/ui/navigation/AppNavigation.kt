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

package com.openhiker.android.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Hiking
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.openhiker.android.ui.community.CommunityBrowseScreen
import com.openhiker.android.ui.hikes.HikeListScreen
import com.openhiker.android.ui.map.MapScreen
import com.openhiker.android.ui.regions.RegionListScreen
import com.openhiker.android.ui.regions.RegionSelectorScreen
import com.openhiker.android.ui.routing.RoutePlanningScreen
import com.openhiker.android.ui.settings.SettingsScreen

/**
 * Navigation route constants for all app destinations.
 *
 * Each constant maps to a composable screen in the NavHost graph.
 * Top-level tabs use simple route strings; detail screens would
 * use parameterized routes (e.g., "hike/{id}").
 */
object Routes {
    const val NAVIGATE = "navigate"
    const val REGIONS = "regions"
    const val REGION_SELECTOR = "region_selector"
    const val HIKES = "hikes"
    const val ROUTES = "routes"
    const val COMMUNITY = "community"
    const val SETTINGS = "settings"
}

/**
 * Represents a bottom navigation tab with its route, label, and icon.
 *
 * @property route The navigation route string for this tab.
 * @property label The display label shown under the tab icon.
 * @property icon The Material icon displayed in the navigation bar.
 */
data class BottomNavItem(
    val route: String,
    val label: String,
    val icon: ImageVector
)

/** Bottom navigation tabs displayed in the main navigation bar. */
val bottomNavItems = listOf(
    BottomNavItem(Routes.NAVIGATE, "Navigate", Icons.Default.Explore),
    BottomNavItem(Routes.REGIONS, "Regions", Icons.Default.Map),
    BottomNavItem(Routes.HIKES, "Hikes", Icons.Default.Hiking),
    BottomNavItem(Routes.ROUTES, "Routes", Icons.Default.Route),
    BottomNavItem(Routes.COMMUNITY, "Community", Icons.Default.People)
)

/**
 * Root composable for app navigation.
 *
 * Sets up a [Scaffold] with:
 * - A top app bar with the current screen title and settings gear icon
 * - A bottom navigation bar with 5 tabs (Navigate, Regions, Hikes, Routes, Community)
 * - A [NavHost] that renders the appropriate screen for each route
 *
 * The settings screen is accessible from the gear icon in the top bar,
 * not from the bottom navigation tabs.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppNavigation() {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination

    val currentTitle = bottomNavItems.find { item ->
        currentDestination?.hierarchy?.any { it.route == item.route } == true
    }?.label ?: when (currentDestination?.route) {
        Routes.SETTINGS -> "Settings"
        Routes.REGION_SELECTOR -> "Download Region"
        else -> "OpenHiker"
    }

    // Hide top/bottom bars on full-screen pages
    val isFullScreen = currentDestination?.route == Routes.REGION_SELECTOR

    Scaffold(
        topBar = {
            if (!isFullScreen) {
                TopAppBar(
                    title = { Text(currentTitle) },
                    actions = {
                        IconButton(onClick = {
                            navController.navigate(Routes.SETTINGS) {
                                launchSingleTop = true
                            }
                        }) {
                            Icon(
                                imageVector = Icons.Default.Settings,
                                contentDescription = "Settings"
                            )
                        }
                    }
                )
            }
        },
        bottomBar = {
            if (!isFullScreen) {
                NavigationBar {
                    bottomNavItems.forEach { item ->
                        val selected = currentDestination?.hierarchy?.any {
                            it.route == item.route
                        } == true

                        NavigationBarItem(
                            icon = { Icon(item.icon, contentDescription = item.label) },
                            label = { Text(item.label) },
                            selected = selected,
                            onClick = {
                                navController.navigate(item.route) {
                                    popUpTo(navController.graph.findStartDestination().id) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            }
                        )
                    }
                }
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Routes.NAVIGATE,
            modifier = Modifier.padding(innerPadding)
        ) {
            composable(Routes.NAVIGATE) { MapScreen() }
            composable(Routes.REGIONS) {
                RegionListScreen(
                    onNavigateToSelector = {
                        navController.navigate(Routes.REGION_SELECTOR)
                    },
                    onViewOnMap = { region ->
                        // Navigate to map tab — the MapViewModel handles offline region display
                        navController.navigate(Routes.NAVIGATE) {
                            popUpTo(navController.graph.findStartDestination().id) {
                                saveState = true
                            }
                            launchSingleTop = true
                            restoreState = true
                        }
                    }
                )
            }
            composable(Routes.REGION_SELECTOR) {
                RegionSelectorScreen(
                    onNavigateBack = { navController.popBackStack() }
                )
            }
            composable(Routes.HIKES) { HikeListScreen() }
            composable(Routes.ROUTES) { RoutePlanningScreen() }
            composable(Routes.COMMUNITY) { CommunityBrowseScreen() }
            composable(Routes.SETTINGS) { SettingsScreen() }
        }
    }
}
