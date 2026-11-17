# Public read API

Not live until the owner applies `supabase/migrations/20261117190000_public_read_api.sql` and deploys the `public-api` and `api-key-apply` functions. The switch starts off. Do not apply this to production or deploy the functions until the preview is approved.

The raw key is never printed by `create_api_key`, and it is not put in a URL. Pickup follows the research-key pattern: a proof the holder keeps, one owner approval, one delivery, then the database forgets the key.

## Turn the API on or off

```sql
select public.api_set_enabled(true);   -- or false
```

While it is off, every data request returns 503 `API is turned off` and does not read firms or count the call. Pickup still works, so a key can be delivered before the switch is on.

## Issue a key

In the SQL editor:

```sql
select public.create_api_key('name', 'who it is for', 1000);
```

The result has `key_id` only. Send the holder the apply address and that `key_id`. Do not select `api.key_pickup.pickup_key`.

Address: `POST https://sxxgvkdwgiouyqciztec.supabase.co/functions/v1/api-key-apply`

Holder:

1. Make a random proof of at least 32 characters. Keep it private. Do not put it in chat or a URL.
2. Post `{"key_id":"<key_id>","proof":"<proof>"}`.
3. While the reply is pending, send the owner `proof_prefix` only, then post the same body again.
4. The one reply `{"ok":true,"status":"delivered","key":"..."}` is the key. Save it privately. Do not print it.

Owner, after the prefix matches `select public.pending_api_key_pickups();`:

```sql
select public.approve_api_key_pickup('<key_id>');
```

If the prefix does not match:

```sql
select public.clear_api_key_pickup('<key_id>');
```

Turn a key off without deleting it:

```sql
select public.api_set_key_active('<key_id>', false);
```

## Call the API

Header `x-api-key`. Do not put the key in the URL.

- `GET /functions/v1/public-api/v1/firms`
- `GET /functions/v1/public-api/v1/firms/{slug}`
- `GET /functions/v1/public-api/v1/firms/{slug}/deals`
- `GET /functions/v1/public-api/v1/updated`

The docs page is `/api/`.

Rollback: `supabase/rollbacks/20261117190000_public_read_api.sql`.
