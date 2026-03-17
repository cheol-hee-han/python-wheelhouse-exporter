#!/usr/bin/env bash
# =============================================================================
# 01-lock-deps.sh
# uv lock + uv export → requirements.txt 생성
#
# 각 deps/<모듈>/pyproject.toml 의 의존성을 resolve 하여 uv.lock 을 생성하고,
# 운영 배포용(dev 제외) requirements.txt 를 추출합니다.
#
# 옵션:
#   --modules=   처리할 deps 폴더 (쉼표 구분)   [기본값: deps/ 하위 전체 자동 탐색]
#
# 사용 예시:
#   bash scripts/01-lock-deps.sh                                     # 전체 모듈
#   bash scripts/01-lock-deps.sh --modules=deps/agentic-ai           # 단일 모듈
#   bash scripts/01-lock-deps.sh --modules=deps/agentic-ai,deps/database  # 복수 모듈
#
# 참고:
#   * Python 버전은 각 deps/<모듈>/pyproject.toml 의 requires-python 을 따릅니다.
#   * 사전 조건: uv 가 설치되어 있어야 합니다.
# =============================================================================

set -euo pipefail

# ----------------------------------------------------------------------------
# 경로 설정
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/output"
LOG_FILE="${OUTPUT_DIR}/lock-deps.log"

# ----------------------------------------------------------------------------
# 기본값
# ----------------------------------------------------------------------------
MODULES=""

# uv 설치 후 PATH 에 등록되지 않은 경우를 위해 env 로드 (선택적, 실패 무시)
source "$HOME/.local/bin/env" 2>/dev/null || true

# ----------------------------------------------------------------------------
# 인자 파싱
# ----------------------------------------------------------------------------
for arg in "$@"; do
    case "${arg}" in
        --modules=*)
            MODULES="${arg#*=}"
            ;;
        --help|-h)
            echo "Usage: $0 [--modules=deps/<name>[,deps/<name>,...]]"
            echo ""
            echo "Options:"
            echo "  --modules=   처리할 deps 폴더 (쉼표 구분, 미지정 시 전체 자동 탐색)"
            echo ""
            echo "  * Python 버전은 각 pyproject.toml 의 requires-python 을 따릅니다."
            exit 0
            ;;
        *)
            echo "[WARN] 알 수 없는 옵션: ${arg}" >&2
            ;;
    esac
done

# ----------------------------------------------------------------------------
# 사전 조건 검사
# ----------------------------------------------------------------------------
if ! command -v uv &>/dev/null; then
    echo "[ERROR] uv 가 설치되어 있지 않습니다."
    echo ""
    echo "설치 방법:"
    echo "  pip install uv"
    echo "  또는: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

# ----------------------------------------------------------------------------
# output 디렉터리 초기화
# ----------------------------------------------------------------------------
mkdir -p "${OUTPUT_DIR}"

echo "=== lock-deps $(date '+%Y-%m-%d %H:%M:%S') ===" >> "${LOG_FILE}"

log() {
    local msg="$1"
    echo "${msg}"
    echo "${msg}" >> "${LOG_FILE}"
}

# ----------------------------------------------------------------------------
# 처리할 모듈 목록 결정
# ----------------------------------------------------------------------------
declare -a MODULE_LIST=()

if [[ -n "${MODULES}" ]]; then
    IFS=',' read -ra RAW_MODULES <<< "${MODULES}"
    for m in "${RAW_MODULES[@]}"; do
        m="${m// /}"  # 공백 제거
        if [[ -d "${PROJECT_ROOT}/${m}" ]]; then
            MODULE_LIST+=("${PROJECT_ROOT}/${m}")
        else
            log "[WARN] 모듈 디렉터리를 찾을 수 없습니다: ${PROJECT_ROOT}/${m}"
        fi
    done
else
    while IFS= read -r -d '' dir; do
        MODULE_LIST+=("${dir%/pyproject.toml}")
    done < <(find "${PROJECT_ROOT}/deps" -maxdepth 2 -name "pyproject.toml" -print0 2>/dev/null)
fi

if [[ ${#MODULE_LIST[@]} -eq 0 ]]; then
    log "[ERROR] 처리할 모듈이 없습니다. deps/ 디렉터리를 확인하세요."
    exit 1
fi

log "[INFO] 처리할 모듈 수: ${#MODULE_LIST[@]}"
for m in "${MODULE_LIST[@]}"; do
    log "  - ${m}"
done
log ""

# ----------------------------------------------------------------------------
# 모듈별 처리
# ----------------------------------------------------------------------------
for MODULE_DIR in "${MODULE_LIST[@]}"; do
    MODULE_NAME="$(basename "${MODULE_DIR}")"

    log "------------------------------------------------------------"
    log "[INFO] 처리 중: ${MODULE_NAME}"
    log "------------------------------------------------------------"

    if [[ ! -f "${MODULE_DIR}/pyproject.toml" ]]; then
        log "[WARN] pyproject.toml 이 없습니다. 건너뜁니다: ${MODULE_DIR}"
        continue
    fi

    # 1) uv lock (Python 버전은 pyproject.toml requires-python 기준)
    log "[STEP 1] uv lock 실행..."
    if ! (cd "${MODULE_DIR}" && uv lock 2>&1 | tee -a "${LOG_FILE}"); then
        log "[ERROR] uv lock 실패: ${MODULE_NAME}"
        exit 1
    fi
    log "[OK] uv.lock 생성 완료"

    # 2) requirements.txt 추출 (dev 그룹 제외 - 운영 배포용 wheelhouse)
    log "[STEP 2] requirements.txt 생성 (uv export)..."
    if ! (cd "${MODULE_DIR}" && uv export \
        --format requirements-txt \
        --no-hashes \
        --no-dev \
        --output-file requirements.txt \
        2>&1 | tee -a "${LOG_FILE}"); then
        log "[ERROR] uv export 실패: ${MODULE_NAME}"
        exit 1
    fi
    log "[OK] requirements.txt 생성 완료: ${MODULE_DIR}/requirements.txt"
    log ""
done

# ----------------------------------------------------------------------------
# 완료 요약
# ----------------------------------------------------------------------------
log "============================================================"
log "[DONE] lock-deps 완료"
log "  처리한 모듈 수 : ${#MODULE_LIST[@]}"
log "  로그 파일      : ${LOG_FILE}"
log "============================================================"
