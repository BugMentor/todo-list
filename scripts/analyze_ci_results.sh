#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
APP_PORT=8080
APP_URL="http://localhost:${APP_PORT}"
REPORTS_DIR="playwright-report"
COVERAGE_DIR="coverage"
JUNIT_XML_PATH="${REPORTS_DIR}/junit.xml"
SERVER_LOG="server.log"
ANALYSIS_OUTPUT_FILE="analysis_results.json"
PYTHON_ANALYZER_SCRIPT="scripts/duo_troubleshoot_analyzer.py"

# --- 1. Setup Environment ---
echo "--- Setting up environment ---"
npm ci --quiet
npm install -g http-server wait-on # Install http-server and wait-on globally

# --- 2. Start Application in Background ---
echo "--- Starting app in background on port ${APP_PORT} ---"
# Create directory for coverage
mkdir -p "${COVERAGE_DIR}"
# Redirect stdout and stderr to server.log, run in background
nohup http-server . -p "${APP_PORT}" -c-1 --silent > "${SERVER_LOG}" 2>&1 &
APP_PID=$! # Store PID of the background process

# --- 3. Wait for Application to be Ready ---
echo "--- Waiting for app to be ready at ${APP_URL} ---"
npx wait-on "${APP_URL}" --timeout 60000 --interval 1000

# --- 4. Run Playwright Tests ---
echo "--- Running Playwright tests ---"
# Ensure the reports directory exists
mkdir -p "${REPORTS_DIR}"
# Run tests with coverage
START_TIME=$(date +%s)
npx playwright test
TEST_EXIT_CODE=$?
END_TIME=$(date +%s)
TEST_DURATION=$((END_TIME - START_TIME))
echo "--- Playwright tests finished with exit code: ${TEST_EXIT_CODE} (duration: ${TEST_DURATION}s) ---"

# --- 5. Stop Application ---
echo "--- Stopping app (PID: ${APP_PID}) ---"
kill "${APP_PID}" || true # Kill the background process, '|| true' prevents script from failing if process already gone

# --- 6. Create a simple security report if none exists ---
SECURITY_REPORT="security_report.json"
if [ ! -f "${SECURITY_REPORT}" ]; then
    echo "--- Creating placeholder security report ---"
    echo '{"metadata":{"vulnerabilities":{}}}' > "${SECURITY_REPORT}"
fi

# --- 7. Analyze Results using Python Script ---
echo "--- Analyzing test results and logs ---"

# Run the Python analyzer script with all the necessary parameters
python3 "${PYTHON_ANALYZER_SCRIPT}" \
--playwright-html-report-path "${REPORTS_DIR}" \
--junit-xml-report-path "${JUNIT_XML_PATH}" \
--security-scan-report-path "${SECURITY_REPORT}" \
--server-log-path "${SERVER_LOG}" \
--test-duration "${TEST_DURATION}" \
--coverage-dir "${COVERAGE_DIR}" \
--output-file "${ANALYSIS_OUTPUT_FILE}"

echo "--- Analysis complete. Results saved to ${ANALYSIS_OUTPUT_FILE} ---"
cat "${ANALYSIS_OUTPUT_FILE}" # Print analysis results to stdout

# --- 8. Final Exit Code ---
# Return the exit code from the tests
exit "${TEST_EXIT_CODE}"
