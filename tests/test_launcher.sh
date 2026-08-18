#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
runtime=$(mktemp -d "${TMPDIR:-/tmp}/scpcqtl-launcher-test.XXXXXX")
trap 'rm -rf "$runtime"' EXIT
mkdir -p "$runtime/bin"

cat > "$runtime/bin/java" <<'EOF'
#!/usr/bin/env bash
echo 'openjdk version "17.0.15"' >&2
EOF
cat > "$runtime/bin/docker" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == info ]] && exit 0
if [[ "${1:-}" == run ]]; then
  while (( $# )); do
    if [[ "$1" == -v ]]; then
      host_path=${2%%:*}
      printf 'sc-pcqtl-runtime-ok\n' > "$host_path/result"
      exit 0
    fi
    shift
  done
fi
exit 0
EOF
cat > "$runtime/bin/podman" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == info ]] && exit 0
exit 0
EOF
cat > "$runtime/bin/apptainer" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == --version ]] && exit 0
exit 0
EOF
cat > "$runtime/bin/nextflow" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == -version ]]; then
  echo 'nextflow version 25.10.7'
  exit 0
fi
printf '%s\n' "$*" >> "$SCPCQTL_TEST_CAPTURE"
EOF
chmod 0755 "$runtime/bin/java" "$runtime/bin/docker" "$runtime/bin/podman" \
  "$runtime/bin/apptainer" "$runtime/bin/nextflow"

export PATH="$runtime/bin:/usr/bin:/bin"
export SCPCQTL_TEST_CAPTURE="$runtime/calls.txt"
export SCPCQTL_RUNTIME=docker
export SCPCQTL_NEXTFLOW="$runtime/bin/nextflow"

"$root/bin/sc-pcqtl" doctor >/dev/null
"$root/bin/sc-pcqtl" doctor --deep >/dev/null
if TMPDIR="$runtime/missing" "$root/bin/sc-pcqtl" doctor >/dev/null 2>&1; then
  printf 'Doctor accepted a missing TMPDIR.\n' >&2
  exit 1
fi
if "$root/bin/sc-pcqtl" doctor --unknown >/dev/null 2>&1; then
  printf 'Unknown doctor option was not rejected.\n' >&2
  exit 1
fi
"$root/bin/sc-pcqtl" example --outdir example-output >/dev/null
"$root/bin/sc-pcqtl" run --input samplesheet.csv >/dev/null
"$root/bin/sc-pcqtl" saige step1 --qtl_manifest qtl_tasks.tsv >/dev/null
"$root/bin/sc-pcqtl" saige step2 --step1_manifest step1.tsv --genotype_prefix 'geno_chr{chr}' >/dev/null
"$root/bin/sc-pcqtl" saige step3 --step2_manifest step2.tsv >/dev/null

grep -Fq 'run ZhouLabGenetics/sc-pcQTL -r main -profile docker,example --outdir example-output' "$SCPCQTL_TEST_CAPTURE"
grep -Fq 'run ZhouLabGenetics/sc-pcQTL -r main -profile docker --input samplesheet.csv' "$SCPCQTL_TEST_CAPTURE"
grep -Fq 'run ZhouLabGenetics/sc-pcQTL -r main -entry SAIGE_STEP1 -profile docker --execution_name saige_step1 --publish_saige_intermediates true --qtl_manifest qtl_tasks.tsv' "$SCPCQTL_TEST_CAPTURE"
grep -Fq "run ZhouLabGenetics/sc-pcQTL -r main -entry SAIGE_STEP2 -profile docker --execution_name saige_step2 --publish_saige_intermediates true --step1_manifest step1.tsv --genotype_prefix geno_chr{chr}" "$SCPCQTL_TEST_CAPTURE"
grep -Fq 'run ZhouLabGenetics/sc-pcQTL -r main -entry SAIGE_STEP3 -profile docker --execution_name saige_step3 --publish_saige_intermediates true --step2_manifest step2.tsv' "$SCPCQTL_TEST_CAPTURE"
if "$root/bin/sc-pcqtl" saige step4 >/dev/null 2>&1; then
  printf 'Unknown SAIGE-QTL stage was not rejected.\n' >&2
  exit 1
fi
if "$root/bin/sc-pcqtl" saige step1 --execution_name custom >/dev/null 2>&1; then
  printf 'A reserved staged-execution parameter was accepted.\n' >&2
  exit 1
fi

export SCPCQTL_RUNTIME=podman
"$root/bin/sc-pcqtl" run --input samplesheet.csv >/dev/null
grep -Fq 'run ZhouLabGenetics/sc-pcQTL -r main -profile podman --input samplesheet.csv' "$SCPCQTL_TEST_CAPTURE"

export SCPCQTL_RUNTIME=apptainer
export SCPCQTL_EXTRA_PROFILES=slurm
"$root/bin/sc-pcqtl" run --input samplesheet.csv >/dev/null
grep -Fq 'run ZhouLabGenetics/sc-pcQTL -r main -profile apptainer,slurm --input samplesheet.csv' "$SCPCQTL_TEST_CAPTURE"

export SCPCQTL_PIPELINE="$root"
export SCPCQTL_RUNTIME=docker
unset SCPCQTL_EXTRA_PROFILES
"$root/bin/sc-pcqtl" run --help >/dev/null
grep -Fq "run $root -profile docker --help" "$SCPCQTL_TEST_CAPTURE"
printf 'Launcher tests passed.\n'
