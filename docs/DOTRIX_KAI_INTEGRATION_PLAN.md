# Dotrix integration plan for the fork

Recorded on 19 November 2026. This plan turns the proposed `src/dotrix/` boundary in the [runtime direction](KAI_DOTRIX_NEW_DIRECTION.md#183-what-must-be-written-in-zig-versus-dotrix) into work checked against the fork's source at `main`. Both Dotrix Chat (Nova and the specialists, through the SDK) and Dotrix Codes (Kai, through ACP) run on this fork. Branding stays last: names below are the current `fx` names.

Each item says what already exists, what changes, and the evidence that closes it. Fork work lands first; Dotrix changes follow in their own PRs once the fork artifact they depend on is built and tested.

## Principles

- **Reuse before adding.** The fork already has agent profiles, child permission admission, subagents in ACP, skills, MCP access policy, journals, and checkpoints. A Dotrix module is justified only where the host needs something these don't provide.
- **The host decides, the runtime enforces.** Dotrix owns identities, approvals, scheduling, credentials, and the audit record. The runtime must not take authority from repository files, model output, or its own defaults when a Dotrix host is driving it.
- **Repository content is data.** A repository being coded on must never change Kai's instructions, profiles, skills, MCP servers, or permissions. This is already Dotrix's rule for Claude Code, Codex, and OpenCode.
- **Saved formats change only with a version and a reader.** Follow the pattern used for G1: write a new field only when it applies, bump the event or checkpoint version, and keep older readers failing closed.

## What the source already provides

| Capability | Where | Use for Dotrix |
| --- | --- | --- |
| Agent profiles: model, effort, permission mode, tools (`*`, `!name`), MCP servers, prompt (append or replace) | `src/core/profiles/profiles.zig` | Kai's coding profile and its temporary workers. Nova's specialists stay Dotrix-scheduled (see D3). |
| Profile resolution: `~/.fx/agents`, then the repository's `.fx/agents`, then built-ins. A repository profile cannot set the permission mode and cannot read outside the repository. | `profiles.zig` `Roots`, `load` | Safe against permission escalation, **not** against instruction injection. See D1. |
| Child permission admission: a child may not exceed its parent's mode | `src/core/subagent/authority.zig` `admitChildPermission`, `decideToolAuthority` | Bounded Kai workers inherit narrower authority. |
| Subagent host with children kept in the session log (v2) | `src/acp/server.zig` `enableSubagentHost`, `src/core/subagent/` | Kai's temporary workers in Codes. |
| libfx runs only host tools (`builtin_tools = false`) | `build.zig` `addNapiArtifact` | Chat tools stay in Dotrix (`fx_tools.py`, `runtime_tools.py`). |
| Project instructions toggle: `context` ("Load project instructions such as AGENTS.md") | `src/core/config/settings_keys.zig`, marked `project_safe` | A repository's own settings may set it. See D1. |
| Skills from `~/.fx/skills` and repository roots, loaded on demand | `src/core/skills/` | Host-pinned skill catalogue. See D5. |
| Journal events v1 to v5, checkpoints v1 to v5, snapshot versions, typed `FxJournalVersionError` | `src/core/agent/runtime/journal.zig`, `checkpoint.zig` | Chat recovery. v5 is the G1 fix. |

## Work items

### D1. Host-owned configuration for Codes (security, first)

**Status: done in the fork and wired in Dotrix, verified locally on Linux x64.** The profile-only setting `project_config` (default on) and its override `FX_PROJECT_CONFIG` (`src/core/config/project_config_setting.zig`) gate the repository's `.fx.json` settings layer, `.fx/agents` profile root, workspace skill roots, `.mcp.json`, and project instructions, including subdirectory `AGENTS.md` notes. A repository cannot set it. Before the change, a probe through Dotrix's own cloud driver (`infra/coding/fx-acp.mjs`) with this fork binary showed a repository's `AGENTS.md` and skill reaching the model; with the setting off, neither did. Tests: `tests/e2e/project-config.test.ts`, Zig tests in `profiles.zig` and `mcp/workspace_config.zig`, and Dotrix's driver and local-profile tests. The repository's files stay readable through the agent's tools as data.

**Gap.** Dotrix's cloud ACP driver (`infra/coding/fx-acp.mjs`) writes `~/.fx/settings.json` with only provider and housekeeping keys. It does not set `context: false`, and nothing stops the repository's `.fx/agents/main/` profile, `.fx/skills/`, or `AGENTS.md` from reaching Kai's prompt. The native local profile sets `context: false`, but `context` is a `project_safe` key, so a repository's settings layer may turn it back on. Verify that precedence before relying on either.

**Change in the fork.** One host control that, when set, makes the session ignore every repository-supplied configuration source: project settings, project profiles, project skills, project MCP configuration, and project instructions. Resolve profiles and skills only from roots the host names. Expose it through both ACP (Codes) and the SDK (Chat), with a name chosen through the `fx-cli-shape` skill. The repository's files remain readable as workspace data through the normal tools.

**Evidence.** A deterministic ACP test with a repository that ships `.fx/agents/main/prompt.md`, `.fx/skills/x/SKILL.md`, `.fx/settings.json` with `context: true`, an `AGENTS.md`, and an MCP config: none reach the model request or the tool list with the control set, and all do without it. Then Dotrix sets the control in both drivers and keeps its own test.

### D2. Kai's coding profile from Dotrix

**Gap.** Kai runs as fx's built-in `main` profile. Dotrix's coding brief, model choice, and Plan/Build policy reach it only as the prompt and settings.

**Change.** With D1, Dotrix writes a profile root for each coding turn: `main` for Kai (prompt from Dotrix's built-in coding contract and layered guidance, the turn's model, tools filtered by work mode), plus worker profiles (D4). Record a digest of the profile set with the coding run, so a resumed turn can refuse a changed profile the same way Chat bindings refuse a changed configuration digest. No new Zig module is needed if `Roots` can be pointed at a host directory; add one only if that isn't enough.

**Evidence.** ACP test: the model request carries the host profile's prompt and tool list. Dotrix test: the digest is pinned and a mismatch fails closed.

### D3. Nova and the named specialists stay Dotrix-scheduled

**Decision.** Keep Lyra, Orion, Vega, Juno, and Echo as Dotrix scheduler tasks, each a separate SDK engine with its own journal, contract, model, and key. This is already built (`delegation.py`, `specialist_sessions.py`) with leases, fencing, and continuity checks the runtime's subagent host doesn't have. Do not move named specialists onto in-process runtime children.

**Change in the fork.** None required. Optional later: pass a host-supplied correlation identifier through SDK turn events if a Dotrix consumer needs it for attribution. The run and task IDs already correlate today.

**Evidence.** The existing Dotrix specialist and continuity suites on the fork artifact (passing in Phase 1, see [Phase 1 results](DOTRIX_KAI_PHASE1_COMPATIBILITY.md)).

### D4. Bounded temporary workers for Kai

**What exists.** ACP's subagent host, profile-based children, and `admitChildPermission`.

**Change.** Dotrix supplies worker profiles (for example implementer, tester, reviewer) through D2, each with narrower tools. Audit whether the subagent host already bounds fan-out, depth, concurrency, per-child time, and tokens. Add the missing limits as host-set values in the fork, not as Dotrix-only conventions. Workers never get Dotrix identities and cannot start Dotrix workflows. Juno's independent review stays a separate Dotrix run.

**Evidence.** ACP tests for a child refused when it asks for more permission or tools than its parent, a limit exceeded, cancellation reaching every child, and child events visible in `session/update`. Then a Dotrix test mapping child events into the coding run's steps.

**Audit (19 November 2026).** Checked in the source and by driving the fork binary through Dotrix's own cloud driver with a scripted model:

| Concern | What the fork does | Result |
| --- | --- | --- |
| Depth | Two levels: a subagent's own host clears `children_nest`, so its children never get `subagent` (`authority.zig`) | Bounded |
| Permissions and tools | A child's mode can't exceed its parent's (`admitChildPermission`); a profile narrows its tools | Bounded |
| Stop | `session/cancel` ends the turn as `cancelled`; a child's `sleep 20; touch marker` never wrote its marker and left no process | Works |
| A turn that ends while a child works | The turn waits for the child's report and its answer before `end_turn` | Works |
| Workers at once | Only the 256-child registry cap | **Added `max_subagents`** |
| Steps per child | Children inherit `max_agent_steps` | Unchanged; Dotrix sets no step limit today |
| Per-child time and tokens | No per-child budget | Open; bounded today by the turn's own limits |
| Visibility | A child's tool calls are not `session/update`s, but fx's opt-in `libfx/hook` events carry them, with each child's session and the `delegation` that started it | **Dotrix's driver now maps them** |

`max_subagents` is a profile-only setting (0, the default, means no limit). Under the admission lock, before admission records anything, a message that would start work on one more child while that many work is refused with `too_many_subagents` and a sentence telling the model to wait for a report or message a working one. A message to a working child still queues for its next turn. Tested in `tool_host.zig`. Dotrix's cloud driver and local profile set it to 2, Dotrix's bound for parallel builds.

Dotrix's driver asks each session for hook events with `captureContent`, maps a child's `tool.start` and `tool.end` to the same `tool` and `tool_result` events as the main session's, and names the worker on each step ("Ran pytest -q (tester)"). It also fixes the description of a `subagent` call, which read "Asked a subagent to" with nothing after it for fx 0.0.17's arguments.

### D5. Pinned skills

**What exists.** Skill discovery and on-demand loading. Dotrix already pins its own skill catalogue per run and materializes it outside the repository.

**Change.** With D1, a host-named skill root is the only source. Record each skill's content hash in the journal or session metadata only if a Dotrix consumer needs proof of what was loaded; otherwise keep the pin on the Dotrix side.

**Evidence.** An ACP test where the host root's skill loads and a repository skill of the same name does not.

**Status (19 November 2026): met for coding, no fork change.** Dotrix doesn't use fx's skill loading for Kai: `modules/coding/skills.py` writes the run's pinned skills, checked against their SHA-256, into a fresh read-only `/tmp/dotrix-skills-*` folder outside the repository, and the brief names them for Kai to read as files. With D1 the repository's skill folders no longer load, so only Dotrix's pinned copies reach the model. Chat's skills are host tools (`read_skill`) with role filters, unaffected by fx's skill roots.

### D6. Execution events

**What exists.** SDK events (`text_delta`, `reasoning_delta`, `tool_start`, `tool_end`, results with `stopReason`) and ACP `session/update`.

**Change.** None until a Dotrix consumer needs a field it can't get. Candidates: a stable sequence per execution for replay, and `max_output_tokens` and other stop reasons surfaced to the UI. Do not add the envelope proposed in the direction document wholesale.

### D7. Recovery and saved-state follow-ups

- G1 (output-limit cutoff) is fixed in the fork: events and checkpoints that hold a cut-off answer are version 5, and a retried turn reports `max_output_tokens`.
- Extend Dotrix's cross-version harness (G4 in [Phase 1 results](DOTRIX_KAI_PHASE1_COMPATIBILITY.md#gap-list)): approval decided after a restart, saved write result, accepted steering before a crash, delegation handoff, and the `createFxAgent` session path.
- Codes: test restoring a saved `~/.fx` session archive from the previous binary into the fork binary, and refusing an incompatible one with a clear recovery path.

### D8. Distribution

Private package name, scope, registry, and CI credentials; a version scheme that records the source commit; publishing workflows replaced; Linux arm64 and macOS builds. These are owner decisions (see [decisions](DOTRIX_KAI_PHASE1_COMPATIBILITY.md#decisions-still-open)).

**Decided and done.** GitHub Packages in the kunemi-group organisation: the SDK as `@kunemi-group/kai` with `@kunemi-group/kai-<platform>` packages, and the fx command as `@kunemi-group/kai-cli-linux-x64` and `-arm64`. Versions are `<fx release>-kai.<n>`, each package records its commit in `gitHead`, and a published version is never replaced (`publish-private-libfx.yml`, `scripts/package-private-libfx.sh`, `scripts/package-private-cli.sh`). The upstream publishing workflows run only in `vercel-labs/fx`. Consumers need a token with `read:packages` (`KAI_PACKAGES_TOKEN`). Still open: hosted CI runs of the macOS and arm64 builds, and macOS signing if a Kai command is ever shipped for macOS.

## Order

| Step | Repository | Items | Exit evidence |
| --- | --- | --- | --- |
| 1 | Fork | G1 fix | Zig and SDK tests; the Dotrix harness passes in every direction. Done in this branch, pending CI. |
| 2 | Fork, then Dotrix | D1 (done) | ACP probe through the Dotrix driver, e2e and unit tests |
| 3 | Fork, then Dotrix | D4 audit (done), `max_subagents`, worker activity in Codes | `tool_host.zig` tests; Dotrix driver test; probes through the Dotrix driver |
| 4 | Dotrix | Pin the fork for Chat; widen the one truncation test; harness listing `("0.0.16",)` only | Chat suites on the pinned artifact. Done: Dotrix #281 pins `@kunemi-group/kai@0.0.17-kai.1`. |
| 5 | Dotrix | Codes on the fork binary with D1 and D2; profile digest pinning | Coding suites and a real ACP turn with the built binary |
| 6 | Dotrix | D4 worker profiles and child event mapping | Coding suites with children |
| 7 | Both | D7 recovery fixtures, Phase 2 provider checks | Cross-version and provider matrices |
| 8 | Both | Retire legacy engines, then branding | Per the [migration plan](DOTRIX_KAI_MIGRATION_PLAN.md) |

## Proposed `src/dotrix/` layout, reconsidered

The direction document proposed six Zig modules. Against the source:

| Proposed module | Outcome |
| --- | --- |
| `agent_profiles.zig` | Not needed if `profiles.zig` accepts host roots (D2). |
| `specialist_delegation.zig` | Not needed: named specialists stay Dotrix-scheduled (D3). |
| `execution_events.zig` | Deferred until a consumer needs a field (D6). |
| `dotrix_tools.zig` | Not needed: Chat tools are host tools; Codes reaches Dotrix through the host relay. |
| `permission_bridge.zig` | Covered by D1 and the existing authority code; add only the host-owned configuration control. |
| `checkpoint_bridge.zig` | Not needed: journals and checkpoints already round-trip through the host. |

So the fork likely needs no `src/dotrix/` folder at all. The Dotrix-specific changes are small, general host controls in the modules that own them. That keeps upstream merges simpler, as the [maintenance section](KAI_DOTRIX_NEW_DIRECTION.md#12-upstream-fx-maintenance) asks.
