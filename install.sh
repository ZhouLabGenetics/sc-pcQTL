#!/usr/bin/env bash
set -euo pipefail

nextflow_version=${NEXTFLOW_VERSION:-25.10.7}
install_root=${SCPCQTL_INSTALL_ROOT:-"$HOME/.local/share/sc-pcqtl"}
bin_dir=${SCPCQTL_BIN_DIR:-"$HOME/.local/bin"}
launcher_url=${SCPCQTL_LAUNCHER_URL:-https://raw.githubusercontent.com/ZhouLabGenetics/sc-pcQTL/main/bin/sc-pcqtl}

usage() {
  cat <<'EOF'
Install the sc-pcQTL launcher and a pinned Nextflow into the user account.

Usage: bash install.sh [options]

Options:
  --prefix DIR             Installation root (default: ~/.local/share/sc-pcqtl)
  --bin-dir DIR            Launcher directory (default: ~/.local/bin)
  --nextflow-version VER   Nextflow version (default: 25.10.7)
  --no-java-download       Require an existing compatible Java installation
  -h, --help               Show this help

Environment variables with the same names as the defaults are also supported.
The script does not install a container runtime because Docker Desktop and
Linux/HPC runtimes require platform- or site-specific administration.
EOF
}

allow_java_download=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || { printf '%s requires a value\n' "$1" >&2; exit 2; }
      install_root=$2
      shift 2
      ;;
    --bin-dir)
      [[ $# -ge 2 ]] || { printf '%s requires a value\n' "$1" >&2; exit 2; }
      bin_dir=$2
      shift 2
      ;;
    --nextflow-version)
      [[ $# -ge 2 ]] || { printf '%s requires a value\n' "$1" >&2; exit 2; }
      nextflow_version=$2
      shift 2
      ;;
    --no-java-download) allow_java_download=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

for tool in bash curl tar sed install mktemp mv uname; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'Required command is missing: %s\n' "$tool" >&2
    exit 1
  }
done

java_major() {
  local executable=$1 line version major
  line=$("$executable" -version 2>&1 | head -n 1) || return 1
  version=$(printf '%s\n' "$line" | sed -E 's/.*version "([^"]+)".*/\1/')
  major=${version%%.*}
  if [[ "$major" == '1' ]]; then
    version=${version#1.}
    major=${version%%.*}
  fi
  [[ "$major" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$major"
}

compatible_java() {
  local executable=$1 major
  [[ -x "$executable" ]] || return 1
  major=$(java_major "$executable") || return 1
  (( major >= 17 ))
}

bundled_java_home() {
  local candidate=''
  if [[ -s "$install_root/java-home" ]]; then
    IFS= read -r candidate < "$install_root/java-home"
    if compatible_java "$candidate/bin/java"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  for candidate in \
    "$install_root/java17" \
    "$install_root/java17/Contents/Home"; do
    if compatible_java "$candidate/bin/java"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

write_java_home_pointer() {
  local java_runtime=$1 pointer_candidate
  pointer_candidate=$(mktemp "$install_root/.java-home.XXXXXX")
  cleanup_files+=("$pointer_candidate")
  printf '%s\n' "$java_runtime" > "$pointer_candidate"
  mv -f "$pointer_candidate" "$install_root/java-home"
}

cleanup() {
  local path
  rm -rf "$temporary_dir"
  if (( ${#cleanup_files[@]} > 0 )); then
    for path in "${cleanup_files[@]}"; do
      [[ ! -e "$path" ]] || rm -f -- "$path"
    done
  fi
  if (( ${#cleanup_dirs[@]} > 0 )); then
    for path in "${cleanup_dirs[@]}"; do
      [[ -z "$path" || "$path" == "$keep_java_dir" || ! -e "$path" ]] || \
        rm -rf -- "$path"
    done
  fi
}

mkdir -p "$install_root" "$bin_dir"
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/scpcqtl-install.XXXXXX")
cleanup_files=()
cleanup_dirs=()
keep_java_dir=''
trap cleanup EXIT

java_home=''
java_executable=''
if [[ -n "${JAVA_HOME:-}" ]] && compatible_java "$JAVA_HOME/bin/java"; then
  java_home=$JAVA_HOME
  java_executable=$JAVA_HOME/bin/java
elif command -v java >/dev/null 2>&1 && compatible_java "$(command -v java)"; then
  java_executable=$(command -v java)
  java_home=$("$java_executable" -XshowSettings:properties -version 2>&1 | \
    sed -n 's/^[[:space:]]*java.home = //p' | head -n 1)
  [[ -d "$java_home" ]] || java_home=''
elif java_home=$(bundled_java_home 2>/dev/null); then
  java_executable=$java_home/bin/java
fi

if [[ -z "$java_executable" ]]; then
  [[ "$allow_java_download" == true ]] || {
    printf 'Java 17 or newer was not found.\n' >&2
    exit 1
  }
  case "$(uname -s)" in
    Linux) adoptium_os=linux ;;
    Darwin) adoptium_os=mac ;;
    *) printf 'Automatic Java installation supports Linux and macOS only.\n' >&2; exit 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) adoptium_arch=x64 ;;
    arm64|aarch64) adoptium_arch=aarch64 ;;
    *) printf 'Unsupported CPU architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
  esac
  java_url="https://api.adoptium.net/v3/binary/latest/17/ga/${adoptium_os}/${adoptium_arch}/jre/hotspot/normal/eclipse?project=jdk"
  printf 'Installing Temurin Java 17 under %s\n' "$install_root/jvm"
  curl -fL --retry 3 "$java_url" -o "$temporary_dir/java.tar.gz"
  mkdir -p "$install_root/jvm"
  java_home=$(mktemp -d "$install_root/jvm/temurin-17.XXXXXX")
  cleanup_dirs+=("$java_home")
  tar -xzf "$temporary_dir/java.tar.gz" -C "$java_home" --strip-components=1
  [[ -x "$java_home/bin/java" ]] || java_home="$java_home/Contents/Home"
  compatible_java "$java_home/bin/java" || {
    printf 'Downloaded Temurin runtime is missing a compatible Java executable.\n' >&2
    exit 1
  }
  keep_java_dir=${java_home%/Contents/Home}
  write_java_home_pointer "$java_home"
  java_executable=$java_home/bin/java
fi

nextflow_dir="$install_root/nextflow/$nextflow_version"
nextflow_executable="$nextflow_dir/nextflow"
nextflow_home="$install_root/nextflow-home"
nextflow_candidate=$nextflow_executable
install_nextflow=false
if [[ ! -x "$nextflow_executable" ]]; then
  mkdir -p "$nextflow_dir" "$temporary_dir/nextflow"
  nextflow_candidate=$(mktemp "$nextflow_dir/.nextflow.XXXXXX")
  cleanup_files+=("$nextflow_candidate")
  install_nextflow=true
  if [[ -n "${SCPCQTL_NEXTFLOW_SOURCE:-}" ]]; then
    install -m 0755 "$SCPCQTL_NEXTFLOW_SOURCE" "$nextflow_candidate"
  else
    printf 'Installing Nextflow %s under %s\n' "$nextflow_version" "$nextflow_dir"
    curl -fsSL https://get.nextflow.io -o "$temporary_dir/get-nextflow.sh"
    (
      cd "$temporary_dir/nextflow"
      export PATH="$(dirname "$java_executable"):$PATH"
      export NXF_VER="$nextflow_version"
      export NXF_HOME="$nextflow_home"
      [[ -n "$java_home" ]] && export JAVA_HOME="$java_home"
      export JAVA_CMD="$java_executable"
      bash < "$temporary_dir/get-nextflow.sh" >/dev/null
    )
    [[ -x "$temporary_dir/nextflow/nextflow" ]] || {
      printf 'Nextflow bootstrap did not create an executable.\n' >&2
      exit 1
    }
    install -m 0755 "$temporary_dir/nextflow/nextflow" "$nextflow_candidate"
  fi
fi

nextflow_output=$(
  export PATH="$(dirname "$java_executable"):$PATH"
  export NXF_HOME="$nextflow_home"
  [[ -n "$java_home" ]] && export JAVA_HOME="$java_home"
  export JAVA_CMD="$java_executable"
  "$nextflow_candidate" -version 2>&1
) || {
  printf 'Installed Nextflow could not start.\n%s\n' "$nextflow_output" >&2
  exit 1
}
if [[ "$nextflow_output" =~ ([0-9]+\.[0-9]+\.[0-9]+(-edge)?) ]]; then
  installed_nextflow_version=${BASH_REMATCH[1]}
else
  printf 'Could not determine installed Nextflow version.\n%s\n' "$nextflow_output" >&2
  exit 1
fi
[[ "$installed_nextflow_version" == "$nextflow_version" ]] || {
  printf 'Nextflow version mismatch: requested %s, installed %s\n' \
    "$nextflow_version" "$installed_nextflow_version" >&2
  exit 1
}
if [[ "$install_nextflow" == true ]]; then
  mv -f "$nextflow_candidate" "$nextflow_executable"
fi

launcher_source=''
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
if [[ -n "${SCPCQTL_LAUNCHER_SOURCE:-}" ]]; then
  launcher_source=$SCPCQTL_LAUNCHER_SOURCE
elif [[ -n "$script_dir" && -f "$script_dir/bin/sc-pcqtl" ]]; then
  launcher_source=$script_dir/bin/sc-pcqtl
else
  launcher_source=$temporary_dir/sc-pcqtl
  curl -fsSL "$launcher_url" -o "$launcher_source"
fi
internal_launcher_dir="$install_root/libexec"
internal_launcher="$internal_launcher_dir/sc-pcqtl.real"
mkdir -p "$internal_launcher_dir"
internal_launcher_candidate=$(mktemp "$internal_launcher_dir/.sc-pcqtl.real.XXXXXX")
cleanup_files+=("$internal_launcher_candidate")
install -m 0755 "$launcher_source" "$internal_launcher_candidate"
mv -f "$internal_launcher_candidate" "$internal_launcher"

quoted_nextflow=$(printf '%q' "$nextflow_executable")
quoted_nextflow_home=$(printf '%q' "$nextflow_home")
quoted_java=$(printf '%q' "$java_executable")
quoted_launcher=$(printf '%q' "$internal_launcher")
wrapper_candidate=$(mktemp "$bin_dir/.sc-pcqtl.XXXXXX")
cleanup_files+=("$wrapper_candidate")
{
  printf '%s\n' '#!/usr/bin/env bash'
  if [[ -n "$java_home" ]]; then
    quoted_java_home=$(printf '%q' "$java_home")
    printf 'export JAVA_HOME=%s\n' "$quoted_java_home"
    printf '%s\n' 'export PATH="$JAVA_HOME/bin:$PATH"'
  fi
  printf 'export JAVA_CMD=%s\n' "$quoted_java"
  printf 'if [[ -z "${NXF_HOME:-}" ]]; then export NXF_HOME=%s; fi\n' \
    "$quoted_nextflow_home"
  cat <<EOF
export SCPCQTL_NEXTFLOW=$quoted_nextflow
exec $quoted_launcher "\$@"
EOF
} > "$wrapper_candidate"
chmod 0755 "$wrapper_candidate"
mv -f "$wrapper_candidate" "$bin_dir/sc-pcqtl"

printf '\nInstalled sc-pcqtl: %s\n' "$bin_dir/sc-pcqtl"
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) printf 'Add this directory to PATH: export PATH="%s:$PATH"\n' "$bin_dir" ;;
esac
printf 'A Docker/Podman runtime is required on macOS and workstations; Apptainer is also supported on Linux/HPC.\n'
printf 'After starting the runtime, run: sc-pcqtl doctor\n'
