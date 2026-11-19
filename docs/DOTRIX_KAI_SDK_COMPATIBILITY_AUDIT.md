# Dotrix SDK and saved-state compatibility audit

Historical source comparison against the development qualification commit. The current candidate is [the fx v0.0.17 release plus printf](DOTRIX_KAI_RELEASE_BASELINE.md). Recheck fork-specific differences, including local World startup serialization, against that release-based source before implementing.

Published `libfx@0.0.17` is the relevant comparison target for the Kai fork. Dotrix Chat still installs `libfx@0.0.16` and explicitly rejects a different package version for its low-level engine path. The coding image already pins the fx CLI at `0.0.17`. These are separate integrations.

The source comparison supports a focused host adaptation rather than an SDK rewrite. It does not establish that saved journals resume correctly through the new compiled runtime. Keep existing state and runtime bindings until that behavior is tested.

## Audited inputs

Recorded on 18 November 2026.

| Input | Identity |
| --- | --- |
| Dotrix source | `stage` at `b039f6cfa47abaaec5aa6a6f31470491413f524c` |
| Fork source | Qualification commit `9b0b8ae326e20c3d747517f8541f73565ac20f11` |
| Private baseline | `fx-baseline` at `82c6a80fdf50d0336a53bdcb100fe35f8c187353`; the SDK and Zig journal/checkpoint files inspected here have no diff from the qualification commit |
| Published old SDK | `libfx@0.0.16`, downloaded from its npm tarball and verified against the registry's SHA-512 integrity |
| Published current SDK | `libfx@0.0.17`, downloaded and verified the same way; npm's `latest` endpoint returned `0.0.17` during this audit |

The downloads were extracted for static inspection. Neither package was installed or executed. No new build, model call, or runner job was launched for this audit.

Published archive integrity values:

```text
libfx@0.0.16
sha512-qA/b37rsJ8DNJXkg1+iyQCmzBbiXO+2lCXtdZzP6GjVPcStJEb3QkmhXEpOURb+VCfNc7L9gB6TiTXeS3/CPXQ==

libfx@0.0.17
sha512-kAO6FJ2ck5OvPEAeQLMOkNXA7ELii62aOQOxrAg+K52m1mvcho4yc6BU/t7I8MsE2caM7kHcw2E15knF9cSAwg==
```

Neither version metadata response supplied a `gitHead`. Package integrity identifies the inspected published bytes; it does not identify a source commit for the bundled WASM or native addons.

## Findings

### 1. Dotrix has an explicit package-version barrier

`packages/engine/src/dotrix_engine/runtimes/fx_host/worker.mjs` imports `createFxAgent`, `createFxEngine`, `FxFencedError`, and `memory` from `libfx`, plus `local` from `libfx/durable-local`.

For host persistence or ephemeral-engine execution, it reads `./node_modules/libfx/package.json` and requires its version to equal `0.0.16`. A direct dependency update to `0.0.17` fails that check even if all imports resolve. A private package rename also breaks that hardcoded package lookup.

Other version-coupled surfaces are:

- `runtimes/fx_host/package.json` and its lockfile pin the old package and optional native addons.
- `runtimes/fx.py` checks `node_modules/libfx` and includes `libfx-0.0.16` in the configuration digest.
- `modules/agents/fx_pilot.py` pins `libfx-0.0.16-chat-3` and `libfx-0.0.16-delegation-3`.
- `modules/agents/runtime_sessions.py` accepts stored runtime names `deepagents` and `fx` and fences mismatched identities.

Update these as a coordinated, tested host change. Keep unknown versions refused. Do not remove the package guard without replacing its compatibility decision and tests. **R3.5, R5.4.**

### 2. The JavaScript engine layer matches across all three inputs

The following results compare text after converting CRLF to LF. They are source equality results, not binary or behavior equivalence.

| File | Published 0.0.16 vs 0.0.17 | Published 0.0.17 vs fork |
| --- | --- | --- |
| `sdk/engine.js` | Equal | Equal |
| `sdk/fx-harness.js` | Equal | Equal |
| `sdk/core-output.js` | Equal | Equal |
| `sdk/node.js` | Different | Equal |
| `sdk/custom-provider.js` | Different | Equal |
| `sdk/fetch-cleanup.js` | Different | Equal |
| `sdk/durable.js` | Different | Different |
| `sdk/types/node.d.ts` | Equal | Equal |
| `sdk/types/durable-local.d.ts` | Equal | Equal |

For published packages, the paths are relative to the package root without `sdk/`.

The normalized SHA-256 of `engine.js` in all three inputs is:

```text
48ff3ea051dca7924c204cdd6677ed4165d89f55932baaa97bfeacd67fae7bbf
```

The imports Dotrix uses remain available in published 0.0.17 and the fork. The inspected Node bridge keeps `libfxApiVersion = 3` and `nativeCoreApiVersion = 4`; the shared engine keeps `fxSdkApiVersion = 2`. These numbers describe different contracts and are not npm package versions.

Matching API numbers do not justify mixing arbitrary native packages and SDK JavaScript. Package the fork's SDK and compiled artifacts together from one reviewed revision and verify the actual loader. **R1.4, R5.4.**

### 3. Published 0.0.17 adds provider and transport behavior

The Node bridge passes numeric `Retry-After` information through `startCoreFetchResponseWithRetryAfter` when the addon supports it, with a fallback to the older entry point. The fetch helper parses digits-only retry delays and bounds the value.

The custom-provider adapter adds provider defaults, title/vision model selection, output-limit field selection, request fields, and reasoning-effort mappings. Dotrix currently supplies a smaller provider object with name, URL, and tool/context metadata. Its existing shape remains represented in the inspected adapter, but actual provider turns still need verification.

This does not establish support for a new provider, reasoning configuration, or modality in Dotrix. Keep the host's selected endpoint and credential boundaries. **R4.8, R7.3.**

### 4. The low-level journal wrapper is unchanged; native decoding remains a gate

The common `engine.js` writes the outer format `libfx-journal-v1` and reads records as ordered events. It recognizes `FXSN` when extracting a checkpoint sequence. Both published versions and the fork share that JavaScript code.

Within the fork, `src/core/agent/runtime/journal.zig` has event versions through 4 and `FXSN` snapshot variants through 4. `src/core/agent/runtime/checkpoint.zig` reads `FXCP` checkpoint versions 1 through 4. Feature-dependent versions carry additions such as named images and context notes. The outer JSON wrapper remaining at v1 does not mean every inner event or checkpoint has the same version.

Dotrix's `committedAnswers` helper directly reads v1 journal event objects to reconstruct completed text from `turn_progress` and `turn_committed`. Its engine path relies on that map when a completed retry produces no text. This private journal interpretation is a compatibility dependency even though Dotrix stores the journal bytes opaquely elsewhere.

Dotrix configures `checkpointAfterBytes` to 16 MiB while its host journal is capped at 8 MiB, deliberately retaining record history for that completed-answer reader. Do not lower the checkpoint threshold during the package swap without testing completed-answer recovery from checkpointed history. This audit does not change those limits.

The inspected SDK tests include a previous-release checkpoint fixture labeled 0.0.11. That test and matching wrapper code do not replace a Dotrix 0.0.16-to-0.0.17/fork resume test using its real host storage and tool ledger. **R3.3, R3.4, R3.5, R3.7, R7.6.**

### 5. Durable-agent changes affect a separate path

Dotrix normally uses `createFxEngine` with its Postgres-backed host persistence for journaled runs. Its worker also has a `createFxAgent` path using `memory()` or `local()` and the durable session API. Test both paths; success in one does not establish the other.

Published 0.0.17 changes the shared durable layer's handling of newly created World-backed runs and event-slot coverage, among other changes. The fork adds per-store serialization of World startup. Its `local()` adapter derives a canonical folder key so concurrent starts in one process do not race while the local World creates its version file.

The published 0.0.16 and 0.0.17 `durable/local.mjs` bundles are equal. Comparing either bundled file directly with the fork's short source module yields a large diff because the package includes bundled dependencies. That diff alone is not evidence of a local store format change. Compare packaged fork output and exercise saved-store continuation before drawing that conclusion.

### 6. Branding must preserve saved-format identifiers deliberately

Keep exported names, journal format tags, checkpoint magic, durable symbols, stored runtime identities, and configuration fingerprints separate from display branding. A blanket `fx` replacement could alter compatibility rather than presentation.

The package name, installed dependency path, artifact loader, native-package map, and version lookup must agree. Changing only the top-level npm name is insufficient because `sdk/node.js` still names platform packages under `@libfx/`. Select the private package layout and test clean installation in the actual backend image. **R3.5, R5.1, R5.4, R8.2.**

## Compatibility status

| Question | Result |
| --- | --- |
| Is published 0.0.17 the current npm latest? | Yes, verified against the registry during this audit. |
| Does Dotrix Chat already use it? | No; dependency, lockfile, fingerprint, and worker version guard still name 0.0.16. |
| Are the required exports still present? | Yes, by source inspection of published 0.0.17 and the fork. |
| Does Dotrix's unmodified durable host accept 0.0.17? | No; its exact-version check rejects it. |
| Does the JavaScript journal engine match? | Yes after line-ending normalization. |
| Can all existing Dotrix state resume on the fork? | Unverified; requires compiled-runtime and host integration evidence. |
| Is a fresh-turn reset justified by this comparison? | No; no incompatibility requiring a reset was demonstrated. Preserve originals and test first. |
| Is CLI/ACP saved state covered by this SDK comparison? | No; coding archives and native profiles are separate verification work. |

## Required compatibility exercise before changing the pin

Use disposable storage, deterministic local provider responses, and the same Dotrix tool definitions on both sides. Never use production journals or credentials in fixtures. No full CI rerun is necessary merely to execute this source audit; implementation must still meet repository gates.

| Fixture produced by published 0.0.16 | Target verification on published 0.0.17 and packaged fork |
| --- | --- |
| Completed text turn | Repeat the same turn ID and recover its text without another model request or write. |
| Open model turn killed after a durable barrier | Resume once under a current Dotrix lease, retain accepted inputs, and produce one final result. |
| Pending approved or denied tool handoff | Preserve the approval identity and honor the decision after resume. |
| Tool result saved before worker death | Return the stored result without repeating the write. |
| Claimed write with unknown outcome | Keep reconciliation required; do not silently replay it. |
| Accepted steering before a crash | Preserve stable input identity and ordering without duplicate delivery. |
| Completed turn plus checkpoint and journal tail | Recover output and resume the next turn with consistent cursor/fencing behavior. |
| Memory/local durable-agent session | Continue through the high-level session API; verify repeated results and independent same-folder startup. |
| Image-bearing state, where admitted by the host | Verify image references and storage requirements independently of plain-text success. |
| Unsupported newer or corrupt state | Fail without altering the source records; provide the compatible-artifact recovery route. |

Also test the reverse direction for the exact state intended to support rollback. If the old runtime cannot read new writes, rollback must retain the new artifact for those sessions and change only admission for new work. Do not infer downgrade compatibility from successful upgrade. **R3.3, R3.5, R3.6, R7.1, R7.3, R7.6.**

## Recommended next patch after baseline verification

Prepare a focused Dotrix host compatibility change with an explicit supported artifact/version policy and deterministic cross-version fixtures. Keep the stored `fx` slot for the pilot. Update its dependency/lockfile, package resolution, configuration digest, and binding version together only after the intended artifact passes those fixtures.

Use existing `test_chat_runtimes.py`, `fx_host/handoff.test.mjs`, `test_fx_changes.py`, `test_chat_inputs.py`, and `test_runtime_tools.py` as starting owners. Extend the relevant fixture coverage rather than treating an import check as a recovery test. No package pin, runtime guard, state, or deployment was changed by this audit.

## Sources

- [Published libfx 0.0.16 metadata](https://registry.npmjs.org/libfx/0.0.16)
- [Published libfx 0.0.17 metadata](https://registry.npmjs.org/libfx/0.0.17)
- [Current libfx latest metadata](https://registry.npmjs.org/libfx/latest)
- [Pinned Dotrix worker](https://github.com/adeyemiadekunle/dotrix/blob/b039f6cfa47abaaec5aa6a6f31470491413f524c/packages/engine/src/dotrix_engine/runtimes/fx_host/worker.mjs)
- [Pinned Dotrix host persistence](https://github.com/adeyemiadekunle/dotrix/blob/b039f6cfa47abaaec5aa6a6f31470491413f524c/apps/backend/src/dotrix_backend/modules/agents/runtime_journal.py)
- [Fork JavaScript engine](https://github.com/adeyemiadekunle/kai-engine/blob/9b0b8ae326e20c3d747517f8541f73565ac20f11/sdk/engine.js)
- [Fork native journal codec](https://github.com/adeyemiadekunle/kai-engine/blob/9b0b8ae326e20c3d747517f8541f73565ac20f11/src/core/agent/runtime/journal.zig)
- [Dotrix integration map](DOTRIX_KAI_INTEGRATION_AUDIT.md)
