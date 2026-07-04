# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class app.northax.** {
    *** Companion;
}
-keepclasseswithmembers class app.northax.** {
    kotlinx.serialization.KSerializer serializer(...);
}
