# Porting activitypub-academy onto v4.7.1

Base: `v4.7.1`. This branch was cut from the tag, not from `activitypub-academy`.

**The fork spec is a git command, not a document.** For any cluster:

```sh
git diff v4.1.18..activitypub-academy -- <cluster paths>   # what the cluster must do
git diff v4.7.1..HEAD                -- <cluster paths>   # what we have built
```

A cluster is done when the second reproduces the *intent* of the first and its specs pass.
No session needs to remember anything — re-derive from those two commands.

Full plan: `~/.claude/plans/eventual-whistling-wirth.md`

## Session start

1. `cat PORTING.md`
2. `git log --oneline v4.7.1..HEAD`
3. `git diff v4.1.18..activitypub-academy -- <today's cluster paths>`

One cluster per session, one commit per cluster. Update this file before stopping.

## Status

- [ ] Phase 0 — dev loop green on unmodified v4.7.1 + Rack-hijack SSE verified
- [ ] 1 — Ops & config
- [ ] 2 — WebFingerOverride
- [ ] 3 — Actor type (backend half only)
- [ ] 4 — Academy signup  ← **must set `id_scheme: :username_ap_id`**
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

**Actually:** the rationale does *not* stand. In v4.1.18, `app/lib/redis_configuration.rb` used
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

**Cost:** simplifies Phase 0 — `docker-compose.test.yml` and most of `bin/rspec-local` are obsolete;
the wrapper becomes a thin `docker compose exec app bin/rspec`.

### 2. `--format Fuubar` is a non-issue

The plan said to remove it from `.rspec`. We build on upstream's `.rspec` (already just `--color`
and `--require spec_helper`), so there is nothing to remove — simply don't port the fork's line.
`fuubar` is absent from v4.7.1's Gemfile.
