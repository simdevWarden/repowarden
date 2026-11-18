#!/usr/bin/env bats
# requiredChecks (.repowarden.conf) against the jobs of ci.yml (#590): a required
# check that no job produces would make every merge wait forever, so a renamed
# job or matrix breaks this test instead of blocking the merges.

CONF="$BATS_TEST_DIRNAME/../.repowarden.conf"
CI="$BATS_TEST_DIRNAME/../.github/workflows/ci.yml"

# Check names ci.yml produces: job ids, literal job names, and each templated
# name expanded over the "os" list of the matrix (name: tests (${{ matrix.os }}))
job_names() {
    local oslist os tpl
    sed -n 's/^  \([a-z0-9-]*\):$/\1/p' "$CI"
    grep '^    name:' "$CI" | sed 's/^    name: *//' | grep -v '\${{' || true
    oslist="$(sed -n 's/^ *os: *\[\(.*\)\]/\1/p' "$CI" | tr ',' ' ')"
    grep '^    name:.*matrix\.os' "$CI" | sed 's/^    name: *//' | while IFS= read -r tpl; do
        for os in $oslist; do
            printf '%s\n' "$tpl" | sed "s/\${{ matrix.os }}/$os/"
        done
    done
}

# Required checks of the configuration, one per line, blanks trimmed
required_checks() {
    git config -f "$CONF" repowarden.requiredChecks | tr ',' '\n' | sed 's/^ *//;s/ *$//'
}

# Names of the list "$1" (one per line) that no job of ci.yml produces
missing_checks() {
    local names name
    names="$(job_names)"
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        printf '%s\n' "$names" | grep -Fxq -- "$name" || printf '%s\n' "$name"
    done <<<"$1"
}

@test "required checks: requiredChecks is declared in .repowarden.conf" {
    [ -n "$(required_checks)" ]
}

@test "required checks: every required check is produced by a job of ci.yml" {
    run missing_checks "$(required_checks)"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || { echo "no job produces: $output"; false; }
}

@test "required checks: ubuntu tests, windows summary and repowarden are required" {
    run required_checks
    [[ "$output" == *"repowarden"* ]] || false
    [[ "$output" == *"tests (ubuntu-latest)"* ]] || false
    [[ "$output" == *"tests (windows-latest)"* ]] || false
}

@test "required checks: a name no job produces is reported" {
    run missing_checks "$(printf 'repowarden\ntests (nowhere-latest)\n')"
    [ "$status" -eq 0 ]
    [ "$output" = "tests (nowhere-latest)" ]
}

@test "required checks: ESSAI #590, test rouge volontaire, PR jetable jamais fusionnee" {
    false
}
