#!/usr/bin/env bash
# =============================================================================
# run-all.sh
# 01-lock-deps → 02-download-wheels → 03-package-for-transfer 전체 파이프라인
#
# 사용법:
#   bash scripts/run-all.sh
#   bash scripts/run-all.sh --modules=deps/agentic-ai
#   bash scripts/run-all.sh --modules=deps/agentic-ai,deps/database --clean
#   bash scripts/run-all.sh --modules=deps/agentic-ai --format=zip --clean
#
# * Python 버전은 각 deps/<모듈>/pyproject.toml 의 requires-python 을 따릅니다.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ----------------------------------------------------------------------------
# 기본값
# ----------------------------------------------------------------------------
MODULES=""
FORMAT="tar.gz"
CLEAN=false

# ----------------------------------------------------------------------------
# 인자 파싱
# ----------------------------------------------------------------------------
for arg in "$@"; do
    case "${arg}" in
        --modules=*)
            MODULES="${arg#*=}"
            ;;
        --format=*)
            FORMAT="${arg#*=}"
            ;;
        --clean)
            CLEAN=true
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --modules=   처리할 deps 폴더 (쉼표 구분, 미지정 시 전체)"
            echo "               예: --modules=deps/agentic-ai"
            echo "               예: --modules=deps/agentic-ai,deps/database"
            echo "  --format=    압축 포맷 (기본값: tar.gz, 선택: zip)"
            echo "  --clean      output/wheelhouse 초기화 후 실행"
            echo ""
            echo "  * Python 버전은 각 pyproject.toml 의 requires-python 을 따릅니다."
            echo ""
            echo "예시:"
            echo "  bash scripts/run-all.sh"
            echo "  bash scripts/run-all.sh --modules=deps/agentic-ai --clean"
            echo "  bash scripts/run-all.sh --modules=deps/agentic-ai,deps/database --format=zip --clean"
            exit 0
            ;;
        *)
            echo "[WARN] 알 수 없는 옵션: ${arg}" >&2
            ;;
    esac
done

# ----------------------------------------------------------------------------
# 헬퍼 함수
# ----------------------------------------------------------------------------
print_banner() {
    echo ""
    echo "============================================================"
    echo "  Python Wheelhouse Exporter"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================"
    echo "  모듈     : ${MODULES:-전체 자동 탐색}"
    echo "  Python   : pyproject.toml requires-python 기준"
    echo "  포맷     : ${FORMAT}"
    echo "  Clean    : ${CLEAN}"
    echo "============================================================"
    echo ""
}

run_step() {
    local step_num="$1"
    local step_name="$2"
    local script="$3"
    shift 3
    local args=("$@")

    echo ""
    echo "------------------------------------------------------------"
    echo "  [STEP ${step_num}] ${step_name}"
    echo "------------------------------------------------------------"

    if bash "${SCRIPT_DIR}/${script}" "${args[@]}"; then
        echo ""
        echo "  [STEP ${step_num}] 완료 ✓"
    else
        echo ""
        echo "  [STEP ${step_num}] 실패 ✗  →  파이프라인 중단"
        exit 1
    fi
}

# ----------------------------------------------------------------------------
# 실행
# ----------------------------------------------------------------------------
print_banner

START_TIME=$(date +%s)

# --clean: Step 1 실행 전에 output/wheelhouse 초기화
if [[ "${CLEAN}" == true ]]; then
    WHEELHOUSE_DIR="${PROJECT_ROOT}/output/wheelhouse"
    echo "------------------------------------------------------------"
    echo "  [PRE] output/wheelhouse 초기화 (--clean)"
    echo "------------------------------------------------------------"
    if [[ -d "${WHEELHOUSE_DIR}" ]]; then
        rm -rf "${WHEELHOUSE_DIR}"
        echo "  [OK] 초기화 완료"
    else
        echo "  [SKIP] output/wheelhouse 없음 (건너뜀)"
    fi
fi

# 공통 옵션 조립
COMMON_OPTS=()
[[ -n "${MODULES}" ]] && COMMON_OPTS+=("--modules=${MODULES}")

# STEP 1: uv lock + uv export → requirements.txt
run_step 1 "lock-deps (uv lock + uv export)" "01-lock-deps.sh" "${COMMON_OPTS[@]}"

# STEP 2: pip download → output/wheelhouse/
run_step 2 "download-wheels (pip download)" "02-download-wheels.sh" "${COMMON_OPTS[@]}"

# STEP 3: tar.gz / zip 압축
run_step 3 "package-for-transfer (압축)" "03-package-for-transfer.sh" "--format=${FORMAT}"

# ----------------------------------------------------------------------------
# 완료
# ----------------------------------------------------------------------------
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

echo ""
echo "============================================================"
echo "  [ALL DONE] 전체 파이프라인 완료"
echo "  소요 시간: ${ELAPSED_MIN}분 ${ELAPSED_SEC}초"
echo "  결과물: ${PROJECT_ROOT}/output/"
echo "============================================================"
echo ""
