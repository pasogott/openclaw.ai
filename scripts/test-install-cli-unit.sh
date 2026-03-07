#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2030,SC2031,SC2016,SC2329,SC2317
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local got="$1"
  local want="$2"
  local msg="${3:-}"
  if [[ "$got" != "$want" ]]; then
    fail "${msg} expected=${want} got=${got}"
  fi
}

assert_nonempty() {
  local got="$1"
  local msg="${2:-}"
  if [[ -z "$got" ]]; then
    fail "${msg} expected non-empty"
  fi
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export OPENCLAW_INSTALL_CLI_SH_NO_RUN=1
# shellcheck source=../public/install-cli.sh
source "${ROOT_DIR}/public/install-cli.sh"

echo "==> case: ensure_pnpm_binary_for_scripts installs prefix wrapper"
(
  root="${TMP_DIR}/case-pnpm-wrapper"
  prefix="${root}/prefix"
  fake_node="${root}/node/bin"
  mkdir -p "${prefix}" "${fake_node}"

  cat >"${fake_node}/corepack" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "pnpm" && "${2:-}" == "--version" ]]; then
  echo "10.29.2"
  exit 0
fi
if [[ "${1:-}" == "pnpm" ]]; then
  shift
  exec "${BASH_SOURCE%/*}/pnpm-real" "$@"
fi
exit 1
EOF
  chmod +x "${fake_node}/corepack"

  cat >"${fake_node}/pnpm-real" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  echo "10.29.2"
  exit 0
fi
echo "wrapped:$*"
EOF
  chmod +x "${fake_node}/pnpm-real"

  export PREFIX="${prefix}"
  export PATH="/usr/bin:/bin"
  set_pnpm_cmd "${fake_node}/corepack" pnpm

  ensure_pnpm_binary_for_scripts

  got="$(command -v pnpm || true)"
  assert_eq "$got" "${prefix}/bin/pnpm" "ensure_pnpm_binary_for_scripts wrapper path"
  out="$(pnpm --version)"
  assert_eq "$out" "10.29.2" "ensure_pnpm_binary_for_scripts wrapper version"
)

echo "==> case: ensure_pnpm_git_prepare_allowlist appends known dep"
(
  root="${TMP_DIR}/case-allowlist"
  repo="${root}/repo"
  mkdir -p "${repo}"
  cat >"${repo}/pnpm-workspace.yaml" <<'EOF'
packages:
  - .

onlyBuiltDependencies:
  - esbuild
EOF
  cat >"${repo}/package.json" <<'EOF'
{
  "name": "repo",
  "pnpm": {
    "onlyBuiltDependencies": [
      "esbuild"
    ]
  }
}
EOF

  ensure_pnpm_git_prepare_allowlist "${repo}"
  ensure_pnpm_git_prepare_allowlist "${repo}"

  workspace_count="$(grep -c '@tloncorp/api' "${repo}/pnpm-workspace.yaml" || true)"
  package_count="$(grep -c '@tloncorp/api' "${repo}/package.json" || true)"
  assert_eq "$workspace_count" "1" "ensure_pnpm_git_prepare_allowlist workspace count"
  assert_eq "$package_count" "1" "ensure_pnpm_git_prepare_allowlist package count"
)

echo "==> case: install_openclaw_from_git uses run_pnpm"
(
  root="${TMP_DIR}/case-install-git"
  repo="${root}/repo"
  prefix="${root}/prefix"
  home_dir="${root}/home"
  mkdir -p "${repo}/.git" "${repo}/dist" "${prefix}" "${home_dir}"
  : > "${repo}/dist/entry.js"

  export HOME="${home_dir}"
  export PREFIX="${prefix}"
  export GIT_UPDATE=0
  export SHARP_IGNORE_GLOBAL_LIBVIPS=1

  deps_cmd=""
  build_cmd=""

  ensure_git() { :; }
  ensure_pnpm() { set_pnpm_cmd echo pnpm; }
  ensure_pnpm_binary_for_scripts() { :; }
  cleanup_legacy_submodules() { :; }
  log() { :; }
  emit_json() { :; }
  fail() { echo "FAIL: $*" >&2; exit 1; }
  run_pnpm() {
    if [[ -z "$deps_cmd" ]]; then
      deps_cmd="$1"
    else
      build_cmd="$1"
    fi
    return 0
  }

  install_openclaw_from_git "${repo}"
  assert_eq "$deps_cmd" "-C" "install_openclaw_from_git deps command entry"
  assert_nonempty "$build_cmd" "install_openclaw_from_git build command entry"
  test -x "${prefix}/bin/openclaw"
)

echo "PASS"
