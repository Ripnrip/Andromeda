# PR #113 behavioral flow evidence

Behavior/source revision: `377313a8cc1a4f48a49c416cf959813442cd62db`. This packet adds documentation and rendered evidence only; it does not change production code or tests and does not create new native/e2e proof.

Editable source: [flow.mmd](flow.mmd). Static evidence: [light PNG](flow-light.png), [dark PNG](flow-dark.png). The two theme configs derive their colors from canonical `DESIGN.md` tokens; typography uses its grotesk UI family with system fallbacks.

Rendered with [Mermaid CLI](https://github.com/mermaid-js/mermaid-cli) **12.2.0**, Node **22.23.3**, and locally installed headless Chrome. Dimensions: light: 1484 × 2856 pixels; dark: 1484 × 2856 pixels. The parent task inspects the static PNGs before committing/publishing.

Replay from the repository root with Mermaid CLI 12.2.0 installed locally or through npx. If using existing Chrome, supply a local Puppeteer configuration containing its `executablePath`; this local machine configuration is deliberately not committed.

```console
npx -p @mermaid-js/mermaid-cli@12.2.0 mmdc -i docs/pr-113/flow.mmd -o docs/pr-113/flow-light.png -c docs/pr-113/theme-light.json -p <local-chrome.json> -b '#F7FBFC' -s 2 -j 1
npx -p @mermaid-js/mermaid-cli@12.2.0 mmdc -i docs/pr-113/flow.mmd -o docs/pr-113/flow-dark.png -c docs/pr-113/theme-dark.json -p <local-chrome.json> -b '#040F12' -s 2 -j 1
```

Native I/O, installed readiness, authentication/wiring and soak exclusions remain as stated in the PR's revision-pinned proof; diagrams are not those proofs.
