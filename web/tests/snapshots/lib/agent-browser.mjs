/**
 * Thin promise wrapper around the `agent-browser` CLI.
 *
 * The CLI keeps a long-lived browser daemon per namespace, so each invocation is
 * cheap and page state persists between calls. A dedicated namespace keeps this
 * suite from colliding with any interactive `agent-browser` session an operator
 * (or agent) has open on the same machine.
 */

import { spawn } from "node:child_process"
import { createRequire } from "node:module"

const require = createRequire(import.meta.url)

const NAMESPACE = "andromeda-web-snapshots"
const SESSION = "snapshots"

/** Resolves the CLI entrypoint from node_modules so CI never depends on a global install. */
function resolveBinary() {
  // agent-browser publishes a `bin` entry; resolve through its package.json so we
  // do not hardcode a dist path that can move between minor versions.
  const pkgPath = require.resolve("agent-browser/package.json")
  const pkg = require("agent-browser/package.json")
  const bin = typeof pkg.bin === "string" ? pkg.bin : pkg.bin?.["agent-browser"]
  if (!bin) throw new Error("agent-browser package exposes no bin entry")
  return new URL(bin, new URL(pkgPath, "file://")).pathname
}

const BINARY = resolveBinary()

/**
 * Runs one `agent-browser` command.
 *
 * @param {string[]} args CLI arguments, already tokenised (no shell involved).
 * @param {{allowFailure?: boolean, timeoutMs?: number}} [options]
 * @returns {Promise<{code: number, stdout: string, stderr: string}>}
 */
export function agentBrowser(args, options = {}) {
  const { allowFailure = false, timeoutMs = 120_000 } = options
  const argv = ["--namespace", NAMESPACE, "--session", SESSION, ...args]

  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [BINARY, ...argv], {
      stdio: ["ignore", "pipe", "pipe"],
      env: process.env,
    })

    let stdout = ""
    let stderr = ""
    let settled = false

    const timer = setTimeout(() => {
      if (settled) return
      settled = true
      child.kill("SIGKILL")
      reject(new Error(`agent-browser timed out after ${timeoutMs}ms: ${argv.join(" ")}`))
    }, timeoutMs)

    child.stdout.on("data", (chunk) => {
      stdout += chunk
    })
    child.stderr.on("data", (chunk) => {
      stderr += chunk
    })

    child.on("error", (error) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      reject(error)
    })

    child.on("close", (code) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      if (code !== 0 && !allowFailure) {
        reject(new Error(`agent-browser ${argv.join(" ")} exited ${code}\n${stdout}\n${stderr}`))
        return
      }
      resolve({ code: code ?? 0, stdout, stderr })
    })
  })
}

/** Installs the bundled Chromium (and Linux system deps on CI) exactly once per run. */
export async function installBrowser({ withDeps = false } = {}) {
  const args = ["install"]
  if (withDeps) args.push("--with-deps")
  await agentBrowser(args, { timeoutMs: 600_000 })
}

/** Tears down the daemon so a rerun never inherits a stale page or viewport. */
export async function closeBrowser() {
  await agentBrowser(["close", "--all"], { allowFailure: true, timeoutMs: 60_000 })
}

/**
 * Cold-starts the browser with the given init script, retrying transient
 * socket races.
 *
 * `close --all` removes the daemon's Unix socket asynchronously, so an immediate
 * `open` can hit "Failed to connect: No such file or directory" while the old
 * socket is still being reaped. That is a startup race, not a page problem, so it
 * is retried here rather than surfaced as a scenario failure.
 */
export async function openBrowser(initScriptPath, { attempts = 4, backoffMs = 750 } = {}) {
  let lastError = null

  // `--disable-dev-shm-usage`: containers commonly cap /dev/shm at 64MB (this
  // sandbox does), well under what Chrome expects for its shared-memory buffers.
  // Without this, tall-page captures fail in ways that surface as unrelated
  // renderer errors. `--disable-gpu` / `--no-sandbox` are the standard headless-CI
  // pair and keep the container from falling back to a software GL path mid-run.
  const launchArgs = "--disable-dev-shm-usage,--disable-gpu,--no-sandbox"

  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      await agentBrowser(["open", "--args", launchArgs, "--init-script", initScriptPath])
      return
    } catch (error) {
      lastError = error
      // Escalate: drop any half-dead daemon before the next attempt.
      await closeBrowser().catch(() => {})
      await new Promise((resolve) => setTimeout(resolve, backoffMs * (attempt + 1)))
    }
  }

  throw new Error(`Could not start browser after ${attempts} attempts: ${lastError?.message ?? "unknown error"}`)
}
