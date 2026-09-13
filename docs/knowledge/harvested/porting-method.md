# porting-method

## Rules
- Where a MUST-level requirement's intent is separable from its host-specific mechanism, the port must keep the intent and find the Ruby-native mechanism, and where collapsing or retiring a reference concept is what idiomatic design demands, the document must say so plainly and cite the requirement whose letter, not spirit, is being adjusted.
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:3-8` · high · sha:eb1a8a16312f</sub>
- For every MUST requirement, the porting method (P1) requires asking what invariant the requirement protects and what platform constraint made the reference express it in its particular way, because the rationale clause is usually where the constraint hides.
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:10-12` · high · sha:eb1a8a16312f</sub>
- Per working principle P2, a seam whose only job is dependency avoidance retires when the host has a runtime standard, determined by whether the type is shipped and versioned with the runtime itself rather than installed from a package registry.
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:13-17` · high · sha:eb1a8a16312f</sub>
- Per working principle P3, a seam must be kept even when embedding its implementation would be free of dependency cost, because the distinguishing question is whether the seam exists to avoid a dependency (retire it) or to avoid a policy default (keep it).
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:18-20` · high · sha:eb1a8a16312f</sub>
- Per working principle P4, two reference concepts may be collapsed into one only when the host genuinely has one, and conversely a split the host genuinely has must not be collapsed.
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:21-24` · high · sha:eb1a8a16312f</sub>
- Per working principle P5, after merging two requirements the port must quote both and show that the single primitive satisfies each clause verbatim, since a collapse that cannot be argued clause-by-clause is a narrowing in disguise.
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:25-27` · high · sha:eb1a8a16312f</sub>
- Per working principle P6, any residual difference introduced by a deviation must be named precisely using the pattern "this changes how the requirement is satisfied, not whether."
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:28-29` · high · sha:eb1a8a16312f</sub>
- Per working principle P7, whenever the host makes a requirement free, the document must say so, say why, and then state the hidden precondition under which it stops being free.
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:30-32` · high · sha:eb1a8a16312f</sub>
- Per working principle P8, when the host makes a requirement harder or impossible, the catalogue must admit it by stating the mitigation, stating that it narrows rather than eliminates the gap, and recording it as a language-level limitation.
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:33-35` · high · sha:eb1a8a16312f</sub>
- Per working principle P9, no deviation may narrow a MUST-level correctness guarantee, since deviation is permitted only in mechanism and packaging, never in observable guarantee.
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:36-38` · high · sha:eb1a8a16312f</sub>
- Per working principle P10, the document must distinguish "the spec sanctions this" from "we judged this," quoting the sanctioning text when a specification clause anticipates the port's situation directly, and otherwise treating the deviation as carrying the full burden of P5 and P9.
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:39-41` · high · sha:eb1a8a16312f</sub>
- Per working principle P11, the document must not fabricate a tier, seam, or module to preserve symmetry, and specifically must avoid routing a fabricated tier through the same underlying source under a different key.
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:42-44` · high · sha:eb1a8a16312f</sub>
- Per working principle P12, all deviations must be consolidated into one numbered catalogue, cross-referenced, containing nothing new, so a reviewer can audit the complete deviation set without reading the whole document.
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:45-47` · high · sha:eb1a8a16312f</sub>
- Per working principle P13, the document must hunt for the obvious-but-wrong platform tool — a host-provided thing that looks like the requirement's answer but silently violates it — and give each instance a named gotcha with the precise divergence, verified against a real interpreter rather than asserted.
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:48-51` · high · sha:eb1a8a16312f</sub>
- Per working principle P14, where the host ecosystem has converged on one dominant API shape for a concern, the seam must be defined as a structural subset of that shape so existing infrastructure duck-types in with zero adapter code, adopting the ecosystem's shape rather than its package. (SEAM-1)
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:52-55` · high · sha:eb1a8a16312f</sub>

## Constraints

## Conclusions

## Reference
- Ruby facts in the port design were verified against Ruby 3.4.10 on the authoring machine unless explicitly marked as holding only from a later release, and where verification contradicted secondary research, the verified behaviour is what is recorded.
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:57-60` · high · sha:eb1a8a16312f</sub>
- A sibling port design for another host language exists and follows the same porting method, but the Ruby port design does not depend on it.
  <sub>design · `docs/sdk-design-ruby/00-porting-method.md:57-60` · high · sha:eb1a8a16312f</sub>

## Conflicts

## Superseded
