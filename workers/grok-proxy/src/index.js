/**
 * FATNAG shared Grok proxy (Worker name: the-scale-grok).
 *
 * Holds XAI_API_KEY server-side. iOS authenticates with APP_SHARED_SECRET
 * (header X-Scale-App-Secret). Enforces burst rate limits (IP + device) and
 * ISO-week Grok credit caps aligned with Free/Plus/Pro (5 / 28 / 120).
 *
 * When body.stream === true, forwards xAI SSE bytes (no full-buffer wait).
 */

const XAI_URL = "https://api.x.ai/v1/chat/completions";

/** Matches ScalePlan.weeklyGrokCredits in the iOS app. */
const WEEKLY_LIMITS = Object.freeze({
  free: 5,
  plus: 28,
  pro: 120,
});

const AUTH_HEADER = "X-Scale-App-Secret";
const DEVICE_HEADER = "X-Scale-Device-Id";
const PLAN_HEADER = "X-Scale-Plan";
const CREDIT_HEADER = "X-Scale-Credit";
/** Reserved for App Attest follow-up (ignored today). */
const ATTEST_HEADER = "X-Scale-Attest-Assertion";

const CORS_ALLOW_HEADERS = [
  "Content-Type",
  AUTH_HEADER,
  DEVICE_HEADER,
  PLAN_HEADER,
  CREDIT_HEADER,
  ATTEST_HEADER,
].join(", ");

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    if (request.method === "GET") {
      return json(
        {
          ok: true,
          service: "the-scale-grok",
          stream: true,
          auth: "shared_secret",
          weekly_limits: WEEKLY_LIMITS,
          attest: "stub",
        },
        200
      );
    }

    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }

    const apiKey = (env.XAI_API_KEY || "").trim();
    if (!apiKey) {
      return json({ error: "missing_server_key" }, 503);
    }

    const sharedSecret = (env.APP_SHARED_SECRET || "").trim();
    if (!sharedSecret) {
      return json({ error: "missing_app_secret" }, 503);
    }

    const provided = (request.headers.get(AUTH_HEADER) || "").trim();
    let authed = false;
    try {
      authed = Boolean(provided) && secretsMatch(provided, sharedSecret);
    } catch {
      authed = false;
    }
    if (!authed) {
      return json({ error: "unauthorized" }, 401);
    }

    // App Attest path (follow-up): when ATTEST_REQUIRED=1, require assertion.
    // Today we only document the header; missing assertion is allowed.
    if ((env.ATTEST_REQUIRED || "").trim() === "1") {
      const assertion = (request.headers.get(ATTEST_HEADER) || "").trim();
      if (!assertion) {
        return json(
          {
            error: "attest_required",
            detail: "App Attest assertion missing (ATTEST_REQUIRED=1).",
          },
          401
        );
      }
      // Full verification not implemented in this slice.
      return json(
        {
          error: "attest_not_implemented",
          detail: "Disable ATTEST_REQUIRED until App Attest verify lands.",
        },
        501
      );
    }

    const deviceId = normalizeDeviceId(request.headers.get(DEVICE_HEADER));
    if (!deviceId) {
      return json({ error: "missing_device_id" }, 400);
    }

    const plan = normalizePlan(request.headers.get(PLAN_HEADER));
    const burnsCredit = normalizeCredit(request.headers.get(CREDIT_HEADER));
    const clientIp = clientIpOf(request);

    const ipLimited = await checkRateLimit(env.IP_RATE_LIMIT, `ip:${clientIp}`);
    if (!ipLimited.ok) {
      return json(
        { error: "rate_limited", scope: "ip", retry_after_s: 60 },
        429,
        { "Retry-After": "60" }
      );
    }

    const deviceLimited = await checkRateLimit(
      env.DEVICE_RATE_LIMIT,
      `device:${deviceId}`
    );
    if (!deviceLimited.ok) {
      return json(
        { error: "rate_limited", scope: "device", retry_after_s: 60 },
        429,
        { "Retry-After": "60" }
      );
    }

    if (!env.LIMITS) {
      return json({ error: "missing_limits_kv" }, 503);
    }

    const week = isoWeekId(new Date());
    const weekKey = `quota:v1:${week}:${deviceId}`;
    let used = await readCount(env.LIMITS, weekKey);
    const limit = WEEKLY_LIMITS[plan];

    if (burnsCredit && used >= limit) {
      return json(
        {
          error: "quota_exhausted",
          plan,
          used,
          limit,
          week,
          detail: `Weekly Keel limit hit on ${plan} (${used}/${limit}). Resets next ISO week (Monday).`,
        },
        429,
        quotaHeaders({ plan, used, limit, week })
      );
    }

    let bodyText;
    let wantsStream = false;
    try {
      bodyText = await request.text();
      if (!bodyText || bodyText.length > 120_000) {
        return json({ error: "bad_body" }, 400);
      }
      const parsed = JSON.parse(bodyText);
      wantsStream = parsed?.stream === true;
    } catch {
      return json({ error: "invalid_json" }, 400);
    }

    if (burnsCredit) {
      used += 1;
      // ~10 days TTL so stale weeks self-expire (ISO week keys already isolate).
      await env.LIMITS.put(weekKey, String(used), { expirationTtl: 864_000 });
    }

    const upstream = await fetch(XAI_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        Accept: wantsStream ? "text/event-stream" : "application/json",
      },
      body: bodyText,
    });

    const qh = quotaHeaders({ plan, used, limit, week });

    if (wantsStream) {
      return new Response(upstream.body, {
        status: upstream.status,
        headers: {
          ...corsHeaders(),
          ...qh,
          "Content-Type":
            upstream.headers.get("Content-Type") ||
            "text/event-stream; charset=utf-8",
          "Cache-Control": "no-cache, no-transform",
          Connection: "keep-alive",
        },
      });
    }

    const payload = await upstream.text();
    return new Response(payload, {
      status: upstream.status,
      headers: {
        ...corsHeaders(),
        ...qh,
        "Content-Type":
          upstream.headers.get("Content-Type") || "application/json",
      },
    });
  },
};

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": CORS_ALLOW_HEADERS,
    "Access-Control-Expose-Headers":
      "X-Scale-Quota-Used, X-Scale-Quota-Limit, X-Scale-Quota-Plan, X-Scale-Quota-Week",
  };
}

function json(obj, status, extraHeaders = {}) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: {
      ...corsHeaders(),
      ...extraHeaders,
      "Content-Type": "application/json",
    },
  });
}

function quotaHeaders({ plan, used, limit, week }) {
  return {
    "X-Scale-Quota-Used": String(used),
    "X-Scale-Quota-Limit": String(limit),
    "X-Scale-Quota-Plan": plan,
    "X-Scale-Quota-Week": week,
  };
}

function clientIpOf(request) {
  return (
    request.headers.get("CF-Connecting-IP") ||
    request.headers.get("X-Forwarded-For")?.split(",")[0]?.trim() ||
    "unknown"
  );
}

function normalizeDeviceId(raw) {
  const value = (raw || "").trim().toLowerCase();
  if (!value || value.length > 80) return null;
  // Prefer UUID; allow stable opaque ids from older builds.
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value)) {
    return value;
  }
  if (/^[a-z0-9._:-]{8,80}$/.test(value)) return value;
  return null;
}

function normalizePlan(raw) {
  const value = (raw || "").trim().toLowerCase();
  if (value === "plus" || value === "pro" || value === "free") return value;
  return "free";
}

/** Default burns a credit. Specialist / internal consults send 0. */
function normalizeCredit(raw) {
  if (raw == null || raw === "") return true;
  const value = String(raw).trim().toLowerCase();
  if (value === "0" || value === "false" || value === "no") return false;
  return true;
}

/** ISO week id matching CoachWeeklyQuota (yearForWeekOfYear-Wweek). */
export function isoWeekId(date = new Date()) {
  // UTC-based ISO week (Monday start) — same calendar identity as most locales for week-of-year.
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((d - yearStart) / 86400000 + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

export function weeklyLimitForPlan(plan) {
  return WEEKLY_LIMITS[normalizePlan(plan)] ?? WEEKLY_LIMITS.free;
}

async function readCount(kv, key) {
  const raw = await kv.get(key);
  if (!raw) return 0;
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

async function checkRateLimit(binding, key) {
  if (!binding || typeof binding.limit !== "function") {
    // Local tests / misconfigured bind: fail open on burst limiter only when
    // the binding is absent; production wrangler.toml always defines them.
    return { ok: true, skipped: true };
  }
  try {
    const result = await binding.limit({ key });
    return { ok: result?.success !== false };
  } catch {
    // Prefer availability over hard-fail if the limiter API errors.
    return { ok: true, skipped: true };
  }
}

/** Constant-time-ish string compare for secrets (length mismatch fails fast). */
function secretsMatch(provided, expected) {
  const a = String(provided ?? "");
  const b = String(expected ?? "");
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}
