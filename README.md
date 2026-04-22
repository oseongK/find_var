# find_var

ripgrep 기반 병렬 소스 검색 bash 스크립트. 현재 디렉토리 하위를 재귀 스캔해 패턴/변수·함수 선언을 빠르게 찾고, 폴더별로 그룹화된 컬러 출력을 제공합니다.

## 주요 기능

- **언어별 선언 탐지** (`-v`): Python / TCL / Perl / bash / csh 의 변수·함수·전역·alias 등
- **폴더별 병렬 실행**: 하위 디렉토리마다 rg 워커 1개, 실시간 프로그레스바
- **깔끔한 출력**: 헤더 + 폴더 그룹 + 라인 하이라이트
- **옵션 위치 무관**: `find_var aaa -E` == `find_var -E aaa`

## 설치

```bash
chmod +x find_var
# 필요 시 PATH 에 추가
cp find_var ~/bin/
```

### ripgrep 경로 설정

스크립트 상단의 `DEFAULT_RG` 변수에 ripgrep 경로를 넣어두면 기본값으로 사용됩니다.

```bash
# find_var 상단
DEFAULT_RG="/your/path/to/rg"
```

비워두면 `PATH` 에서 `rg` 를 찾습니다. 실행 시 덮어쓰려면:
- CLI: `--rg /path/to/rg`
- 환경변수: `FIND_VAR_RG=/path/to/rg find_var ...`

우선순위: `--rg` > `$FIND_VAR_RG` > `DEFAULT_RG`

### -v 전용 제외 폴더

`-v` 로 선언 검색 시 아예 스캔하고 싶지 않은 폴더가 있으면 스크립트 상단 `V_EXCLUDE_DIRS` 배열에 추가하세요. 하위 폴더 포함해 제외됩니다. (일반 검색에는 영향 없음)

```bash
# find_var 상단
V_EXCLUDE_DIRS=(
    "./vendor"
    "./third_party/generated"
    "/some/absolute/path"
)
```

환경변수 `FIND_VAR_V_EXCLUDE` (`:` 구분) 로 일시적 추가도 가능:
```bash
FIND_VAR_V_EXCLUDE="./tmp:./legacy" find_var -v aaa
```

## 사용법

```
find_var [옵션] <pattern>
```

### 옵션

| 옵션 | 설명 |
|---|---|
| `-v` | `<pattern>`을 선언 대상 이름으로 해석 |
| `-E` | 매칭 라인까지 표시 (`[N] 경로 : 내용`). 미사용시 파일 경로만 |
| `-t` | 총 소요 시간 표시 (stderr). <10초: `X.XXXs`, 10~60초: `X.Xs`, 60초~: `Nm Ms` |
| `-w` | `-v` 와 함께: 정확한 이름 일치 (기본은 부분포함) |
| `-F` | 고정 문자열 검색 (기본 regex, `-v` 와 동시 사용 불가) |
| `-j N` | 동시 실행 워커 수 (기본: `nproc`) |
| `--rg PATH` | ripgrep 실행파일 경로 지정 |
| `--color WHEN` | 색상 제어 (`always`/`auto`/`never`, 기본 `auto`) |
| `-h`, `--help` | 도움말 |

### 환경변수

- `NO_COLOR` — 설정 시 색상 강제 비활성 (업계 표준)
- `FIND_VAR_RG` — ripgrep 경로 지정 (우선순위: `--rg` > `$FIND_VAR_RG` > 내장 기본값)
- `FIND_VAR_V_EXCLUDE` — `-v` 모드에서 제외할 폴더 (`:` 구분, 스크립트 내 `V_EXCLUDE_DIRS` 에 추가됨)

### 예시

```bash
find_var aaa                 # aaa 를 regex 로 포함한 파일
find_var -F 'a.b'            # 고정 문자열 'a.b' 포함 파일
find_var -v aaa              # aaa 가 선언된 파일 (부분포함)
find_var -v -w aaa           # 정확히 'aaa' 로 선언된 파일
find_var -v -E aaa           # 선언 라인까지 표시
find_var -t -v aaa           # 선언 검색 + 소요시간
find_var -j 8 -E aaa         # 워커 8개
find_var aaa -E              # 옵션 후행도 가능
```

## 출력 예시

```
================================================================================
Pattern       : aaa
Directory     : /home/me/project
Directory num : 47
================================================================================

---[./lib]--- Matches : 2
[ 3] ./lib/utils.sh : aaa="hello"
[12] ./lib/api.sh  : export aaa=1

---[./src]--- Matches : 3
[ 8] ./src/auth.py : def aaa(user_id):
[12] ./src/auth.py : aaa = load_token()
[45] ./src/db.py   : aaa = None
```

- 헤더 레이블/구분선: **파랑**, 값: 흰색
- 폴더 그룹 헤더: **노랑**
- 라인번호 `[N]`: **보라**
- 라인 내 매칭 패턴: **빨강 bold**

진행 중에는 stderr 에 프로그레스바가 그려지며, 완료 시 자동으로 지워집니다:
```
[############--------------------] 12/47 (25%)
```

## 지원 언어별 선언 패턴

| 언어 | 탐지 패턴 |
|---|---|
| Python | `def NAME`, `class NAME`, `global NAME`, `nonlocal NAME`, `NAME = ...`, `NAME: type` |
| TCL | `set NAME`, `variable NAME`, `global NAME`, `proc NAME` |
| Perl | `my/our/local $@%NAME`, `sub NAME` |
| Bash | `NAME=`, `declare/local/export/readonly/typeset NAME`, `NAME()`, `function NAME` |
| csh | `set NAME`, `setenv NAME`, `alias NAME` |

## 검색 대상 / 제외

- 시작 디렉토리: 현재 작업 디렉토리 (`.`)
- 바이너리 파일 자동 제외 (ripgrep 기본)
- 심볼릭 링크 따라가지 않음
- 숨김 디렉토리 제외 (`.git`, `.svn`, `.cache` 등)
- 빌드/의존성 제외: `node_modules`, `__pycache__`, `build`, `dist`
- **압축 파일 자동 스캔**: `.gz`, `.bz2`, `.xz`, `.zst`, `.lz4` 내부까지 검색 (rg `--search-zip`)

## 종료 코드

- `0` — 매치 있음
- `1` — 매치 없음
- `2` — 인자/환경 오류 (rg 없음, 잘못된 옵션 등)

## 테스트

```bash
chmod +x tests/test_find_var.sh
bash tests/test_find_var.sh
# rg 경로 오버라이드
bash tests/test_find_var.sh --rg /path/to/rg
```

## 기술 스택

- bash 4+
- [ripgrep](https://github.com/BurntSushi/ripgrep)
- 표준 유닉스 도구: `find`, `xargs`, `awk`, `sed`, `sort`

## 제약

- 디렉토리 수천 개 이상의 트리에서는 rg 프로세스 spawn 오버헤드가 rg 내부 병렬 대비 커질 수 있음 (수백 개 이하에선 체감 차이 없음)
- ripgrep 바이너리가 별도 경로에 있는 경우 `FIND_VAR_RG` 또는 `--rg` 로 경로 지정 필요
