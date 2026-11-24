# Firebase setup guide (google-services.json, collections, Storage)

## google-services.json
A real `google-services.json` contains your own project's keys, so it cannot be shipped in the source. The Android build **fails until you add it**.
1. Firebase console → Project settings → Your apps → Add app → Android → package `com.studybd.app`.
2. Add SHA-1 and SHA-256 (`cd android && ./gradlew signingReport`).
3. Download `google-services.json` → place at `android/app/google-services.json`.
4. Do not commit it to a public repo (it is in `.gitignore`).

`lib/firebase_options.dart` is not needed on Android: `Firebase.initializeApp()` reads `google-services.json`. If you later add iOS/web, run `dart pub global activate flutterfire_cli && flutterfire configure` to generate it and pass it to `initializeApp`.

## Firestore collections
| Collection | Written by | Key fields |
|---|---|---|
| `users/{uid}` | app (own doc), admin | name, email, photoUrl, role (`student`\|`admin`), isPremium, premiumUntil, isGuest, banned, fcmToken, createdAt, lastActiveAt |
| `users/{uid}/bookmarks/{contentId}` | user | contentId, at |
| `users/{uid}/enrollments/{courseId}` | user (free) / admin (paid) | courseId, at, via |
| `content/{id}` | admin | title, titleBn, section, group, category, kind (`pdf\|video\|youtube\|image\|link\|text`), url, storagePath, description, body, isPremium, sizeBytes, searchKeywords[], createdAt |
| `categories/{id}` | admin | section, nameEn, nameBn |
| `courses/{id}` | admin | title, description, teacher, thumbnailUrl, price, isPremium, published |
| `courses/{id}/lessons/{id}` | admin | title, kind, url, body, order, isPreview |
| `courses/{id}/assignments/{id}/submissions/{uid}` | admin / student | title, description / text, fileUrl, at |
| `exams/{id}` | admin | title, section, group, type (`mcq\|written`), durationMin, negativeMark, isPremium, published, courseId, questions[{q,options,answer,explanation}] |
| `results/{id}` | student | examId, uid, userName, score, total, correct, wrong, skipped, seconds, status, section, createdAt |
| `liveClasses/{id}` (+ `chat`, `attendance`, `assignments`) | admin / students | title, teacher, url, recordingUrl, startsAt, status (`upcoming\|live\|ended`), reminded |
| `payments/{id}` | student creates `pending`, admin approves | uid, type (`premium\|course\|donation`), refId, amount, method, trxId, status |
| `quizBank/{id}`, `vocabulary/{id}` | admin | question fields / word, meaningBn, meaningEn, example |
| `config/app` | admin | ads{enabled,banner,interstitial,rewarded,appOpen,native}, payment{bkash,nagad,rocket,note}, plans[], homeBanner |
| `stats/daily_YYYYMMDD` | app (increments) | visits, opens, downloads, exams |
| `aiUsage/{uid_day}` | Cloud Function only | count |

Premium plans can be customised in `config/app.plans`, for example:
`[{"id":"monthly","nameEn":"Monthly","nameBn":"মাসিক","days":30,"price":99}]`

## Storage layout
`content/{section}/{group}/{category}/{timestamp}_{file}` · `courses/thumbs/…` · `courses/{courseId}/…` · `submissions/{uid}/…`
Uploads use `ContentRepository.upload()` with progress; deleting content also deletes the Storage object.

## Deploy
```
firebase deploy --only firestore,storage,functions
```
