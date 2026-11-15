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

package com.openhiker.android.data.db

import androidx.room.ColumnInfo

/**
 * The id and last-modified time of one stored entity, without its data.
 *
 * Cloud sync reads these to decide what to upload or download without loading track or photo
 * BLOBs for every row.
 *
 * @property id The entity UUID.
 * @property modifiedAt ISO-8601 time of the last change, or null if never recorded.
 */
data class SyncStamp(
    val id: String,
    @ColumnInfo(name = "modified_at") val modifiedAt: String?
)
