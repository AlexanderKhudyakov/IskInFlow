# MCP-First Tooling Rule

Before taking any implementation action, always inspect available MCP servers and tools in the current environment.

## Required behavior

1. Enumerate available MCP servers/tools first.
2. Prefer MCP tools over ad-hoc/manual approaches when they are applicable.
3. If a relevant MCP tool exists, use it for discovery, validation, execution, and verification steps.
4. Fall back to non-MCP methods only when no suitable MCP capability is available.
5. When falling back, explicitly state why MCP was not used.

## Agent policy

This is a mandatory default: check MCP availability first, then act.
