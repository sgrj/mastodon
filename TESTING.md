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

Currently tagged:

| Example                                                                                                           | Reason                                                                                                                                                                                                                                                                         |
| ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `spec/serializers/activitypub/actor_serializer_spec.rb` — `#type with an application actor serializes as Service` | The fork serializes the stored `actor_type` verbatim, so a non-instance account whose `actor_type` is `Application` is published as `Application`. Upstream collapses it into `Service` via `bot?`. The sibling example asserting the fork's behaviour sits directly below it. |

## After porting a cluster

1. That cluster's own specs.
2. The full suite — compare against the baseline above. Anything new is ours.
3. Config-only clusters (`puma.rb`, `sidekiq.yml`, `database.yml`, `nginx.conf`) have no
   spec coverage and fail silently: the app boots and the Activity Log simply goes quiet.
   Check those by hand.
