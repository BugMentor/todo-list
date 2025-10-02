# 🤖 Playwright Todo App: A Target for CI/CD Troubleshooting

<div align="center">
  <img src="https://raw.githubusercontent.com/abdellatif-laghjaj/todo-list/main/assets/todo_app_screenshot.png" alt="Playwright Todo App Screenshot" width="300">
  
  <p align="center">A simple web-based Todo List application designed as a practical target for **End-to-End Testing** and **AI-Driven CI/CD Pipeline Troubleshooting** using **GitLab Duo**.</p>
  
  <a href="https://github.com/microsoft/playwright">
    <img src="https://img.shields.io/badge/Tested%20With-Playwright-brightgreen?style=for-the-badge&logo=playwright" alt="Tested with Playwright">
  </a>
  <a href="https://docs.gitlab.com/ee/user/gitlab_duo/">
    <img src="https://img.shields.io/badge/AI%20Troubleshooting-GitLab%20Duo-orange?style=for-the-badge&logo=gitlab" alt="GitLab Duo AI">
  </a>
</div>

---

## Table of Contents

- [🤖 Playwright Todo App: A Target for CI/CD Troubleshooting](#-playwright-todo-app-a-target-for-cicd-troubleshooting)
  - [Table of Contents](#table-of-contents)
  - [1. Introduction](#1-introduction)
  - [2. Context: Target for GitLab Duo AI](#2-context-target-for-gitlab-duo-ai)
    - [🚀 The Duo Troubleshooting Stage](#-the-duo-troubleshooting-stage)
      - [A. Pipeline Failure Analysis (Demo Scenario 1)](#a-pipeline-failure-analysis-demo-scenario-1)
      - [B. Security Vulnerability Analysis (Demo Scenario 2)](#b-security-vulnerability-analysis-demo-scenario-2)
  - [3. Project Overview \& Features](#3-project-overview--features)
  - [4. Getting Started](#4-getting-started)
    - [Prerequisites](#prerequisites)
    - [Installation](#installation)
  - [5. Dependencies \& Tech Stack](#5-dependencies--tech-stack)
  - [6. Code Architecture (Refactoring Focus)](#6-code-architecture-refactoring-focus)
  - [7. License](#7-license)

---

## 1. Introduction

Welcome to the documentation for the **Playwright Todo App**.

This repository is utilized as the application under test (AUT) for demonstrating advanced **CI/CD Pipeline Optimization** and **Troubleshooting**. It features a modern, refactored codebase built with clean architecture principles, making it an ideal subject for robust **End-to-End (E2E) testing** and subsequent **AI analysis** of failures.

The primary focus of this project's CI pipeline is the integration of the **GitLab Duo AI** tool, which analyzes complex test failures and security reports to provide **actionable recommendations**.

---

## 2. Context: Target for GitLab Duo AI

This repository is designed to simulate the challenges addressed in the "AI-Driven Pipeline Optimization & Troubleshooting with GitLab Duo" presentation, specifically:

### 🚀 The Duo Troubleshooting Stage
The CI/CD configuration includes a dedicated stage, typically named `duo_troubleshoot`, which executes when a prior stage (like `e2e_tests` or `security_scan`) fails.

#### A. Pipeline Failure Analysis (Demo Scenario 1)
When Playwright E2E tests fail, this stage uses **GitLab Duo CLI** to analyze the lengthy, complex job logs.
* **AI Output:** Provides a concise, human-readable summary of the failure, identifies the likely root cause, and suggests code remediation steps, significantly reducing **Mean Time To Resolution (MTTR)**.

#### B. Security Vulnerability Analysis (Demo Scenario 2)
When dependency or SAST scans (like `npm audit`) produce dense technical reports, this stage simplifies the output.
* **AI Output:** Explains the vulnerability's impact, assigns a clear severity level, and outlines the precise steps needed to patch the issue.

---

## 3. Project Overview & Features

The TO-DOIT App is a standard web-based task manager featuring:

* **CRUD Operations:** Easily add, edit, and delete tasks.
* **Status Management:** Mark tasks as pending or completed.
* **Filtering:** Filter tasks by status (All, Pending, Completed).
* **Theme Switching:** A persistent theme switcher.

---

## 4. Getting Started

Follow these steps to set up and run the application locally:

### Prerequisites
* Node.js (LTS recommended)
* A modern web browser
* Git

### Installation

1.  **Clone the Repository:**
    ```bash
    git clone git@github.com:abdellatif-laghjaj/todo-list.git
    ```

2.  **Navigate and Install Dependencies:**
    ```bash
    cd todo-list
    npm install  # Assuming npm is the package manager after refactoring
    ```

3.  **Run the Application (for local testing):**
    Open the `index.html` file directly in your preferred web browser.

---

## 5. Dependencies & Tech Stack

This project utilizes modern web technologies:

* **Core Language:** Vanilla JavaScript
* **Styling:** **Tailwind CSS** and **Daisy UI** (via CDN).
* **Testing (External):** Designed to be run with **Playwright** (though not contained in this repository, this is the environment for the Duo demo).
* **CI/CD Tooling:** **GitLab CI/CD** and **GitLab Duo CLI**.

---

## 6. Code Architecture (Refactoring Focus)

The underlying codebase was heavily refactored to serve as a robust, maintainable target for testing. Key architectural highlights include:

* **Single Responsibility Principle (SRP):** Logic is strictly separated into dedicated classes:
    * **`TodoManager`**: Handles all business logic and state management.
    * **`UIManager`**: Handles all DOM manipulation and event listening.
    * **`ThemeSwitcher`**: Manages theme state (using the **Singleton Pattern**).
* **Design Patterns:**
    * **Singleton Pattern** (`ThemeSwitcher`): Ensures centralized control over the application's theme.
    * **Strategy Pattern** (`TodoItemFormatter`): Ensures consistent, interchangeable formatting logic for tasks.

---

## 7. License

This project is licensed under the **[MIT License](https://opensource.org/licenses/MIT)**.
