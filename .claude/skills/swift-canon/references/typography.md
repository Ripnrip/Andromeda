# Typography

Default to platform-native typography, which means SF Pro on Apple platforms unless the product has a deliberate brand override.

## Rules

- Prefer semantic text styles over hand-picked point sizes.
- Build hierarchy with weight, style, spacing, and layout before inventing custom fonts.
- Respect Dynamic Type and scaling behavior.

## Typical hierarchy

- `.largeTitle` / `.title`
- `.headline`
- `.body`
- `.subheadline`
- `.caption`

## Avoid

- decorative font stacks for ordinary product UI
- fixed tiny text
- arbitrary kerning/tracking everywhere
- mixing too many weights/styles in the same surface

## Review questions

- Does this look native and calm?
- Is the hierarchy clear without over-styling?
- Will it survive Dynamic Type?
- Is custom typography actually required here?
