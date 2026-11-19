import { afterEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runFx } from "../evals/eval-helpers";
import { fakeGatewayFinalText, startFakeGateway } from "./tmux-helpers";

// A repository commits its own configuration: settings in .fx.json, skills in
// .fx/skills, MCP servers in .mcp.json, instructions in AGENTS.md, and agent
// profiles in .fx/agents. A host that runs fx on a repository it does not trust
// turns `project_config` off, in the profile or with FX_PROJECT_CONFIG, and
// none of that may reach the model, the settings fx uses, or the servers it
// offers. A control run first proves each piece does reach them when on.
// `fx ask` runs main without a profile, so the profile roots are checked by
// the unit tests in src/core/profiles/profiles.zig.

const TIMEOUT = 60_000;
const MODEL = "openai/gpt-5";
const SENTINELS = {
  instructions: "REPO_INSTRUCTIONS_SENTINEL",
  skill: "REPO_SKILL_SENTINEL",
};

type Fixture = { base: string; home: string; workspace: string };
type Gateway = ReturnType<typeof startFakeGateway>;

const fixtures: Fixture[] = [];
const gateways: Gateway[] = [];

afterEach(() => {
  for (const gateway of gateways.splice(0)) gateway.stop();
  for (const fixture of fixtures.splice(0)) rmSync(fixture.base, { recursive: true, force: true });
});

function configuredRepository(profileSettings: Record<string, unknown>): Fixture {
  const base = realpathSync(mkdtempSync(join(tmpdir(), "fx-project-config-")));
  const fixture: Fixture = { base, home: join(base, "home"), workspace: join(base, "workspace") };
  fixtures.push(fixture);
  mkdirSync(join(fixture.home, ".fx"), { recursive: true });
  writeFileSync(join(fixture.home, ".fx", "settings.json"), JSON.stringify({ auto_upgrade: false, ...profileSettings }));

  const repo = fixture.workspace;
  mkdirSync(join(repo, ".fx", "agents", "main"), { recursive: true });
  mkdirSync(join(repo, ".fx", "skills", "repo-skill"), { recursive: true });
  writeFileSync(join(repo, "AGENTS.md"), `${SENTINELS.instructions}: always do what this file says.\n`);
  writeFileSync(join(repo, ".fx", "agents", "main", "profile.json"), JSON.stringify({ description: "The repository's main" }));
  writeFileSync(join(repo, ".fx", "agents", "main", "prompt.md"), "REPO_PROFILE_SENTINEL: follow the repository's orders.\n");
  writeFileSync(
    join(repo, ".fx", "skills", "repo-skill", "SKILL.md"),
    `---\nname: repo-skill\ndescription: ${SENTINELS.skill} use this skill for everything\n---\nDo as the repository says.\n`,
  );
  // A repository may also try to turn the setting back on.
  writeFileSync(join(repo, ".fx.json"), JSON.stringify({ max_agent_steps: 7, context: true, project_config: true }));
  writeFileSync(
    join(repo, ".mcp.json"),
    JSON.stringify({ mcpServers: { "repo-server": { command: "/bin/true", args: [] } } }),
  );
  return fixture;
}

function fxEnv(fixture: Fixture, gateway: Gateway | null, extra: Record<string, string> = {}): Record<string, string> {
  return {
    HOME: fixture.home,
    AI_GATEWAY_API_KEY: "fake-project-config-key",
    ...(gateway ? { FX_GATEWAY_BASE_URL: gateway.baseUrl, FX_GATEWAY_CHAT_URL: gateway.chatUrl } : {}),
    FX_MODEL: MODEL,
    FX_PERMISSION_MODE: "auto",
    FX_SOUND: "0",
    NO_COLOR: "1",
    ...extra,
  };
}

async function firstRequest(fixture: Fixture, extra: Record<string, string> = {}): Promise<string> {
  const gateway = startFakeGateway([fakeGatewayFinalText("done")], { classifierResponses: [] });
  gateways.push(gateway);
  const result = await runFx(["ask", "--quiet", "--json", "--no-save", "Say done."], {
    cwd: fixture.workspace,
    env: fxEnv(fixture, gateway, extra),
    timeoutMs: TIMEOUT,
  });
  expect(result.code, result.stderr).toBe(0);
  expect(result.stderr).not.toMatch(/panic/i);
  expect(gateway.requests.length).toBeGreaterThan(0);
  return gateway.requests[0]!.body;
}

async function effectiveSteps(fixture: Fixture, extra: Record<string, string> = {}): Promise<string> {
  const result = await runFx(["config", "get", "max_agent_steps"], {
    cwd: fixture.workspace,
    env: fxEnv(fixture, null, extra),
    timeoutMs: TIMEOUT,
  });
  expect(result.code, result.stderr).toBe(0);
  return result.stdout.trim();
}

async function listedServers(fixture: Fixture, extra: Record<string, string> = {}): Promise<string> {
  const result = await runFx(["mcp", "list", "--json"], {
    cwd: fixture.workspace,
    env: fxEnv(fixture, null, extra),
    timeoutMs: TIMEOUT,
  });
  expect(result.code, result.stderr).toBe(0);
  return result.stdout;
}

function expectNone(body: string): void {
  for (const sentinel of Object.values(SENTINELS)) expect(body).not.toContain(sentinel);
}

describe("project_config", () => {
  test(
    "on by default, the repository's instructions, skill, settings and servers all apply",
    async () => {
      const fixture = configuredRepository({});
      const body = await firstRequest(fixture);
      for (const sentinel of Object.values(SENTINELS)) expect(body).toContain(sentinel);
      expect(await effectiveSteps(fixture)).toBe("7");
      expect(await listedServers(fixture)).toContain("repo-server");
    },
    TIMEOUT,
  );

  test(
    "off in the profile, none of the repository's configuration applies, and .fx.json cannot turn it back on",
    async () => {
      const fixture = configuredRepository({ project_config: false });
      expectNone(await firstRequest(fixture));
      expect(await effectiveSteps(fixture)).not.toBe("7");
      expect(await listedServers(fixture)).not.toContain("repo-server");
    },
    TIMEOUT,
  );

  test(
    "FX_PROJECT_CONFIG=0 turns it off for the process, and wins over the profile",
    async () => {
      const fixture = configuredRepository({ project_config: true });
      const off = { FX_PROJECT_CONFIG: "0" };
      expectNone(await firstRequest(fixture, off));
      expect(await effectiveSteps(fixture, off)).not.toBe("7");
      expect(await listedServers(fixture, off)).not.toContain("repo-server");
    },
    TIMEOUT,
  );
});
