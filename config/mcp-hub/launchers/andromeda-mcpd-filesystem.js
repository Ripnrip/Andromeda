// andromeda-mcpd-filesystem — named launcher for the shared filesystem
// upstream (§2.2: process.title sets the Activity Monitor name; measured
// working on macOS 26.6.2). The real entrypoint is resolved at install
// time and REQUIRED from its on-disk path — no anonymous eval blobs.
process.title = "andromeda-mcpd-filesystem";
require("/Users/admin/.npm/_npx/a3241bba59c344f5/node_modules/@modelcontextprotocol/server-filesystem/dist/index.js");
