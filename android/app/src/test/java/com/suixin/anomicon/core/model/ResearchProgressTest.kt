package com.suixin.anomicon.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class ResearchProgressTest {
    private val zone = ZoneId.of("Asia/Shanghai")
    private val content = ContentRef.create(ContentKind.Scp, "scp-173", "雕像")

    @Test
    fun derivesExperienceAndResearchCountFromCreditedReading() {
        val now = Instant.parse("2026-09-03T12:00:00Z").toEpochMilli()
        val progress = deriveResearchProgress(
            segments = listOf(
                ResearchActivitySegment(
                    segmentId = "segment-1",
                    content = content,
                    startedAt = now - 2 * ResearchMinuteMs,
                    endedAt = now,
                    activeMs = 2 * ResearchMinuteMs
                )
            ),
            now = now,
            zoneId = zone
        )

        assertEquals(2 * ResearchMinuteMs, progress.creditedActiveMs)
        assertEquals(1, progress.researchedContentCount)
        assertEquals(10, progress.experience)
        assertEquals(2, progress.level)
        assertEquals(ResearchRankTitle.Visitor, progress.rankTitle)
        assertTrue(progress.levelProgressPercent > 0f)
    }

    @Test
    fun appliesDailyCapBeforeCalculatingExperience() {
        val now = Instant.parse("2026-09-03T12:00:00Z").toEpochMilli()
        val progress = deriveResearchProgress(
            segments = listOf(
                ResearchActivitySegment(
                    segmentId = "segment-1",
                    content = content,
                    startedAt = now - 240 * ResearchMinuteMs,
                    endedAt = now,
                    activeMs = 240 * ResearchMinuteMs
                )
            ),
            now = now,
            zoneId = zone
        )

        assertEquals(ResearchDailyCapMs, progress.creditedActiveMs)
        assertEquals(3 * 60 + ResearchedContentReward, progress.experience)
    }

    @Test
    fun splitsCrossDayReadingWithoutLosingActiveMilliseconds() {
        val start = Instant.parse("2026-09-03T15:59:00Z").toEpochMilli()
        val end = Instant.parse("2026-09-03T16:01:00Z").toEpochMilli()
        val progress = deriveResearchProgress(
            segments = listOf(
                ResearchActivitySegment(
                    segmentId = "segment-1",
                    content = content,
                    startedAt = start,
                    endedAt = end,
                    activeMs = 2 * ResearchMinuteMs
                )
            ),
            now = end,
            zoneId = zone
        )

        assertEquals(2, progress.daily.size)
        assertEquals(2 * ResearchMinuteMs, progress.daily.sumOf { it.activeMs })
    }
}
