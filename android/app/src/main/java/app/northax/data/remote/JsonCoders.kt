package app.northax.data.remote

import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Shared JSON configuration for the backend contract: camelCase keys matched
 * 1:1 by DTO property names; unknown keys ignored so the client tolerates
 * additive backend changes (like the iOS JSONDecoder default).
 */
object JsonCoders {
    val json: Json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
    }

    val calendarDate: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE
}

/** `yyyy-MM-dd` calendar dates (e.g. `date`, `weekStart`). */
object LocalDateSerializer : KSerializer<LocalDate> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("LocalDate", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: LocalDate) =
        encoder.encodeString(value.format(DateTimeFormatter.ISO_LOCAL_DATE))

    override fun deserialize(decoder: Decoder): LocalDate =
        LocalDate.parse(decoder.decodeString(), DateTimeFormatter.ISO_LOCAL_DATE)
}

/**
 * ISO-8601 datetimes (e.g. `startTime`, `createdAt`). The backend emits
 * offset datetimes with or without fractional seconds; a bare calendar date is
 * also accepted (start of day UTC), matching the lenient iOS decoder.
 */
object FlexInstantSerializer : KSerializer<Instant> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("Instant", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: Instant) =
        encoder.encodeString(DateTimeFormatter.ISO_INSTANT.format(value))

    override fun deserialize(decoder: Decoder): Instant {
        val raw = decoder.decodeString()
        return try {
            OffsetDateTime.parse(raw).toInstant()
        } catch (_: Exception) {
            try {
                Instant.parse(raw)
            } catch (_: Exception) {
                LocalDate.parse(raw).atStartOfDay(ZoneOffset.UTC).toInstant()
            }
        }
    }
}

typealias ApiDate = @kotlinx.serialization.Serializable(with = LocalDateSerializer::class) LocalDate
typealias ApiInstant = @kotlinx.serialization.Serializable(with = FlexInstantSerializer::class) Instant
