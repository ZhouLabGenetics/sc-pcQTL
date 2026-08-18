#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(data.table))
script_dir <- dirname(normalizePath(sub("--file=", "", commandArgs(FALSE)[grep("--file=", commandArgs(FALSE))[1L]])))
source(file.path(script_dir, "scpcqtl_utils.R"))
args <- parse_cli()
input_list <- required_arg(args, "input_list")
stage <- required_arg(args, "stage")
published_root <- normalizePath(required_arg(args, "published_root"), mustWork = FALSE)
out <- required_arg(args, "out")
if (!stage %in% c("step1", "step2", "step3")) stop("stage must be step1, step2, or step3")

directories <- fread(input_list, header = FALSE)[[1L]]
directories <- sort(unique(directories[dir.exists(directories)]))
if (!length(directories)) stop("No completed SAIGE-QTL task directories were supplied")

rows <- lapply(directories, function(directory) {
  metadata_file <- file.path(directory, "stage_metadata.tsv")
  if (!file.exists(metadata_file)) stop("Missing stage metadata: ", metadata_file)
  metadata <- fread(metadata_file, colClasses = "character")
  if (nrow(metadata) != 1L) stop("Expected one stage metadata row in ", metadata_file)
  metadata
})
manifest <- rbindlist(rows, use.names = TRUE, fill = TRUE)
base_columns <- c(
  "task_id", "celltype", "cluster_id", "phenotype_id", "chromosome",
  "phenotype_file", "region_file"
)
missing <- setdiff(base_columns, names(manifest))
if (length(missing)) stop("Stage metadata is missing columns: ", paste(missing, collapse = ", "))
if (anyDuplicated(manifest$task_id)) stop("Stage task identifiers are not unique")

if (stage == "step1") {
  required <- c("variance_ratio_fam_file", "saige_params_file")
  missing <- setdiff(required, names(manifest))
  if (length(missing)) stop("Step 1 metadata is missing columns: ", paste(missing, collapse = ", "))
  task_root <- file.path(published_root, "qtl", "step1")
  manifest[, null_model_file := file.path(task_root, task_id, "saige_null_model.rda")]
  manifest[, variance_ratio_file := file.path(task_root, task_id, "saige_null_model.varianceRatio.txt")]
  columns <- c(base_columns, "null_model_file", "variance_ratio_file",
               "variance_ratio_fam_file", "saige_params_file")
} else if (stage == "step2") {
  required <- "saige_params_file"
  missing <- setdiff(required, names(manifest))
  if (length(missing)) stop("Step 2 metadata is missing columns: ", paste(missing, collapse = ", "))
  task_root <- file.path(published_root, "qtl", "tasks")
  manifest[, association_file := file.path(task_root, task_id, "association.tsv")]
  columns <- c(base_columns, "association_file", "saige_params_file")
} else {
  required <- "saige_params_file"
  missing <- setdiff(required, names(manifest))
  if (length(missing)) stop("Step 3 metadata is missing columns: ", paste(missing, collapse = ", "))
  task_root <- file.path(published_root, "qtl", "tasks")
  manifest[, association_file := file.path(task_root, task_id, "association.tsv")]
  manifest[, acat_file := file.path(task_root, task_id, "acat.tsv")]
  manifest[, metadata_file := file.path(task_root, task_id, "metadata.tsv")]
  manifest[, complete_file := file.path(task_root, task_id, "COMPLETE")]
  columns <- c(base_columns, "association_file", "acat_file", "metadata_file",
               "complete_file", "saige_params_file")
}

setorder(manifest, celltype, chromosome, cluster_id, phenotype_id)
fwrite(manifest[, ..columns], out, sep = "\t")
