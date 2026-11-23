// Read-only public API. verify_jwt is false: callers send x-api-key, not a user JWT.
// The service role stays in this function. Responses never include it, and logs never include the API key.
// Not deployed by this change. The owner turns the database switch on after reviewing the preview.
import { createClient } from "npm:@supabase/supabase-js@2";
import { handle } from "./handler.mjs";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function rpcError(error: { code?: string } | null) {
  if (!error) return null;
  console.log(JSON.stringify({ evt: "public_api", code: error.code || "rpc" }));
  return { ok: false, error: "server" };
}

Deno.serve((req) => handle(req, {
  enabled: async () => {
    const { data, error } = await db.rpc("api_is_enabled");
    if (error) {
      rpcError(error);
      return false;
    }
    return data === true;
  },
  authorize: async (hash: string) => {
    const { data, error } = await db.rpc("api_authorize", { p_key_hash: hash });
    return rpcError(error) || data;
  },
  firms: async (q: { q: string | null; country: string | null; activity: string | null; cursor: string | null; limit: number }) => {
    const { data, error } = await db.rpc("api_firms", {
      p_q: q.q, p_country: q.country, p_activity: q.activity, p_cursor: q.cursor, p_limit: q.limit,
    });
    return rpcError(error) || data;
  },
  updated: async (q: { cursor: string | null; limit: number }) => {
    const { data, error } = await db.rpc("api_firms_updated", { p_cursor: q.cursor, p_limit: q.limit });
    return rpcError(error) || data;
  },
  firm: async (q: { slug: string }) => {
    const { data, error } = await db.rpc("api_firm", { p_slug: q.slug });
    return rpcError(error) || data;
  },
  deals: async (q: { slug: string; cursor: string | null; limit: number }) => {
    const { data, error } = await db.rpc("api_firm_deals", { p_slug: q.slug, p_cursor: q.cursor, p_limit: q.limit });
    return rpcError(error) || data;
  },
  log: async (row: { keyId: string; endpoint: string; status: number; ms: number }) => {
    const { error } = await db.rpc("api_log", {
      p_key_id: row.keyId, p_endpoint: row.endpoint, p_status: row.status, p_ms: row.ms,
    });
    if (error) rpcError(error);
  },
}));
