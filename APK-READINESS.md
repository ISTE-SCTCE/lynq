# Android release readiness — 2026-09-27

## Local changes

- Lynq remains sign-in-only. Missing profiles are no longer created as active Execom accounts; client-side email matching no longer rewrites user IDs.
- Role access uses the backend role instead of guessing from a person's position text. Suspended/inactive accounts fail closed. Ordinary members continue to the existing wrong-app screen.
- Concurrent profile loads share their result. Stale requests cannot restore a signed-out account. Session subscriptions are disposed and account caches are cleared on identity changes/sign-out.
- Permission fetch failures no longer silently substitute guessed/default access. Login displays a safe recovery message.
- Approving a website registration requires the administrator to enter an official `KE104` plus three-digit membership ID. No ID is generated. The endpoint receives `membershipId`; backend uniqueness and atomic allocation must be deployed separately.

## Verification

- Dart parsed all modified files successfully (formatter). This is syntax validation, not a complete type check.
- `dart tool/check_membership_id.dart`: passed 10 validation cases plus normalization.
- `git diff --check` for modified Dart files: passed.
- `flutter pub get`: failed because the existing path dependency `../shared/dart` is absent. Full analysis, Flutter tests and APK build are blocked; no new APK has been produced.

## Release gates still open

1. Restore the real shared Dart package and shared permission test matrix from their authoritative source; do not invent replacement authorization rules.
2. Install Android SDK command-line tools and resolve SDK license status. Flutter doctor finds Android Studio/Java and SDK, but no connected Android device.
3. Supply the established release signing configuration through secure local/CI configuration. Both local and GitHub main `android/app/build.gradle.kts` currently use the debug key for release. No replacement key, signing secret or package-ID change was made.
4. Select a versionCode higher than the currently distributed APK (repository currently says `1.0.0+1`).
5. Finish server-side authorization and unified-identity rollout. This client still uses legacy `profiles`; local fixes are not evidence that production RLS is safe.
6. Verify existing Execom sign-in, ordinary-member denial, suspension, session restoration/refresh, offline retry, membership approval/duplicate-ID rejection, attendance and certificates on real Android devices and website using the same backend.
7. OTP flows and email delivery remain separately unverified for this Flutter client. No test email was sent by this APK work.

No production deployment, signing change, or database write was performed by this work.
