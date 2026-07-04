package app.northax.domain.model

import kotlinx.serialization.Serializable

// Weekday encoding: Int 0..6, 0=Monday … 6=Sunday (wire contract).
@Serializable
data class DomainSchedule(
    val domain: TrainingDomain,
    val weekdays: Set<Int>, // 0..6
) {
    val daysPerWeek: Int get() = weekdays.size
}

@Serializable
data class TrainingFrequency(val schedules: List<DomainSchedule>) {

    /** Distinct weekdays that have at least one session (UNION across sports). */
    val totalTrainingDays: Int get() = schedules.flatMap { it.weekdays }.toSet().size

    /** Total sessions across the week (a weekday may host more than one sport). */
    val totalSessions: Int get() = schedules.sumOf { it.weekdays.size }

    val restDaysPerWeek: Int get() = maxOf(0, 7 - totalTrainingDays)
    val isOverloaded: Boolean get() = totalTrainingDays > 6

    fun weekdays(domain: TrainingDomain): Set<Int> =
        schedules.firstOrNull { it.domain == domain }?.weekdays ?: emptySet()

    fun days(domain: TrainingDomain): Int = weekdays(domain).size

    fun settingDays(weekdays: Set<Int>, domain: TrainingDomain): TrainingFrequency {
        val clamped = weekdays.filter { it in 0..6 }.toSet()
        val idx = schedules.indexOfFirst { it.domain == domain }
        val next = schedules.toMutableList()
        when {
            idx >= 0 && clamped.isEmpty() -> next.removeAt(idx)
            idx >= 0 -> next[idx] = next[idx].copy(weekdays = clamped)
            clamped.isNotEmpty() -> next.add(DomainSchedule(domain, clamped))
        }
        return TrainingFrequency(next)
    }

    fun toggling(weekday: Int, domain: TrainingDomain): TrainingFrequency {
        if (weekday !in 0..6) return this
        val days = weekdays(domain).toMutableSet()
        if (!days.remove(weekday)) days.add(weekday)
        return settingDays(days, domain)
    }

    companion object {
        val defaultFrequency = TrainingFrequency(
            listOf(
                DomainSchedule(TrainingDomain.Cycling, setOf(0, 2, 4)),
                DomainSchedule(TrainingDomain.Strength, setOf(1, 5)),
            )
        )

        val empty = TrainingFrequency(emptyList())
    }
}
