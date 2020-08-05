# zsh-updater - Update your software from source with simple zsh scripts

## Introduction

Writing compile scripts for software has many repetitive tasks:

- Creating a temporary build directory
- Checking the currently running platform
- Querying the newest version from the internet
- Cleaning up afterwards
- etc.

Therefore, I have decided to write a small set of utility scripts for these tasks, so compile scripts can stay lean and
simple. Compile scripts run in zsh since it is more powerful than bash and makes some tasks easier. Current software
versions can be queried by Git url (latest tag) or by a website url with CSS selector to extract text information of a
project homepage.

## Requirements

This tool needs Python 2.7 or 3.3+. You can check your installed Python version with

```bash
python --version
```

If you are running a recent Linux distribution or macOS, an appropriate Python version should already be installed.

You need ``requests`` and ``pyquery`` as additional Python packages. These can be installed via ``pip``:

```bash
pip install requests pyquery
```

## Installation

### Using zplug

1. Add `zplug "IngoMeyer441/zsh-updater"` to your `.zshrc`.

2. Run

   ```bash
   zplug install
   ```

### Manual

1. Clone this repository and source `updater.plugin.zsh` in your `.zshrc`
