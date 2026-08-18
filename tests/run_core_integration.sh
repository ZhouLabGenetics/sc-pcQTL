#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
runtime=$(mktemp -d "${TMPDIR:-/tmp}/scpcqtl-core-test.XXXXXX")
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

run_case() {
  local name=$1
  local scope=$2
  local test_name=$3
  local output="${runtime}/output_${name}"
  nextflow run "${root}" -profile "${profile}" -ansi-log false \
    -work-dir "${runtime}/work_${name}" --outdir "${output}" \
    --pair_scope "${scope}" --pair_test "${test_name}" "${@:4}"
  run_rscript "${root}/tests/assert_core_outputs.R" "${output}" "${test_name}" "${scope}"
}

run_case fast_component fast component_union "$@"
run_case complete_component complete component_union "$@"
run_case fast_joint fast joint_score "$@"

ineligible_output="${runtime}/output_ineligible"
nextflow run "${root}" -profile "${profile}" -ansi-log false \
  -work-dir "${runtime}/work_ineligible" --outdir "${ineligible_output}" \
  --min_cells 21 "$@"
run_rscript "${root}/tests/assert_ineligible_outputs.R" "${ineligible_output}"
