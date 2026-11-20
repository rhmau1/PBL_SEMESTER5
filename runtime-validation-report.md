# Runtime Validation Report

**Generated**: 2026-11-18
**Target**: `silva_rama` on physical Android device `V2310 - Android 15`

## Summary

| Layer | Status | Exit code | Result |
|---|---:|---:|---|
| Flutter UI journey | PASS | 0 | 1 flow covering all 10 requested screen journeys |
| Android Espresso | PASS | 0 | 3 native Activity/lifecycle/package tests |

## UI Journey Coverage

1. Splash screen
2. First-launch onboarding, all 4 steps
3. Home
4. Detection Video
5. Detection Foto
6. Detection Upload
7. Kamus
8. Riwayat
9. Learning progress, badge, and streak
10. Panduan Penggunaan opened from Home

## Notes

Espresso validates the Android-native `MainActivity` boundary. The Flutter UI journey uses
`integration_test` because Flutter widgets are rendered inside the Flutter engine and are not
Android `View` instances addressable by Espresso matchers.

The physical device camera was active during the detection flow; CameraX reported a valid
720x480 buffer with a 480x720 upright preview transform.
