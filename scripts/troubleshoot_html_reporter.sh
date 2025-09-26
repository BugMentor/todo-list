#!/usr/bin/env bash
set -euo pipefail

# Usage:
# scripts/troubleshoot_html_reporter.sh \
#   <REPORTS_DIR> <CI_PROJECT_DIR> <PIPELINE_ID> <BRANCH> <NODE_ENV> \
#   <COVERAGE_DIR> <SECURITY_REPORT_FILE> <ANALYSIS_JSON> <TEST_RUN_TIME>

REPORTS_DIR="${1:-playwright-report}"
CI_PROJECT_DIR="${2:-.}"
PIPELINE_ID="${3:-N/A}"
BRANCH="${4:-N/A}"
NODE_ENV="${5:-N/A}"
COVERAGE_DIR="${6:-coverage}"
SECURITY_REPORT_FILE="${7:-}"
ANALYSIS_JSON="${8:-}"
TEST_RUN_TIME="${9:-N/A}"

OUTPUT_FILE="${CI_PROJECT_DIR}/troubleshooting-report.html"
TEMP_FILE="$(mktemp)"
JUNIT_XML="${REPORTS_DIR}/junit.xml"

# --- helpers -----------------------------------------------------------------

log_info(){ printf "[INFO] %s\n" "$*"; }
log_warn(){ printf "[WARN] %s\n" "$*"; }
log_error(){ printf "[ERROR] %s\n" "$*" >&2; }

html_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

# --- parse junit results ----------------------------------------------------

parse_junit() {
  local xml="$1"
  local total=0 passed=0 failures=0 errors=0 skipped=0

  if [ ! -f "$xml" ]; then
    echo "$total $passed $failures $errors $skipped"
    return
  fi

  total=$(grep -c "<testcase" "$xml" 2>/dev/null || echo 0)
  failures=$(grep -c "<failure" "$xml" 2>/dev/null || echo 0)
  errors=$(grep -c "<error" "$xml" 2>/dev/null || echo 0)
  skipped=$(grep -c "<skipped" "$xml" 2>/dev/null || echo 0)

  if [ "$total" -eq 0 ]; then
    total=$(sed -n 's/.*tests="\([^"]*\)".*/\1/p' "$xml" | head -n1 || echo 0)
    failures=$(sed -n 's/.*failures="\([^"]*\)".*/\1/p' "$xml" | head -n1 || echo 0)
    errors=$(sed -n 's/.*errors="\([^"]*\)".*/\1/p' "$xml" | head -n1 || echo 0)
    skipped=$(sed -n 's/.*skipped="\([^"]*\)".*/\1/p' "$xml" | head -n1 || echo 0)
  fi

  # Ensure all variables are numeric
  total=${total:-0}; failures=${failures:-0}; errors=${errors:-0}; skipped=${skipped:-0}
  total=$(echo "$total" | tr -cd '0-9')
  failures=$(echo "$failures" | tr -cd '0-9')
  errors=$(echo "$errors" | tr -cd '0-9')
  skipped=$(echo "$skipped" | tr -cd '0-9')

  # Calculate passed
  passed=$(( total - failures - errors - skipped ))
  [ "$passed" -lt 0 ] && passed=0

  echo "$total $passed $failures $errors $skipped"
}

# --- security summary -------------------------------------------------------

security_summary_html() {
  local file="$1"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    echo "<p>No security scan results found.</p>"
    return
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "<p>Security report exists but 'jq' is not available to parse it.</p>"
    return
  fi

  local total=0 critical=0 high=0 moderate=0 low=0 summary_html="" top_list=""

  if jq -e '.metadata.vulnerabilities' "$file" >/dev/null 2>&1; then
    total=$(jq -r '.metadata.vulnerabilities.total // 0' "$file" 2>/dev/null || echo 0)
    critical=$(jq -r '.metadata.vulnerabilities.critical // 0' "$file" 2>/dev/null || echo 0)
    high=$(jq -r '.metadata.vulnerabilities.high // 0' "$file" 2>/dev/null || echo 0)
    moderate=$(jq -r '.metadata.vulnerabilities.moderate // 0' "$file" 2>/dev/null || echo 0)
    low=$(jq -r '.metadata.vulnerabilities.low // 0' "$file" 2>/dev/null || echo 0)
  elif jq -e '.vulnerabilities' "$file" >/dev/null 2>&1; then
    critical=$(jq -r '(.vulnerabilities // {}) | (if type=="object" then to_entries | map(.value.severity) else map(.severity) end) | map(select(.=="critical")) | length' "$file" 2>/dev/null || echo 0)
    high=$(jq -r '(.vulnerabilities // {}) | (if type=="object" then to_entries | map(.value.severity) else map(.severity) end) | map(select(.=="high")) | length' "$file" 2>/dev/null || echo 0)
    moderate=$(jq -r '(.vulnerabilities // {}) | (if type=="object" then to_entries | map(.value.severity) else map(.severity) end) | map(select(.=="moderate" or .=="medium")) | length' "$file" 2>/dev/null || echo 0)
    low=$(jq -r '(.vulnerabilities // {}) | (if type=="object" then to_entries | map(.value.severity) else map(.severity) end) | map(select(.=="low")) | length' "$file" 2>/dev/null || echo 0)
    total=$((critical + high + moderate + low))
  else
    summary_html="<pre>$(html_escape "$(jq -r . "$file" 2>/dev/null || cat "$file")")</pre>"
  fi

  if [ -z "$summary_html" ]; then
    summary_html="<div class='stats' style='display:flex;gap:12px;margin-bottom:10px'>
      <div style='padding:8px;border-radius:6px;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,0.06)'><strong>Total</strong><div>$total</div></div>
      <div style='padding:8px;border-radius:6px;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,0.06)'><strong>Critical</strong><div style='color:#c82333'>$critical</div></div>
      <div style='padding:8px;border-radius:6px;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,0.06)'><strong>High</strong><div style='color:#e36414'>$high</div></div>
      <div style='padding:8px;border-radius:6px;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,0.06)'><strong>Moderate</strong><div style='color:#e6b800'>$moderate</div></div>
      <div style='padding:8px;border-radius:6px;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,0.06)'><strong>Low</strong><div style='color:#2f9b3a'>$low</div></div>
    </div>"

    if [ "$total" -gt 0 ]; then
      top_list=$(jq -r '(.vulnerabilities // {}) | to_entries | .[0:5] | map("- " + .key + " (severity: " + ( .value.severity // "unknown") + ")") | .[]' "$file" 2>/dev/null || true)
      [ -n "$top_list" ] && summary_html+="<p><strong>Top vulnerabilities:</strong></p><ul>$(echo "$top_list" | sed 's/^/<li>/;s/$/<\/li>/')</ul>"
    fi
  fi

  printf '%s\n' "$summary_html"
}

# --- Duo recommendations ---------------------------------------------------

extract_duo_recommendations_html() {
  local analysis="$1"
  if [ -z "$analysis" ] || [ ! -f "$analysis" ]; then echo ""; return; fi
  if ! command -v jq >/dev/null 2>&1; then echo ""; return; fi

  local recs html
  recs=$(jq -r '( .duo.recommendations // .recommendations // .suggestions // .duo_recommendations ) as $r
    | if $r == null then empty elif ($r | type) == "array" then ($r[]) else $r end' "$analysis" 2>/dev/null || true)

  [ -z "$recs" ] && echo "" && return

  html="<ul>"
  while IFS= read -r line; do html+="<li>$(html_escape "$line")</li>"; done <<< "$recs"
  html+="</ul>"
  echo "$html"
}

# --- coverage ---------------------------------------------------------------

check_coverage_reports() {
  local covdir="$1"
  local covhtml
  covhtml="<p>No coverage directory found at: $(html_escape "$covdir")</p>"
  local covsum="<p><strong>⚠️ No coverage reports available</strong></p>"

  if [ -n "$covdir" ] && [ -d "$covdir" ]; then
    local files
    files=$(find "$covdir" -name "*.html" -o -name "coverage-summary.json" -type f | sort || true)
    if [ -n "$files" ]; then
      covhtml="<ul>"
      for f in $files; do covhtml+="<li>$(html_escape "$f")</li>"; done
      covhtml+="</ul>"

      local summary_file tot covcov covpct
      summary_file=$(find "$covdir" -name "coverage-summary.json" -type f | head -1 || true)
      if [ -f "$summary_file" ]; then
        tot=$(jq -r '.total.lines.total // 0' "$summary_file" 2>/dev/null || echo 0)
        covcov=$(jq -r '.total.lines.covered // 0' "$summary_file" 2>/dev/null || echo 0)
        covpct=0
        [ "$tot" -gt 0 ] && covpct=$(( (covcov*100)/tot ))
        covsum="<p><strong>Coverage:</strong> ${covpct}% (${covcov}/${tot} lines)</p>"
      else
        covsum="<p>Coverage reports found but no summary data available.</p>"
      fi
    fi
  fi

  printf '%s\n' "$covhtml" "$covsum"
}

# --- gather data ------------------------------------------------------------

read -r TOTAL PASSED FAILS ERRORS SKIPPED < <(parse_junit "$JUNIT_XML")
NODE_VERSION=$(node -v 2>/dev/null || echo "N/A")
NPM_VERSION=$(npm -v 2>/dev/null || echo "N/A")
OS_INFO=$(uname -a 2>/dev/null || echo "Unknown")

read -r COVERAGE_HTML COVERAGE_SUMMARY < <(check_coverage_reports "$COVERAGE_DIR")
SECURITY_HTML=$(security_summary_html "$SECURITY_REPORT_FILE")
DUO_HTML=$(extract_duo_recommendations_html "$ANALYSIS_JSON")
DISK_SPACE=$(df -h | grep -v "tmpfs" || echo "Unable to query disk space")

# --- format test run time ---------------------------------------------------

TEST_TIME_HTML=""
if [ "$TEST_RUN_TIME" != "N/A" ]; then
  if [ "$TEST_RUN_TIME" -ge 60 ]; then
    MINS=$((TEST_RUN_TIME / 60))
    SECS=$((TEST_RUN_TIME % 60))
    TEST_TIME_HTML="<p><strong>Test run time:</strong> ${MINS}m ${SECS}s</p>"
  else
    TEST_TIME_HTML="<p><strong>Test run time:</strong> ${TEST_RUN_TIME}s</p>"
  fi
else
  TEST_TIME_HTML="<p><strong>Test run time:</strong> Not available</p>"
fi

# --- render HTML ------------------------------------------------------------

cat > "$TEMP_FILE" <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Duo Troubleshoot Report</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body{font-family:Arial,Helvetica,sans-serif;background:#f6f8fa;color:#222;padding:18px}
.card{background:#fff;border-radius:8px;padding:16px;margin-bottom:16px;box-shadow:0 1px 4px rgba(0,0,0,0.06)}
h1{margin:0 0 10px 0}
h2{margin:0 0 10px 0;color:#1f76c2}
pre{background:#f0f0f0;padding:10px;border-radius:6px;overflow:auto}
ul{margin:6px 0 0 18px}
</style>
</head>
<body>
<h1>🔍 Duo Troubleshoot Report</h1>

<div class="card">
<h2>Pipeline info</h2>
<p><strong>Pipeline ID:</strong> $(html_escape "$PIPELINE_ID")</p>
<p><strong>Branch:</strong> $(html_escape "$BRANCH")</p>
<p><strong>Environment:</strong> $(html_escape "$NODE_ENV")</p>
</div>

<div class="card">
<h2>System</h2>
<p><strong>Node:</strong> $(html_escape "$NODE_VERSION") &nbsp; <strong>NPM:</strong> $(html_escape "$NPM_VERSION")</p>
<p><strong>OS:</strong> $(html_escape "$OS_INFO")</p>
</div>

<div class="card">
<h2>Test results</h2>
<ul>
<li><strong>Total:</strong> ${TOTAL}</li>
<li><strong>Passed:</strong> ${PASSED}</li>
<li><strong>Failed:</strong> ${FAILS}</li>
<li><strong>Errors:</strong> ${ERRORS}</li>
<li><strong>Skipped:</strong> ${SKIPPED}</li>
</ul>
$TEST_TIME_HTML
EOF

[ -f "${REPORTS_DIR}/index.html" ] && printf '<p><strong>Playwright report:</strong> %s/index.html</p>\n' "$(html_escape "$REPORTS_DIR")" >> "$TEMP_FILE"

cat >> "$TEMP_FILE" <<EOF
</div>

<div class="card">
<h2>Coverage</h2>
${COVERAGE_HTML}
${COVERAGE_SUMMARY}
</div>

<div class="card">
<h2>Security scan</h2>
${SECURITY_HTML}
</div>

<div class="card">
<h2>Recommendations from Duo</h2>
${DUO_HTML}
</div>

<div class="card">
<h2>Disk space</h2>
<pre>$(html_escape "$DISK_SPACE")</pre>
</div>

<footer style="font-size:13px;color:#666;margin-top:12px">
<div>Generated: $(date -u +"%Y-%m-%d %H:%M:%SZ")</div>
<div>Report file: $(html_escape "$OUTPUT_FILE")</div>
</footer>
</body>
</html>
EOF

mv "$TEMP_FILE" "$OUTPUT_FILE"
log_info "Report generated: $OUTPUT_FILE"
