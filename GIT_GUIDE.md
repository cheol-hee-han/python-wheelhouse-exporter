# Git 사용 가이드

처음 Git을 사용하는 분도 이해할 수 있도록 작성한 가이드입니다.

---

## 목차

- [Git 사용 가이드](#git-사용-가이드)
  - [목차](#목차)
  - [Git 이란?](#git-이란)
  - [사전 준비](#사전-준비)
    - [1. Git 설치](#1-git-설치)
    - [2. GitHub 계정 생성](#2-github-계정-생성)
    - [3. Git Bash 실행](#3-git-bash-실행)
  - [최초 설정 (PC 1대에서 1회만)](#최초-설정-pc-1대에서-1회만)
  - [프로젝트를 GitHub에 처음 올리기](#프로젝트를-github에-처음-올리기)
  - [이후 변경사항 업로드하기](#이후-변경사항-업로드하기)
  - [다른 PC에서 프로젝트 가져오기](#다른-pc에서-프로젝트-가져오기)
  - [다른 PC에서 변경사항 동기화하기](#다른-pc에서-변경사항-동기화하기)
  - [자주 쓰는 명령어 요약](#자주-쓰는-명령어-요약)
  - [자주 묻는 질문](#자주-묻는-질문)

---

## Git 이란?

Git은 **파일의 변경 이력을 관리하는 도구**입니다.
GitHub는 Git 저장소를 **인터넷에 올려두는 서비스**입니다.

```
내 PC (로컬)                GitHub (원격)
┌─────────────────┐         ┌─────────────────┐
│  내 프로젝트     │  push → │  저장소          │
│  (로컬 저장소)   │ ← pull  │  (원격 저장소)   │
└─────────────────┘         └─────────────────┘
```

- **commit** : 변경사항을 로컬에 저장 (스냅샷 찍기)
- **push**   : 로컬의 commit 을 GitHub 에 업로드
- **pull**   : GitHub 의 최신 내용을 로컬로 다운로드
- **clone**  : GitHub 저장소를 내 PC 에 처음 복사

---

## 사전 준비

### 1. Git 설치

[git-scm.com](https://git-scm.com/download/win) 에서 Git for Windows 다운로드 후 설치합니다.
설치 옵션은 기본값(Next → Next → Install)으로 진행합니다.

설치 확인:
```bash
git --version
# 출력 예: git version 2.47.0.windows.1
```

### 2. GitHub 계정 생성

[github.com](https://github.com) 에서 회원가입합니다.

### 3. Git Bash 실행

Git 설치 후 원하는 폴더에서 **우클릭 → Git Bash Here** 로 터미널을 엽니다.
또는 VSCode 터미널에서 Git Bash 를 선택해 사용할 수 있습니다.

---

## 최초 설정 (PC 1대에서 1회만)

Git 을 처음 사용하는 PC 에서 딱 한 번만 실행하면 됩니다.
이 정보는 commit 작성자를 표시하는 데 사용됩니다.

```bash
# GitHub 에서 사용하는 이메일 주소로 입력
git config --global user.email "cjfgml777@gmail.com"

# GitHub 사용자명으로 입력
git config --global user.name "cheol-hee-han"

# 설정 확인
git config --global --list
# 출력 예:
# user.email=your-email@example.com
# user.name=your-github-username
```

---

## 프로젝트를 GitHub에 처음 올리기

> GitHub 에 새 저장소를 먼저 생성한 후 진행합니다.
> github.com → New repository → 이름 입력 → Create repository
> (README, .gitignore 옵션은 체크 해제)

```bash
# 1. 프로젝트 폴더로 이동
cd /c/Users/사용자명/프로젝트폴더

# 2. Git 저장소 초기화
#    .git 폴더가 생성되며 이 폴더가 Git 저장소가 됩니다
git init

# 3. 현재 상태 확인 (어떤 파일이 추가될지 미리 확인)
git status

# 4. 모든 파일을 스테이징 영역에 추가
#    스테이징 = commit 할 파일을 선택하는 준비 단계
git add .

# 5. 스테이징된 파일을 commit (로컬에 저장)
#    -m 뒤에 변경 내용을 간략히 설명하는 메시지를 작성합니다
git commit -m "init: 프로젝트 초기 설정"

# 6-1. GitHub 원격 저장소 연결
#    origin 은 원격 저장소의 별칭 (관례적으로 origin 사용)
git remote add origin https://github.com/cheol-hee-han/python-wheelhouse-exporter.git

# 6-2. 등록된 원격 저장소 확인
git remote -v

# 7. 브랜치 이름을 main 으로 설정
#    GitHub 의 기본 브랜치가 main 이므로 맞춰줍니다
git branch -M main

# 8. GitHub 에 push (업로드)
#    -u 옵션: 이후부터는 git push 만 입력해도 origin main 으로 자동 연결
git push -u origin main
# 또는 충돌을 무시하고 업로드 하려면
git push -u origin main --force
```

> **push 시 인증 요구 시:**
> GitHub 는 비밀번호 대신 **Personal Access Token(PAT)** 을 사용합니다.
> GitHub → Settings → Developer settings → Personal access tokens
> → Generate new token → `repo` 권한 체크 → 생성
> 비밀번호 입력 자리에 토큰을 붙여넣기 하면 됩니다.

---

## 이후 변경사항 업로드하기

파일을 수정한 후 GitHub 에 반영하는 일반적인 흐름입니다.

```bash
# 1. 변경된 파일 확인
#    빨간색: 아직 스테이징 안 된 파일
#    초록색: 스테이징 완료된 파일
git status

# 2. 변경된 내용 미리 보기
git diff

# 3-A. 변경된 파일 전체 스테이징
git add .

# 3-B. 특정 파일만 스테이징하고 싶을 때
git add 파일명
git add deps/agentic-ai/pyproject.toml   # 예시

# 4. commit 메시지 작성 요령:
#    feat:  새 기능 추가
#    fix:   버그 수정
#    docs:  문서 수정
#    chore: 기타 변경 (설정, 의존성 등)
git commit -m "feat: agentic-ai 의존성 세트 추가"

# 5. GitHub 에 push
#    최초 push 이후에는 git push 만 입력해도 됩니다
git push
```

---

## 다른 PC에서 프로젝트 가져오기

> 새 PC 에서 처음으로 프로젝트를 받아올 때 사용합니다.

```bash
# 0. 먼저 최초 설정을 완료했는지 확인
git config --global user.email "your-email@example.com"
git config --global user.name "your-github-username"

# 1. 프로젝트를 받아둘 폴더로 이동
cd /c/Users/사용자명/workspace

# 2. GitHub 저장소를 로컬로 복사 (clone)
#    저장소의 전체 이력이 포함된 채로 복사됩니다
git clone https://github.com/계정명/저장소명.git

# 예시
git clone https://github.com/cheol-hee-han/python-wheelhouse-exporter.git

# 3. clone 된 폴더로 이동
cd python-wheelhouse-exporter

# 4. 파일이 잘 받아졌는지 확인
ls
```

clone 이 완료되면 원격 저장소와 자동으로 연결된 상태가 됩니다.
별도로 `git remote add` 를 할 필요가 없습니다.

---

## 다른 PC에서 변경사항 동기화하기

> 이미 clone 해둔 PC 에서 GitHub 의 최신 내용을 받아올 때 사용합니다.

```bash
# 1. 현재 로컬 변경사항 확인
git status

# 2. GitHub 의 최신 내용을 로컬로 가져오기 (pull)
#    pull = fetch(변경사항 확인) + merge(로컬에 합치기)
git pull

# 3. 최신 상태인지 확인
git log --oneline -5
# 최근 5개 commit 이력이 출력됩니다
```

> **작업 전에 항상 pull 먼저!**
> 다른 PC 에서 작업했다면 현재 PC 에서 작업 시작 전에
> 반드시 `git pull` 로 최신 상태를 맞추는 습관을 들이세요.
> 그렇지 않으면 충돌(conflict)이 발생할 수 있습니다.

---

## 자주 쓰는 명령어 요약

| 명령어 | 설명 |
|--------|------|
| `git init` | 현재 폴더를 Git 저장소로 초기화 |
| `git status` | 변경된 파일 목록 확인 |
| `git add .` | 모든 변경 파일 스테이징 |
| `git add <파일>` | 특정 파일만 스테이징 |
| `git commit -m "메시지"` | 스테이징된 내용을 로컬에 저장 |
| `git push` | 로컬 commit 을 GitHub 에 업로드 |
| `git pull` | GitHub 최신 내용을 로컬에 반영 |
| `git clone <URL>` | GitHub 저장소를 로컬에 복사 |
| `git log --oneline` | commit 이력 간략히 확인 |
| `git diff` | 변경된 내용 상세 확인 |

---

## 자주 묻는 질문

**Q. `git add .` 과 `git add 파일명` 의 차이는?**

`git add .` 은 현재 폴더의 모든 변경 파일을 한꺼번에 스테이징합니다.
`git add 파일명` 은 원하는 파일만 선택적으로 스테이징합니다.
실수로 올리면 안 되는 파일이 있을 경우 후자를 사용하세요.

---

**Q. commit 메시지를 잘못 입력했어요.**

아직 push 하기 전이라면 아래 명령으로 마지막 commit 메시지를 수정할 수 있습니다.
```bash
git commit --amend -m "수정된 메시지"
```
이미 push 한 후라면 수정하지 않는 것을 권장합니다.

---

**Q. push 했는데 rejected(거절) 오류가 납니다.**

다른 PC 에서 push 한 내용이 로컬에 반영되지 않은 상태입니다.
먼저 pull 로 최신 내용을 받은 후 다시 push 하세요.
```bash
git pull
git push
```

---

**Q. `.gitignore` 에 추가했는데 파일이 계속 추적됩니다.**

이미 Git 이 추적 중인 파일은 `.gitignore` 에 추가해도 무시되지 않습니다.
아래 명령으로 추적을 해제한 후 commit 하세요.
```bash
# 캐시에서 제거 (파일 자체는 삭제되지 않음)
git rm -r --cached 파일명
git add .
git commit -m "chore: gitignore 적용"
```
