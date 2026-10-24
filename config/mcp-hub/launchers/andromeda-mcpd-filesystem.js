// andromeda-mcpd-filesystem — named launcher for the shared filesystem
// upstream. The allowed directories are NOT pinned here: the hub spawns
// this launcher with the config's allowed-directory arguments appended
// (see config/mcp-hub/servers.example.json — the sandbox is hub-owned).
//
// Call main() explicitly. server-filesystem only auto-starts when
// process.argv[1] is this module (isEntryPoint). A require/import from
// this launcher leaves argv[1] pointing here, so the process exits 0
// without ever listening — the hub then burns its restart budget.
process.title = "andromeda-mcpd-filesystem";
import("/Users/admin/.npm/_npx/a3241bba59c344f5/node_modules/@modelcontextprotocol/server-filesystem/dist/index.js")
    .then((mod) => mod.main())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
