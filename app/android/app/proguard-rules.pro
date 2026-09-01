# R8 rules for the release build.
#
# Flutter ships the keeps its own engine needs; these cover the plugins whose
# entry points are only reached reflectively (so R8 can't see them) and silence
# warnings about optional dependencies we don't ship.

# Play Core / deferred components — referenced by the Flutter engine but not
# bundled (this app has no dynamic feature modules).
-dontwarn com.google.android.play.core.**

# Google Play Billing (in_app_purchase) — proguard strips the response models
# that the billing library builds by reflection otherwise.
-keep class com.android.billingclient.api.** { *; }

# Google Mobile Ads: mediation adapters are looked up by class name.
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# Firebase (auth/analytics) keeps its own model classes for Gson-style parsing.
-keepattributes Signature,InnerClasses,EnclosingMethod,*Annotation*
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# speech_to_text / flutter_tts talk to platform services through callbacks.
-keep class com.google.android.tts.** { *; }
-dontwarn org.chromium.**

# --- Razorpay checkout ------------------------------------------------------
# The SDK drives its checkout through a WebView that calls back into Java over
# @JavascriptInterface, and finds the payment callbacks by NAME via reflection.
# R8 has no way to see either, so without these keeps the release build opens
# checkout and then silently never returns a result.
-keepattributes JavascriptInterface
-keepattributes *Annotation*
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
  public void onPayment*(...);
}
