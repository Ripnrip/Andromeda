import { execFile } from "node:child_process"
import { promisify } from "node:util"
import { stat } from "node:fs/promises"
import path from "node:path"
import { NextResponse } from "next/server"

const execFileAsync = promisify(execFile)

// Repo root = web/../ (the Next app lives at <repo>/web).
const REPO_ROOT = path.resolve(process.cwd(), "..")

// Allow-listed artifacts only — this route reads the repo, so the
// parameter is never interpolated into a path freely.
const ARTIFACTS: Record<string, { repoPath: string; tarName: string }> = {
  "swift-review-gate": {
    repoPath: ".claude/skills/swift-review-gate",
    tarName: "swift-review-gate.tar",
  },
  "swift-canon": {
    repoPath: ".claude/skills/swift-canon",
    tarName: "swift-canon.tar",
  },
  "PR template": {
    repoPath: ".github/PULL_REQUEST_TEMPLATE.md",
    tarName: "pull-request-template.md",
  },
  "app-control": {
    repoPath: "docs/app-control",
    tarName: "app-control.tar",
  },
}

export async function GET(request: Request) {
  const url = new URL(request.url)
  const name = url.searchParams.get("artifact") ?? ""
  const artifact = ARTIFACTS[name]
  if (!artifact) {
    return NextResponse.json(
      { error: "unknown artifact", available: Object.keys(ARTIFACTS) },
      { status: 404 },
    )
  }

  const absolute = path.join(REPO_ROOT, artifact.repoPath)
  // Containment: the resolved path must stay inside the repo.
  if (!absolute.startsWith(REPO_ROOT + path.sep)) {
    return NextResponse.json({ error: "invalid path" }, { status: 400 })
  }

  try {
    await stat(absolute)
  } catch {
    return NextResponse.json(
      { error: `artifact not present in this build: ${artifact.repoPath}` },
      { status: 404 },
    )
  }

  const repoRel = path.relative(REPO_ROOT, absolute)
  try {
    // encoding: 'buffer' keeps the tar bytes binary — string stdout would
    // UTF-8-corrupt them (caught by round-trip `tar -tf` in verification).
    const { stdout } = await execFileAsync(
      "tar",
      ["-cf", "-", repoRel],
      {
        cwd: REPO_ROOT,
        maxBuffer: 64 * 1024 * 1024,
        encoding: "buffer",
      },
    )
    const bytes = new Uint8Array(stdout)
    return new NextResponse(bytes, {
      status: 200,
      headers: {
        "Content-Type": "application/x-tar",
        "Content-Disposition": `attachment; filename="${artifact.tarName}"`,
        "Content-Length": String(bytes.byteLength),
        "Cache-Control": "no-store",
      },
    })
  } catch (err) {
    return NextResponse.json(
      { error: "bundle failed", detail: String(err) },
      { status: 500 },
    )
  }
}
