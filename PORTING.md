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
- [ ] 1 — Ops & config
- [ ] 2 — WebFingerOverride
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
- **`activitypub-visualization` 2.0.0** (React 19, React as a webpack external) was published
  2026-09-08 and verified on the Hugo blog. Phase 2 bumps the pin from 1.5.1.

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
example count, never the status.

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
