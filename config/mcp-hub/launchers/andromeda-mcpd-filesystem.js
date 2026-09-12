// andromeda-mcpd-filesystem — named launcher for the shared filesystem
// upstream. The allowed directories are NOT pinned here: the hub spawns
// this launcher with the config's allowed-directory arguments appended
// (see config/mcp-hub/servers.example.json — the sandbox is hub-owned).
process.title = "andromeda-mcpd-filesystem";
require("/Users/admin/.npm/_npx/a3241bba59c344f5/node_modules/@modelcontextprotocol/server-filesystem/dist/index.js");
