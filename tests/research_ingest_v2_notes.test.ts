// Feedback inbox: claim replies carry this key's unread notes; notes and notes_ack never touch submit or freezes.
// No network, no database: supabase-js calls are answered by a fake fetch with a tiny in-memory notes table.
// Run: deno test -A --no-check tests/research_ingest_v2_notes.test.ts
Deno.env.set("SUPABASE_URL", "http://mock.local");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-only-not-a-key");
type H = (r: Request) => Promise<Response>;
const handlers: H[] = [];
(Deno as any).serve = (h: H) => { handlers.push(h); return {} as any; };
const calls: { name: string; args: any }[] = [];
const KEY_A = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const KEY_B = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const keys: Record<string, string> = { "key-a": KEY_A, "key-b": KEY_B };
const N1 = "00000000-0000-4000-8000-000000000001";
const N2 = "00000000-0000-4000-8000-000000000002";
const NB = "00000000-0000-4000-8000-0000000000b1";
type Note = { note_id: string; key: string; body: string; created_at: string; read_at: string | null };
let notes: Note[] = [];
const reset = () => {
  notes = [
    { note_id: N1, key: KEY_A, body: "use person_name, not full_name", created_at: "2026-11-18T05:00:00Z", read_at: null },
    { note_id: N2, key: KEY_A, body: "F18 title must be CEO or Managing Partner", created_at: "2026-11-18T05:01:00Z", read_at: null },
    { note_id: NB, key: KEY_B, body: "note for bot B only", created_at: "2026-11-18T05:02:00Z", read_at: null },
  ];
};
let notesBroken = false;
globalThis.fetch = async (input: any, init?: any) => {
  const u = new URL(typeof input === "string" ? input : input.url);
  const body = init?.body ? JSON.parse(String(init.body)) : null;
  const m = u.pathname.match(/\/rest\/v1\/rpc\/(\w+)/);
  const ok = (b: unknown) => new Response(JSON.stringify(b), { status: 200, headers: { "content-type": "application/json" } });
  if (!m) return ok([]);
  calls.push({ name: m[1], args: body });
  if (m[1] === "ingest_auth") {
    return ok({ ok: true, key_id: currentKey });
  }
  if (m[1] === "v2_research_claim") return ok({ ok: true, bot_id: "bot", firm_id: 7, slug: "s", name: "N", website: "https://s.example" });
  if (m[1] === "v2_section_claim") return ok({ ok: true, bot_id: "bot", section: body.p_section, firm_id: 20, slug: "t", name: "T", website: "https://t.example" });
  if (m[1] === "v2_bot_notes_unread") {
    if (notesBroken) return new Response(JSON.stringify({ message: "relation does not exist" }), { status: 404, headers: { "content-type": "application/json" } });
    return ok(notes.filter((n) => n.key === body.p_key_id && !n.read_at).map(({ note_id, body, created_at }) => ({ note_id, body, created_at })));
  }
  if (m[1] === "v2_bot_notes_ack") {
    const acked: string[] = [];
    for (const n of notes) if (n.key === body.p_key_id && !n.read_at && body.p_note_ids.includes(n.note_id)) { n.read_at = "now"; acked.push(n.note_id); }
    return ok({ ok: true, acked, not_found: body.p_note_ids.filter((x: string) => !acked.includes(x)) });
  }
  return ok(null);
};
let currentKey = KEY_A;
await import(new URL("../supabase/functions/research-ingest-v2/index.ts", import.meta.url).href);
const h = handlers[0];
const req = (body: unknown, key = "key-a") => {
  currentKey = keys[key];
  return new Request("http://x/research-ingest-v2", { method: "POST", headers: { "content-type": "application/json", "x-ingest-key": key }, body: JSON.stringify(body) });
};
const eq = (a: unknown, b: unknown, msg: string) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}\n got ${JSON.stringify(a)}\nwant ${JSON.stringify(b)}`); };
const noFreezeRpc = () => eq(calls.filter((c) => c.name === "v2_research_submit").length, 0, "submit (rejections/freeze) never called");

Deno.test("research claim reply keeps every field and adds this key's unread notes", async () => {
  reset(); calls.length = 0;
  const r = await h(req({ action: "claim" }));
  const j = await r.json();
  eq(r.status, 200, "status");
  eq([j.ok, j.firm_id, j.slug, j.name, j.website], [true, 7, "s", "N", "https://s.example"], "claim fields unchanged");
  eq(j.notes.map((n: any) => n.note_id), [N1, N2], "A's notes only");
  eq(Object.keys(j.notes[0]).sort(), ["body", "created_at", "note_id"], "note shape");
  eq(calls.find((c) => c.name === "v2_bot_notes_unread")!.args, { p_key_id: KEY_A }, "notes asked for the calling key");
  noFreezeRpc();
});

Deno.test("section claims (legal, reviews, youtube) carry notes too", async () => {
  for (const block of ["legal", "reviews", "youtube"]) {
    reset(); calls.length = 0;
    const j = await (await h(req({ action: "claim", block }))).json();
    eq([j.section, j.firm_id], [block, 20], `${block} fields`);
    eq(j.notes.map((n: any) => n.note_id), [N1, N2], `${block} notes`);
  }
});

Deno.test("no unread notes gives an empty notes list", async () => {
  reset(); notes = notes.filter((n) => n.key !== KEY_A); calls.length = 0;
  const j = await (await h(req({ action: "claim" }))).json();
  eq(j.notes, [], "empty");
});

Deno.test("a notes failure never breaks the claim: reply is the old shape without notes", async () => {
  reset(); notesBroken = true;
  try {
    const r = await h(req({ action: "claim", block: "legal" }));
    const j = await r.json();
    eq(r.status, 200, "status");
    eq(j.firm_id, 20, "firm still handed out");
    eq("notes" in j, false, "no notes key");
    eq((await h(req({ action: "notes" }))).status, 500, "plain notes read reports the error");
  } finally { notesBroken = false; }
});

Deno.test("notes reads without claiming", async () => {
  reset(); calls.length = 0;
  const r = await h(req({ action: "notes" }, "key-b"));
  const j = await r.json();
  eq(r.status, 200, "status");
  eq(j, { ok: true, notes: [{ note_id: NB, body: "note for bot B only", created_at: "2026-11-18T05:02:00Z" }] }, "B sees only B");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_bot_notes_unread"], "no claim rpc");
});

Deno.test("notes_ack marks read, and read notes stop showing", async () => {
  reset(); calls.length = 0;
  const r = await h(req({ action: "notes_ack", note_ids: [N1] }));
  eq(r.status, 200, "status");
  eq(await r.json(), { ok: true, acked: [N1], not_found: [] }, "acked");
  eq(calls[1], { name: "v2_bot_notes_ack", args: { p_key_id: KEY_A, p_note_ids: [N1], p_ack_text: "read" } }, "ack args use the calling key");
  const j = await (await h(req({ action: "claim" }))).json();
  eq(j.notes.map((n: any) => n.note_id), [N2], "only the unread note left");
  noFreezeRpc();
});

Deno.test("key isolation: bot A cannot see or ack bot B's notes", async () => {
  reset();
  const a = await (await h(req({ action: "notes" }, "key-a"))).json();
  eq(a.notes.some((n: any) => n.note_id === NB), false, "A does not see B's note");
  const ack = await (await h(req({ action: "notes_ack", note_ids: [NB] }, "key-a"))).json();
  eq(ack, { ok: true, acked: [], not_found: [NB] }, "A's ack of B's note changes nothing");
  const b = await (await h(req({ action: "notes" }, "key-b"))).json();
  eq(b.notes.map((n: any) => n.note_id), [NB], "B's note is still unread");
});

Deno.test("bad notes_ack input is refused before the database", async () => {
  reset(); calls.length = 0;
  for (const bad of [{}, { note_ids: [] }, { note_ids: "x" }, { note_ids: ["not-a-uuid"] }, { note_ids: [N1], ack_text: 5 },
                     { note_ids: Array.from({ length: 51 }, () => N1) }]) {
    eq((await h(req({ action: "notes_ack", ...bad }))).status, 400, JSON.stringify(bad).slice(0, 40));
  }
  eq(calls.filter((c) => c.name !== "ingest_auth").length, 0, "no rpc for bad input");
});
