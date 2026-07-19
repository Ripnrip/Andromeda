import type React from "react"
import type { Metadata, Viewport } from "next"
import { Space_Grotesk, Geist_Mono } from "next/font/google"
import "./globals.css"

const spaceGrotesk = Space_Grotesk({
  subsets: ["latin"],
  variable: "--font-space-grotesk",
  display: "swap",
})

const geistMono = Geist_Mono({
  subsets: ["latin"],
  variable: "--font-geist-mono",
  display: "swap",
})

export const metadata: Metadata = {
  title: "Andromeda — Local-first Swift control plane",
  description:
    "Andromeda owns Memory, MCP host, Skills, LLM proxy, Secrets broker, and Fleet runtime behind a capability curtain. Local-first, Swift-native, graph-aware.",
  icons: {
    icon: "/andromeda-icon.png",
  },
}

export const viewport: Viewport = {
  themeColor: "#060a0c",
  colorScheme: "dark",
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" className={`${spaceGrotesk.variable} ${geistMono.variable} bg-background`}>
      <body className="font-sans antialiased">{children}</body>
    </html>
  )
}
