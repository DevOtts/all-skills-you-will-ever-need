# AI Coding Rules and Claude SKILLs

Welcome to Devotts's public repository of AI coding rules for Cursor and SKILLs for Claude Code! This collection is designed to help AI developers, and AI agents themselves, improve the quality, consistency, and reliability of the code they write.

Initially focused on Cursor rules, this repository has expanded to prioritize Claude SKILLs, which provide powerful autonomous capabilities and integrations.

## Claude SKILLs (Priority)

These skills enhance Claude Code with specific, powerful capabilities.

---

### `launch`

**Description**: Mission control for autonomous projects — analyzes tasks, recommends approaches (sub-agents/teams), sets up environment (features, evals, hooks, init.sh), suggests and configures tooling (MCPs), and launches the work.

---

### `notebooklm`

**Description**: Complete API for Google NotebookLM - full programmatic access including features not in the web UI. Create notebooks, add sources, generate all artifact types, download in multiple formats. Activates on explicit /notebooklm or intent like "create a podcast about X"

---

## Cursor Rules

By leveraging Cursor's powerful rule-based customization, you can enforce best practices, institutionalize knowledge, and guide AI-driven development toward more robust and maintainable outcomes.

### How to Use Cursor Rules

1.  **Clone or Fork this Repository**: Get a local copy of these rules.
2.  **Copy to Your Project**: Copy the `.mdc` files from the `.cursor/rules/` directory into the `.cursor/rules/` directory of your own project.
3.  **Customize**: Adapt the `globs` and content of the rules to match your project's structure and specific needs.
4.  **Let Cursor Work**: Cursor will automatically apply these rules during your coding sessions, guiding you and any AI assistants you work with.

### Cursor Rules Overview

Here is a breakdown of the rules available in this repository:

---

### `cursor_rules.mdc`

**Description**: Guidelines for creating and maintaining Cursor rules to ensure consistency and effectiveness.

This meta-rule establishes the standard format for all other rules. It defines the required frontmatter (`description`, `globs`, `alwaysApply`), file referencing syntax, and best practices for writing clear and actionable rule content.

---

### `dev_workflow.mdc`

**Description**: Guide for using Task Master to manage task-driven development workflows.

This rule outlines a comprehensive development workflow centered around the "Task Master" tool. It covers project initialization, task management (listing, viewing, breaking down), handling implementation drift, and the iterative process of implementing subtasks, including logging progress and updating rules.

---

### `e2e-testing-rules.mdc`

**Description**: Best practices for creating and maintaining end-to-end (E2E) tests.

This rule defines a robust E2E testing strategy. Key principles include testing against a real database, ensuring full workflow coverage, isolating data per test, and generating automated cleanup scripts. It provides a standard structure for test files and a helper `apiCall` function.

---

### `error-context-logging.mdc`

**Description**: Enforces logging best practices to ensure that when errors occur, they provide enough context to be debugged quickly.

This rule tackles insufficient error context by mandating structured, contextual logging. It introduces a "5-Minute Debugging Protocol" for API errors and provides patterns for enriching error messages with the specific data that caused the failure.

---

### `mcp_server_rules.mdc`

**Description**: Best practices for working with MCP (Model Context Protocol) Servers.

This rule focuses on defining clear and unambiguous tool descriptions for AI agents. It mandates that every tool description must explain its purpose, define the required input structure, and provide a realistic JSON example to ensure AI agents can build correct requests.

---

### `medium-sized-coding-tasks.mdc`

**Description**: Structured workflow for medium-sized coding tasks involving multiple files, refactoring, or complex debugging.

This rule provides a systematic approach for tasks that are too complex for a single edit but not large enough for a full task-management system. It enforces a pre-coding analysis phase, the creation of a JSON tracking document, and a user-authorization gate before implementation begins.

---

### `microfactory-best-practices.mdc`

**Description**: Enforces best practices for development, covering database, Next.js, React, and data handling.

This is a comprehensive rule set covering a wide range of best practices, including:
-   **Database**: `snake_case` naming, handling multiple foreign keys.
-   **Next.js**: Separating Server/Client components, handling dynamic routes, configuring external image sources.
-   **React**: Avoiding infinite update loops.
-   **Data**: Bulk import/export patterns.
-   **API**: Forcing Node.js runtime and correctly typing HOC context parameters for API routes.
-   **Authentication**: Implementing `withDualAuth` for JWT and service key support.

---

### `mongodb-field-mapping.mdc`

**Description**: Prevents common MongoDB validation errors by enforcing correct field mapping between the API layer and MongoDB models.

This rule addresses `ValidationError` issues by providing explicit mapping tables for common field name mismatches (e.g., `organization_id` in the API vs. `organizationId` in the Mongoose model). It also covers safe handling of `ObjectId` to `string` conversions.

---

### `n8n-mcp-workflow-building-rules.mdc`

**Description**: Comprehensive guidelines for building robust n8n workflows for MCP (Model Context Protocol) servers.

This extensive rule set provides a complete guide to building n8n workflows for MCP servers. It covers authentication, workflow architecture (single trigger, multiple tools), API endpoint configuration, tool description standards, error handling, testing, documentation, and performance optimization.

---

### `self_improve.mdc`

**Description**: Guidelines for continuously improving Cursor rules based on emerging code patterns and best practices.

This meta-rule defines a process for the AI to improve its own rule set. It outlines triggers for rule updates (e.g., new patterns, common errors), an analysis process, and quality checks to ensure the rule base evolves with the codebase.

---

### `service-data-transformation.mdc`

**Description**: Ensures that data is correctly transformed between different layers of the application (e.g., API to Service, Service to DB Model).

This rule prevents data format mismatches by enforcing the use of explicit transformation functions. It provides patterns for mapping API data to service-layer interfaces, validating file constraints for ingestion, and safely using optional chaining for nested properties.

---

### `taskmaster.mdc`

**Description**: Comprehensive reference for Taskmaster MCP tools and CLI commands.

This rule serves as a detailed command reference for the "Task Master" tool. It documents both the MCP tools (for AI/integration use) and the equivalent CLI commands, covering initialization, task management, AI model configuration, dependency management, and more.

---

### `use-context7-code-documentation.mdc`

**Description**: Proactively consults the Context7 MCP Server for internal documentation when encountering ambiguity or cognitive struggle.

This rule directs the AI to use an internal documentation server (Context7) when it's stuck. Triggers include semantic ambiguity, looping on a bug fix, or low-confidence guesses. This mimics a human developer's "pause and research" behavior.

---

### `vectorization-defaults.mdc`

**Description**: Prevents common search and indexing issues by ensuring that content is properly vectorized and stored in Weaviate.

This rule ensures content is made searchable by default. It enforces `vectorizeContent: true` for all new content, specifies the use of semantic chunking, and provides best practices for Weaviate integration, such as converting MongoDB `ObjectId`s to strings.

---

### `vercel-deployment.mdc`

**Description**: Documents essential practices and common pitfalls to avoid when deploying Next.js applications to Vercel.

A critical guide for Vercel deployments, this rule provides a pre-deployment checklist, solutions for common build errors (like `export-detail.json` missing), bundle size optimization strategies, and best practices for managing dependencies, environment variables, and serverless function architecture. 