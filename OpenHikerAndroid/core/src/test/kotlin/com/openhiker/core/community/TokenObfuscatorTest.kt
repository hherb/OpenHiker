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
import org.junit.Assert.assertNotEquals
import org.junit.Test

/** Unit tests for [TokenObfuscator] XOR-based token obfuscation. */
class TokenObfuscatorTest {

    @Test
    fun `obfuscate and deobfuscate roundtrip preserves original`() {
        val original = "ghp_abc123XYZ"
        val obfuscated = TokenObfuscator.obfuscate(original)
        val recovered = TokenObfuscator.deobfuscate(obfuscated)
        assertEquals(original, recovered)
    }

    @Test
    fun `obfuscated output is hex-encoded`() {
        val obfuscated = TokenObfuscator.obfuscate("test")
        // Each byte becomes 2 hex chars: 4 chars in → 8 hex chars out
        assertEquals(8, obfuscated.length)
        // All characters should be valid lowercase hex
        assert(obfuscated.all { it in '0'..'9' || it in 'a'..'f' }) {
            "Expected hex string but got: $obfuscated"
        }
    }

    @Test
    fun `obfuscated output differs from plaintext hex`() {
        val plaintext = "AB"
        val obfuscated = TokenObfuscator.obfuscate(plaintext)
        val plainHex = plaintext.toByteArray().joinToString("") { "%02x".format(it) }
        assertNotEquals(plainHex, obfuscated)
    }

    @Test
    fun `empty string roundtrips correctly`() {
        val obfuscated = TokenObfuscator.obfuscate("")
        assertEquals("", obfuscated)
        assertEquals("", TokenObfuscator.deobfuscate(""))
    }

    @Test
    fun `long GitHub PAT-like token roundtrips correctly`() {
        val token = "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgh0123"
        val recovered = TokenObfuscator.deobfuscate(TokenObfuscator.obfuscate(token))
        assertEquals(token, recovered)
    }

    @Test
    fun `special characters roundtrip correctly`() {
        val special = "token/with+special=chars&more!"
        val recovered = TokenObfuscator.deobfuscate(TokenObfuscator.obfuscate(special))
        assertEquals(special, recovered)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `deobfuscate rejects odd-length hex string`() {
        TokenObfuscator.deobfuscate("abc")
    }

    @Test
    fun `obfuscation is deterministic`() {
        val token = "ghp_test123"
        val first = TokenObfuscator.obfuscate(token)
        val second = TokenObfuscator.obfuscate(token)
        assertEquals(first, second)
    }
}
