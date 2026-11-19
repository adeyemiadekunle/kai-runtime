# Kai migration baseline

Historical development-snapshot audit. The current migration candidate is [fx v0.0.17 plus the upstream printf backport](DOTRIX_KAI_RELEASE_BASELINE.md). The checks below apply to their recorded revisions and do not qualify the new candidate.

The migration branch starts at `283323f402aea1810174a43be259172781320264`, the same Git commit as private `origin/fx-baseline`, public `public-fork/main`, and fetched `upstream/main`. The fork diff at that revision is empty. Dotrix's verified GitHub `stage` was `b039f6cfa47abaaec5aa6a6f31470491413f524c`. The local Dotrix checkout has its own in-progress changes and remains on its earlier commit.

## Capability inventory

| Capability | Baseline source and evidence | Migration work |
| --- | --- | --- |
| Bootstrap and core loop | `build.zig` builds `fx`. `src/main.zig` wires the app. `src/core/agents/agents.zig` exports agent state, and `src/core/agent/runtime/` owns the turn runtime and checkpoints. | Reuse the turn runtime. Extend branding and configuration at their owning surfaces. |
| Chat embedding | `sdk/engine.js` implements `createFxEngine`. `sdk/package.json` exports `./durable-local`. Dotrix's fx host and handoff probe use the SDK through a private worker process. | Reuse the SDK entry points and host process. Test journal compatibility with Dotrix's deployed `libfx@0.0.16` before admitting saved runs. |
| Codes transport | `src/acp/server.zig` dispatches session creation, prompt, cancellation, load, and resume. `tests/e2e/acp.test.ts` exercises configured provider turns and replays tool updates. | Reuse ACP and test against Dotrix's existing driver handshake and host isolation. Keep the SDK and binary pinned to the same private Kai revision. |
| Model providers | `src/gateway/configured_transport.zig` and the protocol adapters in `src/gateway/` implement configured transports. `tests/e2e/configured-providers.test.ts` and `sdk/tests/test-agent-provider-tools.mjs` provide starting coverage. | Reuse compatible adapters. Compare the actual Dotrix provider and model combinations before narrowing the existing engine choices. |
| Tools and permissions | `src/core/tooling/tool_specs.zig` holds shared tool specs. `src/core/permissions/permissions.zig` owns runtime permission checks. Dotrix's `fx_tools.py` handles project tools in the host. | Reuse tool dispatch. Preserve host authorization, worker isolation, and scoped credentials on both surfaces. |
| Skills | `src/core/skills/skill_runtime.zig` handles discovery and catalogue behavior. `src/tools/skills/skill.zig` loads skill resources. `sdk/skills-node.js` covers Node-side loading. | Reuse the existing skill format and loading paths where compatible. Add category, version, and enablement policy in Dotrix. Verify supported roots and discovery depth before deciding on a catalogue layout. |
| Delegation | `src/core/subagent/authority.zig` and neighboring runtime modules handle child authority and execution. Dotrix's Chat scheduler owns named specialists and their workflow state. | Preserve scheduler-owned named specialists. Evaluate the runtime's existing primitives for bounded temporary coding workers after slot parity. |
| State and recovery | `src/acp/libfx_journal.zig`, `src/core/session_manager/`, and `src/core/recovery/recovery.zig` cover runtime journals, durable sessions, and model request recovery. The request recovery model lives in `tests/tla/recovery/Recovery.tla`. | Reuse Kai's session recovery. Preserve Dotrix leases, approvals, and side-effect reconciliation. Verify compatibility and cancellation at the integration boundary. |
| Distribution | `.github/workflows/release.yml` runs on pushes to `main`. `.github/workflows/publish-libfx.yml` targets public libfx publishing. | Replace inherited destinations before promoting the private baseline. Select the private SDK registry and CI credential path before publishing. |

The source inventory establishes where to start implementation. Performance comparisons and claims about saved-state or provider compatibility require execution evidence. **R1.1, R1.4, R3.5, R4.1, R4.3, R5.3, R5.4, R7.3, R7.6.**

## Baseline verification

- Linux module boundary checks passed for agents, compactor, indexer, and recovery. All 38 PGSO corpus tests passed. Zig 0.17.1 accepted the formatting of `src/`.
- All 41 focused request recovery tests passed with Zig 0.17.1 in ReleaseSafe.
- The private Linux CI SDK job failed in `sdk/tests/test-native-core-misuse.mjs:235`. After accepting a response chunk, `finishCoreFetch` returned `0` where the test expects `1`. The same test passed nine times locally under Bun 1.4.2 with the addon from that CI run. The cause remains open.
- The macOS arm64 build passed. The Keychain MCP store lock driver reported `VIOLATES` where the model expects `ACCEPTED` in `tests/tla/drivers/mcp_host/store-lock-budget.test.ts:390`.
- The SDK and Keychain test repairs failed with the old assertion or comparator and passed locally after the change.
- The original 205-trace unsaved transcript replay exhausted the Java heap during semantic processing of the generated module. Checking batches with the same model and assertions passed all 205 unsaved and 206 saved traces locally.
- A combined draft runs all three repairs on one commit in private CI. Linux and macOS arm64 verification is pending.
- Local Docker verification on `9b0b8ae326e20c3d747517f8541f73565ac20f11` passed the Linux build, ACP command and saved-session replay smoke, native printf parity, module boundaries, 38 PGSO corpus checks, 41 request recovery tests, and the Keychain trace-ordering fixture. The ACP test verified empty stderr and a zero exit code.
- Run `./scripts/docker-ci/run.ps1` from the repository root for local Linux smoke verification. Use `-Suite Unit` to run ReleaseSafe unit tests before the smoke. The native macOS and hosted CI gates still apply. **R7.3, R7.5, R7.6.**
