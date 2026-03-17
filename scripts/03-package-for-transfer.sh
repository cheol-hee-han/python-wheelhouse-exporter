#!/usr/bin/env bash
# =============================================================================
# 03-package-for-transfer.sh
# output/wheelhouse 와 output/src 를 tar.gz 또는 zip 으로 압축
#
# 02-download-wheels.sh 로 다운로드된 wheel 과 소스 패키지를 하나의 아카이브로 묶어
# 폐쇄망 서버로 전송할 수 있는 형태로 패키징합니다.
# 파일명에 타임스탬프가 포함됩니다. (예: wheelhouse_20260317_120000.tar.gz)
#
# 압축 대상:
#   output/wheelhouse/  ← .whl 파일 (항상 포함)
#   output/src/         ← .tar.gz/.zip 소스 패키지 (파일이 있을 때만 포함)
#
# 옵션:
#   --format=   압축 포맷 (tar.gz | zip)   [기본값: tar.gz]
#
# 사용 예시:
#   bash scripts/03-package-for-transfer.sh                  # tar.gz (기본)
#   bash scripts/03-package-for-transfer.sh --format=zip     # zip 포맷
#   bash scripts/03-package-for-transfer.sh --format=tar.gz  # tar.gz 명시
#
# 참고:
#   * 사전 조건: 02-download-wheels.sh 실행 후 output/wheelhouse/ 에 파일이 있어야 합니다.
#   * zip 포맷 사용 시 zip 명령어가 설치되어 있어야 합니다.
# =============================================================================

set -euo pipefail

# ----------------------------------------------------------------------------
# 경로 설정
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/output"
WHEELHOUSE_DIR="${OUTPUT_DIR}/wheelhouse"
SRC_DIR="${OUTPUT_DIR}/src"
LOG_FILE="${OUTPUT_DIR}/package-transfer.log"

# ----------------------------------------------------------------------------
# 기본값
# ----------------------------------------------------------------------------
FORMAT="tar.gz"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"

# ----------------------------------------------------------------------------
# 인자 파싱
# ----------------------------------------------------------------------------
for arg in "$@"; do
    case "${arg}" in
        --format=*)
            FORMAT="${arg#*=}"
            ;;
        --help|-h)
            echo "Usage: $0 [--format=tar.gz|zip]"
            echo ""
            echo "Options:"
            echo "  --format=   압축 포맷 (기본값: tar.gz, 선택: zip)"
            exit 0
            ;;
        *)
            echo "[WARN] 알 수 없는 옵션: ${arg}" >&2
            ;;
    esac
done

# ----------------------------------------------------------------------------
# 검증
# ----------------------------------------------------------------------------
if [[ ! -d "${WHEELHOUSE_DIR}" ]]; then
    echo "[ERROR] wheelhouse 디렉터리가 없습니다: ${WHEELHOUSE_DIR}"
    echo "        02-download-wheels.sh 를 먼저 실행하세요."
    exit 1
fi

WHL_COUNT=$(find "${WHEELHOUSE_DIR}" -maxdepth 1 -name "*.whl" 2>/dev/null | wc -l)
if [[ "${WHL_COUNT}" -eq 0 ]]; then
    echo "[ERROR] wheelhouse 에 .whl 파일이 없습니다."
    echo "        01-lock-deps.sh 와 02-download-wheels.sh 를 먼저 실행하세요."
    exit 1
fi

# src/ 디렉터리에 소스 패키지가 있는지 확인
SRC_COUNT=0
HAS_SRC=false
if [[ -d "${SRC_DIR}" ]]; then
    SRC_COUNT=$(find "${SRC_DIR}" -maxdepth 1 \( -name "*.tar.gz" -o -name "*.zip" \) 2>/dev/null | wc -l)
    if [[ "${SRC_COUNT}" -gt 0 ]]; then
        HAS_SRC=true
    fi
fi

TOTAL_COUNT=$((WHL_COUNT + SRC_COUNT))

mkdir -p "${OUTPUT_DIR}"
echo "=== package-for-transfer $(date '+%Y-%m-%d %H:%M:%S') ===" >> "${LOG_FILE}"

log() {
    local msg="$1"
    echo "${msg}"
    echo "${msg}" >> "${LOG_FILE}"
}

# ----------------------------------------------------------------------------
# 압축 대상 목록 구성
# wheelhouse/ 는 항상 포함, src/ 는 소스 패키지가 있을 때만 포함
# ----------------------------------------------------------------------------
declare -a ARCHIVE_TARGETS=("wheelhouse/")
if [[ "${HAS_SRC}" == true ]]; then
    ARCHIVE_TARGETS+=("src/")
fi

log "[INFO] 압축 대상:"
log "  - wheelhouse/ (${WHL_COUNT} 개 wheel)"
if [[ "${HAS_SRC}" == true ]]; then
    log "  - src/        (${SRC_COUNT} 개 소스 패키지)"
fi

# ----------------------------------------------------------------------------
# 압축 실행
# ----------------------------------------------------------------------------
case "${FORMAT}" in
    tar.gz|tgz)
        ARCHIVE_NAME="wheelhouse_${TIMESTAMP}.tar.gz"
        ARCHIVE_PATH="${OUTPUT_DIR}/${ARCHIVE_NAME}"

        log "[INFO] tar.gz 압축 중..."
        log "       출력: ${ARCHIVE_PATH}"

        (cd "${OUTPUT_DIR}" && tar -czf "${ARCHIVE_NAME}" "${ARCHIVE_TARGETS[@]}")

        log "[OK] 압축 완료: ${ARCHIVE_NAME}"
        ;;

    zip)
        # zip 명령어 존재 여부 확인
        if ! command -v zip &>/dev/null; then
            echo "[ERROR] zip 명령어를 찾을 수 없습니다. tar.gz 포맷을 사용하거나 zip 을 설치하세요."
            exit 1
        fi

        ARCHIVE_NAME="wheelhouse_${TIMESTAMP}.zip"
        ARCHIVE_PATH="${OUTPUT_DIR}/${ARCHIVE_NAME}"

        log "[INFO] zip 압축 중..."
        log "       출력: ${ARCHIVE_PATH}"

        (cd "${OUTPUT_DIR}" && zip -r "${ARCHIVE_NAME}" "${ARCHIVE_TARGETS[@]}" -x "*.DS_Store")

        log "[OK] 압축 완료: ${ARCHIVE_NAME}"
        ;;

    *)
        echo "[ERROR] 지원하지 않는 포맷: ${FORMAT} (지원: tar.gz, zip)"
        exit 1
        ;;
esac

# ----------------------------------------------------------------------------
# 결과 통계
# ----------------------------------------------------------------------------
if [[ -f "${ARCHIVE_PATH}" ]]; then
    if command -v du &>/dev/null; then
        ARCHIVE_SIZE=$(du -sh "${ARCHIVE_PATH}" 2>/dev/null | cut -f1)
    else
        ARCHIVE_SIZE="(계산 불가)"
    fi

    log ""
    log "============================================================"
    log "[DONE] 패키지 생성 완료"
    log "  파일명             : ${ARCHIVE_NAME}"
    log "  경로               : ${ARCHIVE_PATH}"
    log "  파일 크기          : ${ARCHIVE_SIZE}"
    log "  포함 wheel 수      : ${WHL_COUNT} 개"
    if [[ "${HAS_SRC}" == true ]]; then
        log "  포함 소스 패키지 수: ${SRC_COUNT} 개"
    fi
    log ""
    log "  [폐쇄망 전달 방법]"
    log "  1. 위 파일을 폐쇄망 서버로 전송"
    log "  2. 서버에서 압축 해제:"
    if [[ "${FORMAT}" == "zip" ]]; then
        log "     unzip ${ARCHIVE_NAME} -d /opt/"
    else
        log "     tar -xzf ${ARCHIVE_NAME} -C /opt/"
    fi
    log "  3. 오프라인 설치:"
    log "     pip install --no-index --find-links=/opt/wheelhouse <패키지명>"
    if [[ "${HAS_SRC}" == true ]]; then
        log ""
        log "  [주의] 소스 패키지 빌드:"
        log "     /opt/src/ 의 소스 패키지는 타겟 서버에서 직접 빌드해야 합니다."
        log "     pip install --no-index --find-links=/opt/src <패키지명>"
    fi
    log "============================================================"
fi
