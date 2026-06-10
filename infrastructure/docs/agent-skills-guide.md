<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# AI Agent-Driven Development Strategy

AI Agent-Driven Development Strategy shows how to structure the AI agent guidance for this edge infrastructure repository using context files, scoped rules, and agent skills, while enabling developers and customers to run platform workflows through natural language.

Audience: Engineering Leads, Solution Architects, Program Managers, and Component Developers.

Date: April 2026

## Scope

This document has two goals:

1. Help developers write new skills for the component they own.
2. Help customers use those skills with consistent results.

## Architecture

### The Five Layers of AI Agent Instruction

| Layer | Name | Purpose | Examples |
|------|------|---------|----------|
| LAYER 5 | Model Context Protocol (MCP) SERVERS | Real-time tools and system integration to query state and perform controlled actions | Query cluster state, run benchmarks, flash OS images, and deploy containers |
| LAYER 4 | AGENT SKILLS | Domain expertise packages through SKILL.md and optional component or skill scripts | create-image, deploy-plugins, deploy-apps, run-benchmark |
| LAYER 3 | SLASH COMMANDS | Repeatable workflow automation | /create-image, /deploy-plugins, /deploy-apps, /run-benchmark |
| LAYER 2 | SCOPED RULES | Per-directory or per-file-type rules | module-specific AGENTS.md instructions |
| LAYER 1 | CONTEXT FILES | Always-on project knowledge | AGENTS.md and CLAUDE.md |

Each layer builds on the one below. Layer 1 provides the baseline context and Layer 5 provides the live system action.

MCP is part of the architecture. Detailed MCP server implementation guidance will be covered in a separate document.

## Part 1: Foundational Concepts

### 1.1 Context Engineering

Prompting is not enough for repeatability. Context engineering defines the persistent instructions that make agent behavior stable across sessions.

### 1.2 File Types and Role

| File | Scope | Use |
|------|-------|-----|
| AGENTS.md | Per-directory | Universal context and constraints |
| CLAUDE.md | Hierarchical, Claude-specific context file | Skill discovery and Claude behavior |
| .github/copilot-instructions.md | Repository-wide | Copilot-specific coding and review conventions |
| skills/<skill-id>/SKILL.md | Per skill | Executable workflow contract |

Recommended baseline: use AGENTS.md everywhere, then add tool-specific files where needed.

## Part 2: Repository Structure for Skill Authoring

### 2.1 Reference Layout

```text
ENIB/
  AGENTS.md
  CLAUDE.md
  .github/copilot-instructions.md
  os-provisioning/
    AGENTS.md
  intel-drivers/
    AGENTS.md
  ai-runtime/
    AGENTS.md
  benchmarks/
    AGENTS.md
  skills/
    create-image/
    create-usb-installation-files/
    validate-platform-config/
```

### 2.2 Repository Files Used in This Workspace

Use the current repository files directly rather than maintaining separate template copies:

- Repository context: [AGENTS.md](../../AGENTS.md)
- Claude behavior and skill contract: [CLAUDE.md](../../CLAUDE.md)
- Infrastructure-scoped context: [infrastructure/AGENTS.md](../AGENTS.md)
- Copilot behavior and execution instructions: [.github/copilot-instructions.md](../../.github/copilot-instructions.md)
- Skill definition in use: [skills/create-image/SKILL.md](../../skills/create-image/SKILL.md)

### 2.3 Adding New Component Skills

When adding a new component skill:

1. Add or update the nearest AGENTS.md file in that component path.
2. Create the new skill at `skills/<skill-id>/SKILL.md.`
3. Ensure CLAUDE.md and .github/copilot-instructions.md continue to point to the same execution contract.
4. Keep one authoritative source per file, and avoid duplicating template versions in documents.

## Part 3: How Developers Write New Component Skills

### 3.1 Pick a Narrow Component Workflow

Good first candidates:

1. Create images
2. Deploy plugins
3. Deploy applications
4. Run benchmarks

### 3.2 Reuse the Existing SKILL.md Contract

Use [skills/create-image/SKILL.md](../../skills/create-image/SKILL.md) as the baseline contract and copy its structure for new skills.

### 3.3 Keep SKILL.md Thin and Put Logic in Component Scripts

Put detailed execution in existing component scripts where possible, so SKILL.md stays readable and maintainable.

If needed, add skill-local scripts under skills/<skill-id>/scripts/.

Examples:

1. detect hardware
2. apply configuration edits
3. run build sequences
4. collect and format results

## Part 4: How Developers Try Out Skills

This section is a quick test checklist a developer can run immediately after writing a skill.

### 4.1 Pre-Test Setup

Before testing, confirm:

1. SKILL.md has the required inputs, preconditions, steps, validation, and rollback.
2. Commands in preconditions and validation are runnable on your machine.
3. Test data is ready for one success run and one failure run.
4. Any privileged steps are marked for confirmation.

### 4.2 Fast Smoke Test (First Run)

1. The agent picks the intended skill.
2. Preconditions run before execution.
3. The agent asks before running privileged or destructive steps.
4. Validation output is shown at the end.

## Part 5: Cross-Tool Skill Discovery

Once your skill is written and tested, add tool-specific instructions so that the Claude, Copilot, and Cursor AI agents all follow the same SKILL.md flow.

### 5.1 Where and How to Add Tool-Specific Instructions

| Tool | File to edit | Instruction to add |
|------|-------------|--------------------|
| Claude Code | CLAUDE.md | Discover skills from skills/, select by trigger phrase, execute in SKILL.md order: inputs → preconditions → steps → validation → rollback. |
| GitHub Copilot Code | .github/copilot-instructions.md | Use AGENTS.md as skill catalog, execute matching SKILL.md flow, do not skip preconditions or validation. |

## Part 6: How Customers Use Skills

### 6.1 Customer Journey

1. **Customer clones the Software Development Kit (SDK) or workspace.** The repository includes `AGENTS.md` with the platform overview, `CLAUDE.md` with the available skills, and `skills/` with tested skill definitions.

2. **The agent reads `AGENTS.md` and `CLAUDE.md` for context.** This gives the agent the component map, available skills, build order, and constraints before any user prompt is processed.

3. **Customer asks for a workload outcome in natural language.** For example:
   - *"Build an OS image for my Intel Core Ultra system."*
   - *"Deploy the GPU plugin on my provisioned node."*
   - *"Run the full AI benchmark suite and show me the results."*

4. **The agent selects the right component skill and asks for required inputs.** The agent matches the request to a skill trigger phrase (e.g., `create-image`, `deploy-plugins`, and `run-benchmark`) and prompts for any missing required inputs declared in `SKILL.md`. Example:
   > *"I'll use the `create-image` skill. Provide: target hardware profile (e.g., `ubuntu24-x86_64-minimal-ptl`) and any custom package list if needed."*

5. **Agent executes, validates, and returns the artifacts and status.** The agent runs preconditions, steps, and validation in order, pauses for confirmation before running privileged or destructive actions, and returns a summary with artifact paths and the pass or fail status.

### 6.2 Slash Commands Usage

Slash commands are used to run repeatable multi-step flows that call one or more skills in a fixed order. They are an optional, Claude-specific surface; in this repository the canonical execution contracts are the `SKILL.md` files under `skills/`. Slash commands are not maintained.

If you choose to add them for Claude code, the conventional location is `.claude/commands/<name>.md`.

The command's behavior must follow the same safety model as skills':

1. Run preconditions first
2. Ask before running privileged or destructive steps
3. Stop on validation failure
4. Return actionable result summary

## Summary

1. Skills are the contract between platform teams and customer experiences.
2. Keep each skill component-specific and testable.
3. Keep SKILL.md in skills/ and reuse component scripts when possible.
4. Design every skill for both author usability and customer usability.
