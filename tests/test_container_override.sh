#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/scpcqtl-container-override.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/project"

cat > "$scratch/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$SCPCQTL_DOCKER_CAPTURE"
if [[ "${1:-}" == run ]]; then
  bash -ue .command.sh
fi
EOF
chmod 0755 "$scratch/bin/docker"

cat > "$scratch/project/main.nf" <<'EOF'
nextflow.enable.dsl=2

process CORE_PROBE {
    label 'process_low'
    output:
    path 'core.txt'
    script:
    "printf 'core\\n' > core.txt"
}

process QTL_PROBE {
    label 'process_qtl'
    output:
    path 'qtl.txt'
    script:
    "printf 'qtl\\n' > qtl.txt"
}

workflow {
    CORE_PROBE()
    QTL_PROBE()
}
EOF

export PATH="$scratch/bin:$PATH"
export SCPCQTL_DOCKER_CAPTURE="$scratch/docker-args.txt"
nextflow -c "$root/nextflow.config" run "$scratch/project/main.nf" \
  -profile docker,example -ansi-log false \
  -work-dir "$scratch/work" --outdir "$scratch/output" \
  --core_container example.invalid/core:test \
  --saige_container example.invalid/saige:test >/dev/null

grep -Fq 'example.invalid/core:test' "$SCPCQTL_DOCKER_CAPTURE"
grep -Fq 'example.invalid/saige:test' "$SCPCQTL_DOCKER_CAPTURE"
grep -q $'\tcontainer$' "$scratch/output/pipeline_info/execution_trace.txt"
grep -Fq 'example.invalid/core:test' "$scratch/output/pipeline_info/execution_trace.txt"
grep -Fq 'example.invalid/saige:test' "$scratch/output/pipeline_info/execution_trace.txt"
if grep -Fq 'ghcr.io/zhoulabgenetics/sc-pcqtl-' "$SCPCQTL_DOCKER_CAPTURE"; then
  printf 'A default image was used despite explicit container overrides.\n' >&2
  exit 1
fi
printf 'Container override test passed.\n'
