import json
import xml.etree.ElementTree as ET
import re
import argparse
from collections import defaultdict
import os


def duo_troubleshoot(
    gitlab_ci_log_content: str = "",
    playwright_html_report_path: str = "",
    junit_xml_report_content: str = "",
    security_scan_report_content: str = "",
    performance_metrics: dict = None,
    custom_app_logs_content: str = "",
) -> dict:
    """
    Analyzes various logs and reports from a CI/CD pipeline (specifically Playwright tests)
    to provide troubleshooting insights, recommendations, and optimizations.

    Args:
        gitlab_ci_log_content (str): The full GitLab CI/CD job log content.
        playwright_html_report_path (str): The path to the Playwright HTML report directory.
        junit_xml_report_content (str): The content of the JUnit XML report.
        security_scan_report_content (str): Content from a security scan report.
        performance_metrics (dict): Dictionary of key performance indicators.
        custom_app_logs_content (str): Any additional application-specific logs content.

    Returns:
        dict: A structured dictionary containing analysis, recommendations, and optimizations.
    """

    analysis = {
        "overall_status": "UNKNOWN",
        "summary": [],
        "errors_warnings": defaultdict(list),
        "test_results": {
            "total": 0,
            "passed": 0,
            "failed": 0,
            "skipped": 0,
            "duration_ms": 0,
            "failing_tests_details": [],
        },
        "performance_analysis": {},
        "security_findings": [],
        "ci_pipeline_issues": [],
        "recommendations": [],
        "optimizations": [],
    }

    # --- 1. Analyze GitLab CI Log ---
    if gitlab_ci_log_content:
        if "Job succeeded" in gitlab_ci_log_content:
            analysis["overall_status"] = "PASSED"
            analysis["summary"].append("GitLab CI job completed successfully.")
        elif "Job failed" in gitlab_ci_log_content:
            analysis["overall_status"] = "FAILED"
            analysis["summary"].append("GitLab CI job failed.")

        if "Failed to extract cache" in gitlab_ci_log_content:
            analysis["ci_pipeline_issues"].append(
                "Cache restoration failed. This might impact build times."
            )
            analysis["optimizations"].append(
                "Investigate cache configuration (`cache:key`, `cache:paths`) to ensure it's correctly saved and restored."
            )
        if (
            "WARNING: playwright-report/*.xml: no matching files"
            in gitlab_ci_log_content
        ):
            analysis["ci_pipeline_issues"].append(
                "Playwright JUnit XML report artifact warning. Check artifact path."
            )
            analysis["recommendations"].append(
                "Adjust `.gitlab-ci.yml` artifact path for JUnit XML (e.g., `playwright-report/junit.xml`) to ensure it's correctly collected."
            )
        if "ERROR: No files to upload" in gitlab_ci_log_content:
            analysis["ci_pipeline_issues"].append(
                "Artifact upload failed for some files."
            )
            analysis["recommendations"].append(
                "Verify artifact paths in `.gitlab-ci.yml` are correct and files exist."
            )
        if "Test timeout of" in gitlab_ci_log_content:
            analysis["errors_warnings"]["Test Timeout"].append(
                "A test action exceeded its timeout. This often points to a UI element not appearing or being interactable within the expected time."
            )
            analysis["recommendations"].append(
                "Review the application's responsiveness and the specific Playwright action that timed out. "
                "Consider adding `await page.waitForSelector()` or increasing the action timeout if the element is genuinely slow."
            )

        for line in gitlab_ci_log_content.splitlines():
            if "ERROR:" in line:
                analysis["errors_warnings"]["CI Log Error"].append(line.strip())
            elif "WARNING:" in line:
                analysis["errors_warnings"]["CI Log Warning"].append(line.strip())

    # --- 2. Analyze JUnit XML Report ---
    if junit_xml_report_content:
        try:
            root = ET.fromstring(junit_xml_report_content)
            testsuites = root.findall("testsuite")
            if not testsuites:
                testsuites = [root]

            for testsuite in testsuites:
                analysis["test_results"]["total"] += int(testsuite.get("tests", 0))
                analysis["test_results"]["failed"] += int(testsuite.get("failures", 0))
                analysis["test_results"]["skipped"] += int(testsuite.get("skipped", 0))
                analysis["test_results"]["duration_ms"] += (
                    float(testsuite.get("time", 0)) * 1000
                )

                for testcase in testsuite.findall("testcase"):
                    if testcase.find("failure") is not None:
                        failure_message = testcase.find("failure").get(
                            "message", "No message"
                        )
                        analysis["test_results"]["failing_tests_details"].append(
                            {
                                "name": testcase.get("name"),
                                "classname": testcase.get("classname"),
                                "message": failure_message,
                                "type": "FAILURE",
                            }
                        )
                    elif testcase.find("error") is not None:
                        error_message = testcase.find("error").get(
                            "message", "No message"
                        )
                        analysis["test_results"]["failing_tests_details"].append(
                            {
                                "name": testcase.get("name"),
                                "classname": testcase.get("classname"),
                                "message": error_message,
                                "type": "ERROR",
                            }
                        )

            analysis["test_results"]["passed"] = (
                analysis["test_results"]["total"]
                - analysis["test_results"]["failed"]
                - analysis["test_results"]["skipped"]
            )

            if analysis["test_results"]["failed"] > 0:
                analysis["summary"].append(
                    f"{analysis['test_results']['failed']} Playwright tests failed."
                )
                analysis["recommendations"].append(
                    "Review failing test details to identify application bugs or test flakiness."
                )
                for failure in analysis["test_results"]["failing_tests_details"]:
                    analysis["recommendations"].append(
                        f"  - Test '{failure['name']}' failed: {failure['message']}"
                    )
            else:
                analysis["summary"].append("All Playwright tests passed successfully.")

        except ET.ParseError:
            analysis["errors_warnings"]["JUnit Parse Error"].append(
                "Could not parse JUnit XML report."
            )
        except Exception as e:
            analysis["errors_warnings"]["JUnit Analysis Error"].append(
                f"Error analyzing JUnit report: {e}"
            )

    # --- 3. Analyze Playwright HTML Report Presence/Summary ---
    if playwright_html_report_path and os.path.isdir(playwright_html_report_path):
        analysis["summary"].append(
            f"Playwright HTML report generated and available as artifact: {playwright_html_report_path}"
        )
        analysis["recommendations"].append(
            f"For detailed visual debugging of Playwright tests, download and review the HTML report artifact (located in '{playwright_html_report_path}')."
        )

        if (
            "Error: expect(locator).toHaveClass(expected) failed"
            in gitlab_ci_log_content
        ):
            analysis["recommendations"].append(
                "A test failed due to an incorrect CSS class. Verify application's DOM manipulation logic (e.g., `main.js`) for styling changes."
            )
        if "Error: expect(locator).not.toBeVisible() failed" in gitlab_ci_log_content:
            analysis["recommendations"].append(
                "A test failed because an element was unexpectedly visible/invisible. Check application's rendering logic and element removal/hiding."
            )
        if "Error: locator.click: Test timeout of" in gitlab_ci_log_content:
            analysis["recommendations"].append(
                "A Playwright click action timed out. Consider adding explicit waits or checking application's UI readiness."
            )
        if "attachment #2: trace (application/zip)" in gitlab_ci_log_content:
            analysis["optimizations"].append(
                "Playwright traces are available for failed tests. Use `npx playwright show-trace` to debug visually."
            )

    # --- 4. Analyze Security Scan Report ---
    if security_scan_report_content:
        if (
            "Vulnerability Found" in security_scan_report_content
            or "High Severity" in security_scan_report_content
        ):
            analysis["security_findings"].append("Security vulnerabilities detected.")
            analysis["recommendations"].append(
                "Review the security scan report for details and prioritize fixes based on severity."
            )
            if analysis["overall_status"] != "FAILED":
                analysis["overall_status"] = "FAILED"
        else:
            analysis["summary"].append(
                "No critical security vulnerabilities detected by scan."
            )

    # --- 5. Analyze Performance Metrics ---
    if performance_metrics:
        if (
            performance_metrics.get("load_time")
            and performance_metrics["load_time"] > 5000
        ):
            analysis["performance_analysis"][
                "Initial Load Time"
            ] = f"{performance_metrics['load_time']}ms (High)"
            analysis["optimizations"].append(
                "Initial page load time is high. Investigate asset loading, server response times, and client-side rendering performance."
            )
        if (
            performance_metrics.get("cpu_usage")
            and performance_metrics["cpu_usage"] > 70
        ):
            analysis["performance_analysis"][
                "CPU Usage"
            ] = f"{performance_metrics['cpu_usage']}% (High)"
            analysis["optimizations"].append(
                "High CPU usage detected. Profile application for CPU-intensive operations, especially during interactive phases."
            )

    # --- 6. Analyze Custom Application Logs ---
    if custom_app_logs_content:
        for line in custom_app_logs_content.splitlines():
            if re.search(r"(?i)error|exception|fail", line):
                analysis["errors_warnings"]["Application Log Error"].append(
                    line.strip()
                )
                analysis["recommendations"].append(
                    "Review application logs for runtime errors that might not be caught by tests."
                )
            if re.search(r"(?i)warn", line):
                analysis["errors_warnings"]["Application Log Warning"].append(
                    line.strip()
                )

    # --- Final Summary and Overall Recommendations ---
    if (
        analysis["overall_status"] == "UNKNOWN"
        and analysis["test_results"]["total"] > 0
    ):
        if analysis["test_results"]["failed"] > 0:
            analysis["overall_status"] = "FAILED"
        else:
            analysis["overall_status"] = "PASSED"

    if analysis["overall_status"] == "FAILED":
        analysis["summary"].insert(
            0, "Overall CI/CD pipeline status: FAILED. Immediate attention required."
        )
    elif analysis["overall_status"] == "PASSED":
        analysis["summary"].insert(
            0,
            "Overall CI/CD pipeline status: PASSED. Review recommendations for further improvements.",
        )

    if (
        not analysis["recommendations"]
        and not analysis["optimizations"]
        and analysis["overall_status"] == "PASSED"
    ):
        analysis["summary"].append(
            "No specific recommendations or optimizations identified based on provided logs."
        )

    return analysis


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Analyze CI/CD logs and reports.")
    parser.add_argument(
        "--gitlab-ci-log-placeholder",
        type=str,
        help="Placeholder for GitLab CI log content (for local testing).",
    )
    parser.add_argument(
        "--playwright-html-report-path",
        type=str,
        help="Path to the Playwright HTML report directory.",
    )
    parser.add_argument(
        "--junit-xml-report-path", type=str, help="Path to the JUnit XML report file."
    )
    parser.add_argument(
        "--security-scan-report-path",
        type=str,
        help="Path to the security scan report file.",
    )
    parser.add_argument(
        "--server-log-path", type=str, help="Path to the application server log file."
    )
    # Add arguments for performance metrics if they were collected into a file
    # parser.add_argument("--performance-metrics-path", type=str, help="Path to a JSON file with performance metrics.")

    args = parser.parse_args()

    # Read file contents
    gitlab_ci_log_content = (
        args.gitlab_ci_log_placeholder
    )  # For CI, this would be the actual log
    junit_xml_report_content = ""
    security_scan_report_content = ""
    custom_app_logs_content = ""
    performance_metrics = None  # Placeholder for now

    if args.junit_xml_report_path and os.path.exists(args.junit_xml_report_path):
        with open(args.junit_xml_report_path, "r") as f:
            junit_xml_report_content = f.read()

    if args.security_scan_report_path and os.path.exists(
        args.security_scan_report_path
    ):
        with open(args.security_scan_report_path, "r") as f:
            security_scan_report_content = f.read()

    if args.server_log_path and os.path.exists(args.server_log_path):
        with open(args.server_log_path, "r") as f:
            custom_app_logs_content = f.read()

    analysis_results = duo_troubleshoot(
        gitlab_ci_log_content=gitlab_ci_log_content,
        playwright_html_report_path=args.playwright_html_report_path,
        junit_xml_report_content=junit_xml_report_content,
        security_scan_report_content=security_scan_report_content,
        performance_metrics=performance_metrics,
        custom_app_logs_content=custom_app_logs_content,
    )

    print(json.dumps(analysis_results, indent=2))
