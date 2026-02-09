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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [CostFunction] edge cost calculations.
 *
 * Verifies that routing costs correctly account for distance, elevation,
 * surface quality, SAC difficulty scale, and highway type adjustments.
 * All constants must match the iOS RoutingCostConfig.
 */
class CostFunctionTest {

    // ── Flat ground, no elevation ──────────────────────────────────

    @Test
    fun `flat paved 1000m hiking cost is distance over speed`() {
        val cost = CostFunction.edgeCost(
            distance = 1000.0,
            elevationGain = 0.0,
            elevationLoss = 0.0,
            surface = "asphalt",
            highway = "footway",
            sacScale = null,
            mode = RoutingMode.HIKING
        )
        // Expected: 1000 / 1.33 * 1.0 (asphalt) = ~751.9 seconds
        assertEquals(751.9, cost, 1.0)
    }

    @Test
    fun `flat paved 1000m cycling cost is less than hiking`() {
        val hikingCost = CostFunction.edgeCost(1000.0, 0.0, 0.0, "asphalt", "footway", null, RoutingMode.HIKING)
        val cyclingCost = CostFunction.edgeCost(1000.0, 0.0, 0.0, "asphalt", "footway", null, RoutingMode.CYCLING)
        assertTrue("Cycling should be faster", cyclingCost < hikingCost)
    }

    // ── Climb penalty ──────────────────────────────────────────────

    @Test
    fun `uphill adds Naismith penalty per metre gain`() {
        val flatCost = CostFunction.edgeCost(1000.0, 0.0, 0.0, "asphalt", "footway", null, RoutingMode.HIKING)
        val uphillCost = CostFunction.edgeCost(1000.0, 100.0, 0.0, "asphalt", "footway", null, RoutingMode.HIKING)

        val expectedPenalty = 100.0 * RoutingCostConfig.HIKING_CLIMB_PENALTY_PER_METRE
        assertEquals(flatCost + expectedPenalty, uphillCost, 1.0)
    }

    @Test
    fun `cycling climb penalty is steeper than hiking`() {
        val hikingUphill = CostFunction.edgeCost(1000.0, 100.0, 0.0, "asphalt", null, null, RoutingMode.HIKING)
        val cyclingUphill = CostFunction.edgeCost(1000.0, 100.0, 0.0, "asphalt", null, null, RoutingMode.CYCLING)

        // Cycling has higher climb penalty per metre
        val hikingFlat = CostFunction.edgeCost(1000.0, 0.0, 0.0, "asphalt", null, null, RoutingMode.HIKING)
        val cyclingFlat = CostFunction.edgeCost(1000.0, 0.0, 0.0, "asphalt", null, null, RoutingMode.CYCLING)

        val hikingClimbCostAdded = hikingUphill - hikingFlat
        val cyclingClimbCostAdded = cyclingUphill - cyclingFlat
        assertTrue("Cycling climb cost should be higher", cyclingClimbCostAdded > hikingClimbCostAdded)
    }

    // ── Descent penalty ────────────────────────────────────────────

    @Test
    fun `gentle descent has no penalty`() {
        val flatCost = CostFunction.edgeCost(1000.0, 0.0, 0.0, "asphalt", null, null, RoutingMode.HIKING)
        val gentleDownhillCost = CostFunction.edgeCost(1000.0, 0.0, 20.0, "asphalt", null, null, RoutingMode.HIKING)
        // 2% grade (20m over 1000m) should be below 5% threshold
        assertEquals(flatCost, gentleDownhillCost, 1.0)
    }

    @Test
    fun `steep descent adds penalty`() {
        val flatCost = CostFunction.edgeCost(1000.0, 0.0, 0.0, "asphalt", null, null, RoutingMode.HIKING)
        val steepDownhillCost = CostFunction.edgeCost(1000.0, 0.0, 300.0, "asphalt", null, null, RoutingMode.HIKING)
        // 30% grade should be in the "very steep" category
        assertTrue("Steep descent should cost more than flat", steepDownhillCost > flatCost)
    }

    // ── Surface multipliers ────────────────────────────────────────

    @Test
    fun `gravel surface is more expensive than asphalt`() {
        val asphaltCost = CostFunction.edgeCost(1000.0, 0.0, 0.0, "asphalt", null, null, RoutingMode.HIKING)
        val gravelCost = CostFunction.edgeCost(1000.0, 0.0, 0.0, "gravel", null, null, RoutingMode.HIKING)
        assertTrue("Gravel should cost more", gravelCost > asphaltCost)
    }

    @Test
    fun `mud surface is most expensive`() {
        val asphaltCost = CostFunction.edgeCost(1000.0, 0.0, 0.0, "asphalt", null, null, RoutingMode.HIKING)
        val mudCost = CostFunction.edgeCost(1000.0, 0.0, 0.0, "mud", null, null, RoutingMode.HIKING)
        assertTrue("Mud should cost significantly more", mudCost > 1.5 * asphaltCost)
    }

    @Test
    fun `unknown surface uses default multiplier`() {
        val unknownCost = CostFunction.edgeCost(1000.0, 0.0, 0.0, null, null, null, RoutingMode.HIKING)
        val asphaltCost = CostFunction.edgeCost(1000.0, 0.0, 0.0, "asphalt", null, null, RoutingMode.HIKING)
        // Default multiplier is 1.3 for hiking
        val expectedRatio = RoutingCostConfig.DEFAULT_HIKING_SURFACE_MULTIPLIER
        assertEquals(asphaltCost * expectedRatio, unknownCost, 1.0)
    }

    // ── SAC scale ──────────────────────────────────────────────────

    @Test
    fun `demanding alpine hiking is much more expensive`() {
        val hikingCost = CostFunction.edgeCost(1000.0, 0.0, 0.0, "rock", null, "hiking", RoutingMode.HIKING)
        val alpineCost = CostFunction.edgeCost(1000.0, 0.0, 0.0, "rock", null, "demanding_alpine_hiking", RoutingMode.HIKING)
        assertTrue("Alpine should cost 3x hiking", alpineCost > 2.5 * hikingCost)
    }

    @Test
    fun `SAC scale does not affect cycling`() {
        val noSac = CostFunction.edgeCost(1000.0, 0.0, 0.0, "asphalt", null, null, RoutingMode.CYCLING)
        val withSac = CostFunction.edgeCost(1000.0, 0.0, 0.0, "asphalt", null, "alpine_hiking", RoutingMode.CYCLING)
        assertEquals(noSac, withSac, 0.01)
    }

    // ── Highway type (steps) ───────────────────────────────────────

    @Test
    fun `steps are slower for hiking`() {
        val pathCost = CostFunction.edgeCost(100.0, 10.0, 0.0, null, "path", null, RoutingMode.HIKING)
        val stepsCost = CostFunction.edgeCost(100.0, 10.0, 0.0, null, "steps", null, RoutingMode.HIKING)
        assertTrue("Steps should cost more than path", stepsCost > pathCost)
    }

    // ── Zero distance ──────────────────────────────────────────────

    @Test
    fun `zero distance returns zero cost`() {
        val cost = CostFunction.edgeCost(0.0, 0.0, 0.0, "asphalt", null, null, RoutingMode.HIKING)
        assertEquals(0.0, cost, 0.001)
    }

    // ── Cross-platform constant verification ───────────────────────

    @Test
    fun `hiking base speed matches iOS constant`() {
        assertEquals(1.33, RoutingCostConfig.HIKING_BASE_SPEED_MPS, 0.001)
    }

    @Test
    fun `cycling base speed matches iOS constant`() {
        assertEquals(4.17, RoutingCostConfig.CYCLING_BASE_SPEED_MPS, 0.001)
    }

    @Test
    fun `hiking climb penalty matches iOS constant`() {
        assertEquals(7.92, RoutingCostConfig.HIKING_CLIMB_PENALTY_PER_METRE, 0.001)
    }

    @Test
    fun `cycling climb penalty matches iOS constant`() {
        assertEquals(12.0, RoutingCostConfig.CYCLING_CLIMB_PENALTY_PER_METRE, 0.001)
    }
}
