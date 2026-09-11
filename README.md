# CLMS Support Agent

## Project Origin

This project started from a real operational need.

In the original environment, Windows endpoints needed to have their installed applications regularly updated using:

```powershell
winget upgrade --all
```

Running this manually on multiple machines quickly became impractical. The process also lacked centralized control over which applications should be updated, when the updates should run, and how different environments could receive different automation routines.

This led to the idea of building a centralized automation agent that could:

* Automate maintenance tasks across multiple Windows endpoints;
* Centralize scripts in a Git repository;
* Control script versions;
* Define which scripts should run on specific clients, sectors or machines;
* Execute tasks automatically without requiring manual intervention;
* Keep track of the execution state of each endpoint.

What started as a solution for automating `winget` updates evolved into the **CLMS Support Agent**, a general-purpose automation engine for centrally managing scripts and maintenance routines across different environments.

## How It Works

The CLMS Support Agent works as a bootstrap + scheduled automation system.

The initial setup is performed by the `agent.ps1` script. After the bootstrap is completed, the `engine.py` becomes responsible for continuously synchronizing the repository, reading the machine configuration, checking script versions and deciding which scripts must be executed.

The entire process can be divided into two main stages:

```text
Initial Setup
    │
    ▼
agent.ps1
    │
    ├── Prepare environment
    ├── Install dependencies
    ├── Clone repository
    ├── Create scheduled task
    └── Run engine.py
             │
             ▼
       Continuous Operation
             │
             ▼
          engine.py
             │
             ├── Git update
             ├── Read machine.json
             ├── Read manifest.json
             ├── Read state.json
             ├── Decide what to execute
             ├── Execute scripts
             └── Update state.json
```

### 1. Running the Bootstrap

The process starts by executing the agent with administrative privileges:

```powershell
.\agent.ps1 -cliente CLIENTE -setor SETOR
```

The `agent.ps1` script is responsible for preparing the endpoint to be managed automatically.

At this stage, the agent:

1. Validates that it is running with administrative privileges.
2. Creates the required directory structure.
3. Performs a network connectivity test to make sure the endpoint can reach the required resources.
4. Creates the `machine.json` file with the machine's identification information.
5. Creates the initial `state.json` file.
6. Checks whether the required dependencies are already installed.
7. Downloads and installs Python and Git directly from their official URLs when necessary.
8. Performs the installations silently, without requiring user interaction.
9. Clones the centralized GitHub repository to the local machine.
10. Creates the Windows Task Scheduler task responsible for running the automation engine.
11. Executes the `engine.py` for the first time.

After this process finishes, the endpoint is ready to operate autonomously.

---

### 2. `machine.json` — Machine Identity

The `machine.json` file identifies the endpoint inside the automation environment.

It stores information such as:

* Client/company
* Sector/environment
* Computer name

Conceptually, it works as the machine's **identity card** inside the agent.

For example:

```json
{
    "cliente": "TEST",
    "setor": "LAB1",
    "hostname": "LAB1-PC01"
}
```

The engine uses this information to determine **where the machine belongs** and consequently which scripts are applicable to it.

The machine identity is especially important because the same repository can contain scripts for multiple clients, sectors and environments.

---

### 3. `state.json` — Local Execution State

The `state.json` file stores the versions of the scripts that have already been processed by that specific machine.

It allows the engine to know what version of each script is currently installed/executed locally.

For example:

```json
{
    "script_a.ps1": "1.0.2",
    "script_b.ps1": "2.1.0"
}
```

This creates a local state that can be compared with the versions defined in the centralized `manifest.json`.

The important distinction is:

```text
manifest.json → What version SHOULD be available
state.json    → What version THIS MACHINE has processed
```

This version comparison is one of the mechanisms used by the engine to determine whether a script needs to be executed.

---

### 4. Installing the Repository

After the required dependencies are available, the agent clones the centralized repository locally.

The repository contains the automation scripts and the configuration required by the engine.

The endpoint therefore receives a local copy of the centralized automation environment:

```text
GitHub Repository
       │
       ▼
C:\CLMS\Github\repo
       │
       ├── manifest.json
       ├── engine.py
       └── scripts
```

From this point forward, the local repository becomes the source used by the engine.

---

### 5. Scheduled Execution

The bootstrap creates a Windows Task Scheduler task configured to execute the automation engine periodically.

The engine runs every **10 minutes**.

This means that after the initial setup, there is no need for an administrator to manually execute the agent again during normal operation.

```text
Windows Task Scheduler
          │
          │ every 10 minutes
          ▼
      engine.py
```

The scheduled execution allows changes made to the centralized repository to be automatically propagated to the managed endpoints.

---

# How `engine.py` Makes Decisions

The `engine.py` is the main component responsible for the continuous operation of the agent.

Every time it runs, it follows a defined sequence.

### 6. Repository Update

The first step is to synchronize the local repository with GitHub.

The engine performs a Git update so that the endpoint receives changes made to the centralized repository.

This allows scripts to be:

* Added
* Updated
* Removed
* Reconfigured through the manifest

The engine therefore works with the latest version of the repository before making execution decisions.

```text
GitHub
  │
  │ Git update
  ▼
Local Repository
```

---

### 7. Reading the Configuration Files

After updating the repository, the engine reads the JSON files used to make its decisions.

The three files have different responsibilities:

```text
machine.json
     │
     └── Who am I?

manifest.json
     │
     └── What should exist and where should it run?

state.json
     │
     └── What has this machine already processed?
```

Together, these files provide the information required by the engine.

---

## 8. `manifest.json` — Central Source of Truth

The `manifest.json` is the central configuration file of the project.

It is located at the root of the repository and defines the current version of each automation script and the targets to which that script applies.

A simplified example:

```json
{
    "scripts": [
        {
            "name": "script.ps1",
            "version": "1.2.0",
            "targets": ["*"]
        },
        {
            "name": "client_script.ps1",
            "version": "2.0.0",
            "targets": ["TEST:LAB1"]
        }
    ]
}
```

The `manifest.json` answers two important questions:

1. **Which version of the script is currently available?**
2. **Which machines/environments should execute it?**

### Global Scripts

A target of:

```text
*
```

means that the script is **global**.

It is applicable to all managed machines.

```text
targets: ["*"]
```

---

### Specific Client and Sector

A target such as:

```text
TEST:LAB1
```

means that the script applies specifically to:

```text
Client: TEST
Sector: LAB1
```

Therefore, only machines whose `machine.json` identifies them as `TEST:LAB1` should execute that script.

---

### Wildcard Targeting

The target can also use a wildcard for the machine/sector scope.

For example, a target representing:

```text
TEST:*
```

means that the script applies to **all machines belonging to the TEST sector/environment**, rather than to a single specific machine.

This targeting mechanism allows the same centralized repository to contain automation for different clients and environments without requiring separate repositories.

---

# 9. The Decision Process

Once the repository and JSON files have been loaded, the engine combines the information from `machine.json`, `manifest.json` and `state.json`.

The decision process can be represented as:

```text
              machine.json
                   │
                   ▼
        Identify this machine
                   │
                   ▼
              manifest.json
                   │
                   ▼
       Find applicable scripts
                   │
                   ▼
              state.json
                   │
                   ▼
       Compare script versions
                   │
                   ▼
        Should it be executed?
             /           \
           NO             YES
           │               │
           ▼               ▼
        Skip          Execute script
                           │
                           ▼
                      Update state
                           │
                           ▼
                       state.json
```

For each script defined in the manifest, the engine checks whether the current machine is one of its targets.

If the script does not apply to that machine, it is ignored.

If the script applies to the machine, the engine compares the version defined in `manifest.json` with the version stored in `state.json`.

Conceptually:

```text
Manifest version > State version
            │
            ▼
       New version
            │
            ▼
      Execute script
            │
            ▼
     Update state.json
```

If the machine already has the current version, the script does not need to be executed again.

This allows the system to continuously check for new versions without repeatedly executing scripts that are already up to date.

---

# 10. Updating `state.json`

After the execution process finishes, the engine updates `state.json` with the current state of the scripts.

This ensures that the next execution of the engine knows which versions have already been processed.

The complete cycle therefore becomes:

```text
GitHub
  │
  ▼
Git update
  │
  ▼
Read machine.json
  │
  ▼
Read manifest.json
  │
  ▼
Identify applicable scripts
  │
  ▼
Read state.json
  │
  ▼
Compare versions
  │
  ├───────────────┐
  │               │
  ▼               ▼
Already current   New version
  │               │
  ▼               ▼
Skip            Execute
                  │
                  ▼
             Update state
                  │
                  ▼
             state.json
```

The next scheduled execution repeats the same process.

---

# Complete Workflow

Putting everything together, the complete lifecycle of the CLMS Support Agent is:

```text
                    ADMINISTRATOR
                         │
                         │ agent.ps1
                         ▼
              ┌─────────────────────┐
              │      Bootstrap      │
              ├─────────────────────┤
              │ Create directories  │
              │ Network test        │
              │ machine.json        │
              │ state.json          │
              │ Install Python      │
              │ Install Git         │
              │ Clone repository    │
              │ Create scheduled task│
              └──────────┬──────────┘
                         │
                         ▼
                    engine.py
                         │
                         ▼
                  Git repository update
                         │
                         ▼
                  Read machine.json
                         │
                         ▼
                  Read manifest.json
                         │
                         ▼
                Find applicable scripts
                         │
                         ▼
                   Read state.json
                         │
                         ▼
                   Compare versions
                         │
                    ┌────┴────┐
                    │         │
                  Current    New
                    │         │
                    ▼         ▼
                   Skip     Execute
                              │
                              ▼
                         Update state
                              │
                              ▼
                         state.json
                              │
                              ▼
                    Wait for next run
                              │
                              ▼
                         10 minutes
                              │
                              └──────────► engine.py
```

The key idea behind the architecture is that the endpoint does not need to know in advance which scripts it should execute.

Instead, the **central repository defines the desired state through `manifest.json`**, while the endpoint identifies itself through `machine.json` and keeps track of its local execution state through `state.json`.

This makes it possible to centrally manage automation for multiple clients, sectors and machines using a single repository and a common execution engine.
