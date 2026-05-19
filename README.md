# CLMS Support Agent

PowerShell-based automation agent created to simplify endpoint maintenance, script deployment and operational tasks in small IT environments.

## Background

The project was created after facing a very common problem in small support operations:

Routine maintenance tasks were being executed manually on every machine, including:

- software updates
- maintenance scripts
- administrative commands
- endpoint configuration
- troubleshooting routines

One specific example was updating applications using:

```powershell
winget upgrade --all
```

This process required manually accessing every machine, entering administrator credentials and executing the commands individually.

Besides being time consuming, there was also no:

- centralized control
- version management
- execution tracking
- rollback process
- remote disable/update capability
- standardized logging

## Goal

The main idea behind the project was to create a lightweight automation agent capable of:

- receiving centralized script updates
- downloading scripts automatically
- controlling versions using manifests
- executing maintenance routines remotely
- collecting execution logs
- organizing scripts by client/environment
- reducing repetitive operational workload

The project uses GitHub as a lightweight command/control and version distribution platform.

## Technologies Used

- PowerShell
- GitHub
- JSON manifests
- Windows Task Scheduler
- Python (support modules)
- Winget

## Features

- Bootstrap installation process
- Centralized script repository
- Automatic script updates
- Manifest-based version control
- Local logging system
- Modular script execution
- Multi-client structure
- Lightweight architecture
- Remote maintenance automation

## Project Structure

```text
CLMS/
├── agent_2.0.ps1
├── manifest.json
├── SCRIPTS/
│   ├── GLOBAL/
│   ├── CLIENT_A/
│   └── CLIENT_B/
├── LOGS/
└── state.json
```

## Why GitHub?

GitHub was used as a lightweight and practical way to:

- distribute scripts
- control versions
- manage updates
- centralize maintenance routines
- simplify deployment

without requiring a dedicated infrastructure or management server.

## Future Improvements

Planned future improvements include:

- dashboard interface
- centralized log collection
- GLPI integration
- Grafana integration
- automatic ticket creation
- Ollama/LLM integration
- remote execution management
- inventory system
- REST API
- Docker support

## Purpose

This project was developed as a personal study and real-world automation initiative focused on:

- infrastructure automation
- endpoint management
- operational standardization
- support optimization
- PowerShell scripting
- systems integration

---

> Built to solve real operational problems in small IT environments.
