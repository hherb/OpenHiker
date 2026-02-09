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

package com.openhiker.android.ui.community

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DirectionsBike
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Hiking
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.openhiker.core.model.RoutingMode

/**
 * Community route browsing screen.
 *
 * Displays a searchable, filterable, sortable list of community-shared
 * hiking and cycling routes from the OpenHikerRoutes GitHub repository.
 * Supports pull-to-refresh, text search, activity type filter chips,
 * country filter, and multiple sort criteria.
 *
 * Tapping a route card navigates to the [CommunityRouteDetailScreen].
 *
 * @param onNavigateToDetail Callback to navigate to route detail with path.
 * @param viewModel The Hilt-injected ViewModel managing the browse state.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CommunityBrowseScreen(
    onNavigateToDetail: ((String) -> Unit)? = null,
    viewModel: CommunityViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(uiState.error) {
        val message = uiState.error ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(message)
        viewModel.clearError()
    }

    Box(modifier = Modifier.fillMaxSize()) {
        PullToRefreshBox(
            isRefreshing = uiState.isRefreshing,
            onRefresh = viewModel::refresh,
            modifier = Modifier.fillMaxSize()
        ) {
            Column(modifier = Modifier.fillMaxSize()) {
                // Search bar and sort/filter buttons
                SearchAndFilterBar(
                    searchQuery = uiState.searchQuery,
                    onSearchChanged = viewModel::setSearchQuery,
                    sortOption = uiState.sortOption,
                    onSortSelected = viewModel::setSortOption,
                    countryFilter = uiState.countryFilter,
                    onCountryFilterChanged = viewModel::setCountryFilter,
                    availableCountries = uiState.availableCountries
                )

                // Activity type filter chips
                ActivityFilterChips(
                    currentFilter = uiState.activityFilter,
                    onFilterChanged = viewModel::setActivityFilter
                )

                // Content
                when {
                    uiState.isLoading -> {
                        Box(
                            modifier = Modifier.fillMaxSize(),
                            contentAlignment = Alignment.Center
                        ) {
                            CircularProgressIndicator()
                        }
                    }
                    uiState.isEmpty -> {
                        EmptyCommunityList()
                    }
                    uiState.routes.isEmpty() -> {
                        Box(
                            modifier = Modifier.fillMaxSize(),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = "No routes matching your filters",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    else -> {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                            contentPadding = PaddingValues(
                                horizontal = 16.dp, vertical = 8.dp
                            )
                        ) {
                            items(
                                items = uiState.routes,
                                key = { it.id }
                            ) { route ->
                                CommunityRouteCard(
                                    route = route,
                                    onClick = { onNavigateToDetail?.invoke(route.path) }
                                )
                            }
                        }
                    }
                }
            }
        }

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier.align(Alignment.BottomCenter)
        )
    }
}

/**
 * Search bar with sort and country filter dropdown buttons.
 */
@Composable
private fun SearchAndFilterBar(
    searchQuery: String,
    onSearchChanged: (String) -> Unit,
    sortOption: CommunitySortOption,
    onSortSelected: (CommunitySortOption) -> Unit,
    countryFilter: String?,
    onCountryFilterChanged: (String?) -> Unit,
    availableCountries: List<String>
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        OutlinedTextField(
            value = searchQuery,
            onValueChange = onSearchChanged,
            placeholder = { Text("Search routes...") },
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = "Search") },
            singleLine = true,
            modifier = Modifier.weight(1f)
        )
        Spacer(modifier = Modifier.width(4.dp))
        CountryFilterButton(
            currentCountry = countryFilter,
            availableCountries = availableCountries,
            onCountrySelected = onCountryFilterChanged
        )
        SortButton(
            currentSort = sortOption,
            onSortSelected = onSortSelected
        )
    }
}

/**
 * Row of filter chips for activity type (All, Hiking, Cycling).
 */
@Composable
private fun ActivityFilterChips(
    currentFilter: RoutingMode?,
    onFilterChanged: (RoutingMode?) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        FilterChip(
            selected = currentFilter == null,
            onClick = { onFilterChanged(null) },
            label = { Text("All") }
        )
        FilterChip(
            selected = currentFilter == RoutingMode.HIKING,
            onClick = {
                onFilterChanged(if (currentFilter == RoutingMode.HIKING) null else RoutingMode.HIKING)
            },
            label = { Text("Hiking") },
            leadingIcon = if (currentFilter == RoutingMode.HIKING) {
                { Icon(Icons.Default.Hiking, contentDescription = null, modifier = Modifier.size(18.dp)) }
            } else null
        )
        FilterChip(
            selected = currentFilter == RoutingMode.CYCLING,
            onClick = {
                onFilterChanged(if (currentFilter == RoutingMode.CYCLING) null else RoutingMode.CYCLING)
            },
            label = { Text("Cycling") },
            leadingIcon = if (currentFilter == RoutingMode.CYCLING) {
                { Icon(Icons.Default.DirectionsBike, contentDescription = null, modifier = Modifier.size(18.dp)) }
            } else null
        )
    }
}

/**
 * Sort dropdown button with available sort criteria.
 */
@Composable
private fun SortButton(
    currentSort: CommunitySortOption,
    onSortSelected: (CommunitySortOption) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Box {
        IconButton(onClick = { expanded = true }) {
            Icon(Icons.Default.Sort, contentDescription = "Sort")
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            CommunitySortOption.entries.forEach { option ->
                DropdownMenuItem(
                    text = {
                        Text(
                            text = sortLabel(option),
                            fontWeight = if (option == currentSort) FontWeight.Bold else FontWeight.Normal
                        )
                    },
                    onClick = {
                        onSortSelected(option)
                        expanded = false
                    }
                )
            }
        }
    }
}

/**
 * Country filter dropdown button.
 */
@Composable
private fun CountryFilterButton(
    currentCountry: String?,
    availableCountries: List<String>,
    onCountrySelected: (String?) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Box {
        IconButton(onClick = { expanded = true }) {
            Icon(Icons.Default.FilterList, contentDescription = "Filter by country")
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(
                text = {
                    Text(
                        "All countries",
                        fontWeight = if (currentCountry == null) FontWeight.Bold else FontWeight.Normal
                    )
                },
                onClick = {
                    onCountrySelected(null)
                    expanded = false
                }
            )
            availableCountries.forEach { code ->
                DropdownMenuItem(
                    text = {
                        Text(
                            text = code,
                            fontWeight = if (code == currentCountry) FontWeight.Bold else FontWeight.Normal
                        )
                    },
                    onClick = {
                        onCountrySelected(code)
                        expanded = false
                    }
                )
            }
        }
    }
}

/**
 * Card displaying a community route summary.
 *
 * Shows name, author, activity icon, country/area, stats, and photo/waypoint counts.
 */
@Composable
private fun CommunityRouteCard(
    route: CommunityRouteListItem,
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.weight(1f)
                ) {
                    Icon(
                        imageVector = if (route.activityType == RoutingMode.HIKING)
                            Icons.Default.Hiking else Icons.Default.DirectionsBike,
                        contentDescription = route.activityType.name,
                        modifier = Modifier.size(20.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = route.name,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Text(
                    text = route.country,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(modifier = Modifier.height(4.dp))

            Text(
                text = "by ${route.author} \u2022 ${route.area}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            if (route.summary.isNotBlank()) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = route.summary,
                    style = MaterialTheme.typography.bodySmall,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                StatChip(label = "Distance", value = route.formattedDistance)
                StatChip(label = "Elevation", value = route.formattedElevation)
                StatChip(label = "Duration", value = route.formattedDuration)
            }

            if (route.photoCount > 0 || route.waypointCount > 0) {
                Spacer(modifier = Modifier.height(4.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (route.photoCount > 0) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Default.Photo, contentDescription = null,
                                modifier = Modifier.size(14.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(modifier = Modifier.width(2.dp))
                            Text(
                                "${route.photoCount}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    if (route.waypointCount > 0) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Default.Place, contentDescription = null,
                                modifier = Modifier.size(14.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(modifier = Modifier.width(2.dp))
                            Text(
                                "${route.waypointCount}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        }
    }
}

/**
 * Small label+value pair for displaying a statistic.
 */
@Composable
private fun StatChip(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/**
 * Empty state shown when no community routes exist.
 */
@Composable
private fun EmptyCommunityList() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Default.People,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "No community routes yet",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Be the first to share a route with the community!",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

/** Returns a human-readable label for a sort option. */
private fun sortLabel(option: CommunitySortOption): String = when (option) {
    CommunitySortOption.DATE -> "Newest first"
    CommunitySortOption.DISTANCE -> "Longest first"
    CommunitySortOption.ELEVATION -> "Highest first"
    CommunitySortOption.NAME -> "Name (A-Z)"
}
