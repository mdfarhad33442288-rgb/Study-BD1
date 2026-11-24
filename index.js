/**
 * Study BD – Cloud Functions (Node 20, firebase-functions v2)
 *
 *  aiTutor            callable   AI chat (key stays on the server, per-user daily quota)
 *  sendNotification   callable   admin → FCM topic
 *  onContentCreated   trigger    "New book alert" to topic `all`
 *  liveReminders      scheduled  reminds ~15 min before a live class
 *  examReminders      scheduled  daily nudge when new exams exist (optional)
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();
const REGION = "asia-south1"; // must match functionsProvider in the app

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const AI_MODEL = process.env.AI_MODEL || "claude-haiku-5-5";
const FREE_DAILY = 10;
const PREMIUM_DAILY = 100;

const SYSTEM = {
  general: "You are Study BD's friendly AI tutor for Bangladeshi students. Answer clearly and concisely, step by step.",
  homework: "You are a homework helper for Bangladesh National Curriculum (NCTB) students. Guide the student through the solution step by step and explain the reasoning rather than only giving the final answer.",
  explain: "Explain the given answer or concept simply, with a short example, at school level.",
  mcq: "Solve the multiple-choice question. State the correct option first, then a short justification, and why the others are wrong.",
  grammar: "You are an English grammar coach. Correct the student's text, list each mistake with a short rule, then give the corrected version.",
  speaking: "You are a friendly English speaking partner. Reply conversationally in 2-4 sentences, then gently correct any mistakes and ask a follow-up question.",
  speaking_eval: "You are an English speaking examiner. The text is a speech-to-text transcript, so ignore punctuation and spelling artefacts. Evaluate fluency & coherence, vocabulary, grammar and relevance. Give a rough IELTS-style band (0-9) for each, 3 concrete improvements, and a stronger sample sentence.",
  translation: "You are a Bangla-English translation checker. Say whether the student's translation is correct, list errors, and give a natural model translation.",
  ielts: "You are an IELTS coach. Give exam-focused advice, estimate band scores when evaluating writing/speaking, and explain how to reach the next band.",
  math: "You are a maths tutor. Solve step by step, show formulas, and verify the final answer.",
  science: "You are a science teacher for Bangladeshi school students. Explain concepts accurately with simple everyday examples.",
};

exports.aiTutor = onCall({ region: REGION, secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 60, memory: "256MiB" }, async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  const { mode = "general", messages = [], lang = "en" } = req.data || {};
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > 20) throw new HttpsError("invalid-argument", "Bad messages");

  const clean = messages
    .filter((m) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
    .map((m) => ({ role: m.role, content: m.content.slice(0, 4000) }));
  if (!clean.length || clean[0].role !== "user") throw new HttpsError("invalid-argument", "First message must be from the user");

  // ---- daily quota (transactional) ----
  const uid = req.auth.uid;
  const userSnap = await db.collection("users").doc(uid).get();
  const u = userSnap.data() || {};
  const until = u.premiumUntil ? u.premiumUntil.toDate() : null;
  const premium = u.isPremium === true && (!until || until > new Date());
  const limit = premium ? PREMIUM_DAILY : FREE_DAILY;
  const day = new Date().toISOString().slice(0, 10);
  const qref = db.collection("aiUsage").doc(`${uid}_${day}`);
  await db.runTransaction(async (t) => {
    const s = await t.get(qref);
    const n = s.exists ? s.data().count : 0;
    if (n >= limit) throw new HttpsError("resource-exhausted", "Daily AI limit reached");
    t.set(qref, { uid, day, count: n + 1 });
  });

  const system = `${SYSTEM[mode] || SYSTEM.general}\nReply in ${lang === "bn" ? "Bangla (বাংলা), keeping English technical terms where helpful" : "English"}. Keep answers focused and under about 350 words unless more detail is clearly needed.`;

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "content-type": "application/json", "x-api-key": ANTHROPIC_API_KEY.value(), "anthropic-version": "2023-06-01" },
    body: JSON.stringify({ model: AI_MODEL, max_tokens: 1024, system, messages: clean }),
  });
  if (!res.ok) {
    console.error("Anthropic error", res.status, await res.text());
    // refund the quota unit on provider failure
    await qref.update({ count: admin.firestore.FieldValue.increment(-1) }).catch(() => {});
    throw new HttpsError("internal", "The AI service is busy. Please try again.");
  }
  const json = await res.json();
  const text = (json.content || []).filter((b) => b.type === "text").map((b) => b.text).join("\n");
  return { text };
});

async function assertAdmin(req) {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  const s = await db.collection("users").doc(req.auth.uid).get();
  if (!s.exists || s.data().role !== "admin") throw new HttpsError("permission-denied", "Admins only.");
}

exports.sendNotification = onCall({ region: REGION }, async (req) => {
  await assertAdmin(req);
  const { title, body = "", topic = "all" } = req.data || {};
  if (!title || !/^[a-zA-Z0-9-_.~%]+$/.test(topic)) throw new HttpsError("invalid-argument", "Bad input");
  await admin.messaging().send({
    topic,
    notification: { title, body },
    android: { notification: { channelId: "studybd_default" } },
  });
  return { ok: true };
});

// "New book alert" – fires for every newly published PDF in books-like categories.
exports.onContentCreated = onDocumentCreated({ document: "content/{id}", region: REGION }, async (event) => {
  const c = event.data && event.data.data();
  if (!c) return;
  const bookLike = ["nctb", "guide", "book", "books", "testpaper"].includes(c.category);
  if (!bookLike) return;
  await admin.messaging().send({
    topic: "all",
    notification: { title: "New book added", body: c.title || "" },
    android: { notification: { channelId: "studybd_default" } },
  });
});

// Course update alert when a lesson is added.
exports.onLessonCreated = onDocumentCreated({ document: "courses/{courseId}/lessons/{lessonId}", region: REGION }, async (event) => {
  const l = event.data && event.data.data();
  if (!l) return;
  await admin.messaging().send({
    topic: `course_${event.params.courseId}`,
    notification: { title: "Course update", body: `New lesson: ${l.title || ""}` },
    android: { notification: { channelId: "studybd_default" } },
  });
});

// Runs every 5 minutes: remind about live classes starting within 15 minutes.
exports.liveReminders = onSchedule({ schedule: "every 5 minutes", region: REGION, timeZone: "Asia/Dhaka" }, async () => {
  const now = admin.firestore.Timestamp.now();
  const soon = admin.firestore.Timestamp.fromMillis(Date.now() + 15 * 60 * 1000);
  const snap = await db.collection("liveClasses").where("startsAt", ">=", now).where("startsAt", "<=", soon).get();
  for (const d of snap.docs) {
    const c = d.data();
    if (c.reminded || c.status === "ended") continue;
    await admin.messaging().send({
      topic: "all",
      notification: { title: "Live class starting soon", body: c.title || "" },
      android: { notification: { channelId: "studybd_default" } },
    });
    await d.ref.update({ reminded: true });
  }
});

// Daily 6 PM (Dhaka) exam nudge, only if an exam was published in the last 24h.
exports.examReminders = onSchedule({ schedule: "0 18 * * *", region: REGION, timeZone: "Asia/Dhaka" }, async () => {
  const since = admin.firestore.Timestamp.fromMillis(Date.now() - 24 * 3600 * 1000);
  const snap = await db.collection("exams").where("createdAt", ">=", since).limit(1).get();
  if (snap.empty) return;
  await admin.messaging().send({
    topic: "all",
    notification: { title: "New exam available", body: `${snap.docs[0].data().title || "Take a test"} — practice now!` },
    android: { notification: { channelId: "studybd_default" } },
  });
});
