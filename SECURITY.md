# Security

Do not include credentials, databases, chat bodies, personal paths or unredacted
reader logs in a public issue or pull request.

For a security issue, use [GitHub's private vulnerability reporting](https://github.com/gambinoga/codex-dock/security/advisories/new)
when enabled. If unavailable, ask the maintainer for a private reporting channel
without publishing exploit details. There is currently no guaranteed response SLA.

Codex Dock reads local metadata. It must not write Codex databases, bypass trust,
automatically grant macOS permissions, or send data to third parties.
