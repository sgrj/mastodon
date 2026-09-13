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
- [ ] 3 — Actor type (backend half only)
- [ ] 4 — Academy signup ← **must set `id_scheme: :username_ap_id`**
- [ ] 5 — Activity Log pipeline
- [ ] 6 — Activity Workshop
- [ ] 7 — ActivityPub Explorer
- [ ] 8 — Old account cleanup
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
- **`activitypub-visualization` 2.0.0** (React 19, React as a webpack external) was published
  2026-09-08 and verified on the Hugo blog. Phase 2 bumps the pin from 1.5.1.
- **Mail delivery is configured by environment, not by patching `config/environments/`.**
  The fork forced `config.action_mailer.delivery_method = :file` in both
  `development.rb` and `production.rb`. Upstream v4.7.1 reads it from
  `config/email.yml` (`delivery_method: <%= ENV.fetch('SMTP_DELIVERY_METHOD', 'smtp') %>`)
  via `config.x.email.delivery_method`, so **set `SMTP_DELIVERY_METHOD=file` in the
  production environment** and carry no patch. Neither environment file is touched by
  this fork any more. Caveat in Surprise 6: this covers production only.

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
`/ap/accounts/<id>` URLs), `check_account_suspension` moved to `permanently_unavailable?`, and
`gone` moved and gained an `expires_in`. So a **patch-shaped** apply would still have conflicted
even though the hunk itself is clean. Hand-port, as the method says.

Two follow-ups checked while here:

- **`WebfingerSerializer` diverges from what a stored override mirrors,** as the plan warned. It
  gained the FEP-3b86 `Create` / `Object` link templates, and `self` / `aliases` hrefs now come
  from `ActivityPub::TagManager.instance.uri_for`. Under v4.7's default `id_scheme:
numeric_ap_id` that href is `https://host/ap/accounts/<id>`, **not** `https://host/users/<name>`
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
