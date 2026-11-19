# Phase 1: Dotrix Chat host compatibility with the fork

Recorded on 19 November 2026. This page records the Phase 1 evidence from the [migration plan](DOTRIX_KAI_MIGRATION_PLAN.md): whether the fork's SDK can replace Dotrix Chat's `libfx@0.0.16` pin, and what blocks it. It does not establish macOS, Windows, paid-model, or deployed behavior.

**Result:** the fork reads every Dotrix journal shape tested here that 0.0.16 wrote, and a 0.0.16 host reads the fork's journals back. One gap blocks admitting the fork for new Chat work: libfx 0.0.17 journals an answer that the provider cut off at its output limit as an ordinary completed turn, so a retry of that turn returns the truncated text as a complete reply. Upstream fx main has the same behavior. The Dotrix pin stays at 0.0.16 until that is fixed. **R3.3, R3.5, R7.3, R7.6.**

## Revisions and artifacts

| Surface | Identity |
| --- | --- |
| Fork source | `adeyemiadekunle/kai-runtime` `main` at `38bb6e316cc8db21f4d529d8474da2ee4bad3445` (release baseline `5356f7fee` plus docs and the released-journal fixtures) |
| Toolchain | Zig `0.17.0` from ziglang.org, SHA-256 `1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026` |
| Platform | Linux x64 (glibc), Node 22.23.5, Bun from the container; no macOS or Windows run |
| Fork binary | `zig build -Doptimize=ReleaseSafe`, reports `0.0.17`; SHA-256 `935fe279ea66152192dbfbdc97efeace8393e67a10f609fadba9c9d5d665fa30` |
| Fork addon | `zig-out/lib/libfx.node`, SHA-256 `8cc2a14912ebcead7d17df0f1c6a08ccf7b3ad5c2722f3a90b0b5a6ea30072cd` |
| Fork SDK artifact | `node sdk/scripts/package-libfx.mjs` with `LIBFX_VERSION=0.0.17-dotrix.1`, this machine's addon only; local tarballs, nothing published |
| Published comparisons | `libfx@0.0.16`, `libfx@0.0.17` and their `@libfx/libfx-linux-x64-gnu` addons, each checked against the registry's SHA-512 integrity |
| Dotrix | `stage` at `b039f6cfa47abaaec5aa6a6f31470491413f524c`, plus the host change below |

`0.0.17-dotrix.1` is a local test version that distinguishes the fork artifact from the published release. Choosing the real private version scheme and registry is still open (see [decisions](#decisions-still-open)).

### SDK source at the release baseline

Every JavaScript and type file in published `libfx@0.0.17` is identical to the fork's `sdk/` after line-ending normalization, except `durable/local.mjs`, `durable/vercel.mjs`, and `durable/world.mjs`. The published files are bundles of `sdk/durable/` and its pinned dependencies, so a direct comparison with the fork's short source modules always differs. The earlier [SDK audit](DOTRIX_KAI_SDK_COMPATIBILITY_AUDIT.md) found more drift because it compared a later development snapshot.

## Fork checks

| Check | Result |
| --- | --- |
| `zig build -Doptimize=ReleaseSafe` and `zig build libfx-napi -Dnapi-surface=core -Doptimize=ReleaseSafe` | Passed (about 7 and 4.5 minutes on 4 cores) |
| `./zig-out/bin/fx --version` | `0.0.17`, exit 0 |
| `bun sdk/tests/test-journal.mjs native native 'released '` | 4 of 4 passed: released 0.0.16 and 0.0.17 journals and checkpoints restore without repeating a completed tool |
| `bun sdk/tests/test-journal.mjs native native` (full suite) | Passed |
| `node sdk/tests/test-native-core-ready.mjs`, `test-host-tools.mjs native`, `test-host-tool-cancel.mjs native` | Passed |
| `node sdk/tests/test-native-core-misuse.mjs` | Passed. This is the test that failed in private CI on the old development snapshot; it passes on the release baseline here. |

`FX_SOUND=0` was set for these runs. Formatting, unit tests (`zig build test`), the Bun E2E corpus, and macOS arm64 CI were not run in this pass.

## Dotrix host change

The Dotrix Chat host refused any libfx other than `0.0.16` with a hardcoded check in `fx_host/worker.mjs`, and `fx.py` and `fx_pilot.py` each repeated the version string. The change on Dotrix branch `claude/admiring-gauss-ntq6un` (commit `007848b`) replaces those with one policy. It keeps the pin at `0.0.16`, so stored bindings and behavior at that pin are unchanged.

- `runtimes/fx.py` `LIBFX_ARTIFACTS` names each admitted libfx artifact and the earlier artifacts whose journals it was shown to resume. `libfx_version()` reads the pin from `fx_host/package.json` and refuses one that isn't listed.
- `FxRuntime.create` refuses an install that differs from the pin, and the worker checks the installed package against the version Python sends. Before, the worker only checked on the journaled paths.
- The configuration digest and `fx_pilot` binding versions (`libfx-<pin>-chat-3`, `libfx-<pin>-delegation-3`) come from the pin. Earlier bindings are upgraded only when their artifact is in the current pin's list; anything else still fails closed. At `0.0.16` the upgrade map is identical to the previous hardcoded one.
- `tests/integration/test_fx_cross_version.py` is an opt-in harness. It runs a writer host and a reader host, each a separate install of `fx_host`, against the same encrypted Postgres journal. It is the evidence required before adding an entry to `LIBFX_ARTIFACTS`.

Admitting the fork later is a coordinated change: the pin, the lockfile, and an entry such as `"0.0.17-dotrix.1": ("0.0.16",)`.

## Cross-version results

Writer and reader are independent installs of the Dotrix host, so every case goes through `worker.mjs`, `FxRuntime`, `runtime_journal.py`, and real Postgres with a deterministic local Chat Completions server.

| Case | 0.0.16 → fork | 0.0.17 → fork | fork → fork | fork → 0.0.16 (rollback) |
| --- | --- | --- | --- | --- |
| Completed tool turn retried by ID: same text, no model request, no tool call; next turn keeps history | Pass | Pass | Pass | Pass |
| Host killed after a saved tool intent: one resume, same execution ID | Pass | Pass | Pass | Pass |
| Content-filter cutoff retried by ID stays incomplete | Pass | Pass | Pass | Pass |
| Output-limit cutoff retried by ID stays incomplete | Pass | Pass | **Fail** | **Fail** |

0.0.16 → 0.0.17 and 0.0.17 → 0.0.16 with the published packages give the same pattern as the fork columns.

### Dotrix suites with the fork installed

With the fork artifact installed as the repository's host and admitted in the table, the Chat suites ran 152 passed, 2 skipped (paid live-model tests), and 1 failed. The failure is `test_runtime_tools.py::test_fx_replay_does_not_treat_a_truncated_or_refused_answer_as_complete[length]`, the same gap as above. The suites were `test_chat_runtimes.py`, `test_fx_changes.py` (approve, reject, Accept edits, Plan, and a worker killed mid-change), `test_chat_inputs.py`, `test_runtime_tools.py`, `test_specialist_continuity.py`, `test_agent_scripts.py`, `test_fx_pilot.py`, and `test_runtime_tool_failures.py`. On the committed 0.0.16 pin, the engine, fx Chat, and backend unit suites pass: 781 passed, 9 skipped. `fx_host/handoff.test.mjs` passes on 0.0.16.

### Codes with the fork binary

The cloud ACP unit suites (`test_fx_coding.py`, `test_coding.py`) pass; they use a fake `fx acp`. `DOTRIX_TEST_FX=<fork fx>` runs the native local suite with the real binary: 9 passed, including the cloud ACP driver's protocol and resume inside the Bubblewrap namespace, Stop, and a provider failure after an edit.

Those native tests first failed on this host for a reason unrelated to fx. Dotrix's namespace mounts `/usr` but not `/etc/alternatives`, so a Debian `/usr/bin/python3` alternatives link dangles inside it and the run times out. The tests passed once the link pointed directly at `python3.13`. That is a Dotrix host bug, tracked separately.

## Gap list

| ID | Gap | Blocks | Owner |
| --- | --- | --- | --- |
| G1 | An output-limit cutoff is journaled as a completed turn. From 0.0.17, the runtime settles a `finish_reason: "length"` answer with `stopReason: "max_output_tokens"`; 0.0.16 failed the turn. Its `turn_committed` record is `kind: "assistant"` with no marker of the cutoff, unlike a content-filter cutoff (`kind: "interrupted"`, `terminal_reason: "failed"`). A retry of that turn ID reports `end_turn`, and Dotrix's host fills the text from the journal, so a Continue or recovered attempt would finish the run with a truncated reply. Every reader, including a 0.0.16 rollback, is affected for journals written by 0.0.17 or later. | Admitting the fork for new Chat work | Runtime: record the terminal stop reason on the committed turn and return it for a repeated turn. Needs a saved-format review, because a 0.0.16 rollback reader must still parse the record. Host fallback: Dotrix records non-`end_turn` outcomes per message, which leaves a crash window between the runtime's commit and the host's record. |
| G2 | No private package scope, registry, or CI credential path. The fork artifact here is a local tarball. | Changing the Dotrix pin | Owner decision |
| G3 | Only Linux x64 was built and tested. The packager needs every platform's addon for a publishable set; macOS arm64 CI has not run on this commit. | Publishing; any macOS claim | Fork CI |
| G4 | Not yet covered across artifacts: a pending approval decided after a restart, a saved write result returned without repeating it, accepted steering before a crash, a delegation handoff, and the `createFxAgent` memory/local session path. They pass on a single artifact in the Dotrix suites above. | Admitting saved runs mid-approval or mid-delegation | Extend `test_fx_cross_version.py` |
| G5 | Phase 2 provider capability checks (streaming, tools, errors, cancellation per provider and model) have not started. | Phase 3 | Phase 2 |

## Decisions still open

1. The private SDK package name, scope, registry, and how CI and the backend image authenticate to it. The published layout also names platform packages `@libfx/*` in `sdk/node.js`, so a rename must change the loader too.
2. The version scheme for fork artifacts, and how the source commit is recorded with each one. `0.0.17-dotrix.1` was a local placeholder.
3. Whether G1 is fixed in the runtime (preferred) or worked around in the host first.

## Reproduce

Build the fork, then package and pack it for this machine:

```sh
zig build -Doptimize=ReleaseSafe
zig build libfx-napi -Dnapi-surface=core -Doptimize=ReleaseSafe
zig build -Dwasm-surface=core -Doptimize=ReleaseSmall
zig build -Dwasm-surface=term -Doptimize=ReleaseSmall
npm ci --prefix sdk/durable
LIBFX_VERSION=0.0.17-dotrix.1 node sdk/scripts/package-libfx.mjs <out>/dist
```

The WASM build step also reinstalls `zig-out/bin/fx` as ReleaseSmall, so rebuild with `-Doptimize=ReleaseSafe` before running the binary checks. Run `npm pack` on `<out>/dist/libfx` and `<out>/dist/libfx-linux-x64-gnu`.

In Dotrix, make two copies of `packages/engine/src/dotrix_engine/runtimes/fx_host` (its `worker.mjs` with a `package.json` pinning the version under test), install one artifact in each, then run:

```sh
DOTRIX_FX_WRITER_HOST=<writer host> DOTRIX_FX_READER_HOST=<reader host> \
  uv run pytest apps/backend/tests/integration/test_fx_cross_version.py
```
