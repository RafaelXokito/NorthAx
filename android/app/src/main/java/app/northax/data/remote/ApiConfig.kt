package app.northax.data.remote

import app.northax.BuildConfig

/**
 * Backend connection configuration. The URL comes from BuildConfig:
 * debug -> http://rafaelpereira.local:8080/v1 (Raspberry Pi; override via
 * gradle.properties `northax.apiBaseUrl`, e.g. http://10.0.2.2:8080/v1 on an
 * emulator), release -> https://api.northax.app/v1. Mirrors iOS APIConfig.
 */
object ApiConfig {
    val baseUrl: String = BuildConfig.API_BASE_URL.trimEnd('/')

    /** Custom URL scheme used for the intervals.icu OAuth callback deep link. */
    const val APP_SCHEME = "northax"
}
