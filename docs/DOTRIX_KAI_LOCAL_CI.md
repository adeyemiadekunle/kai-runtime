# Local CI while GitHub Actions is unavailable

GitHub Actions can't run for this fork or for Dotrix until the account has credit again. Until then, each push is checked first by running the CI jobs locally, and the results are recorded here per commit. This doesn't replace hosted CI: macOS, Linux arm64, and the jobs that need artifacts from every platform still need it, and hosted CI should run on these commits once it is available. **R7.3, R7.5, R7.6.**

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
| E2E | The whole deterministic corpus through `ci-run-files.sh`, in two local shards | Running when this was recorded; so far `tui-resize` and one other file passed only on retry (reported as warnings, as CI does), and `tui-terminal-tool` failed on process-group stops (see below) |
| TLA+ MCP, transcript window, subagent | As in the workflow | Not yet run; queued after E2E |

The four unit-test failures are `core.cli.doctor_probes` (a child killed with its group at the deadline), `core.execution.command_runner` (a timeout terminates the foreground process group's descendants), and two `mcp.io.process` tests (stopping or deinitializing a server signals its whole process group). All four signal a process group. They failed the same way, as root, on the earlier commit `5cb37e3a`, which has neither this change nor any change to those modules. They fail in this container because its PID 1 (`process_api`) doesn't reap orphaned processes: a process a group stop killed stays a zombie that still answers `kill(pid, 0)`, so the test sees it running. A direct check showed an orphaned, killed grandchild left in state `Z`, and gone when run under `tini -s`, which reaps like a normal init. Hosted runners reap orphans. The E2E terminal-tool failures have the same cause. Re-running these tests under `tini -s` is pending.

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
