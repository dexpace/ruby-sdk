# Security Policy

## Supported versions

Nothing has been published yet. The six gems under `gems/` are built, but every one is at `0.0.0`
and none is on RubyGems, so there is no released version to support and no patched release to
point at. Until the first release, the supported revision is the tip of `main` — report against a
commit SHA. Once a version is published, this section will name the supported release lines.

## Reporting a vulnerability

Please **do not** open a public issue, pull request or discussion for a security vulnerability.

Report it privately by email to
[oaljarrah@dexpace.org](mailto:oaljarrah@dexpace.org) with `[SECURITY]` in
the subject line.

Include what you can of the following:

- The affected gem(s), and the commit SHA and Ruby version you reproduced against
- A description of the vulnerability and its impact
- Steps or a proof of concept to reproduce it

You can expect an acknowledgement within a few days. Please allow time for
a fix to land and be released before disclosing publicly.

## Scope

The SDK is a **toolkit**: `dexpace-core` performs no network I/O of its own. In scope here:

- **Credential handling** — the Basic, Digest, API-key and bearer-token credentials and stampers,
  RFC 7235 challenge parsing, and any path by which a credential reaches a log, an exception
  message, `#inspect` or `pp` output.
- **Redaction** — URL, query and header redaction in logging and tracing, including a credential
  surviving in userinfo or in a header outside the allow-list.
- **Redirect safety** — `Authorization` stripped before every re-issue, `Cookie` and
  `Proxy-Authorization` stripped cross-origin, the HTTPS guard on credentials, and scheme
  downgrades.
- **Request integrity** — header-name and header-value validation at the wire boundary (CRLF or
  request-splitting), and URL handling.
- **Resource exhaustion** — the SDK's own bounded buffers, stream line and event caps, pagination
  caps, and bounded maps.
- **The two transport adapters** — `dexpace-transport-net_http` and
  `dexpace-transport-async_http` — as far as their own mapping, TLS settings and cancellation go.

Vulnerabilities in `net-http`, `async-http` or `json` themselves belong upstream; report them there,
and tell us if the SDK needs a dependency floor raised.
