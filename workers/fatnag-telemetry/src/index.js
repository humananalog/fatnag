/**
 * FATNAG anonymous product telemetry + password-gated admin dashboard.
 *
 * POST /v1/event  — app secret + device id; aggregates only (no chat bodies)
 * GET  /admin     — login form / dashboard (ADMIN_PASSWORD)
 * POST /admin/login
 * POST /admin/logout
 */

const AUTH_HEADER = "X-Scale-App-Secret";
const DEVICE_HEADER = "X-Scale-Device-Id";
const COOKIE = "fatnag_admin";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors() });
    }

    if (url.pathname === "/v1/event" && request.method === "POST") {
      return handleEvent(request, env);
    }

    if (url.pathname === "/admin" || url.pathname === "/admin/") {
      if (request.method === "GET") {
        return (await isAuthed(request, env))
          ? renderDashboard(env)
          : renderLogin("");
      }
    }

    if (url.pathname === "/admin/login" && request.method === "POST") {
      return handleLogin(request, env);
    }

    if (url.pathname === "/admin/logout" && request.method === "POST") {
      return new Response(null, {
        status: 302,
        headers: {
          Location: "/admin",
          "Set-Cookie": `${COOKIE}=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0`,
        },
      });
    }

    if (url.pathname === "/admin/api/summary" && request.method === "GET") {
      if (!(await isAuthed(request, env))) {
        return json({ error: "unauthorized" }, 401);
      }
      return json(await summarize(env), 200);
    }

    if (url.pathname === "/" && request.method === "GET") {
      return json({ ok: true, service: "fatnag-telemetry" }, 200);
    }

    return json({ error: "not_found" }, 404);
  },
};

async function handleEvent(request, env) {
  const secret = (env.APP_SHARED_SECRET || "").trim();
  if (!secret) return json({ error: "missing_app_secret" }, 503);

  const provided = (request.headers.get(AUTH_HEADER) || "").trim();
  if (!provided || !secretsMatch(provided, secret)) {
    return json({ error: "unauthorized" }, 401);
  }

  const deviceId = (request.headers.get(DEVICE_HEADER) || "").trim();
  if (!deviceId || deviceId.length > 80) {
    return json({ error: "missing_device_id" }, 400);
  }

  if (!env.EVENTS) return json({ error: "missing_kv" }, 503);

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const name = String(body?.name || "")
    .replace(/[^a-zA-Z0-9._-]/g, "")
    .slice(0, 64);
  if (!name) return json({ error: "bad_name" }, 400);

  const day = utcDay(new Date());
  const plan = String(body?.plan || "free").slice(0, 16);
  const version = String(body?.app_version || "?").slice(0, 24);

  await bump(env.EVENTS, `day:${day}:total`, 1);
  await bump(env.EVENTS, `day:${day}:event:${name}`, 1);
  await bump(env.EVENTS, `day:${day}:plan:${plan}`, 1);
  await bump(env.EVENTS, `day:${day}:ver:${version}`, 1);
  await bump(env.EVENTS, `day:${day}:devices`, 0); // ensure key exists
  // Approximate unique devices via HyperLogLog-ish set: store device hash in a capped list key.
  await rememberDevice(env.EVENTS, day, deviceId);

  return json({ ok: true }, 200);
}

async function handleLogin(request, env) {
  const password = (env.ADMIN_PASSWORD || "").trim();
  if (!password) {
    return renderLogin("Admin password not configured on Worker.");
  }
  const form = await request.formData();
  const guess = String(form.get("password") || "");
  if (!secretsMatch(guess, password)) {
    return renderLogin("Wrong password.");
  }
  const token = await sessionToken(password);
  return new Response(null, {
    status: 302,
    headers: {
      Location: "/admin",
      "Set-Cookie": `${COOKIE}=${token}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=604800`,
    },
  });
}

async function isAuthed(request, env) {
  const password = (env.ADMIN_PASSWORD || "").trim();
  if (!password) return false;
  const cookie = request.headers.get("Cookie") || "";
  const match = cookie.match(new RegExp(`${COOKIE}=([^;]+)`));
  if (!match) return false;
  const expected = await sessionToken(password);
  return secretsMatch(match[1], expected);
}

async function sessionToken(password) {
  const data = new TextEncoder().encode(`fatnag-admin-v1:${password}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

const EVENT_NAMES = Object.freeze([
  "app.open",
  "tab.weigh",
  "tab.progress",
  "tab.keel",
  "tab.meals",
  "tab.settings",
  "weigh.save",
  "coach.open",
  "coach.send",
  "coach.session.create",
  "coach.session.select",
  "coach.session.rename",
  "coach.session.delete",
  "deploy.smoke",
]);

async function summarize(env) {
  const now = new Date();
  const dayKeys = Array.from({ length: 14 }, (_, i) =>
    utcDay(new Date(now.getTime() - i * 86_400_000))
  );

  const days = await Promise.all(
    dayKeys.map(async (key) => {
      const [total, devices, ...counts] = await Promise.all([
        readCount(env.EVENTS, `day:${key}:total`),
        readCount(env.EVENTS, `day:${key}:device_count`),
        ...EVENT_NAMES.map((name) =>
          readCount(env.EVENTS, `day:${key}:event:${name}`)
        ),
      ]);
      const events = {};
      EVENT_NAMES.forEach((name, idx) => {
        if (counts[idx] > 0) events[name] = counts[idx];
      });
      return { day: key, total, devices, events };
    })
  );

  return { days, generated_at: new Date().toISOString() };
}

/** Light shell — data loads via /admin/api/summary so the HTML response is instant. */
async function renderDashboard(_env) {
  const html = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>FATNAG telemetry</title>
<style>
  :root { color-scheme: dark; font-family: ui-sans-serif, system-ui, sans-serif; }
  body { margin: 0; background: #0b0d10; color: #e8eaed; }
  main { max-width: 960px; margin: 0 auto; padding: 28px 18px 64px; }
  h1 { font-size: 1.4rem; margin: 0 0 6px; }
  p { color: #9aa0a6; margin: 0 0 22px; }
  table { width: 100%; border-collapse: collapse; font-size: 0.92rem; }
  th, td { text-align: left; padding: 10px 8px; border-bottom: 1px solid #22262c; vertical-align: top; }
  th { color: #9aa0a6; font-weight: 600; }
  code { color: #8ab4f8; }
  form { margin: 0 0 18px; }
  button { background: #1a1f26; color: #e8eaed; border: 1px solid #2c333c; border-radius: 8px; padding: 8px 12px; cursor: pointer; }
  .muted { color: #9aa0a6; }
</style></head><body><main>
  <form method="post" action="/admin/logout"><button type="submit">Log out</button></form>
  <h1>FATNAG · anonymous usage</h1>
  <p id="meta" class="muted">Loading…</p>
  <table>
    <thead><tr><th>UTC day</th><th>Events</th><th>~Devices</th><th>Breakdown</th></tr></thead>
    <tbody id="rows"><tr><td colspan="4" class="muted">Fetching summary…</td></tr></tbody>
  </table>
<script>
async function load() {
  const res = await fetch('/admin/api/summary', { credentials: 'same-origin' });
  if (!res.ok) { document.getElementById('meta').textContent = 'Auth expired — refresh and log in.'; return; }
  const data = await res.json();
  document.getElementById('meta').textContent =
    'No chat text. No Health samples. Device UUID only. Generated ' + data.generated_at;
  document.getElementById('rows').innerHTML = (data.days || []).map(d => {
    const ev = Object.entries(d.events || {}).map(([k,v]) => '<code>' + k + '</code>: ' + v).join(' · ') || '—';
    return '<tr><td>' + d.day + '</td><td>' + d.total + '</td><td>' + d.devices + '</td><td>' + ev + '</td></tr>';
  }).join('');
}
load();
</script>
</main></body></html>`;
  return new Response(html, {
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function renderLogin(error) {
  const html = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>FATNAG admin</title>
<style>
  :root { color-scheme: dark; font-family: ui-sans-serif, system-ui, sans-serif; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #0b0d10; color: #e8eaed; }
  form { width: min(360px, 92vw); padding: 28px; background: #12161c; border: 1px solid #22262c; border-radius: 14px; }
  h1 { font-size: 1.15rem; margin: 0 0 14px; }
  input { width: 100%; box-sizing: border-box; margin: 0 0 12px; padding: 10px 12px; border-radius: 8px; border: 1px solid #2c333c; background: #0b0d10; color: #e8eaed; }
  button { width: 100%; padding: 10px; border: 0; border-radius: 8px; background: #e8eaed; color: #0b0d10; font-weight: 700; cursor: pointer; }
  .err { color: #f28b82; font-size: 0.9rem; margin: 0 0 10px; min-height: 1.2em; }
</style></head><body>
<form method="post" action="/admin/login">
  <h1>FATNAG telemetry</h1>
  <p class="err">${escapeHtml(error || "")}</p>
  <input type="password" name="password" placeholder="Admin password" autofocus required />
  <button type="submit">Enter</button>
</form></body></html>`;
  return new Response(html, {
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" },
  });
}

async function bump(kv, key, by) {
  const next = (await readCount(kv, key)) + by;
  await kv.put(key, String(next), { expirationTtl: 60 * 60 * 24 * 45 });
}

async function rememberDevice(kv, day, deviceId) {
  const setKey = `day:${day}:device_set`;
  const raw = (await kv.get(setKey)) || "";
  const parts = raw ? raw.split(",") : [];
  if (parts.includes(deviceId)) return;
  parts.push(deviceId);
  // Cap stored ids; count still useful as lower bound of uniques.
  const trimmed = parts.slice(-4000);
  await kv.put(setKey, trimmed.join(","), { expirationTtl: 60 * 60 * 24 * 45 });
  await kv.put(`day:${day}:device_count`, String(trimmed.length), {
    expirationTtl: 60 * 60 * 24 * 45,
  });
}

async function readCount(kv, key) {
  const raw = await kv.get(key);
  const n = Number.parseInt(raw || "0", 10);
  return Number.isFinite(n) ? n : 0;
}

function utcDay(d) {
  return d.toISOString().slice(0, 10);
}

function cors() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": `${AUTH_HEADER}, ${DEVICE_HEADER}, Content-Type`,
  };
}

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors(), "Content-Type": "application/json" },
  });
}

function secretsMatch(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
