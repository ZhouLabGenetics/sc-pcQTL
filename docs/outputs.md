# Outputs

```text
results/
  qc/celltypes/<celltype>/
  pairs/<celltype>/
  clusters/<celltype>/
  phenotypes/<celltype>/
  phenotypes/qtl_tasks.tsv
  qtl/tasks/<celltype>__<cluster>__<PC>/
  summary/
  pipeline_info/
```

## QC and pair screen

- `celltype_qc.tsv`: cell and donor counts, annotation/count overlap,
  eligibility, filtered-gene count, and library-size source.
- `gene_filtering.tsv`: complete autosomal annotation with count-table
  presence, per-gene nonzero fraction, and pair-screen keep flag.
- `pair_summary.tsv`: global denominator, computed pairs, threshold,
  significant-pair count, pair settings, and fasthurdle version.
- `all_computed_pairs.tsv.gz`: canonical unordered pair results.
- `significant_pairs.tsv.gz`: cluster-forming pair subset.
- `directional_tests.tsv.gz`: optional ordered tests when
  `save_directional_tests=true`.

## Clusters and phenotypes

- `clusters.tsv`: genomic span, size, edge density, and genes per cluster.
- `cluster_genes.tsv`: one cluster-gene assignment per row.
- `pca_summary.tsv`: PCA status and retained PC count.
- `<cluster>/gene_loadings.tsv`: loadings for all PCs.
- `<cluster>/variance_explained.tsv`: eigenvalues and cumulative variance.
- `<cluster>/phenotypes.tsv`: retained PCs and SAIGE-QTL covariates.
- `<cluster>/cis_region.tsv`: no-header chromosome/start/end interval.
- `qtl_tasks.tsv`: global record of all cluster-PC phenotypes and their cis
  regions.

## QTL results

- `qtl/tasks/.../association.tsv`: SAIGE-QTL single-variant output.
- `qtl/tasks/.../acat.tsv`: SAIGE-QTL region-level ACAT output.
- `summary/all_variant_results.tsv.gz`: concatenated variants with canonical
  `pvalue`, within-phenotype `qvalue`, and significance flag.
- `summary/phenotype_summary.tsv`: tested/significant variant counts, minimum
  p/q, and donor sample size per cluster-PC phenotype.
- `summary/significant_pcqtl_phenotypes.tsv`: phenotypes with at least one
  variant below the configured within-phenotype BH threshold.
- `summary/region_acat_results.tsv`: ACAT results with BH correction across
  all successfully tested cluster-PC phenotypes.
- `summary/pcqtl_counts_by_celltype.tsv`: tested and significant phenotype
  counts by cell type.

## Provenance

`pipeline_info/` contains `analysis_parameters.json`, the normalized
`validated_samplesheet.csv`, the resolved SAIGE-QTL table, trace, report,
timeline, DAG, and any auto-generated variance-ratio marker set.

`analysis_parameters.json` preserves the resolved pipeline parameters and also
records the workflow revision/commit, session and run names, Nextflow version,
selected profiles, container engine, and configured core/QTL image names. The
`container` column in `execution_trace.txt` records the image resolved for each
executed task and is authoritative when a site config overrides a process
container directly.

## Advanced staged-execution outputs

The following additional paths are created only by the advanced staged mode;
they are not expected after a standard `sc-pcqtl run`:

```text
results/
  upstream/step1/prepared/<celltype>/
  upstream/manifests/
  qtl/step1/<task>/
  qtl/manifests/
  pipeline_info/upstream_step1/
  pipeline_info/upstream_step2/
  pipeline_info/upstream_step3/
  pipeline_info/saige_step1/
  pipeline_info/saige_step2/
  pipeline_info/saige_step3/
```

Upstream stages publish reusable prepared cell-type data and write `step1.tsv`,
`step2.tsv`, and `step3.tsv` under `upstream/manifests/`. These manifests carry
validated paths from preparation and pair testing to cluster calling and then
cluster-PC phenotype construction.

Independent SAIGE-QTL stages publish null models and variance-ratio estimates
under `qtl/step1/<task>/` and write their three manifests under
`qtl/manifests/`. The standard command keeps null models in the Nextflow work
directory instead of duplicating these large intermediates in the result
directory.

Independent QTL stages use separate provenance directories:
`pipeline_info/saige_step1/`, `pipeline_info/saige_step2/`, and
`pipeline_info/saige_step3/`. Running one stage therefore does not overwrite
the report, trace, timeline, or metadata from another stage.

Independent upstream stages likewise use `pipeline_info/upstream_step1/`,
`pipeline_info/upstream_step2/`, and `pipeline_info/upstream_step3/`.

See [Advanced staged execution](staged-execution.md) for the commands and
manifest dependencies that produce these additional outputs.
