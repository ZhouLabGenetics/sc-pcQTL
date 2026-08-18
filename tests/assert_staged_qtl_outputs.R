#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Usage: assert_staged_qtl_outputs.R <full-outdir> <staged-outdir>")
full <- normalizePath(args[[1L]])
staged <- normalizePath(args[[2L]])

read_sorted <- function(path, keys) {
  value <- fread(path)
  available <- intersect(keys, names(value))
  if (length(available) && nrow(value)) setorderv(value, available)
  value
}

summary_files <- c(
  "all_variant_results.tsv.gz", "phenotype_summary.tsv",
  "significant_pcqtl_phenotypes.tsv", "region_acat_results.tsv",
  "pcqtl_counts_by_celltype.tsv"
)
keys <- c("celltype", "cluster_id", "phenotype_id", "CHR", "POS", "MarkerID")
for (filename in summary_files) {
  observed <- read_sorted(file.path(staged, "summary", filename), keys)
  expected <- read_sorted(file.path(full, "summary", filename), keys)
  stopifnot(identical(observed, expected))
}

full_tasks <- sort(list.dirs(file.path(full, "qtl", "tasks"), recursive = FALSE, full.names = FALSE))
staged_tasks <- sort(list.dirs(file.path(staged, "qtl", "tasks"), recursive = FALSE, full.names = FALSE))
stopifnot(length(full_tasks) > 0L, identical(full_tasks, staged_tasks))
for (task in full_tasks) {
  for (filename in c("association.tsv", "acat.tsv", "metadata.tsv", "COMPLETE")) {
    stopifnot(
      identical(
        readLines(file.path(full, "qtl", "tasks", task, filename)),
        readLines(file.path(staged, "qtl", "tasks", task, filename))
      )
    )
  }
}

qtl_manifest <- fread(file.path(full, "phenotypes", "qtl_tasks.tsv"), colClasses = "character")
stopifnot(nrow(qtl_manifest) == length(full_tasks), !anyDuplicated(qtl_manifest$task_id))
stopifnot(all(!grepl("^/", qtl_manifest$phenotype_file)), all(!grepl("^/", qtl_manifest$region_file)))

step1 <- fread(file.path(staged, "qtl", "manifests", "step1.tsv"), colClasses = "character")
step2 <- fread(file.path(staged, "qtl", "manifests", "step2.tsv"), colClasses = "character")
step3 <- fread(file.path(staged, "qtl", "manifests", "step3.tsv"), colClasses = "character")
stopifnot(nrow(step1) == length(full_tasks), nrow(step2) == length(full_tasks), nrow(step3) == length(full_tasks))
stopifnot(all(file.exists(step1$null_model_file)), all(file.exists(step1$variance_ratio_file)))
stopifnot(all(file.exists(step2$association_file)))
stopifnot(all(file.exists(step3$association_file)), all(file.exists(step3$acat_file)))
stopifnot(
  length(unique(step1$saige_params_file)) == 1L,
  identical(unique(step1$saige_params_file), unique(step2$saige_params_file)),
  identical(unique(step2$saige_params_file), unique(step3$saige_params_file)),
  file.exists(unique(step3$saige_params_file))
)

for (stage in paste0("saige_step", 1:3)) {
  info <- file.path(staged, "pipeline_info", stage)
  stopifnot(
    file.exists(file.path(info, "analysis_parameters.json")),
    file.exists(file.path(info, "execution_trace.txt"))
  )
}

full_models <- list.files(file.path(full, "qtl"), pattern = "saige_null_model", recursive = TRUE)
stopifnot(length(full_models) == 0L)
message("Staged SAIGE-QTL outputs are equivalent to the end-to-end outputs")
