# Dough

Dough is a GTK 4 desktop app for personal envelope budgeting. It helps you keep two views of your money connected: the account view, where money physically lives, and the envelope view, what that money is meant to do.

The current codebase is a SQGI/Squirrel app backed by Spinodb persistence. It is usable today for tracking accounts, envelopes, budgets, transactions, imports, and reports, with active work continuing on polish and deeper workflow coverage.

## Features

- Envelope budgeting with separate income and expense folders.
- Accounts with opening balances and calculated current balances.
- Income, expense, and transfer transactions.
- Transaction splits across multiple envelopes.
- Period budgets for weekly, fortnightly, or monthly planning.
- Dashboard and budget reports that compare budgeted and actual activity.
- Line and pie charts with PNG export.
- CSV and QIF transaction import.
- QIF transaction export.
- Regex-based import rules that assign imported transactions to envelopes.
- Guided setup walkthrough and first-run setup checklist.
- Spinodb-backed local persistence with journaling.
- SQGIPkg packaging configuration for Linux and Windows.

## Requirements

For development you need:

- `sqgi`
- `sqgipkg`
- GTK 4 and GObject Introspection runtime files
- Spinodb / `Spino-1.2` typelib

For packaging, the manifest also builds or bundles:

- SQGI from `https://github.com/supercamel/sqgi.git` at `v0.1.6-alpha`
- Spinodb from `https://github.com/supercamel/spinodb`
- CMake and Ninja
- Meson, for the Spinodb native project
- Linux GTK runtime packages or MSYS2 MinGW GTK packages, depending on target

See [sqgipkg.json](sqgipkg.json) for the exact package and native build configuration.

## Running

Run the app directly during development:

```sh
sqgi main.nut
```

Run the built-in smoke test:

```sh
sqgi main.nut --smoke
```

The smoke test opens the app, exercises key windows and workflows, and exits.

## Validation

Validate the manifest, resources, Squirrel scripts, native libraries, typelibs, and portability hints:

```sh
sqgipkg --doctor
```

## Packaging

Build a package with SQGIPkg:

```sh
sqgipkg --manifest sqgipkg.json --target appimage
```

Other configured targets include Linux sysroot/AppDir/tarball style outputs and Windows directory or NSIS installer outputs:

```sh
sqgipkg --manifest sqgipkg.json --target win-dir
sqgipkg --manifest sqgipkg.json --target win-nsis
sqgipkg --manifest sqgipkg.json --target all
```

The Windows NSIS installer uses `assets/icon.ico` and installs per-user by default.

## Data Storage

By default Dough stores the active budget document at:

```text
~/.local/share/dough/dough.spino
```

Spinodb journaling is enabled alongside that file:

```text
~/.local/share/dough/dough.spino.journal
```

The repository currently stores one active Dough document in the Spinodb `state` collection. The model includes document settings, periods, accounts, folders, envelopes, budget rows, transactions, splits, import rules, and tutorial state.

## Project Layout

```text
.
|-- main.nut                         # Application entry point
|-- sqgipkg.json                     # SQGIPkg build and packaging manifest
|-- app/
|   |-- application.nut              # GTK application, pages, dialogs, workflows
|   |-- assets.nut                   # Runtime asset lookup
|   |-- models.nut                   # Budget domain model and sample data
|   |-- repository.nut               # Spinodb persistence layer
|   `-- ui_helpers.nut               # GTK widget helpers
|-- assets/                          # Icons and navigation imagery
|-- docs/
|   |-- philosophy-concepts-workflow.md
|   |-- porting-audit.md
|   `-- ui-improvement-plan.md
`-- packaging/
    `-- disable-cross-gir.sh         # Native build helper for cross builds
```

## Development Notes

Useful places to start:

- Product concepts and intended workflow: [docs/philosophy-concepts-workflow.md](docs/philosophy-concepts-workflow.md)
- Port status and known gaps: [docs/porting-audit.md](docs/porting-audit.md)
- GTK 4 shell and overlay direction: [docs/ui-improvement-plan.md](docs/ui-improvement-plan.md)

The main application is currently concentrated in `app/application.nut`. Future cleanup should split page builders and task overlays into smaller modules once the GTK 4 presentation model settles.

## Current Status

Dough is an active, usable budgeting app with the core workflows in place: accounts, envelope setup, period budgets, transactions, imports, reports, graphs, and persistence. Development is continuing on UI polish and advanced workflow depth, especially around transfer editing, saved filters, and richer report customization.
