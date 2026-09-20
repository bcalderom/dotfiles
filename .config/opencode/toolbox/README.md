# Private MCP Toolbox

Target-specific wrappers and diagnostic queries belong in `toolbox/local/`.
That directory is ignored because it can contain infrastructure names, database
schemas, hosts, and operational queries that are unsuitable for a public
dotfiles repository.

Use the files under `examples/` as public, read-only starting points. Copy and
adapt them under `local/`, then declare the resulting MCP server in the ignored
`../config.local.json` overlay. Never place credentials in toolbox files; keep
them under `../secrets/` with directory mode `0700` and file mode `0600`.
