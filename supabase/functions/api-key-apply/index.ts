// One-time pickup for a public API key that create_api_key already sealed.
// The URL has no secret. The holder posts key_id and a proof they keep. The owner approves once.
// The key is returned once in this response, then the database forgets it.
// verify_jwt = false because the holder has no user login. The service role stays here.
// This is separate from bots.bot_key_pickup and does not read or write that table.
import { createClient } from "npm:@supabase/supabase-js@2";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const MAX_BYTES = 4_000;
const CODES = new Set(["pending", "delivered", "unauthorized", "pending_locked", "already_delivered"]);
const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type",
  "cache-control": "no-store",
  "referrer-policy": "no-referrer",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "content-type": "application/json" } });
const sha256 = async (value: string) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)))]
    .map((b) => b.toString(16).padStart(2, "0")).join("");

Deno.serve(async (req) => {
  let status = 0;
  let keyId = "";
  let code = "unauthorized";
  const res = await (async () => {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    if (req.method !== "POST") return json({ ok: false, error: "method not allowed" }, 405);
    if ([...new URL(req.url).searchParams.keys()].length > 0) return json({ ok: false, error: "unauthorized" }, 400);
    const raw = await req.text();
    if (raw.length > MAX_BYTES) return json({ ok: false, error: "unauthorized" }, 413);
    let body: { key_id?: unknown; proof?: unknown };
    try { body = JSON.parse(raw); } catch { return json({ ok: false, error: "unauthorized" }, 400); }
    const id = typeof body.key_id === "string" ? body.key_id : "";
    const proof = typeof body.proof === "string" ? body.proof : "";
    keyId = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id) ? id : "";
    if (!keyId || proof.length < 32 || proof.length > 200) return json({ ok: false, error: "unauthorized" }, 401);
    const proofHash = await sha256(proof);
    const { data, error } = await db.rpc("api_key_apply", { p_key_id: keyId, p_proof_hash: proofHash });
    if (error || !data || typeof data !== "object") return json({ ok: false, error: "server error" }, 500);
    const row = data as { ok?: boolean; status?: string; error?: string; key?: string; proof_prefix?: string };
    const rawCode = row.ok ? String(row.status ?? "") : String(row.error ?? "");
    code = CODES.has(rawCode) ? rawCode : "other";
    if (!row.ok) {
      const http = rawCode === "already_delivered" || rawCode === "pending_locked" ? 409 : 401;
      return json({ ok: false, error: CODES.has(rawCode) ? rawCode : "unauthorized" }, http);
    }
    if (row.status === "delivered") {
      const key = typeof row.key === "string" ? row.key : "";
      if (key.length < 20 || key.length > 200) return json({ ok: false, error: "server error" }, 500);
      return json({ ok: true, status: "delivered", key }, 200);
    }
    if (row.status === "pending") {
      const prefix = typeof row.proof_prefix === "string" && /^[0-9a-f]{8}$/.test(row.proof_prefix)
        ? row.proof_prefix : "";
      return json(prefix ? { ok: true, status: "pending", proof_prefix: prefix } : { ok: true, status: "pending" }, 202);
    }
    return json({ ok: false, error: "server error" }, 500);
  })();
  status = res.status;
  console.log(JSON.stringify({ evt: "api_key_apply", key_id: keyId || null, status, code }));
  return res;
});
