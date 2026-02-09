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

package com.openhiker.core.routing

/**
 * Configuration constants for routing cost calculations.
 *
 * All values must match the iOS RoutingCostConfig exactly to ensure
 * identical route computation results across platforms. A route planned
 * on iOS must produce the same path when computed on Android.
 *
 * Constants are grouped by category: base speeds, surface multipliers,
 * SAC scale multipliers, descent penalties, and highway adjustments.
 */
object RoutingCostConfig {

    // ── Base speeds (Naismith's Rule) ──────────────────────────────

    /** Hiking base speed in m/s (~4.8 km/h). */
    const val HIKING_BASE_SPEED_MPS = 1.33

    /** Cycling base speed in m/s (~15 km/h). */
    const val CYCLING_BASE_SPEED_MPS = 4.17

    /** Hiking climb penalty per metre of elevation gain (Naismith: 1hr per 600m). */
    const val HIKING_CLIMB_PENALTY_PER_METRE = 7.92

    /** Cycling climb penalty per metre of elevation gain (steeper than hiking). */
    const val CYCLING_CLIMB_PENALTY_PER_METRE = 12.0

    // ── Surface type multipliers ───────────────────────────────────

    /** Surface multipliers for hiking mode. Higher = slower. */
    val HIKING_SURFACE_MULTIPLIERS: Map<String, Double> = mapOf(
        "asphalt" to 1.0,
        "concrete" to 1.0,
        "paved" to 1.0,
        "compacted" to 1.1,
        "fine_gravel" to 1.1,
        "gravel" to 1.2,
        "ground" to 1.3,
        "dirt" to 1.3,
        "earth" to 1.3,
        "grass" to 1.4,
        "rock" to 1.5,
        "pebblestone" to 1.5,
        "sand" to 1.8,
        "mud" to 2.0,
        "wood" to 1.1
    )

    /** Surface multipliers for cycling mode. Higher = slower. */
    val CYCLING_SURFACE_MULTIPLIERS: Map<String, Double> = mapOf(
        "asphalt" to 1.0,
        "concrete" to 1.0,
        "paved" to 1.0,
        "compacted" to 1.2,
        "fine_gravel" to 1.3,
        "gravel" to 1.5,
        "ground" to 2.0,
        "dirt" to 2.0,
        "earth" to 2.0,
        "grass" to 3.0,
        "rock" to 2.5,
        "pebblestone" to 2.0,
        "sand" to 3.0,
        "mud" to 4.0,
        "wood" to 1.2
    )

    /** Default surface multiplier when the surface tag is missing or unknown. */
    const val DEFAULT_HIKING_SURFACE_MULTIPLIER = 1.3
    const val DEFAULT_CYCLING_SURFACE_MULTIPLIER = 1.5

    // ── SAC scale multipliers (hiking only) ────────────────────────

    /** SAC hiking scale difficulty multipliers. Higher = slower/harder. */
    val SAC_SCALE_MULTIPLIERS: Map<String, Double> = mapOf(
        "hiking" to 1.0,
        "mountain_hiking" to 1.2,
        "demanding_mountain_hiking" to 1.5,
        "alpine_hiking" to 2.0,
        "demanding_alpine_hiking" to 3.0,
        "difficult_alpine_hiking" to 5.0
    )

    /** Default SAC scale multiplier when the tag is missing. */
    const val DEFAULT_SAC_SCALE_MULTIPLIER = 1.0

    // ── Descent penalties (Tobler's Hiking Function) ───────────────

    /** Grade threshold percentages and their descent penalty multipliers. */
    const val DESCENT_GRADE_GENTLE_PERCENT = 5.0
    const val DESCENT_GRADE_MODERATE_PERCENT = 15.0
    const val DESCENT_GRADE_STEEP_PERCENT = 25.0

    const val DESCENT_PENALTY_NONE = 0.0
    const val DESCENT_PENALTY_SLIGHT = 0.3
    const val DESCENT_PENALTY_SIGNIFICANT = 0.8
    const val DESCENT_PENALTY_VERY_STEEP = 1.5

    /**
     * Returns the descent penalty multiplier for a given grade percentage.
     *
     * Based on Tobler's Hiking Function: steeper descents are penalised
     * because they require careful stepping and braking.
     *
     * @param gradePercent Absolute descent grade as a percentage (positive value).
     * @return Penalty multiplier (0.0 = no penalty, 1.5 = very steep).
     */
    fun descentMultiplier(gradePercent: Double): Double = when {
        gradePercent < DESCENT_GRADE_GENTLE_PERCENT -> DESCENT_PENALTY_NONE
        gradePercent < DESCENT_GRADE_MODERATE_PERCENT -> DESCENT_PENALTY_SLIGHT
        gradePercent < DESCENT_GRADE_STEEP_PERCENT -> DESCENT_PENALTY_SIGNIFICANT
        else -> DESCENT_PENALTY_VERY_STEEP
    }

    // ── Highway type adjustments ───────────────────────────────────

    /** Highway type that incurs extra cost for hiking (stairs are slow). */
    const val HIGHWAY_STEPS = "steps"

    /** Multiplier applied to steps for hiking mode. */
    const val STEPS_HIKING_MULTIPLIER = 1.5

    // ── Impassable edge ────────────────────────────────────────────

    /** Cost value representing an impassable edge (prevents A* selection). */
    const val IMPASSABLE_COST = Double.MAX_VALUE

    // ── Search radius ──────────────────────────────────────────────

    /** Maximum radius in metres for snapping a coordinate to the nearest graph node. */
    const val NEAREST_NODE_SEARCH_RADIUS_METRES = 500.0

    // ── Routable highway values ────────────────────────────────────

    /**
     * OSM highway tag values that are included in the routing graph.
     *
     * Used in the Overpass query filter and during graph construction
     * to determine which ways are routable.
     */
    val ROUTABLE_HIGHWAY_VALUES: Set<String> = setOf(
        "path", "footway", "track", "cycleway", "bridleway", "steps",
        "pedestrian", "residential", "unclassified", "tertiary",
        "secondary", "primary", "trunk", "living_street", "service"
    )
}
