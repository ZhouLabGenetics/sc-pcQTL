#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: run_saige_step2.sh <task-id> <celltype> <cluster> <phenotype> <chr> <pheno-source> <region> <region-source> <bed> <bim> <fam> <vr-fam> <null-model> <variance-ratio> <params> <params-source> <outdir>" >&2
  exit 2
}
[[ $# -eq 17 ]] || usage

task_id=$1
celltype=$2
cluster=$3
phenotype=$4
chromosome=$5
pheno_source=$6
region=$(realpath "$7")
region_source=$8
bed=$(realpath "$9")
bim=$(realpath "${10}")
fam=$(realpath "${11}")
vr_fam=$(realpath "${12}")
model=$(realpath "${13}")
variance_ratio=$(realpath "${14}")
params=$(realpath "${15}")
params_source=${16}
outdir=${17}
for path in "${region}" "${bed}" "${bim}" "${fam}" "${vr_fam}" \
            "${model}" "${variance_ratio}" "${params}"; do
  test -s "${path}" || { echo "Missing or empty required input: ${path}" >&2; exit 2; }
done
cmp -s "${fam}" "${vr_fam}" || {
  echo "Chromosome and variance-ratio PLINK FAM files differ" >&2
  exit 2
}

region_chr=$(awk 'NF && tolower($1) !~ /chrom/ {sub(/^chr/, "", $1); print $1; exit}' "${region}")
[[ "${region_chr}" == "${chromosome}" ]] || {
  echo "Region chromosome ${region_chr:-missing} does not match task chromosome ${chromosome}" >&2
  exit 2
}

args_for_step() {
  local step=$1
  awk -F'\t' -v step="${step}" 'NR>1 && $1==step {printf "--%s=%s\n", $2, $3}' "${params}"
}
mapfile -t step2_args < <(args_for_step step2)

mkdir -p "${outdir}"
outdir=$(realpath "${outdir}")
association="${outdir}/association.tsv"
step2_tests_qtl.R \
  "${step2_args[@]}" \
  --bedFile="${bed}" \
  --bimFile="${bim}" \
  --famFile="${fam}" \
  --SAIGEOutputFile="${association}" \
  --chrom="${chromosome}" \
  --GMMATmodelFile="${model}" \
  --varianceRatioFile="${variance_ratio}" \
  --rangestoIncludeFile="${region}"

test -s "${association}"
printf 'task_id\tcelltype\tcluster_id\tphenotype_id\tchromosome\tphenotype_file\tregion_file\tsaige_params_file\n' > "${outdir}/stage_metadata.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "${task_id}" "${celltype}" "${cluster}" "${phenotype}" "${chromosome}" \
  "${pheno_source}" "${region_source}" "${params_source}" \
  >> "${outdir}/stage_metadata.tsv"
