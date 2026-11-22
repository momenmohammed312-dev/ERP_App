import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { spawn } from "node:child_process";

const server = new McpServer({
  name: "opencode-delegate",
  version: "1.0.0",
});

server.tool(
  "delegate",
  "Delegates a task to the OpenCode CLI for autonomous execution.",
  {
    task: z.string().describe("The task/prompt to execute in OpenCode"),
    model: z.string().optional().describe("Optional model in provider/model format"),
  },
  async ({ task, model }) => {
    const args = ["run", task];
    if (model) {
      args.push("--model", model);
    }
    args.push("--auto", "--format", "json");

    return new Promise((resolve) => {
      const proc = spawn("opencode", args, {
        stdio: ["ignore", "pipe", "pipe"],
        cwd: process.cwd(),
        shell: true,
      });

      let stdout = "";
      let stderr = "";
      let settled = false;

      proc.stdout.on("data", (d) => {
        stdout += d.toString();
      });
      proc.stderr.on("data", (d) => {
        stderr += d.toString();
      });

      proc.on("error", (err) => {
        if (settled) return;
        settled = true;
        resolve({
          content: [{ type: "text", text: `Failed to start opencode: ${err.message}` }],
          isError: true,
        });
      });

      proc.on("close", (code) => {
        if (settled) return;
        settled = true;
        const text = stdout || stderr;
        resolve({
          content: [{ type: "text", text }],
          ...(code === 0 ? {} : { isError: true }),
        });
      });
    });
  },
);

await server.connect(new StdioServerTransport());
