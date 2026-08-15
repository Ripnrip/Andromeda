# Swift OpenAPI / Generated Server Code

Use contract-first generation cleanly. Generated code is an asset, not a place to freelance.

## Core rules

- Never hand-edit generated files.
- Keep the OpenAPI spec, generation config, and generated output reproducible.
- Put custom behavior in adapters, handlers, middleware, or wrappers around generated types.

## Typical flow

1. Define/update the OpenAPI document.
2. Run the Swift OpenAPI Generator plugin/tool.
3. Commit generated surfaces if the repo policy wants generated output versioned.
4. Implement server/client adapters in handwritten code.

## Boundaries

- **Generated models/routes**: mechanical contract surface
- **Handwritten adapters**: business logic, storage, auth, orchestration, framework integration
- **Framework glue**: Hummingbird/Vapor/NIO wiring, middleware, dependency injection

## Hummingbird/server notes

- Keep route registration thin.
- Translate generated request/response types at the edge.
- Do not let generated files become the place where business logic accretes.

## Review questions

- Was generated code regenerated instead of edited by hand?
- Is the spec the real source of truth?
- Are handwritten adapters clearly separated?
- Does the contract change belong in this PR or was it smuggled into a runtime fix?
