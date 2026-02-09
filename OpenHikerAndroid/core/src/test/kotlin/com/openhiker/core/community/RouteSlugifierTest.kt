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

import org.junit.Assert.assertEquals
import org.junit.Test

/** Unit tests for [RouteSlugifier] URL-safe name generation. */
class RouteSlugifierTest {

    @Test
    fun `simple name slugifies correctly`() {
        assertEquals("mount-tamalpais", RouteSlugifier.slugify("Mount Tamalpais"))
    }

    @Test
    fun `special characters are removed`() {
        assertEquals("blue-ridge-trail", RouteSlugifier.slugify("Blue Ridge Trail!"))
    }

    @Test
    fun `multiple spaces collapse to single hyphen`() {
        assertEquals("some-trail", RouteSlugifier.slugify("Some   Trail"))
    }

    @Test
    fun `underscores become hyphens`() {
        assertEquals("my-route", RouteSlugifier.slugify("my_route"))
    }

    @Test
    fun `leading and trailing hyphens are trimmed`() {
        assertEquals("trail", RouteSlugifier.slugify("---trail---"))
    }

    @Test
    fun `empty input returns default slug`() {
        assertEquals("unnamed-route", RouteSlugifier.slugify(""))
    }

    @Test
    fun `all special characters returns default slug`() {
        assertEquals("unnamed-route", RouteSlugifier.slugify("!@#$%^&*()"))
    }

    @Test
    fun `unicode characters are removed`() {
        assertEquals("grner-see", RouteSlugifier.slugify("Grüner See"))
    }

    @Test
    fun `long names are truncated to max length`() {
        val longName = "a".repeat(100)
        val slug = RouteSlugifier.slugify(longName)
        assertEquals(80, slug.length)
    }

    @Test
    fun `numbers are preserved`() {
        assertEquals("trail-42", RouteSlugifier.slugify("Trail 42"))
    }

    @Test
    fun `mixed case becomes lowercase`() {
        assertEquals("camelcase", RouteSlugifier.slugify("CamelCase"))
    }
}
