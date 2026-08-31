# sc-pcQTL

<p align="center">
  <img src="docs/assets/sc-pcQTL-concept-logo.png" alt="sc-pcQTL concept logo" width="420">
</p>

[![CI](https://github.com/ZhouLabGenetics/sc-pcQTL/actions/workflows/ci.yml/badge.svg)](https://github.com/ZhouLabGenetics/sc-pcQTL/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Nextflow](https://img.shields.io/badge/Nextflow-25.10.0%2B-23aa62.svg)](https://www.nextflow.io/)

sc-pcQTL is a single-cell framework for identifying local co-expression
clusters and cis-regulatory variants associated with coordinated multi-gene
expression programs. It combines hurdle-based gene-pair association testing,
local cluster construction, principal-component phenotype generation, and
cluster-level cis-QTL mapping.

## Workflow

1. Prepare cell-type-specific expression data and retain adequately represented
   cell types and genes.
2. Identify co-expression among neighboring genes using single-cell hurdle
   models.
3. Group associated genes into local co-expression clusters.
4. Summarize each cluster with principal-component expression phenotypes.
5. Map cis genetic associations for cluster-derived phenotypes.

## Supported platforms

| Host | Container runtime | Support |
|---|---|---|
| Linux x86_64 | Docker, Podman, Apptainer, or Singularity | Native |
| Linux ARM64 | Docker or Podman with amd64 emulation | Emulated |
| macOS Intel | Docker Desktop or Podman | Native container architecture |
| macOS Apple Silicon | Docker Desktop or Podman | `linux/amd64` emulation |
| Windows 11 | WSL2 with Docker Desktop | Linux compatibility layer |
| Linux HPC | Apptainer or Singularity, optionally Slurm or SGE/UGE | Native |

The workflow uses pinned analysis containers, so users do not need to install
individual analysis dependencies on the host. Apple Silicon is supported
through container emulation and is expected to run more slowly than an x86_64
Linux host.

## Install

First install and start a supported container runtime. Docker Desktop is the
recommended workstation runtime; Apptainer is recommended on Linux HPC. Then
install the user-level launcher, pinned Nextflow, and Java 17 when needed:

```bash
curl -fsSL https://raw.githubusercontent.com/ZhouLabGenetics/sc-pcQTL/main/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"
sc-pcqtl doctor
```

Run `sc-pcqtl doctor --deep` once after installation to verify that the
selected runtime can pull and execute an amd64 image, mount a writable host
directory, and, for Docker/Podman, apply resource limits.

The installer does not require administrator privileges and does not modify
the system Java installation. See the
[platform-specific installation guide](docs/installation.md) for macOS,
Linux, WSL2, HPC, Conda, and manual installation.

Official runtime setup: [Docker Desktop for macOS](https://docs.docker.com/desktop/setup/install/mac-install/),
[Docker Engine](https://docs.docker.com/engine/install/),
[Podman](https://podman.io/docs/installation), or
[Apptainer](https://apptainer.org/docs/admin/main/installation.html).

## Run the example

The bundled example uses public 1000 Genomes EUR genotypes and simulated
single-cell expression. It runs from input validation through cis-pcQTL
association results:

```bash
sc-pcqtl example --outdir results/example
```

See [the example documentation](examples/README.md) for its design, expected
outputs, and optional pair-test modes. The dataset demonstrates execution and
is not a performance benchmark.

## Run your data

```bash
sc-pcqtl run \
  --input samplesheet.csv \
  --gene_annotation genes.tsv \
  --genotype_prefix '/data/genotype_chr{chr}' \
  --variance_ratio_prefix /data/pruned_markers \
  --covariates 'age,batch,ancestry_pc1,ancestry_pc2' \
  --categorical_covariates 'batch' \
  --outdir results \
  -resume
```

The covariate names above are illustrative. Users should replace them with
donor-level columns available in their own data; additional covariates may
also be omitted.

The launcher selects Docker/Podman on macOS and
Apptainer/Singularity/Docker/Podman on Linux. Set `SCPCQTL_RUNTIME` to select
one explicitly. Run `sc-pcqtl run --help` for a concise workflow summary.
Direct `nextflow run` commands remain supported for advanced and institutional
deployments.

`sc-pcqtl run` is the recommended interface and executes the complete workflow
with internal parallelism. Running the complete workflow on a scheduler is
covered in [large-scale and HPC execution](docs/large-scale.md). Users who
specifically require separate driver submissions or manifest checkpoints
should instead follow [staged execution](docs/staged-execution.md).

## Statistical Modes

The default statistical mode uses `--pair_scope fast` and
`--pair_test component_union`. `fast` evaluates non-overlapping genomic blocks
of at most 50 genes. `complete` guarantees coverage of all pairs that could
occur together in a cluster of the configured maximum size, including pairs
across fast-block boundaries, and can evaluate additional nearby pairs.

`component_union` retains the smaller directional p-value separately for the
count and detection components and calls a pair when either component passes
`0.05/M`. `joint_score` uses the two-degree-of-freedom sum of count and
detection score statistics for each ordered direction and uses `0.05/(2M)`.
Both modes use the same global denominator `M`, the number of all unordered
within-chromosome autosomal pairs among filtered genes.

## Documentation

- [Installation](docs/installation.md)
- [Inputs and execution](docs/usage.md)
- [Parameters](docs/parameters.md)
- [Method definitions](docs/methods.md)
- [SAIGE-QTL execution and customization](docs/saigeqtl.md)
- [Outputs](docs/outputs.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Advanced: large-scale and HPC execution](docs/large-scale.md)
- [Advanced: staged execution](docs/staged-execution.md)

## Citation

Publication citation forthcoming. Citation details will be added here when
available. Until then, use the software citation in [`CITATION.cff`](CITATION.cff).
