// research-ingest-v2: v2 sender. Bots send batches of facts into the v2 database (v2_research_submissions -> entry check -> v2 page tables / Checker queue).
// Auth: header x-ingest-key (same key as research-ingest; sha256 checked by ingest_auth: active, kill switch, rate limit). verify_jwt = false.
// v1 research-ingest is untouched. Doc: plans/newdb/21_v2_sender.md
// add_firm refuses a website whose domain already belongs to a firm, then creates one v2_firms row (or returns the existing firm_id). It does not publish facts.
// claim reserves one free v2_research_assignments row for 6 hours and returns that v2 firm. done finishes the bot's own row.
// claim/done with block legal|reviews|youtube uses the section hold. The same ingest key is used. Plain claim/done ignore block only when it is omitted.
// Feedback inbox: a successful claim reply also has `notes` (this key's unread notes from the Regretamin team).
// notes reads them without claiming; notes_ack marks them read for this key only. Neither touches submissions or freezes.
// deals is read-only: one firm's current deals with deal_id (any bot's), for F12 corrections. only_gaps: no date and no round.
// next_firm/firm_done: the database setting v2_work_setting.current_job picks the job (job in the body is optional and only used when no job is set).
// A key may hold up to 10 firms per job from v2_work_claims, 2-hour hold. Replies and hints name the job actually used.
// add_round / claim_next_round / finish_round: the separate round list (schema roundlist, migration 20261119170000_roundlist).
// Up to 10 held rounds per key (count 1-10 per call), each with a 2-hour hold; a copy of a round is refused (409); done needs an accepted deal since the claim.
// lookup is read-only: finds an existing firm or startup by website domain, name, or partial name (migration 20261120060000_v2_research_lookup).
// lookup also accepts {"founder":{"name","linkedin_url"}} and returns up to 5 people with their startups, past jobs, and founded_before facts (migration 20261121010000_v2_founders).
// A founded_before fact may include exit_outcome (acquired, ipo, shut_down), exit_acquirer (only when acquired), and exit_source_url (required when exit_outcome is set). Empty when unknown (migration 20261121040000_v2_founder_founded_before_exit).
// A later add_founder for the same founded_before value fills those three fields when the stored row has no exit (status exit_added). An exit already stored stays: exit_already_set when the new exit differs, already stored when it is the same. The door passes the fact through; v2_founder_add does the write (migration 20261121050000_v2_founder_founded_before_exit_fill).
// Reuse a founder_id only when the LinkedIn is the same, or the name is the same and a startup or a past job matches.
// add_founder saves one person, their role at a startup, and optional facts, in one call. Nothing is written if any part is refused.
// claim_next_founder_startups / finish_founder_startup: separate hand-out (schema founderlist, migration 20261121020000_founderlist).
// Up to 10 held startups, each with a 2-hour hold. done needs a founder role for that startup saved by this bot since the claim.
// Required lookup (migration 20261120090000_v2_required_lookup): add_firm is refused (409, same_as ids) when lookup finds the same website or the
// same name / short / legal name; a new startup in submit is refused when one older startup has the same name and website base.
// Override: "not_same_as":[ids] + "not_same_reason". Switch: v2_work_setting lookup_block on/off.
import { createClient } from "npm:@supabase/supabase-js@2";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const MAX_BYTES = 2_000_000;
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "x-ingest-key, content-type, authorization" };
const json = (b: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, "content-type": "application/json", ...extra } });
const sha256 = async (s: string) => [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))]
  .map((b) => b.toString(16).padStart(2, "0")).join("");
const HINT = "POST {\"action\":\"claim\"} or {\"action\":\"done\",\"firm_id\":N} or {\"action\":\"add_firm\",\"firm\":{\"name\",\"website\",\"registry_id\"}} or {\"action\":\"submit\",\"dry_run\":false,\"items\":[{\"firm_id\":2,\"box\":\"F5\",\"table\":\"v2_investor_principles\",\"fact\":{...}}]} or {\"action\":\"results\",\"days\":30,\"limit\":100,\"firm_id\":N} or {\"action\":\"deals\",\"firm_id\":N,\"only_gaps\":false,\"limit\":500,\"offset\":0} or {\"action\":\"next_firm\"} or {\"action\":\"missing\",\"firm_id\":N} or {\"action\":\"firm_done\",\"firm_id\":N} or {\"action\":\"notes\"} or {\"action\":\"notes_ack\",\"note_ids\":[\"...\"]} or {\"action\":\"lookup\",\"firm\":{\"name\",\"website\"}} or {\"action\":\"lookup\",\"startup\":{\"name\",\"website\"}} or {\"action\":\"lookup\",\"founder\":{\"name\",\"linkedin_url\"}} or {\"action\":\"add_founder\",\"startup_id\":N,\"founder\":{\"name\",\"linkedin_url\"},\"role\":{\"source_url\"},\"facts\":[]} or {\"action\":\"claim_next_founder_startups\",\"count\":1} or {\"action\":\"finish_founder_startup\",\"startup_id\":N,\"result\":\"done|rejected\",\"note\":\"...\"}; max 10 firms per batch. Section: {\"action\":\"claim\",\"block\":\"legal|reviews|youtube\"} or {\"action\":\"done\",\"block\":\"legal|reviews|youtube\",\"firm_id\":N}";
const LOOKUP_HINT = "{\"action\":\"lookup\",\"firm\":{\"name\":\"All Aboard Fund\",\"website\":\"allaboard.vc\"}} or {\"action\":\"lookup\",\"startup\":{\"name\":\"Rivercell\",\"website\":\"rivercell.ai\"}} or {\"action\":\"lookup\",\"founder\":{\"name\":\"Ada Lovelace\",\"linkedin_url\":\"https://www.linkedin.com/in/ada\"}}; firm and startup take a name, a website, or both; a founder takes a name, a LinkedIn link, or both";
const ROUND_HINT = "Round list: {\"action\":\"add_round\",\"round\":{\"startup_name\",\"startup_website\",\"country\",\"round\",\"round_date\":\"YYYY-MM-DD\",\"source_url\"}} or {\"action\":\"claim_next_round\",\"count\":1} or {\"action\":\"finish_round\",\"round_id\":N,\"result\":\"done|rejected\",\"note\":\"...\"}";
const FOUNDER_HINT = "{\"action\":\"add_founder\",\"startup_id\":10,\"founder\":{\"name\":\"Ada Lovelace\",\"linkedin_url\":\"https://www.linkedin.com/in/ada\",\"founder_id\":7},\"role\":{\"value\":\"CEO\",\"source_url\":\"https://example.com/about\"},\"facts\":[{\"fact\":\"current_country\",\"value\":\"GB\",\"source_url\":\"https://example.com/about\"},{\"fact\":\"past_job\",\"value\":\"Babbage Co\",\"role\":\"Mathematician\",\"company_website\":\"https://babbage.example\",\"source_url\":\"https://news.example/ada\"},{\"fact\":\"founded_before\",\"value\":\"yes: Analytical Kids\",\"exit_outcome\":\"acquired\",\"exit_acquirer\":\"Babbage Co\",\"exit_source_url\":\"https://news.example/ada\"}]}";
const FOUNDERLIST_HINT = "Founder list: {\"action\":\"claim_next_founder_startups\",\"count\":1} or {\"action\":\"finish_founder_startup\",\"startup_id\":N,\"result\":\"done|rejected\",\"note\":\"...\"}";
const isObj = (v: unknown): v is Record<string, any> => !!v && typeof v === "object" && !Array.isArray(v);
const HTTP_URL = /^https?:\/\/\S+$/i;
const FOUNDER_FACTS = new Set(["current_city", "current_country", "previous_city", "previous_country", "university", "founded_before", "past_job"]);
const FOUNDER_FACT_LIST = "current_city, current_country, previous_city, previous_country, university, founded_before, past_job";
function linkedinProfile(raw: string): boolean {
  const cut = raw.trim().split(/[?#]/)[0].toLowerCase();
  const m = cut.match(/^(?:https?:\/\/)?(?:[a-z0-9-]+\.)*linkedin\.com\/in\/([^/]+)\/?$/);
  return !!m && /^[a-z0-9_-]{2,100}$/.test(m[1]);
}
// Shape checks for add_founder. The database repeats them. Messages match v2_founder_add.
function founderInputError(body: any): string | null {
  if (typeof body.startup_id !== "number" || !Number.isInteger(body.startup_id) || body.startup_id <= 0) return "startup_id is required";
  if (!isObj(body.founder)) return "founder must be an object with name, and linkedin_url or founder_id when reusing a person";
  if (!isObj(body.role)) return "role must be an object with source_url";
  const reuse = body.founder.founder_id;
  if (reuse !== undefined && reuse !== null && (typeof reuse !== "number" || !Number.isInteger(reuse) || reuse <= 0)) return "founder_id must be a positive integer";
  const name = body.founder.name;
  if (name !== undefined && name !== null && (typeof name !== "string" || name.length > 200)) return "name must be text up to 200 characters";
  if ((reuse === undefined || reuse === null) && (typeof name !== "string" || name.trim() === "")) return "founder name is required (up to 200 characters)";
  const li = body.founder.linkedin_url;
  if (li !== undefined && li !== null && li !== "" && (typeof li !== "string" || li.length > 500 || !linkedinProfile(li))) {
    return "linkedin_url must be a LinkedIn profile link like https://www.linkedin.com/in/name, or leave it out";
  }
  const src = body.role.source_url;
  if (typeof src !== "string" || !HTTP_URL.test(src.trim()) || src.trim().length > 2000) return "role source_url is required (an http(s) link)";
  if (body.role.value !== undefined && body.role.value !== null && (typeof body.role.value !== "string" || body.role.value.length > 300)) return "role value must be text up to 300 characters";
  if (body.facts === undefined || body.facts === null) return null;
  if (!Array.isArray(body.facts)) return "facts must be a list";
  if (body.facts.length > 30) return "facts can list at most 30";
  for (let i = 0; i < body.facts.length; i++) {
    const f = body.facts[i];
    const at = "facts[" + (i + 1) + "]";
    if (!isObj(f)) return at + " must be an object with fact, value and source_url";
    if (typeof f.fact !== "string") return "unknown fact type ''; allowed: " + FOUNDER_FACT_LIST;
    const kind = f.fact.trim().toLowerCase();
    if (kind === "role") return "send the startup role in role, not in facts";
    if (!FOUNDER_FACTS.has(kind)) return "unknown fact type '" + f.fact.slice(0, 40) + "'; allowed: " + FOUNDER_FACT_LIST;
    if (typeof f.source_url !== "string" || !HTTP_URL.test(f.source_url.trim()) || f.source_url.trim().length > 2000) return at + " needs a source_url (an http(s) link)";
    const hasSite = f.company_website !== undefined && f.company_website !== null && String(f.company_website).trim() !== "";
    const filled = (v: unknown) => v !== undefined && v !== null && String(v).trim() !== "";
    if (kind !== "past_job" && f.role !== undefined && f.role !== null && String(f.role).trim() !== "") return "role on a fact is only for past_job";
    if (kind !== "founded_before") {
      if (filled(f.exit_outcome)) return "exit_outcome is only for founded_before";
      if (filled(f.exit_acquirer)) return "exit_acquirer is only for founded_before";
      if (filled(f.exit_source_url)) return "exit_source_url is only for founded_before";
    }
    if (kind === "past_job") {
      if (typeof f.value !== "string" || f.value.trim() === "" || f.value.length > 300) return "past_job needs a company name in value";
      if (f.role !== undefined && f.role !== null && f.role !== "" && (typeof f.role !== "string" || f.role.trim() === "" || f.role.length > 300)) {
        return "past_job role must be text up to 300 characters, or leave it out";
      }
      if (hasSite && (typeof f.company_website !== "string" || !HTTP_URL.test(f.company_website.trim()) || f.company_website.trim().length > 500)) {
        return "past_job company_website must be an http(s) link, or leave it out";
      }
    } else if (hasSite) {
      return "company_website is only for past_job";
    } else if (kind === "current_country" || kind === "previous_country") {
      if (typeof f.value !== "string" || !/^[A-Za-z]{2}$/.test(f.value.trim())) return kind + " must be a 2-letter country code (for example US)";
    } else if (kind === "founded_before") {
      if (typeof f.value !== "string" || f.value.length > 300 || !/^(yes|no)(:\s*\S.*)?$/i.test(f.value.trim())) {
        return "founded_before value must be yes or no, optionally followed by the earlier company (yes: Earlier Company)";
      }
      if (f.exit_outcome !== undefined && f.exit_outcome !== null && f.exit_outcome !== "" && typeof f.exit_outcome !== "string") {
        return "exit_outcome must be acquired, ipo or shut_down, or leave it out";
      }
      const outcome = typeof f.exit_outcome === "string" ? f.exit_outcome.trim().toLowerCase() : "";
      if (outcome !== "" && outcome !== "acquired" && outcome !== "ipo" && outcome !== "shut_down") {
        return "exit_outcome must be acquired, ipo or shut_down, or leave it out";
      }
      if (f.exit_acquirer !== undefined && f.exit_acquirer !== null && f.exit_acquirer !== "" && (typeof f.exit_acquirer !== "string" || f.exit_acquirer.trim() === "" || f.exit_acquirer.length > 300)) {
        return "exit_acquirer must be text up to 300 characters, or leave it out";
      }
      if (typeof f.exit_acquirer === "string" && f.exit_acquirer.trim() !== "" && outcome !== "acquired") {
        return "exit_acquirer is only allowed when exit_outcome is acquired";
      }
      const exitSrc = f.exit_source_url;
      const hasExitSrc = exitSrc !== undefined && exitSrc !== null && String(exitSrc).trim() !== "";
      if (hasExitSrc && outcome === "") return "exit_source_url is only allowed when exit_outcome is set";
      if (outcome !== "" && (typeof exitSrc !== "string" || !HTTP_URL.test(exitSrc.trim()) || exitSrc.trim().length > 2000)) {
        return "exit_source_url is required when exit_outcome is set (an http(s) link)";
      }
    } else if (typeof f.value !== "string" || f.value.trim() === "" || f.value.length > 300) {
      return kind + " needs a value";
    }
  }
  return null;
}
// Domain only: lowercase, no scheme, no leading www, no port, no path.
const firmDomain = (website: string) => {
  let s = website.trim().toLowerCase();
  s = s.replace(/^[a-z][a-z0-9+.-]*:\/\//, "");
  s = s.replace(/^www\./, "");
  const cut = s.search(/[/?#]/);
  if (cut >= 0) s = s.slice(0, cut);
  return s.replace(/:\d+$/, "");
};
const domainOr = (column: string, domain: string) =>
  [domain, `www.${domain}`, `*://${domain}`, `*://www.${domain}`, `*://${domain}/*`, `*://www.${domain}/*`, `${domain}/*`, `www.${domain}/*`]
    .map((v) => `${column}.ilike."${v.replace(/"/g, "\"\"")}"`).join(",");
const sameDomain = (stored: unknown, domain: string) => typeof stored === "string" && firmDomain(stored) === domain;
// Only v2_firms. Bots and pages use that firm_id. public.firms is not read.
async function existingFirm(domain: string): Promise<{ error?: true; slug?: string; id?: string | number }> {
  const { data, error } = await db.from("v2_firms").select("firm_id, slug, website_url, archived").or(domainOr("website_url", domain)).limit(50);
  if (error) return { error: true };
  const row = (data ?? []).find((r) => r.archived !== true && r.slug && sameDomain(r.website_url, domain));
  if (row) return { slug: String(row.slug), id: row.firm_id };
  return {};
}
const JOB = /^[a-z][a-z0-9_]{0,40}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Unread notes for this key. A notes error never breaks a claim: the reply is sent without notes.
async function unreadNotes(keyId: string): Promise<unknown[] | null> {
  try {
    const { data, error } = await db.rpc("v2_bot_notes_unread", { p_key_id: keyId });
    if (error || !Array.isArray(data)) return null;
    return data;
  } catch { return null; }
}
const withNotes = async (data: any, keyId: string) => {
  const notes = await unreadNotes(keyId);
  return notes === null ? data : { ...data, notes };
};
Deno.serve(async (req) => {
  let status = 0; let bot = "";
  const res = await (async () => {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    if (req.method !== "POST") return json({ error: "method not allowed", hint: HINT }, 405);
    if (new URL(req.url).searchParams.has("key")) return json({ error: "key must not be in the URL", hint: "send it in header x-ingest-key" }, 400);
    const authz = req.headers.get("authorization") ?? "";
    const key = req.headers.get("x-ingest-key") || (/^bearer\s+/i.test(authz) ? authz.replace(/^bearer\s+/i, "").trim() : "");
    if (!key) return json({ error: "unauthorized", hint: "send the ingest key in header x-ingest-key" }, 401);
    const { data: auth, error: aerr } = await db.rpc("ingest_auth", { p_hash: await sha256(key) });
    if (aerr) return json({ error: "server error" }, 500);
    if (!auth.ok) {
      if (auth.error === "paused") return json({ error: "ingest paused - stop and report" }, 503);
      if (auth.error === "rate_limited") return json({ error: "rate limited - wait 60s" }, 429, { "retry-after": "60" });
      return json({ error: "unauthorized" }, 401);
    }
    const raw = await req.text();
    if (raw.length > MAX_BYTES) return json({ error: `payload too large (max ${MAX_BYTES} bytes)` }, 413);
    let body: any; try { body = JSON.parse(raw); } catch { return json({ error: "body is not valid JSON", hint: HINT }, 400); }
    if (!body || typeof body !== "object" || Array.isArray(body)) return json({ error: "body must be a JSON object", hint: HINT }, 400);
    if (body.dry_run !== undefined && typeof body.dry_run !== "boolean") return json({ error: "dry_run must be true or false" }, 400);
    if (body.action === "add_firm") {
      const website = body.firm && typeof body.firm === "object" && !Array.isArray(body.firm) ? body.firm.website : "";
      const domain = typeof website === "string" ? firmDomain(website) : "";
      if (/^[a-z0-9.-]+$/.test(domain) && domain.includes(".") && domain.length <= 253) {
        const existing = await existingFirm(domain);
        if (existing.error) return json({ error: "server error" }, 500);
        if (existing.slug) return json({ error: "a firm with this website already exists", slug: existing.slug, id: existing.id }, 409);
      }
      // Required lookup: same website or same name / short / legal name -> refused with the ids, unless overridden.
      const fName = body.firm && typeof body.firm === "object" && typeof body.firm.name === "string" ? body.firm.name.slice(0, 200) : null;
      const fSite = typeof website === "string" ? website.slice(0, 500) : null;
      const ns = body.not_same_as; const nsReason = typeof body.not_same_reason === "string" ? body.not_same_reason.trim().slice(0, 500) : "";
      if (ns !== undefined && (!Array.isArray(ns) || ns.length > 20 || !ns.every((x: unknown) => Number.isInteger(x) && (x as number) > 0))) {
        return json({ error: "not_same_as must be a list of up to 20 firm ids" }, 400);
      }
      const { data: guard, error: gerr } = await db.rpc("v2_firm_guard", { p_key: auth.key_id, p_name: fName, p_website: fSite });
      if (gerr || !guard) return json({ error: "server error" }, 500);
      const strong: any[] = guard.ok && Array.isArray(guard.strong) ? guard.strong : [];
      const weak: any[] = guard.ok && Array.isArray(guard.weak) ? guard.weak : [];
      let override = false;
      if (guard.ok && guard.block_on === true && strong.length > 0) {
        const ids = strong.map((m) => Number(m.id));
        const covered = Array.isArray(ns) && ids.every((id) => (ns as number[]).includes(id));
        if (!covered || !nsReason) {
          return json({ error: "a firm with this name or website already exists", same_as: ids, matches: strong,
            hint: "use the existing firm_id; only if it is a different firm, resend add_firm with \"not_same_as\":" + JSON.stringify(ids) + " and \"not_same_reason\"" }, 409);
        }
        override = true;
      }
      const { data, error } = await db.rpc("v2_research_add_firm", { p_key_id: auth.key_id, p_firm: body.firm ?? null });
      if (error || !data) return json({ error: "server error" }, 500);
      bot = data.bot_id ?? "";
      if (!data.ok) return json({ error: data.error }, String(data.error).startsWith("Key frozen") ? 403 : 400);
      if (override) {
        await db.rpc("v2_lookup_override_log", { p_key: auth.key_id, p_kind: "firm", p_name: fName, p_website: fSite,
          p_ids: ns, p_reason: nsReason, p_result_id: data.firm_id ?? null });
      }
      const extra: Record<string, unknown> = {};
      if (weak.length > 0 || (!override && strong.length > 0)) extra.similar_firms = [...strong, ...weak];
      if (override) extra.lookup_override = strong;
      return json({ ...data, ...extra }, 200);
    }
    if (body.action === "claim" && body.block === undefined) {
      const { data, error } = await db.rpc("v2_research_claim", { p_key_id: auth.key_id });
      if (error || !data) return json({ error: "server error" }, 500);
      bot = data.bot_id ?? "";
      if (!data.ok) return json({ error: data.error }, String(data.error).startsWith("Key frozen") ? 403 : 400);
      return json(await withNotes(data, auth.key_id), 200);
    }
    if (body.action === "claim") {
      const block = body.block;
      if (block !== "legal" && block !== "reviews" && block !== "youtube") {
        return json({ error: "block must be legal, reviews, or youtube" }, 400);
      }
      const { data, error } = await db.rpc("v2_section_claim", { p_key_id: auth.key_id, p_section: block });
      if (error || !data) return json({ error: "server error" }, 500);
      bot = data.bot_id ?? "";
      if (!data.ok) return json({ error: data.error }, String(data.error).startsWith("Key frozen") ? 403 : 400);
      return json(await withNotes(data, auth.key_id), 200);
    }
    if (body.action === "notes") {
      const notes = await unreadNotes(auth.key_id);
      if (notes === null) return json({ error: "server error" }, 500);
      return json({ ok: true, notes }, 200);
    }
    if (body.action === "notes_ack") {
      const ids = body.note_ids;
      if (!Array.isArray(ids) || ids.length === 0 || ids.length > 50 || !ids.every((x: unknown) => typeof x === "string" && UUID.test(x))) {
        return json({ error: "note_ids must be a list of 1-50 note_id values from the notes" }, 400);
      }
      if (body.ack_text !== undefined && (typeof body.ack_text !== "string" || body.ack_text.length > 500)) {
        return json({ error: "ack_text must be text up to 500 characters" }, 400);
      }
      const { data, error } = await db.rpc("v2_bot_notes_ack", { p_key_id: auth.key_id, p_note_ids: ids, p_ack_text: body.ack_text ?? "read" });
      if (error || !data) return json({ error: "server error" }, 500);
      if (!data.ok) return json({ error: data.error }, 400);
      return json({ ok: true, acked: data.acked ?? [], not_found: data.not_found ?? [] }, 200);
    }
    if (body.action === "done" && body.block === undefined) {
      const firmId = body.firm_id;
      if (typeof firmId !== "number" || !Number.isInteger(firmId) || firmId <= 0) {
        return json({ error: "firm_id must be the firm from claim" }, 400);
      }
      const { data, error } = await db.rpc("v2_research_done", { p_key_id: auth.key_id, p_firm_id: firmId });
      if (error || !data) return json({ error: "server error" }, 500);
      bot = data.bot_id ?? "";
      if (!data.ok) return json({ error: data.error }, String(data.error).startsWith("Key frozen") ? 403 : 400);
      return json(data, 200);
    }
    if (body.action === "done") {
      const firmId = body.firm_id;
      if (typeof firmId !== "number" || !Number.isInteger(firmId) || firmId <= 0) {
        return json({ error: "firm_id must be the firm from claim" }, 400);
      }
      const block = body.block;
      if (block !== "legal" && block !== "reviews" && block !== "youtube") {
        return json({ error: "block must be legal, reviews, or youtube" }, 400);
      }
      const { data, error } = await db.rpc("v2_section_done", { p_key_id: auth.key_id, p_section: block, p_firm_id: firmId });
      if (error || !data) return json({ error: "server error" }, 500);
      bot = data.bot_id ?? "";
      if (!data.ok) return json({ error: data.error }, String(data.error).startsWith("Key frozen") ? 403 : 400);
      return json(data, 200);
    }
    if (body.action === "list_queue" || body.action === "verdict") {  // Checker key only (checked in SQL)
      const args = body.action === "verdict" ? { id: body.id, verdict: body.verdict, reason: body.reason, sources: body.sources, drop_fields: body.drop_fields } : { limit: body.limit };
      const { data, error } = await db.rpc("v2_checker_action", { p_key_id: auth.key_id, p_action: body.action, p_args: args, p_dry_run: body.dry_run === true });
      if (error || !data) return json({ error: "server error" }, 500);
      bot = data.bot_id ?? "";
      if (!data.ok) return json({ error: data.error }, String(data.error).startsWith("only the Checker") ? 403 : 400);
      return json(data, 200);
    }
    if (body.action === "results") {
      const days = body.days === undefined ? 30 : body.days;
      const limit = body.limit === undefined ? 100 : body.limit;
      if (!Number.isInteger(days) || days < 1 || days > 30) {
        return json({ error: "days must be 1-30", hint: "omit days (defaults to 30) or send an integer 1-30" }, 400);
      }
      if (!Number.isInteger(limit) || limit < 1 || limit > 200) {
        return json({ error: "limit must be 1-200", hint: "omit limit (defaults to 100) or send an integer 1-200" }, 400);
      }
      let firmId: number | null = null;
      if (body.firm_id !== undefined && body.firm_id !== null) {
        if (typeof body.firm_id !== "number" || !Number.isInteger(body.firm_id) || body.firm_id <= 0) {
          return json({ error: "firm_id must be a positive integer" }, 400);
        }
        firmId = body.firm_id;
      }
      const { data, error } = await db.rpc("v2_research_my_results", { p_key: auth.key_id, p_days: days, p_limit: limit, p_firm_id: firmId });
      if (error || !data) return json({ error: "server error" }, 500);
      bot = data.bot_id ?? "";
      if (!data.ok) return json({ error: data.error }, 403);
      const items = Array.isArray(data.items) ? data.items : [];
      const firms = Array.isArray(data.firms) ? data.firms : [];
      return json({ ok: true, bot_id: data.bot_id, days: data.days, counts: data.counts, items, firms }, 200);
    }
    if (body.action === "deals") {
      const firmId = body.firm_id;
      if (typeof firmId !== "number" || !Number.isInteger(firmId) || firmId <= 0) {
        return json({ error: "firm_id must be a positive integer" }, 400);
      }
      if (body.only_gaps !== undefined && typeof body.only_gaps !== "boolean") return json({ error: "only_gaps must be true or false" }, 400);
      const limit = body.limit === undefined ? 500 : body.limit;
      const offset = body.offset === undefined ? 0 : body.offset;
      if (!Number.isInteger(limit) || limit < 1 || limit > 500) return json({ error: "limit must be 1-500" }, 400);
      if (!Number.isInteger(offset) || offset < 0 || offset > 100000) return json({ error: "offset must be 0 or more" }, 400);
      const { data, error } = await db.rpc("v2_research_firm_deals", {
        p_key: auth.key_id, p_firm_id: firmId, p_only_gaps: body.only_gaps === true, p_limit: limit, p_offset: offset,
      });
      if (error || !data) return json({ error: "server error" }, 500);
      if (!data.ok) return json({ error: data.error }, data.error === "firm not found" ? 404 : 403);
      return json(data, 200);
    }
    if (body.action === "missing") {  // the one-firm missing list and saved people, for any firm (redo old firms)
      const firmId = body.firm_id;
      if (typeof firmId !== "number" || !Number.isInteger(firmId) || firmId <= 0) {
        return json({ error: "firm_id must be a positive integer" }, 400);
      }
      const { data, error } = await db.rpc("v2_research_firm_missing", { p_key: auth.key_id, p_firm_id: firmId });
      if (error || !data) return json({ error: "server error" }, 500);
      if (!data.ok) return json({ error: data.error }, data.error === "unauthorized" ? 403 : 404);
      return json(data, 200);
    }
    // Read-only lookup of an existing firm, startup, or founder.
    if (body.action === "lookup") {
      const hasFirm = body.firm !== undefined; const hasStartup = body.startup !== undefined; const hasFounder = body.founder !== undefined;
      if ([hasFirm, hasStartup, hasFounder].filter(Boolean).length !== 1) return json({ error: "send exactly one of firm, startup or founder", hint: LOOKUP_HINT }, 400);
      if (hasFounder) {
        if (!isObj(body.founder)) return json({ error: "founder must be an object with name and/or linkedin_url", hint: LOOKUP_HINT }, 400);
        const name = body.founder.name ?? null; const linkedin = body.founder.linkedin_url ?? null;
        if (name !== null && (typeof name !== "string" || name.length > 200)) return json({ error: "name must be text up to 200 characters", hint: LOOKUP_HINT }, 400);
        if (linkedin !== null && (typeof linkedin !== "string" || linkedin.length > 500)) return json({ error: "linkedin_url must be text up to 500 characters", hint: LOOKUP_HINT }, 400);
        if (!(name ?? "").trim() && !(linkedin ?? "").trim()) return json({ error: "send a name or a LinkedIn link", hint: LOOKUP_HINT }, 400);
        const { data, error } = await db.rpc("v2_founder_lookup", { p_key: auth.key_id, p_name: name, p_linkedin: linkedin });
        if (error || !data) return json({ error: "server error" }, 500);
        if (!data.ok) return json({ error: data.error, hint: LOOKUP_HINT }, data.error === "unauthorized" ? 401 : 400);
        const hint = data.found
          ? "reuse a founder_id only when the LinkedIn is the same, or the name is the same and a startup or a past job matches; otherwise add a new person"
          : "no founder matched this name or LinkedIn: not stored yet";
        return json({ ...data, hint }, 200);
      }
      const kind = hasFirm ? "firm" : "startup";
      const q = hasFirm ? body.firm : body.startup;
      if (!isObj(q)) return json({ error: kind + " must be an object with name and/or website", hint: LOOKUP_HINT }, 400);
      const name = q.name ?? null; const website = q.website ?? null;
      if (name !== null && (typeof name !== "string" || name.length > 200)) return json({ error: "name must be text up to 200 characters", hint: LOOKUP_HINT }, 400);
      if (website !== null && (typeof website !== "string" || website.length > 500)) return json({ error: "website must be text up to 500 characters", hint: LOOKUP_HINT }, 400);
      if (!(name ?? "").trim() && !(website ?? "").trim()) return json({ error: "send a name or a website", hint: LOOKUP_HINT }, 400);
      const { data, error } = await db.rpc("v2_research_lookup", { p_key: auth.key_id, p_kind: kind, p_name: name, p_website: website });
      if (error || !data) return json({ error: "server error" }, 500);
      if (!data.ok) return json({ error: data.error, hint: LOOKUP_HINT }, data.error === "unauthorized" ? 401 : 400);
      const hint = data.found
        ? "use the id of the right match; check the website before you pick a name or partial name match"
        : "no " + kind + " matched this name or website: it is not in the system";
      return json({ ...data, hint }, 200);
    }
    // Round list (schema roundlist, separate from the firm/deal tables): add_round, claim_next_round, finish_round.
    if (body.action === "add_round" || body.action === "claim_next_round" || body.action === "finish_round") {
      let rpc: string; let args: Record<string, unknown>;
      if (body.action === "add_round") {
        if (!body.round || typeof body.round !== "object" || Array.isArray(body.round)) {
          return json({ error: "round must be an object", hint: ROUND_HINT }, 400);
        }
        rpc = "roundlist_add_round"; args = { p_key_id: auth.key_id, p_round: body.round };
      } else if (body.action === "claim_next_round") {
        const count = body.count === undefined ? 1 : body.count;
        if (typeof count !== "number" || !Number.isInteger(count) || count < 1 || count > 10) {
          return json({ error: "count must be 1-10 (a bot holds at most 10 rounds)", hint: ROUND_HINT }, 400);
        }
        rpc = "roundlist_claim_next_round"; args = { p_key_id: auth.key_id, p_count: count };
      } else {
        const roundId = body.round_id;
        if (typeof roundId !== "number" || !Number.isInteger(roundId) || roundId <= 0) {
          return json({ error: "round_id must be the round from claim_next_round", hint: ROUND_HINT }, 400);
        }
        if (body.result !== "done" && body.result !== "rejected") return json({ error: "result must be done or rejected", hint: ROUND_HINT }, 400);
        if (typeof body.note !== "string" || body.note.trim() === "" || body.note.length > 4000) {
          return json({ error: "note is required (up to 4000 characters)", hint: ROUND_HINT }, 400);
        }
        rpc = "roundlist_finish_round"; args = { p_key_id: auth.key_id, p_round_id: roundId, p_result: body.result, p_note: body.note };
      }
      const { data, error } = await db.rpc(rpc, args);
      if (error || !data) return json({ error: "server error" }, 500);
      bot = data.bot_id ?? "";
      if (!data.ok) {
        if (Array.isArray(data.held_round_ids)) return json({ error: data.error, held_count: data.held_count, held_round_ids: data.held_round_ids }, 409);
        return json(data.duplicate ? data : { error: data.error }, String(data.error).startsWith("Key frozen") ? 403 : data.duplicate ? 409 : 400);
      }
      if (body.action === "claim_next_round") {
        const hint = data.round
          ? "save each round's deals with submit, then send {\"action\":\"finish_round\",\"round_id\":" + data.round.round_id + ",\"result\":\"done\",\"note\":\"...\"} for each round (up to 10 held at once)"
          : "no open round left";
        return json({ ...data, hint }, 200);
      }
      return json(data, 200);
    }
    if (body.action === "next_firm" || body.action === "firm_done") {
      const job = body.job ?? null;
      if (job !== null && (typeof job !== "string" || !JOB.test(job))) return json({ error: "job must be a job name, or leave it out" }, 400);
      const firmId = body.firm_id;
      if (body.action === "firm_done" && (typeof firmId !== "number" || !Number.isInteger(firmId) || firmId <= 0)) {
        return json({ error: "firm_id must be the firm from next_firm" }, 400);
      }
      const { data, error } = body.action === "next_firm"
        ? await db.rpc("v2_next_firm", { p_key_id: auth.key_id, p_job: job })
        : await db.rpc("v2_firm_done", { p_key_id: auth.key_id, p_job: job, p_firm_id: firmId });
      if (error || !data) return json({ error: "server error" }, 500);
      bot = data.bot_id ?? "";
      if (!data.ok) return json({ error: data.error }, String(data.error).startsWith("Key frozen") ? 403 : 400);
      const usedJob = typeof data.job === "string" ? data.job : job;
      if (body.action === "next_firm") {
        const hint = data.firm ? "fix this firm, then send {\"action\":\"firm_done\",\"job\":\"" + usedJob + "\",\"firm_id\":" + data.firm.firm_id + "}" : "no firm left for this job";
        return json(await withNotes({ ...data, hint }, auth.key_id), 200);
      }
      return json({ ...data, hint: "send {\"action\":\"next_firm\",\"job\":\"" + usedJob + "\"} for the next firm" }, 200);
    }
    if (body.action === "add_founder") {
      const problem = founderInputError(body);
      if (problem) return json({ error: problem, hint: FOUNDER_HINT }, 400);
      const { data, error } = await db.rpc("v2_founder_add", {
        p_key_id: auth.key_id, p_startup_id: body.startup_id, p_founder: body.founder, p_role: body.role, p_facts: body.facts ?? [],
      });
      if (error || !data) return json({ error: "server error" }, 500);
      bot = data.bot_id ?? "";
      if (!data.ok) {
        if (data.duplicate) return json(data, 409);
        const err = String(data.error ?? "");
        return json({ error: data.error }, err.startsWith("Key frozen") ? 403 : /not found/.test(err) ? 404 : 400);
      }
      return json(data, 200);
    }
    if (body.action === "claim_next_founder_startups" || body.action === "finish_founder_startup") {
      let rpc: string; let args: Record<string, unknown>;
      if (body.action === "claim_next_founder_startups") {
        const count = body.count === undefined ? 1 : body.count;
        if (typeof count !== "number" || !Number.isInteger(count) || count < 1 || count > 10) {
          return json({ error: "count must be 1-10 (a bot holds at most 10 startups)", hint: FOUNDERLIST_HINT }, 400);
        }
        rpc = "founderlist_claim_next_founder_startups"; args = { p_key_id: auth.key_id, p_count: count };
      } else {
        const startupId = body.startup_id;
        if (typeof startupId !== "number" || !Number.isInteger(startupId) || startupId <= 0) {
          return json({ error: "startup_id must be the startup from claim_next_founder_startups", hint: FOUNDERLIST_HINT }, 400);
        }
        if (body.result !== "done" && body.result !== "rejected") return json({ error: "result must be done or rejected", hint: FOUNDERLIST_HINT }, 400);
        if (typeof body.note !== "string" || body.note.trim() === "" || body.note.length > 4000) {
          return json({ error: "note is required (up to 4000 characters)", hint: FOUNDERLIST_HINT }, 400);
        }
        rpc = "founderlist_finish_founder_startup"; args = { p_key_id: auth.key_id, p_startup_id: startupId, p_result: body.result, p_note: body.note };
      }
      const { data, error } = await db.rpc(rpc, args);
      if (error || !data) return json({ error: "server error" }, 500);
      bot = data.bot_id ?? "";
      if (!data.ok) {
        if (Array.isArray(data.held_startup_ids)) return json({ error: data.error, held_count: data.held_count, held_startup_ids: data.held_startup_ids }, 409);
        return json({ error: data.error }, String(data.error).startsWith("Key frozen") ? 403 : 400);
      }
      if (body.action === "claim_next_founder_startups") {
        const hint = data.startup
          ? "save this startup's founders with add_founder, then send {\"action\":\"finish_founder_startup\",\"startup_id\":" + data.startup.startup_id + ",\"result\":\"done\",\"note\":\"...\"} (up to 10 held at once)"
          : "no open startup left";
        return json({ ...data, hint }, 200);
      }
      return json(data, 200);
    }
    if (body.action !== "submit") return json({ error: "action must be submit, add_firm, claim, done, results, deals, missing, next_firm, firm_done, notes, notes_ack, lookup, list_queue or verdict, or add_founder, claim_next_founder_startups or finish_founder_startup", hint: HINT }, 400);
    if (!Array.isArray(body.items) || body.items.length === 0) return json({ error: "items must be a non-empty array", hint: HINT }, 400);
    if (body.dry_run !== undefined && typeof body.dry_run !== "boolean") return json({ error: "dry_run must be true or false" }, 400);
    const { data, error } = await db.rpc("v2_research_submit", { p_key_id: auth.key_id, p_items: body.items, p_dry_run: body.dry_run === true });
    if (error || !data) return json({ error: "server error" }, 500);
    bot = data.bot_id ?? "";
    if (!data.ok) return json({ error: data.error }, String(data.error).startsWith("Key frozen") ? 403 : 400);
    const sameAs = Array.isArray(data.results) && data.results.some((r: any) => r && Array.isArray(r.same_as));
    return json(data, data.accepted + data.held > 0 || data.dry_run ? 200 : sameAs ? 409 : 422);
  })();
  status = res.status;
  console.log(JSON.stringify({ evt: "ingest_v2_request", method: req.method, bot_id: bot || null, status }));
  return res;
});
