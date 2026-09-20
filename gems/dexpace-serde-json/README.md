# dexpace-serde-json

Part of the [dexpace Ruby SDK](../../README.md): an HTTP-client toolkit, not an HTTP client.
This gem is the wire-codec seam's reference implementation, over `json`.

**Status: built by phase 7a, at `0.0.0`, unpublished.** `lib/` holds `Dexpace::Serde::JSON::Codec`
— the seam's six methods over one private `JSON::Coder` per instance — the two factories
`Dexpace::Serde::JSON.default` (a fresh codec on every call) and `.build(options)` (over a five-key
option allowlist), the `json >= 2.19.9` floor asserted at require time as `Dexpace::SeamError`, and
the seam registration under `:json`. The as-built page is
[`docs/sdk-documentation/serde.md`](../../docs/sdk-documentation/serde.md); the per-requirement
proof is
[`docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization-checklist.md`](../../docs/work/mvp/phase7/phase7a/2026-09-10-phase7a-serialization-checklist.md).

## Install

```ruby
# Gemfile
gem "dexpace-serde-json"
```

## The smallest thing that works today

```ruby
require "dexpace/serde/json"

class Pet
  attr_reader :name

  def self.dexpace_load(parsed, ctx)
    new(ctx.string!(ctx.object!(parsed)["name"], key: "name"))
  end

  def initialize(name) = @name = name
  def dexpace_dump = { "name" => @name }
end

codec = Dexpace::Serde::JSON.default
codec.dump_string(Pet.new("Ré"))                       # => "{\"name\":\"Ré\"}"
source = Dexpace::IO::BufferedSource.of_bytes("{\"name\":\"Ré\"}".b)
codec.load(source, Pet).name                           # => "Ré"
Dexpace::Serde.registered_keys                         # => [:json]
```

The witness protocol (`.dexpace_load` / `#dexpace_dump`), the decode context, the combinators, the
`Tristate` PATCH type and the two response handlers are `dexpace-core`'s; this gem supplies the
codec they run through.

## Depends on

`dexpace-core`, and `json >= 2.19.9` -- the one third-party gem `NFR-2` budgets for this adapter.
That floor lives in this gemspec and nowhere else: it is the first `json` with `JSON::Coder`, the
per-instance engine the codec is built on, and the one carrying the 2026 advisories. An unbundled
`require "dexpace/serde/json"` on a stock Ruby 3.3 or 3.4 activates the interpreter's default
`json` (2.7.2 / 2.9.1), so the entry file asserts the floor itself rather than failing later inside
the codec.

## Where to read next

- `docs/sdk-documentation/serde.md` -- the layer and the codec, as built.
- `docs/sdk-documentation/architecture.md` -- how the gems compose and which one to install.
- `docs/sdk-design-ruby/02-gem-and-workspace-layout.md` -- the gem layout and the
  zero-dependency invariant every gem here is built under.
