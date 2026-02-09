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

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.windowsizeclass.WindowSizeClass
import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.openhiker.android.ui.community.CommunityBrowseScreen
import com.openhiker.android.ui.community.CommunityRouteDetailScreen
import com.openhiker.android.ui.community.RouteUploadScreen
import com.openhiker.android.ui.hikes.HikeDetailScreen
import com.openhiker.android.ui.hikes.HikeListScreen
import com.openhiker.android.ui.map.MapScreen
import com.openhiker.android.ui.regions.RegionListScreen
import com.openhiker.android.ui.regions.RegionSelectorScreen
import com.openhiker.android.ui.routing.NavigationScreen
import com.openhiker.android.ui.routing.RouteDetailScreen
import com.openhiker.android.ui.routing.RoutePlanningScreen
import com.openhiker.android.ui.settings.SettingsScreen
import com.openhiker.android.ui.waypoints.AddWaypointScreen
import com.openhiker.android.ui.waypoints.WaypointDetailScreen
import com.openhiker.android.ui.waypoints.WaypointListScreen

/**
 * Navigation route constants for all app destinations.
 *
 * Each constant maps to a composable screen in the NavHost graph.
 * Top-level tabs use simple route strings; detail screens use
 * parameterised routes (e.g., "hike_detail/{hikeId}").
 */
object Routes {
    const val NAVIGATE = "navigate"
    const val REGIONS = "regions"
    const val REGION_SELECTOR = "region_selector"
    const val HIKES = "hikes"
    const val HIKE_DETAIL = "hike_detail/{hikeId}"
    const val ROUTES = "routes"
    const val ROUTE_DETAIL = "route_detail/{routeId}"
    const val COMMUNITY = "community"
    const val COMMUNITY_ROUTE_DETAIL = "community_route_detail/{routePath}"
    const val ROUTE_UPLOAD = "route_upload/{routeId}"
    const val SETTINGS = "settings"
    const val TURN_BY_TURN = "turn_by_turn/{routeId}"
    const val WAYPOINTS = "waypoints"
    const val WAYPOINT_DETAIL = "waypoint_detail/{waypointId}"
    const val ADD_WAYPOINT = "add_waypoint"

    /** Builds the hike detail route with a specific hike ID. */
    fun hikeDetail(hikeId: String): String = "hike_detail/$hikeId"

    /** Builds the route detail route with a specific route ID. */
    fun routeDetail(routeId: String): String = "route_detail/$routeId"

    /** Builds the turn-by-turn navigation route with a specific route ID. */
    fun turnByTurn(routeId: String): String = "turn_by_turn/$routeId"

    /** Builds the waypoint detail route with a specific waypoint ID. */
    fun waypointDetail(waypointId: String): String = "waypoint_detail/$waypointId"

    /** Builds the community route detail route with the repository path. */
    fun communityRouteDetail(routePath: String): String =
        "community_route_detail/${java.net.URLEncoder.encode(routePath, "UTF-8")}"

    /** Builds the route upload route with a specific route ID. */
    fun routeUpload(routeId: String): String = "route_upload/$routeId"
}

/**
 * Represents a navigation tab with its route, label, and icon.
 *
 * Used for both bottom navigation (compact) and navigation rail (medium/expanded).
 *
 * @property route The navigation route string for this tab.
 * @property label The display label shown with the tab icon.
 * @property icon The Material icon displayed in the navigation bar or rail.
 */
data class NavItem(
    val route: String,
    val label: String,
    val icon: ImageVector
)

/** Navigation tabs displayed in the bottom bar or navigation rail. */
val navItems = listOf(
    NavItem(Routes.NAVIGATE, "Navigate", Icons.Default.Explore),
    NavItem(Routes.REGIONS, "Regions", Icons.Default.Map),
    NavItem(Routes.HIKES, "Hikes", Icons.Default.Hiking),
    NavItem(Routes.ROUTES, "Routes", Icons.Default.Route),
    NavItem(Routes.COMMUNITY, "Community", Icons.Default.People)
)

/**
 * Root composable for app navigation with adaptive layout.
 *
 * Uses [WindowSizeClass] to choose the navigation pattern:
 * - **Compact width** (phones): Bottom navigation bar
 * - **Medium/Expanded width** (tablets, foldables): Navigation rail on the left
 *
 * Sets up a [Scaffold] with:
 * - A top app bar with the current screen title and settings gear icon
 * - Adaptive navigation (bottom bar or rail) with 5 tabs
 * - A [NavHost] that renders the appropriate screen for each route
 *
 * @param windowSizeClass The current window size classification from the activity.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppNavigation(windowSizeClass: WindowSizeClass) {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination
    val useNavigationRail = windowSizeClass.widthSizeClass != WindowWidthSizeClass.Compact

    val currentTitle = navItems.find { item ->
        currentDestination?.hierarchy?.any { it.route == item.route } == true
    }?.label ?: when (currentDestination?.route) {
        Routes.SETTINGS -> "Settings"
        Routes.REGION_SELECTOR -> "Download Region"
        Routes.HIKE_DETAIL -> "Hike Detail"
        Routes.ROUTE_DETAIL -> "Route Detail"
        Routes.COMMUNITY_ROUTE_DETAIL -> "Community Route"
        Routes.ROUTE_UPLOAD -> "Share Route"
        Routes.WAYPOINTS -> "Waypoints"
        Routes.WAYPOINT_DETAIL -> "Waypoint"
        Routes.ADD_WAYPOINT -> "Add Waypoint"
        else -> "OpenHiker"
    }

    // Hide top/bottom bars on full-screen pages (detail screens have their own top bar)
    val isFullScreen = currentDestination?.route in setOf(
        Routes.REGION_SELECTOR,
        Routes.TURN_BY_TURN,
        Routes.HIKE_DETAIL,
        Routes.ROUTE_DETAIL,
        Routes.COMMUNITY_ROUTE_DETAIL,
        Routes.ROUTE_UPLOAD,
        Routes.WAYPOINT_DETAIL,
        Routes.ADD_WAYPOINT
    )

    if (useNavigationRail && !isFullScreen) {
        // ── Tablet / Foldable: Navigation Rail on left ──────────
        Row(modifier = Modifier.fillMaxSize()) {
            AdaptiveNavigationRail(
                navController = navController,
                currentRoute = currentDestination?.route
            )
            Scaffold(
                topBar = {
                    TopAppBar(
                        title = { Text(currentTitle) },
                        actions = {
                            IconButton(
                                onClick = {
                                    navController.navigate(Routes.SETTINGS) {
                                        launchSingleTop = true
                                    }
                                },
                                modifier = Modifier.semantics {
                                    contentDescription = "Open settings"
                                }
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Settings,
                                    contentDescription = "Settings"
                                )
                            }
                        }
                    )
                }
            ) { innerPadding ->
                AppNavHost(
                    navController = navController,
                    modifier = Modifier.padding(innerPadding)
                )
            }
        }
    } else {
        // ── Phone: Bottom Navigation Bar ────────────────────────
        Scaffold(
            topBar = {
                if (!isFullScreen) {
                    TopAppBar(
                        title = { Text(currentTitle) },
                        actions = {
                            IconButton(
                                onClick = {
                                    navController.navigate(Routes.SETTINGS) {
                                        launchSingleTop = true
                                    }
                                },
                                modifier = Modifier.semantics {
                                    contentDescription = "Open settings"
                                }
                            ) {
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
                        navItems.forEach { item ->
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
                                },
                                modifier = Modifier.semantics {
                                    contentDescription = "${item.label} tab"
                                }
                            )
                        }
                    }
                }
            }
        ) { innerPadding ->
            AppNavHost(
                navController = navController,
                modifier = Modifier.padding(innerPadding)
            )
        }
    }
}

/**
 * Navigation rail for tablet and foldable layouts.
 *
 * Displays a vertical rail of navigation items on the left side of the screen,
 * with a Settings icon button at the top. Used when the window width is
 * [WindowWidthSizeClass.Medium] or [WindowWidthSizeClass.Expanded].
 *
 * @param navController The app's NavHostController for navigation.
 * @param currentRoute The currently active route for selection highlighting.
 */
@Composable
private fun AdaptiveNavigationRail(
    navController: NavHostController,
    currentRoute: String?
) {
    NavigationRail(
        header = {
            IconButton(
                onClick = {
                    navController.navigate(Routes.SETTINGS) {
                        launchSingleTop = true
                    }
                },
                modifier = Modifier.semantics {
                    contentDescription = "Open settings"
                }
            ) {
                Icon(
                    imageVector = Icons.Default.Settings,
                    contentDescription = "Settings"
                )
            }
        }
    ) {
        navItems.forEach { item ->
            val selected = currentRoute == item.route

            NavigationRailItem(
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
                },
                modifier = Modifier.semantics {
                    contentDescription = "${item.label} tab"
                }
            )
        }
    }
}

/**
 * Central navigation host containing all screen destinations.
 *
 * Extracted from AppNavigation to be shared between phone (Scaffold)
 * and tablet (Row + NavigationRail + Scaffold) layouts.
 *
 * @param navController The shared NavHostController.
 * @param modifier Modifier applied to the NavHost container.
 */
@Composable
private fun AppNavHost(
    navController: NavHostController,
    modifier: Modifier = Modifier
) {
    NavHost(
        navController = navController,
        startDestination = Routes.NAVIGATE,
        modifier = modifier
    ) {
        // ── Tab screens ──────────────────────────────────────────

        composable(Routes.NAVIGATE) { MapScreen() }

        composable(Routes.REGIONS) {
            RegionListScreen(
                onNavigateToSelector = {
                    navController.navigate(Routes.REGION_SELECTOR)
                },
                onViewOnMap = {
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

        composable(Routes.HIKES) {
            HikeListScreen(
                onNavigateToDetail = { hikeId ->
                    navController.navigate(Routes.hikeDetail(hikeId))
                }
            )
        }

        composable(Routes.ROUTES) {
            RoutePlanningScreen(
                onStartNavigation = { routeId ->
                    navController.navigate(Routes.turnByTurn(routeId)) {
                        launchSingleTop = true
                    }
                }
            )
        }

        composable(Routes.COMMUNITY) {
            CommunityBrowseScreen(
                onNavigateToDetail = { routePath ->
                    navController.navigate(Routes.communityRouteDetail(routePath))
                }
            )
        }
        composable(Routes.SETTINGS) { SettingsScreen() }

        // ── Community route detail ───────────────────────────────

        composable(
            route = Routes.COMMUNITY_ROUTE_DETAIL,
            arguments = listOf(navArgument("routePath") { type = NavType.StringType })
        ) {
            CommunityRouteDetailScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }

        // ── Route upload ─────────────────────────────────────────

        composable(
            route = Routes.ROUTE_UPLOAD,
            arguments = listOf(navArgument("routeId") { type = NavType.StringType })
        ) {
            RouteUploadScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }

        // ── Hike detail ──────────────────────────────────────────

        composable(
            route = Routes.HIKE_DETAIL,
            arguments = listOf(navArgument("hikeId") { type = NavType.StringType })
        ) {
            HikeDetailScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }

        // ── Route detail ─────────────────────────────────────────

        composable(
            route = Routes.ROUTE_DETAIL,
            arguments = listOf(navArgument("routeId") { type = NavType.StringType })
        ) {
            RouteDetailScreen(
                onNavigateBack = { navController.popBackStack() },
                onStartNavigation = { routeId ->
                    navController.navigate(Routes.turnByTurn(routeId)) {
                        launchSingleTop = true
                    }
                }
            )
        }

        // ── Turn-by-turn navigation ──────────────────────────────

        composable(
            route = Routes.TURN_BY_TURN,
            arguments = listOf(navArgument("routeId") { type = NavType.StringType })
        ) {
            NavigationScreen(
                onNavigationStopped = { navController.popBackStack() }
            )
        }

        // ── Waypoint screens ─────────────────────────────────────

        composable(Routes.WAYPOINTS) {
            WaypointListScreen(
                onNavigateToDetail = { waypointId ->
                    navController.navigate(Routes.waypointDetail(waypointId))
                },
                onNavigateToAdd = {
                    navController.navigate(Routes.ADD_WAYPOINT)
                }
            )
        }

        composable(
            route = Routes.WAYPOINT_DETAIL,
            arguments = listOf(navArgument("waypointId") { type = NavType.StringType })
        ) { backStackEntry ->
            WaypointDetailScreen(
                waypointId = backStackEntry.arguments?.getString("waypointId") ?: "",
                onNavigateBack = { navController.popBackStack() }
            )
        }

        composable(Routes.ADD_WAYPOINT) {
            AddWaypointScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }
    }
}
