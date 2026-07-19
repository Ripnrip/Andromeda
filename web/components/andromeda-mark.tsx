import Image from "next/image"

export function AndromedaMark({
  size = 40,
  glow = true,
  rounded = true,
  className = "",
}: {
  size?: number
  glow?: boolean
  rounded?: boolean
  className?: string
}) {
  return (
    <span
      className={`relative inline-flex shrink-0 items-center justify-center ${className}`}
      style={{ width: size, height: size }}
    >
      {glow && (
        <span
          aria-hidden
          className="absolute inset-0"
          style={{
            background: "radial-gradient(circle, oklch(0.83 0.14 190 / 0.35), transparent 70%)",
            filter: "blur(10px)",
            transform: "scale(1.15)",
          }}
        />
      )}
      <Image
        src="/andromeda-icon.png"
        alt="Andromeda"
        width={size}
        height={size}
        className={`relative object-cover ${rounded ? "rounded-[22%]" : ""}`}
        style={{ boxShadow: rounded ? "0 0 0 1px oklch(0.83 0.14 190 / 0.15)" : undefined }}
        priority
      />
    </span>
  )
}
