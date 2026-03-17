#!/usr/bin/env bash
# =============================================================================
# run-all.sh
# 01-lock-deps → 02-download-wheels → 03-package-for-transfer 전체 파이프라인
#
# 의존성 잠금 → wheel 다운로드 → 압축 아카이브 생성까지 3단계를 순차 실행합니다.
# 중간 단계 실패 시 파이프라인을 즉시 중단합니다.
#
# 옵션:
#   --modules=       처리할 deps 폴더 (쉼표 구분)           [기본값: 전체 자동 탐색]
#   --format=        압축 포맷 (tar.gz | zip)               [기본값: tar.gz]
#   --platform=      타겟 플랫폼 (auto | rhel9 | custom)    [기본값: auto]
#   --platform-tag=  --platform=custom 일 때 플랫폼 태그    [기본값: 없음]
#   --clean          실행 전 output/wheelhouse, output/src 초기화  [기본값: false]
#
# 사용 예시:
#   bash scripts/run-all.sh                                          # 전체 모듈, 현재 OS 기준
#   bash scripts/run-all.sh --modules=deps/agentic-ai --clean        # 단일 모듈, 초기화 후 실행
#   bash scripts/run-all.sh --platform=rhel9 --clean                 # RHEL 9 x86_64 타겟
#   bash scripts/run-all.sh --modules=deps/agentic-ai,deps/database --format=zip --clean
#   bash scripts/run-all.sh --platform=custom --platform-tag=manylinux_2_28_aarch64
#
# 참고:
#   * Python 버전은 각 deps/<모듈>/pyproject.toml 의 requires-python 을 따릅니다.
#   * --platform=rhel9 사용 시 Windows/macOS 에서도 리눅스용 wheel 을 다운로드합니다.
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
PLATFORM=""
PLATFORM_TAG=""

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
        --platform=*)
            PLATFORM="${arg#*=}"
            ;;
        --platform-tag=*)
            PLATFORM_TAG="${arg#*=}"
            ;;
        --clean)
            CLEAN=true
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --modules=       처리할 deps 폴더 (쉼표 구분, 미지정 시 전체)"
            echo "                   예: --modules=deps/agentic-ai"
            echo "                   예: --modules=deps/agentic-ai,deps/database"
            echo "  --format=        압축 포맷 (기본값: tar.gz, 선택: zip)"
            echo "  --platform=      타겟 플랫폼 (기본: auto)"
            echo "                   auto   - 현재 시스템에 맞는 wheel 다운로드"
            echo "                   rhel9  - RHEL 9.x x86_64 타겟"
            echo "                   custom - --platform-tag 에 지정한 값 사용"
            echo "  --platform-tag=  custom 모드일 때 플랫폼 태그"
            echo "  --clean          output/wheelhouse, output/src 초기화 후 실행"
            echo ""
            echo "  * Python 버전은 각 pyproject.toml 의 requires-python 을 따릅니다."
            echo ""
            echo "예시:"
            echo "  bash scripts/run-all.sh"
            echo "  bash scripts/run-all.sh --modules=deps/agentic-ai --clean"
            echo "  bash scripts/run-all.sh --platform=rhel9 --clean"
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
    echo "  플랫폼   : ${PLATFORM:-auto}"
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

    echo ""
    echo "------------------------------------------------------------"
    echo "  [STEP ${step_num}] ${step_name}"
    echo "------------------------------------------------------------"

    if bash "${SCRIPT_DIR}/${script}" ${@+"$@"}; then
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

# --clean: Step 1 실행 전에 output/wheelhouse, output/src 초기화
if [[ "${CLEAN}" == true ]]; then
    WHEELHOUSE_DIR="${PROJECT_ROOT}/output/wheelhouse"
    SRC_DIR="${PROJECT_ROOT}/output/src"
    echo "------------------------------------------------------------"
    echo "  [PRE] output/wheelhouse, output/src 초기화 (--clean)"
    echo "------------------------------------------------------------"
    for dir in "${WHEELHOUSE_DIR}" "${SRC_DIR}"; do
        if [[ -d "${dir}" ]]; then
            rm -rf "${dir}"
            echo "  [OK] 삭제: ${dir##*/}/"
        fi
    done
    echo "  [OK] 초기화 완료"
fi

# 공통 옵션 조립 (모듈 지정)
COMMON_OPTS=()
[[ -n "${MODULES}" ]] && COMMON_OPTS+=("--modules=${MODULES}")

# download-wheels 전용 옵션 조립 (공통 + 플랫폼)
DOWNLOAD_OPTS=()
[[ -n "${MODULES}" ]] && DOWNLOAD_OPTS+=("--modules=${MODULES}")
[[ -n "${PLATFORM}" ]] && DOWNLOAD_OPTS+=("--platform=${PLATFORM}")
[[ -n "${PLATFORM_TAG}" ]] && DOWNLOAD_OPTS+=("--platform-tag=${PLATFORM_TAG}")

# STEP 1: uv lock + uv export → requirements.txt
run_step 1 "lock-deps (uv lock + uv export)" "01-lock-deps.sh" \
    ${COMMON_OPTS[@]+"${COMMON_OPTS[@]}"}

# STEP 2: uv run pip download → output/wheelhouse/
run_step 2 "download-wheels (uv run pip download)" "02-download-wheels.sh" \
    ${DOWNLOAD_OPTS[@]+"${DOWNLOAD_OPTS[@]}"}

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
