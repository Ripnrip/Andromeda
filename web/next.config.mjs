import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const __dirname = dirname(fileURLToPath(import.meta.url))

/** @type {import('next').NextConfig} */
const nextConfig = {
  eslint: { ignoreDuringBuilds: true },
  typescript: { ignoreBuildErrors: true },
  images: { unoptimized: true },
  // The Next app is an npm workspace under the Swift repo root.
  // Pin the tracing root so Next stops guessing between lockfiles.
  outputFileTracingRoot: join(__dirname, ".."),
  outputFileTracingIncludes: {
    "/api/lessons/download": ["./app/api/lessons/download/bundles/**/*"],
  },
}

export default nextConfig
