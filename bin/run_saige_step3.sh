#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: run_saige_step3.sh <task-id> <celltype> <cluster> <phenotype> <chr> <pheno-source> <region-source> <association> <params> <params-source> <outdir>" >&2
  exit 2
}
[[ $# -eq 11 ]] || usage

task_id=$1
celltype=$2
cluster=$3
phenotype=$4
chromosome=$5
pheno_source=$6
region_source=$7
association=$(realpath "$8")
params=$(realpath "$9")
params_source=${10}
outdir=${11}

for path in "${association}" "${params}"; do
  test -s "${path}" || { echo "Missing or empty required input: ${path}" >&2; exit 2; }
done

args_for_step() {
  local step=$1
  awk -F'\t' -v step="${step}" 'NR>1 && $1==step {printf "--%s=%s\n", $2, $3}' "${params}"
}
mapfile -t step3_args < <(args_for_step step3)

mkdir -p "${outdir}"
outdir=$(realpath "${outdir}")
cp -- "${association}" "${outdir}/association.tsv"
step3_gene_pvalue_qtl.R \
  "${step3_args[@]}" \
  --assocFile="${outdir}/association.tsv" \
  --geneName="${phenotype}" \
  --genePval_outputFile="${outdir}/acat.tsv"

test -s "${outdir}/acat.tsv"
printf 'celltype\tcluster_id\tphenotype_id\tchromosome\n%s\t%s\t%s\t%s\n' \
  "${celltype}" "${cluster}" "${phenotype}" "${chromosome}" > "${outdir}/metadata.tsv"
printf 'task_id\tcelltype\tcluster_id\tphenotype_id\tchromosome\tphenotype_file\tregion_file\tsaige_params_file\n' > "${outdir}/stage_metadata.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "${task_id}" "${celltype}" "${cluster}" "${phenotype}" "${chromosome}" \
  "${pheno_source}" "${region_source}" "${params_source}" \
  >> "${outdir}/stage_metadata.tsv"
printf 'OK\n' > "${outdir}/COMPLETE"
