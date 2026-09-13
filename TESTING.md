# Testing

## Running the suite

```sh
bin/rspec-local                                   # everything
bin/rspec-local spec/requests/                    # a directory
bin/rspec-local spec/models/account_spec.rb:42    # one example
bin/rspec-local spec/lib/ --seed 1234
```

Everything runs inside the `app` container from `.devcontainer/compose.yaml`. The host
no longer has a usable toolchain for this: v4.7.1 needs Ruby >= 3.3 (`.ruby-version`
pins 4.0.6) and Node 24.19, while this machine has Ruby 3.0.6 and Node 22, and rbenv's
ruby-build definitions stop at 3.2.2.

`bin/rspec-local` starts `app`, `db` and `redis-test`, waits for them to report healthy,
and hands every argument through to `bin/rspec`. First run builds the image, which takes
a while; afterwards it is instant.

Requires **docker compose v2** (`sudo apt-get install docker-compose-v2`). The
devcontainer compose files have no `version:` key, which compose v1 cannot parse.

### After a devcontainer image rebuild

The container runs as root against a checkout owned by uid 1000 on the host, so git
inside it refuses the repo as "dubious ownership" and anything that shells out to git
fails. Re-run this after every image rebuild:

```sh
docker compose -f .devcontainer/compose.yaml exec app \
  git config --global --add safe.directory /workspaces/mastodon
```

The same root-versus-uid-1000 split bites the frontend toolchain. `yarn typecheck` inside the
container creates `tmp/cache/tsconfig.tsbuildinfo` owned by root, and the pre-commit hook runs
`yarn tsc -p tsconfig.json --noEmit` on the **host** -- which then fails with
`TS5033: Could not write file ... permission denied` and makes every commit that stages a `.ts` or
`.tsx` file impossible. Hand it back once:

```sh
docker compose -f .devcontainer/compose.yaml exec app \
  chown -R 1000:1000 /workspaces/mastodon/tmp/cache
```

tsc truncates the file in place rather than recreating it, so once it belongs to the host user it
stays there. Do not use `--no-verify`.

### After adding a frontend asset

`config/vite.yml`'s `test:` block sets `auto_build: true`, but that only triggers when the
manifest file is **missing**. An entry that is missing from an existing manifest raises
`Vite::Manifest::MissingEntryError` and the suite simply fails. After adding or renaming anything
under `app/javascript/{fonts,icons,images}`, rebuild once by hand:

```sh
docker compose -f .devcontainer/compose.yaml exec app bash -lc 'yarn build:production'
```

`public/packs/` is gitignored, so this is a local step.

### Parallel runs

The full suite serially is slow. Upstream's CI uses flatware, and so can we:

```sh
docker compose -f .devcontainer/compose.yaml -f docker-compose.test.yml \
  exec -T -e RAILS_ENV=test app bash -lc \
  'env -u LOCAL_DOMAIN -u LIBRE_TRANSLATE_ENDPOINT -u ES_ENABLED -u ES_HOST \
       -u ES_PORT -u REDIS_HOST -u REDIS_PORT \
   bash -c "bin/flatware fan -w 6 bin/rails db:test:prepare && bin/flatware rspec -w 6"'
```

Each worker gets its own database (`mastodon_test1`…) and its own Redis db
(`TEST_ENV_NUMBER + 1`).

### Elasticsearch and LibreTranslate

Deliberately not started. `:search` specs are excluded by default, along with `:js` and
`:streaming`. To run search specs, bring up `es` and drop `-u ES_ENABLED -u ES_HOST`.

## Baseline

**v4.7.1 unmodified: 7646 examples, 0 failures, 2 pending.**

After clusters 1–4: **7662 examples, 0 failures, 2 pending.** Cluster 4 adds 19 examples and
excludes 29 upstream ones (7672 + 19 − 29), so the run total goes _down_. See Surprise 13 in
`PORTING.md`: each new fabricator silently adds one example on top of the specs you write.

After cluster 5: **7722 examples, 0 failures, 2 pending.** The Activity Log pipeline adds 60: 42 in
six new files, plus 14 in `spec/workers/activitypub/delivery_worker_spec.rb` and 4 in
`spec/requests/activitypub/inboxes_spec.rb`. It tags nothing new as `academy: :disabled` and adds no
fabricator, so the arithmetic is unusually honest this time. The two pendings are upstream's
(`spec/lib/activitypub/object_integrity_proof_spec.rb`, "waiting for ubuntu-26.04 runners").

After cluster 6: **7734 examples, 0 failures, 2 pending.** 12 new examples in
`spec/requests/activity_workshop_spec.rb`, no fabricator, nothing newly tagged.

After cluster 7: **7759 examples, 0 failures, 2 pending.** The ActivityPub Explorer adds 25: 22 in
`spec/controllers/api/v1/json_ld_controller_spec.rb` and 3 in
`spec/requests/activitypub_explorer_spec.rb`. No fabricator, nothing newly tagged.

The follow-up commit that caps relayed bodies at 1 MB adds 3 more, so the branch sat at **7762
examples, 0 failures, 2 pending** before cluster 8.

After cluster 8: **7773 examples, 0 failures, 2 pending.** Old account cleanup adds 11, all in
`spec/workers/scheduler/old_account_cleanup_scheduler_spec.rb`. No fabricator, nothing newly tagged.
Six of them run with `:inline_jobs`, so `AccountDeletionWorker` and `DeleteAccountService` actually
execute and the accounts really are gone — which is the only way the spec can see the `unavailable?`
guard described in Surprise 40, or the `web_finger_overrides` cascade from Cluster 2.

After cluster 9: **7773 examples, 0 failures, 2 pending** — unchanged. Branding & OG edits four
presentation files and swaps one binary; it adds no examples, no fabricator, and nothing newly
tagged. `spec/presenters/instance_presenter_spec.rb` needed no change at all: v4.7.1 already
covers `#source_url` with and without `GITHUB_REPOSITORY` (PORTING.md, Surprise 44).

**Phase 1 is complete at this number.** See "Phase 1 complete" at the end of `PORTING.md`.

Phase 2a (frontend: `activitypub-visualization` 2.0.0, the academy stylesheets, the Activity Log)
leaves it at **7773 examples, 0 failures, 2 pending** — unchanged. Nothing under `app/javascript`
has Ruby coverage, so a frontend cluster that moves this number has broken something. The frontend
gates are separate and all four must pass:

```sh
docker compose -f .devcontainer/compose.yaml exec app bash -lc \
  'yarn build:production && yarn typecheck && yarn lint:js'
npx stylelint "app/javascript/styles/**/*.scss"   # see below -- not `yarn lint:css`
```

`yarn lint:css` reports ~2,500 errors on this checkout that have nothing to do with the fork: they
are all in `foo/default-90ec0bff.chunk.css`, a stray untracked file at the repo root that
`stylelint.config.js`'s `ignoreFiles` does not cover. Scope the glob to
`app/javascript/styles/**/*.scss` to get a usable answer.

Note also that **`.jsx` files are not linted** — `eslint.config.mjs` has no `files` glob that
matches them, so ESLint 9 flat config skips them with "File ignored because no matching
configuration was supplied" (PORTING.md, Surprise 50). Prefer `.ts`/`.tsx` for new frontend code.

Re-establish this whenever the base version changes. Any failure after a cluster lands is
ours — that unambiguity is the whole point of keeping the baseline green.

## The devcontainer environment trap

`.devcontainer/compose.yaml` sets variables on the `app` service, and **dotenv does not
override a variable that is already set**, so `.env.test` is silently ignored for those
names. On an unmodified v4.7.1 this fails 12 specs:

| Variable                    | Container value              | What breaks                                                                                                                                                                                                            |
| --------------------------- | ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `LOCAL_DOMAIN`              | `localhost:3000`             | `.env.test` wants `cb6e6126.ngrok.io`. Local URLs stop being recognised as local — 4 "tagged objects" failures in `PostStatusService`, `ProcessLinksService`, `UpdateStatusService`, plus 2 in `ResolveAccountService` |
| `REDIS_HOST` / `REDIS_PORT` | `redis` / `6379`             | `redis_configuration_spec` asserts the `localhost:6379` defaults — 4 failures                                                                                                                                          |
| `LIBRE_TRANSLATE_ENDPOINT`  | `http://libretranslate:5000` | The "no translation service configured" branch becomes unreachable, so the spec attempts a real HTTP call and WebMock blocks it                                                                                        |
| `ES_ENABLED` / `ES_HOST`    | `true` / `es`                | Points at a service we do not start                                                                                                                                                                                    |

`bin/rspec-local` clears all of these. Do not run `bin/rspec` directly inside the
container unless you clear them yourself.

### `RAILS_ENV` is the dangerous one

The container sets `RAILS_ENV=development`, and `spec/rails_helper.rb:3` is
`ENV['RAILS_ENV'] ||= 'test'` — `||=` cannot override it. The visible symptom is
harmless (`uninitialized constant Shoulda`, because `Bundler.require` loads the wrong
groups). The invisible one is not:

`spec/rails_helper.rb` runs `redis.del(redis.keys)` after **every example**. Upstream
contains that by choosing db `TEST_ENV_NUMBER + 1` whenever `Rails.env.test?`, leaving
development on db 0 — but that is conditional on the environment. Outside test, the wipe
targets development's Redis.

Three things guard this:

1. `bin/rspec-local` passes `RAILS_ENV=test` explicitly and **asserts it took effect** in
   the same shell that execs rspec.
2. `docker-compose.test.yml` gives tests `redis-test`, a separate instance in the app
   container's network namespace. `bin/dev` keeps the base `redis` service, so the two
   never share data.
3. **Never set `REDIS_URL`.** `lib/mastodon/redis_configuration.rb` returns early on a
   URL and discards the computed db, defeating the separation in (2).

> The fork's pre-4.7 wrapper solved this by putting the test Redis on port 6380, because
> v4.1.18 had no test/dev separation at all. That offset is obsolete — but the hazard is
> not, it just arrives through `RAILS_ENV` now instead of through the port.

### Why `docker-compose.test.yml` exists

`redis_configuration_spec` asserts the default `redis://localhost:6379/0` when no
`REDIS_` variables are set. Upstream CI satisfies this because GitHub Actions services
answer on localhost. Here Redis is a separate host, so `REDIS_HOST` must be set — which
fails those specs. Unsetting it instead breaks every spec that touches Redis.

The override resolves it by giving the app container a Redis that genuinely answers on
its own localhost (`network_mode: service:app`). It is additive rather than an override
of the base `redis` service, because compose refuses to combine `network_mode:` with the
`networks:` that service already declares — and staying additive keeps `.devcontainer/`
untouched, so there is nothing extra to re-port at the next upgrade.

## Exit codes lie

Three times during the 4.7.1 port, `rspec` exited **0** having run nothing:

- the `RAILS_ENV` problem above produced `0 examples, 1 error occurred outside of examples`
- a bug in `bin/rspec-local` (`exec` bypasses shell functions and found ImageMagick's
  `compose` binary in `PATH`) meant the command never reached rspec
- a second bug in `bin/rspec-local`: `printf '%q ' "$@"` with **no** arguments still runs
  the format once and yields a literal `''`, which rspec takes as a path argument. The
  bare `bin/rspec-local` — the documented "run everything" invocation — matched nothing
  and reported `0 examples, 1 error occurred outside of examples`, exit 0. Fixed with a
  `$#` guard; every earlier green run had passed an explicit path.

Check the example count, not the status.

## Fork-divergence convention

Upstream examples that the academy's features intentionally break are tagged
`academy: :disabled` with a `reason:`, and excluded by default — the same mechanism
upstream uses for `:js`, `:search` and `:streaming`.

```sh
ACADEMY_SHOW_DISABLED=1 bin/rspec-local --tag academy:disabled
```

`bin/rspec-local` forwards `ACADEMY_SHOW_DISABLED` into the container; nothing else
does, so `docker compose exec` invocations need `-e ACADEMY_SHOW_DISABLED=1` of their own.

The plan expected this to arrive with the academy signup cluster (4). It was needed one
cluster early, in **Cluster 3**, and lives in `spec/rails_helper.rb` next to upstream's
own exclusions.

Currently tagged — **33 examples in 11 files.** Every tag carries a `reason:`; run the command
above to read them.

The command reports **30**, not 33: three of the tagged examples also carry `:js` or
`:streaming`, and `spec/rails_helper.rb` excludes those independently of
`ACADEMY_SHOW_DISABLED`. They are the JS-app sign-out in `spec/system/log_out_spec.rb`, the
landing-page redirect in `spec/system/home_spec.rb`, and all of `spec/system/unlogged_spec.rb`.

| File                                                     | N   | Cluster | What diverges                                                                                                                                                                             |
| -------------------------------------------------------- | --- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `spec/serializers/activitypub/actor_serializer_spec.rb`  | 1   | 3       | The fork serializes the stored `actor_type` verbatim, so an `Application` account is published as `Application`; upstream collapses it into `Service` via `bot?`. Sibling directly below. |
| `spec/system/auth/registrations_spec.rb`                 | 11  | 4       | Tagged at the `RSpec.describe` level: the whole file drives the multi-field sign-up form the academy replaces with one button.                                                            |
| `spec/system/settings/migrations_spec.rb`                | 4   | 4       | The account-move challenge field is gone. Sibling: "updates moved to account without asking for a challenge".                                                                             |
| `spec/controllers/auth/registrations_controller_spec.rb` | 4   | 4       | `auth_setup_path` redirect, lookup by submitted e-mail, username collision.                                                                                                               |
| `spec/controllers/auth/sessions_controller_spec.rb`      | 3   | 4       | Sign-out goes to `/auth/sign_up`.                                                                                                                                                         |
| `spec/requests/log_out_spec.rb`                          | 2   | 4       | Sign-out goes to `/auth/sign_up`. Siblings for both HTML and JSON.                                                                                                                        |
| `spec/system/log_out_spec.rb`                            | 2   | 4       | Sign-out goes to `/auth/sign_up` (one is `:js`).                                                                                                                                          |
| `spec/system/settings/migration/redirects_spec.rb`       | 2   | 4       | The redirect challenge field is gone. Sibling: "creates a redirect without a challenge".                                                                                                  |
| `spec/system/home_spec.rb`                               | 2   | 4       | Anonymous `/` redirects to sign-up (one is `:js`, for the landing-page setting, which only the JS app applies). Sibling directly below.                                                   |
| `spec/requests/content_security_policy_spec.rb`          | 1   | 4       | `GET /` no longer renders a view, so the app layout never adds its inline-script `sha256-` to `script-src`. Sibling asserts the same headers on `/auth/sign_up`.                          |
| `spec/system/unlogged_spec.rb`                           | 1   | 4       | Anonymous browsing. `:js, :streaming`, so excluded by default anyway — tagged because it genuinely breaks.                                                                                |

`spec/requests/academy_signup_spec.rb` is the untagged counterpart for the whole sign-up flow, so
the registration files get no sibling of their own.

## After porting a cluster

1. That cluster's own specs.
2. The full suite — compare against the baseline above. Anything new is ours.
3. Config-only clusters (`puma.rb`, `sidekiq.yml`, `database.yml`, `nginx.conf`) have no
   spec coverage and fail silently: the app boots and the Activity Log simply goes quiet.
   Check those by hand.

## The Activity Log specs

`spec/lib/activity_log_pipeline_spec.rb` is the only test that exercises the whole chain, and it
needs a **real Redis**: it starts an `ActivityLogSubscriber` on its own thread and pushes probe
events through `PUBLISH`/`SUBSCRIBE` until one comes out the far end. `bin/rspec-local` already
brings up `redis-test`, so it works out of the box — but it will hang for 15 seconds and then fail
with "the Activity Log pipeline never came up" if Redis is missing, rather than erroring cleanly.

It deliberately avoids the database-backed `/followers` branch of audience resolution: the
subscriber runs on its own thread, so it has its own connection and cannot see rows the example has
not committed. That branch is covered in `spec/lib/activity_log_audience_helper_spec.rb`.

`config/puma.rb` still has no spec coverage. To check the hook by hand:

```sh
docker compose -f .devcontainer/compose.yaml exec app bash -lc \
  'bundle exec ruby -e "require %q(puma); require %q(puma/configuration)
     c = Puma::Configuration.new({ config_files: [%q(config/puma.rb)] }); c.load; c.clamp
     puts c.final_options[:before_worker_boot].size"'
```

One hook, and no Puma deprecation warning (`on_worker_boot` is only a deprecated alias in Puma 8 —
see Surprise 26).

## Deliberately unrestricted

Each of these is the point of the feature it belongs to, not an oversight:

- **`GET /api/v1/json_ld` fetches arbitrary URLs signed with the instance actor's key.** That is
  the ActivityPub Explorer. It is an SSRF by design: `allow_local: true` is passed to `Request` on
  purpose so that private and loopback addresses stay reachable, because a workshop's targets live
  on the lab network. It is behind `require_user!` and nothing else. Do not add a host allow-list
  without removing the exercise first. See Decisions and Surprise 36 in `PORTING.md`.
- **`POST /api/v1/activity` delivers arbitrary activities to arbitrary inboxes,** signed as the
  student, with no validation of the activity whatsoever. That is the Activity Workshop.
- **`ActivityPub::DeliveryWorker` uses `retry: 0`,** so a failure appears in the Activity Log once,
  immediately, instead of being retried out of sight for days.

Two endpoints hijack the Rack socket and answer from a bare thread, so they cannot be driven
through Rack::Test end to end:

- `Api::V1::ActivityLogController#show` — the spec invokes the returned `rack.hijack` proc itself
  and asserts the SSE is registered.
- `Api::V1::JsonLdController#show` — a _full_ hijack, so there is no proc to invoke. Its redirect
  following, request building and signing are exercised directly, the reachable part (routing,
  authentication, URL validation) has a request spec, and the raw socket write is checked by hand
  against a real Puma. The probe table is Surprise 38 in `PORTING.md`; re-run it at the Phase 3
  smoke test.
