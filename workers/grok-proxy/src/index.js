/**
 * The Scale shared Grok proxy.
 * Holds XAI_API_KEY server-side; iOS posts the same chat-completions JSON the app
 * would send to api.x.ai, without a Bearer header.
 */

const XAI_URL = "https://api.x.ai/v1/chat/completions";

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    if (request.method === "GET") {
      return json({ ok: true, service: "the-scale-grok" }, 200);
    }

    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }

    const apiKey = (env.XAI_API_KEY || "").trim();
    if (!apiKey) {
      return json({ error: "missing_server_key" }, 503);
    }

    let bodyText;
    try {
      bodyText = await request.text();
      if (!bodyText || bodyText.length > 120_000) {
        return json({ error: "bad_body" }, 400);
      }
      JSON.parse(bodyText);
    } catch {
      return json({ error: "invalid_json" }, 400);
    }

    const upstream = await fetch(XAI_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: bodyText,
    });

    const payload = await upstream.text();
    return new Response(payload, {
      status: upstream.status,
      headers: {
        ...corsHeaders(),
        "Content-Type": upstream.headers.get("Content-Type") || "application/json",
      },
    });
  },
};

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };
}

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders(), "Content-Type": "application/json" },
  });
}
