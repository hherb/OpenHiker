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

/**
 * XOR-based token obfuscation for embedded GitHub PAT.
 *
 * This is NOT cryptographic security — it is a speed bump to prevent
 * casual extraction of the token from the APK binary. The real security
 * gate is the GitHub repository's branch protection rules and PR
 * approval requirement. Matches the iOS implementation's XOR key (0xA5)
 * for cross-platform consistency.
 *
 * Usage:
 * 1. At build time: `obfuscate("ghp_...")` → hex string for embedding
 * 2. At runtime: `deobfuscate(hexString)` → original PAT
 */
object TokenObfuscator {

    /** XOR key byte. Matches the iOS implementation. */
    private const val XOR_KEY: Byte = 0xA5.toByte()

    /**
     * Obfuscates a plaintext token string into a hex-encoded XOR'd byte string.
     *
     * Each byte of the UTF-8 encoded input is XOR'd with [XOR_KEY],
     * then the result is encoded as lowercase hexadecimal.
     *
     * @param plaintext The original token string (e.g., "ghp_abc123...").
     * @return Hex-encoded obfuscated string.
     */
    fun obfuscate(plaintext: String): String {
        val bytes = plaintext.toByteArray(Charsets.UTF_8)
        val xored = ByteArray(bytes.size) { i -> (bytes[i].toInt() xor XOR_KEY.toInt()).toByte() }
        return xored.joinToString("") { "%02x".format(it) }
    }

    /**
     * Deobfuscates a hex-encoded XOR'd string back to the original token.
     *
     * Reverses the [obfuscate] transformation: decodes hex, then XOR's
     * each byte with [XOR_KEY] to recover the original UTF-8 string.
     *
     * @param hex The hex-encoded obfuscated string.
     * @return The original plaintext token string.
     * @throws IllegalArgumentException If [hex] has an odd length or contains non-hex chars.
     */
    fun deobfuscate(hex: String): String {
        require(hex.length % 2 == 0) { "Hex string must have even length" }
        val bytes = ByteArray(hex.length / 2) { i ->
            hex.substring(i * 2, i * 2 + 2).toInt(HEX_RADIX).toByte()
        }
        val xored = ByteArray(bytes.size) { i -> (bytes[i].toInt() xor XOR_KEY.toInt()).toByte() }
        return String(xored, Charsets.UTF_8)
    }

    /** Radix for hexadecimal parsing. */
    private const val HEX_RADIX = 16
}
