#!/usr/bin/env bash
# =============================================================================
# 02-download-wheels.sh
# pip download → output/wheelhouse/ (.whl), output/wheelhouse/src/ (소스)
#
# 사전 조건: 01-lock-deps.sh 실행 후 각 모듈에 requirements.txt 가 있어야 합니다.
#
# 사용법:
#   bash scripts/02-download-wheels.sh
#   bash scripts/02-download-wheels.sh --modules=deps/agentic-ai
#   bash scripts/02-download-wheels.sh --modules=deps/agentic-ai,deps/database
# =============================================================================

set -euo pipefail

# ----------------------------------------------------------------------------
# 경로 설정
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/output"
WHEELHOUSE_DIR="${OUTPUT_DIR}/wheelhouse"
SRC_DIR="${WHEELHOUSE_DIR}/src"
TMP_DIR="${OUTPUT_DIR}/wheelhouse-tmp"
LOG_FILE="${OUTPUT_DIR}/download-wheels.log"

# ----------------------------------------------------------------------------
# 기본값
# ----------------------------------------------------------------------------
MODULES=""

source $HOME/.local/bin/env 2>/dev/null || true  # uv 설치 후 바로 사용할 수 있도록 env 로드 (선택적)

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

if ! command -v pip &>/dev/null; then
    echo "[ERROR] pip 가 설치되어 있지 않습니다."
    exit 1
fi

# pip 최신 버전으로 업그레이드
echo "[INFO] pip 업그레이드 중..."
python -m pip install --upgrade pip --quiet

# ----------------------------------------------------------------------------
# output 디렉터리 초기화
# ----------------------------------------------------------------------------
mkdir -p "${OUTPUT_DIR}" "${WHEELHOUSE_DIR}" "${SRC_DIR}"

echo "=== download-wheels $(date '+%Y-%m-%d %H:%M:%S') ===" >> "${LOG_FILE}"

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
        m="${m// /}"
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
TOTAL_WHL=0
TOTAL_SRC=0

for MODULE_DIR in "${MODULE_LIST[@]}"; do
    MODULE_NAME="$(basename "${MODULE_DIR}")"
    REQUIREMENTS_FILE="${MODULE_DIR}/requirements.txt"

    log "------------------------------------------------------------"
    log "[INFO] 다운로드 중: ${MODULE_NAME}"
    log "------------------------------------------------------------"

    if [[ ! -f "${REQUIREMENTS_FILE}" ]]; then
        log "[ERROR] requirements.txt 가 없습니다. 01-lock-deps.sh 를 먼저 실행하세요."
        log "        경로: ${REQUIREMENTS_FILE}"
        exit 1
    fi

    # uv 가 resolve 한 Python 버전 동적 획득
    REQUIRES_PYTHON=$(cd "${MODULE_DIR}" && uv run python -c \
        "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
    if [[ -z "${REQUIRES_PYTHON}" ]]; then
        log "[WARN] Python 버전을 확인하지 못했습니다. 기본값 3.12 사용"
        REQUIRES_PYTHON="3.12"
    fi
    log "[INFO] 타겟 Python: ${REQUIRES_PYTHON} (uv resolve 기준)"

    # 임시 디렉터리에 다운로드
    mkdir -p "${TMP_DIR}"

    # 1차 시도: wheel 전용 (--only-binary :all:)
    log "[STEP 1] wheel 다운로드 (--only-binary :all:)..."
    if ! pip download \
        --prefer-binary \
        --python-version "${REQUIRES_PYTHON}" \
        --only-binary :all: \
        --dest "${TMP_DIR}" \
        -r "${REQUIREMENTS_FILE}" \
        2>&1 | tee -a "${LOG_FILE}"; then

        # 2차 시도: wheel 없는 패키지는 소스로 fallback
        # --python-version 은 소스 패키지와 함께 사용 불가하므로 제외
        log "[WARN] 일부 패키지 wheel 없음. 소스 포함하여 재시도..."
        if ! pip download \
            --prefer-binary \
            --dest "${TMP_DIR}" \
            -r "${REQUIREMENTS_FILE}" \
            2>&1 | tee -a "${LOG_FILE}"; then
            log "[ERROR] pip download 실패: ${MODULE_NAME}"
            rm -rf "${TMP_DIR}"
            exit 1
        fi
    fi

    # wheel / 소스 분리
    log "[STEP 2] wheel / 소스 분리..."
    WHL_COUNT=0
    SRC_COUNT=0

    while IFS= read -r -d '' f; do
        mv "${f}" "${WHEELHOUSE_DIR}/"
        WHL_COUNT=$((WHL_COUNT + 1))
    done < <(find "${TMP_DIR}" -maxdepth 1 -name "*.whl" -print0 2>/dev/null)

    while IFS= read -r -d '' f; do
        mv "${f}" "${SRC_DIR}/"
        SRC_COUNT=$((SRC_COUNT + 1))
        log "  [SRC] $(basename "${f}") → wheelhouse/src/"
    done < <(find "${TMP_DIR}" -maxdepth 1 \( -name "*.tar.gz" -o -name "*.zip" \) -print0 2>/dev/null)

    rm -rf "${TMP_DIR}"

    TOTAL_WHL=$((TOTAL_WHL + WHL_COUNT))
    TOTAL_SRC=$((TOTAL_SRC + SRC_COUNT))

    log "[OK] wheel: ${WHL_COUNT} 개, 소스: ${SRC_COUNT} 개"
    log ""

    # 다운로드 목록 출력
    log "[목록] ${MODULE_NAME} wheel 패키지:"
    find "${WHEELHOUSE_DIR}" -maxdepth 1 -name "*.whl" \
        -exec basename {} \; 2>/dev/null | sort | while read -r f; do
        log "  ${f}"
    done

    if [[ ${SRC_COUNT} -gt 0 ]]; then
        log "[목록] ${MODULE_NAME} 소스 패키지 (폐쇄망 서버에서 빌드 필요):"
        find "${SRC_DIR}" -maxdepth 1 \( -name "*.tar.gz" -o -name "*.zip" \) \
            -exec basename {} \; 2>/dev/null | sort | while read -r f; do
            log "  ${f}"
        done
    fi
    log ""
done

# ----------------------------------------------------------------------------
# 완료 요약
# ----------------------------------------------------------------------------
if command -v du &>/dev/null; then
    TOTAL_SIZE=$(du -sh "${WHEELHOUSE_DIR}" 2>/dev/null | cut -f1)
else
    TOTAL_SIZE="(계산 불가)"
fi

log "============================================================"
log "[DONE] download-wheels 완료"
log "  처리한 모듈 수     : ${#MODULE_LIST[@]}"
log "  총 wheel 패키지 수 : ${TOTAL_WHL}"
log "  총 소스 패키지 수  : ${TOTAL_SRC}"
log "  총 용량            : ${TOTAL_SIZE}"
log "  출력 경로          : ${WHEELHOUSE_DIR}"
if [[ ${TOTAL_SRC} -gt 0 ]]; then
    log ""
    log "  [주의] 소스 패키지는 폐쇄망 서버에서 빌드 도구(gcc 등)가 필요합니다."
    log "         위치: ${SRC_DIR}"
fi
log "  로그 파일          : ${LOG_FILE}"
log "============================================================"
