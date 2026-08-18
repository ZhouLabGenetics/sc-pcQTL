# Contributing

Open an issue before changing statistical defaults or output schemas. Pull
requests should include a focused rationale, tests for changed behavior, and
documentation updates.

Run the local checks from the repository root:

```bash
nextflow lint main.nf
Rscript tests/testthat.R
tests/run_core_integration.sh
tests/run_qtl_mock_integration.sh
tests/run_qtl_staged_mock_integration.sh
```

Manual edits should not mix scientific-default changes with refactoring in a
single commit. Container dependencies must be pinned to a release or commit.

## Public release checklist

Before advertising the one-command installer:

1. make the repository public;
2. set both `sc-pcqtl-core` and `sc-pcqtl-saigeqtl` GHCR packages to public;
3. confirm that the container workflow published the intended tag and passed
   its anonymous-pull, runtime, and complete bundled-example gates;
4. test anonymous pulls of both images on a clean host; and
5. test the README installation and bundled-example commands without existing
   GitHub credentials.

GHCR container packages are private by default even when they are linked to a
repository. Repository visibility and package visibility must therefore be
checked separately.
