---
name: python-env
description: Setting up a Python project's environment. A sample skill that ships with Skill Health.
---

# Python environment

Create and activate a virtual environment in the project folder:

    python3 -m venv .venv
    source .venv/bin/activate

Install what the project needs with `pip install -r requirements.txt`, or, if the project uses
uv, `uv sync` creates the environment and installs everything in one step.
