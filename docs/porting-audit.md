# Dough GTK4/SQGI Port Audit

This audit compares the current SQGI/GTK4 port with the old GTK2mm code in
`/home/sam/Programming/dough-code`.

## Source Areas Reviewed

- `main.cpp`, `gui.cpp`, `gui.h`: startup, main hub, period navigation, toolbar/menu actions.
- `gui_accounts.cpp`, `add_account.cpp`, `gui_edit_trn.cpp`, `gui_tran_splitter.cpp`, `gui_filter.cpp`, `gui_import.cpp`: account, transaction, filter, split, QIF import/export workflows.
- `gui_budget.cpp`, `gui_budget_edit_trn.cpp`: budget editor, budget item editing, clear/copy/remove, balance indicator.
- `gui_envelopes.cpp`, `gui_envelope_chooser.cpp`: income/expense folders, envelopes, descriptions, hidden flags, chooser.
- `gui_options.cpp`: title, currency, reserve, date format, start date, period length.
- `gui_budget_review.cpp`, `gui_line_graph.cpp`, `gui_pie_chart.cpp`: budget review, chart modes, date ranges, custom envelope selection, graph export.
- `gui_new.cpp`: original new-file wizard for accounts, income folders/envelopes, expense folders/envelopes.

## Current Port Status

The SQGI port now has a modular GTK4 application with:

- `DoughApplication` as the GTK controller.
- `SpinodbRepository` persistence using `Spino 1.2`.
- Domain objects for accounts, folders, envelopes, transactions, transaction splits, import rules, budgets, and document settings.
- Auto-persistence to `~/.local/share/dough/dough.spino`.
- A dashboard with budget bars and period navigation.
- Top-level windows for Accounts, Budget, Report, Envelopes, Line Graph, Pie Chart, Options, and About.

## Ported Workflows

### Data Model and Persistence

- Account records store name, number, description, and opening balance.
- Income and expense folders contain distinct envelope records with descriptions and hidden flags.
- Transactions store account, date, type, folder/envelope path, description, amount, transfer account, and optional split rows.
- Budget records are linked to real folders/envelopes and period labels.
- Import rules store regex patterns, target type, target folder/envelope, priority, and enabled state.
- Settings store title, currency, reserve settings, date format, start date, and period length.
- Weekly, fortnightly, and monthly period labels are generated from the configured ISO start date.
- Legacy simple budget rows are migrated into the richer folder/envelope shape on load.

### Accounts

- Add, edit, and delete accounts.
- Edit account name, number, opening balance, and description.
- Show calculated current balance.
- Add, edit, delete, and split transactions.
- Filter transactions by description, date text, account, type, and envelope path.
- Record income, expense, and transfer transaction types.
- Import CSV and QIF files.
- CSV import supports configurable zero-based date, description, amount, memo, debit, and credit columns.
- CSV and QIF imports route transactions through persisted regex envelope match rules.
- Existing transaction rows can be reclassified through the current import rules with the `Auto` action.
- Export bank-style QIF files.

### Budget

- Add new income and expense envelopes directly from the budget editor.
- Add existing income or expense envelopes through a chooser window.
- Edit budget row envelope name, type, folder/envelope path, and allocated amount.
- Remove budget rows.
- Clear the budget.
- Copy current budget rows.
- Show income, expenses, reserve, unallocated totals, and a balance indicator.
- Dashboard/report spending is calculated from transactions and split rows where available.

### Envelopes

- Separate income and expense tabs.
- Add/delete folders.
- Add/delete envelopes.
- Edit folder names.
- Edit envelope names and descriptions.
- Toggle folder/envelope hidden state.
- Deleting folders/envelopes removes related budgets and transactions.

### Options

- Edit budget title and currency symbol.
- Toggle reserve and edit reserve amount.
- Edit date format, start date, and period length.
- Regenerate period labels when period settings change.

### Reports and Graphs

- Budget report has table and graph tabs.
- Report shows income, expense, spent, and unallocated totals.
- Line graph and pie chart windows draw from the current persisted model.
- Graph windows include mode/date controls and PNG export.

### Import Rules

- Pre-made regex rules classify groceries, utilities, transport, eating out, salary, and interest.
- Import rules are editable from the Import window.
- Rules can be enabled/disabled, reprioritized, tested against sample text, deleted, added, or reset to defaults.
- Rules are persisted in Spinodb with the rest of the Dough document.

## Remaining Gaps

This is now a functional broad port, but it is not yet a pixel-for-pixel or behavior-for-behavior clone of the old GTK2mm app.

- Some editors still expose internal IDs (`account_id`, `folder_id/envelope_id`) instead of using polished combo boxes everywhere.
- Transaction filters are still ad hoc window controls, not the old saved filter editor model.
- Transfer editing exists as data fields but does not yet provide a guided account selector or paired transaction UI.
- CSV/QIF import is intentionally practical rather than exhaustive; it does not yet map multiple source accounts, QIF categories, or all QIF variants.
- Budget copy currently duplicates current rows; it does not yet copy from a true previous-period budget snapshot.
- Reports and graphs do not yet implement the old custom envelope/color selection workflows.
- Graph date range and mode controls are present but not deeply wired into separate report calculations.
- The old setup wizard has not been rebuilt; the `New` button creates a new Spinodb-backed document directly.
- Spinodb persistence still stores one document in the `state` collection. A future schema could split accounts, transactions, folders, envelopes, budgets, and settings into separate collections with indexes.

## Validation

- `sqgipkg --doctor` compiles every script and validates resources, the Spino shared library, and the Spino typelib.
- `sqgi main.nut --smoke` opens the main windows and exits successfully.
- Import smoke checks verify CSV and QIF rule-based envelope assignment.
- A model smoke check verifies generated weekly periods and split-aware budget spending.
- A Cairo smoke check exports a non-empty PNG graph.
