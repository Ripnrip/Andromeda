// andromeda-mcpd-memory — named launcher for the shared memory upstream.
//
// Call main() explicitly. server-memory only auto-starts when argv[1] is
// this module (isMainModule). Importing it from the launcher exits 0
// immediately and the hub counts a death.
process.title = "andromeda-mcpd-memory";
import("/Users/admin/.npm/_npx/15b07286cbcc3329/node_modules/@modelcontextprotocol/server-memory/dist/index.js")
    .then((mod) => mod.main())
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
