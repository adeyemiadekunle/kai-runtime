# Phase 1: Dotrix Chat host compatibility with the fork

Recorded on 19 November 2026. This page records the Phase 1 evidence from the [migration plan](DOTRIX_KAI_MIGRATION_PLAN.md): whether the fork's SDK can replace Dotrix Chat's `libfx@0.0.16` pin, and what blocks it. It does not establish macOS, Windows, paid-model, or deployed behavior.

**Result:** the fork reads every Dotrix journal shape tested here that 0.0.16 wrote. The one blocking gap, G1, was that libfx 0.0.17 journals an answer the provider cut off at its output limit as an ordinary completed turn, so a retry returned the truncated text as complete. Upstream fx main has the same behavior. G1 is fixed in the fork (see the [gap list](#gap-list)); the Dotrix pin stays at 0.0.16 until the fix passes CI and the pin change lands. **R3.3, R3.5, R7.3, R7.6.**

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
| G1 | **Fixed in the fork, pending CI.** An output-limit cutoff was journaled as a completed turn. From 0.0.17, the runtime settles a `finish_reason: "length"` answer with `stopReason: "max_output_tokens"`; 0.0.16 failed the turn. Its `turn_committed` record was `kind: "assistant"` with no marker, so a retry of that turn ID reported `end_turn`. The fork now records `output_limited: true` on that turn, at journal event version 5 and checkpoint version 5, and a retried turn reports `max_output_tokens`. Readers up to version 4, including 0.0.16 and published 0.0.17, refuse such a session instead of misreading it. Journals already written by unfixed 0.0.17 never recorded the cutoff and cannot be repaired, so Dotrix lists only `0.0.16` as readable by the fork. Dotrix's `test_fx_replay_does_not_treat_a_truncated_or_refused_answer_as_complete[length]` expects the retry to raise; with the fork it returns `max_output_tokens`, which `fx_pilot` already rejects, so widen that assertion when the pin changes. | Admitting the fork for new Chat work until CI passes | Fork |
| G2 | No private package scope, registry, or CI credential path. The fork artifact here is a local tarball. | Changing the Dotrix pin | Owner decision |
| G3 | Only Linux x64 was built and tested. The packager needs every platform's addon for a publishable set; macOS arm64 CI has not run on this commit. | Publishing; any macOS claim | Fork CI |
| G4 | **Covered.** Dotrix's restart tests run across artifacts with `DOTRIX_FX_RESTART_WRITER` and `DOTRIX_FX_RESTART_READER` (Dotrix `84448ea`): with libfx 0.0.16 writing and the fork reading, an approval approved or rejected after a restart, a change cut off mid-way and recovered without changing the project twice, steering accepted before a crash, and a delegation handoff resumed with the real scheduler all pass (133 passed, 2 skipped live-model tests). The `createFxAgent` local-store path holds no production state: the backend always uses the Postgres journal or an ephemeral engine. | None | Dotrix |
| G5 | Phase 2 provider capability checks (streaming, tools, errors, cancellation per provider and model) have not started. | Phase 3 | Phase 2 |

## G1 fix verification

Recorded on Linux x64 with Zig 0.17.0, on the commit that adds the fix.

- `sdk/tests/test-journal.mjs native native`: 84 passed, including two new cases (a journal retry and a checkpoint restore of a cut-off turn both report `max_output_tokens` with no model request, and only the cut-off turn is written at version 5). The released 0.0.16 and 0.0.17 fixtures still restore.
- New Zig tests in `journal.zig`: a cut-off turn writes and folds at event version 5 and checkpoint version 5, a completed turn keeps its version 1 bytes, and `output_limited` other than `true` is refused.
- `test-native-core-ready`, `test-host-tools`, `test-host-tool-cancel`, and `test-native-core-misuse`: passed. `zig fmt --check src/`, the agents, compactor, indexer, and recovery boundary checks, and `check-public-surface.sh`: passed.
- `zig build test`: 11,234 passed, 31 skipped, 7 failed, 4 crashed in the main suite; the session manager suites had 4 failures each. Every failure is a process-group signal, read-only file, or file-mode test. The container runs as root, and the session manager failures pass as an unprivileged user. None is in the journal, checkpoint, or session codec. They were not re-run against the unchanged baseline, so treat that as unconfirmed until CI runs.
- Dotrix's real host with the fixed fork packed as `0.0.17-dotrix.2`: the cross-version harness passes 0.0.16 → fork, fork → fork, and, by refusing the session, fork → 0.0.16 and fork → 0.0.17. The Dotrix Chat suites ran 157 passed and 1 failed, the truncation assertion described in G1.
- The rebuilt ReleaseSafe `fx` binary passed all 9 `DOTRIX_TEST_FX` native and ACP driver tests.

macOS arm64 and hosted CI have not run.

## Decisions still open

1. The private SDK package name, scope, registry, and how CI and the backend image authenticate to it. The published layout also names platform packages `@libfx/*` in `sdk/node.js`, so a rename must change the loader too.
2. The version scheme for fork artifacts, and how the source commit is recorded with each one. `0.0.17-dotrix.1` was a local placeholder.
3. G1 was fixed in the runtime, as preferred. The [integration plan](DOTRIX_KAI_INTEGRATION_PLAN.md) orders the remaining fork and Dotrix work.

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
