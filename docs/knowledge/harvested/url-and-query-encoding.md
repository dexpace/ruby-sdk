# url-and-query-encoding

## Rules
- The operation-input projection MUST let generated code declare, per operation, an HTTP method, a path template with named placeholders, and typed projections of inputs onto path/query/header/body, with only method and path template required and the four projections defaulting to empty, and the body carried but not encoded by this seam (SEAM-26).
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:29-29` · high · sha:0adae2d6a47f</sub>
- When assembled against a base URL, path-parameter values MUST be percent-encoded as single path segments so a value cannot inject an extra slash (SEAM-27).
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:30-30` · high · sha:0adae2d6a47f</sub>
- Every path-template placeholder MUST have a supplied value, and the query MUST be RFC-3986 rendered (SEAM-27).
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:30-30` · high · sha:0adae2d6a47f</sub>
- Base-URL composition follows fixed rules: a trailing slash normalizes to one separator, an empty operation path leaves the base untouched, an existing base query is preserved with the operation query appended after it, and a base carrying a fragment or resolving to a malformed URL is rejected with a context-bearing error (SEAM-27).
  <sub>spec · `docs/product-spec/03-pluggable-seams-and-extension-model.md:30-30` · high · sha:0adae2d6a47f</sub>
- The port pins URI::RFC3986_PARSER explicitly for every parse and every resolution and never relies on URI::DEFAULT_PARSER, enforced by the same lint rule that forbids Time.parse.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:385-387` · high · sha:bf7f85fc5f18</sub>

## Constraints

## Conclusions
- No code generation is implied by the operation descriptor; the port specifies only the runtime primitive a generator would target, matching the parent project's deferral of a codegen layer.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:362-364` · high · sha:bf7f85fc5f18</sub>
- Core hand-writes one strict component encoder, with unreserved set exactly A-Za-z0-9-._~, used for path segments, query rendering, and single-component encoding, and one separate form encoder for application/x-www-form-urlencoded bodies that is plus-for-space and never claims RFC 3986 compliance, keeping the two as distinct functions with distinct tests that are never interchanged. (SEAM-27, HTTP-29, HTTP-32, HTTP-38, BODY-35)
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:374-378` · high · sha:bf7f85fc5f18</sub>
- Base-URL composition uses URI.join/URI#merge for RFC 3986 reference resolution and never re-parses a re-rendered string, because round-tripping through to_s is where percent-encoding gets normalised away.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:389-391` · high · sha:bf7f85fc5f18</sub>

## Reference
- The Ruby shape for the operation-input projection seam is a frozen Dexpace::Operation descriptor — method, template String, and a projection table mapping input keys to [:path | :query | :header | :body, name] — plus one Dexpace::Operation#build_request helper in core.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:360-363` · high · sha:bf7f85fc5f18</sub>
- None of Ruby's three built-in escapers implements RFC 3986 component encoding correctly, verified against the input "a b*~+/!()'": URI.encode_www_form_component turns space into "+" and "~" into "%7E" and leaves "*" bare; CGI.escape is form encoding by design; and URI::RFC3986_PARSER.escape leaves "/", "+", "*", and sub-delimiters unescaped because it escapes only characters outside a broad URI set. (HTTP-32, HTTP-29)
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:365-372` · high · sha:bf7f85fc5f18</sub>
- URI::DEFAULT_PARSER is a version-dependent alias — URI::RFC3986_Parser on Ruby 3.4 (verified on 3.4.10) but URI::RFC2396_Parser on 3.2 and 3.3, both within this port's supported range — so code written against DEFAULT_PARSER silently changes behaviour across the CI matrix without a code change.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:380-384` · high · sha:bf7f85fc5f18</sub>
- URI::RFC3986_PARSER has been present since Ruby 3.0, so pinning it explicitly costs nothing on the port's supported floor.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:386-387` · high · sha:bf7f85fc5f18</sub>
- URI.join("https://h/base/", "../y?q=1#f") yields "https://h/y?q=1#f" (verified).
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:389-390` · high · sha:bf7f85fc5f18</sub>
- URI preserves already-encoded octets verbatim — URI("https://h/a%2Fb?x=%26").to_s round-trips unchanged (verified) — which is what REDIR-13 needs.
  <sub>design · `docs/sdk-design-ruby/03-seam-by-seam-idiomatic-mapping.md:391-393` · high · sha:bf7f85fc5f18</sub>

## Conflicts

## Superseded
