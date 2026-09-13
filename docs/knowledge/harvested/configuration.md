# configuration

## Rules
- A configuration value lookup resolves in strict order—an explicit override for the exact key, then the environment source queried by the exact key name, then the system-property source queried by the normalized key name, then the caller-supplied default which may be absent. (CFG-1)
  <sub>spec · `docs/product-spec/16-configuration.md:7-7` · high · sha:367e27ec6481</sub>
- An environment value that is present but empty is treated as absent, so the lookup falls through to the property layer. (CFG-2)
  <sub>spec · `docs/product-spec/16-configuration.md:8-8` · high · sha:367e27ec6481</sub>
- The property layer is queried under a normalized key derived by lowercasing and replacing every underscore with a dot (e.g. MAX_RETRY_ATTEMPTS becomes max.retry.attempts), while the override and environment layers use the original key name. (CFG-3)
  <sub>spec · `docs/product-spec/16-configuration.md:9-9` · high · sha:367e27ec6481</sub>
- A separate raw property accessor looks up by the exact key name without env-to-property normalization, so camelCase property-only keys such as https.proxyHost resolve with casing preserved. (CFG-4)
  <sub>spec · `docs/product-spec/16-configuration.md:10-10` · high · sha:367e27ec6481</sub>
- The typed accessors (integer, boolean, duration) must resolve the raw value through the same layered lookup as the string accessor before parsing, must not read only the override map or skip the environment/property layers, and apply the typed default only when the layered lookup yields no value. (CFG-38)
  <sub>spec · `docs/product-spec/16-configuration.md:11-11` · high · sha:367e27ec6481</sub>
- Typed accessors must never throw on missing or unparseable values, with the integer accessor returning the default when absent or not a valid integer (negative integers are valid and returned as-is) and the duration accessor returning the default on any parse failure. (CFG-5)
  <sub>spec · `docs/product-spec/16-configuration.md:15-15` · high · sha:367e27ec6481</sub>
- The boolean accessor is strict, recognizing only case-insensitive "true"/"false"; any other value such as "1", "0", "yes", "no", "on", or "off" falls through to the default. (CFG-6)
  <sub>spec · `docs/product-spec/16-configuration.md:16-16` · high · sha:367e27ec6481</sub>
- The duration accessor accepts ISO-8601 durations (leading P/p), shorthand <number><unit> forms (units ms, s, m, h, d, case-insensitive), and a bare number interpreted as milliseconds, rejecting a negative duration and an unknown unit by returning the default. (CFG-7)
  <sub>spec · `docs/product-spec/16-configuration.md:17-17` · high · sha:367e27ec6481</sub>
- A built configuration is immutable and safe to share without external synchronization because the override map is defensively copied at build time so later builder mutation cannot alter a built instance. (CFG-8)
  <sub>spec · `docs/product-spec/16-configuration.md:21-21` · high · sha:367e27ec6481</sub>
- Deriving a reconfigured configuration is copy-on-write, producing a new instance with the mutator applied while leaving the receiver unchanged; the override map is copied before the mutator runs while the environment and property source seams are inherited by reference unless the mutator replaces them. (CFG-9)
  <sub>spec · `docs/product-spec/16-configuration.md:22-22` · high · sha:367e27ec6481</sub>
- Removing an override drops only the override layer so a subsequent lookup falls through to env/property/default as if the override never existed, must not force the key to resolve to null, and removing a key with no override is a no-op. (CFG-10)
  <sub>spec · `docs/product-spec/16-configuration.md:23-23` · high · sha:367e27ec6481</sub>
- The environment and property sources are substitutable seams (injectable functions from key name to optional string) so tests can supply hermetic lookups without touching the real environment, while production defaults delegate to the platform environment and system properties. (CFG-11)
  <sub>spec · `docs/product-spec/16-configuration.md:24-24` · high · sha:367e27ec6481</sub>
- Configuration builders should be usable single-threaded only; the immutability guarantee applies to the built configuration, not to an in-progress builder. (CFG-12)
  <sub>spec · `docs/product-spec/16-configuration.md:25-25` · high · sha:367e27ec6481</sub>
- A process-wide global configuration slot should be provided with last-write-wins replacement and safe publication, defaulting to an empty configuration. (CFG-13)
  <sub>spec · `docs/product-spec/16-configuration.md:26-26` · high · sha:367e27ec6481</sub>
- Passing a null or absent required argument to a mutating configuration operation (override key or value, source function, derive mutator, global-config setter) must fail fast rather than storing a null, though documented-nullable optional slots such as proxy credentials, challenge handler, and lookup default may be null. (CFG-37)
  <sub>spec · `docs/product-spec/16-configuration.md:28-28` · high · sha:367e27ec6481</sub>
- The proxy model is immutable and carries the proxy type (HTTP, SOCKS4, SOCKS5), socket address, an ordered list of non-proxy host glob patterns, optional credentials, an optional challenge-handler slot, and an explicit bypass-all flag, and its string rendering must mask credentials. (CFG-22)
  <sub>spec · `docs/product-spec/16-configuration.md:42-42` · high · sha:367e27ec6481</sub>
- The host-bypass decision short-circuits to true when bypass-all is set, otherwise returning true if the host matches any configured glob, where glob conversion treats * as any run and ? as one character, escapes regex metacharacters, requires a full-string match, and matches case-insensitively. (CFG-23)
  <sub>spec · `docs/product-spec/16-configuration.md:43-43` · high · sha:367e27ec6481</sub>
- Resolving proxy options from configuration follows a fixed precedence and must never throw on malformed input (invalid config yields null plus a warning): system properties are checked first, preferring https.proxyHost over http.proxyHost with the port read from the same layer as the chosen host and credentials read only from https.proxyUser/https.proxyPassword with no http.* fallback; otherwise the env URL HTTPS_PROXY is preferred over HTTP_PROXY and parsed as scheme://user:pass@host:port. (CFG-24)
  <sub>spec · `docs/product-spec/16-configuration.md:44-44` · high · sha:367e27ec6481</sub>
- The proxy port must be explicit and within the range 0-65535; a missing, non-numeric, or out-of-range port yields null with no default-port guessing, and an absent port in a proxy URL is treated as invalid. (CFG-25)
  <sub>spec · `docs/product-spec/16-configuration.md:45-45` · high · sha:367e27ec6481</sub>
- The non-proxy host list is resolved with the system property (pipe-separated) winning over the environment variable (comma-separated), both honoring a backslash escape preceding the literal separator and trimming tokens, following the order split, drop-empty, unescape, then trim. (CFG-26)
  <sub>spec · `docs/product-spec/16-configuration.md:46-46` · high · sha:367e27ec6481</sub>
- When the resolved non-proxy configuration is exactly a single bare *, it is interpreted as bypass-all represented by the explicit bypass-all flag (not as a literal * entry), causing resolution to return null so the caller routes directly, while a * inside a multi-entry list is a normal any-host glob. (CFG-27)
  <sub>spec · `docs/product-spec/16-configuration.md:47-47` · high · sha:367e27ec6481</sub>
- A convenience resolver may read proxy options from the global configuration, but the environment must be consulted only when a resolver is explicitly invoked, since nothing may read proxy configuration implicitly at startup. (CFG-28)
  <sub>spec · `docs/product-spec/16-configuration.md:48-48` · high · sha:367e27ec6481</sub>
- RFC 1123 date parsing is tolerant, accepting case-insensitive month names and zone tokens of GMT, UTC, +0000, or +00:00 (all normalized to zero offset), with the leading weekday token treated as informational only and stripped rather than validated against the date. (CFG-30)
  <sub>spec · `docs/product-spec/16-configuration.md:53-53` · high · sha:367e27ec6481</sub>
- RFC 1123 parsing is strict on the day-of-month-onward grammar, so blank input must fail and a form missing the comma after the weekday must fail. (CFG-31)
  <sub>spec · `docs/product-spec/16-configuration.md:54-54` · high · sha:367e27ec6481</sub>
- The non-blocking UUID generator produces type-4 UUIDs with the correct RFC 4122 layout (version 4, IETF variant), is usable concurrently without shared mutable state via a non-blocking per-thread PRNG, and its output must be treated as non-cryptographic by callers. (CFG-32)
  <sub>spec · `docs/product-spec/16-configuration.md:55-55` · high · sha:367e27ec6481</sub>
- Deep value-equality helpers compare by content—arrays element-by-element (object arrays recursing for nested/multi-dimensional arrays, primitive arrays comparing by element value) and non-arrays via ordinary equality—and both helpers are null-safe (two nulls are equal, null hashes to zero) with equals and hashCode mutually consistent. (CFG-33)
  <sub>spec · `docs/product-spec/16-configuration.md:56-56` · high · sha:367e27ec6481</sub>
- Deep equality follows floating-point array semantics where NaN equals NaN and +0.0 does not equal -0.0 for primitive and boxed float/double arrays, with hashing matching, and an object array is never equal to a primitive array of the same numeric values. (CFG-34)
  <sub>spec · `docs/product-spec/16-configuration.md:57-57` · high · sha:367e27ec6481</sub>
- A static build/runtime descriptor should expose the SDK version and host runtime identity resolved once at load time, each falling back to a non-blank "unknown" when unavailable, and should provide a default ordered identity-token list (SDK token then runtime token) where every token must be non-blank. (CFG-36)
  <sub>spec · `docs/product-spec/16-configuration.md:59-59` · high · sha:367e27ec6481</sub>

## Constraints

## Conclusions
- The configuration subsystem's porting goal is behavioral parity across ports—identical precedence, never-throw lookup, immutability, and substitutable env/property/time seams—so conformance tests run hermetically.
  <sub>spec · `docs/product-spec/16-configuration.md:3-3` · medium · sha:367e27ec6481</sub>
- Ruby has no ambient key/value store equivalent to a -D system property flag; rather than fabricating a fake system-property source from a second ENV lookup or dropping to three tiers, the port substitutes the process-wide defaults installed by Dexpace.configure { |c| ... } as a genuinely different third-tier source.
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:153-157` · high · sha:180a9abbb69f</sub>
- The configuration precedence order is deliberately preserved from the specification (call-site override > ENV > configure defaults > caller default) rather than following the common Ruby convention (call-site > configure > ENV > default), because the specification's ordering is normative and a conformance test written against it would observe the difference. (CFG-1)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:159-162` · high · sha:180a9abbb69f</sub>
- Letting a deployment's environment variable override a default written in application code is considered the 12-factor property adopters actually want, since it lets a timeout or proxy be adjusted in staging without a redeploy, whereas a configure block silently beating ENV would turn every such knob into a code change.
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:162-166` · high · sha:180a9abbb69f</sub>
- The non-cryptographic UUID generator and the CSPRNG requirement are kept as two separate code paths as the specification insists, even though Ruby's SecureRandom lacks the blocking-entropy problem that originally motivated the split, because keeping them separate costs nothing and preserves the ability to substitute either independently. (CFG-32, XCUT-21)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:190-193` · high · sha:180a9abbb69f</sub>

## Reference
- The configuration subsystem should expose stable well-known key constants for the retry-attempt cap, log level, and standard proxy variables (HTTP_PROXY, HTTPS_PROXY, NO_PROXY). (CFG-14)
  <sub>spec · `docs/product-spec/16-configuration.md:27-27` · high · sha:367e27ec6481</sub>
- RFC 1123 date formatting emits the canonical HTTP-date form with a zero-padded two-digit day-of-month and a literal GMT, rendered in UTC (e.g. Sun, 06 Nov 1994 08:49:37 GMT). (CFG-29)
  <sub>spec · `docs/product-spec/16-configuration.md:52-52` · high · sha:367e27ec6481</sub>
- A copy-on-write derive produces a reconfigured configuration from an existing one by applying a mutator to a prefilled builder while leaving the receiver unchanged, copying the override map up front while sharing pure read seams by reference.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:17` · high · sha:f0b3d2058626</sub>
- Deep value equality is content-based equals/hashCode comparison that recurses into arrays element-by-element while falling back to ordinary equality for non-arrays, keeping equals and hashCode mutually consistent including NaN-equals-NaN and +0.0-unequal-to-(-0.0) array semantics.
  <sub>spec · `docs/product-spec/appendix-a-glossary.md:23` · high · sha:f0b3d2058626</sub>
- Configuration resolution follows four-layer precedence: explicit override, then environment variable, then normalized property, then default. (CFG-1, CFG-2, CFG-3, CFG-4, CFG-38)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:50` · high · sha:0451cc7f3bb4</sub>
- An empty environment variable value is treated as absent for configuration resolution. (CFG-1, CFG-2, CFG-3, CFG-4, CFG-38)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:50` · high · sha:0451cc7f3bb4</sub>
- Configuration property keys are normalized. (CFG-1, CFG-2, CFG-3, CFG-4, CFG-38)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:50` · high · sha:0451cc7f3bb4</sub>
- A raw property accessor is available that bypasses key normalization. (CFG-1, CFG-2, CFG-3, CFG-4, CFG-38)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:50` · high · sha:0451cc7f3bb4</sub>
- Typed configuration accessors resolve through the full layered lookup. (CFG-1, CFG-2, CFG-3, CFG-4, CFG-38)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:50` · high · sha:0451cc7f3bb4</sub>
- Integer and duration configuration accessors never throw, and negative values are valid for them. (CFG-5, CFG-6, CFG-7)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:51` · high · sha:0451cc7f3bb4</sub>
- Strict boolean configuration parsing accepts only the literal values true and false. (CFG-5, CFG-6, CFG-7)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:51` · high · sha:0451cc7f3bb4</sub>
- Duration configuration values may be specified as ISO-8601, shorthand notation, or a bare number of milliseconds, with negative durations rejected. (CFG-5, CFG-6, CFG-7)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:51` · high · sha:0451cc7f3bb4</sub>
- A built configuration is immutable, with its override map copied at build time. (CFG-8, CFG-9, CFG-10, CFG-11, CFG-12, CFG-13, CFG-14, CFG-37)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:52` · high · sha:0451cc7f3bb4</sub>
- Deriving a new configuration from an existing one is copy-on-write, sharing the source's read seams. (CFG-8, CFG-9, CFG-10, CFG-11, CFG-12, CFG-13, CFG-14, CFG-37)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:52` · high · sha:0451cc7f3bb4</sub>
- Removing a configuration value drops it only from the override layer. (CFG-8, CFG-9, CFG-10, CFG-11, CFG-12, CFG-13, CFG-14, CFG-37)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:52` · high · sha:0451cc7f3bb4</sub>
- The environment and property lookup seams in the configuration layer are substitutable. (CFG-8, CFG-9, CFG-10, CFG-11, CFG-12, CFG-13, CFG-14, CFG-37)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:52` · high · sha:0451cc7f3bb4</sub>
- The configuration builder has a single-threaded usage contract. (CFG-8, CFG-9, CFG-10, CFG-11, CFG-12, CFG-13, CFG-14, CFG-37)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:52` · high · sha:0451cc7f3bb4</sub>
- The global configuration slot follows last-write-wins semantics. (CFG-8, CFG-9, CFG-10, CFG-11, CFG-12, CFG-13, CFG-14, CFG-37)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:52` · high · sha:0451cc7f3bb4</sub>
- Well-known configuration keys are exposed as named constants. (CFG-8, CFG-9, CFG-10, CFG-11, CFG-12, CFG-13, CFG-14, CFG-37)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:52` · high · sha:0451cc7f3bb4</sub>
- A null value passed for a required configuration argument is rejected. (CFG-8, CFG-9, CFG-10, CFG-11, CFG-12, CFG-13, CFG-14, CFG-37)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:52` · high · sha:0451cc7f3bb4</sub>
- A clock seam exposes now(), a monotonic clock, and an interruptible sleep, with a shared default implementation. (CFG-15, CFG-16, CFG-17, CFG-18, CFG-19, CFG-20, CFG-21)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:53` · high · sha:0451cc7f3bb4</sub>
- The monotonic clock is non-decreasing, and the wall clock must not be used for measuring elapsed time. (CFG-15, CFG-16, CFG-17, CFG-18, CFG-19, CFG-20, CFG-21)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:53` · high · sha:0451cc7f3bb4</sub>
- The sleep operation rejects a negative duration and honors cancellation by re-asserting the interrupt/cancel flag. (CFG-15, CFG-16, CFG-17, CFG-18, CFG-19, CFG-20, CFG-21)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:53` · high · sha:0451cc7f3bb4</sub>
- A non-blocking scheduled delay cancels its underlying task when cancelled. (CFG-15, CFG-16, CFG-17, CFG-18, CFG-19, CFG-20, CFG-21)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:53` · high · sha:0451cc7f3bb4</sub>
- Async-wrapper exception unwrapping in the configuration/clock seam is cycle-safe. (CFG-15, CFG-16, CFG-17, CFG-18, CFG-19, CFG-20, CFG-21)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:53` · high · sha:0451cc7f3bb4</sub>
- An interruptible task's future leaves a clean interrupt state. (CFG-15, CFG-16, CFG-17, CFG-18, CFG-19, CFG-20, CFG-21)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:53` · high · sha:0451cc7f3bb4</sub>
- An orphaned closeable result is closed when discarded. (CFG-15, CFG-16, CFG-17, CFG-18, CFG-19, CFG-20, CFG-21)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:53` · high · sha:0451cc7f3bb4</sub>
- The proxy configuration model is immutable and masks its credentials. (CFG-22, CFG-23, CFG-24, CFG-25, CFG-26, CFG-27, CFG-28)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:54` · high · sha:0451cc7f3bb4</sub>
- Proxy bypass glob matching is a full-string, case-insensitive match. (CFG-22, CFG-23, CFG-24, CFG-25, CFG-26, CFG-27, CFG-28)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:54` · high · sha:0451cc7f3bb4</sub>
- Proxy resolution precedence never throws, resolves host and port from the same configuration layer, and only applies credentials over HTTPS. (CFG-22, CFG-23, CFG-24, CFG-25, CFG-26, CFG-27, CFG-28)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:54` · high · sha:0451cc7f3bb4</sub>
- A proxy port must be either an explicit in-range value or null. (CFG-22, CFG-23, CFG-24, CFG-25, CFG-26, CFG-27, CFG-28)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:54` · high · sha:0451cc7f3bb4</sub>
- The non-proxy host list has defined precedence rules and escape handling. (CFG-22, CFG-23, CFG-24, CFG-25, CFG-26, CFG-27, CFG-28)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:54` · high · sha:0451cc7f3bb4</sub>
- A single bare `*` in the non-proxy list bypasses the proxy for all hosts. (CFG-22, CFG-23, CFG-24, CFG-25, CFG-26, CFG-27, CFG-28)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:54` · high · sha:0451cc7f3bb4</sub>
- Environment-based proxy resolution is opt-in. (CFG-22, CFG-23, CFG-24, CFG-25, CFG-26, CFG-27, CFG-28)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:54` · high · sha:0451cc7f3bb4</sub>
- Date formatting follows RFC 1123 canonical form. (CFG-29, CFG-30, CFG-31, CFG-32, CFG-33, CFG-34, CFG-35, CFG-36)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:55` · high · sha:0451cc7f3bb4</sub>
- Date parsing is tolerant of informational weekday text and recognized timezone aliases, but strict on all other components. (CFG-29, CFG-30, CFG-31, CFG-32, CFG-33, CFG-34, CFG-35, CFG-36)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:55` · high · sha:0451cc7f3bb4</sub>
- UUID generation in the configuration layer is non-blocking, non-cryptographic, and type-4. (CFG-29, CFG-30, CFG-31, CFG-32, CFG-33, CFG-34, CFG-35, CFG-36)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:55` · high · sha:0451cc7f3bb4</sub>
- Deep value equality is content-based and null-safe, treats NaN as equal to itself, distinguishes signed zero, and is kind-distinct for arrays. (CFG-29, CFG-30, CFG-31, CFG-32, CFG-33, CFG-34, CFG-35, CFG-36)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:55` · high · sha:0451cc7f3bb4</sub>
- A shared retryability classifier is used wherever retryability classification is implemented. (CFG-29, CFG-30, CFG-31, CFG-32, CFG-33, CFG-34, CFG-35, CFG-36)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:55` · high · sha:0451cc7f3bb4</sub>
- The build/runtime descriptor falls back to a non-blank "unknown" value rather than an empty string. (CFG-29, CFG-30, CFG-31, CFG-32, CFG-33, CFG-34, CFG-35, CFG-36)
  <sub>spec · `docs/product-spec/appendix-b-conformance-test-checklist.md:55` · high · sha:0451cc7f3bb4</sub>
- Configuration resolution fixes four tiers: explicit override, environment variable by exact key, a system-property source by normalised key, then the caller default. (CFG-1)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:152-153` · high · sha:180a9abbb69f</sub>
- An application needing its programmatic value to beat a deployment's environment variable can pass it as an explicit per-client or per-call override, which is the tier that wins over ENV. (CFG-3, CFG-4)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:166-168` · high · sha:180a9abbb69f</sub>
- The normalised-key accessor and the raw exact-name accessor both survive as distinct methods; the raw accessor is what lets an application set a https.proxyHost-style key with its casing intact, which the normalising accessor would mangle. (CFG-3, CFG-4, CFG-24)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:168-170` · high · sha:180a9abbb69f</sub>
- The proxy configuration model reads the configure tier first and falls back to HTTPS_PROXY/HTTP_PROXY environment variables, preserving the same precedence shape as general configuration with a Ruby-native source. (CFG-24, CFG-22, CFG-28)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:170-173` · high · sha:180a9abbb69f</sub>
- Dexpace.configure yields a mutable staging object and atomically replaces a single frozen Configuration reference under a Thread::Mutex; readers take no lock and read one reference that can never change under them because it is frozen. (CFG-8, CFG-13)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:175-177` · high · sha:180a9abbb69f</sub>
- Configuration derivation is copy-on-write, with the override map copied before the mutator runs and the source seams (env/property lookup functions) inherited by reference. (CFG-8, CFG-13, CFG-9, CFG-11)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:177-178` · high · sha:180a9abbb69f</sub>
- Environment and property sources are injectable ->(key) { ... } callables so a hermetic test never mutates real ENV, alongside a documented Dexpace.reset_config! method for the process-wide configuration slot. (CFG-9, CFG-11, CFG-5, CFG-7)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:178-180` · high · sha:180a9abbb69f</sub>
- The never-throw boolean configuration accessor recognises only case-insensitive true/false and falls back for 1, yes, or on; the duration accessor accepts ISO-8601, a <number><unit> shorthand, or a bare number as milliseconds while rejecting negatives; and every integer parse passes base 10 explicitly. (CFG-38)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:181-184` · high · sha:180a9abbb69f</sub>
- Typed configuration accessors route through the full layered lookup rather than the override map alone, and explicit null validation is implemented as fail-fast argument guards. (CFG-38, CFG-37)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:184-186` · high · sha:180a9abbb69f</sub>
- Deep value equality for configuration values is recursive structural comparison, with NaN equal to NaN and +0.0 distinct from -0.0 for float arrays; the boxed-versus-primitive equality clause has no Ruby manifestation and is recorded as inapplicable rather than emulated. (CFG-33, CFG-34, CFG-32)
  <sub>design · `docs/sdk-design-ruby/08-instrumentation-and-configuration.md:188-190` · high · sha:180a9abbb69f</sub>

## Conflicts

## Superseded
