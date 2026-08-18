#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
runtime=$(mktemp -d "${TMPDIR:-/tmp}/scpcqtl-upstream-staged-test.XXXXXX")
trap 'rm -rf "${runtime}"' EXIT
profile=${SCPCQTL_TEST_PROFILE:-test}
gzip -c "${root}/tests/fixtures/counts.tsv" > "${runtime}/counts.tsv.gz"
printf 'celltype,counts\nexample,%s\n' "${runtime}/counts.tsv.gz" > "${runtime}/samplesheet.csv"

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

common=(nextflow run "${root}" -profile "${profile}" -ansi-log false)
"${common[@]}" -work-dir "${runtime}/work_full" --outdir "${runtime}/full" \
  --input "${runtime}/samplesheet.csv" --run_qtl false "$@"

"${common[@]}" -work-dir "${runtime}/work_step1" --outdir "${runtime}/staged" \
  --execution_stage upstream_step1 --execution_name upstream_step1 \
  --publish_upstream_intermediates true --input "${runtime}/samplesheet.csv" "$@"
"${common[@]}" -work-dir "${runtime}/work_step2" --outdir "${runtime}/staged" \
  --execution_stage upstream_step2 --execution_name upstream_step2 \
  --publish_upstream_intermediates true \
  --upstream_step1_manifest "${runtime}/staged/upstream/manifests/step1.tsv" "$@"
"${common[@]}" -work-dir "${runtime}/work_step3" --outdir "${runtime}/staged" \
  --execution_stage upstream_step3 --execution_name upstream_step3 \
  --publish_upstream_intermediates true \
  --upstream_step2_manifest "${runtime}/staged/upstream/manifests/step2.tsv" "$@"

run_rscript "${root}/tests/assert_staged_upstream_outputs.R" \
  "${runtime}/full" "${runtime}/staged"

manifest_dir="${runtime}/staged/upstream/manifests"
awk -F'\t' 'BEGIN{OFS="\t"} NR==1 {$5=""} {print}' \
  "${manifest_dir}/step1.tsv" > "${manifest_dir}/invalid_missing_column.tsv"
if "${common[@]}" -work-dir "${runtime}/work_invalid_column" \
  --outdir "${runtime}/invalid_column" --execution_stage upstream_step2 \
  --execution_name upstream_step2 --publish_upstream_intermediates true \
  --upstream_step1_manifest "${manifest_dir}/invalid_missing_column.tsv" \
  >/dev/null 2>&1; then
  printf 'An upstream manifest with a missing column was accepted.\n' >&2
  exit 1
fi

awk 'NR==1 {print} NR==2 {print; print; exit}' \
  "${manifest_dir}/step1.tsv" > "${manifest_dir}/invalid_duplicate_celltype.tsv"
if "${common[@]}" -work-dir "${runtime}/work_invalid_duplicate" \
  --outdir "${runtime}/invalid_duplicate" --execution_stage upstream_step2 \
  --execution_name upstream_step2 --publish_upstream_intermediates true \
  --upstream_step1_manifest "${manifest_dir}/invalid_duplicate_celltype.tsv" \
  >/dev/null 2>&1; then
  printf 'An upstream manifest with duplicate cell types was accepted.\n' >&2
  exit 1
fi

if "${common[@]}" -work-dir "${runtime}/work_parameter_mismatch_step2" \
  --outdir "${runtime}/parameter_mismatch_step2" --execution_stage upstream_step2 \
  --execution_name upstream_step2 --publish_upstream_intermediates true \
  --upstream_step1_manifest "${manifest_dir}/step1.tsv" --max_cluster_genes 5 \
  >/dev/null 2>&1; then
  printf 'Step 2 accepted a max_cluster_genes value that differed from Step 1.\n' >&2
  exit 1
fi

if "${common[@]}" -work-dir "${runtime}/work_parameter_mismatch_step3" \
  --outdir "${runtime}/parameter_mismatch_step3" --execution_stage upstream_step3 \
  --execution_name upstream_step3 --publish_upstream_intermediates true \
  --upstream_step2_manifest "${manifest_dir}/step2.tsv" --covariates age \
  >/dev/null 2>&1; then
  printf 'Step 3 accepted covariates that differed from Step 1.\n' >&2
  exit 1
fi

printf 'Staged upstream integration and manifest validation tests passed.\n'
