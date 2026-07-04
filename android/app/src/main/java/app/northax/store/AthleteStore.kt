package app.northax.store

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.northax.BuildConfig
import app.northax.data.AppContainer
import app.northax.data.remote.dto.ActivityCreateRequest
import app.northax.data.remote.dto.CoachMessageRequest
import app.northax.data.remote.dto.ManualMetricsRequest
import app.northax.data.remote.CoachStreamEvent
import app.northax.data.toDto
import app.northax.domain.engine.PlanEngine
import app.northax.domain.engine.PlanMatchingEngine
import app.northax.domain.engine.ReadinessEngine
import app.northax.domain.engine.SessionMatch
import app.northax.domain.engine.WeekData
import app.northax.domain.model.ActivitySourcePriority
import app.northax.domain.model.ActivityStreams
import app.northax.domain.model.AthleteThresholds
import app.northax.domain.model.AuthUser
import app.northax.domain.model.CoachMessage
import app.northax.domain.model.DailyReadiness
import app.northax.domain.model.GarminActivity
import app.northax.domain.model.GarminActivityType
import app.northax.domain.model.GoalCheck
import app.northax.domain.model.LoggedExercise
import app.northax.domain.model.MetricSourcePriority
import app.northax.domain.model.PlannedDay
import app.northax.domain.model.PlannedSession
import app.northax.domain.model.SessionOverride
import app.northax.domain.model.SportTarget
import app.northax.domain.model.SwitchSuggestion
import app.northax.domain.model.TrainingDomain
import app.northax.domain.model.TrainingFrequency
import app.northax.domain.model.TrainingMetrics
import app.northax.domain.model.WeeklyMuscleGroupSplit
import app.northax.domain.model.WeeklyPlan
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.UUID

/** Main tab identity — exposed so deep-link buttons can jump to a tab. */
enum class AppTab { Dashboard, Coach, Metrics, Plan, Settings }

/**
 * Central view-model. When a backend session exists it loads live data
 * (readiness, metrics, plan, coach, preferences) and reconciles optimistic
 * local engine output with the server; offline (or debug) it falls back to the
 * client engines and mock seed so the UI always has data. Port of the iOS
 * AthleteStore — property observers become explicit update functions.
 */
class AthleteStore(private val container: AppContainer) : ViewModel() {

    private val api = container.api
    private val prefs = container.prefs
    private val tokens = container.tokens

    var athleteName by mutableStateOf("Athlete")
    var enabledDomains by mutableStateOf(listOf(TrainingDomain.Cycling, TrainingDomain.Strength))
        private set
    var muscleGroupSplit by mutableStateOf(WeeklyMuscleGroupSplit.pushPullLegs)
        private set

    /** Structured-workout target for cycling: "hr" (default) or "power". */
    var cyclingTarget by mutableStateOf("hr")
        private set

    /** Per-sport goal targets. They only influence the AI planner, so changes
     *  are staged plan changes. */
    var sportTargets by mutableStateOf<Map<TrainingDomain, SportTarget>>(emptyMap())
        private set

    /** Latest AI goal-progress verdicts (dashboard "Goal check" card). */
    var goalChecks by mutableStateOf<List<GoalCheck>>(emptyList())

    /** Athlete physiological thresholds. */
    var thresholds by mutableStateOf(AthleteThresholds())
        private set

    /** Live wellness data — null means "no data yet". The UI shows an empty
     *  state rather than fabricated values. */
    var metrics by mutableStateOf<TrainingMetrics?>(null)
    var readiness by mutableStateOf<DailyReadiness?>(null)
    var messages by mutableStateOf(listOf(CoachMessage.opening))

    /** Which main tab is shown. */
    var selectedTab by mutableStateOf(AppTab.Dashboard)

    /** True only for a "Continue as Debug User" session (no backend tokens). */
    var isDebugSession by mutableStateOf(false)
        private set

    // Training frequency + plan — persisted across launches
    var trainingFrequency by mutableStateOf(prefs.loadFrequency())
        private set

    var weeklyPlans by mutableStateOf<List<WeeklyPlan>>(emptyList())

    /** Imported workouts used to mark planned sessions done. */
    var weekActivities by mutableStateOf<List<GarminActivity>>(emptyList())

    /** Pre-fetched AI switch suggestions, keyed by [SessionMatch.suggestionKey]. */
    val dailySuggestions = mutableStateMapOf<String, List<SwitchSuggestion>>()

    /** Suggestion keys currently being fetched — drives the detail loading state. */
    var suggestionsLoading by mutableStateOf<Set<String>>(emptySet())
        private set

    var planWasRecentlyUpdated by mutableStateOf(false)

    /** True while the AI planner runs — drives the full-screen loading overlay. */
    var isGeneratingPlan by mutableStateOf(false)
        private set

    /** A plan-affecting preference changed but hasn't been applied yet. The
     *  plan is only (re)generated by [applyPlanChanges]. */
    var pendingPlanChanges by mutableStateOf(false)

    var hasSetFrequency by mutableStateOf(prefs.hasSetFrequency)
        private set

    /** Per-metric source ranking for multi-integration conflict resolution. */
    var metricPriority by mutableStateOf(prefs.loadMetricPriority())
        private set

    /** Ordered activity-source preference; synced to the backend on change. */
    var activityPriority by mutableStateOf(ActivitySourcePriority.default)
        private set

    val intervals = IntervalsService(api)
    val strava = StravaService(api)

    /** Set while applying server state so update functions don't echo back. */
    private var suppressServerSync = false

    init {
        // Only build a local plan for a returning user who already defined
        // their frequency (offline-friendly). A new user starts with no plan.
        if (trainingFrequency.totalTrainingDays > 0) {
            weeklyPlans = PlanEngine.generatePlans(
                weeks = 4, frequency = trainingFrequency, muscleGroupSplit = muscleGroupSplit,
            )
        }
    }

    // MARK: - Preference setters (iOS `didSet` observers made explicit)

    fun setHasSetFrequencyFlag(value: Boolean) {
        hasSetFrequency = value
        prefs.hasSetFrequency = value
    }

    /** Rename the athlete locally and persist to the profile endpoint. */
    fun saveAthleteName(name: String) {
        athleteName = name
        if (tokens.hasSession) {
            viewModelScope.launch { runCatching { api.updateProfileName(name) } }
        }
    }

    fun updateEnabledDomains(domains: List<TrainingDomain>) {
        val changed = domains != enabledDomains
        enabledDomains = domains
        if (changed && !suppressServerSync && tokens.hasSession) {
            viewModelScope.launch { runCatching { api.updateDomains(domains) } }
        }
    }

    fun updateMuscleGroupSplit(split: WeeklyMuscleGroupSplit) {
        muscleGroupSplit = split
        if (suppressServerSync) return
        if (tokens.hasSession) {
            pendingPlanChanges = true // staged — applied via applyPlanChanges()
        } else {
            regeneratePlan()          // offline/debug: instant local plan
        }
    }

    fun updateCyclingTarget(target: String) {
        val changed = target != cyclingTarget
        cyclingTarget = target
        if (!changed || suppressServerSync) return
        if (tokens.hasSession) {
            pendingPlanChanges = true
        } else {
            regeneratePlan()
        }
    }

    fun updateSportTargets(targets: Map<TrainingDomain, SportTarget>) {
        val changed = targets != sportTargets
        sportTargets = targets
        if (changed && !suppressServerSync && tokens.hasSession) {
            pendingPlanChanges = true
        }
    }

    /** PATCHes a partial merge; does NOT regenerate plans (zones are render-time). */
    fun updateThresholds(value: AthleteThresholds) {
        val changed = value != thresholds
        thresholds = value
        if (changed && !suppressServerSync && tokens.hasSession) {
            viewModelScope.launch { runCatching { api.updateThresholds(value) } }
        }
    }

    fun updateTrainingFrequency(freq: TrainingFrequency) {
        if (freq == trainingFrequency) return
        trainingFrequency = freq
        prefs.saveFrequency(freq)
        if (suppressServerSync) return
        if (tokens.hasSession) {
            pendingPlanChanges = true
        } else {
            regeneratePlan()
        }
    }

    fun updateMetricPriority(priority: MetricSourcePriority) {
        val changed = priority != metricPriority
        metricPriority = priority
        prefs.saveMetricPriority(priority)
        if (changed && !suppressServerSync && tokens.hasSession) {
            viewModelScope.launch { runCatching { api.updateMetricPriority(priority) } }
        }
    }

    fun updateActivityPriority(priority: ActivitySourcePriority) {
        val changed = priority != activityPriority
        activityPriority = priority
        if (changed && !suppressServerSync && tokens.hasSession) {
            viewModelScope.launch { runCatching { api.updateActivityPriority(priority) } }
        }
    }

    // MARK: - Session lifecycle

    /** Called when the signed-in user changes. */
    fun configure(user: AuthUser) {
        if (user.name.isNotEmpty()) athleteName = user.name
        if (tokens.hasSession) {
            isDebugSession = false
            viewModelScope.launch { loadFromBackend() }
        } else if (BuildConfig.DEBUG) {
            // No backend tokens means this is the "Continue as Debug User"
            // bypass. Seed the demo data so the UI is explorable offline.
            isDebugSession = true
            metrics = TrainingMetrics.mockFresh
            recalculate()
            val demoFrequency = if (trainingFrequency.totalTrainingDays > 0) trainingFrequency
            else TrainingFrequency.defaultFrequency
            weeklyPlans = PlanEngine.generatePlans(
                weeks = 4, frequency = demoFrequency, muscleGroupSplit = muscleGroupSplit,
            )
        }
    }

    fun resetForSignOut() {
        setHasSetFrequencyFlag(false)
        trainingFrequency = TrainingFrequency.empty // no assumed plan after sign-out
        prefs.saveFrequency(TrainingFrequency.empty)
        messages = listOf(CoachMessage.opening)
        isDebugSession = false
        metrics = null
        readiness = null
        weeklyPlans = emptyList()
        sportTargets = emptyMap()
        goalChecks = emptyList()
    }

    // MARK: - Backend loading

    /** Pull live data when authenticated; no-op (engine/mock) otherwise. */
    suspend fun loadFromBackend() {
        if (!tokens.hasSession) return
        loadPreferences()
        loadMetricsAndReadiness()
        loadPlans()
        loadActivities()
        loadGoalProgress()
        prefetchDailySuggestionsIfNeeded()
        loadCoachHistory()
        intervals.refreshStatus()
        strava.refreshStatus()
        syncConnectedSourcesIfNeeded() // pull latest from connected sources on open
    }

    suspend fun loadPreferences() {
        val loaded = runCatching { api.preferences() }.getOrNull() ?: return
        suppressServerSync = true
        if (loaded.enabledDomains.isNotEmpty()) enabledDomains = loaded.enabledDomains
        muscleGroupSplit = loaded.split
        trainingFrequency = loaded.frequency
        prefs.saveFrequency(loaded.frequency)
        if (loaded.frequency.totalTrainingDays > 0) setHasSetFrequencyFlag(true)
        cyclingTarget = loaded.cyclingTarget
        sportTargets = loaded.sportTargets
        thresholds = loaded.thresholds
        metricPriority = loaded.metricPriority
        prefs.saveMetricPriority(loaded.metricPriority)
        activityPriority = loaded.activityPriority
        suppressServerSync = false
    }

    suspend fun loadMetricsAndReadiness() {
        // No mock fallback: when no source has data, metrics/readiness stay
        // null and the UI shows an empty state instead of fabricated numbers.
        metrics = runCatching { api.metricsToday() }.getOrNull()

        val r = runCatching { api.readinessToday() }.getOrNull()
        if (r != null) {
            readiness = r
        } else {
            recalculate() // engine result from real metrics, or null if none
        }
    }

    /** Submit user-entered wellness values as a `manual` source, then reload
     *  so the resolved metrics reflect the new reading. Requires a session. */
    suspend fun submitManualMetrics(hrv: Double?, restingHR: Int?, sleepHours: Double?, weight: Double?) {
        if (!tokens.hasSession) return
        val req = ManualMetricsRequest(
            date = LocalDate.now().toString(),
            hrv = hrv, restingHr = restingHR,
            sleepDuration = sleepHours, sleepScore = null, bodyWeight = weight,
        )
        if (runCatching { api.submitManualMetrics(req) }.isSuccess) {
            loadMetricsAndReadiness()
        }
    }

    /** Persist a live-logged strength workout as a `manual` activity so the
     *  plan matcher marks the session done. In a debug session it's appended
     *  locally so the flow stays explorable offline. Returns false when the
     *  backend rejects the save (caller shows an error). */
    suspend fun logStrengthWorkout(
        title: String,
        startedAt: Instant,
        durationSeconds: Int,
        exercises: List<LoggedExercise>,
    ): Boolean {
        val name = title.ifEmpty { "Strength Workout" }
        if (tokens.hasSession) {
            val request = ActivityCreateRequest(
                name = name, domain = TrainingDomain.Strength.raw,
                startTime = startedAt, durationSeconds = durationSeconds,
                strengthExercises = exercises.map { it.toDto() },
            )
            if (runCatching { api.createActivity(request) }.isFailure) return false
            loadActivities()
        } else {
            weekActivities = weekActivities + GarminActivity(
                id = UUID.randomUUID().toString(), name = name,
                type = GarminActivityType.StrengthTraining,
                startTime = startedAt, durationSeconds = durationSeconds.toLong(),
                strengthExercises = exercises,
            )
        }
        return true
    }

    /** Rewrite the exercise log of a completed strength workout. Debug sessions
     *  edit the local copy so the flow stays explorable offline. Returns false
     *  when the backend rejects the update (caller shows an error). */
    suspend fun updateStrengthWorkout(activityId: String, exercises: List<LoggedExercise>): Boolean {
        if (tokens.hasSession) {
            val result = runCatching {
                api.updateActivityExercises(activityId, exercises.map { it.toDto() })
            }
            if (result.isFailure) return false
            loadActivities()
        } else {
            weekActivities = weekActivities.map {
                if (it.id == activityId) it.copy(strengthExercises = exercises) else it
            }
        }
        return true
    }

    suspend fun loadPlans() {
        val plans = runCatching { api.plans(weeks = 4) }.getOrNull()
        if (!plans.isNullOrEmpty()) weeklyPlans = plans
    }

    suspend fun loadActivities() {
        runCatching { api.activities(limit = 50) }.getOrNull()?.let { weekActivities = it }
    }

    /** Latest AI goal-progress verdicts (empty on failure or when no sport has
     *  a target). Refreshed on load and after a source sync. */
    suspend fun loadGoalProgress() {
        if (!tokens.hasSession) return
        runCatching { api.goalProgress() }.getOrNull()?.let { goalChecks = it }
    }

    /** When the app opens (or foregrounds), pull the latest from connected
     *  sources so the plan/dashboard reflect reality without a manual sync.
     *  Throttled and non-blocking; a no-op when nothing is connected. */
    private var lastSourceSyncAt: Instant? = null

    fun syncConnectedSourcesIfNeeded(minIntervalSeconds: Long = 600) {
        if (!tokens.hasSession) return
        if (!intervals.connectionState.isConnected && !strava.connectionState.isConnected) return
        val last = lastSourceSyncAt
        if (last != null && ChronoUnit.SECONDS.between(last, Instant.now()) < minIntervalSeconds) return
        lastSourceSyncAt = Instant.now()
        viewModelScope.launch { syncConnectedSources() }
    }

    private suspend fun syncConnectedSources() {
        var didSync = false
        if (intervals.connectionState.isConnected && runCatching { api.intervalsSync() }.isSuccess) didSync = true
        if (strava.connectionState.isConnected && runCatching { api.stravaSync() }.isSuccess) didSync = true
        if (didSync) {
            loadActivities()
            loadMetricsAndReadiness()
            loadGoalProgress()
        }
    }

    /** Cached activity streams for the completed-workout charts. */
    private val activityStreamsCache = mutableMapOf<String, ActivityStreams>()

    suspend fun activityStreams(activityId: String): ActivityStreams? {
        activityStreamsCache[activityId]?.let { return it }
        if (!tokens.hasSession) return null
        val streams = runCatching { api.activityStreams(activityId) }.getOrNull() ?: return null
        activityStreamsCache[activityId] = streams
        return streams
    }

    /** The plan for the current week (falls back to the first available week). */
    val currentWeek: WeeklyPlan?
        get() = weeklyPlans.firstOrNull { it.isCurrentWeek } ?: weeklyPlans.firstOrNull()

    /** This week's planned sessions paired with their completion state. */
    val currentWeekMatches: List<SessionMatch>
        get() = currentWeek?.let { PlanMatchingEngine.matches(it, weekActivities) } ?: emptyList()

    /** Today's dashboard rows: planned sessions plus off-plan extras, shown
     *  even when no plan week covers today. */
    val todayMatches: List<SessionMatch>
        get() = PlanMatchingEngine.todayMatches(currentWeek, weekActivities)

    // MARK: - Week navigation

    /** Furthest future week (in whole weeks from this week) that the plan
     *  covers. The right arrow is disabled beyond this. */
    val maxFutureWeekOffset: Int
        get() {
            val base = PlanEngine.mondayOf(LocalDate.now())
            val offsets = weeklyPlans.map { plan ->
                val days = ChronoUnit.DAYS.between(base, PlanEngine.mondayOf(plan.weekStart))
                Math.round(days / 7.0).toInt()
            }
            return maxOf(0, offsets.maxOrNull() ?: 0)
        }

    /** The plan (offset ≥ 0) or a past week synthesized from imported
     *  activities (offset < 0), paired with completion state. */
    fun weekData(offset: Int): WeekData? {
        val base = PlanEngine.mondayOf(LocalDate.now())
        val start = base.plusDays((offset * 7).toLong())

        if (offset >= 0) {
            val plan = weeklyPlans.firstOrNull {
                ChronoUnit.DAYS.between(start, PlanEngine.mondayOf(it.weekStart)) == 0L
            } ?: return null
            return WeekData(
                offset = offset, week = plan,
                matches = PlanMatchingEngine.matches(plan, weekActivities),
                isHistorical = false,
            )
        }

        val end = start.plusDays(7)
        val zone = java.time.ZoneId.systemDefault()
        val acts = weekActivities.filter {
            val d = it.startTime.atZone(zone).toLocalDate()
            !d.isBefore(start) && d.isBefore(end)
        }
        val days = (0 until 7).map { i ->
            val date = start.plusDays(i.toLong())
            val dayActs = acts.filter { it.startTime.atZone(zone).toLocalDate() == date }
            val sessions = dayActs.map {
                PlannedSession(
                    domain = it.type.domain, title = it.name, subtitle = "",
                    duration = (it.durationSeconds / 60).toInt(), intensityLabel = "",
                )
            }
            PlannedDay(date = date, sessions = sessions, isRest = sessions.isEmpty())
        }
        val week = WeeklyPlan(weekStart = start, days = days)
        return WeekData(
            offset = offset, week = week,
            matches = PlanMatchingEngine.matches(week, acts),
            isHistorical = true,
        )
    }

    // MARK: - Daily switch suggestions

    /** On the first foreground of a new day (or when the cache is empty after
     *  a relaunch), pre-fetch AI alternatives for each of today's planned
     *  sessions. Each request is independent; failures leave that key empty so
     *  the detail view falls back to the deterministic switcher. */
    fun prefetchDailySuggestionsIfNeeded() {
        if (!tokens.hasSession) return
        val week = currentWeek ?: return
        val todayKey = LocalDate.now().toString()
        val last = prefs.lastSuggestionFetchDate
        if (last == todayKey && dailySuggestions.isNotEmpty()) return

        val todays = week.days
            .filter { it.isToday }
            .flatMap { day -> day.sessions.map { day to it } }
        prefs.lastSuggestionFetchDate = todayKey
        if (todays.isEmpty()) return

        for ((day, session) in todays) {
            val key = SessionMatch.suggestionKey(day, session)
            if (dailySuggestions.containsKey(key) || key in suggestionsLoading) continue
            suggestionsLoading = suggestionsLoading + key
            viewModelScope.launch {
                val result = runCatching { api.switchSuggestions(session, day.date) }.getOrDefault(emptyList())
                dailySuggestions[key] = result
                suggestionsLoading = suggestionsLoading - key
            }
        }
    }

    /** Deterministic alternatives for other enrolled sports — the silent
     *  offline fallback when AI suggestions aren't available. */
    fun fallbackSuggestions(excluding: TrainingDomain): List<SwitchSuggestion> =
        enabledDomains.filter { it != excluding }.take(3).map { d ->
            val o = switchSuggestion(d)
            SwitchSuggestion(
                domain = d, title = o.title, duration = o.duration,
                intensityLabel = o.intensityLabel, description = o.intensityDescription,
                rationale = null, estimatedLoad = null,
                workout = null, exercises = null, isAI = false,
            )
        }

    /** Apply a chosen switch to a planned day: overrides that day's session on
     *  the server and swaps the updated week into [weeklyPlans]. */
    suspend fun applySwitch(match: SessionMatch, suggestion: SwitchSuggestion) {
        if (!tokens.hasSession) return
        val weekStart = currentWeek?.weekStart ?: return
        val updated = runCatching {
            api.overrideDay(weekStart, match.day.date, suggestion)
        }.getOrNull() ?: return
        val idx = weeklyPlans.indexOfFirst { it.weekStart == updated.weekStart }
        if (idx >= 0) {
            weeklyPlans = weeklyPlans.toMutableList().also { it[idx] = updated }
        } else {
            loadPlans()
        }
    }

    suspend fun loadCoachHistory() {
        val history = runCatching { api.coachHistory(limit = 50) }.getOrNull()
        if (!history.isNullOrEmpty()) messages = history
    }

    fun recalculate() {
        readiness = metrics?.let { ReadinessEngine.calculate(it) }
    }

    // MARK: - Plan generation

    fun regeneratePlan() {
        // No training days defined yet → no plan. The Plan tab shows a
        // "create a plan" prompt rather than an assumed schedule.
        if (trainingFrequency.totalTrainingDays == 0) {
            weeklyPlans = emptyList()
            planWasRecentlyUpdated = false
            return
        }
        weeklyPlans = PlanEngine.generatePlans(
            weeks = 4, frequency = trainingFrequency, muscleGroupSplit = muscleGroupSplit,
        )
        flashPlanUpdatedBanner()
    }

    private fun flashPlanUpdatedBanner() {
        planWasRecentlyUpdated = true
        viewModelScope.launch {
            delay(4_000)
            planWasRecentlyUpdated = false
        }
    }

    /** Submit staged plan changes: persist the schedule + split, then generate
     *  the next two weeks with the AI planner (deterministic fallback happens
     *  server-side). Drives the loading overlay via [isGeneratingPlan]. */
    suspend fun applyPlanChanges() {
        pendingPlanChanges = false

        if (!tokens.hasSession) {
            regeneratePlan() // offline/debug: local engine only
            return
        }
        if (trainingFrequency.totalTrainingDays == 0) {
            // No training days → clear the plan (persist the empty schedule).
            runCatching { api.updateSchedule(trainingFrequency.schedules) }
            weeklyPlans = emptyList()
            return
        }

        isGeneratingPlan = true
        try {
            // Persist the plan-affecting preferences before generating.
            runCatching { api.updateSchedule(trainingFrequency.schedules) }
            runCatching { api.updateMuscleSplit(muscleGroupSplit) }
            runCatching { api.updateCyclingTarget(cyclingTarget) }
            runCatching { api.updateSportTargets(sportTargets) }

            val plans = runCatching { api.generatePlanAI() }.getOrNull()
            if (!plans.isNullOrEmpty()) {
                weeklyPlans = plans
            } else {
                loadPlans() // fall back to whatever the server has
            }

            // New plan invalidates today's cached switch suggestions.
            dailySuggestions.clear()
            prefs.lastSuggestionFetchDate = null
            prefetchDailySuggestionsIfNeeded()

            flashPlanUpdatedBanner()
        } finally {
            isGeneratingPlan = false
        }
    }

    // MARK: - Training-load model (TSS-like: hours × IF² × 100)

    fun sessionLoad(durationMin: Int, intensity: String): Double {
        val f = intensityFactor(intensity)
        return durationMin / 60.0 * f * f * 100.0
    }

    /** The training load prescribed for today (the deterministic suggestion). */
    val prescribedLoad: Double
        get() {
            val r = readiness ?: return 0.0
            return sessionLoad(r.suggestedDuration, r.suggestedIntensityLabel)
        }

    /** Minutes needed at `intensity` to match `target` load, clamped to a sane range. */
    private fun durationForLoad(target: Double, intensity: String, range: IntRange): Int {
        val f = intensityFactor(intensity)
        val mins = target / (f * f * 100.0) * 60.0
        return Math.round(mins).toInt().coerceIn(range.first, range.last)
    }

    /** A switch alternative whose training load matches today's prescribed
     *  load as closely as the sport allows (recovery/mobility stay short). */
    fun switchSuggestion(domain: TrainingDomain): SessionOverride {
        val target = prescribedLoad
        val score = readiness?.score ?: 0

        fun matched(title: String, intensity: String, desc: String, range: IntRange): SessionOverride {
            val dur = durationForLoad(target, intensity, range)
            return SessionOverride(domain, title, dur, intensity, desc)
        }

        return when (domain) {
            TrainingDomain.Cycling -> when {
                score >= 80 -> matched("Zone 3 Intervals", "Threshold", "70–85% FTP", 30..150)
                score >= 60 -> matched("Aerobic Endurance", "Moderate", "65–75% FTP", 30..180)
                else -> matched("Recovery Ride", "Easy", "Zone 1–2", 30..120)
            }

            TrainingDomain.Running -> when {
                score >= 80 -> matched("Tempo Run", "Hard", "Comfortably hard pace", 20..75)
                score >= 60 -> matched("Easy Run", "Easy", "Zone 2", 20..100)
                else -> matched("Recovery Jog", "Very Easy", "Conversational pace", 20..75)
            }

            TrainingDomain.Swimming -> when {
                score >= 80 -> matched("Interval Set", "Hard", "8×100m at race pace", 20..75)
                score >= 60 -> matched("Technique Session", "Moderate", "Drills + aerobic", 20..75)
                else -> matched("Easy Swim", "Easy", "Continuous aerobic", 20..60)
            }

            TrainingDomain.Triathlon -> matched("Brick Session", "Moderate", "Bike + run", 45..150)

            // Recovery-oriented: kept short rather than load-matched.
            TrainingDomain.Mobility -> SessionOverride(
                domain, "Yoga Flow", 40, "Easy", "Hip flexors, hamstrings, thoracic spine",
            )

            TrainingDomain.Recovery, TrainingDomain.Strength -> SessionOverride(
                domain, "Active Recovery", 20, "Minimal", "Short walk or light stretching",
            )
        }
    }

    // MARK: - Coaching responses

    /** Stream a coach reply over SSE when authenticated; fall back to the
     *  local templated response offline. The caller has already appended the
     *  user's message to [messages]. */
    suspend fun respond(question: String) {
        if (!tokens.hasSession) {
            val response = buildResponse(question)
            delay(800)
            messages = messages + CoachMessage(content = response, isCoach = true, timestamp = Instant.now())
            return
        }

        messages = messages + CoachMessage(content = "", isCoach = true, timestamp = Instant.now())
        val index = messages.size - 1

        fun updateLast(transform: (String) -> String) {
            messages = messages.toMutableList().also {
                it[index] = it[index].copy(content = transform(it[index].content))
            }
        }

        try {
            container.sse.coachStream("ai/coach/message", CoachMessageRequest(question)).collect { event ->
                when (event) {
                    is CoachStreamEvent.Delta -> updateLast { it + event.text }
                    is CoachStreamEvent.Done -> if (event.fullContent.isNotEmpty()) updateLast { event.fullContent }
                    is CoachStreamEvent.Failed -> updateLast {
                        it.ifEmpty { "The coach is unavailable right now. Please try again." }
                    }
                }
            }
        } catch (_: Exception) {
            updateLast { it.ifEmpty { buildResponse(question) } }
        }
    }

    private fun intensityLabelFor(readiness: DailyReadiness): String = when (readiness.status) {
        DailyReadiness.Status.Peak, DailyReadiness.Status.High -> "heavy"
        DailyReadiness.Status.Moderate -> "moderate"
        DailyReadiness.Status.Low, DailyReadiness.Status.Rest -> "light"
    }

    private fun buildResponse(question: String): String {
        val q = question.lowercase()
        val r = readiness
        val m = metrics
        if (r == null || m == null) {
            return "I don't have your training data yet. Connect a data source in Settings → Integrations and I'll give you guidance based on your real HRV, sleep, and training load."
        }

        if (q.contains("train") || q.contains("session") || q.contains("today")) {
            return if (r.score >= 70) {
                "Based on your data, you're in good shape to train. Readiness is ${r.score}/100 — ${r.status.raw.lowercase()} zone.\n\nI'd go ahead with the ${r.suggestedSessionTitle}. Your HRV is performing well and your training load is balanced, so you can push the intensity without significant risk."
            } else {
                "Looking at your numbers, I'd recommend against hard training today. Readiness is ${r.score}/100 — your body is showing signs of stress.\n\nThe most productive thing you can do is rest or keep activity very light. The adaptations from yesterday's training happen during recovery, not during the next hard session."
            }
        }

        if (q.contains("recovery") || q.contains("low") || q.contains("tired") || q.contains("fatigue")) {
            val reasons = mutableListOf<String>()
            if (m.hrvChange < -0.08) reasons.add("HRV is ${(Math.abs(m.hrvChange) * 100).toInt()}% below baseline")
            if (m.sleepDuration < 7) reasons.add("only ${String.format(java.util.Locale.US, "%.1f", m.sleepDuration)} hours of sleep")
            if (m.trainingBalance < -15) reasons.add("a spike in recent training load")

            if (reasons.isEmpty()) return "Your recovery is actually looking reasonable. HRV, sleep quality, and training load are all within normal range."
            return "Recovery is compromised primarily because of ${reasons.joinToString(", and ")}.\n\nThese signals combine to indicate accumulated stress. Prioritising sleep, hydration, and nutrition over the next 24–48 hours will have more impact on your performance than any workout."
        }

        if (q.contains("overtrain")) {
            return if (m.trainingBalance < -20 || m.hrvChange < -0.15) {
                "There are early warning signs. Acute load has spiked and your HRV trend is declining — this pattern is associated with functional overreaching.\n\nIt's not overtraining yet, but continuing at this pace without adequate recovery will get you there. Reduce intensity for 3–5 days."
            } else {
                "Based on current metrics, you're not showing signs of overtraining. HRV is stable and training load is within a sustainable range.\n\nKey warning signs: persistent HRV depression, elevated resting HR, declining performance, chronic fatigue."
            }
        }

        if (q.contains("improv") || q.contains("progress") || q.contains("plateau")) {
            return "Progression is happening, though it's rarely linear. Your chronic training load has been building steadily — the foundation of long-term performance.\n\nThe biggest lever right now is sleep consistency. Athletes who prioritise 8+ hours of quality sleep adapt faster than those who train more but sleep less."
        }

        if (q.contains("focus") || q.contains("habit") || q.contains("biggest")) {
            return "The single habit that would produce the biggest improvement right now is sleep consistency.\n\nYour training structure is solid, but sleep has been variable. Even one additional hour of quality sleep per night would measurably improve HRV, shorten recovery, and increase the training volume you can absorb."
        }

        if (q.contains("load") || q.contains("tsb") || q.contains("atl") || q.contains("ctl")) {
            val tsb = m.trainingBalance
            val sign = if (tsb >= 0) "+" else ""
            val stateText = if (Math.abs(tsb) < 10) "in a great training window"
            else if (tsb < 0) "carrying meaningful fatigue" else "quite fresh — consider adding some load"
            return "Your Training Stress Balance (TSB) is currently $sign${tsb.toInt()}.\n\nTSB = Fitness (CTL) minus Fatigue (ATL). Positive means fresh; negative means carrying fatigue. The optimal performance window is roughly −10 to +5.\n\nAt ${tsb.toInt()}, you're $stateText."
        }

        if (q.contains("garmin") || q.contains("intervals") || q.contains("sync")) {
            return if (intervals.connectionState.isConnected) {
                "intervals.icu is connected and syncing. Your Garmin activities and wellness are being used to improve load calculations and recovery estimates."
            } else {
                "intervals.icu isn't connected yet. Head to Settings → Connect to link your account (it brings in your Garmin data). Once connected, your real training history replaces the sample data."
            }
        }

        if (q.contains("gym") || q.contains("muscle") || q.contains("strength") || q.contains("lift")) {
            val split = muscleGroupSplit.splitForIsoWeekday(LocalDate.now().dayOfWeek.value)
            if (split.isRestDay || split.muscleGroups.isEmpty()) {
                return "According to your weekly split, today is a rest day for strength work. If you want to hit the gym anyway, tap 'Switch Activity' on the dashboard — I'll generate an appropriate session based on your recovery status."
            }
            val groups = split.muscleGroups.joinToString(", ") { it.raw }
            return "Today's split in your plan is: $groups.\n\nWith readiness at ${r.score}/100, I'd programme this as a ${intensityLabelFor(r)} session. Tap 'Switch Activity' on the dashboard to see the full exercise list."
        }

        val advice = if (r.score >= 70) "executing today's session with intention — your body is ready"
        else "keeping today light and prioritising recovery"
        return "Good question. With a readiness score of ${r.score}/100, I'd recommend $advice.\n\nIs there a specific metric you'd like to understand better?"
    }

    companion object {
        /** Relative intensity factor for an intensity label (fraction of threshold). */
        fun intensityFactor(label: String): Double = when (label.lowercase()) {
            "very easy", "minimal", "recovery" -> 0.55
            "easy" -> 0.65
            "moderate" -> 0.75
            "tempo" -> 0.85
            "hard", "threshold" -> 0.95
            "vo2", "vo2max", "max" -> 1.05
            else -> 0.75
        }
    }
}
