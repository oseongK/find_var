#!/bin/bash
# find_var 회귀 테스트
# 사용법: bash tests/test_find_var.sh [--rg /path/to/rg]
#
# 기본 rg 경로는 find_var 스크립트의 기본값을 사용.
# 필요 시 --rg 또는 FIND_VAR_RG 환경변수로 오버라이드 가능.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FV="$SCRIPT_DIR/find_var"

RG_ARG=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rg) RG_ARG=( --rg "$2" ); shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

PASS=0
FAIL=0
FAILED_TESTS=()

assert_pass() {
    local name="$1"
    PASS=$((PASS + 1))
    printf '  [PASS] %s\n' "$name"
}

assert_fail() {
    local name="$1" reason="$2"
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$name: $reason")
    printf '  [FAIL] %s — %s\n' "$name" "$reason"
}

strip_ansi() {
    sed -E 's/\x1B\[[0-9;]*[mK]//g'
}

# -------- fixture 생성 --------
FIX=$(mktemp -d -t find_var_fix.XXXXXX)
trap 'rm -rf "$FIX"' EXIT

mkdir -p "$FIX/src" "$FIX/lib" "$FIX/tools" "$FIX/scripts"
mkdir -p "$FIX/.git/hooks"              # 숨김 디렉토리 (제외되어야 함)
mkdir -p "$FIX/node_modules/foo"        # 제외되어야 함
mkdir -p "$FIX/__pycache__"             # 제외되어야 함
mkdir -p "$FIX/build"                   # 제외되어야 함

# Python
cat > "$FIX/src/sample.py" <<'PY'
import os

def aaa(user_id):
    return user_id

class Aaa:
    pass

aaa = 10
bbb = 20
aaabbb = "substring hit"
PY

# TCL
cat > "$FIX/tools/sample.tcl" <<'TCL'
set aaa 10
variable bbb
proc aaa {} {
    return 1
}
TCL

# Perl
cat > "$FIX/lib/sample.pl" <<'PERL'
my $aaa = 1;
our @bbb = ();
sub aaa {
    return 42;
}
PERL

# Bash
cat > "$FIX/lib/sample.sh" <<'BASH'
#!/bin/bash
aaa=10
export aaa=1
readonly BBB=5
aaa() {
    echo hello
}
function bbb() {
    echo world
}
BASH

# csh
cat > "$FIX/scripts/sample.csh" <<'CSH'
#!/bin/csh
set aaa = 10
setenv aaa /opt
alias aaa ls
CSH

# 매치 없는 파일
cat > "$FIX/src/no_match.txt" <<'NM'
just some prose without the declaration target
NM

# 숨김 디렉토리 내 파일 — 제외 검증용 (`aaa` 포함)
cat > "$FIX/.git/hooks/post-commit" <<'HOOK'
aaa=should_be_excluded
HOOK

# node_modules 내 파일 — 제외 검증용
cat > "$FIX/node_modules/foo/index.js" <<'JS'
var aaa = 1;
JS

# 바이너리 파일 — 제외 검증용
printf '\x00\x01\x02aaa\x00\x03\x04' > "$FIX/src/binary.bin"

cd "$FIX"

run_fv() {
    # 색상 비활성 + 비TTY 모드로 강제 (파이프됨 → auto=off)
    "$FV" "${RG_ARG[@]}" --color=never "$@" 2>/dev/null
}

run_fv_stderr() {
    "$FV" "${RG_ARG[@]}" --color=never "$@" 2>&1 >/dev/null
}

echo "=== find_var 회귀 테스트 ==="
echo "fixture: $FIX"
echo

# -------- TC1: -v aaa — 선언 파일 (부분포함) --------
n="T1: -v aaa (부분포함, 파일만)"
out=$(run_fv -v aaa)
if echo "$out" | grep -q "src/sample.py" \
    && echo "$out" | grep -q "tools/sample.tcl" \
    && echo "$out" | grep -q "lib/sample.pl" \
    && echo "$out" | grep -q "lib/sample.sh" \
    && echo "$out" | grep -q "scripts/sample.csh"; then
    assert_pass "$n"
else
    assert_fail "$n" "expected 5 language files present"
fi

# -------- TC2: .git / node_modules / 바이너리 제외 --------
n="T2: .git/node_modules/binary 제외"
out=$(run_fv -v aaa)
if echo "$out" | grep -q '\.git' \
    || echo "$out" | grep -q 'node_modules' \
    || echo "$out" | grep -q 'binary\.bin'; then
    assert_fail "$n" "hidden/excluded/binary paths leaked"
else
    assert_pass "$n"
fi

# -------- TC3: no_match.txt 제외 --------
n="T3: no_match.txt 없음"
out=$(run_fv -v aaa)
if echo "$out" | grep -q 'no_match\.txt'; then
    assert_fail "$n" "no_match.txt should not appear"
else
    assert_pass "$n"
fi

# -------- TC4: -v -E — 선언 라인 표시 --------
n="T4: -v -E 라인 출력 포맷"
out=$(run_fv -v -E aaa)
# '[라인번호] 경로 : 내용' 형식 확인
if echo "$out" | grep -qE '^\[[[:space:]]*[0-9]+\][[:space:]]+[^ ]+ : '; then
    assert_pass "$n"
else
    assert_fail "$n" "expected [N] path : content format"
fi

# -------- TC5: -v -w 정확일치 — Aaa 제외 --------
n="T5: -v -w aaa → class Aaa 제외"
out=$(run_fv -v -w -E aaa)
# class Aaa 가 라인에 나오면 안됨
if echo "$out" | grep -qi 'class Aaa'; then
    assert_fail "$n" "class Aaa should not match with -w"
else
    assert_pass "$n"
fi

# -------- TC6: -v 부분포함 — aaabbb 포함 --------
n="T6: -v aaa (no -w) → aaabbb 히트"
out=$(run_fv -v -E aaa)
if echo "$out" | grep -q 'aaabbb'; then
    assert_pass "$n"
else
    assert_fail "$n" "aaabbb should match without -w"
fi

# -------- TC7: 일반 regex 검색 --------
n="T7: regex 검색 (no -v)"
out=$(run_fv 'aaa')
if echo "$out" | grep -q 'sample'; then
    assert_pass "$n"
else
    assert_fail "$n" "pattern search should find sample files"
fi

# -------- TC8: -F 고정문자열 --------
n="T8: -F 'aaa=1'"
out=$(run_fv -F 'aaa=1')
if echo "$out" | grep -q 'sample.sh'; then
    assert_pass "$n"
else
    assert_fail "$n" "fixed string should hit sample.sh"
fi

# -------- TC9: -t — Elapsed 출력 (새 포맷) --------
n="T9: -t 소요시간 (초 단위)"
err=$(run_fv_stderr -t -v aaa)
# 가능한 포맷: 'X.XXXs' / 'X.Xs' / 'Nm Ms'
if echo "$err" | grep -qE 'Elapsed: ([0-9]+\.[0-9]+s|[0-9]+m [0-9]+s)'; then
    assert_pass "$n"
else
    assert_fail "$n" "expected 'Elapsed: X.XXXs|X.Xs|Nm Ms' on stderr, got: $err"
fi

# -------- TC10: 옵션 후행 --------
n="T10: find_var aaa -E (옵션 후행)"
out1=$(run_fv aaa -E)
out2=$(run_fv -E aaa)
if [[ "$out1" == "$out2" ]]; then
    assert_pass "$n"
else
    assert_fail "$n" "option position must not matter"
fi

# -------- TC11: -j N --------
n="T11: -j 2 정상 동작"
out=$(run_fv -j 2 -v aaa)
if echo "$out" | grep -q 'sample.py'; then
    assert_pass "$n"
else
    assert_fail "$n" "-j 2 should work"
fi

# -------- TC12: 인자 오류 --------
n="T12: pattern 없음 → exit 2"
"$FV" "${RG_ARG[@]}" --color=never >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then assert_pass "$n"; else assert_fail "$n" "expected exit 2, got $rc"; fi

n="T13: pattern 2개 → exit 2"
"$FV" "${RG_ARG[@]}" --color=never aaa bbb >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then assert_pass "$n"; else assert_fail "$n" "expected exit 2, got $rc"; fi

n="T14: -F 와 -v 동시 사용 → exit 2"
"$FV" "${RG_ARG[@]}" --color=never -F -v aaa >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then assert_pass "$n"; else assert_fail "$n" "expected exit 2, got $rc"; fi

# -------- TC15: -h / --help --------
n="T15: -h 도움말 출력"
out=$("$FV" -h 2>&1)
rc=$?
if [[ $rc -eq 0 ]] && echo "$out" | grep -q '사용법:'; then
    assert_pass "$n"
else
    assert_fail "$n" "-h should exit 0 and print usage"
fi

n="T16: --help 는 다른 인자 무관"
out=$("$FV" -v aaa --help 2>&1)
rc=$?
if [[ $rc -eq 0 ]] && echo "$out" | grep -q '사용법:'; then
    assert_pass "$n"
else
    assert_fail "$n" "--help should short-circuit"
fi

# -------- TC17: 헤더 포맷 --------
n="T17: 헤더 Pattern/Directory/Directory num 출력"
out=$(run_fv -v aaa)
if echo "$out" | grep -qE '^Pattern[[:space:]]+:' \
    && echo "$out" | grep -qE '^Directory[[:space:]]+:' \
    && echo "$out" | grep -qE '^Directory num[[:space:]]+:'; then
    assert_pass "$n"
else
    assert_fail "$n" "header lines missing"
fi

# -------- TC18: 폴더 그룹 헤더 --------
n="T18: ---[dir]--- Matches : N 헤더"
out=$(run_fv -v aaa)
if echo "$out" | grep -qE '^---\[\./.*\]--- Matches : [0-9]+$'; then
    assert_pass "$n"
else
    assert_fail "$n" "folder group header missing"
fi

# -------- TC19: 색상 코드 auto(비TTY)에서 생성 안됨 --------
n="T19: --color=never 시 ANSI 없음"
out=$(run_fv -v -E aaa)
if echo "$out" | grep -q $'\e\['; then
    assert_fail "$n" "ANSI codes leaked with --color=never"
else
    assert_pass "$n"
fi

# -------- TC20: --color=always 시 ANSI 포함 --------
n="T20: --color=always 시 ANSI 포함"
out=$("$FV" "${RG_ARG[@]}" --color=always -v -E aaa 2>/dev/null)
if echo "$out" | grep -q $'\e\['; then
    assert_pass "$n"
else
    assert_fail "$n" "ANSI codes missing with --color=always"
fi

# -------- TC21: NO_COLOR 환경변수 --------
n="T21: NO_COLOR=1 로 색상 비활성"
out=$(NO_COLOR=1 "$FV" "${RG_ARG[@]}" -v -E aaa 2>/dev/null)
if echo "$out" | grep -q $'\e\['; then
    assert_fail "$n" "NO_COLOR ignored"
else
    assert_pass "$n"
fi

# -------- TC23: -v V_EXCLUDE_DIRS (FIND_VAR_V_EXCLUDE) --------
# fixture 에 excl/sample.py 추가 후 환경변수로 제외 확인
mkdir -p "$FIX/excl"
cat > "$FIX/excl/sample.py" <<'PY'
def aaa():
    pass
PY

n="T23: FIND_VAR_V_EXCLUDE 로 폴더 제외"
# 기준: 제외 없을 때 excl/sample.py 포함
out_all=$("$FV" "${RG_ARG[@]}" --color=never -v aaa 2>/dev/null)
# 환경변수로 ./excl 제외
out_excl=$(FIND_VAR_V_EXCLUDE="./excl" "$FV" "${RG_ARG[@]}" --color=never -v aaa 2>/dev/null)

if echo "$out_all" | grep -q 'excl/sample.py' \
    && ! echo "$out_excl" | grep -q 'excl/sample.py'; then
    assert_pass "$n"
else
    assert_fail "$n" "excl/sample.py should appear without exclusion and disappear with it"
fi

# -------- TC24: -v 제외는 하위 폴더까지 포함 --------
mkdir -p "$FIX/excl/nested"
cat > "$FIX/excl/nested/deep.sh" <<'SH'
aaa=10
SH

n="T24: 제외 경로의 하위 폴더도 제외"
out_excl=$(FIND_VAR_V_EXCLUDE="./excl" "$FV" "${RG_ARG[@]}" --color=never -v aaa 2>/dev/null)
if echo "$out_excl" | grep -q 'excl/nested'; then
    assert_fail "$n" "nested subdir should also be excluded"
else
    assert_pass "$n"
fi

# -------- TC25: -v 제외 경로는 일반 검색에 영향 없음 --------
n="T25: 제외 경로는 -v 없을 때 영향 없음"
out_plain=$(FIND_VAR_V_EXCLUDE="./excl" "$FV" "${RG_ARG[@]}" --color=never 'aaa' 2>/dev/null)
if echo "$out_plain" | grep -q 'excl/sample.py'; then
    assert_pass "$n"
else
    assert_fail "$n" "exclusion should only apply to -v mode"
fi

# -------- TC26: .gz 기본은 검색 안 함 --------
mkdir -p "$FIX/compressed"
printf 'def aaa():\n    pass\n' | gzip > "$FIX/compressed/sample.py.gz"

n="T26: .gz 파일 기본은 스캔 안 함"
out=$(run_fv -v aaa)
if echo "$out" | grep -q 'compressed/sample.py.gz'; then
    assert_fail "$n" ".gz should be skipped without -zip"
else
    assert_pass "$n"
fi

# -------- TC27: -zip 옵션 시 .gz 내부까지 검색 --------
n="T27: -zip 으로 .gz 파일 검색"
out=$(run_fv -zip -v aaa)
if echo "$out" | grep -q 'compressed/sample.py.gz'; then
    assert_pass "$n"
else
    assert_fail "$n" "-zip should enable .gz search"
fi

# -------- TC22: 매치 없음 → exit 1 --------
n="T22: 매치 없음 → exit 1"
run_fv -v zzz_nonexistent_xyz123 >/dev/null 2>&1
rc=$?
if [[ $rc -eq 1 ]]; then assert_pass "$n"; else assert_fail "$n" "expected exit 1, got $rc"; fi

echo
echo "=== 결과 ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [[ $FAIL -gt 0 ]]; then
    echo
    echo "실패한 테스트:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t"
    done
    exit 1
fi
exit 0
