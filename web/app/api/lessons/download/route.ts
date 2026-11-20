import { readFile } from "node:fs/promises"
import path from "node:path"
import { NextResponse } from "next/server"

// Bundles live next to this route so the Vercel function can see them.
// The old route tarred `.claude/skills` from the repo parent, which is
// outside the `web/` deploy root and 404s in production.
const BUNDLES = path.join(process.cwd(), "app/api/lessons/download/bundles")

const ARTIFACTS: Record<string, { file: string; type: string; filename: string }> = {
  "swift-review-gate": {
    file: "swift-review-gate.zip",
    type: "application/zip",
    filename: "swift-review-gate.zip",
  },
  "swift-canon": {
    file: "swift-canon.zip",
    type: "application/zip",
    filename: "swift-canon.zip",
  },
  "PR template": {
    file: "PULL_REQUEST_TEMPLATE.md",
    type: "text/markdown; charset=utf-8",
    filename: "PULL_REQUEST_TEMPLATE.md",
  },
  "app-control": {
    file: "app-control.md",
    type: "text/markdown; charset=utf-8",
    filename: "app-control.md",
  },
}

export async function GET(request: Request) {
  const name = new URL(request.url).searchParams.get("artifact") ?? ""
  const artifact = ARTIFACTS[name]
  if (!artifact) {
    return NextResponse.json(
      { error: "unknown artifact", available: Object.keys(ARTIFACTS) },
      { status: 404 },
    )
  }

  const absolute = path.join(BUNDLES, artifact.file)
  if (!absolute.startsWith(BUNDLES + path.sep)) {
    return NextResponse.json({ error: "invalid path" }, { status: 400 })
  }

  try {
    const bytes = await readFile(absolute)
    return new NextResponse(bytes, {
      status: 200,
      headers: {
        "Content-Type": artifact.type,
        "Content-Disposition": `attachment; filename="${artifact.filename}"`,
        "Content-Length": String(bytes.byteLength),
        "Cache-Control": "public, max-age=3600",
      },
    })
  } catch {
    return NextResponse.json(
      { error: `artifact not present in this build: ${artifact.file}` },
      { status: 404 },
    )
  }
}
