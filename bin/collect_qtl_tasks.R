#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(data.table))
script_dir <- dirname(normalizePath(sub("--file=", "", commandArgs(FALSE)[grep("--file=", commandArgs(FALSE))[1L]])))
source(file.path(script_dir, "scpcqtl_utils.R"))
args <- parse_cli()
input_list <- required_arg(args, "input_list")
out <- required_arg(args, "out")

directories <- fread(input_list, header = FALSE)[[1L]]
directories <- sort(unique(directories[dir.exists(directories)]))
rows <- list()

for (directory in directories) {
  task_file <- file.path(directory, "qtl_tasks.tsv")
  if (!file.exists(task_file)) stop("Missing PCA task table: ", task_file)
  tasks <- fread(task_file, colClasses = "character")
  required <- c(
    "task_id", "celltype", "cluster_id", "phenotype_id", "chromosome",
    "phenotype_file", "region_file"
  )
  missing <- setdiff(required, names(tasks))
  if (length(missing)) stop("PCA task table is missing columns: ", paste(missing, collapse = ", "))
  if (!nrow(tasks)) next

  tasks[, task_id := paste(celltype, cluster_id, phenotype_id, sep = "__")]
  tasks[, phenotype_file := file.path(celltype, phenotype_file)]
  tasks[, region_file := file.path(celltype, region_file)]
  rows[[length(rows) + 1L]] <- tasks[, ..required]
}

result <- if (length(rows)) rbindlist(rows, use.names = TRUE) else data.table(
  task_id = character(), celltype = character(), cluster_id = character(),
  phenotype_id = character(), chromosome = integer(), phenotype_file = character(),
  region_file = character()
)
if (anyDuplicated(result$task_id)) stop("Generated QTL task identifiers are not unique")
if (nrow(result)) setorder(result, celltype, chromosome, cluster_id, phenotype_id)
fwrite(result, out, sep = "\t")
