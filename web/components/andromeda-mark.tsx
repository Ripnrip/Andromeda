import Image from "next/image"

export function AndromedaMark({
  size = 40,
  glow = true,
  className = "",
}: {
  size?: number
  glow?: boolean
  className?: string
}) {
  return (
    <span
      className={`relative inline-flex items-center justify-center ${className}`}
      style={{ width: size, height: size }}
    >
      {glow && (
        <span
          aria-hidden
          className="absolute inset-0 rounded-full"
          style={{
            background: "radial-gradient(circle, oklch(0.83 0.14 190 / 0.45), transparent 70%)",
            filter: "blur(8px)",
          }}
        />
      )}
      <Image
        src="/andromeda-logo.png"
        alt="Andromeda"
        width={size}
        height={size}
        className="relative object-contain"
        priority
      />
    </span>
  )
}
