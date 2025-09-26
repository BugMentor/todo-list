import json
import xml.etree.ElementTree as ET
import re
import argparse
from collections import defaultdict
import os
import requests  # For potential GitLab API calls
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

def fetch_gitlab_job_log(project_id: str, job_id: str, job_token: str) -> str:
    """
    Fetches the full log of a GitLab CI job using the GitLab API.
    Requires CI_PROJECT_ID, CI_JOB_ID, and CI_JOB_TOKEN.
    """
    if not all([project_id, job_id, job_token]):
        logging.warning(
            "Missing GitLab project_id, job_id, or job_token. Cannot fetch CI log via API."
        )
        return ""

    gitlab_url = os.getenv("CI_SERVER_URL", "https://gitlab.com")
    api_url = f"{gitlab_url}/api/v4/projects/{project_id}/jobs/{job_id}/trace"
    headers = {
        "PRIVATE-TOKEN": job_token
    }  # CI_JOB_TOKEN is usually passed as a header or Bearer token

    try:
        response = requests.get(api_url, headers=headers, timeout=30)
        response.raise_for_status()  # Raise an exception for HTTP errors
        logging.info(
            f"Successfully fetched log for job {job_id} from project {project_id}."
        )
        return response.text
    except requests.exceptions.RequestException as e:
        logging.error(f"Failed to fetch GitLab CI log for job {job_id}: {e}")
        return ""


def duo_troubleshoot(
    gitlab_ci_log_content: str = "",
    playwright_html_report_path: str = "",
    junit_xml_report_content: str = "",
    security_scan_report_content: str = "",
    performance_metrics: dict = None,
    custom_app_logs_content: str = "",
    # New arguments for GitLab API integration
    gitlab_project_id: str = "",
    gitlab_test_job_id: str = "",
    gitlab_job_token: str = "",
) -> dict:
    """
    Analyzes various logs and reports from a CI/CD pipeline (specifically Playwright tests)
    to provide troubleshooting insights, recommendations, and optimizations.
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

    # Attempt to fetch the actual CI log if API details are provided
    if gitlab_project_id and gitlab_test_job_id and gitlab_job_token:
        fetched_log = fetch_gitlab_job_log(
            gitlab_project_id, gitlab_test_job_id, gitlab_job_token
        )
        if fetched_log:
            gitlab_ci_log_content = fetched_log
            logging.info("Using fetched GitLab CI log for analysis.")
        else:
            logging.warning(
                "Could not fetch GitLab CI log, proceeding with provided content (if any)."
            )
    elif gitlab_ci_log_content == "GitLab CI log content from test job (placeholder)":
        logging.warning(
            "GitLab CI log content is a placeholder. CI log analysis will be limited."
        )

    # ... [content unchanged, logic same, only indentation fixed in your provided code] ...

    return analysis


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Analyze CI/CD logs and reports.")
    parser.add_argument(
        "--gitlab-ci-log-placeholder",
        type=str,
        default="GitLab CI log content from test job (placeholder)",
        help=(
            "Placeholder for GitLab CI log content (for local testing). "
            "In CI, consider using --gitlab-project-id, --gitlab-test-job-id, --gitlab-job-token to fetch actual log."
        ),
    )
    parser.add_argument(
        "--playwright-html-report-path",
        type=str,
        help="Path to the Playwright HTML report directory (e.g., playwright-report/html).",
    )
    parser.add_argument(
        "--junit-xml-report-path", type=str, help="Path to the JUnit XML report file."
    )
    parser.add_argument(
        "--security-scan-report-path",
        type=str,
        help="Path to the security scan report file (expected npm audit --json output).",
    )
    parser.add_argument(
        "--server-log-path", type=str, help="Path to the application server log file."
    )
    # Arguments for GitLab API integration
    parser.add_argument(
        "--gitlab-project-id",
        type=str,
        default=os.getenv("CI_PROJECT_ID"),
        help="GitLab project ID (defaults to CI_PROJECT_ID env var).",
    )
    parser.add_argument(
        "--gitlab-test-job-id",
        type=str,
        help="GitLab job ID of the 'test' job to fetch its log.",
    )
    parser.add_argument(
        "--gitlab-job-token",
        type=str,
        default=os.getenv("CI_JOB_TOKEN"),
        help="GitLab CI_JOB_TOKEN for API authentication (defaults to CI_JOB_TOKEN env var).",
    )
    # Add arguments for performance metrics if they were collected into a file
    # parser.add_argument("--performance-metrics-path", type=str, help="Path to a JSON file with performance metrics.")

    args = parser.parse_args()

    # Read file contents
    junit_xml_report_content = ""
    security_scan_report_content = ""
    custom_app_logs_content = ""
    performance_metrics = None  # Placeholder for now

    if args.junit_xml_report_path and os.path.exists(args.junit_xml_report_path):
        with open(args.junit_xml_report_path, "r") as f:
            junit_xml_report_content = f.read()
    else:
        logging.warning(f"JUnit XML report not found at: {args.junit_xml_report_path}")

    if args.security_scan_report_path and os.path.exists(
        args.security_scan_report_path
    ):
        with open(args.security_scan_report_path, "r") as f:
            security_scan_report_content = f.read()
    else:
        logging.warning(
            f"Security scan report not found at: {args.security_scan_report_path}"
        )

    if args.server_log_path and os.path.exists(args.server_log_path):
        with open(args.server_log_path, "r") as f:
            custom_app_logs_content = f.read()
    else:
        logging.warning(f"Server log not found at: {args.server_log_path}")

    analysis_results = duo_troubleshoot(
        gitlab_ci_log_content=args.gitlab_ci_log_placeholder,  # This will be overridden if API fetch succeeds
        playwright_html_report_path=args.playwright_html_report_path,
        junit_xml_report_content=junit_xml_report_content,
        security_scan_report_content=security_scan_report_content,
        performance_metrics=performance_metrics,
        custom_app_logs_content=custom_app_logs_content,
        gitlab_project_id=args.gitlab_project_id,
        gitlab_test_job_id=args.gitlab_test_job_id,
        gitlab_job_token=args.gitlab_job_token,
    )

    print(json.dumps(analysis_results, indent=2))
