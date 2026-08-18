# Changelog

All notable changes will be documented here. The project follows Semantic
Versioning after its first stable release.

## Unreleased

- Initial standalone Nextflow implementation from cell-level expression input
  through SAIGE-QTL summary statistics.
- Reproducible `component_union` and `joint_score` pair tests.
- Manuscript-compatible `fast` scheduling and cluster-complete scheduling.
- Production-compatible annotation-aware cluster windows and cluster-PC PCA.
- Independently resumable upstream stages for preparation plus pair testing,
  cluster calling, and cluster-PC phenotype construction.
- Bundled 1000 Genomes EUR example with simulated single-cell expression for
  both pair-test modes.
- Cross-platform `sc-pcqtl` launcher and no-admin Java/Nextflow installer.
- Docker, Podman, Apptainer, Singularity, local, Slurm, and SGE/UGE profiles.
- Hardened clean-host installation, HPC scratch handling, resumable telemetry,
  runtime provenance, reproducible container builds, and release smoke tests.
