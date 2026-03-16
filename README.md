# Python Wheelhouse Exporter

Python 의존성 패키지를 `.whl` 파일로 다운로드하여 폐쇄망(Air-gapped) 서버에 배포하기 위한 도구입니다.

## 개요

```text
[인터넷 환경]                          [폐쇄망 서버]
  pyproject.toml                          /opt/wheelhouse/
       ↓                                       ↓
  uv lock                            pip install --no-index
       ↓                              --find-links=/opt/wheelhouse
  pip download                               <패키지명>
       ↓
  wheelhouse_*.tar.gz  ──(전송)──→
```

## 프로젝트 구조

```text
python-wheelhouse-exporter/
├── deps/                            # Python 의존성 세트 (프로젝트별 독립)
│   ├── fastapi-server/
│   │   ├── pyproject.toml          # FastAPI 관련 의존성 정의
│   │   └── uv.lock                 # uv 로 생성된 lock 파일
│   ├── data-science/
│   │   ├── pyproject.toml          # pandas, numpy, scikit-learn 등
│   │   └── uv.lock
│   ├── llm-api/
│   │   ├── pyproject.toml          # openai, langchain 등
│   │   └── uv.lock
│   └── database/
│       ├── pyproject.toml          # sqlalchemy, alembic 등
│       └── uv.lock
├── scripts/
│   ├── 01-resolve-deps.sh          # uv lock + pip download
│   ├── 02-export-wheels.sh         # output/wheelhouse 로 통합
│   ├── 03-package-for-transfer.sh # tar.gz / zip 압축
│   └── run-all.sh                  # 전체 파이프라인 실행
├── output/                         # 결과물 (.gitignore 처리)
│   └── wheelhouse/                 # 추출된 .whl 파일들
├── requirements-offline.txt        # 폐쇄망 서버 설치 가이드
├── .gitignore
└── README.md
```

## 사전 요구사항

- Python 3.12+ (기본값, 필요 시 `--python=3.11` 으로 변경 가능)
- [uv](https://docs.astral.sh/uv/) 설치 필요
- pip

```bash
# uv 설치
pip install uv

# 또는 (Linux/macOS)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Windows (PowerShell)
powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
```

## 빠른 시작

### 1. 전체 의존성 세트 처리

```bash
# 모든 deps 세트를 처리하여 wheelhouse 생성
bash scripts/run-all.sh --clean
```

### 2. 특정 세트만 처리

```bash
# fastapi-server 세트만
bash scripts/run-all.sh --modules=deps/fastapi-server --clean

# 여러 세트 동시 처리
bash scripts/run-all.sh --modules=deps/fastapi-server,deps/database --clean
```

### 3. 옵션 조합

```bash
# Python 3.11 기준, zip 포맷으로 압축
bash scripts/run-all.sh --modules=deps/fastapi-server --python=3.11 --format=zip --clean
```

## 스크립트 개별 실행

### 01. 의존성 resolve 및 다운로드

```bash
# 전체 자동 탐색
bash scripts/01-resolve-deps.sh

# 특정 모듈만
bash scripts/01-resolve-deps.sh --modules=deps/fastapi-server

# Python 버전 지정 (기본값: 3.12)
bash scripts/01-resolve-deps.sh --modules=deps/fastapi-server --python=3.11
```

동작:

1. `uv lock` 으로 lock 파일 생성
1. `uv export` 로 `requirements.txt` 생성
1. `pip download` 로 `.whl` 파일을 `deps/<모듈>/wheelhouse/` 에 저장

### 02. wheelhouse 통합 내보내기

```bash
# 전체 통합
bash scripts/02-export-wheels.sh

# 특정 모듈만 + 기존 output 초기화
bash scripts/02-export-wheels.sh --modules=deps/fastapi-server --clean
```

동작: `deps/*/wheelhouse/` → `output/wheelhouse/` 로 통합 복사

### 03. 전송용 압축 패키지 생성

```bash
# tar.gz (기본값)
bash scripts/03-package-for-transfer.sh

# zip 포맷
bash scripts/03-package-for-transfer.sh --format=zip
```

결과물: `output/wheelhouse_<YYYYMMDD_HHmmss>.tar.gz`

## 새 deps 세트 추가

1. `deps/<새프로젝트명>/pyproject.toml` 생성:

```toml
[project]
name = "deps-<새프로젝트명>"
version = "1.0.0"
requires-python = ">=3.12"
dependencies = [
    "some-package>=1.0.0",
    # 추가 의존성...
]

[tool.uv]
```

1. 스크립트 실행:

```bash
bash scripts/run-all.sh --modules=deps/<새프로젝트명> --clean
```

## 기본 제공 deps 세트

| 폴더명 | 주요 패키지 |
| --- | --- |
| `fastapi-server` | fastapi, uvicorn, pydantic, httpx, python-jose, passlib |
| `data-science` | pandas, numpy, scikit-learn, matplotlib, jupyter, scipy |
| `llm-api` | openai, langchain, langchain-openai, tiktoken, chromadb, anthropic |
| `database` | sqlalchemy, alembic, psycopg2-binary, pymysql, pymongo, redis |

## 폐쇄망 서버 배포

### 1. 압축 파일 전송

```bash
scp output/wheelhouse_*.tar.gz user@airgapped-server:/opt/
```

### 2. 서버에서 압축 해제

```bash
tar -xzf /opt/wheelhouse_20250316_143022.tar.gz -C /opt/
# → /opt/wheelhouse/ 디렉터리 생성
```

### 3. 오프라인 설치

```bash
# 단일 패키지
pip install --no-index --find-links=/opt/wheelhouse fastapi

# requirements.txt 기반 전체 설치
pip install --no-index --find-links=/opt/wheelhouse -r requirements.txt

# 가상 환경 사용 시
python -m venv .venv
source .venv/bin/activate
pip install --no-index --find-links=/opt/wheelhouse -r requirements.txt
```

## 주의사항

> **플랫폼 일치 필요**
>
> `.whl` 파일은 OS, CPU 아키텍처, Python 버전에 따라 다릅니다.
> 가능하면 다운로드 환경과 폐쇄망 서버의 환경을 일치시키세요.
>
> 예: 둘 다 `Linux x86_64`, Python 3.12

- `--python=<version>` 으로 타겟 Python 버전을 명시하세요.
- 플랫폼 불일치 시 소스 패키지(`.tar.gz`)가 포함될 수 있으며, 서버에 C 컴파일러가 필요할 수 있습니다.
- `output/` 디렉터리는 `.gitignore` 에 포함되어 있습니다. 결과물은 별도로 관리하세요.

## 로그 파일

| 로그 파일 | 내용 |
| --- | --- |
| `output/resolve-deps.log` | uv lock / pip download 로그 |
| `output/export-wheels.log` | wheelhouse 통합 복사 로그 |
| `output/package-transfer.log` | 압축 패키지 생성 로그 |
