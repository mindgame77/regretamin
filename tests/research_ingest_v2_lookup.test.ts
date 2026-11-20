// research-ingest-v2: lookup (read-only firm / startup search) takes the key from x-ingest-key.
// No network, no database: supabase-js calls are answered by a fake fetch.
// Run: deno test -A --no-check tests/research_ingest_v2_lookup.test.ts
Deno.env.set("SUPABASE_URL", "http://mock.local");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-only-not-a-key");
type H = (r: Request) => Promise<Response>;
const handlers: H[] = [];
(Deno as any).serve = (h: H) => { handlers.push(h); return {} as any; };
const KEY = "11111111-1111-1111-1111-111111111111";
const calls: { name: string; args: any }[] = [];
let reply: any = { ok: true, kind: "firm", found: true, total: 1, matches: [{ id: 2543, name: "All Aboard", website: "https://allaboard.vc/", match_reason: "name" }] };
globalThis.fetch = async (input: any, init?: any) => {
  const u = new URL(typeof input === "string" ? input : input.url);
  const body = init?.body ? JSON.parse(String(init.body)) : null;
  const m = u.pathname.match(/\/rest\/v1\/rpc\/(\w+)/);
  const ok = (b: unknown) => new Response(JSON.stringify(b), { status: 200, headers: { "content-type": "application/json" } });
  if (m) {
    calls.push({ name: m[1], args: body });
    if (m[1] === "ingest_auth") return ok({ ok: true, key_id: KEY });
    if (m[1] === "v2_research_lookup") return ok(reply);
    return ok(null);
  }
  calls.push({ name: "table:" + u.pathname, args: body });
  return ok([]);
};
await import(new URL("../supabase/functions/research-ingest-v2/index.ts", import.meta.url).href);
const h = handlers[0];
const req = (body: unknown) =>
  new Request("http://x/research-ingest-v2", { method: "POST", headers: { "content-type": "application/json", "x-ingest-key": "k" }, body: JSON.stringify(body) });
const eq = (a: unknown, b: unknown, msg: string) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}\n got ${JSON.stringify(a)}\nwant ${JSON.stringify(b)}`); };

Deno.test("lookup firm: key from header, name and website passed through, matches returned", async () => {
  calls.length = 0;
  const r = await h(req({ action: "lookup", firm: { name: "All Aboard Fund", website: "allaboard.vc" }, key_id: "someone-else" }));
  eq(r.status, 200, "status");
  const b = await r.json();
  eq(b.matches[0].id, 2543, "match id");
  eq(typeof b.hint, "string", "hint");
  eq(calls.filter((x) => x.name === "v2_research_lookup").map((x) => x.args),
    [{ p_key: KEY, p_kind: "firm", p_name: "All Aboard Fund", p_website: "allaboard.vc" }], "rpc args");
  eq(calls.filter((x) => x.name.startsWith("table:")).length, 0, "no table reads or writes");
});

Deno.test("lookup startup: website only, empty result says not in the system", async () => {
  calls.length = 0;
  reply = { ok: true, kind: "startup", found: false, total: 0, matches: [] };
  const r = await h(req({ action: "lookup", startup: { website: "https://nope.example" } }));
  eq(r.status, 200, "status");
  const b = await r.json();
  eq(b.matches, [], "empty");
  if (!String(b.hint).includes("not in the system")) throw new Error("hint should say not in the system");
  eq(calls.find((x) => x.name === "v2_research_lookup")!.args, { p_key: KEY, p_kind: "startup", p_name: null, p_website: "https://nope.example" }, "rpc args");
});

Deno.test("lookup: bad bodies are 400 before the database", async () => {
  calls.length = 0;
  for (const body of [
    { action: "lookup" },
    { action: "lookup", firm: { name: "A" }, startup: { name: "B" } },
    { action: "lookup", firm: "All Aboard" },
    { action: "lookup", firm: [] },
    { action: "lookup", firm: {} },
    { action: "lookup", firm: { name: " ", website: "" } },
    { action: "lookup", firm: { name: 5 } },
    { action: "lookup", startup: { name: "x".repeat(201) } },
    { action: "lookup", startup: { website: "x".repeat(501) } },
  ]) eq((await h(req(body))).status, 400, JSON.stringify(body).slice(0, 80));
  eq(calls.filter((x) => x.name === "v2_research_lookup").length, 0, "no lookup rpc");
});

Deno.test("lookup: a database refusal is 400 with the reason; a database error is 500", async () => {
  reply = { ok: false, error: "website is not a valid domain, and no name was sent" };
  const r = await h(req({ action: "lookup", firm: { website: "not a site" } }));
  eq(r.status, 400, "status");
  eq((await r.json()).error, "website is not a valid domain, and no name was sent", "reason");
  reply = null;
  eq((await h(req({ action: "lookup", firm: { name: "A" } }))).status, 500, "server error");
});

Deno.test("unknown action lists lookup", async () => {
  const b = await (await h(req({ action: "nope" }))).json();
  if (!String(b.error).includes("lookup")) throw new Error("error list should name lookup");
  if (!String(b.hint).includes("\"action\":\"lookup\"")) throw new Error("hint should show lookup");
});
