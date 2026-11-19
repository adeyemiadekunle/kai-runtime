# Kai baseline from the fx 0.0.17 release

The migration now starts from upstream's published fx `v0.0.17` tag with one upstream printf repair. This replaces the earlier qualification approach based on a later upstream development snapshot. Preserve the old repair branches as historical investigation; they are not prerequisites for this release-based candidate.

## Revisions

| Surface | Revision |
| --- | --- |
| Upstream release | `v0.0.17`, commit `d1d4a883382daf8f2e7447dc361978312cf403d2` |
| Upstream printf repair | `91888247097ae539dbf4504e75f5b6574478f3a2` |
| Existing private copy of that repair | `82c6a80fdf50d0336a53bdcb100fe35f8c187353` |
| Release-based branch | `codex/release-0.0.17-printf` |
| Release-based candidate | `5356f7feea6f2ffe5de2c7ed91e22b59febca0b9` |
| Release toolchain | Zig `0.17.0`, matching the release CI pin |

The previous development baseline at `283323f40` contained 565 commits beyond the release tag. The release-based candidate contains one commit beyond the tag and changes only `src/core/shell_command/command_effect.zig`, including its inline regressions. No SDK repair, Keychain trace repair, transcript checker repair, branding, or runner-routing changes are included.

The existing private `fx-baseline` branch is retained as history. The release-based branch is the working migration candidate; it is not a force-rewrite of that historical branch or `main`.

## Printf behavior

The release does not include the upstream printf repair. On Ubuntu 26.04, uutils `/usr/bin/printf` can interpret a data argument such as `--help` as its own option even when it follows the format argument. That differs from shell builtin behavior.

The backport refuses direct execution when any printf data starts with `--`, so the command takes the existing shell/review path. Single-dash data remains eligible for direct execution. Preserve the upstream tests and permission behavior. **R4.1, R4.5, R7.1.**

## Verification scope

The user requested replacing the broad development-baseline qualification with the release plus this focused repair. The obsolete qualification runs were cancelled. Do not reopen their matrices or assume their fixes belong on the release branch.

Verify the repair with:

1. The unchanged release's native printf parity test reproducing the mismatch on Ubuntu 26.04.
2. The backported printf planner tests passing with Zig 0.17.0.
3. The review-free shell parity matrix passing across sh, dash, bash, and zsh.
4. A successful release-based build.
5. A real interaction using the freshly built `./zig-out/bin/fx`, sending `printf '%s' '--help'` through the ACP shell tool, checking the literal output, saved-session replay, clean stderr, and zero exit status.

The local verification uses an isolated Docker container with external networking disabled and a deterministic local provider fixture. Its temporary printf interaction probe adapts an existing ACP test inside the container; it does not change the repository's committed E2E corpus.

Linux verification passed at `5356f7fee`: the original release reproduced the mismatch, the backported planner and shell parity tests passed, and the built binary returned literal `--help` through ACP. The ACP test also verified saved-session replay, empty stderr, and exit status zero.

The release is an upstream starting point, not proof that every Dotrix model, saved journal, worker, or operating system works. Full unit/SDK/platform qualification is not claimed for the patched candidate. In particular, local Linux checks cannot establish macOS execution. **R3.5, R7.3, R7.5, R7.6.**

## Migration consequences

- Recheck source inventories against the release-based branch before implementing. The earlier capability and SDK audits identified later development-snapshot behavior and retain that historical scope.
- Dotrix Chat's installed `libfx@0.0.16` still needs a tested adaptation to the selected private SDK. The release tag does not remove its exact-version guard.
- Keep SDK and coding binary artifacts tied to the same chosen source revision and record the printf backport SHA. A version string of `0.0.17` alone does not distinguish the patched binary from the upstream release.
- Keep private publishing and branding separate from this repair. Preserve upstream attribution and state compatibility. **R3.5, R4.8, R5.4, R8.2.**
- Branding is now the final migration phase. Continue functional work under the existing fx/libfx names and replace Chat's 0.0.16 pin with the selected fork artifact after compatibility verification.

## Sources

- [Upstream fx 0.0.17 release](https://github.com/vercel-labs/fx/releases/tag/v0.0.17)
- [Upstream printf repair](https://github.com/vercel-labs/fx/commit/91888247097ae539dbf4504e75f5b6574478f3a2)
- [Migration plan](DOTRIX_KAI_MIGRATION_PLAN.md)
