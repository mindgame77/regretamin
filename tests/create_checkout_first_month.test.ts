// First month 50% off (27 Nov 2026): monthly plans get the once-only 50% coupon, yearly plans do not.
// Runs create-checkout with fake Stripe and Supabase (no keys, no network): deno test -A tests/create_checkout_first_month.test.ts
import { assertEquals } from "jsr:@std/assert@1";

const calls: { url: string; method: string; body: string }[] = [];
let couponExists = false;
const made: URLSearchParams[] = [];
Deno.env.set("STRIPE_MODE", "live");
Deno.env.set("STRIPE_LIVE_SECRET_KEY", "sk_live_fake");
for (const k of ["PRESEED", "PRESEED_Y", "SEED", "SEED_Y", "INCUBATOR", "INCUBATOR_Y"]) Deno.env.set(`STRIPE_LIVE_PRICE_${k}`, `price_${k.toLowerCase()}`);
Deno.env.set("SITE_URL", "https://regretamin.com/");
Deno.env.set("SUPABASE_URL", "https://fake.supabase.co");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { "content-type": "application/json" } });
globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
  const req = new Request(input, init);
  const url = req.url, body = await req.text();
  calls.push({ url, method: req.method, body });
  if (url.includes("/auth/v1/user")) return json({ msg: "no user" }, 401);
  if (url.includes("/rpc/user_id_for_email")) return json(null);
  if (url.includes("/v1/coupons/regretamin_first_month_50")) return couponExists ? json({ id: "regretamin_first_month_50", object: "coupon" }) : json({ error: { code: "resource_missing", type: "invalid_request_error", message: "No such coupon" } }, 404);
  if (url.endsWith("/v1/coupons") && req.method === "POST") { couponExists = true; made.push(new URLSearchParams(body)); return json({ id: "regretamin_first_month_50", object: "coupon" }); }
  if (url.endsWith("/v1/checkout/sessions")) return json({ id: "cs_test_fake", object: "checkout.session", url: "https://checkout.stripe.com/fake" });
  return json({ error: { message: "unexpected " + url } }, 500);
};
let handler: (r: Request) => Promise<Response> = async () => new Response();
// deno-lint-ignore no-explicit-any
(Deno as any).serve = (h: (r: Request) => Promise<Response>) => { handler = h; return {}; };
await import("../supabase/functions/create-checkout/index.ts");

const buy = async (kind: string) => {
  calls.length = 0;
  const r = await handler(new Request("https://fake/functions/v1/create-checkout", { method: "POST", body: JSON.stringify({ kind, email: "probe@example.com" }) }));
  assertEquals(r.status, 200, await r.clone().text());
  const s = calls.find((c) => c.url.endsWith("/v1/checkout/sessions"))!;
  return { form: new URLSearchParams(s.body), calls: [...calls] };
};

Deno.test("monthly plans get the first-month coupon and no promotion-code box", async () => {
  for (const kind of ["preseed", "seed", "incubator"]) {
    const { form } = await buy(kind);
    assertEquals(form.get("discounts[0][coupon]"), "regretamin_first_month_50", kind);
    assertEquals(form.get("allow_promotion_codes"), null, kind);
    assertEquals(form.get("mode"), "subscription");
    assertEquals(form.get("line_items[0][price]"), `price_${kind}`);
  }
});

Deno.test("the coupon is made once (50%, once) and then reused", async () => {
  await buy("seed");
  assertEquals(made.length, 1);
  assertEquals(made[0].get("percent_off"), "50");
  assertEquals(made[0].get("duration"), "once");
  assertEquals(made[0].get("id"), "regretamin_first_month_50");
  assertEquals(made[0].get("metadata[app]"), "regretamin");
});

Deno.test("yearly plans pay full price and keep promotion codes", async () => {
  for (const kind of ["preseed_y", "seed_y", "incubator_y"]) {
    const { form } = await buy(kind);
    assertEquals(form.get("discounts[0][coupon]"), null, kind);
    assertEquals(form.get("allow_promotion_codes"), "true", kind);
  }
});
