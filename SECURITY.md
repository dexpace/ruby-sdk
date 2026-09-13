# Security Policy

## Supported versions

Nothing has shipped yet: there is no `gems/` directory in this repository yet, and once it exists
every gem in it will start at `0.0.0` with nothing published to RubyGems. There is therefore no
released version to support and no patched release to point at. Until the first release, the
supported revision is the tip of `mvp` — report against a commit SHA.

## Reporting a vulnerability

Please **do not** open a public issue for security vulnerabilities.

Instead, report privately by email to
[oaljarrah@dexpace.org](mailto:oaljarrah@dexpace.org) with `[SECURITY]` in
the subject line.

Include what you can of the following:

- The affected gem(s), and the commit SHA and Ruby version you reproduced against
- A description of the vulnerability and its impact
- Steps or a proof of concept to reproduce it

You can expect an acknowledgement within a few days. Please allow time for
a fix to land and be released before disclosing publicly.

## Scope notes

- The SDK is a **toolkit**, not a service: `dexpace-core` will execute no network I/O of its own.
  Transport-level vulnerabilities (TLS, connection handling, message parsing) belong to whatever
  sits behind the `Transport` seam — `net-http` for `dexpace-transport-net_http`, or `async-http`
  for `dexpace-transport-async_http` — report those upstream.
- In scope here, once it exists: credential handling and challenge parsing, header/URL redaction
  in logging, redirect safety (`Authorization` stripped on every re-issue, `Cookie` and
  `Proxy-Authorization` cross-origin), and body capture. See
  `docs/sdk-design-ruby/06-retry-redirect-and-authentication.md` and
  `docs/sdk-design-ruby/04-domain-model-construction.md` for where these will live once built.
