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

import com.openhiker.core.model.RoutingMode

/**
 * Pure function for computing edge traversal cost in the routing graph.
 *
 * The cost incorporates distance, elevation (Naismith's rule for climbing,
 * Tobler's function for steep descent), surface quality, SAC difficulty
 * scale, and highway type. All constants come from [RoutingCostConfig]
 * to ensure cross-platform consistency with the iOS implementation.
 *
 * The cost roughly represents "equivalent flat-ground walking time in seconds"
 * — an edge with high elevation gain or poor surface will have a higher cost
 * than a flat paved path of the same length.
 */
object CostFunction {

    /**
     * Computes the cost of traversing an edge.
     *
     * @param distance Edge length in metres.
     * @param elevationGain Uphill elevation change in metres (positive).
     * @param elevationLoss Downhill elevation change in metres (positive).
     * @param surface OSM surface tag value (e.g., "gravel"), or null.
     * @param highway OSM highway tag value (e.g., "footway"), or null.
     * @param sacScale SAC hiking scale tag value, or null.
     * @param mode Activity type (hiking or cycling).
     * @return The computed cost in abstract units (roughly seconds of equivalent walking).
     *         Returns [RoutingCostConfig.IMPASSABLE_COST] for impassable edges.
     */
    fun edgeCost(
        distance: Double,
        elevationGain: Double,
        elevationLoss: Double,
        surface: String?,
        highway: String?,
        sacScale: String?,
        mode: RoutingMode
    ): Double {
        if (distance <= 0.0) return 0.0

        val baseSpeed = when (mode) {
            RoutingMode.HIKING -> RoutingCostConfig.HIKING_BASE_SPEED_MPS
            RoutingMode.CYCLING -> RoutingCostConfig.CYCLING_BASE_SPEED_MPS
        }

        val climbPenalty = when (mode) {
            RoutingMode.HIKING -> RoutingCostConfig.HIKING_CLIMB_PENALTY_PER_METRE
            RoutingMode.CYCLING -> RoutingCostConfig.CYCLING_CLIMB_PENALTY_PER_METRE
        }

        // Base cost: time to traverse the edge at base speed on flat ground
        var cost = distance / baseSpeed

        // Naismith's rule: add climb penalty per metre of elevation gain
        cost += elevationGain * climbPenalty

        // Tobler's descent penalty: steep downhill is slower than moderate downhill
        if (elevationLoss > 0.0 && distance > 0.0) {
            val descentGradePercent = (elevationLoss / distance) * 100.0
            val descentPenalty = RoutingCostConfig.descentMultiplier(descentGradePercent)
            cost += elevationLoss * descentPenalty
        }

        // Surface type multiplier
        val surfaceMultiplier = surfaceMultiplier(surface, mode)
        cost *= surfaceMultiplier

        // SAC scale multiplier (hiking only)
        if (mode == RoutingMode.HIKING) {
            val sacMultiplier = sacScaleMultiplier(sacScale)
            cost *= sacMultiplier
        }

        // Highway type adjustment (steps are slower for hiking)
        if (mode == RoutingMode.HIKING && highway == RoutingCostConfig.HIGHWAY_STEPS) {
            cost *= RoutingCostConfig.STEPS_HIKING_MULTIPLIER
        }

        return cost
    }

    /**
     * Looks up the surface type multiplier for the given mode.
     *
     * @param surface OSM surface tag value, or null for default.
     * @param mode Activity type.
     * @return The multiplier (>= 1.0). Higher means slower travel.
     */
    fun surfaceMultiplier(surface: String?, mode: RoutingMode): Double {
        if (surface == null) {
            return when (mode) {
                RoutingMode.HIKING -> RoutingCostConfig.DEFAULT_HIKING_SURFACE_MULTIPLIER
                RoutingMode.CYCLING -> RoutingCostConfig.DEFAULT_CYCLING_SURFACE_MULTIPLIER
            }
        }
        val multipliers = when (mode) {
            RoutingMode.HIKING -> RoutingCostConfig.HIKING_SURFACE_MULTIPLIERS
            RoutingMode.CYCLING -> RoutingCostConfig.CYCLING_SURFACE_MULTIPLIERS
        }
        return multipliers[surface] ?: when (mode) {
            RoutingMode.HIKING -> RoutingCostConfig.DEFAULT_HIKING_SURFACE_MULTIPLIER
            RoutingMode.CYCLING -> RoutingCostConfig.DEFAULT_CYCLING_SURFACE_MULTIPLIER
        }
    }

    /**
     * Looks up the SAC scale difficulty multiplier.
     *
     * @param sacScale SAC hiking scale tag value, or null for default.
     * @return The multiplier (>= 1.0). Higher means harder/slower terrain.
     */
    fun sacScaleMultiplier(sacScale: String?): Double {
        if (sacScale == null) return RoutingCostConfig.DEFAULT_SAC_SCALE_MULTIPLIER
        return RoutingCostConfig.SAC_SCALE_MULTIPLIERS[sacScale]
            ?: RoutingCostConfig.DEFAULT_SAC_SCALE_MULTIPLIER
    }
}
