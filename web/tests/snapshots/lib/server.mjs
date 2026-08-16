/**
 * Production-build server lifecycle for the snapshot suite.
 *
 * Snapshots are taken against `next build` + `next start`, never `next dev`:
 * dev mode injects the error overlay, ships unminified Fast Refresh runtime, and
 * compiles routes on first request — all of which make pixel output depend on
 * request order rather than on the committed source.
 */

import { spawn } from "node:child_process"
import { once } from "node:events"

const READY_TIMEOUT_MS = 120_000
const POLL_INTERVAL_MS = 500

/** Runs `next build` for the web workspace, streaming output to the caller's stdio. */
export async function buildWebApp({ cwd }) {
  const child = spawn("npm", ["run", "build", "--workspace", "web"], {
    cwd,
    stdio: "inherit",
    env: { ...process.env, NEXT_TELEMETRY_DISABLED: "1" },
  })
  const [code] = await once(child, "close")
  if (code !== 0) throw new Error(`next build failed with exit code ${code}`)
}

/**
 * Starts `next start` and resolves once the root route answers.
 *
 * @returns {Promise<{baseUrl: string, stop: () => Promise<void>}>}
 */
export async function startWebApp({ cwd, port }) {
  const child = spawn("npm", ["run", "start", "--workspace", "web", "--", "--port", String(port)], {
    cwd,
    stdio: ["ignore", "inherit", "inherit"],
    env: { ...process.env, NEXT_TELEMETRY_DISABLED: "1", NODE_ENV: "production" },
  })

  let exited = false
  child.on("close", () => {
    exited = true
  })

  const baseUrl = `http://127.0.0.1:${port}`
  const deadline = Date.now() + READY_TIMEOUT_MS

  while (Date.now() < deadline) {
    if (exited) throw new Error("next start exited before becoming ready")
    try {
      const response = await fetch(baseUrl, { redirect: "manual" })
      // Any HTTP answer means the listener is up; a 3xx or 404 is still "ready".
      if (response.status > 0) {
        return { baseUrl, stop: () => stopChild(child) }
      }
    } catch {
      // Connection refused while Next boots — keep polling.
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS))
  }

  await stopChild(child)
  throw new Error(`next start did not become ready within ${READY_TIMEOUT_MS}ms`)
}

/** Sends SIGTERM, escalating to SIGKILL so a wedged server cannot hang CI. */
async function stopChild(child) {
  if (child.exitCode !== null || child.signalCode !== null) return
  child.kill("SIGTERM")
  const timer = setTimeout(() => child.kill("SIGKILL"), 5_000)
  try {
    await once(child, "close")
  } finally {
    clearTimeout(timer)
  }
}
