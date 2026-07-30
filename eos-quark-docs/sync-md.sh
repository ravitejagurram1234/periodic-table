#!/usr/bin/env bash
#
# sync-md.sh — rebuild this docs folder from the EOS Quark working tree.
#
# Copies the top-level EOS Quark markdown notes into topic folders and
# regenerates README.md as an index. Read-only on the source tree: originals
# at $SRC are never modified, moved, or deleted.
#
# Adding a new note? Add a `put` line for it below. Anything not listed is
# reported as UNMAPPED at the end — never copied silently, never dropped
# silently.
#
set -uo pipefail

SRC="/Users/tejaswigurram/Documents/eos quark"
DST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d "$SRC" ]; then
  echo "ERROR: source tree not found: $SRC" >&2
  exit 1
fi

copied=0
missing=0
MISSING_LIST=""
MAPPED=""

# put <folder> <filename-relative-to-SRC>
put() {
  local cat="$1" name="$2" src="$SRC/$2"
  MAPPED="$MAPPED$name"$'\n'
  if [ ! -f "$src" ]; then
    missing=$((missing + 1))
    MISSING_LIST="$MISSING_LIST  MISSING: $name"$'\n'
    return
  fi
  mkdir -p "$DST/$cat"
  cp -p "$src" "$DST/$cat/$name"
  copied=$((copied + 1))
}

# ── 01 Start here ───────────────────────────────────────────────────────────
put 01-start-here EOS_Quark_KT_Tracking.md
put 01-start-here EOS_Quark_Consolidated_Changes.md
put 01-start-here EOS_Quark_Deferred_Considerations_Register.md

# ── 02 Engine rewrite batches ───────────────────────────────────────────────
for b in 1 2 3 4 5 6 7 8 9 10 11 12 13; do
  put 02-engine-batches "EOS_Quark_Batch${b}_Changes.md"
done
put 02-engine-batches EOS_Quark_Batch5b_TestFixes.md

# ── 03 Fixes: QXPS / QXPSM SOAP transport ───────────────────────────────────
put 03-fixes-soap-qxps-qxpsm EOS_Quark_QXPSM_FINAL.md
put 03-fixes-soap-qxps-qxpsm EOS_Quark_QXPSM_WSDL_Fix.md
put 03-fixes-soap-qxps-qxpsm EOS_Quark_QXPSM_Correctness_Verification.md
put 03-fixes-soap-qxps-qxpsm EOS_Quark_QxpsmSoapClient_Update.md
put 03-fixes-soap-qxps-qxpsm EOS_Quark_QxpsmSoap_MultiRef_Fix.md
put 03-fixes-soap-qxps-qxpsm EOS_Quark_QxpsBuffer_Timeout_Fix.md

# ── 04 Fixes: Oracle SQL, binding & dates ───────────────────────────────────
put 04-fixes-oracle-sql-dates EOS_Quark_DynamicSQL_Date_Fix.md
put 04-fixes-oracle-sql-dates EOS_Quark_DynamicSQL_Date_NLS_Fix_14-07.md
put 04-fixes-oracle-sql-dates EOS_Quark_DateBind_DocLog_TracingSpam_Fix.md
put 04-fixes-oracle-sql-dates EOS_Quark_InParamMapper_NullHardening.md
put 04-fixes-oracle-sql-dates EOS_Quark_RowCount_and_PositionalBinding_Fix.md

# ── 05 Fixes: logging & live-run analysis ───────────────────────────────────
put 05-fixes-logging-run-analysis EOS_Quark_RunAnalysis_Fixes_488654_505244.md
put 05-fixes-logging-run-analysis EOS_Quark_Logging_Fixes_and_Run339403.md
put 05-fixes-logging-run-analysis EOS_Quark_AuditNull_Fix_and_TestRunQuery.md

# ── 06 Validation & testing ─────────────────────────────────────────────────
put 06-validation-and-testing EOS_Quark_Validation_Issue_List_Verified.md
put 06-validation-and-testing EOS_Quark_Validation_Issue_List.md
put 06-validation-and-testing EOS_Quark_Engine_Validation_Findings.md
put 06-validation-and-testing EOS_Quark_Repo_Verification_27-06.md

# ── 07 Copilot / AI agent instructions ──────────────────────────────────────
put 07-copilot-instructions EOS_Quark_Copilot_Instructions_BUNDLE.md


# ════════════════════════════════════════════════════════════════════════════
#  Regenerate README.md
# ════════════════════════════════════════════════════════════════════════════

label() {
  case "$1" in
    01-start-here)                echo "Start here" ;;
    02-engine-batches)            echo "Engine rewrite batches" ;;
    03-fixes-soap-qxps-qxpsm)     echo "Fixes — QXPS / QXPSM SOAP" ;;
    04-fixes-oracle-sql-dates)    echo "Fixes — Oracle SQL, binding & dates" ;;
    05-fixes-logging-run-analysis) echo "Fixes — logging & live-run analysis" ;;
    06-validation-and-testing)    echo "Validation & testing" ;;
    07-copilot-instructions)      echo "Copilot / AI agent instructions" ;;
    *) echo "$1" ;;
  esac
}

blurb() {
  case "$1" in
    01-start-here)
      echo "Current state of the work. \`KT_Tracking\` is the live session log; \`Consolidated_Changes\` is the post-stabilization change log; \`Deferred_Considerations\` is what was knowingly postponed." ;;
    02-engine-batches)
      echo "The .NET&nbsp;&rarr;&nbsp;Java port, batch by batch, as copy-paste change sets. Batches 11&ndash;13 are the REDO pass and supersede earlier numbering where they overlap." ;;
    03-fixes-soap-qxps-qxpsm)
      echo "The per-step QXPS (HTTP) / QXPSM (SOAP) transport switch and its failure modes. \`QXPSM_FINAL\` is the single source of truth &mdash; read it before the others." ;;
    04-fixes-oracle-sql-dates)
      echo "Dynamic-SQL date binding (ORA-01843 / ORA-01830), NLS session settings, positional binds, and NULL hardening in the parameter mappers." ;;
    05-fixes-logging-run-analysis)
      echo "Fixes driven by analysing specific production runs, plus logging-hygiene work." ;;
    06-validation-and-testing)
      echo "Divergences between the Java engine and the .NET original. \`Validation_Issue_List_Verified\` is the ground-truth-reconciled version &mdash; prefer it over the unverified list." ;;
    07-copilot-instructions)
      echo "Copy-paste bundle of the nine \`.github/\` instruction files that tell Copilot how to work in the engine repo." ;;
    *) echo "" ;;
  esac
}

# First markdown heading, tolerating leading whitespace; falls back to filename.
title_of() {
  local t
  t=$(grep -m1 -E '^[[:space:]]*#+[[:space:]]' "$1" 2>/dev/null \
        | sed -E 's/^[[:space:]]*#+[[:space:]]*//; s/[[:space:]]*$//; s/\|/\\|/g')
  if [ -z "$t" ]; then
    t=$(basename "$1" .md | tr '_' ' ')
  fi
  printf '%s' "$t" | cut -c1-95
}

total=$(find "$DST" -mindepth 2 -name '*.md' -type f | wc -l | tr -d ' ')

{
  echo "# EOS Quark — Documentation"
  echo
  echo "My working notes for the EOS Quark .NET → Java engine port."
  echo "**$total documents**, markdown only, no source code."
  echo
  echo "> **Ground rule:** the original .NET code plus \`ora.txt\` are the source of truth."
  echo "> These notes record analysis and proposed changes — verify against the code before acting."
  echo
  echo "## Index"
  echo

  for dir in "$DST"/[0-9]*/; do
    [ -d "$dir" ] || continue
    cat=$(basename "$dir")
    n=$(find "$dir" -name '*.md' -type f | wc -l | tr -d ' ')

    echo "### $(label "$cat") <sub>&nbsp;$n docs</sub>"
    echo
    b="$(blurb "$cat")"
    [ -n "$b" ] && { echo "$b"; echo; }
    echo "| Document | Topic |"
    echo "|---|---|"
    find "$dir" -name '*.md' -type f | sort | while read -r f; do
      echo "| [$(basename "$f")]($cat/$(basename "$f")) | $(title_of "$f") |"
    done
    echo
  done

  cat <<'FOOTER'
## Keeping this in sync

These files are **copies**. The originals live in the working tree and are
never touched by this repo. To pull in new or edited notes:

```bash
./sync-md.sh
```

That re-copies every mapped file and regenerates this index. When you write a
new note, add a `put` line for it in `sync-md.sh` — the script prints an
`UNMAPPED` list for any top-level markdown it doesn't know about, so nothing
goes missing quietly.

## Scope

Only the top-level EOS Quark notes are here. The working tree also holds ~106
other markdown files buried inside code folders — legacy .NET QXP
documentation, `.github/instructions/`, execution plans, batch-service docs,
and duplicate copies across four repo snapshots. Those are deliberately left
out to keep this searchable; the Copilot instruction files are covered by the
bundle in `07-copilot-instructions/`.
FOOTER
} > "$DST/README.md"

# ── Report ──────────────────────────────────────────────────────────────────
echo "copied:  $copied"
echo "missing: $missing"
[ "$missing" -gt 0 ] && printf '%s' "$MISSING_LIST"

# Any top-level .md in SRC that no put() line claims?
UNMAPPED=$(comm -23 \
  <(cd "$SRC" && ls -1 *.md 2>/dev/null | sort) \
  <(printf '%s' "$MAPPED" | grep -v '^$' | sort))
if [ -n "$UNMAPPED" ]; then
  echo "UNMAPPED (in source, not in any category — add a put line):"
  printf '%s\n' "$UNMAPPED" | sed 's/^/  /'
else
  echo "unmapped: 0"
fi
echo "index:   README.md ($total docs)"
