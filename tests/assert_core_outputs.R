#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop("Usage: assert_core_outputs.R <outdir> <pair_test> <pair_scope>")
outdir <- args[[1L]]
pair_test <- args[[2L]]
pair_scope <- args[[3L]]

qc <- fread(file.path(outdir, "qc", "celltypes", "example", "celltype_qc.tsv"))
stopifnot(qc$eligible[[1L]], qc$n_cells[[1L]] == 20L, qc$n_donors[[1L]] == 10L)
pair <- fread(file.path(outdir, "pairs", "example", "pair_summary.tsv"))
stopifnot(pair$global_unordered_pairs[[1L]] == 6L, pair$computed_unordered_pairs[[1L]] == 6L)
stopifnot(identical(pair$pair_test[[1L]], pair_test))
expected_threshold <- if (pair_test == "joint_score") 1 / 12 else 1 / 6
stopifnot(isTRUE(all.equal(pair$threshold[[1L]], expected_threshold, tolerance = 1e-12)))
if (pair_test == "joint_score") {
  computed <- fread(file.path(outdir, "pairs", "example", "all_computed_pairs.tsv.gz"))
  stopifnot(any(computed$significant))
  stopifnot(all(is.finite(computed$stat_joint)), all(is.finite(computed$p_joint)))
}
clusters <- fread(file.path(outdir, "clusters", "example", "clusters.tsv"))
stopifnot(nrow(clusters) >= 1L)
pca <- fread(file.path(outdir, "phenotypes", "example", "pca_summary.tsv"))
stopifnot(nrow(pca) >= 1L, all(pca$status == "ok"), all(pca$n_pcs_retained >= 1L))
tasks <- fread(file.path(outdir, "phenotypes", "example", "qtl_tasks.tsv"))
stopifnot(nrow(tasks) >= 1L)
global_tasks <- fread(file.path(outdir, "phenotypes", "qtl_tasks.tsv"))
stopifnot(nrow(global_tasks) == nrow(tasks), !anyDuplicated(global_tasks$task_id))
stopifnot(all(grepl("^example/", global_tasks$phenotype_file)))
message("Core integration assertions passed: ", pair_scope, " + ", pair_test)
