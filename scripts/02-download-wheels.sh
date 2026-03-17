#!/usr/bin/env bash
# =============================================================================
# 02-download-wheels.sh
# uv run pip download → output/wheelhouse/ (.whl), output/src/ (소스)
#
# 각 deps/<모듈>/requirements.txt 에 명시된 패키지의 wheel(.whl) 파일을 다운로드합니다.
# 크로스 플랫폼 다운로드를 지원하여, Windows/macOS 빌드 머신에서
# RHEL 9 등 리눅스 서버용 wheel 을 받을 수 있습니다.
#
# 다운로드 전략 (2단계 fallback):
#   1차) --only-binary :all: --no-deps → wheel 만 다운로드 (플랫폼 지정 가능)
#   2차) 소스(.tar.gz) 포함 재시도 (플랫폼 지정 불가 — pip 제약)
#        ※ 2차 fallback 으로 받은 소스 패키지는 폐쇄망 서버에서 직접 빌드해야 합니다.
#
# 출력 구조:
#   output/wheelhouse/  ← .whl 파일 (바이너리 + pure Python)
#   output/src/         ← .tar.gz/.zip 소스 패키지 (wheel 미제공 패키지)
#
# 옵션:
#   --modules=       처리할 deps 폴더 (쉼표 구분)           [기본값: deps/ 하위 전체 자동 탐색]
#   --platform=      타겟 플랫폼                            [기본값: auto]
#                      auto   - 현재 시스템에 맞는 wheel 다운로드
#                      rhel9  - RHEL 9.x x86_64 (manylinux_2_34/2_28/2014 + linux_x86_64)
#                      custom - --platform-tag 에 지정한 값 사용
#   --platform-tag=  --platform=custom 일 때 플랫폼 태그    [기본값: 없음]
#                      예: manylinux_2_28_aarch64
#
# 사용 예시:
#   bash scripts/02-download-wheels.sh                                          # 전체, auto
#   bash scripts/02-download-wheels.sh --modules=deps/agentic-ai                # 단일 모듈
#   bash scripts/02-download-wheels.sh --modules=deps/agentic-ai,deps/database  # 복수 모듈
#   bash scripts/02-download-wheels.sh --platform=rhel9                         # RHEL 9 타겟
#   bash scripts/02-download-wheels.sh --platform=custom --platform-tag=manylinux_2_28_aarch64
#
# 참고:
#   * 사전 조건: 01-lock-deps.sh 실행 후 각 모듈에 requirements.txt 가 있어야 합니다.
#   * Python 버전은 각 모듈의 pyproject.toml requires-python 에서 자동 결정됩니다.
#   * uv 가 관리하는 venv 에는 pip 이 없으므로 uv run pip download 을 사용합니다.
# =============================================================================

set -euo pipefail

# ----------------------------------------------------------------------------
# 경로 설정
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/output"
WHEELHOUSE_DIR="${OUTPUT_DIR}/wheelhouse"       # .whl 파일 저장
SRC_DIR="${OUTPUT_DIR}/src"                      # 소스 패키지(.tar.gz/.zip) 저장
TMP_DIR="${OUTPUT_DIR}/wheelhouse-tmp"           # 다운로드 임시 디렉터리 (처리 후 삭제)
LOG_FILE="${OUTPUT_DIR}/download-wheels.log"

# ----------------------------------------------------------------------------
# 기본값
# ----------------------------------------------------------------------------
MODULES=""
TARGET_PLATFORM="auto"      # auto | rhel9 | custom
CUSTOM_PLATFORM_TAG=""       # --platform=custom 일 때 사용할 플랫폼 태그

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
        --platform=*)
            TARGET_PLATFORM="${arg#*=}"
            ;;
        --platform-tag=*)
            CUSTOM_PLATFORM_TAG="${arg#*=}"
            ;;
        --help|-h)
            echo "Usage: $0 [--modules=deps/<name>[,...]] [--platform=auto|rhel9|custom]"
            echo ""
            echo "Options:"
            echo "  --modules=       처리할 deps 폴더 (쉼표 구분, 미지정 시 전체 자동 탐색)"
            echo "  --platform=      타겟 플랫폼 (기본: auto)"
            echo "                     auto   - 현재 시스템에 맞는 wheel 다운로드"
            echo "                     rhel9  - RHEL 9.x x86_64 (manylinux_2_34/2_28/2014)"
            echo "                     custom - --platform-tag 에 지정한 값 사용"
            echo "  --platform-tag=  custom 모드일 때 사용할 플랫폼 태그"
            echo "                     예: manylinux_2_28_aarch64"
            exit 0
            ;;
        *)
            echo "[WARN] 알 수 없는 옵션: ${arg}" >&2
            ;;
    esac
done

# ----------------------------------------------------------------------------
# 플랫폼별 pip download 옵션 구성
#
# pip download 의 --platform 옵션은 --only-binary :all: 와 함께 사용해야 합니다.
# 여러 --platform 을 지정하면 pip 이 호환되는 wheel 을 넓게 검색합니다.
#
# manylinux 태그와 glibc 호환성:
#   manylinux2014  = glibc 2.17 (CentOS 7+, 가장 폭넓은 호환)
#   manylinux_2_28 = glibc 2.28 (RHEL 8+, 많은 최신 패키지가 사용)
#   manylinux_2_34 = glibc 2.34 (RHEL 9 정확히 일치)
#   linux_x86_64   = 네이티브 리눅스 (일부 패키지가 이 태그 사용)
# ----------------------------------------------------------------------------
declare -a PLATFORM_OPTS=()

case "${TARGET_PLATFORM}" in
    rhel9)
        # RHEL 9.x (glibc 2.34) x86_64 호환 플랫폼 태그
        PLATFORM_OPTS+=(
            --platform manylinux2014_x86_64
            --platform manylinux_2_28_x86_64
            --platform manylinux_2_34_x86_64
            --platform linux_x86_64
        )
        ;;
    custom)
        if [[ -z "${CUSTOM_PLATFORM_TAG}" ]]; then
            echo "[ERROR] --platform=custom 사용 시 --platform-tag= 를 지정해야 합니다."
            exit 1
        fi
        PLATFORM_OPTS+=(--platform "${CUSTOM_PLATFORM_TAG}")
        ;;
    auto)
        # 플랫폼 옵션 없음 → pip 가 현재 시스템에 맞게 자동 감지
        ;;
    *)
        echo "[ERROR] 알 수 없는 플랫폼: ${TARGET_PLATFORM}"
        echo "        사용 가능: auto, rhel9, custom"
        exit 1
        ;;
esac

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

# uv 가 관리하는 venv 에는 pip 이 설치되어 있지 않으므로
# 각 모듈 디렉터리에서 uv run pip download 을 사용합니다.

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
    # --modules 옵션으로 지정된 모듈만 처리
    IFS=',' read -ra RAW_MODULES <<< "${MODULES}"
    for m in "${RAW_MODULES[@]}"; do
        m="${m// /}"    # 공백 제거
        if [[ -d "${PROJECT_ROOT}/${m}" ]]; then
            MODULE_LIST+=("${PROJECT_ROOT}/${m}")
        else
            log "[WARN] 모듈 디렉터리를 찾을 수 없습니다: ${PROJECT_ROOT}/${m}"
        fi
    done
else
    # 미지정 시 deps/ 하위 pyproject.toml 이 있는 모든 디렉터리를 자동 탐색
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

    # ── Python 버전 및 ABI 태그 결정 ──────────────────────────────────
    # uv 가 resolve 한 Python 버전을 동적으로 획득합니다.
    # 이 버전은 각 모듈의 pyproject.toml requires-python 에 의해 결정됩니다.
    REQUIRES_PYTHON=$(cd "${MODULE_DIR}" && uv run python -c \
        "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
    if [[ -z "${REQUIRES_PYTHON}" ]]; then
        log "[WARN] Python 버전을 확인하지 못했습니다. 기본값 3.12 사용"
        REQUIRES_PYTHON="3.12"
    fi
    log "[INFO] 타겟 Python: ${REQUIRES_PYTHON} (uv resolve 기준)"

    # ABI 태그 구성 (예: Python 3.12 → cp312)
    # pip download 에 --platform 지정 시 --abi 도 함께 전달해야 올바른 wheel 을 매칭합니다.
    #   - cp312 : C 확장이 포함된 바이너리 wheel 용 (예: numpy, pandas)
    #   - none  : pure Python wheel 용 (예: httpx, fastapi — py3-none-any.whl)
    PY_ABI="cp${REQUIRES_PYTHON//./}"

    # 플랫폼 옵션이 지정된 경우에만 ABI 옵션을 추가
    declare -a DOWNLOAD_PLATFORM_OPTS=()
    if [[ ${#PLATFORM_OPTS[@]} -gt 0 ]]; then
        DOWNLOAD_PLATFORM_OPTS=("${PLATFORM_OPTS[@]}" --abi "${PY_ABI}" --abi none)
        log "[INFO] 타겟 플랫폼: ${TARGET_PLATFORM} (ABI: ${PY_ABI}, none)"
    else
        log "[INFO] 타겟 플랫폼: auto (현재 시스템 자동 감지)"
    fi

    # ── requirements.txt 플랫폼 마커 필터링 ──────────────────────────
    # pip download 에 --platform 을 명시하면 환경 마커(; sys_platform == 'win32' 등)를
    # 평가하지 않고 모든 패키지를 다운로드 시도합니다. (pip 의 알려진 동작)
    #
    # 예: pywin32 ; sys_platform == 'win32' → Linux 타겟에서 다운로드 시도 → 실패
    #
    # 이를 방지하기 위해 크로스 플랫폼 모드일 때 타겟 OS 와 호환되지 않는
    # 마커가 붙은 행을 requirements.txt 에서 제거한 임시 파일을 생성합니다.
    EFFECTIVE_REQUIREMENTS="${REQUIREMENTS_FILE}"

    if [[ "${TARGET_PLATFORM}" == "rhel9" || "${TARGET_PLATFORM}" == "custom" ]]; then
        FILTERED_REQUIREMENTS="${TMP_DIR}/requirements-filtered.txt"
        mkdir -p "${TMP_DIR}"

        # Linux 타겟: Windows 전용 패키지 제외
        # - sys_platform == 'win32'
        # - platform_system == 'Windows'
        # 반대로 Linux 전용 마커(sys_platform == 'linux' 등)는 유지
        grep -v -E "sys_platform\s*==\s*['\"]win32['\"]|platform_system\s*==\s*['\"]Windows['\"]" \
            "${REQUIREMENTS_FILE}" > "${FILTERED_REQUIREMENTS}" || true

        FILTERED_COUNT=$(( $(wc -l < "${REQUIREMENTS_FILE}") - $(wc -l < "${FILTERED_REQUIREMENTS}") ))
        if [[ ${FILTERED_COUNT} -gt 0 ]]; then
            log "[INFO] 타겟 플랫폼과 호환되지 않는 패키지 ${FILTERED_COUNT} 개 제외 (Windows 전용)"
        fi

        EFFECTIVE_REQUIREMENTS="${FILTERED_REQUIREMENTS}"
    fi

    # ── 임시 디렉터리에 다운로드 ──────────────────────────────────────
    mkdir -p "${TMP_DIR}"

    # 1차 시도: wheel 전용 다운로드
    #
    # --only-binary :all: : 소스 패키지를 제외하고 wheel 만 다운로드
    # --no-deps          : pip 의 자체 의존성 해석을 비활성화
    #
    # --no-deps 를 사용하는 이유:
    #   requirements.txt 는 uv export 가 생성한 완전한 flat 의존성 목록입니다.
    #   (모든 transitive 의존성이 이미 포함되어 있음)
    #   pip 이 --platform 모드에서 자체적으로 의존성을 다시 resolve 하면
    #   환경 마커를 무시하여 타겟 플랫폼에 존재하지 않는 패키지
    #   (예: pywin32 — Windows 전용)를 요구하는 문제가 발생합니다.
    #   --no-deps 로 이 문제를 회피하고, 이미 resolve 된 목록을 그대로 다운로드합니다.
    log "[STEP 1] wheel 다운로드 (--only-binary :all: --no-deps)..."
    if ! (cd "${MODULE_DIR}" && uv run pip download \
        --no-deps \
        --python-version "${REQUIRES_PYTHON}" \
        --only-binary :all: \
        ${DOWNLOAD_PLATFORM_OPTS[@]+"${DOWNLOAD_PLATFORM_OPTS[@]}"} \
        --dest "${TMP_DIR}" \
        -r "${EFFECTIVE_REQUIREMENTS}") \
        2>&1 | tee -a "${LOG_FILE}"; then

        # 2차 시도: 소스 패키지 포함 재시도
        #
        # pip 제약사항:
        #   --platform, --abi, --python-version 옵션은 --only-binary :all: 와 함께만 사용 가능
        #   소스 패키지를 허용하려면 이 옵션들을 모두 제거해야 합니다.
        #
        # 전략:
        #   1차에서 이미 받은 wheel 은 TMP_DIR 에 남아있으므로 보존합니다.
        #   2차에서는 uv run 이 모듈의 venv Python(pyproject.toml requires-python 기준)을
        #   사용하므로 올바른 Python 버전으로 다운로드됩니다.
        #   --no-deps 유지: requirements.txt 가 이미 flat 목록이므로 재해석 불필요
        #
        # ⚠ 주의 (크로스 플랫폼 모드):
        #   소스 패키지(.tar.gz)는 폐쇄망 타겟 서버에서 빌드 도구(gcc 등)로
        #   직접 빌드해야 합니다.
        log "[WARN] 일부 패키지 wheel 없음. 소스 포함하여 재시도..."
        log "[WARN] ※ 플랫폼/ABI/python-version 지정 해제 (pip 제약)"
        if ! (cd "${MODULE_DIR}" && uv run pip download \
            --no-deps \
            --prefer-binary \
            --dest "${TMP_DIR}" \
            -r "${EFFECTIVE_REQUIREMENTS}") \
            2>&1 | tee -a "${LOG_FILE}"; then
            log "[ERROR] pip download 실패: ${MODULE_NAME}"
            rm -rf "${TMP_DIR}"
            exit 1
        fi
    fi

    # ── wheel / 소스 분리 ─────────────────────────────────────────────
    # .whl 파일은 output/wheelhouse/ 로, .tar.gz/.zip 소스는 output/src/ 로 분리합니다.
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
        log "  [SRC] $(basename "${f}") → src/"
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
    WHL_SIZE=$(du -sh "${WHEELHOUSE_DIR}" 2>/dev/null | cut -f1)
    SRC_SIZE=$(du -sh "${SRC_DIR}" 2>/dev/null | cut -f1)
else
    WHL_SIZE="(계산 불가)"
    SRC_SIZE="(계산 불가)"
fi

log "============================================================"
log "[DONE] download-wheels 완료"
log "  처리한 모듈 수     : ${#MODULE_LIST[@]}"
log "  타겟 플랫폼        : ${TARGET_PLATFORM}"
log "  총 wheel 패키지 수 : ${TOTAL_WHL} (${WHL_SIZE})"
log "  총 소스 패키지 수  : ${TOTAL_SRC} (${SRC_SIZE})"
log "  wheel 출력 경로    : ${WHEELHOUSE_DIR}"
log "  소스 출력 경로     : ${SRC_DIR}"
if [[ ${TOTAL_SRC} -gt 0 ]]; then
    log ""
    log "  [주의] 소스 패키지는 폐쇄망 서버에서 빌드 도구(gcc 등)가 필요합니다."
fi
log "  로그 파일          : ${LOG_FILE}"
log "============================================================"
