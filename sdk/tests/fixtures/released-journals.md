# Released journal fixtures

`libfx-0.0.16-journal.json` and `libfx-0.0.17-journal.json` were recorded with the published SDK and matching Linux x64 native addon for each version. They contain synthetic conversation state, not user sessions. Each writer completed a plain turn and a host-tool turn and saved both its original journal records and a checkpoint.

The compatibility cases in `sdk/tests/test-journal.mjs` open the original bytes with the candidate SDK. They check that retrying the completed tool turn makes no model request or tool call, then check the next turn retains the earlier user messages and tool result. Separate cases check checkpoint restoration. These cases do not establish every approval, interruption, image, or Dotrix host-binding behavior.

Run only these cases with a matching native addon built at `zig-out/lib/libfx.node`:

```sh
bun sdk/tests/test-journal.mjs native native 'released '
```

Omitting the case filter runs the whole journal suite. A case filter matching nothing fails. Native-only runs do not require a WASM artifact. WASM comparisons require the built `fx-core.wasm` and a JSPI-capable host as usual.

## Recording provenance

The npm archives were verified against their registry metadata before extraction. The SHA-512 integrity values used were:

| Package | Integrity |
| --- | --- |
| `libfx@0.0.16` | `sha512-qA/b37rsJ8DNJXkg1+iyQCmzBbiXO+2lCXtdZzP6GjVPcStJEb3QkmhXEpOURb+VCfNc7L9gB6TiTXeS3/CPXQ==` |
| `@libfx/libfx-linux-x64-gnu@0.0.16` | `sha512-JAz5lUwGTTVqmVDT6p0a2o4m7lOFBPU+i3sYYYw3r+FQUPY+cV0r/AnXY40edA1ICf00EHlH9Okna5gWBr/Zyg==` |
| `libfx@0.0.17` | `sha512-kAO6FJ2ck5OvPEAeQLMOkNXA7ELii62aOQOxrAg+K52m1mvcho4yc6BU/t7I8MsE2caM7kHcw2E15knF9cSAwg==` |
| `@libfx/libfx-linux-x64-gnu@0.0.17` | `sha512-o/QorRhKSPUGCz5k2LjTPeQskaHTkq5Q0EaWNLluZ4IH8zdQv5dEICvaoVqfe9XEvmF1pkrV0DUCInoebSIyTA==` |

Prepare an explicit temporary artifact root containing:

```text
<root>/0.0.16/sdk/package/       extracted libfx 0.0.16 SDK
<root>/0.0.16/addon/package/     extracted matching addon
<root>/0.0.17/sdk/package/       extracted libfx 0.0.17 SDK
<root>/0.0.17/addon/package/     extracted matching addon
```

Then run:

```sh
bun sdk/tests/fixtures/generate-released-journals.mjs <root>
```

The recorder verifies each SDK's declared version, executes it with its matching addon, and uses a loopback-only synthetic provider. It writes fixture candidates in the supplied artifact root and does not overwrite repository fixtures automatically. Timestamps and generated storage identifiers can differ between recordings; inspect semantic differences before replacing a committed fixture. Keep released-writer fixtures unchanged when updating the reader, so the test continues to check cross-version compatibility.
