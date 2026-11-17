// HTTP door for the read-only API. The database decides visibility, activity, and limits.
// This file has no Deno imports so the endpoint tests can run it under Node.

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, OPTIONS",
  "access-control-allow-headers": "x-api-key, content-type",
  "access-control-max-age": "86400",
  "cache-control": "no-store",
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
};
const OFF = "API is turned off";
const KEY_QUERY = new Set(["key", "api_key", "x-api-key", "apikey"]);

export function json(body, status = 200, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json", ...extra },
  });
}

export async function sha256Hex(value) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function matchRoute(pathname) {
  let path = String(pathname || "").split("?")[0].replace(/\/+$/, "") || "/";
  const marker = "/public-api";
  const at = path.lastIndexOf(marker);
  if (at >= 0) path = path.slice(at + marker.length) || "/";
  if (path === "/v1/firms") return { name: "firms" };
  if (path === "/v1/updated") return { name: "updated" };
  let m = path.match(/^\/v1\/firms\/([a-z0-9]+(?:-[a-z0-9]+)*)\/deals$/);
  if (m) return { name: "deals", slug: m[1] };
  m = path.match(/^\/v1\/firms\/([a-z0-9]+(?:-[a-z0-9]+)*)$/);
  if (m) return { name: "firm", slug: m[1] };
  return null;
}

function limitOf(url) {
  const raw = url.searchParams.get("limit");
  if (raw == null || raw === "") return 50;
  if (!/^\d{1,4}$/.test(raw)) return null;
  const n = Number(raw);
  if (n < 1) return null;
  return Math.min(n, 100);
}

function rateHeaders(gate) {
  const headers = {};
  if (gate && Number.isInteger(gate.limit)) headers["x-ratelimit-limit"] = String(gate.limit);
  if (gate && Number.isInteger(gate.remaining)) headers["x-ratelimit-remaining"] = String(gate.remaining);
  if (gate && typeof gate.reset_at === "string") headers["x-ratelimit-reset"] = gate.reset_at;
  return headers;
}

function firmOut(firm, detail) {
  if (!firm || typeof firm !== "object") return null;
  const out = {
    id: firm.id,
    slug: firm.slug,
    name: firm.name,
    website: firm.website ?? null,
    country: firm.country ?? null,
    activity: firm.activity,
  };
  if (firm.updated_at) out.updated_at = firm.updated_at;
  if (detail) {
    out.team = Array.isArray(firm.team) ? firm.team.map((person) => ({
      name: person && person.name,
      title: person && person.title != null ? person.title : null,
      founder: !!(person && person.founder),
    })) : [];
    out.legal = Array.isArray(firm.legal) ? firm.legal.map((item) => ({
      title: item && item.title,
      status: item && item.status != null ? item.status : null,
      case_type: item && item.case_type != null ? item.case_type : null,
      filed_year: item && item.filed_year != null ? item.filed_year : null,
      court: item && item.court != null ? item.court : null,
      summary: item && item.summary != null ? item.summary : null,
      source_url: item && item.source_url != null ? item.source_url : null,
    })) : [];
  }
  return out;
}

function publicBody(route, data) {
  if (route.name === "firm") {
    const firm = firmOut(data && data.firm, true);
    return firm ? { firm } : null;
  }
  if (route.name === "deals") {
    if (!data || !Array.isArray(data.deals)) return null;
    return {
      deals: data.deals.map((deal) => ({
        startup: deal && deal.startup != null ? deal.startup : null,
        round: deal && deal.round != null ? deal.round : null,
        date: deal && deal.date != null ? deal.date : null,
        source_url: deal && deal.source_url != null ? deal.source_url : null,
      })),
      next_cursor: data.next_cursor || null,
    };
  }
  if (!data || !Array.isArray(data.firms)) return null;
  const firms = data.firms.map((firm) => firmOut(firm, false));
  if (firms.some((firm) => !firm)) return null;
  return { firms, next_cursor: data.next_cursor || null };
}

export async function handle(req, deps) {
  const started = Date.now();
  let endpoint = "";
  let keyId = null;
  let status = 500;
  const finish = async (response, log) => {
    status = response.status;
    if (log && keyId && endpoint && deps.log) {
      try { await deps.log({ keyId, endpoint, status, ms: Date.now() - started }); } catch { /* the call still answers */ }
    }
    return response;
  };
  try {
    let enabled = false;
    try { enabled = await deps.enabled(); } catch { enabled = false; }
    if (!enabled) return finish(json({ error: OFF }, 503), false);

    if (req.method === "OPTIONS") return finish(new Response(null, { status: 204, headers: CORS }), false);
    if (req.method !== "GET") return finish(json({ error: "method not allowed" }, 405), false);

    const url = new URL(req.url);
    for (const name of url.searchParams.keys()) {
      if (KEY_QUERY.has(String(name).toLowerCase())) {
        return finish(json({ error: "send the key in the x-api-key header" }, 400), false);
      }
    }
    const route = matchRoute(url.pathname);
    if (!route) return finish(json({ error: "not found" }, 404), false);
    endpoint = route.name;

    const rawKey = req.headers.get("x-api-key");
    const key = typeof rawKey === "string" ? rawKey.trim() : "";
    if (key.length < 20 || key.length > 200) return finish(json({ error: "unauthorized" }, 401), false);
    const hash = await sha256Hex(key);
    const gate = await deps.authorize(hash);
    if (!gate || gate.error === "server") return finish(json({ error: "server error" }, 500), false);
    if (gate.error === "off" || gate.ok === false && gate.error === "off") {
      return finish(json({ error: OFF }, 503), false);
    }
    if (gate.error === "rate_limited") {
      keyId = gate.key_id || null;
      const extra = rateHeaders(gate);
      const resetMs = Date.parse(gate.reset_at || "");
      if (Number.isFinite(resetMs)) extra["retry-after"] = String(Math.max(0, Math.ceil((resetMs - Date.now()) / 1000)));
      return finish(json({ error: "daily limit reached", reset_at: gate.reset_at || null }, 429, extra), true);
    }
    if (!gate.ok) return finish(json({ error: "unauthorized" }, 401), false);
    keyId = gate.key_id || null;

    const limit = limitOf(url);
    if (limit == null) return finish(json({ error: "bad request" }, 400, rateHeaders(gate)), true);
    const cursor = url.searchParams.get("cursor") || null;
    let data;
    if (route.name === "firms") {
      data = await deps.firms({
        q: url.searchParams.get("q"),
        country: url.searchParams.get("country"),
        activity: url.searchParams.get("activity"),
        cursor,
        limit,
      });
    } else if (route.name === "updated") {
      data = await deps.updated({ cursor, limit });
    } else if (route.name === "firm") {
      data = await deps.firm({ slug: route.slug });
    } else {
      data = await deps.deals({ slug: route.slug, cursor, limit });
    }
    if (!data || data.error === "server") return finish(json({ error: "server error" }, 500, rateHeaders(gate)), true);
    if (data.error === "off") return finish(json({ error: OFF }, 503), false);
    if (data.error === "not_found") return finish(json({ error: "not found" }, 404, rateHeaders(gate)), true);
    if (data.error === "bad_cursor") return finish(json({ error: "bad cursor" }, 400, rateHeaders(gate)), true);
    if (data.error === "bad_request") return finish(json({ error: "bad request" }, 400, rateHeaders(gate)), true);
    if (data.error || data.ok === false) return finish(json({ error: "server error" }, 500, rateHeaders(gate)), true);
    const body = publicBody(route, data);
    if (!body) return finish(json({ error: "server error" }, 500, rateHeaders(gate)), true);
    return finish(json(body, 200, rateHeaders(gate)), true);
  } catch {
    return finish(json({ error: "server error" }, status === 500 ? 500 : status), false);
  }
}
