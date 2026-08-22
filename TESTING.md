# Testing ActivityPub.Academy

This is a fork of Mastodon that deliberately diverges from upstream, so "the test suite
is green" needs qualifying. Some upstream specs cover behaviour this fork intentionally
changed — one-click sign-up, for instance, means every upstream assertion about choosing
a username is wrong here. Those specs are tagged and excluded rather than deleted, so
that a red suite always means a real regression.

That matters most when merging upstream: see [Merging upstream](#merging-upstream).

## Running the tests

```bash
bin/rspec-local                                   # everything
bin/rspec-local spec/requests/                    # one directory
bin/rspec-local spec/models/account_spec.rb:42    # one example
bin/rspec-local --only-failures                   # just what failed last time
```

`bin/rspec-local` handles everything: it starts the test containers, waits for them,
creates and loads the database the first time, and passes all arguments through to
`rspec`. There is no separate setup step. The first run takes a minute or so to load the
schema; later runs start immediately.

JavaScript tests are separate and unmanaged:

```bash
yarn test:jest
```

Note that no CI workflow currently runs jest — only `.github/workflows/test-ruby.yml`
(`bin/rspec`) and the linters run there.

## Test services

The suite runs against throwaway Postgres and Redis containers defined in
`docker-compose.test.yml`, on ports **5432** and **6380**.

> **Never point the suite at your development Redis.** `spec/rails_helper.rb` runs
> `redis.del(redis.keys)` after *every single example*, so it would wipe it. Redis
> pub/sub is also not database-scoped — `PUBLISH`/`SUBSCRIBE` ignore `SELECT` — so
> using a different database number on a shared server does *not* isolate the Activity
> Log pipeline spec: a running dev Puma would receive the test's synthetic events, and
> dev events would leak into the test's assertions. The test Redis therefore listens on
> 6380, and `bin/rspec-local` refuses to run if `REDIS_URL` points at 6379.

To reset the test database completely:

```bash
docker-compose -f docker-compose.test.yml down -v
```

The equivalent raw commands, if you need to debug outside the wrapper:

```bash
docker-compose -f docker-compose.test.yml up -d
export DB_HOST=localhost DB_PORT=5432 DB_USER=postgres
export REDIS_URL=redis://localhost:6380/0
RAILS_ENV=test bin/rails db:create db:schema:load db:seed
DISABLE_SIMPLECOV=true bundle exec rspec
```

`db:seed` is required, not optional: `spec/spec_helper.rb`'s `before(:suite)` calls
`Rails.application.load_seed`, and specs rely on seeded data such as the instance actor
at id `-99`.

### If the app will not boot

Native gems are compiled against system libraries. After an OS upgrade you may see
`libicudata.so.66: cannot open shared object file` or `libidn.so.11: cannot open shared
object file`. Rebuild the affected gem against the current libraries:

```bash
bundle pristine charlock_holmes
bundle pristine idn-ruby
```

## Intentionally disabled tests

Upstream specs covering behaviour this fork changed on purpose are tagged
`academy: :disabled` with a `reason:`, and excluded by default in
`spec/rails_helper.rb`. To see them:

```bash
ACADEMY_SHOW_DISABLED=1 bin/rspec-local --tag academy:disabled --dry-run   # list them
ACADEMY_SHOW_DISABLED=1 bin/rspec-local --tag academy:disabled             # run them
```

The reasons live next to each test in the source; this table is a summary.

| Spec | What is disabled | Why |
| --- | --- | --- |
| `spec/controllers/auth/registrations_controller_spec.rb` | `redirects to setup` (×4) | Sign-up redirects straight to the new user's confirmation link, not `auth_setup_path`, so the instance needs no mail server. |
| `spec/controllers/auth/registrations_controller_spec.rb` | `creates user` (×4) | `build_resource` generates username, email and password and discards what was submitted, so the user cannot be found by the submitted email. |
| `spec/controllers/auth/sessions_controller_spec.rb` | `redirects to home after sign out` (×2) | Signed-out users go to `/auth/sign_up`, not the sign-in form — accounts here are one-click and ephemeral. |
| `spec/controllers/home_controller_spec.rb` | `returns http success` (×1) | Anonymous visitors to `/` are redirected to `/auth/sign_up` instead of seeing a landing page. |

**11 examples disabled in total.** Everything else upstream ships is expected to pass.


## Merging upstream

1. Merge, then run `bin/rspec-local`.
2. **Any failure is a real regression.** Fork-intentional divergence is already
   excluded, so a red suite is signal, not noise.
3. Check what upstream converged on:
   `ACADEMY_SHOW_DISABLED=1 bin/rspec-local --tag academy:disabled`. A disabled spec
   that now *passes* means upstream moved towards our behaviour — drop the tag.
4. The specs that tell you federation and the Activity Log still work are
   `spec/requests/` and `spec/lib/activity_log_pipeline_spec.rb`. If those pass, the
   teaching features survived the merge.
5. `ActiveRecord::Migration.maintain_test_schema!` picks up new upstream migrations
   automatically; you do not need to reload the schema by hand.

## What is covered

| Feature | Specs |
| --- | --- |
| Activity Log (Redis → SSE pipeline) | `spec/lib/activity_log_pipeline_spec.rb`, `spec/lib/activity_log{ger,_event,_publisher,_audience_helper}_spec.rb`, `spec/requests/activity_log_stream_spec.rb` |
| ActivityPub Explorer (signed JSON-LD proxy) | `spec/controllers/api/v1/json_ld_controller_spec.rb` |
| Activity Workshop | `spec/requests/activity_workshop_spec.rb` |
| WebFinger Forge | `spec/requests/webfinger_override_spec.rb`, `spec/models/web_finger_override_spec.rb` |
| Academy sign-up | `spec/requests/academy_signup_spec.rb` |
| Editable actor type | `spec/requests/actor_type_spec.rb` |
| Ephemeral account cleanup | `spec/workers/scheduler/old_account_cleanup_scheduler_spec.rb` |
| Activity Log producers | `spec/workers/activitypub/delivery_worker_spec.rb`, `spec/controllers/activitypub/inboxes_controller_spec.rb` |

Two endpoints hijack the Rack socket and answer from a bare thread, so they cannot be
driven through Rack::Test end to end:

- `Api::V1::JsonLdController#show` — its redirect-following and request-signing logic is
  tested directly instead.
- `Api::V1::ActivityLogController#show` — the spec invokes the returned `rack.hijack`
  proc itself and asserts the SSE is registered.

Deliberately *not* restricted, because each is the point of the feature it belongs to:
`/api/v1/json_ld` fetches arbitrary URLs signed with the instance actor's key (that is
the Explorer); `/api/v1/activity` delivers arbitrary activities to arbitrary inboxes
(that is the Workshop); and `ActivityPub::DeliveryWorker` uses `retry: 0` so failures
appear in the Activity Log immediately instead of being retried out of sight.
