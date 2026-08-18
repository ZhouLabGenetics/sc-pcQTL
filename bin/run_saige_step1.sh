#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: run_saige_step1.sh <task-id> <celltype> <cluster> <phenotype> <chr> <pheno> <pheno-source> <region-source> <vr-prefix> <vr-fam-source> <params> <params-source> <outdir>" >&2
  exit 2
}
[[ $# -eq 13 ]] || usage

task_id=$1
celltype=$2
cluster=$3
phenotype=$4
chromosome=$5
pheno=$(realpath "$6")
pheno_source=$7
region_source=$8
vr_prefix=$(realpath -m "$9")
vr_fam_source=${10}
params=$(realpath "${11}")
params_source=${12}
outdir=${13}

for path in "${pheno}" "${vr_prefix}.bed" "${vr_prefix}.bim" \
            "${vr_prefix}.fam" "${params}"; do
  test -s "${path}" || { echo "Missing or empty required input: ${path}" >&2; exit 2; }
done

if [[ "${pheno}" == *.gz ]]; then
  header=$(gzip -cd -- "${pheno}" 2>/dev/null | head -n 1 || true)
else
  header=$(head -n 1 "${pheno}")
fi
printf '%s\n' "${header}" | awk -F'\t' -v phenotype="${phenotype}" '
  {
    has_id=0; has_pheno=0
    for (i=1; i<=NF; i++) {
      if ($i=="individual") has_id=1
      if ($i==phenotype) has_pheno=1
    }
    if (!has_id || !has_pheno) exit 1
  }
' || { echo "Phenotype table must contain individual and ${phenotype}: ${pheno}" >&2; exit 2; }

args_for_step() {
  local step=$1
  awk -F'\t' -v step="${step}" 'NR>1 && $1==step {printf "--%s=%s\n", $2, $3}' "${params}"
}
mapfile -t step1_args < <(args_for_step step1)

mkdir -p "${outdir}"
outdir=$(realpath "${outdir}")
prefix="${outdir}/saige_null_model"
step1_fitNULLGLMM_qtl.R \
  "${step1_args[@]}" \
  --phenoFile="${pheno}" \
  --phenoCol="${phenotype}" \
  --sampleIDColinphenoFile=individual \
  --outputPrefix="${prefix}" \
  --plinkFile="${vr_prefix}"

test -s "${prefix}.rda"
test -s "${prefix}.varianceRatio.txt"
printf 'task_id\tcelltype\tcluster_id\tphenotype_id\tchromosome\tphenotype_file\tregion_file\tvariance_ratio_fam_file\tsaige_params_file\n' > "${outdir}/stage_metadata.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "${task_id}" "${celltype}" "${cluster}" "${phenotype}" "${chromosome}" \
  "${pheno_source}" "${region_source}" "${vr_fam_source}" "${params_source}" \
  >> "${outdir}/stage_metadata.tsv"
