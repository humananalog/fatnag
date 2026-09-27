import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const CATEGORIES = new Set(["bug", "idea", "praise"]);
const SOURCES = new Set(["settings", "soft_ask", "debug", "coach_reply"]);
const RATINGS = new Set(["up", "down"]);
const MAX_MESSAGE = 2000;
const MAX_CONTACT = 320;
const MAX_EXCERPT = 800;
const MAX_MODEL = 120;

type FeedbackBody = {
  category?: string;
  message?: string;
  contact?: string | null;
  app_version?: string | null;
  build?: string | null;
  platform?: string | null;
  locale?: string | null;
  device_model?: string | null;
  plan_tier?: string | null;
  anonymous_user_id?: string | null;
  source?: string | null;
  rating?: string | null;
  live_model?: string | null;
  on_device_model?: string | null;
  reply_excerpt?: string | null;
  turn_id?: string | null;
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function trimOrNull(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.slice(0, max);
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

async function sendResendEmail(params: {
  category: string;
  message: string;
  contact: string | null;
  appVersion: string | null;
  build: string | null;
  platform: string;
  locale: string | null;
  deviceModel: string | null;
  planTier: string | null;
  anonymousUserId: string;
  source: string;
  rating: string | null;
  liveModel: string | null;
  onDeviceModel: string | null;
  replyExcerpt: string | null;
  turnId: string | null;
  rowId: string;
}): Promise<{ sent: boolean; detail: string }> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    return { sent: false, detail: "RESEND_API_KEY not set" };
  }

  const from =
    Deno.env.get("RESEND_FROM") ??
    "FATNAG Feedback <feedback@inbound.humananalog.ai>";
  const to = Deno.env.get("FEEDBACK_TO") ?? "dev@humananalog.ai";

  const vote = params.rating ? ` · ${params.rating}` : "";
  const subject =
    `[FATNAG] ${params.category}${vote} · ${params.appVersion ?? "?"} (${params.build ?? "?"})`;
  const lines = [
    `Category: ${params.category}`,
    `Source: ${params.source}`,
    `Rating: ${params.rating ?? "(none)"}`,
    `Plan: ${params.planTier ?? "unknown"}`,
    `App: ${params.appVersion ?? "?"} (${params.build ?? "?"}) · ${params.platform}`,
    `Locale: ${params.locale ?? "?"}`,
    `Device: ${params.deviceModel ?? "?"}`,
    `Live model: ${params.liveModel ?? "(n/a)"}`,
    `On-device model: ${params.onDeviceModel ?? "(n/a)"}`,
    `Turn: ${params.turnId ?? "(n/a)"}`,
    `Anonymous user: ${params.anonymousUserId}`,
    `Row: ${params.rowId}`,
    `Contact: ${params.contact ?? "(none)"}`,
    "",
    params.message,
    "",
    params.replyExcerpt ? `--- Reply excerpt ---\n${params.replyExcerpt}` : "",
  ].filter((line, i, arr) => !(line === "" && arr[i - 1] === ""));

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject,
      text: lines.join("\n"),
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    return { sent: false, detail: `Resend ${res.status}: ${errText.slice(0, 400)}` };
  }
  return { sent: true, detail: "ok" };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  let body: FeedbackBody;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const category = (body.category ?? "").trim().toLowerCase();
  const message = (body.message ?? "").trim();
  const source = (body.source ?? "settings").trim().toLowerCase();
  const anonymousUserId = (body.anonymous_user_id ?? "").trim();
  const contact = trimOrNull(body.contact, MAX_CONTACT);
  const appVersion = trimOrNull(body.app_version, 40);
  const build = trimOrNull(body.build, 40);
  const platform = trimOrNull(body.platform, 40) ?? "ios";
  const locale = trimOrNull(body.locale, 40);
  const deviceModel = trimOrNull(body.device_model, 80);
  const planTier = trimOrNull(body.plan_tier, 40);
  const ratingRaw = trimOrNull(body.rating, 16)?.toLowerCase() ?? null;
  const liveModel = trimOrNull(body.live_model, MAX_MODEL);
  const onDeviceModel = trimOrNull(body.on_device_model, MAX_MODEL);
  const replyExcerpt = trimOrNull(body.reply_excerpt, MAX_EXCERPT);
  const turnIdRaw = trimOrNull(body.turn_id, 40);

  if (!CATEGORIES.has(category)) {
    return json(400, { error: "invalid_category" });
  }
  if (!SOURCES.has(source)) {
    return json(400, { error: "invalid_source" });
  }
  if (ratingRaw != null && !RATINGS.has(ratingRaw)) {
    return json(400, { error: "invalid_rating" });
  }
  if (source === "coach_reply" && ratingRaw == null) {
    return json(400, { error: "invalid_rating" });
  }
  if (message.length < 1 || message.length > MAX_MESSAGE) {
    return json(400, { error: "invalid_message" });
  }
  if (!isUuid(anonymousUserId)) {
    return json(400, { error: "invalid_anonymous_user_id" });
  }
  if (turnIdRaw != null && !isUuid(turnIdRaw)) {
    return json(400, { error: "invalid_turn_id" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return json(500, { error: "server_misconfigured" });
  }

  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await supabase
    .from("app_feedback")
    .insert({
      category,
      message,
      contact,
      app_version: appVersion,
      build,
      platform,
      locale,
      device_model: deviceModel,
      plan_tier: planTier,
      anonymous_user_id: anonymousUserId,
      source,
      rating: ratingRaw,
      live_model: liveModel,
      on_device_model: onDeviceModel,
      reply_excerpt: replyExcerpt,
      turn_id: turnIdRaw,
    })
    .select("id")
    .single();

  if (error || !data?.id) {
    console.error("app_feedback insert failed", error);
    return json(500, { error: "insert_failed" });
  }

  const email = await sendResendEmail({
    category,
    message,
    contact,
    appVersion,
    build,
    platform,
    locale,
    deviceModel,
    planTier,
    anonymousUserId,
    source,
    rating: ratingRaw,
    liveModel,
    onDeviceModel,
    replyExcerpt,
    turnId: turnIdRaw,
    rowId: data.id,
  });

  if (!email.sent) {
    console.warn("feedback email skipped/failed", email.detail);
  }

  return json(200, {
    ok: true,
    id: data.id,
    email_sent: email.sent,
  });
});
