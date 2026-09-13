# knowledge fixture

A miniature repository root for `scripts/test/knowledge_test.rb`: a five-row appendix C, three
harvested topic files, one note, a phase document and a harvest manifest. Hand-written and small
on purpose — the real corpus lives in a sibling SDK and is never copied here.

Two digests in `docs/knowledge/harvested/SOURCES.md` are load-bearing:
`docs/product-spec/04-core-http-domain-model.md` records the true sha of the stub beside it (so a
query over `http-domain-model` is drift-free) and `docs/product-spec/12-pagination.md` records a
deliberately wrong one (so a query over `pagination` raises the inline stale-source warning).
Editing either stub without re-recording its digest will move those two tests.
