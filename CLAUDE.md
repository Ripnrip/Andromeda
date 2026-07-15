# Claude Agent Guide

Claude-based agents working on Andromeda should:

1. Read `ANDROMEDA-CHARTER.md` first.
2. Inspect relevant ADRs and runbooks before implementation once they exist.
3. Search session memory and project docs before rediscovering prior decisions.
4. Use Swift-native implementation patterns and strict concurrency.
5. Update documentation in the same change when behavior, schema, configuration, or operational expectations change.
6. Run targeted tests before broad tests.
7. Avoid reading unrelated files merely to accumulate context.
8. Never add Bash automation files or hidden launch/watchdog behavior.
9. Surface every important background operation through visible UI/status plus telemetry.
