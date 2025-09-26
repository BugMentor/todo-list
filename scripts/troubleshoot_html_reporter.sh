#!/bin/bash
set -euo pipefail

# --- Arguments ---
REPORTS_DIR="${1:-}"
CI_PROJECT_DIR="${2:-}"
PIPELINE_ID="${3:-}"
BRANCH="${4:-}"
NODE_ENV="${5:-}"
COVERAGE_DIR="${6:-}"
SECURITY_REPORT_FILE="${7:-}"
SAST_REPORT_FILE="${8:-}"

# --- Output file ---
REPORT_FILE="${CI_PROJECT_DIR}/troubleshooting-report.html"
JUNIT_XML="${REPORTS_DIR}/junit.xml"

# --- Test results ---
TOTAL_TESTS=0
FAILED_TESTS=0
ERROR_TESTS=0
SKIPPED_TESTS=0
PASSED_TESTS=0

if [ -f "$JUNIT_XML" ]; then
    TOTAL_TESTS=$(grep -oP '<testsuites[^>]*tests="\K[^"]+' "$JUNIT_XML" || echo 0)
    FAILED_TESTS=$(grep -oP '<testsuites[^>]*failures="\K[^"]+' "$JUNIT_XML" || echo 0)
    ERROR_TESTS=$(grep -oP '<testsuites[^>]*errors="\K[^"]+' "$JUNIT_XML" || echo 0)
    SKIPPED_TESTS=$(grep -oP '<testsuites[^>]*skipped="\K[^"]+' "$JUNIT_XML" || echo 0)
    PASSED_TESTS=$((TOTAL_TESTS - FAILED_TESTS - ERROR_TESTS - SKIPPED_TESTS))
fi

# --- HTML Reports ---
HTML_REPORTS=$(find "$REPORTS_DIR" -name "*.html" -not -name "troubleshooting-report.html" | sort || true)

# --- Coverage Reports ---
COVERAGE_REPORTS=""
if [ -n "$COVERAGE_DIR" ] && [ -d "$COVERAGE_DIR" ]; then
    COVERAGE_REPORTS=$(find "$COVERAGE_DIR" -name "*.html" | sort || true)
fi

# --- Security Scan ---
SECURITY_SUMMARY="No security report provided."
SECURITY_FINDINGS="No vulnerabilities found."
SECURITY_VULNERABILITIES=0
SECURITY_CRITICAL=0
SECURITY_HIGH=0
SECURITY_MEDIUM=0
SECURITY_LOW=0

if [ -f "$SECURITY_REPORT_FILE" ] && [ -s "$SECURITY_REPORT_FILE" ]; then
    SECURITY_SUMMARY="Security report file found at: $SECURITY_REPORT_FILE"
    if grep -q "\"vulnerabilities\":" "$SECURITY_REPORT_FILE"; then
        SECURITY_CRITICAL=$(jq '.vulnerabilities | map(select(.severity=="critical")) | length' "$SECURITY_REPORT_FILE" 2>/dev/null || echo 0)
        SECURITY_HIGH=$(jq '.vulnerabilities | map(select(.severity=="high")) | length' "$SECURITY_REPORT_FILE" 2>/dev/null || echo 0)
        SECURITY_MEDIUM=$(jq '.vulnerabilities | map(select(.severity=="moderate")) | length' "$SECURITY_REPORT_FILE" 2>/dev/null || echo 0)
        SECURITY_LOW=$(jq '.vulnerabilities | map(select(.severity=="low")) | length' "$SECURITY_REPORT_FILE" 2>/dev/null || echo 0)
        SECURITY_VULNERABILITIES=$((SECURITY_CRITICAL + SECURITY_HIGH + SECURITY_MEDIUM + SECURITY_LOW))
        
        if [ "$SECURITY_VULNERABILITIES" -gt 0 ]; then
            SECURITY_FINDINGS=$(jq -r '
              .vulnerabilities |
              to_entries |
              sort_by(.value.severity) | reverse |
              .[0:5] |
              map("- **" + .key + "**: Severity: " + .value.severity + ", Path: " + (.value.via[0].source // "direct") + ", Fix: " + (.value.fixAvailable.name // "Not available")) |
              join("\n")
            ' "$SECURITY_REPORT_FILE" 2>/dev/null || echo "Error parsing vulnerabilities")
        fi
    fi
fi

# --- SAST Scan ---
SAST_SUMMARY="No SAST report provided."
SAST_FINDINGS="No vulnerabilities found."
SAST_VULNERABILITIES=0
SAST_CRITICAL=0
SAST_HIGH=0
SAST_MEDIUM=0
SAST_LOW=0

if [ -f "$SAST_REPORT_FILE" ] && [ -s "$SAST_REPORT_FILE" ]; then
    SAST_SUMMARY="SAST report file found at: $SAST_REPORT_FILE"
    if grep -q "\"vulnerabilities\":" "$SAST_REPORT_FILE"; then
        SAST_CRITICAL=$(jq '.vulnerabilities | map(select(.severity=="Critical")) | length' "$SAST_REPORT_FILE" 2>/dev/null || echo 0)
        SAST_HIGH=$(jq '.vulnerabilities | map(select(.severity=="High")) | length' "$SAST_REPORT_FILE" 2>/dev/null || echo 0)
        SAST_MEDIUM=$(jq '.vulnerabilities | map(select(.severity=="Medium")) | length' "$SAST_REPORT_FILE" 2>/dev/null || echo 0)
        SAST_LOW=$(jq '.vulnerabilities | map(select(.severity=="Low")) | length' "$SAST_REPORT_FILE" 2>/dev/null || echo 0)
        SAST_VULNERABILITIES=$((SAST_CRITICAL + SAST_HIGH + SAST_MEDIUM + SAST_LOW))
        
        if [ "$SAST_VULNERABILITIES" -gt 0 ]; then
            SAST_FINDINGS=$(jq -r '
              .vulnerabilities |
              sort_by(.severity) | reverse |
              .[0:5] |
              map("- **" + .name + "**: Severity: " + .severity + ", Location: " + .location.file + ":" + (.location.start_line|tostring) + ", Description: " + (.description // "No description")) |
              join("\n")
            ' "$SAST_REPORT_FILE" 2>/dev/null || echo "Error parsing SAST vulnerabilities")
        fi
    fi
fi

# --- Generate HTML Report ---
cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Pipeline Troubleshooting Report</title>
<style>
/* minimal CSS omitted for brevity, reuse your previous styles */
</style>
</head>
<body>
<h1>Pipeline Troubleshooting Report</h1>
<p>Pipeline ID: ${PIPELINE_ID} | Branch: ${BRANCH} | Environment: ${NODE_ENV}</p>

<h2>Test Results</h2>
<ul>
<li>Total: ${TOTAL_TESTS}</li>
<li>Passed: ${PASSED_TESTS}</li>
<li>Failed: ${FAILED_TESTS}</li>
<li>Errors: ${ERROR_TESTS}</li>
<li>Skipped: ${SKIPPED_TESTS}</li>
</ul>

<h2>HTML Reports</h2>
<ul>
EOF

for f in $HTML_REPORTS; do
    echo "<li><a href=\"$f\">$f</a></li>" >> "$REPORT_FILE"
done

cat >> "$REPORT_FILE" <<EOF
</ul>

<h2>Coverage Reports</h2>
<ul>
EOF

if [ -n "$COVERAGE_REPORTS" ]; then
    for f in $COVERAGE_REPORTS; do
        echo "<li><a href=\"$f\">$f</a></li>" >> "$REPORT_FILE"
    done
else
    echo "<li>No coverage reports found</li>" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" <<EOF
</ul>

<h2>Security Scan</h2>
<p>${SECURITY_SUMMARY}</p>
<pre>${SECURITY_FINDINGS}</pre>

<h2>SAST Scan</h2>
<p>${SAST_SUMMARY}</p>
<pre>${SAST_FINDINGS}</pre>

</body>
</html>
EOF

echo "Troubleshooting report generated at: $REPORT_FILE"
