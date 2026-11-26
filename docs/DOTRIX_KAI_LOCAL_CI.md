# Local CI while GitHub Actions is unavailable

GitHub Actions couldn't run for this fork while it was private, since private repositories use the account's paid minutes and none were left; Dotrix, which is public, ran again first. This repository was made public on 2026-11-19, so hosted CI should run on its pull requests and on `main` again, and later commits are checked there. Until then, each push was checked first by running the CI jobs locally, and the results are recorded here per commit. This doesn't replace hosted CI: macOS, Linux arm64, and the jobs that need artifacts from every platform still need it, and hosted CI should run on these commits once it is available. **R7.3, R7.5, R7.6.**

## How the jobs were run

A clean clone of the exact commit, as an unprivileged user, on Linux x64 (glibc), in a disposable container. The commands come from `.github/workflows/ci.yml`. Four conditions matter, because breaking any of them produced failures that hosted CI would not:

- **Not root.** Root ignores file modes, so tests of read-only files and private folders fail.
- **`umask 022`**, as on hosted runners. With `002`, the `~/.fx` folders tests create are group-writable, fx warns about them on stderr, and tests that expect empty stderr fail.
- **A clean `/tmp`.** Tests share fixed paths such as `/tmp/.fx`, `/tmp/fx-recordings`, and `/tmp/fx-command-output`. Folders left there by a run as another user make the next user's runs fail.
- **The workflow's build flags.** The Linux addon is built with `-Dtarget=x86_64-linux-gnu.2.34 -Dcpu=baseline`, or the ABI check refuses its glibc requirement. The SDK lanes need the WASM surfaces built first.

Toolchain: Zig 0.17.0 (the workflows' pin), Bun 1.4.4 and Node 22.23.5 (the workflows use Bun 1.4.2 and Node 24), Java 21 with `tla2tools.jar` v1.7.4 (checksum verified), tmux, zsh, and fish.

## kai-runtime `fda214c4`

| Job | Steps | Result |
| --- | --- | --- |
| Build & Test | `zig fmt --check src/`, PGSO corpus and its tests, public surface, the agents, compactor, indexer, and recovery boundaries, CLI shape, CI script tests | Passed |
| Build & Test, model checks | Request recovery, empty-reply nudge, connection open, session titles; recovery, connection-open, agent-runtime, and malformed tool-call walks | Passed |
| Build & Test, unit tests | `zig build test -Doptimize=ReleaseSafe` with `FX_TEST_SHELL_PARITY_ALL_SHELLS=1` | 11,254 passed, 22 skipped, 4 failed; see below |
| Build fx (ReleaseSafe) | `-Dcpu=baseline` build, `scripts/smoke-binary.sh` | Passed |
| SDK build (N-API, linux-x64) | Addon for glibc 2.34, Linux ABI check | Passed |
| SDK build (WASM) | Core and term surfaces, ReleaseSmall | Built (not shrunk with `wasm-opt`) |
| SDK (Node + N-API) | `test:node-napi`, minimal native integrations, durable sessions on N-API | Passed |
| SDK (Bun) | N-API lane, durable and core suites, journal, tool contract, host tools, cancellation, MCP and skills adapters (native) | Passed |
| Shellcheck | `bash -n` and `shellcheck` on the listed scripts | Passed |
| E2E | The whole deterministic corpus through `ci-run-files.sh`, in two local shards | 82 files: 73 passed, 4 passed only on retry (`mcp-http`, `mcp-verbs`, `tui-composer-edit-contracts`, `tui-resize`, which CI reports as warnings), 5 failed; see below |
| TLA+ MCP, transcript window, subagent | As in the workflow | Passed in the `ac077e2f` pass below (no change to these models between the two commits) |

The four unit-test failures are `core.cli.doctor_probes` (a child killed with its group at the deadline), `core.execution.command_runner` (a timeout terminates the foreground process group's descendants), and two `mcp.io.process` tests (stopping or deinitializing a server signals its whole process group). All four signal a process group. They failed the same way, as root, on the earlier commit `5cb37e3a`, which has neither this change nor any change to those modules. They fail in this container because its PID 1 (`process_api`) doesn't reap orphaned processes: a process a group stop killed stays a zombie that still answers `kill(pid, 0)`, so the test sees it running. A direct check showed an orphaned, killed grandchild left in state `Z`, and gone when run under `tini -s`, which reaps like a normal init. Hosted runners reap orphans. The E2E terminal-tool failures have the same cause. Re-running these tests under `tini -s` is pending.

Of the 5 E2E files that failed after their retry, `tui-terminal-tool` passed (19 of 19) when rerun under `tini -s` with Bun 1.4.2, the workflow's pin: its failures were the zombie processes above. The other four (`gateway-stream-lifecycle`, 1 test; `review-model-override`, 1 test, `ERR_BODY_ALREADY_USED` in the test's fake server; `tui-command-permissions`, 1 test; `tui-decision-prompts`, the Herdr cases, `write EPIPE`) failed the same way under those conditions, and identically with the published fx 0.0.17 release binary (checksum verified) in place of this build. They don't come from this branch; hosted CI must confirm whether they fail there too.

Not run locally: macOS arm64 and every macOS job, Linux arm64, the SDK package guards (they need the addon for all four platforms), the WASM and browser lanes that need JSPI or Chrome (`sdk-node-wasm`, `sdk-browser-wasm`), live model and live network E2E, and the binary-size, benchmark, and nightly fuzz workflows.

## Dotrix `5cdca6b` and `d9a877c`

Run from the working checkout with local Postgres 16 and pgvector, and Node 22 (the workflow uses Node 24).

| Job | Result |
| --- | --- |
| Guards: `pnpm format:check`, ESLint, Ruff, Python and JavaScript boundaries, script tests | Passed; ESLint has 3 warnings, in web files this branch doesn't touch |
| Python: `uv run pytest` for the engine, CLI, and backend, the fx handoff test, `alembic upgrade head` and `alembic check` | 1,642 passed, 146 skipped; no migration needed |
| CLI install: `uv tool install ./apps/cli`, `dotrix --help`, `dotrix whoami` | Passed |
| Contract: OpenAPI export and generated client unchanged | Passed |
| Node: build, typecheck, and tests for `@dotrix/desktop` and its dependencies, `knip` | Passed |
| Browser tests: `pnpm --filter @dotrix/web e2e` | 156 passed, 9 skipped, 1 failed on the first run (a navigation abort in `auth.spec.ts`); 157 passed on the second |
| fx Chat suites on the Kai runtime build (`d9a877c`) | 158 passed, 2 skipped (paid live-model tests); the same on the 0.0.16 host |

Not run locally: the Windows desktop build and the release workflows.

## kai-runtime `ac077e2f` (`max_subagents`) and `3a997576` (changelog)

Pushed while this pass was running, at the session's request; every step then passed. Run as before, plus a reaping init (`tini -s`) for the unit suite and Bun 1.4.2. `3a997576` changes only `CHANGELOG.md` and `AGENTS.md`.

| Step | Result |
| --- | --- |
| Format, CLI shape, PGSO corpus, public surface, boundaries | Passed |
| Unit tests (`zig build test -Doptimize=ReleaseSafe` under `tini -s`) | Passed, with no failures: the four process-group tests that fail without a reaping init pass |
| Build (`-Dcpu=baseline`), `scripts/smoke-binary.sh` | Passed |
| TLA+ subagent (stop-message, steer-queue, main-mail, quiet-relay, session write and live models, and their drivers) | Passed |
| TLA+ MCP (model, MCP host, drivers) | Passed |
| TLA+ transcript window (`--ci`) | Passed |
| E2E: `acp`, `project-config`, `config-persistence`, `mcp-verbs`, `cli`, `doctor`, `toolbox`, `sessions`, `tui-agent`, `session-recovery` | Passed with no retries; `tui-agent` ran no tests here |

The new `max_subagents` unit test and the settings-list tests are in the unit suite above.

## kai-runtime `925598b4` (private packaging) and `@kunemi-group/kai@0.0.17-kai.1`

Changes only workflows, the packager, its test, a new script, and the changelog.

| Step | Result |
| --- | --- |
| `node sdk/tests/test-node-package.mjs` (adds the private scope's names, aliases, registry, commit, and refusals) | Passed |
| `shellcheck` and `bash -n` on `scripts/package-private-libfx.sh`; the workflows parse as YAML | Passed |
| Addons for linux-x64 and linux-arm64 (glibc 2.34, baseline CPU), darwin-x64 and darwin-arm64, cross-compiled here with Zig 0.17.0 from `925598b4`'s source; both Linux addons pass `check-linux-abi.py` | Built; the macOS and arm64 addons weren't run, since there's no such machine here |
| WASM core and term surfaces, ReleaseSmall | Built (not shrunk with `wasm-opt`) |
| `scripts/package-private-libfx.sh` from the clean commit: pack, check, install as `libfx` with this machine's platform package, load the native backend | Passed |
| Published to GitHub Packages: `@kunemi-group/kai` and its four platform packages at `0.0.17-kai.1`, `gitHead` `925598b4` | Published |
| Installed from the registry as `"libfx": "npm:@kunemi-group/kai@0.0.17-kai.1"`: the alias pulls in only the linux-x64 package, and the native backend loads; three archives downloaded from the registry are byte-identical to those built here | Passed |

Hosted CI still has to run the macOS and arm64 addons (`test:node-napi` on each) before Dotrix is deployed on those machines. Dotrix's Chat host runs on Linux x64.

## kai-runtime `413707ee` (fx command packaging) and Dotrix's Chat pin

| Step | Result |
| --- | --- |
| `shellcheck` and `bash -n` on `scripts/package-private-cli.sh`; the workflows parse as YAML | Passed |
| Static fx for Linux x86_64 and aarch64 (`-Doptimize=ReleaseSafe -Dcpu=baseline -Dtarget=<arch>-linux-musl`), source as on `main` at `95d32954` | Built; the arm64 binary wasn't run, since there's no such machine here |
| `scripts/smoke-binary.sh` on the x86_64 binary | Passed |
| Dotrix's real-binary tests with it as `fx` (`apps/cli/tests/test_real_local_engines.py`, `test_fx_native.py`: native namespace, protocol, resume, Stop, browser) | 18 passed, 10 skipped (Codex and desktop cases), the same as the earlier glibc build |
| Dotrix [#281](https://github.com/adeyemiadekunle/dotrix/pull/281), Chat on `@kunemi-group/kai@0.0.17-kai.1`: full `uv run pytest` | 1,645 passed, 146 skipped |
| Its fx Chat suites, the handoff test, and 0.0.16 → Kai cross-version (4) and restart (5) checks | 160 passed, 2 skipped (paid live-model tests); all passed |

## Dotrix #282: Codes on `@kunemi-group/kai-cli-linux-<cpu>@0.0.17-kai.1`

| Step | Result |
| --- | --- |
| Published `@kunemi-group/kai-cli-linux-x64` and `-arm64` from `8935660b`; registry archives byte-identical to those built | Passed |
| The coding image's install step, run with `sh` outside Docker against the registry: SHA-256 checked, `fx --version` | Passed; a wrong SHA-256 stops it |
| Dotrix's cloud driver on a hostile repository: Kai's fx makes one model request with no repository instructions or skill; upstream fx 0.0.17 is refused before any request | Passed |
| Dotrix's real-binary local tests with Kai's static fx | 27 passed, 10 skipped; upstream fx refused in every native case |
| Dotrix's coding and CLI suites | 264 passed, 24 skipped |

Not run: `docker build` of the coding image (no Docker daemon here), and the arm64 binary.

## kai-runtime upstream sync (`adeyemiadekunle/kai@170f50e4`)

Synced `sync/upstream-170f50e4` from `origin/main` (`2ee91382`) with `upstream/main` (`170f50e4`, 931 commits ahead of fork base `d1d4a883`), resolving conflicts in `AGENTS.md`, `scripts/pgso/tests/test_corpus.py`, `src/core/cli/cli_config.zig`, and `src/core/subagent/tool_host.zig` (adding `.too_many_subagents` to `src/core/subagent/refusal.zig`).

Platform and toolchain: macOS arm64, Zig 0.17.1, Bun 1.4.5, Node v26.13.1, Python 3.

| Step | Result |
| --- | --- |
| `git diff --check` and `zig fmt --check src/` | Passed |
| Boundary and surface guards (`compactor`, `indexer`, `recovery`, `agents`, `public-surface`) | Passed |
| `python3 -m unittest scripts/pgso/tests/test_corpus.py` | Passed (`38` tests, `76` candidate scenarios) |
| `zig build`, N-API addon (`ReleaseSafe`), WASM core and term (`ReleaseSmall`) | Passed |
| `zig build test` | Passed (exit `0`) |
| Built `./zig-out/bin/fx` smoke (`version` and `project_config` default and override) | Passed (`0.0.17`, `true`, `false`, clean stderr) |
| E2E: `tests/e2e/project-config.test.ts` and `tests/e2e/acp.test.ts` | `299` passed, `14` skipped (live-model cases), `0` failed |
| SDK: `test-journal.mjs`, `test-agent-correlation.mjs`, `test-node-napi.mjs`, `test-node-package.mjs` | Passed |

Outstanding for hosted CI: Linux x64/arm64 builds and ABI checks, macOS arm64 hosted CI lane, remaining E2E corpus files, TLA+ workflows, WASM browser/Node JSPI suites, and live-model tests.

## kai-runtime `feat/subagent-timeout-and-macos-cli`

Added per-child profile timeout (`max_duration_seconds` in `profiles.zig`, plumbed through `authority.zig`, `domain.zig`, `tool_host.zig`, `config.zig`, `orchestrator.zig`, and enforced via a child-scoped `DurationWatchdog` in `agent_adapter.zig`), parameterized `scripts/sign-and-notarize-macos.sh`, added optional macOS CLI packaging (`@kunemi-group/kai-cli-darwin-arm64`, `-x64`) to `scripts/package-private-cli.sh`, and bumped `publish-private-libfx.yml` to Zig 0.17.1 with a `cli-macos` matrix.

Platform and toolchain: macOS arm64, Zig 0.17.1, Python 3.

| Step | Result |
| --- | --- |
| `zig fmt --check src/`, `git diff --check`, `bash -n` on signing and packaging scripts | Passed |
| Boundary and surface guards (`compactor`, `indexer`, `recovery`, `agents`, `public-surface`) | Passed |
| `python3 -m unittest scripts.tests.test_macos_signing scripts.tests.test_signed_macos scripts.pgso.tests.test_corpus` | Passed (`66` tests) |
| `zig build` and `zig build test` | Passed (exit `0`) |
| Built `./zig-out/bin/fx` smoke (`--version` and `config get max_subagents`) | Passed (`0.0.17`, `0`, clean stderr) |

Outstanding for hosted CI: Linux x64/arm64 and macOS arm64 PR CI lanes, `publish-private-libfx.yml` `cli-macos` publish run, and Apple Developer ID signing and notarization once Apple secrets are configured.

## Kai-runtime Fx v0.0.18 sync

The merge at `b6e741bca5f6` imports 212 Kai commits through Fx `6196071`. The checks below ran on Linux x86_64 with Zig 0.17.1 and Bun 1.4.5.

| Check | Result |
| --- | --- |
| `zig build` and CLI smoke | Passed. The binary reports `0.0.18`, `max_subagents` defaults to `0`, and `FX_PROJECT_CONFIG=0` disables project configuration. |
| Zig formatting, CLI shape, and agents, compactor, indexer, and recovery boundaries | Passed |
| PGSO corpus tests | 38 passed with 78 candidate scenarios, including Kai's project-configuration test. |
| Focused ACP and project-configuration E2E | Seven passed using local fake providers. Covered live and replayed shell metadata, a command kept across prompts, subagent profile discovery, project-configuration policy, and content-filter refusal. |

Hosted Linux and macOS verification is tracked in [PR #24](https://github.com/adeyemiadekunle/kai-runtime/pull/24).

## Kai runtime 0.0.18-kai.1 release

Published from `4259a031d` by `publish-private-libfx.yml` (run 45893155716). The checks below ran on Windows 11 x64 with Node 24.13.1, and on WSL Ubuntu x86_64 with Node 18.19.1.

| Check | Result |
| --- | --- |
| Hosted CI on the release commit (PR #24) | Passed: Build & Test, E2E (deterministic), Shellcheck, Startup Latency, macOS arm64, and every SDK job. |
| Published package metadata | `@kunemi-group/kai@0.0.18-kai.1` records `gitHead` `4259a031d`. Each Linux `bin/fx` matches its SHA-256 and the package's `fx.sha256`. |
| Published x64 `fx` on WSL Ubuntu | Reports `0.0.18`, and `config get project_config` is `false` with `FX_PROJECT_CONFIG=0`. Dotrix's `fx-acp.mjs` ran a turn and a resumed turn against a scripted model, both `end_turn` with clean stderr. |
| Dotrix `fx_host` on Windows | `npm ci` installed `0.0.18-kai.1`. `handoff.test.mjs` passed through the WebAssembly fallback (`--experimental-wasm-jspi`), since no Windows native addon is published. `platform-handoff-probe.mjs` aborts on a libuv assertion on Windows, and it does the same on `0.0.17-kai.3`. |

Outstanding: the arm64 and macOS packages were not run outside GitHub's runners. Dotrix's cross-version journal test and its Linux fx coding tests run in Dotrix's CI.

## Kai runtime 0.0.18-kai.2 release

Published from `f3450193` by `publish-private-libfx.yml` (run 45910918125), after the `-Dkai-release` change (PR #26). The checks below ran on WSL Ubuntu x86_64 with Zig 0.17.1 and Node 18.19.1, and on Windows 11 x64 with Node 24.13.1.

| Check | Result |
| --- | --- |
| `zig fmt --check src/ build.zig` and `check_deprecated.py` (PR #26) | Passed |
| `-Dkai-release` validation (PR #26) | `0.0.17-kai.1` and `0.0.18-kai.x` stop the build. A plain build reports `0.0.18`, and `-Dkai-release=0.0.18-kai.2` reports it for `--version`, `-v`, and ACP `agentInfo.version`, with clean stderr. |
| `zig build test` in Debug (PR #26) | 13109 of 13136 passed, 25 skipped, and 2 failed, neither in code the change touches: a git worktree test, since the copy had no `.git`, and a streamed-presentation span test. Hosted CI passed both in ReleaseSafe. |
| Published packages | `@kunemi-group/kai@0.0.18-kai.2` records `gitHead` `f3450193`. Each Linux `bin/fx` matches its SHA-256 and `fx.sha256`. |
| Published x64 `fx` | Reports `0.0.18-kai.2`, and `project_config` is `false`. Dotrix's native version check accepts it and refuses 0.0.18-kai.1. `fx-acp.mjs` ran a turn and a resumed turn, both `end_turn` with clean stderr. |
| Dotrix `fx_host` on Windows | `npm ci` installed `0.0.18-kai.2`. `handoff.test.mjs` passed through the WebAssembly fallback. |

Outstanding: the arm64 and macOS packages were not run outside GitHub's runners.
