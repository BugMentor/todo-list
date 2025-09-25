#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
APP_PORT=8080
APP_URL="http://localhost:${APP_PORT}"
REPORTS_DIR="playwright-report"
JUNIT_XML_PATH="${REPORTS_DIR}/junit.xml"
SERVER_LOG="server.log"
ANALYSIS_OUTPUT_FILE="analysis_results.json"
PYTHON_ANALYZER_SCRIPT="duo_troubleshoot_analyzer.py" # Name of our Python script

# --- 1. Setup Environment ---
echo "--- Setting up environment ---"
npm ci --quiet
npm install -g http-server wait-on # Install http-server and wait-on globally

# --- 2. Start Application in Background ---
echo "--- Starting TODO app in background on port ${APP_PORT} ---"
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
# Run tests, generate HTML and JUnit reports
# Store the exit code of Playwright tests
npx playwright test --reporter=html,junit --output="${REPORTS_DIR}"
PLAYWRIGHT_EXIT_CODE=$?

# --- 5. Collect CI Log (for analysis) ---
# In a real CI environment, the full job log is automatically available.
# For local testing, we'll simulate by capturing stdout/stderr of this script.
# For the Python script, we'd pass the actual CI log if available.
# For now, we'll use a placeholder or capture the script's output later.
echo "--- Playwright tests finished with exit code: ${PLAYWRIGHT_EXIT_CODE} ---"

# --- 6. Stop Application ---
echo "--- Stopping TODO app (PID: ${APP_PID}) ---"
kill "${APP_PID}" || true # Kill the background process, '|| true' prevents script from failing if process already gone

# --- 7. Analyze Results using Python Script ---
echo "--- Analyzing test results and logs ---"

# Create a dummy security report for demonstration
echo "No vulnerabilities found." > security_report.txt

# This is where you'd call your Python analysis script.
# We'll pass the paths to the generated reports and logs.
# The Python script would read these files.
# Note: For `gitlab_ci_log`, in a real CI, you'd pass the actual CI log.
# For this example, we'll pass a placeholder or let the Python script infer from context.
python3 "${PYTHON_ANALYZER_SCRIPT}" \
--gitlab-ci-log-placeholder "Placeholder for actual CI log content" \
--playwright-html-report-path "${REPORTS_DIR}" \
--junit-xml-report-path "${JUNIT_XML_PATH}" \
--security-scan-report-path "security_report.txt" \
--server-log-path "${SERVER_LOG}" \
> "${ANALYSIS_OUTPUT_FILE}"

echo "--- Analysis complete. Results saved to ${ANALYSIS_OUTPUT_FILE} ---"
cat "${ANALYSIS_OUTPUT_FILE}" # Print analysis results to stdout

# --- 8. Final Exit Code ---
# The script's exit code should reflect the Playwright test results
# or the overall analysis if the Python script determines a failure.
# For now, we'll use Playwright's exit code.
exit "${PLAYWRIGHT_EXIT_CODE}"
