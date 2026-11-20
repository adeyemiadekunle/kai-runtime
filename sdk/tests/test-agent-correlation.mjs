#!/usr/bin/env node
// A host's correlationId reaches the turn, every one of its events, and its result; a turn without one is unchanged.
import { strict as assert } from "node:assert";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createFxEngine, supportsJspi } from "../node.js";

const scriptDir = fileURLToPath(new URL(".", import.meta.url));
const backend = process.argv[2] || "native";
if (!new Set(["native", "wasm"]).has(backend)) throw new Error("usage: test-agent-correlation.mjs [native|wasm]");
if (backend === "wasm" && !supportsJspi()) throw new Error("WebAssembly backend requires JSPI");

let requests = 0;
const agent = await createFxEngine({
  backend,
  apiKey: "correlation-test-key",
  model: "sdk/correlation-model",
  ...(backend === "native"
    ? { nativeAddon: resolve(scriptDir, "../../zig-out/lib/libfx.node") }
    : { wasm: await readFile(resolve(scriptDir, "../../zig-out/bin/fx-core.wasm")) }),
  fetch(_url, init = {}) {
    if (init.method === "GET") {
      return Response.json({ object: "list", data: [{ id: "sdk/correlation-model", type: "language", tags: ["tool-use"] }] });
    }
    requests++;
    const events = requests % 2 === 1
      ? [
        { type: "tool-call", toolCallId: `call-${requests}`, toolName: "tick", input: {} },
        { type: "finish", finishReason: { unified: "tool-calls", raw: "tool-calls" } },
      ]
      : [
        { type: "text-delta", delta: "done" },
        { type: "finish", finishReason: { unified: "stop", raw: "stop" } },
      ];
    return new Response(events.map((event) => `data: ${JSON.stringify(event)}\n\n`).join("") + "data: [DONE]\n\n", {
      headers: { "content-type": "text/event-stream" },
    });
  },
  tools: [{
    name: "tick",
    description: "Tick once",
    inputSchema: { type: "object", properties: {} },
    execute() { return "ticked"; },
  }],
});

async function run(options) {
  const turn = agent.prompt("Tick once, then finish.", options);
  const events = [];
  for await (const event of turn) events.push(event);
  return { turn, events, result: await turn.result };
}

try {
  const tagged = await run({ correlationId: "dotrix-run:42/step:1" });
  assert.equal(tagged.turn.correlationId, "dotrix-run:42/step:1");
  assert.equal(tagged.result.correlationId, "dotrix-run:42/step:1");
  assert.equal(tagged.result.stopReason, "end_turn");
  assert.deepEqual(new Set(tagged.events.map((event) => event.type)), new Set(["tool_start", "tool_end", "text_delta"]));
  for (const event of tagged.events) assert.equal(event.correlationId, "dotrix-run:42/step:1", JSON.stringify(event));

  const plain = await run({});
  assert.equal("correlationId" in plain.turn, false);
  assert.equal("correlationId" in plain.result, false);
  for (const event of plain.events) assert.equal("correlationId" in event, false, JSON.stringify(event));

  for (const bad of ["", "x".repeat(257), "a\nb", 42]) {
    assert.throws(() => agent.prompt("Tick", { correlationId: bad }), /correlationId must be/);
  }
  assert.equal(requests, 4); // refused prompts never reached the model
  console.log(`correlation ok (${backend})`);
} finally {
  await agent.close();
}
