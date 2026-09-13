// FORK PATCH (activitypub-academy): route the Ruby linters through the devcontainer.
//
// This host has no Ruby >= 3.3 -- v4.7.1 pins 4.0.6 and rbenv's ruby-build definitions
// stop at 3.2.2 (see TESTING.md). `bin/rubocop` and `bin/haml-lint` therefore cannot run
// here at all, and because lint-staged reverts the commit when a task fails, the
// pre-commit hook made *every* commit impossible rather than just skipping Ruby linting.
//
// Only the Ruby tasks are delegated. lint-staged itself, and the JS/CSS tooling, stay on
// the host on purpose: lint-staged runs `git stash` and rewrites the index, and the
// container runs as root against a uid-1000 checkout, so letting it touch .git would
// leave root-owned objects that the host's git could no longer write.
//
// When re-deriving this file at the next upgrade, the upstream version is the plain
// string form: 'Gemfile|*.{rb,ruby,ru,rake}': 'bin/rubocop --force-exclusion -a'.

const path = require('node:path');

const CONTAINER_ROOT = '/workspaces/mastodon';
const COMPOSE = [
  'docker compose',
  '-f .devcontainer/compose.yaml',
  '-f docker-compose.test.yml',
  'exec -T app bash -lc',
].join(' ');

// lint-staged hands tasks absolute host paths; the container sees the same files under
// a different root.
const toContainerPath = (file) =>
  path.posix.join(CONTAINER_ROOT, path.relative(__dirname, file));

const inContainer = (command, files) => {
  const args = files.map((f) => `'${toContainerPath(f)}'`).join(' ');
  return `${COMPOSE} ${JSON.stringify(`${command} ${args}`)}`;
};

const config = {
  '*': 'oxfmt --no-error-on-unmatched-pattern',
  'Gemfile|*.{rb,ruby,ru,rake}': (files) =>
    inContainer('bin/rubocop --force-exclusion -a', files),
  '*.{js,jsx,ts,tsx}': 'eslint --fix',
  '*.{css,scss}': 'stylelint --fix',
  '*.haml': (files) => inContainer('bin/haml-lint -a', files),
  '**/*.ts?(x)': () => 'yarn tsc -p tsconfig.json --noEmit',
  'app/javascript/**/*.{js,jsx,ts,tsx}': () => [
    `yarn i18n:extract`,
    'git diff --exit-code app/javascript/mastodon/locales/en.json',
  ],
};

module.exports = config;
