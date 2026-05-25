<!--
SPDX-FileCopyrightText: (C) 2026 Intel Corporation
SPDX-License-Identifier: Apache-2.0
-->

# AI Agent-Driven Development Strategy

How to structure AI agent guidance for this edge infrastructure repository using context files, scoped rules, and agent skills, while enabling developers and customers to run platform workflows through natural language.

Audience: Engineering Leads, Solution Architects, Program Managers, and component developers

Date: April 2026

## Scope

This document has two goals:

1. Help developers write new skills for the component they own.
2. Help customers use those skills with consistent results.

## Architecture

### The Five Layers of AI Agent Instruction

| Layer | Name | Purpose | Examples |
|------|------|---------|----------|
| LAYER 5 | MCP SERVERS | Real-time tools and system integration to query state and perform controlled actions | Query cluster state, run benchmarks, flash OS images, deploy containers |
| LAYER 4 | AGENT SKILLS | Domain expertise packages through SKILL.md and optional component or skill scripts | create-image, deploy-plugins, deploy-apps, run-benchmark |
| LAYER 3 | SLASH COMMANDS | Repeatable workflow automation | /create-image, /deploy-plugins, /deploy-apps, /run-benchmark |
| LAYER 2 | SCOPED RULES | Per-directory or per-file-type rules | module-specific AGENTS.md instructions |
| LAYER 1 | CONTEXT FILES | Always-on project knowledge | AGENTS.md, CLAUDE.md |

Each layer builds on the one below. Layer 1 provides baseline context, and Layer 5 provides live system action.

MCP is part of the architecture. Detailed MCP server implementation guidance will be covered in a separate document.

## Part 1: Foundational Concepts

### 1.1 Context Engineering

Prompting is not enough for repeatability. Context engineering defines the persistent instructions that make agent behavior stable across sessions.

### 1.2 File Types and Role

| File | Scope | Use |
|------|-------|-----|
| AGENTS.md | Per-directory | Universal context and constraints |
| CLAUDE.md | Hierarchical, Claude-specific | Skill discovery and Claude behavior |
| .github/copilot-instructions.md | Repo-wide | Copilot-specific coding and review conventions |
| .claude/skills/<skill-id>/SKILL.md | Per skill | Executable workflow contract |

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
  .claude/
    skills/
      create-image/
      deploy-plugins/
      deploy-apps/
      run-benchmark/
```

### 2.2 Repository Files Used in This Workspace

Use the current repository files directly rather than maintaining separate template copies:

- Repo context: [AGENTS.md](../../AGENTS.md)
- Claude behavior and skill contract: [CLAUDE.md](../../CLAUDE.md)
- Infrastructure-scoped context: [infrastructure/AGENTS.md](../AGENTS.md)
- Copilot behavior and execution instructions: [.github/copilot-instructions.md](../../.github/copilot-instructions.md)
- Skill definition in use: [.claude/skills/create-image/SKILL.md](../../.claude/skills/create-image/SKILL.md)

### 2.3 Adding New Component Skills

When adding a new component skill:

1. Add or update the nearest AGENTS.md in that component path.
2. Create the new skill at `.claude/skills/<skill-id>/SKILL.md.`
3. Ensure CLAUDE.md and .github/copilot-instructions.md continue to point to the same execution contract.
4. Keep one authoritative source per file, and avoid duplicating template versions in docs.

## Part 3: How Developers Write New Component Skills

### 3.1 Pick a Narrow Component Workflow

Good first candidates:

1. Create image
2. Deploy plugins
3. Deploy apps
4. Run benchmark

### 3.2 Reuse the Existing SKILL.md Contract

Use [.claude/skills/create-image/SKILL.md](../../.claude/skills/create-image/SKILL.md) as the baseline contract and copy its structure for new skills.

### 3.3 Keep SKILL.md Thin and Put Logic in Component Scripts

Put detailed execution in existing component scripts where possible so SKILL.md stays readable and maintainable.

If needed, add skill-local scripts under .claude/skills/<skill-id>/scripts/.

Examples:

1. detect hardware
2. apply config edits
3. run build sequence
4. collect and format results

## Part 4: How Developers Try Out Skills

This section is a quick test checklist a developer can run immediately after writing a skill.

### 4.1 Pre-Test Setup

Before testing, confirm:

1. SKILL.md has required inputs, preconditions, steps, validation, and rollback.
2. Commands in preconditions and validation are runnable on your machine.
3. Test data is ready for one success run and one failure run.
4. Any privileged steps are marked for confirmation.

### 4.2 Fast Smoke Test (First Run)

1. Agent picks the intended skill.
2. Preconditions run before execution.
3. Agent asks before privileged or destructive steps.
4. Validation output is shown at the end.

## Part 5: Cross-Tool Skill Discovery

Once your skill is written and tested, add tool-specific instructions so Claude, Copilot, and Cursor all follow the same SKILL.md flow.

### 5.1 Where and How to Add Tool-Specific Instructions

| Tool | File to edit | Instruction to add |
|------|-------------|--------------------|
| Claude Code | CLAUDE.md | Discover skills from .claude/skills/, select by trigger phrase, execute in SKILL.md order: inputs → preconditions → steps → validation → rollback. |
| GitHub Copilot | .github/copilot-instructions.md | Use AGENTS.md as skill catalog, execute matching SKILL.md flow, do not skip preconditions or validation. |

## Part 6: How Customers Use Skills

### 6.1 Customer Journey

1. **Customer clones the SDK or workspace.** The repo includes `AGENTS.md` with the platform overview, `CLAUDE.md` listing available skills, `.claude/skills/` with tested skill definitions.

2. **Agent reads `AGENTS.md` and `CLAUDE.md` for context.** This gives the agent the component map, available skills, build order, and constraints before any user prompt is processed.

3. **Customer asks for a workload outcome in natural language.** For example:
   - *"Build an OS image for my Intel Core Ultra system."*
   - *"Deploy the GPU plugin on my provisioned node."*
   - *"Run the full AI benchmark suite and show me the results."*

4. **Agent selects the right component skill and asks for required inputs.** The agent matches the request to a skill trigger phrase (e.g., `create-image`, `deploy-plugins`, `run-benchmark`) and prompts for any missing required inputs declared in `SKILL.md`. Example:
   > *"I'll use the `create-image` skill. Please provide: target hardware profile (e.g., `ubuntu24-x86_64-minimal-ptl`) and any custom package list if needed."*

5. **Agent executes, validates, and returns artifacts and status.** The agent runs preconditions, steps, and validation in order, pauses for confirmation before privileged or destructive actions, and returns a summary with artifact paths and pass/fail status.

### 6.2 Slash Commands Usage

Slash commands are used to run repeatable multi-step flows that call one or more skills in a fixed order.

Recommended location: `.claude/commands/create-image.md`

Typical usage:

```
1. /create-image <target-profile>
2. /deploy-plugins <gpu|npu>
3. /deploy-apps <app-profile>
4. /run-benchmark <suite>
```

Command behavior should follow the same safety model as skills:

1. Run preconditions first
2. Ask before privileged or destructive steps
3. Stop on validation failure
4. Return actionable result summary

## Summary

1. Skills are the contract between platform teams and customer experience.
2. Keep each skill component-specific and testable.
3. Keep SKILL.md in .claude/skills and reuse component scripts when possible.
4. Design every skill for both author usability and customer usability.
