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

package com.openhiker.core.community

import com.openhiker.core.model.RoutingMode

/**
 * Pure functions for filtering and sorting community route index entries.
 *
 * All functions are stateless and side-effect-free. They operate on
 * [RouteIndexEntry] lists and return new filtered/sorted lists without
 * modifying the input. Used by the CommunityViewModel to implement
 * search, filter, and sort in the community browse screen.
 */
object RouteIndexFilter {

    /**
     * Filters route entries by a case-insensitive text query.
     *
     * Matches against name, author, summary, and area fields.
     * Returns all entries if the query is blank.
     *
     * @param entries The full list of route index entries.
     * @param query The search text to match against.
     * @return Filtered list containing only matching entries.
     */
    fun filterByQuery(entries: List<RouteIndexEntry>, query: String): List<RouteIndexEntry> {
        if (query.isBlank()) return entries
        val lowerQuery = query.lowercase()
        return entries.filter { entry ->
            entry.name.lowercase().contains(lowerQuery) ||
                entry.author.lowercase().contains(lowerQuery) ||
                entry.summary.lowercase().contains(lowerQuery) ||
                entry.region.area.lowercase().contains(lowerQuery)
        }
    }

    /**
     * Filters route entries by activity type (hiking or cycling).
     *
     * Returns all entries if [activityType] is null (no filter).
     *
     * @param entries The list of route index entries.
     * @param activityType The activity type to filter by, or null for all.
     * @return Filtered list containing only entries matching the activity type.
     */
    fun filterByActivityType(
        entries: List<RouteIndexEntry>,
        activityType: RoutingMode?
    ): List<RouteIndexEntry> {
        if (activityType == null) return entries
        return entries.filter { it.activityType == activityType }
    }

    /**
     * Filters route entries by country code (ISO 3166-1 alpha-2).
     *
     * Comparison is case-insensitive. Returns all entries if [countryCode] is null or blank.
     *
     * @param entries The list of route index entries.
     * @param countryCode The ISO country code (e.g., "US", "DE"), or null for all.
     * @return Filtered list containing only entries from the specified country.
     */
    fun filterByCountry(
        entries: List<RouteIndexEntry>,
        countryCode: String?
    ): List<RouteIndexEntry> {
        if (countryCode.isNullOrBlank()) return entries
        val upperCode = countryCode.uppercase()
        return entries.filter { it.region.country.uppercase() == upperCode }
    }

    /**
     * Filters route entries whose bounding box intersects with the given viewport.
     *
     * Two bounding boxes intersect if they overlap in both latitude and longitude.
     * Returns all entries if the viewport is null.
     *
     * @param entries The list of route index entries.
     * @param viewport The bounding box of the current map viewport, or null for all.
     * @return Filtered list containing only entries visible in the viewport.
     */
    fun filterByViewport(
        entries: List<RouteIndexEntry>,
        viewport: SharedBoundingBox?
    ): List<RouteIndexEntry> {
        if (viewport == null) return entries
        return entries.filter { entry ->
            boundingBoxesIntersect(entry.boundingBox, viewport)
        }
    }

    /**
     * Applies all filters simultaneously and returns the combined result.
     *
     * Filters are applied in order: query, activity type, country, viewport.
     * Each filter is only applied if its parameter is non-null/non-blank.
     *
     * @param entries The full list of route index entries.
     * @param query Text search query, or blank for no text filter.
     * @param activityType Activity type filter, or null for all types.
     * @param countryCode Country code filter, or null for all countries.
     * @param viewport Map viewport bounding box filter, or null for all locations.
     * @return Filtered list after applying all active filters.
     */
    fun applyFilters(
        entries: List<RouteIndexEntry>,
        query: String = "",
        activityType: RoutingMode? = null,
        countryCode: String? = null,
        viewport: SharedBoundingBox? = null
    ): List<RouteIndexEntry> {
        var result = entries
        result = filterByQuery(result, query)
        result = filterByActivityType(result, activityType)
        result = filterByCountry(result, countryCode)
        result = filterByViewport(result, viewport)
        return result
    }

    /**
     * Sorts route entries by creation date, newest first.
     *
     * @param entries The list of route index entries.
     * @return A new list sorted by [RouteIndexEntry.createdAt] descending.
     */
    fun sortByDateDescending(entries: List<RouteIndexEntry>): List<RouteIndexEntry> =
        entries.sortedByDescending { it.createdAt }

    /**
     * Sorts route entries by distance, longest first.
     *
     * @param entries The list of route index entries.
     * @return A new list sorted by distance descending.
     */
    fun sortByDistanceDescending(entries: List<RouteIndexEntry>): List<RouteIndexEntry> =
        entries.sortedByDescending { it.stats.distanceMeters }

    /**
     * Sorts route entries by elevation gain, highest first.
     *
     * @param entries The list of route index entries.
     * @return A new list sorted by elevation gain descending.
     */
    fun sortByElevationDescending(entries: List<RouteIndexEntry>): List<RouteIndexEntry> =
        entries.sortedByDescending { it.stats.elevationGainMeters }

    /**
     * Sorts route entries by name, alphabetically ascending.
     *
     * Comparison is case-insensitive.
     *
     * @param entries The list of route index entries.
     * @return A new list sorted alphabetically by name.
     */
    fun sortByNameAscending(entries: List<RouteIndexEntry>): List<RouteIndexEntry> =
        entries.sortedBy { it.name.lowercase() }

    /**
     * Extracts the distinct set of country codes from route entries.
     *
     * Useful for populating a country filter dropdown in the UI.
     *
     * @param entries The list of route index entries.
     * @return Sorted list of distinct uppercase country codes.
     */
    fun distinctCountries(entries: List<RouteIndexEntry>): List<String> =
        entries.map { it.region.country.uppercase() }.distinct().sorted()

    /**
     * Checks whether two bounding boxes intersect (overlap in both axes).
     *
     * Two boxes do NOT intersect if one is entirely above, below,
     * left of, or right of the other.
     *
     * @param a First bounding box.
     * @param b Second bounding box.
     * @return True if the bounding boxes overlap.
     */
    fun boundingBoxesIntersect(a: SharedBoundingBox, b: SharedBoundingBox): Boolean =
        a.south <= b.north && a.north >= b.south && a.west <= b.east && a.east >= b.west
}
