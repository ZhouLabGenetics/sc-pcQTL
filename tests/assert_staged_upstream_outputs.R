#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: assert_staged_upstream_outputs.R <full-outdir> <staged-outdir>")
}
full <- normalizePath(args[[1L]])
staged <- normalizePath(args[[2L]])

read_sorted <- function(path) {
  value <- fread(path)
  if (nrow(value) && ncol(value)) setorderv(value, names(value))
  value
}

compare_table <- function(relative_path) {
  observed <- read_sorted(file.path(staged, relative_path))
  expected <- read_sorted(file.path(full, relative_path))
  if (!identical(observed, expected)) stop("Staged output differs: ", relative_path)
}

step1 <- fread(
  file.path(staged, "upstream", "manifests", "step1.tsv"),
  colClasses = "character"
)
step2 <- fread(
  file.path(staged, "upstream", "manifests", "step2.tsv"),
  colClasses = "character"
)
step3 <- fread(
  file.path(staged, "upstream", "manifests", "step3.tsv"),
  colClasses = "character"
)

stopifnot(
  nrow(step1) > 0L,
  identical(step1$celltype, step2$celltype),
  identical(step2$celltype, step3$celltype),
  !anyDuplicated(step1$celltype),
  all(file.exists(step1$counts_file)),
  all(dir.exists(step1$prepared_dir)),
  all(dir.exists(step1$pair_dir)),
  all(dir.exists(step2$cluster_dir)),
  all(dir.exists(step3$phenotype_dir)),
  all(file.exists(step1$step1_parameters_file)),
  all(file.exists(step2$step2_parameters_file)),
  all(file.exists(step3$step3_parameters_file))
)

for (celltype in step3$celltype) {
  compare_table(file.path("qc", "celltypes", celltype, "celltype_qc.tsv"))
  compare_table(file.path("qc", "celltypes", celltype, "gene_filtering.tsv"))
  compare_table(file.path("pairs", celltype, "all_computed_pairs.tsv.gz"))
  compare_table(file.path("pairs", celltype, "significant_pairs.tsv.gz"))
  compare_table(file.path("pairs", celltype, "pair_summary.tsv"))
  compare_table(file.path("clusters", celltype, "clusters.tsv"))
  compare_table(file.path("clusters", celltype, "cluster_genes.tsv"))
  compare_table(file.path("clusters", celltype, "cluster_summary.tsv"))
  compare_table(file.path("phenotypes", celltype, "pca_summary.tsv"))
  compare_table(file.path("phenotypes", celltype, "qtl_tasks.tsv"))

  clusters <- fread(file.path(staged, "clusters", celltype, "clusters.tsv"))
  for (cluster_id in clusters$cluster_id) {
    base <- file.path("phenotypes", celltype, cluster_id)
    for (filename in c("phenotypes.tsv", "gene_loadings.tsv", "variance_explained.tsv")) {
      compare_table(file.path(base, filename))
    }
    stopifnot(identical(
      readLines(file.path(staged, base, "cis_region.tsv")),
      readLines(file.path(full, base, "cis_region.tsv"))
    ))
    observed_pca <- readRDS(file.path(staged, base, "pca.rds"))
    expected_pca <- readRDS(file.path(full, base, "pca.rds"))
    stopifnot(isTRUE(all.equal(observed_pca, expected_pca, tolerance = 1e-12)))
  }
}

compare_table(file.path("phenotypes", "qtl_tasks.tsv"))
for (stage in paste0("upstream_step", 1:3)) {
  info <- file.path(staged, "pipeline_info", stage)
  stopifnot(
    file.exists(file.path(info, "analysis_parameters.json")),
    file.exists(file.path(info, "execution_trace.txt"))
  )
}

stopifnot(!dir.exists(file.path(full, "upstream", "step1", "prepared")))
message("Staged upstream outputs are equivalent to the end-to-end core outputs")
