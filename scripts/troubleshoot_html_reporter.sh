#!/bin/bash
set -e

# Arguments:
# $1: REPORTS_DIR (e.g., playwright-report)
# $2: CI_PROJECT_DIR
# $3: PIPELINE_ID
# $4: BRANCH
# $5: NODE_ENV
# $6: COVERAGE_DIR (optional)
# $7: SECURITY_REPORT_FILE (optional)

REPORTS_DIR=$1
CI_PROJECT_DIR=$2
PIPELINE_ID=$3
BRANCH=$4
NODE_ENV=$5
COVERAGE_DIR=${6:-}
SECURITY_REPORT_FILE=${7:-}

# Evitar warnings de ShellCheck SC2034
: "${REPORTS_DIR}" "${CI_PROJECT_DIR}" "${COVERAGE_DIR}" "${SECURITY_REPORT_FILE}"

REPORT_FILE="troubleshooting-report.html"
JUNIT_XML_PATH="${REPORTS_DIR}/junit.xml"
: "${JUNIT_XML_PATH}"

# --- Calcular resultados de JUnit antes del HTML ---
if [ -f "$JUNIT_XML_PATH" ]; then
    total_tests=$(grep -oP '<testsuites[^>]*tests="\K[^"]+' "$JUNIT_XML_PATH" || echo 0)
    total_failures=$(grep -oP '<testsuites[^>]*failures="\K[^"]+' "$JUNIT_XML_PATH" || echo 0)
    total_errors=$(grep -oP '<testsuites[^>]*errors="\K[^"]+' "$JUNIT_XML_PATH" || echo 0)
    total_skipped=$(grep -oP '<testsuites[^>]*skipped="\K[^"]+' "$JUNIT_XML_PATH" || echo 0)
    passed=$((total_tests - total_failures - total_errors - total_skipped))
else
    total_tests=0
    total_failures=0
    total_errors=0
    total_skipped=0
    passed=0
fi

# --- Generar HTML ---
cat > "$REPORT_FILE" <<EOF
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Pipeline Troubleshooting Report</title>
<style>
body { font-family: Arial, sans-serif; margin: 20px; background: #f9f9f9; color: #333; }
h1,h2,h3,h4 { color: #222; }
pre { background: #eee; padding: 10px; border-radius: 6px; overflow-x: auto; }
code { font-family: monospace; }
table { border-collapse: collapse; width: 100%; margin: 10px 0; }
th,td { border: 1px solid #ccc; padding: 6px 10px; text-align: left; }
th { background: #f0f0f0; }
ul { margin: 0; padding-left: 20px; }
.ok { color: green; font-weight: bold; }
.fail { color: red; font-weight: bold; }
.warn { color: orange; font-weight: bold; }
</style>
</head>
<body>
<h1>Pipeline Troubleshooting Report</h1>
<p>Pipeline ID: $PIPELINE_ID<br>
Branch: $BRANCH<br>
Environment: $NODE_ENV</p>

<h2>System Information</h2>
<ul>
<li>Node Version: $(node -v)</li>
<li>NPM Version: $(npm -v)</li>
<li>OS: $(uname -a)</li>
</ul>

<h2>Environment Variables</h2>
<ul>
<li>REPORTS_DIR: $REPORTS_DIR</li>
<li>NODE_ENV: $NODE_ENV</li>
$( [ -n "$METADATA_URL" ] && echo "<li>METADATA_URL: $METADATA_URL</li>" )
$( [ -n "$API_BASE_URL" ] && echo "<li>API_BASE_URL: $API_BASE_URL</li>" )
</ul>

<h2>Test Results Summary</h2>
<ul>
<li>Total: $total_tests</li>
<li>Passed: $passed</li>
<li>Failed: $total_failures</li>
<li>Errors: $total_errors</li>
<li>Skipped: $total_skipped</li>
</ul>

<h2>HTML Reports</h2>
<ul>
$( if [ -f "$REPORTS_DIR/index.html" ]; then
     echo "<li>Playwright HTML Report: <a href=\"$REPORTS_DIR/index.html\">index.html</a></li>"
   else
     echo "<li class=\"warn\">No Playwright HTML report found at $REPORTS_DIR/index.html</li>"
   fi )
</ul>

<h2>Coverage Reports</h2>
$( if [ -n "$COVERAGE_DIR" ] && [ -d "$COVERAGE_DIR" ]; then
     echo "<ul>"
     [ -f "$COVERAGE_DIR/index.html" ] && echo "<li>HTML Coverage Report: <a href=\"$COVERAGE_DIR/index.html\">index.html</a></li>"
     [ -f "$COVERAGE_DIR/coverage-summary.json" ] && echo "<li>Coverage Summary: <a href=\"$COVERAGE_DIR/coverage-summary.json\">coverage-summary.json</a></li>"
     echo "</ul>"
   else
     echo "<p>No coverage reports found.</p>"
   fi )

<h2>Security Scan</h2>
$( if [ -n "$SECURITY_REPORT_FILE" ] && [ -f "$SECURITY_REPORT_FILE" ]; then
     echo "<p>Security report file found at: <code>$SECURITY_REPORT_FILE</code></p>"
     if grep -q "\"vulnerabilities\":" "$SECURITY_REPORT_FILE"; then
         vuln_count=$(jq '.vulnerabilities | length' "$SECURITY_REPORT_FILE" 2>/dev/null || echo "unknown")
         if [ "$vuln_count" != "unknown" ] && [ "$vuln_count" -gt 0 ]; then
             echo "<p class=\"warn\">Found $vuln_count potential vulnerabilities.</p>"
         else
             echo "<p class=\"ok\">No vulnerabilities found.</p>"
         fi
     else
         echo "<p class=\"ok\">No vulnerabilities found.</p>"
     fi
   else
     echo "<p>ℹ️ No security report file provided or found.</p>"
   fi )

<h2>Disk Space</h2>
<pre>$(df -h | grep -v "tmpfs" | grep -v "udev")</pre>

<h2>All HTML Files (Excluding node_modules)</h2>
<pre>$(find "$CI_PROJECT_DIR" -name "*.html" -not -path "*/node_modules/*" | sort)</pre>

<h2>Recommendations</h2>
<ul>
$( if [ "$total_failures" -eq 0 ]; then
     echo '<li class="ok">✅ All tests passing.</li>'
   else
     echo "<li class=\"fail\">❌ $total_failures tests failing.</li>"
   fi )
<li class="ok">✅ Security scanning is configured.</li>
$( if [ -n "$COVERAGE_DIR" ] && [ -d "$COVERAGE_DIR" ]; then
     echo '<li>📊 Coverage reports available.</li>'
   else
     echo '<li>ℹ️ Consider adding code coverage reporting to your pipeline.</li>'
   fi )
</ul>

</body>
</html>
EOF

echo "Troubleshooting report generated at $REPORT_FILE"
