#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
runtime=$(mktemp -d "${TMPDIR:-/tmp}/scpcqtl-qtl-staged-test.XXXXXX")
trap 'rm -rf "${runtime}"' EXIT
profile=${SCPCQTL_TEST_PROFILE:-test}

run_rscript() {
  if [[ -n "${SCPCQTL_TEST_CONTAINER:-}" ]]; then
    docker run --rm -v "${root}:${root}" -v "${runtime}:${runtime}" -w "${root}" \
      "${SCPCQTL_TEST_CONTAINER}" Rscript "$@"
  elif [[ -n "${SCPCQTL_TEST_APPTAINER_IMAGE:-}" ]]; then
    apptainer exec --bind "${root}:${root}" --bind "${runtime}:${runtime}" \
      "${SCPCQTL_TEST_APPTAINER_IMAGE}" Rscript "$@"
  else
    Rscript "$@"
  fi
}

for chromosome in $(seq 1 22); do
  for extension in bed bim fam; do
    printf 'mock\n' > "${runtime}/genotype_chr${chromosome}.${extension}"
  done
done
for extension in bed bim fam; do
  printf 'mock\n' > "${runtime}/vr.${extension}"
done

export PATH="${root}/tests/mocks:${PATH}"
common=(nextflow run "${root}" -profile "${profile}" -ansi-log false)
"${common[@]}" -work-dir "${runtime}/work_full" --outdir "${runtime}/full" \
  --run_qtl true --genotype_prefix "${runtime}/genotype_chr{chr}" \
  --variance_ratio_prefix "${runtime}/vr" "$@"

"${common[@]}" -work-dir "${runtime}/work_step1" \
  --outdir "${runtime}/staged" --execution_stage saige_step1 --execution_name saige_step1 \
  --publish_saige_intermediates true \
  --qtl_manifest "${runtime}/full/phenotypes/qtl_tasks.tsv" \
  --variance_ratio_prefix "${runtime}/vr" "$@"
"${common[@]}" -work-dir "${runtime}/work_step2" \
  --outdir "${runtime}/staged" --execution_stage saige_step2 --execution_name saige_step2 \
  --publish_saige_intermediates true \
  --step1_manifest "${runtime}/staged/qtl/manifests/step1.tsv" \
  --genotype_prefix "${runtime}/genotype_chr{chr}" "$@"
"${common[@]}" -work-dir "${runtime}/work_step3" \
  --outdir "${runtime}/staged" --execution_stage saige_step3 --execution_name saige_step3 \
  --publish_saige_intermediates true \
  --step2_manifest "${runtime}/staged/qtl/manifests/step2.tsv" "$@"

run_rscript "${root}/tests/assert_qtl_outputs.R" "${runtime}/staged"
run_rscript "${root}/tests/assert_staged_qtl_outputs.R" "${runtime}/full" "${runtime}/staged"

manifest_dir="${runtime}/full/phenotypes"
awk -F'\t' 'BEGIN{OFS="\t"} NR==1 {$7=""} {print}' \
  "${manifest_dir}/qtl_tasks.tsv" > "${manifest_dir}/invalid_missing_column.tsv"
if "${common[@]}" -work-dir "${runtime}/work_invalid_column" \
  --outdir "${runtime}/invalid_column" --execution_stage saige_step1 --execution_name saige_step1 \
  --publish_saige_intermediates true \
  --qtl_manifest "${manifest_dir}/invalid_missing_column.tsv" \
  --variance_ratio_prefix "${runtime}/vr" >/dev/null 2>&1; then
  printf 'A QTL manifest with a missing column was accepted.\n' >&2
  exit 1
fi

awk 'NR==1 {print} NR==2 {print; print; exit}' \
  "${manifest_dir}/qtl_tasks.tsv" > "${manifest_dir}/invalid_duplicate_task.tsv"
if "${common[@]}" -work-dir "${runtime}/work_invalid_duplicate" \
  --outdir "${runtime}/invalid_duplicate" --execution_stage saige_step1 --execution_name saige_step1 \
  --publish_saige_intermediates true \
  --qtl_manifest "${manifest_dir}/invalid_duplicate_task.tsv" \
  --variance_ratio_prefix "${runtime}/vr" >/dev/null 2>&1; then
  printf 'A QTL manifest with duplicate task identifiers was accepted.\n' >&2
  exit 1
fi

printf 'Staged SAIGE-QTL integration and manifest validation tests passed.\n'
