import type React from "react"
import type { Metadata, Viewport } from "next"
import { Space_Grotesk, JetBrains_Mono, Instrument_Serif } from "next/font/google"
import { ThemeProvider } from "@/components/theme-provider"
import "./globals.css"

const spaceGrotesk = Space_Grotesk({
  subsets: ["latin"],
  variable: "--font-space-grotesk",
  display: "swap",
})

const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-jetbrains-mono",
  display: "swap",
})

const instrumentSerif = Instrument_Serif({
  subsets: ["latin"],
  weight: "400",
  style: ["normal", "italic"],
  variable: "--font-instrument-serif",
  display: "swap",
})

export const metadata: Metadata = {
  title: "Andromeda — Control the chaos · Coming soon",
  description:
    "Andromeda is a local-first, Swift-native control plane for agents, jobs, tools, models, secrets, memory, and fleet state. Six pillars behind one capability curtain.",
  icons: {
    icon: "/andromeda-icon.png",
  },
  openGraph: {
    title: "Andromeda — Control the chaos. Conceal the complexity.",
    description:
      "Every agent, every job — visible. Six pillars behind one local-first capability curtain, with Memory as the active build track.",
    type: "website",
  },
}

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: "#060a0c" },
    { media: "(prefers-color-scheme: light)", color: "#fbfcfc" },
  ],
  colorScheme: "dark light",
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html
      lang="en"
      className={`dark ${spaceGrotesk.variable} ${jetbrainsMono.variable} ${instrumentSerif.variable} bg-background`}
      suppressHydrationWarning
    >
      <body className="font-sans antialiased">
        <ThemeProvider>{children}</ThemeProvider>
      </body>
    </html>
  )
}
