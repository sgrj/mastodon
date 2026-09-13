# Porting activitypub-academy onto v4.7.1

Base: `v4.7.1`. This branch was cut from the tag, not from `activitypub-academy`.

**The fork spec is a git command, not a document.** For any cluster:

```sh
git diff v4.1.18..activitypub-academy -- <cluster paths>   # what the cluster must do
git diff v4.7.1..HEAD                -- <cluster paths>   # what we have built
```

A cluster is done when the second reproduces the _intent_ of the first and its specs pass.
No session needs to remember anything — re-derive from those two commands.

Full plan: `~/.claude/plans/eventual-whistling-wirth.md`

## Session start

1. `cat PORTING.md`
2. `git log --oneline v4.7.1..HEAD`
3. `git diff v4.1.18..activitypub-academy -- <today's cluster paths>`

One cluster per session, one commit per cluster. Update this file before stopping.

## Status

- [x] Phase 0 — dev loop green on unmodified v4.7.1 (7646 examples, 0 failures); Rack-hijack SSE verified
- [x] 1 — Ops & config
- [x] 2 — WebFingerOverride
- [x] 3 — Actor type (backend half only)
- [x] 4 — Academy signup (sets `id_scheme: :username_ap_id`)
- [x] 5 — Activity Log pipeline
- [x] 6 — Activity Workshop (the last `Oj.` call sites are gone)
- [x] 7 — ActivityPub Explorer (the hand-rolled signing is gone; `Request` does it)
- [x] 8 — Old account cleanup (the fork's scheduler was a no-op on v4.7.1; see Surprise 40)
- [ ] 9 — Branding & OG
- [ ] Phase 2 — Frontend
- [ ] Phase 3 — DB rehearsal + production cutover

## Decisions

- **Replay, not merge.** Never `git merge v4.7.1` — the runtime moved too far (Rails 6.1→8.1,
  Webpacker→Vite, React 16→19) for conflict resolution to mean anything.
- **actor_type UI goes in the React profile editor**, wired to
  `PATCH /api/v1/accounts/update_credentials`. Upstream reduced
  `settings/profiles/show.html.haml` to an 8-line stub, so the old server-rendered form has no host.
- **Dev loop runs in the upstream devcontainer** (`.devcontainer/compose.yaml`); the host keeps Ruby
  3.0.6 / Node 22. Requires docker compose v2 — v1 cannot parse version-less compose files.
- **The three WebFingerOverride migrations keep their original timestamps.** They are already applied
  in production; renumbering would make Rails re-run `create_web_finger_overrides` against an
  existing table. 188 upstream migrations interleave around them — expected and fine.
- **The pre-commit hook routes Ruby linters into the devcontainer.** `lint-staged.config.js` is
  patched so `bin/rubocop` and `bin/haml-lint` run via `docker compose exec`; everything else,
  lint-staged included, stays on the host. Running lint-staged itself in the container would let
  root write `.git` objects in a uid-1000 checkout. Do not use `--no-verify` to get around hook
  failures — fix the hook.
- **`actor_type` and `bot` both stay permitted on `update_credentials`.** `params.permit`
  returns keys in _filter-list_ order, not request order (verified), and `:actor_type` is
  listed after `:bot` — so a client sending both gets the explicit `actor_type`, and
  `Account#bot=` (which writes `Service`/`Person` into the same column) is overwritten
  rather than overwriting. Keep that ordering if the list is ever reshuffled.
- **`configure_sign_up_params` is left exactly as upstream wrote it.** The fork also permitted
  `:actor_type` at the top level and inside `account_attributes`. Neither is needed and one is
  harmful: `build_resource` overwrites `hash['account_attributes']` wholesale _after_
  `devise_parameter_sanitizer.sanitize(:sign_up)` has run, so the generated `username`,
  `display_name`, `actor_type` and `id_scheme` never pass through the filter at all. Meanwhile
  `User` has no `actor_type` attribute — `User.new(actor_type: 'Person')` raises
  `ActiveModel::UnknownAttributeError` (verified in a console), so permitting it at the top level
  turns a stray `user[actor_type]` parameter into a 500. Not ported.

- **The two `@@` name generators became constants plus a `Mutex`.** Same two generators, same
  `generate_name`, same output — see Surprise 21 for why the lock is not optional.

- **`HomeController#index` keeps upstream's `expires_in` on the anonymous redirect.** The fork
  dropped v4.1's `expires_in 0, public: true` because it had nothing to cache; v4.7 caches `/` for
  real, and `spec/requests/cache_spec.rb` asserts it for `/`, `/explore`, `/public` and
  `/directory` — all of which route to `home#index`. The redirect is identical for every anonymous
  visitor and `WebAppControllerConcern` already declares `vary_by 'Accept, Accept-Language,
Cookie'`, so caching it is correct. Upstream's own `redirect_unauthenticated_to_permalinks!`
  caches its redirect exactly this way.

- **`app/controllers/auth/roman.txt` stays inside `app/controllers/auth/`.** Zeitwerk only
  considers `.rb` files when it builds the autoload map, so a `.txt` in an eager-load path is
  ignored rather than an error. Checked: the suite eager-loads clean and the constant that reads it
  is evaluated once at class-body time.

- **`app/javascript/images/academy-mascot.webp` came over with this cluster,** because
  `auth/registrations/new.html.haml` renders it. `config/vite/plugin-assets-manifest.ts` globs
  `{fonts,icons,images}/**/*`, so no entrypoint registration is needed — but see Surprise 20 about
  the rebuild.

- **`activitypub-visualization` 2.0.0** (React 19, React as a webpack external) was published
  2026-09-08 and verified on the Hugo blog. Phase 2 bumps the pin from 1.5.1.
- **`ActivityPub::DeliveryWorker` keeps the fork's `retry: 0`, and it is a federation change.**
  Upstream retries an outbound delivery 16 times with growing jitter. Every attempt is a real HTTP
  request and therefore its own Activity Log entry, so upstream's schedule would replay one
  student's failed delivery into their log for days. The fork's choice is deliberate and is ported
  verbatim — but it means a transient 500 or a network blip drops the activity permanently. The
  subclasses that genuinely depend on redelivery still set their own value:
  `ActivityPub::LowPriorityDeliveryWorker` is `retry: 8`, and
  `ActivityPub::MigratedFollowDeliveryWorker` inherits `retry: 0` but only unfollows the old account
  after `super` returns, so a dropped delivery leaves the old follow in place rather than losing it.

- **An "unsalvageable" delivery failure is still a reported failure.** v4.7.1 restructured
  `perform_request` so that a 4xx (other than 401/408/429), a 501, or a 401 from a permanently
  unavailable account sets `@unsalvageable` and returns _without raising_ — no retry, no
  `track_failure!`, no exception. That is exactly the case where the student would otherwise get no
  explanation at all, so `@failure` is recorded before the salvageable/unsalvageable split, which is
  also what the fork's own hunk did (it set `@failure` for every non-2xx response). `spec/workers/activitypub/delivery_worker_spec.rb`
  pins it with a 410.

- **The outbound sender URI comes from `ActivityPub::TagManager`, and the audience regexes stay
  username-only.** The fork hardcoded `"https://#{web_domain}/users/#{username}"`; TagManager is the
  only thing that knows about v4.7's `id_scheme`. `ActivityLogAudienceHelper` still matches only the
  `/users/<name>` shape, and deliberately does **not** learn `/ap/users/<id>`: the values it returns
  are ActivityLogger routing keys, which are usernames, so a numeric URI would need a database
  lookup per recipient URI on the subscriber thread — for accounts that by construction have nobody
  watching. Cluster 4 forces `id_scheme: :username_ap_id` on every academy signup, and Risk 1's
  migration puts every pre-existing production row on the same scheme, so every account a student
  can log in to is username-based. What genuinely does not resolve is the instance actor and
  anything created by the admin CLI — none of which has an Activity Log open. Two examples in
  `spec/workers/activitypub/delivery_worker_spec.rb` pin both halves of this.

- **The audience regexes are anchored (`\A`) and the domain is `Regexp.escape`d.** The fork's four
  regexes were unanchored, so a remote server could put a local actor URI _inside_ a URI of its own
  (`https://evil.example/https://academy.example/users/alice`) and have its activity show up in that
  student's log. Nothing in the fixtures or the fork's specs depended on a mid-string match.

- **`ActivityLogger`'s registry is a class-level instance variable behind a `Mutex`** rather than the
  fork's `@@loggers` Hash — Risk 4's "fork-local fragility" is real; see Surprise 27. The lock covers
  the registry only: SSE writes happen outside it, because a write goes to a client socket and can
  block.

- **`ActivityLogSubscriber` wraps each message in `Rails.application.executor`.** The subscriber runs
  on a thread the process spawned by hand, and the `/followers` branch of audience resolution issues
  a real query; see Surprise 28.

- **The `/activity_log` SPA path is Phase 2,** like `/web_finger_forge` (Cluster 2). Only the API
  route (`config/routes/api.rb`) lands here. There is no React component to render yet.

- **`Api::V1::ActivityController` sets `wrap_parameters false` — a deliberate deviation from the
  fork.** `config/initializers/wrap_parameters.rb` wraps JSON bodies under a key derived from the
  controller name, which for this controller is `activity` — exactly the endpoint's own parameter.
  The wrapper is inert whenever that key is present, so the SPA never sees it; but on a request that
  omits `activity` it wraps the rest of the body instead, `params.require(:activity)` succeeds, and
  the instance signs and delivers `{"inbox_url": "…"}` to whatever inbox was named. On an endpoint
  whose entire job is emitting federation traffic as the student, `require` has to mean what it
  says. Turning wrapping off changes nothing on the working path and turns that case back into the
  400 the fork's own spec asserted. See Surprise 31.

- **The Explorer caps relayed bodies at 1 MB** (`MAX_BODY_SIZE`), via Mastodon's own
  `body_with_limit`. The number is deliberately shared with `ActivityPub::Activity::MAX_JSON_SIZE`,
  the ceiling an inbox applies to an incoming activity, so anything the Explorer refuses to show is
  also something the instance would have refused to federate. It refuses rather than truncates — a
  half-read JSON document reads as a malformed one — and `Content-Length` is checked before the body
  is pulled into the detached thread.
- **The Activity Workshop still validates nothing, and that is the feature.** No JSON-LD check, no
  `type` whitelist, no inbox allowlist, no SSRF guard. `params.permit(:inbox_url, activity: {})`
  passes the student's object through wholesale; the only transformations are Rails' own (see
  Surprise 32). Anything added here would remove the exercise.

- **The ActivityPub Explorer signs through `Request`, not by hand.** The fork built its own
  draft-cavage signature out of `account.keypair.sign(...)`, which cannot run on v4.7.1 at all (see
  Surprise 35). `app/lib/request.rb` already owns exactly this: `#on_behalf_of(actor)` picks the
  account's RSA keypair out of the new `keypairs` table, `CavageSignatureFeature` produces the same
  `keyId`/`algorithm`/`headers`/`signature` parameters the fork produced, and `#perform` double-knocks
  with RFC 9421 if the first attempt comes back 400 or 401. It is also what every other outbound
  signed fetch in this codebase uses, so the Explorer now succeeds exactly where federation succeeds.
  About 45 lines of hand-rolled crypto (`#signature`, `#signed_headers`, `REQUEST_TARGET`) were
  deleted rather than ported.

- **`allow_local: true` on that `Request` — the SSRF stays deliberate.** `Request::Socket`
  refuses every private address outside development (`Mastodon::PrivateNetworkAddressError`), which
  would have quietly removed half of what the Explorer is for. `allow_local: true` selects
  `ProxySocket`, whose `check_private_address` is a no-op, restoring the fork's Faraday reach. See
  Surprise 36 for what is still blocked.

- **`follow: false`, because the Explorer follows redirects itself.** `Request` defaults to
  `follow: { max_hops: 3 }`. Leaving it on would collapse the chain before `follow_redirects` saw
  it, cap it at 3 instead of the fork's `MAX_REDIRECTS = 5`, and — the reason it cannot be used at
  all — it cannot see the JSON-LD _alternate document location_, which is a `Link` header on a 200
  rather than a redirect.

- **`JsonLdHelper#fetch_resource_without_id_validation` is deliberately not used.** It returns
  parsed JSON only for a 200 with a valid ActivityPub content type and `nil` for everything else.
  A 404, an HTML page, a redirect and a `.well-known` JRD are precisely what the Explorer exists to
  show, so the helper throws away the whole feature. `Request#perform` is used directly and the
  status, headers and body are carried out of its block in a `ProxiedResponse` struct — the response
  object itself is drained and closed by `perform`'s own ensure.

- **The URL is validated before the socket is hijacked.** After a full hijack Rails can no longer
  write to the client, so `rescue_from ArgumentError` would have nowhere to render — in the fork it
  was unreachable code and a bad URL produced a hand-written raw 500. A blank `url`, or one
  `Request.valid_url?` rejects, is now a normal 422 JSON body.

- **The hand-written response line gained a reason phrase and a `Content-Length`.** The fork wrote
  `HTTP/1.1 404\r\n` — no reason phrase, no length, body delimited by `Connection: close` alone.
  Since this response is assembled by hand rather than by Rack, it is written as well-formed
  HTTP/1.1. An empty `Content-Type` header is omitted rather than emitted blank. Verified against a
  real Puma 8; see Surprise 38.

- **The detached fetch thread runs inside `Rails.application.executor.wrap`,** for the same reason
  `ActivityLogSubscriber` does (Surprise 28): it calls `Account.representative`, so a hand-spawned
  thread would hold that database connection until the Puma worker exited. 20 sequential Explorer
  fetches against a dev server with a pool of 6 all returned 200.

- **Mail delivery is configured by environment, not by patching `config/environments/`.**
  The fork forced `config.action_mailer.delivery_method = :file` in both
  `development.rb` and `production.rb`. Upstream v4.7.1 reads it from
  `config/email.yml` (`delivery_method: <%= ENV.fetch('SMTP_DELIVERY_METHOD', 'smtp') %>`)
  via `config.x.email.delivery_method`, so **set `SMTP_DELIVERY_METHOD=file` in the
  production environment** and carry no patch. Neither environment file is touched by
  this fork any more. Caveat in Surprise 6: this covers production only.

- **The old-account cleanup marks the account deleted before enqueueing `AccountDeletionWorker`.**
  Since v4.2 that worker starts with `return unless account.unavailable?`, so the fork's bare
  `AccountDeletionWorker.perform_async(id, { 'reserve_username' => false })` against a live account
  is a silent no-op — see Surprise 40. Every other caller in the codebase marks the account first,
  and the one used here is `Account#mark_deleted!`, the same call
  `Settings::DeletesController#destroy_account!` makes: this is a deletion on the student's behalf,
  not a moderation action, so no `suspend!`, no strike, and no canonical e-mail block on an address
  the instance itself invented. It also makes the job idempotent — a marked account leaves the
  `without_suspended` scope, so a backed-up `pull` queue cannot make the next minute's run call
  `create_deletion_request!` a second time on a `has_one`.

- **The underscore heuristic is unchanged, and its `\_` escape is now pinned by a spec in both
  directions.** `'%\_%'` with the backslash removed is `'%_%'`, and `_` is LIKE's single-character
  wildcard — that pattern matches every username on the instance. Verified against this instance's
  PostgreSQL 14.6 (`standard_conforming_strings` on, so a single-quoted Ruby string passes the
  backslash through untouched), as a literal and as a bind parameter; and mutation-tested, dropping
  the backslash fails two examples that assert `alice` survives. The heuristic itself is load-bearing
  for the same reason the fork's commits "do not delete crepels account" and "do not delete alice
  account" exist, and Cluster 4 still guarantees it: `username = display_name.parameterize(separator:
'_')` over a two-word generated display name.

- **Exclusions are expressed as upstream's own scopes.** `Account.local.without_instance_actor`
  replaces the fork's `where("domain IS NULL").where("id <> -99")`, and `without_suspended` is the
  new idempotency guard. `Account::INSTANCE_ACTOR_ID` is still `-99`, so the emitted SQL is
  identical; only the raw `username LIKE ?` fragment survives, because there is no scope for it.

## Surprises

Append whenever upstream contradicts an assumption in the plan. Format: what was assumed, what is
actually true, what it cost.

### 1. The test Redis no longer needs a separate port — upstream separates by DB number

**Assumed:** the plan said to keep the fork's 6380 test-Redis offset, because
`spec/rails_helper.rb:148` still runs `redis.del(redis.keys)` after every example, so "the rationale
stands verbatim."

**Actually:** the rationale does _not_ stand. In v4.1.18, `app/lib/redis_configuration.rb` used
`REDIS_URL` verbatim with no test/dev separation — so the fork's 6380 offset was genuinely load-bearing.
v4.7.1's `lib/mastodon/redis_configuration.rb:45` now does:

```ruby
db = Rails.env.test? ? ENV.fetch('TEST_ENV_NUMBER', defaults[:db]).to_i + 1 : ENV.fetch("#{prefix}DB", defaults[:db])
```

Test env gets DB 1, development keeps DB 0, and flatware workers each get `TEST_ENV_NUMBER + 1`.
The wipe is contained to the test DB. No second Redis instance or port offset is needed.

**But there is a trap.** Three lines later:

```ruby
return { url:, driver: } if url
```

Setting `REDIS_URL` short-circuits and **discards the computed db entirely**. The fork's
`bin/rspec-local` exports `REDIS_URL=redis://localhost:6380/0`, so porting that wrapper verbatim
would silently disable the new protection. Configure Redis by `REDIS_HOST`/`REDIS_PORT` components
and never set `REDIS_URL` for tests. The devcontainer already does exactly this.

**Correction (same session).** The conclusion above — "`docker-compose.test.yml` and most of
`bin/rspec-local` are obsolete" — was wrong, and Surprise 3 explains why. The port offset is
obsolete; the _guard_ is not, and both files survive in a different shape. The db-number
separation is conditional on `Rails.env.test?`, which the devcontainer quietly defeats.

### 2. `--format Fuubar` is a non-issue

The plan said to remove it from `.rspec`. We build on upstream's `.rspec` (already just `--color`
and `--require spec_helper`), so there is nothing to remove — simply don't port the fork's line.
`fuubar` is absent from v4.7.1's Gemfile.

### 3. The devcontainer's env vars silently defeat `.env.test` — 12 failures on pristine v4.7.1

**Assumed:** the plan's Phase 0 gate treated "`bin/rspec` green on unmodified v4.7.1" as a
formality.

**Actually:** it failed 12 specs, all from one cause. `.devcontainer/compose.yaml` sets variables
on the `app` service, and dotenv will not override an already-set variable, so `.env.test` is
ignored for those names: `LOCAL_DOMAIN` (6 failures — local URLs no longer recognised as local),
`REDIS_HOST` (4 — `redis_configuration_spec` asserts the localhost defaults),
`LIBRE_TRANSLATE_ENDPOINT` (1), `ES_*`.

`RAILS_ENV=development` is the dangerous member. `spec/rails_helper.rb:3` is
`ENV['RAILS_ENV'] ||= 'test'`, which cannot override it. The visible symptom is trivial
(`uninitialized constant Shoulda`); the real one is that `Rails.env.test?` goes false, disabling the
db-number separation from Surprise 1 and pointing the per-example `redis.del(redis.keys)` at
**development's** Redis.

The `REDIS_HOST` four cannot be fixed by clearing variables: the specs need it unset, the suite
needs Redis reachable. `docker-compose.test.yml` now adds `redis-test` in the app container's
network namespace so Redis genuinely answers on localhost — additive, because compose refuses to
combine `network_mode:` with the `networks:` the base service declares.

**Cost:** ~half of Phase 0. **Baseline is now 7646 examples, 0 failures, 2 pending.** See
`TESTING.md`.

### 4. A green exit code means nothing here

`rspec` exited **0** twice while running zero examples: once from the `RAILS_ENV` problem
(`0 examples, 1 error occurred outside of examples`), once from a bug in `bin/rspec-local` — `exec`
bypasses shell functions and resolved `compose` to ImageMagick's binary in `PATH`. Always check the
example count, never the status. **A third instance turned up in Cluster 1 — see Surprise 7.**

### 5. Rack-hijack SSE survives Rack 3 / Puma 8 / Rails 8.1 — verified, not assumed

**Risk 3 in the plan is retired.** Both the Activity Log (`ActionController::Live` + a
`rack.hijack` response header) and the Explorer (raw socket writes) depend on _partial_ hijack,
which Rack 3 could plausibly have dropped.

Verified twice on this branch, against rack 3.2.7 / puma 8.0.2 / rails 8.1.3.1:

1. A bare rackup app returning `{'rack.hijack' => proc}` — streamed correctly under Puma 8.
2. A throwaway Rails controller mirroring `Api::V1::ActivityLogController` exactly (same
   `Content-Type`/`Last-Modified`, same `response.headers['rack.hijack'] = proc`, same
   `SSE.new(stream)`, same `head :ok`) — streamed all events with `content-type:
text/event-stream`.

Rack 3 lowercases response header names; Rails handles that, and `rack.hijack` is already
lowercase. Both probes were removed after the check — nothing of them is committed.

**Cost:** none. Cluster 5 and Cluster 7 can be ported as-is rather than re-architected.

### 6. Cluster 1: three of the four files had moved under the fork's patch

**Assumed:** the plan described Cluster 1 as small and mostly mechanical — re-derive the
pool `+ 1`, drop two nginx blocks, add two, add one systemd line, add one gem.

**Actually,** only `dist/mastodon-web.service` and the `Gemfile` were mechanical. Three
things had moved:

1. **nginx's named location is `@mastodon` now, not `@proxy`.** The fork hardcodes
   `X-Forwarded-Proto https` there. A patch-shaped port would have failed to apply, but a
   careless hand-port would have edited the wrong block — `/api/v1/streaming` also sets
   `X-Forwarded-Proto $scheme` and looks superficially like the right target. It is not:
   the fork left the streaming block alone, and this port does too. Everything the fork
   removed (the `:80` ACME/redirect block, the whole `:443` block) is still present
   upstream in recognisable form, but the TLS block's cipher list was rewritten, so the
   deletion has to be matched by shape rather than by text.

2. **`config/database.yml`'s pool expression is now Sidekiq-aware**, as the plan warned,
   _and_ the file is split primary/replica per environment — but the `&default` anchor is
   still the single place the pool is set, so one edit still covers all six blocks. Final
   form, which preserves the fork's semantics exactly (`DB_POOL` wins verbatim; otherwise
   threads + 1):

   ```erb
   pool: <%= ENV["DB_POOL"] || ((if Sidekiq.server? then Sidekiq.default_configuration[:concurrency] else ENV['MAX_THREADS'] end) || 5).to_i + 1 %>
   ```

   Verified by rendering the ERB: no vars → 6, `MAX_THREADS=8` → 9, `DB_POOL=12` → 12.

3. **Mail:** the plan's suggestion holds for `production.rb` and only for `production.rb`.
   See Surprise 6b below.

**Cost:** small — but the `@proxy`/`@mastodon` rename is the kind of thing that ports
silently wrong and is invisible until a deploy.

### 6b. `SMTP_DELIVERY_METHOD` does not reach development

**Assumed:** setting `SMTP_DELIVERY_METHOD=file` replaces _both_ fork patches to
`config/environments/`.

**Actually:** `config/email.yml` is the only consumer of that variable, and only
`production.rb:98` reads `config.x.email.delivery_method`. `development.rb:93` still
hardcodes `ENV['HEROKU'] || ENV['VAGRANT'] || ENV['REMOTE_DEV'] ? :letter_opener_web :
:letter_opener` — no environment variable reaches it.

The decision stands (no patch), because the gap is harmless: `letter_opener_web` is
reachable at `/letter_opener` in the devcontainer and the fork's `:file` was only ever a
convenience. But **do not expect `SMTP_DELIVERY_METHOD=file` to do anything in
development.** If a future session wants file delivery there, set `REMOTE_DEV=true` for
`letter_opener_web` or patch that one line deliberately.

### 7. `bin/rspec-local` ran zero examples when invoked with no arguments

**Assumed:** Phase 0's harness was finished and `bin/rspec-local` (bare) ran the suite —
that is what `TESTING.md` documents on its first line.

**Actually:** it ran nothing and exited **0**, the third instance of the failure mode
Surprise 4 is about. `printf '%q ' "$@"` with zero arguments still runs the format once
and produces a literal `''`; rspec takes that as a path, matches nothing, and reports
`0 examples, 1 error occurred outside of examples`. Every green run in Phase 0 had passed
an explicit path, so the bug was latent.

Fixed in `bin/rspec-local` with a `[ "$#" -gt 0 ]` guard, and recorded in `TESTING.md`.
Cluster 1 committed the fix because the cluster could not otherwise be verified.

**Cost:** ~10 minutes, and it very nearly counted as a pass.

### 8. The pre-commit hook could not run at all on this host

**Assumed:** nothing — the plan never considered the hook.

**Actually:** `.husky/pre-commit` runs `yarn lint-staged` on the host, and
`lint-staged.config.js` invokes `bin/rubocop` and `bin/haml-lint`, which need Ruby 4.0.6. The host
has 3.0.6. Because lint-staged _reverts the commit_ when a task fails, this made every commit
touching a `.rb` file impossible rather than merely skipping Ruby linting. Cluster 1 worked around
it with `--no-verify`.

**Fixed:** the two Ruby entries now delegate to the devcontainer, translating lint-staged's absolute
host paths to `/workspaces/mastodon`. Verified both directions: `rubocop -a` really does rewrite
staged files, and an uncorrectable offence (`Lint/Debugger`) fails the task and reverts, so the hook
still blocks bad commits.

lint-staged itself stays on the host deliberately — it runs `git stash` and rewrites the index, and
the container is root against a uid-1000 checkout, so letting it touch `.git` would leave
root-owned objects the host's git could not write.

**Still outstanding:** the JS tasks (`yarn tsc`, `yarn i18n:extract`) also assume a working
toolchain and have not been exercised — the host has yarn 1.22.19 against a `packageManager` pin of
yarn 4.18.0. They only trigger on JS/TS changes, so Phase 2 will be the first to find out.

### 9. `oj` is gone from v4.7.1 — 20 call sites in the fork reference an undefined constant

**Assumed:** Cluster 2 was near-mechanical: a model, three migrations, two controllers, specs.

**Actually:** v4.1.18's `Gemfile` has `gem 'oj', '~> 3.13'`. v4.7.1 has no `oj` at all, not even
transitively — it is absent from `Gemfile.lock`. Every `Oj.load` / `Oj.dump` in the fork is a
`NameError` on 4.7.1.

Ported as `JSON.parse(value)` in `Api::V1::WebfingerController#create`, `.to_json` in the
fabricator, and `rescue_from JSON::ParserError, EncodingError`. The one behaviour that matters is
preserved: `JSON.parse('this is not json')` raises `JSON::ParserError` exactly where
`Oj.load(…, mode: :strict)` raised `Oj::ParseError`, so the 422 branch still fires.

**Cost:** minutes here, but this is a _silent, repo-wide_ hazard. The fork has **20 `Oj.` call
sites across 13 files**, and only 3 of them are Cluster 2:

```sh
git grep -n 'Oj\.' activitypub-academy -- app lib spec
```

The rest land in Clusters 5 (`activitypub/inboxes_controller.rb`, `activity_log_event.rb`,
`activity_log_publisher.rb`, `delivery_worker.rb`), 6 (`api/v1/activity_controller.rb`) and their
specs. A missed one is not a boot failure — it is a `NameError` on whichever code path a student
happens to exercise. Substitute on sight when porting those clusters.

### 10. `config/routes.rb` is no longer where API routes live

**Assumed:** the fork spec patches `config/routes.rb`, so this cluster does too.

**Actually:** v4.7.1 split routes into `config/routes/{api,admin,fasp,settings,web_app}.rb`. The
`namespace :v1` block is in **`config/routes/api.rb`** (the webfinger resource went in next to
`namespace :emails`, before `resource :instance`). `config/routes.rb` is not touched by this
cluster at all.

The fork's other routing change — `/web_finger_forge` in the SPA path list — now lives in
`config/routes/web_app.rb`. Deliberately **not** ported: that is Phase 2, along with the
`web_finger_forge` React component.

Related: `body_as_json` is gone from the spec helpers; use `response.parsed_body`. It returns
**symbol** keys for `application/jrd+json`, because `config/initializers/mime_types.rb` registers
that type as a synonym of `:json`. It is a `HashWithIndifferentAccess`-like object, so
`parsed_body[:subject]` works but `eq(subject: …, links: …)` against a plain symbol-keyed Hash does
**not** — assert on `response.body` when you want "served verbatim" anyway.

### 11. `well_known/webfinger_controller.rb#show` really was clean — but everything around it moved

**Assumed** (from the plan): `#show` is CLEAN, upstream never touched that method.

**Actually:** confirmed true, and worth stating precisely — six upstream commits touched that file
between the tags and none of them touched `#show`. But `set_account` was rewritten (it now
delegates to `WebfingerResource#account`, which since `806e2a993a` also resolves
`/ap/users/<id>` URLs), `check_account_suspension` moved to `permanently_unavailable?`, and
`gone` moved and gained an `expires_in`. So a **patch-shaped** apply would still have conflicted
even though the hunk itself is clean. Hand-port, as the method says.

Two follow-ups checked while here:

- **`WebfingerSerializer` diverges from what a stored override mirrors,** as the plan warned. It
  gained the FEP-3b86 `Create` / `Object` link templates, and `self` / `aliases` hrefs now come
  from `ActivityPub::TagManager.instance.uri_for`. Under v4.7's default `id_scheme:
numeric_ap_id` that href is `https://host/ap/users/<id>`, **not** `https://host/users/<name>`
  — so the "real" document the Forge offers a student as a starting point no longer looks like the
  fork's canonical example, and a blob copied from the old academy will disagree with the actor it
  points at. Acceptable for a forge (inconsistency is the lesson) and **fixed for free by Cluster
  4's `id_scheme: :username_ap_id`**. Nothing in Cluster 2 changes.

- **v4.7's "invalid handle" concept does not reach this controller.** `Account#invalidate_username!`
  raises `ArgumentError` for local accounts, and both webfinger endpoints only ever serve local
  accounts, so `invalidated_username?` is always false here and `to_webfinger_s` is unaffected. The
  `invalid_handle` attribute is remote-account UI only (`REST::AccountSerializer`,
  `ResolveAccountService`). Checked and clear — no mitigation needed.

### 12. `bin/rails db:migrate` rewrites an unrelated view in `db/schema.rb`

**Assumed:** regenerating `db/schema.rb` by running migrations yields only the new table.

**Actually:** it also reformats the `user_ips` view, requalifying the subquery columns
(`SELECT user_id` → `SELECT t0.user_id`, `GROUP BY user_id, ip` → `GROUP BY t0.user_id, t0.ip`).
That is Postgres 14 in the devcontainer re-emitting `pg_get_viewdef` differently from whatever
version generated the committed file upstream — nothing to do with this cluster.

Reverted by hand so the committed schema diff is only `web_finger_overrides` and its foreign key.
**Expect this hunk again after every migration run; drop it every time.** Do not "fix" it by
committing the reformatting — it would come back inverted on a different Postgres.

### 13. Adding a fabricator adds a spec example you did not write

**Assumed:** the suite delta after a cluster equals the number of examples in the specs you added,
so anything else is a regression. Cluster 2 added 15 examples but the suite went 7646 → **7662**.

**Actually:** `spec/fabrication/fabricators_spec.rb` walks
`Fabrication.manager.schematics` at load time and defines one example per fabricator:

```ruby
Fabrication.manager.schematics.map(&:first).each do |factory_name|
  RSpec.describe "The #{factory_name} factory" do
    it 'is able to create valid records' do
      records = Fabricate.times(2, factory_name)
      expect(records).to all(be_valid)
    end
  end
end
```

So `spec/fabricators/web_finger_override_fabricator.rb` silently contributed the 16th example,
"The web_finger_override factory is able to create valid records". Confirmed by bisecting with
`--dry-run` while moving files out of the tree.

Two things follow for later clusters:

- **Budget +1 example per new fabricator** when comparing against the 7646 baseline. Do not go
  hunting for a regression that is not there (this cost ~25 minutes of dry-run bisection here).
- That generated example calls `Fabricate.times(2, …)` — **two** records — specifically to catch
  uniqueness collisions. A fabricator with a constant value in a unique column fails there and
  nowhere else. `web_finger_override`'s `value` derives from the account, so it is fine.

### 14. `id_scheme` mitigation verified empirically (do this before Cluster 4, not during)

Risk 1 in the plan was reasoned from source. It is now measured, against a live console in the
devcontainer inside a rolled-back transaction:

```
new Account default id_scheme: "numeric_ap_id"
assignable via Account.new:    "username_ap_id"
assignable via nested attrs:   "username_ap_id"
uri_for(username_ap_id) -> http://localhost:3000/users/probeu487068
uri_for(numeric_ap_id)  -> http://localhost:3000/ap/users/117262265591683233
```

All three links in the chain hold: new accounts default to the numeric scheme, the numeric URI does
**not** match the fork's four `https://#{domain}/users/([^/]*)` audience regexes, and `id_scheme` is
assignable through **nested attributes** — which is exactly how the academy signup's
`build_resource` writes `hash["account_attributes"]`. So Cluster 4's one-line mitigation lands on a
path that works.

**Correction:** earlier notes (and an earlier version of the plan) said the numeric path was
`/ap/accounts/<id>`. It is `/ap/users/<id>`. That string appears in the Phase 3 smoke test, so it
matters.

### 15. `rails runner` needs a Chewy strategy when saving records

`ES_ENABLED=true` in the devcontainer, so any `bin/rails runner` that saves an indexed model raises
`Chewy::UndefinedUpdateStrategy` rather than a validation error — which reads as a model problem
until you look closely. Wrap in `Chewy.strategy(:bypass) { ... }`. Specs are unaffected;
`spec_helper.rb` already does this suite-wide.

### 16. There is no `actor_type` validation to remove — the fork added the one it removed

**Assumed:** fork commit `0c7327f` "remove validation for actor type" is a patch this port has
to reproduce, and v4.7.1's inclusion validator might block the values the academy needs.

**Actually:** upstream never had one. `git show v4.1.18:app/models/account.rb` has no
`validates :actor_type` line; the fork _added_ `inclusion: { in: %w(Application Organization
Service Group Person) }` in an earlier commit and then removed its own addition six lines later
in history. v4.7.1 likewise validates nothing on the column — `git grep -n actor_type -- app lib`
turns up only the `USERNAME_ONLY_RE` / `UnreservedUsernameValidator` conditionals at
`app/models/account.rb:123`/`:129`/`:130`, the `non_automated` scope, and the reader helpers.

So the column takes **any string**, including `Teapot` — covered by an example in
`spec/requests/actor_type_spec.rb`. **No validation was widened and no decision point arose.**

Knock-on effects of setting an unusual value, all checked and all intended:

- `AUTOMATED_ACTOR_TYPES = %w(Application Service)`, so `bot?` — and with it `Account.non_automated`,
  the REST `bot` attribute, and notification filtering — flips when a student picks `Service` or
  `Application`. That is the lesson, not a regression.
- `actor_type_application?` gates the _relaxed_ username rules (dots allowed, reserved names
  allowed). A student setting `Application` **after** signup never re-saves `username`, so
  `will_save_change_to_username?` is false and no validation runs — the loophole is unreachable
  through `update_credentials`. Worth re-checking if Cluster 4 ever writes `actor_type` and
  `username` in the same save.

### 17. Only one upstream example diverges — but the tagging convention had to arrive a cluster early

**Assumed:** `academy: :disabled` arrives with Cluster 4 (academy signup); Cluster 3 is
serializer + param + specs and needs nothing from it.

**Actually:** v4.7.1 added `spec/serializers/activitypub/actor_serializer_spec.rb` — it did not
exist at v4.1.18 — with a `#type` block that pins upstream's _derivation_ directly. Four of its
five examples survive the fork unchanged, because a stored `Service`/`Group`/`Person` round-trips
to itself and the instance actor's stored `actor_type` is already `Application`. The fifth,
"with an application actor", expects a plain account whose `actor_type` is `Application` to
serialize as **`Service`** (upstream collapses it through `bot?`). The fork publishes
`Application`. That is precisely the intentional divergence, so:

- `config.filter_run_excluding(academy: :disabled) unless ENV['ACADEMY_SHOW_DISABLED']` now sits in
  `spec/rails_helper.rb` beside upstream's `:js` / `:search` / `:streaming` exclusions.
- That example is tagged with a `reason:`, and an untagged sibling asserting the fork's
  `Application` sits directly below it, so the file records both behaviours.
- `bin/rspec-local` gained a `-e ACADEMY_SHOW_DISABLED=…` forward: `docker compose exec` does not
  inherit the caller's environment, so the command `TESTING.md` documents silently ran **zero**
  examples and exited 0 — the fourth instance of Surprise 4. Verified afterwards that it now runs
  the tagged example and that it genuinely fails.

**Cost:** small, and Cluster 4 inherits a mechanism that is already exercised.

### 18. `spec/requests/actor_type_spec.rb` needed three substitutions, not one

`body_as_json` → `response.parsed_body` was the expected one (Surprise 10). Two more:

- The fork's `PUT /settings/profile` block is dead — that form is gone (see Decisions). Replaced
  with `PATCH /api/v1/accounts/update_credentials` via upstream's
  `include_context 'with API authentication', oauth_scopes: 'write:accounts'`.
- `account_url(account)` still resolves to `/users/:username` (the `param: :username` route at
  `config/routes.rb:113`), so the actor document is reachable by name even under v4.7's default
  `numeric_ap_id` scheme — `AccountsController#show`'s `format.json` serves it either way. The
  spec uses `account_path` so it does not depend on `LOCAL_DOMAIN`.

### 19. Devise 5 did not change the calling convention `build_resource` depends on

**Assumed:** Devise 4.8 → 5.0.4 might have changed how `create` hands parameters to
`build_resource`, which would break the fork's central hack — it mutates the params hash _before_
calling `super`.

**Actually:** unchanged, and checked in the installed gem rather than from memory
(`/usr/local/bundle/gems/devise-5.0.4`):

- `Devise::RegistrationsController#create` is still `build_resource(sign_up_params)`.
- `sign_up_params` is still `devise_parameter_sanitizer.sanitize(:sign_up)`, and
  `ParameterSanitizer#sanitize` still ends in `cast_to_hash(params)` → `params && params.to_h`.
  `ActionController::Parameters#to_h` returns an `ActiveSupport::HashWithIndifferentAccess`, so the
  object `build_resource` receives is a **plain mutable hash, already past strong parameters** —
  which is exactly why writing `hash['account_attributes']` works and needs no permit entry.
- `Devise::RegistrationsController#build_resource(hash = {})` is `resource_class.new_with_session(hash, session)`.
  Upstream Mastodon declares `build_resource(hash = nil)` and calls bare `super`, which forwards the
  same (possibly mutated) object. `new_with_session(nil, …)` → `User.new(nil)` is fine, so the
  `unless hash.nil?` guard still distinguishes `new` from `create`.

**Cost:** 15 minutes of reading, no code. Worth stating because the hack looks fragile and is not.

### 20. `auto_build` does not rebuild for a _missing entry_ — only for a missing manifest

**Assumed:** `config/vite.yml`'s `test:` block has `auto_build: true`, so adding
`app/javascript/images/academy-mascot.webp` and referencing it with `frontend_asset_path` would
just work in the suite.

**Actually:** `lib/vite/manifest.rb#load` only retries the build when reading the manifest raises
`Errno::ENOENT`. A manifest that exists but lacks your entry goes straight to
`Vite::Manifest::MissingEntryError`, and three examples failed with
`Failed to find entry 'images/academy-mascot.webp' in manifest files`. Fixed by running
`yarn build:production` in the devcontainer once (22s).

**So: after adding or renaming anything under `app/javascript/{fonts,icons,images}`, rebuild by
hand** — `docker compose -f .devcontainer/compose.yaml exec app bash -lc 'yarn build:production'`.
Clusters 6, 7 and 9 all add assets. `public/packs/` is gitignored, so this is a local step, not a
commit.

### 21. The `@@` generators are a real race, and the gem makes it worse than it looks

**Assumed** (Risk 4 in the plan): `@@first_name_generator` / `@@last_name_generator` on a
controller class are "fork-local fragility to re-check".

**Actually:** reading `random_name_generator-4.0.5`, `Generator#compose_array` starts with
`@pre = pre_syllables.sample(random: @rnd)` — it **writes instance state on every call** — and
draws every syllable from `@rnd`, a plain `Random`, which MRI does not document as thread-safe.
Both generators are process-wide. Under Puma with several threads, two simultaneous sign-ups share
one `@pre` and one unsynchronised PRNG. The GVL keeps it from corrupting memory, so the realistic
failure is two students getting the same name — which surfaces as the username-collision error the
fork's own comment describes, only more often than "after > 1k users".

Fixed without changing the feature: the two generators are now constants and `generate_name` wraps
both `compose(3)` calls in one `Mutex#synchronize`. Composing a name is microseconds and happens
once per sign-up, so the lock costs nothing. Output, syllable files and collision behaviour are
unchanged.

**Also noted while there:** `RandomNameGenerator::FANTASY` and friends are module-level `File`
objects shared by every generator in the process, and `Generator#refresh` does `readlines` +
`rewind` on them. That is only reached from `initialize`, which happens once at class-body
evaluation, so it is not a runtime hazard here — but do not construct these generators per request.

### 22. The academy breaks 33 upstream examples, not 11 — and `spec/system/` holds most of them

**Assumed:** the fork tagged 11 examples across `registrations_controller_spec.rb`,
`sessions_controller_spec.rb` and `home_controller_spec.rb`, so the port would tag about 11.

**Actually: 33 upstream examples failed, across 10 files, and one of the fork's three files no
longer exists.** `spec/controllers/home_controller_spec.rb` is gone entirely; upstream has migrated
most of this coverage into `spec/requests/` and `spec/system/`. Of the 33, **4 were a mistake of
mine** (`cache_spec.rb`, fixed by keeping `expires_in` — see Decisions) and 29 are genuine. Three
further examples that genuinely break are `:js`/`:streaming` and so never ran; they are tagged
anyway. **Cluster 4 therefore tags 32 examples, 33 project-wide with Cluster 3's.** Breakdown:

| File                                                     | Count | What diverges                                                                                                      |
| -------------------------------------------------------- | ----- | ------------------------------------------------------------------------------------------------------------------ |
| `spec/system/auth/registrations_spec.rb`                 | 11    | The whole file drives the multi-field sign-up form. Tagged at the `RSpec.describe` level.                          |
| `spec/system/settings/migrations_spec.rb`                | 4     | `fill_in_and_submit` fills `account_migration_current_password`, a field the fork deletes.                         |
| `spec/system/settings/migration/redirects_spec.rb`       | 2     | Same, for `form_redirect_current_password` / `_current_username`.                                                  |
| `spec/controllers/auth/registrations_controller_spec.rb` | 4     | `auth_setup_path` redirect, submitted-e-mail lookup, username collision.                                           |
| `spec/controllers/auth/sessions_controller_spec.rb`      | 3     | Sign-out destination.                                                                                              |
| `spec/requests/log_out_spec.rb`                          | 2     | Sign-out destination, HTML and JSON.                                                                               |
| `spec/system/log_out_spec.rb`                            | 2     | Sign-out destination (one is `:js`).                                                                               |
| `spec/requests/content_security_policy_spec.rb`          | 1     | `GET /` no longer renders a view, so the app layout never contributes its inline-script `sha256-` to `script-src`. |
| `spec/system/home_spec.rb`                               | 2     | Anonymous `/` renders nothing (one is `:js`, for the landing-page setting, which only the JS app applies).         |
| `spec/system/unlogged_spec.rb`                           | 1     | `:js, :streaming`, so excluded by default — tagged anyway, because it genuinely breaks.                            |

Untagged siblings asserting the fork's behaviour were added in `log_out_spec.rb` (both HTML and
JSON), `home_spec.rb`, `content_security_policy_spec.rb` (same header list, asserted on
`/auth/sign_up`, which does render) and both migration system specs. The registration files get no
sibling: `spec/requests/academy_signup_spec.rb` covers that flow end to end.

**Three near-misses worth recording:**

- `spec/requests/cache_spec.rb` initially failed for `/`, `/explore`, `/public` and `/directory` —
  **all four route to `home#index`** — because the fork's `redirect_to` dropped the `expires_in`.
  Keeping it (see Decisions) is both closer to upstream and closer to the fork's intent.
- The CSP sibling on `/auth/sign_up` cannot assert upstream's whole header list: being a form page
  it relaxes `form-action` from `'none'` to `'self'`. It asserts `script-src` only, which is the
  directive the divergence is actually about.
- `spec/controllers/auth/registrations_controller_spec.rb:253` fails with a _stubbed MX_ mismatch
  (`expected ("mail.example.com", …), got ("cb6e6126.ngrok.io", …)`), not an assertion failure. The
  generated address is `<username>@<web_domain>`, so the e-mail-domain-block fixtures in that file
  can never match. Same root cause, different symptom.

### 23. The fork's own `academy_signup_spec.rb` could never have passed as written

`config/settings.yml` ships `registrations_mode: 'none'` at **both** v4.1.18 and on the fork branch
— the academy opens registrations in its production database, not in the repo. So
`check_enabled_registrations` redirects before `create` is ever reached, and every example in the
fork's `spec/requests/academy_signup_spec.rb` would have failed. Ported with
`before { Setting.registrations_mode = 'open' }` added. Nothing else in the file needed changing.

### 24. `config/initializers/stoplight.rb` needed nothing at all

**Assumed** (plan, Cluster 5): the stoplight initializer has to be moved from
`RedisConfiguration.new.connection` to `RedisConnection.new.connection`, and from
`Stoplight::Light.default_data_store =` to Stoplight 4's `Stoplight.configure { |c| ... }`.

**Actually:** v4.7.1 already ships exactly that file. Upstream made both changes for its own
reasons, and the result is byte-for-byte the shape the plan described. The file is not touched by
this cluster.

`RedisConnection` matters elsewhere in the cluster, though — `lib/activity_log_subscriber.rb`
opens its own dedicated connection (a blocking `SUBSCRIBE` must not come out of the shared pool),
and `spec/lib/activity_log_publisher_spec.rb` uses it for the listening side.

**Cost:** none. One fewer file than the plan expected.

### 25. `Oj.dump` was never Oj-specific in this cluster — `to_json` is byte-identical

**Assumed** (Surprise 9): every `Oj.` site is a substitution that has to be reasoned about
individually, and `Oj.dump` of a plain Ruby object is a serialization format this port has to
reproduce by hand.

**Actually:** v4.1's `config/initializers/oj.rb` is one line —
`Oj.default_options = { mode: :compat, time_format: :ruby, use_to_json: true }`. In `:compat` mode
with `use_to_json`, `Oj.dump(obj)` calls `obj.to_json`, which for a plain object is ActiveSupport's
`Object#as_json` → `instance_values`. So the fork's wire format was already
"ActiveSupport's hash of instance variables", and `log_event.to_json` reproduces it exactly —
including the `failure` key, which has no `attr_accessor` and is only ever read back through
`as_json`. Nothing had to be invented.

The eight sites this cluster owns, all converted:

| File                                                | Was                               | Now                                   |
| --------------------------------------------------- | --------------------------------- | ------------------------------------- |
| `app/lib/activity_log_event.rb`                     | `Oj.load(s, mode: :strict)`       | `JSON.parse(s)`                       |
| `app/lib/activity_log_publisher.rb`                 | `Oj.dump(log_event)`              | `log_event.to_json`                   |
| `app/controllers/activitypub/inboxes_controller.rb` | `Oj.load(body, mode: :strict)`    | upstream's memoized `parsed_body`     |
| `app/workers/activitypub/delivery_worker.rb`        | `Oj.load(json, mode: :strict)`    | `JSON.parse(json)`                    |
| `spec/lib/activity_log_event_spec.rb`               | `Oj.dump` / `Oj.load` (×3)        | `to_json` / `JSON.parse`              |
| `spec/lib/activity_log_publisher_spec.rb`           | `Oj.load(message, mode: :strict)` | `JSON.parse(message)`                 |
| `spec/lib/activity_log_pipeline_spec.rb`            | `Oj.load` in `event_fixture`      | deleted — the helper was never called |
| `spec/workers/activitypub/delivery_worker_spec.rb`  | `Oj.dump({...})`                  | `{...}.to_json`                       |

`git grep -n '\bOj\.' -- app lib spec config` is now clean on this branch (two binary fixtures
match by accident). The remaining fork sites are Cluster 6's `api/v1/activity_controller.rb` and
Phase 2's `application_helper.rb`.

**One behavioural difference, and it is the good direction.** `Oj.load(mode: :strict)` raised
`Oj::ParseError`; `JSON.parse` raises `JSON::ParserError` in the same places. Both are
`StandardError`, and every call site here is inside a `rescue` that already treated a parse failure
as "log it and carry on".

### 26. Puma 8 still answers to `on_worker_boot`, but only just

**Assumed** (plan): confirm Puma 8 honours `on_worker_boot`, else use `after_worker_boot`.

**Actually:** `puma-8.0.2/lib/puma/dsl.rb:830` is `alias_method :on_worker_boot, :before_worker_boot`,
and `before_worker_boot` opens with `Puma.deprecate_method_change :on_worker_boot, __callee__, __method__`.
So the fork's spelling still works and prints a deprecation on every boot. `after_worker_boot` is
something else entirely — it is an alias of `after_worker_fork`, which runs in the **master**
process after forking a worker, and a thread started there would be in the wrong process.

The hook is therefore written as `before_worker_boot`, which is also what upstream's own Prometheus
hooks in the same file already use. Verified by loading the real config through
`Puma::Configuration#load` + `#clamp`: one `before_worker_boot` hook registered, no deprecation
printed, and `ActivityLogSubscriber` resolved from the `require_relative` at the top of the file.

`lib/` is on `$LOAD_PATH` (Rails::Engine adds it) but not on the autoload path — `config.autoload_lib`
is commented out in `config/application.rb` — so both `config/puma.rb` and the pipeline spec have to
require `activity_log_subscriber` explicitly. That is unchanged from the fork.

### 27. `ActivityLogger`'s class variable is racy in two different ways

**Assumed** (Risk 4): "fork-local fragility to re-check under Rails 8."

**Actually:** the class variable is not the problem — a bare `Hash` reached from three kinds of
thread is. Two concrete failures, both reachable in production:

1. **A lost registration.** `@@loggers = Hash.new { |h, k| h[k] = [] }`, and `register` is
   `@@loggers[id] << sse`. The default proc is Ruby code, so two students opening the Activity Log
   at the same moment can each build a fresh array and the second assignment wins — the first
   student's stream is registered against an array nobody holds any more, and their log stays empty
   with no error anywhere.
2. **A 500 for whoever registers during a keep-alive sweep.** `start_keep_alive_thread` walks
   `@@loggers.each_key` every 10 seconds. Ruby raises
   `RuntimeError: can't add a new key into hash during iteration` **in the mutating thread**, so
   the cost lands on a request, not on the keep-alive.

Fixed the way Surprise 21 fixed the name generators: a class-level instance variable guarded by a
`Mutex`. `log` and the keep-alive take the lock only long enough to copy the listener array or the
key list — an SSE write goes to a client socket and can block, and holding the registry lock across
it would stall every other student's log. Two examples in `spec/lib/activity_logger_spec.rb` pin
both failures (50 listeners registered from 10 threads; 200 registrations racing 200 keep-alive
sweeps); both fail against the fork's implementation.

Two smaller things went with it: the registry no longer creates an entry for every id merely
_logged_ to (the fork's default proc made `log` a slow memory leak keyed by remote usernames), and
`start_keep_alive_thread` lost its `puts "writing keep-alive"` — a line on stdout every ten seconds
for the life of the process.

`spec/rails_helper.rb` now calls `ActivityLogger.reset` after every example, next to the Redis wipe.
The fork needed the same hook, which is what made this worth looking at.

### 28. The subscriber thread leaks a database connection without the Rails executor

**Assumed:** `config/database.yml`'s pool `+ 1` (Cluster 1) is the whole story for the subscriber
thread's database use.

**Actually:** the `+ 1` covers the _steady state_ but nothing returns the connection. The
`/followers` branch of `ActivityLogAudienceHelper` issues a real query, and a connection leased
inside a hand-rolled `Thread.new` is held by that thread until it dies — which for the subscriber is
"until the Puma worker exits". It is also not safe to autoload from such a thread.

`ActivityLogSubscriber#handle` now wraps each message in `Rails.application.executor.wrap`, which is
the documented idiom for exactly this: it releases the connection when the unit of work ends and
takes the load-interlock share that makes constant lookup safe. `spec/lib/activity_log_pipeline_spec.rb`
asserts the pool's in-use count is unchanged after a followers-expansion event has gone through.

The pool `+ 1` stays: `Redis#subscribe` blocks, so the thread is long-lived either way, and the
executor releasing the connection between messages is belt and braces rather than a replacement.

### 29. The fork's audience spec fabricates an account v4.7.1 will not create

`app/models/account.rb:136` added `validates :followers_url, absence: true` under
`with_options on: :create, if: :local?`. The fork's `activity_log_audience_helper_spec.rb`
fabricates its followers-collection owner as `Fabricate(:account, username: 'bob', followers_url:
'https://other.org/users/bob/followers')` — a **local** account with a remote followers URL, which
now raises `ActiveRecord::RecordInvalid: Followers URL must be blank`. Three examples.

Fixed by adding `domain: 'other.org'`, which is what the fixtures always meant: bob is the remote
account whose followers collection a local student follows. No production impact — the rows in the
real database are remote accounts already.

### 30. Rails 8 rejects a malformed activity body before the inbox controller sees it

**Assumed:** the fork's "does not reject a delivery whose body is not valid JSON" example ports
directly.

**Actually:** `config/initializers/mime_types.rb` registers `application/activity+json` (and
`application/ld+json`) as synonyms of `:json`, so Rails' parameter parsing runs on every federated
POST and raises `JSON::ParserError` **before** `ActivityPub::InboxesController` is reached. The
delivery is rejected by the framework, not by anything in this fork, and no 202 is possible.

The branch that still exists is the one upstream's own `parsed_body` rescue is there for: a body
Rails did not parse, where `parsed_body` returns `nil`. The example now posts without a JSON content
type and asserts both the 202 and `event.data == nil`, and `ActivityLogAudienceHelper` gained a
guard (`return [] unless data.is_a?(Hash)`) so a nil payload resolves to an empty audience instead
of raising in the subscriber. The fork never needed that guard, because its own `Oj.load` raised
first and suppressed the publish entirely.

Worth knowing for Cluster 6 and the Phase 3 smoke test: a student who crafts deliberately broken
JSON in the Activity Workshop gets a 400 from the receiving instance, and **nothing appears in the
Activity Log** — which is a different lesson from the one the fork used to teach.

### 31. `ParamsWrapper` will invent an activity for you, because the controller is called `activity`

**Assumed:** the fork's `activity_controller.rb` is a 28-line pass-through, and the only thing to
re-check about its parameters is whether Rails 8's tightened handling still honours the wildcard
permit.

**Actually:** the wildcard is fine (Surprise 32). What is not fine is the controller's _name_.
`config/initializers/wrap_parameters.rb` is upstream's stock `wrap_parameters format: [:json]`, and
`ActionController::ParamsWrapper` derives the wrapper key from the controller — here, `activity`.
`_wrapper_enabled?` skips wrapping when `request.parameters.key?('activity')`, so the well-formed
request the SPA sends is untouched and the collision is invisible. Omit the `activity` key, though,
and Rails wraps the _remainder of the body_ under it: a JSON `POST {"inbox_url": "…"}` becomes
`params[:activity] == { "inbox_url" => "…" }`, `params.require(:activity)` succeeds, and the
instance signs that object as the student and delivers it. Observed as a 200 where the fork's own
spec asserts 400.

The fork never saw this: its spec posts form-encoded, and wrapping is registered for `:json` only.
The SPA posts `Content-Type: application/json`, so the live path is the one that wraps.

Fixed with `wrap_parameters false` on the controller (see Decisions). Two examples in
`spec/requests/activity_workshop_spec.rb` pin it — a JSON body with no `activity`, and a JSON body
with no `activity` but other keys present.

**Cost:** ~20 minutes, all of it in the failing example. Worth checking on any future fork
controller whose name matches one of its own parameters; `Api::V1::WebfingerController` (Cluster 2)
is safe because its parameter is `value`, not `webfinger`.

### 32. The wildcard permit survives Rails 8 intact — `deep_munge` is what eats a `null`

**Assumed** (plan, Cluster 6): Rails 8 added `params.expect` and tightened parameter handling, so
`params.permit(:inbox_url, activity: {})` has to be re-verified rather than trusted.

**Actually:** verified against actionpack 8.1.3.1 and unchanged. `permit_any_in_parameters` /
`permit_any_in_array` still recurse through nested objects and arrays to any depth, still keep JSON
scalars with their types (integers, booleans, `null` as a hash _value_), and still drop everything
outside the filter list. `params.require` is not deprecated in 8.1 — `expect` was added alongside it
at `strong_parameters.rb:772`, and `require` is still `strong_parameters.rb:519` with no deprecator
call. Ported verbatim.

Two real edges, neither of them the permit:

- **A `null` inside an array does not survive any Rails request.**
  `ActionDispatch::Request::Utils::NoNilParamEncoder` (`perform_deep_munge`, default `true` since
  Rails 4) compacts every array in every request's parameters. `{"to": ["https://…", null]}` arrives
  as a one-element array. A `null` as a hash value is untouched. This is the single shape of
  activity the Workshop cannot deliver verbatim, and it behaved the same way on v4.1.18 — it is a
  documentation gap, not a port regression.
- **A non-object `activity` becomes `{}`.** A bare string or array is not a match for the `{}`
  filter, so permit drops it, `activity_params[:activity]` is `nil`, and `nil.to_h.to_json` is
  `"{}"`. `activity: {}` or `activity: null` raise `ActionController::ParameterMissing` and
  `Api::ErrorHandling` maps that to 400.

Both are pinned in `spec/requests/activity_workshop_spec.rb`.

### 33. The Activity Workshop cannot produce the 400 that Surprise 30 describes

**Assumed** (Surprise 30's closing paragraph): "a student who crafts deliberately broken JSON in the
Activity Workshop gets a 400 from the receiving instance, and nothing appears in the Activity Log."

**Actually: not reachable from the Workshop.** Measured end-to-end, against a signed POST to this
instance's own inbox:

| What the student sends                                          | Inbox response                                                              | Activity Log               |
| --------------------------------------------------------------- | --------------------------------------------------------------------------- | -------------------------- |
| Valid JSON, nonsense ActivityPub (`{"type":"NotARealType", …}`) | **202**                                                                     | full entry, payload intact |
| Byte-level broken JSON, `application/activity+json`             | 400 (`ActionDispatch::Http::Parameters::ParseError`, before the controller) | nothing                    |
| Valid JSON over 1 MB                                            | **413** (`skip_large_payload`, `ActivityPub::Activity::MAX_JSON_SIZE`)      | nothing                    |

The middle row is real but **the Workshop has no way to reach it**, for two independent reasons:

1. The SPA's `onSubmit` does `JSON.stringify({ inbox_url, activity: JSON.parse(activity) })`, so
   text that is not parseable JSON never leaves the browser — the editor's own `JSON.parse` throws
   first.
2. Even bypassing the SPA, `Api::V1::ActivityController` serialises a permitted `Parameters` object
   with `to_json`. The body handed to `ActivityPub::DeliveryWorker` is therefore **always**
   syntactically valid JSON, `"{}"` in the worst case.

So the fork's lesson — "you get a 202 and a log entry" — is **still true for everything the Workshop
can actually send**, and teaching material needs no change on that point. Two things are new and do
need saying:

- **1 MB is now a hard ceiling** on an inbound activity, enforced before anything is logged. A
  student who pastes something enormous gets a silent 413 and an empty log, with no clue why. That
  is the guard the 2026-09-01 JSON-LD DoS release added, and it is worth putting in front of
  students rather than letting them discover it.
- **The 400 is still worth demonstrating** — it is a genuine and newly-framework-level behaviour —
  but it needs a tool that writes a raw request body (`curl --data-binary` with
  `-H 'Content-Type: application/activity+json'`), not the Workshop. The receiving instance rejects
  it in middleware, so no fork code runs and nothing is logged.

Nothing was changed to restore the old behaviour; Surprise 30's fix in Cluster 5 stands.
`retry: 0` (Cluster 5) also means a Workshop delivery that hits a transient error is dropped rather
than retried, so a failure appears in the log exactly once.

### 34. Cluster 6 in numbers

`git grep -n '\bOj\.' -- app lib spec config` now returns **only comments** (plus two binary
fixtures that match by accident). The three sites this cluster owned — `Oj.dump` in the controller,
`Oj.load` twice in the spec — are `to_json` / `JSON.parse`, on Cluster 5's reasoning (Surprise 25):
the fork's `mode: :compat, use_to_json: true` made `Oj.dump` _be_ `to_json`, so the wire format is
unchanged rather than approximated. Surprise 9's repo-wide hazard is closed for `app`/`lib`/`spec`;
the last fork site anywhere is Phase 2's `application_helper.rb`.

`ActivityPub::DeliveryWorker#perform` is `(json, source_account_id, inbox_url, options = {})` —
confirmed by reading `app/workers/activitypub/delivery_worker.rb:29`. The fourth parameter defaults,
so the fork's three-argument `perform_async` is still correct and the worker sees
`bypass_availability` unset. `spec/requests/activity_workshop_spec.rb` asserts the enqueued job has
exactly three arguments, so a future signature change fails loudly here.

Routes went to `config/routes/api.rb` next to Cluster 2's `resource :webfinger` (Surprise 10);
`config/routes.rb` is untouched. The `/activity_workshop` SPA path is Phase 2, alongside
`/web_finger_forge` and `/activity_log`.

Suite: **7722 → 7734**, 12 new examples in one file, no fabricator, nothing newly tagged
`academy: :disabled`.

### 35. The fork's Explorer could not sign anything on v4.7.1 — and the fix is a deletion

**Assumed** (plan, Cluster 7): the Explorer is "raw socket writes and a detached thread; re-verify
under Rack 3". The signing was not called out as a risk at all.

**Actually:** two independent changes under it, and the controller as written raises on every
non-WebFinger fetch:

1. `Account#keypair` changed return type. At v4.1.18 it was
   `OpenSSL::PKey::RSA.new(private_key || public_key)`, so the fork's
   `account.keypair.sign(OpenSSL::Digest.new('SHA256'), signed_string)` worked. At v4.7.1 it is
   `keypair(type: nil)` and returns a **`Keypair` ActiveRecord record**, which has no `#sign`. The
   `OpenSSL` object is one level further down, at `Account#keypair(type: :rsa).keypair`.
2. `db/post_migrate/20260702144128_migrate_local_account_keypairs.rb` moved local keypairs into a
   dedicated `keypairs` table and `Keypair` declares `encrypts :private_key`, so the private key is
   encrypted at rest. Reaching around that to re-implement signing by hand is the wrong direction
   twice over.

**Cost: negative.** `app/lib/request.rb` already does all of it, correctly, and is what the rest of
the codebase signs with. `#signature`, `#signed_headers` and `REQUEST_TARGET` were deleted (~45
lines) rather than ported, and the Explorer gained v4.7's RFC 9421 double-knock for free. What
remains fork-specific is `get_redirect_location` / `follow_redirects` (byte-for-byte the fork's
logic bar the port fix in Surprise 38) and the raw socket write.

The fork's four `#signed_headers` / `#signature` examples became three `#build_request` examples
plus a `#fetch` example that reads the `Signature` header off the request WebMock actually
intercepted, rebuilds the signed string from the `headers=` parameter, and verifies it against
`Account.representative`'s public key. That is a stronger assertion than the fork's, because it
tests the bytes that go on the wire rather than a hash the controller built.

**Also gone: Faraday.** The fork's `require "faraday"` worked only because Elasticsearch and
OpenTelemetry pull it in transitively — it has never been a direct dependency in either version's
`Gemfile`. Nothing in this cluster references it now.

### 36. What `Request` blocks that the fork's Faraday call did not

The Explorer's SSRF is deliberate (`TESTING.md` says so), so every restriction `Request` adds had
to be checked rather than inherited. Three exist; one needed disabling, two are harmless:

| Restriction                                                                                     | Where                                                                                                                | Verdict                                                                                                                                                                                                                |
| ----------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Private / link-local / loopback addresses** — `Mastodon::PrivateNetworkAddressError`          | `Request::Socket.check_private_address`, skipped only in `Rails.env.development?` or for `ALLOWED_PRIVATE_ADDRESSES` | **Disabled** with `allow_local: true`. This is the one that matters: in production it would refuse `http://10.0.0.5/users/alice` and every other lab-network target, which is a large part of what a workshop fetches. |
| **`.onion` / `.i2p`** — `Mastodon::HostValidationError` unless `ALLOW_ACCESS_TO_HIDDEN_SERVICE` | `Request#block_hidden_service?`                                                                                      | Left in place. Faraday could not have reached a hidden service either without a proxy, so nothing is lost.                                                                                                             |
| **Non-http(s) schemes**                                                                         | `HTTP.rb` would fail on them anyway                                                                                  | Turned into an explicit `Request.valid_url?` check before the hijack, so `file:///etc/passwd` is a 422 rather than a raw 500.                                                                                          |

Nothing restricts destination **ports** — neither `Request` nor `HTTP.rb` keeps an allow-list — so
`http://remote.example:8080/actor` is fetched. Confirmed live against a probe server on :4567.

Two things `Request` does that Faraday did not, both benign here: it normalizes the URL through
`Addressable::URI#normalize` before fetching, and it sends `Accept-Encoding: gzip` and inflates the
response (`HTTP.use(:auto_inflate)`), so the student sees the decoded body.

**Not added, on purpose:** a response size cap. `response.body.to_s` reads the whole remote body
into the detached thread, exactly as the fork's Faraday call did. `Request` offers
`body_with_limit` / `truncated_body` at 1 MB, but a silently truncated JSON document is a worse
lesson than a large one, and the endpoint is behind `require_user!`. Recorded here because it is
the one unbounded thing left in this cluster.

### 37. The instance actor's key id is no longer `#main-key`

The fork's spec asserted `keyId == ActivityPub::TagManager.instance.key_uri_for(account)`, which is
`uri_for(account) + '#main-key'`. On v4.7.1 `Account#generate_keys` writes
`keypairs.build(local_fragment: "#rsa-#{SecureRandom.hex(8)}", …)`, and `Keypair#full_uri` — which
is what `CavageSignatureFeature` puts in `keyId` — is `uri_for(account) + local_fragment`. Observed
live: `keyId="http://localhost:3000/actor#rsa-f…"`.

`key_uri_for` is now the **legacy** spelling, reached only through `Keypair.from_legacy_account` for
an account whose keys predate the migration. Both shapes occur in one database after Phase 3, so
nothing may assume either. The spec asserts against `Account.representative.keypair(type: :rsa).full_uri`.

Nothing to fix — `Request` gets this right on its own — but it is one more thing the fork's
hand-rolled signer would have got wrong even after `Account#keypair` was untangled.

### 38. The raw hijacked write still works — and it exposed a fork bug in relative redirects

**Full hijack under Rack 3 / Puma 8 / Rails 8.1 is fine.** `puma-8.0.2/lib/puma/client.rb:142`'s
`full_hijack` still does `env['rack.hijack_io'] ||= @io` _and_ returns it, so both the Rack 3
spelling (use the callable's return value) and the fork's (read `rack.hijack_io` afterwards) work.
`Puma::Response` returns `:async` for a hijacked client, so Rails' own response is discarded and
there is no missing-template noise in the log. Verified end to end against a real dev server:

| Probe                                       | Result                                                          |
| ------------------------------------------- | --------------------------------------------------------------- |
| Instance actor, `application/activity+json` | `200`, correct `Content-Type`, 2971-byte body                   |
| A path that does not exist                  | `404`, `application/json`, `{"error":"Not Found"}`              |
| `.well-known/webfinger`                     | `200`, `application/jrd+json`, **no** `Signature` sent          |
| `302` → `200` across two hops               | `200`, and the probe echoed the second hop's `Signature` header |
| A `302` pointing at itself                  | `302` after `MAX_REDIRECTS`, in 0.08s — not a hang              |
| Missing `url` / `file://`                   | `422` JSON, rendered normally (pre-hijack)                      |
| 20 sequential fetches, dev pool of 6        | 20 × `200`, no connection-pool exhaustion                       |

**The bug the live probe found:** `follow_redirects` built the base for a relative `Location` as
`"#{parsed_url.scheme}://#{parsed_url.host}"` — which **drops the port**. The redirect probe on
`127.0.0.1:4567` sent `Location: /final` and the Explorer went to `127.0.0.1:80`, producing a
hand-written raw 500 with no explanation anywhere. This is a fork bug, not a port regression: the
fork's `URI.parse` line has the same shape, and its spec only ever used a default-port host, so it
passed.

Fixed with `Addressable::URI.parse(url).site` (scheme + authority, so the port survives), and by
resolving each relative location against the URL that _issued_ the redirect rather than against the
one the student typed — which also fixes a chain that crosses hosts. Two examples pin both.

### 39. Cluster 7 in numbers

Suite: **7734 → 7759**, 25 new examples in two files, no fabricator, nothing newly tagged
`academy: :disabled`.

`spec/controllers/api/v1/json_ld_controller_spec.rb` (22) keeps the fork's approach — `#show`
hijacks the socket, so it is unreachable through Rack::Test and the private methods are exercised
directly. It is no longer _only_ that, though: `#fetch` is now covered end to end through WebMock,
which intercepts inside `HTTP::Client#perform`, _after_ http.rb has applied
`CavageSignatureFeature`, so the assertions are made against the real outgoing request.

`spec/requests/activitypub_explorer_spec.rb` (3) is new and covers what a request spec now can:
routing, `require_user!`, and the two pre-hijack URL rejections. That is the whole of `#show` that
does not touch `rack.hijack`. Anything past the hijack still needs a real server — the table in
Surprise 38 is that check, and it should be re-run at the Phase 3 smoke test.

Routes went to `config/routes/api.rb` next to Clusters 2, 5 and 6 (Surprise 10); `config/routes.rb`
is untouched. The `/activitypub_explorer` SPA path is Phase 2. `dist/nginx.conf`'s unbuffered
`location ^~ /api/v1/json_ld` block landed in Cluster 1 and needed nothing here.

### 40. `AccountDeletionWorker` refuses a live account since v4.2 — the fork's scheduler deletes nothing

**Assumed** (plan, Cluster 8): "scheduler + `config/sidekiq.yml` … confirm `Sidekiq::Queue.new('pull').size`
still works on Sidekiq 8." The only risk called out was the queue API. The scheduler's own call —
`AccountDeletionWorker.perform_async(account.id, { 'reserve_username' => false })` — was expected to
port verbatim, and its _signature_ does: `perform(account_id, options = {})`, `options` read through
`with_indifferent_access`, unchanged since v4.1.18.

**Actually:** upstream 4658263b4a ("Fix re-activated accounts being deleted by AccountDeletionWorker",
v4.2.0) added a body the fork has never seen:

```ruby
account = Account.find(account_id)
return unless account.unavailable?   # was `suspended?` until 963354978a
```

`unavailable?` is `deleted? || suspended?`. A freshly generated academy account is neither, so the
ported scheduler would have enqueued five jobs a minute that each found a healthy account and
returned. Nothing raises, nothing logs, `Sidekiq` reports success, and the instance accumulates
actors forever — the exact failure this cluster exists to prevent, arriving silently. Every caller
in v4.7.1 marks the account first (`Form::AccountBatch#reject_account` and
`ResolveAccountService#queue_deletion!` use `suspend!`, `Settings::DeletesController` uses
`mark_deleted!`); the fork's scheduler was written before the guard existed and so does not.

**Cost:** one line in the scheduler and the reasoning behind which marker to use (Decisions). Found
by reading the worker rather than assuming it, which the cluster brief insisted on. Mutation-tested:
removing `mark_deleted!` fails four of the eleven examples, including both `:inline_jobs` ones that
assert the account is actually gone.

### 41. `Sidekiq::Queue#size` is unchanged on Sidekiq 8 — and `Sidekiq::Testing` does not fake it

**Assumed:** `Sidekiq::Queue.new('pull').size` is a version-sensitive API across 6.x → 8.

**Actually:** it is untouched. In sidekiq 8.1.6 `Sidekiq::Queue#initialize(name = "default")` sets
`@rname = "queue:#{name}"` and `#size` is `Sidekiq.redis { |con| con.llen(@rname) }`. Confirmed live
against the running instance: `Sidekiq::Queue.new('pull').size` → `0`, Sidekiq 8.1.6 on
`redis://redis:6379/0`.

The more useful half: `sidekiq/test_api.rb` replaces the _client_ (`atomic_push`) and adds an
in-memory `Sidekiq::Queues`, but it does not touch `Sidekiq::Queue`. So under
`Sidekiq.testing!(:fake)` a job goes to memory while `Sidekiq::Queue.new('pull').size` still issues a
real `LLEN queue:pull` against the test Redis — which is empty. The spec therefore exercises the real
Sidekiq 8 API on the path that matters and stubs only the backed-up branch, where a stub is the only
way to produce a depth above `MAX_PULL_SIZE`.

**Cost:** none. The one thing the plan flagged as a risk was not one.

### 42. The default account fabricator generates usernames with underscores in them

`spec/fabricators/account_fabricator.rb` seeds `username` from
`Faker::Internet.user_name(separators: %w(_))`, so a bare `Fabricate(:account)` is usually something
like `kathe_hoeger12` — indistinguishable, to this scheduler, from an academy signup. It is harmless
today (nothing else invokes the scheduler, and a fabricated account's `created_at` is `now`, outside
the one-day window), but it means the cleanup spec cannot rely on the default: every account in it
names its username explicitly, on one side of the heuristic or the other.

The fork's own control, `alice`, happens to be safe for exactly this reason.

### 43. Cluster 8 in numbers

Suite: **7762 → 7773**, 11 new examples in one file, no fabricator, nothing newly tagged
`academy: :disabled`.

`config/sidekiq.yml` re-nested as the plan predicted: the `:schedule:` map now sits under
`:scheduler:` (alongside `:listened_queues_only:`) and is indented two levels deeper. The entry went
in next to `suspended_user_cleanup_scheduler`, the upstream job this one is modelled on, at the new
level. It has no spec coverage — Risk 2's silent-config-loss category — so it was checked by eye
against its neighbours.

Three things were verified by mutation rather than assertion, because each of the fork's own bug
commits is a case where the spec passing meant nothing:

| Mutation                                           | Examples that fail                                                     |
| -------------------------------------------------- | ---------------------------------------------------------------------- |
| `'%\_%'` → `'%_%'` (drop the LIKE escape)          | 2 — `alice` is marked, and `alice` is deleted                          |
| remove `account.mark_deleted!`                     | 4 — nothing is ever deleted (Surprise 40)                              |
| `web_finger_overrides` FK → no `ON DELETE CASCADE` | 1 — `PG::ForeignKeyViolation` in `DeleteAccountService#purge_content!` |

The last one is Cluster 2's cascade earning its keep: `Account` declares no association to
`WebFingerOverride` and `DeleteAccountService` never mentions the table, so the database-level
cascade is the _only_ thing that lets a student who used the WebFinger Forge be cleaned up a day
later. Restored afterwards; the constraint in `db/schema.rb` is unchanged.
