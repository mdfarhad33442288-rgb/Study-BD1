# Study BD

Flutter + Firebase education app for Bangladesh (NCTB Class 1–12, admission & job prep, English, IELTS, AI tutor, exams, live classes, courses, library, career, news, study tools, admin panel).

> **Status:** source is complete but has **not been compiled or run** (it was written without a Flutter SDK available). Expect to fix a handful of compile errors on the first `flutter analyze`. Follow the steps below, then test on a real device.

## 1. Prerequisites
Flutter (stable, 3.27+), JDK 17, Android SDK, Node 20, Firebase CLI (`npm i -g firebase-tools`), a Firebase project, and optionally an AdMob account and an Anthropic API key (AI tutor).

## 2. Generate the Android scaffolding
This repo contains the app code and the key Android files, but not the Gradle wrapper or `settings.gradle.kts`. Generate them without overwriting this code:

```bash
cd study_bd
flutter create . --platforms=android --org com.studybd --project-name study_bd
```
Then **restore** `android/app/build.gradle.kts` and `android/app/src/main/AndroidManifest.xml` from this repo if `flutter create` replaced them (check with git diff), and add to `android/settings.gradle.kts` plugins:
```kotlin
id("com.google.gms.google-services") version "4.4.2" apply false
id("com.google.firebase.crashlytics") version "3.0.2" apply false
```
Application id is `com.studybd.app` – change it everywhere if you want another.

```bash
dart run flutter_launcher_icons   # icons from assets/icons (placeholder artwork – replace with your own)
flutter pub get
```

## 3. Firebase
1. Create a project, add an Android app `com.studybd.app`, add your debug and release **SHA-1/SHA-256** fingerprints (needed for Google Sign-In).
2. Download `google-services.json` to `android/app/`.
3. Enable **Authentication** (Email/Password, Google, Anonymous), **Firestore**, **Storage**, **Cloud Messaging**, **Crashlytics**, **Analytics**.
4. Deploy rules, indexes, functions:
```bash
firebase use <project-id>
firebase functions:secrets:set ANTHROPIC_API_KEY     # AI tutor; optional
firebase deploy --only firestore,storage,functions
```
Functions run in `asia-south1`; the app’s `functionsProvider` uses the same region. Scheduled functions need the Blaze plan.

## 4. First admin
Sign up in the app, then in Firestore console set `users/<your uid>.role = "admin"`. The Admin panel appears in Profile. Rules prevent students from changing their own role.

## 5. Adding content (no app update needed)
Admin panel → **Upload content**: choose section, class/track, category, type, then pick file(s) or paste a YouTube/link URL. It is written to Firestore `content/` and appears live. Also: create exams (bulk-paste MCQs), courses with lessons/assignments, live classes, categories, notifications, users, payments, ads/payment settings, daily quiz and vocabulary import.

## 6. Monetization
* **AdMob:** the manifest holds Google’s *test* App ID. Replace it with yours, then paste real unit IDs in Admin → Ads & settings (debug builds always use test ads). Rewarded ads unlock single premium items.
* **Premium / paid courses / donations:** manual bKash/Nagad/Rocket flow. Users send money and submit TrxID; an admin approves in Admin → Payments, which activates premium or the course. Set your numbers in Ads & settings. Edit plan prices via `config/app.plans` (array of `{id,nameEn,nameBn,days,price}`).
  *Google Play policy:* digital subscriptions/content sold for use inside an app normally must use **Google Play Billing**. Before publishing a paid version, review the policy; you may need to integrate `in_app_purchase` or restrict to donations/physical goods.

## 7. Build & publish
```bash
cp android/key.properties.example android/key.properties   # fill in; create keystore with keytool
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
# or small per-ABI APKs for sideloading
flutter build apk --release --split-per-abi
```
Upload the `.aab` to Play Console. You will need a privacy policy URL, a Data Safety form (Firebase, AdMob, mic/camera usage), content rating, store listing assets, and 20 testers for 14 days if it is a new personal developer account.

## Architecture
`lib/core` (theme, l10n, router, providers, services) · `lib/data` (models, repositories) · `lib/features/<feature>` (UI). Riverpod for state, go_router for navigation, Firestore offline persistence for cached lists, local download index for offline PDFs/videos.

## Firestore collections
`users`, `content`, `categories`, `courses/{id}/lessons|assignments`, `liveClasses/{id}/chat|attendance|assignments`, `exams`, `results`, `payments`, `quizBank`, `vocabulary`, `config/app`, `stats/daily_YYYYMMDD`, `aiUsage` (functions only).

## Known limitations (read before launch)
* **Exam integrity:** MCQ grading runs on the device and exam documents (with answers) are readable by signed-in users, so a determined user can cheat or forge leaderboard scores. For high-stakes use, move grading into a Cloud Function and keep answers in an admin-only subcollection.
* **Live classes** embed a YouTube Live / meeting link you provide; there is no built-in video conferencing.
* **Written exams** are stored as `pending`; there is no teacher grading screen yet (grade by editing `results/<id>` in the console).
* **OCR** uses on-device ML Kit (Latin script). Bangla OCR is not supported.
* **Speaking evaluation** works on a speech-to-text transcript; it can’t judge pronunciation audio itself.
* Multi-user "Active users" = users seen in the last 7 days; "Daily visitors" counts signed-in app launches.
* Search is prefix-keyword based on the first word typed (Firestore has no full-text search); use Algolia/Typesense for scale.
* Seed content is not included – the app starts empty until you upload material. Only upload material you have rights to (NCTB books are published by NCTB; check licensing for guides/guide books).
* Unit tests in `test/` cover pure logic only; none of the code has been run.

## Tests
`flutter test`
