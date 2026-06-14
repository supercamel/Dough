# Dough Philosophy, Concepts, and Workflow

This document defines the product thinking behind Dough. It is the source of truth for future tutorial mode copy, popover sequencing, and first-run onboarding behavior.

## Product Philosophy

Dough is a personal finance app built around envelope budgeting and cash-flow awareness.

The central idea is simple: money has two stories.

- The account story: where the money physically is.
- The envelope story: what the money is meant to do.

Accounts answer questions like "How much is in checking?" and "Which card did this transaction hit?" Envelopes answer questions like "Was this grocery money?" and "How much transport budget is left this period?"

Dough should help users connect those two stories without making them feel like they are doing accounting homework. It should be calm, explicit, reversible where possible, and honest about what data will change.

## Core Principles

- The user owns the budget. Dough can suggest, auto-match, and summarize, but the user should stay in control of assignments.
- Envelopes are real persisted objects, not free-text tags. A transaction assigned to an envelope should point to an actual envelope record.
- Budgets are period plans. Transactions are actual activity. Reports compare the plan with what happened.
- Import should remove typing, not remove understanding. CSV/QIF import and regex rules should be visible enough that users can trust them.
- Destructive actions should be confirmed because deleting an account, folder, or envelope may remove related transactions, budgets, and rules.
- First-run guidance should teach concepts through the actual app structure, not through a separate fake wizard that hides the workflow.

## Key Concepts

### Document

A Dough document is the user's budget database. In the SQGI port it is stored through Spinodb rather than old CRF/XML file operations.

The document owns:

- options/settings
- accounts
- income and expense envelope folders
- envelopes
- budget rows
- transactions and splits
- import match rules

### Period

A period is the span of time for one budget cycle. Dough supports weekly, fortnightly, and monthly periods.

The period start date and period length generate period labels. The active period controls dashboard/report context and the period assigned to newly added budget rows.

Tutorial implication: explain period settings before asking the user to build a budget, because the budget belongs to a period.

### Account

An account represents where money actually lives or moves through: checking, savings, cash, credit card, or similar.

Accounts have:

- name
- number/reference
- opening balance
- description

Transactions affect account balances. Transfers move money between accounts.

Tutorial implication: the user should create at least one account before adding transactions.

### Envelope

An envelope represents a purpose for money. Examples:

- Salary
- Groceries
- Rent
- Utilities
- Eating Out
- Transport

Envelopes are grouped into income folders and expense folders. Income and expense envelopes are separate because incoming money and outgoing money are different budgeting concepts.

Tutorial implication: avoid describing envelopes as "tags". They are budget categories with identity and history.

### Folder

A folder organizes related envelopes. Examples:

- Income / Regular Income
- Expenses / Household
- Expenses / Transport
- Expenses / Personal

Folders can be hidden when they should not normally appear in chooser lists.

Tutorial implication: encourage a small first set of folders and envelopes. Users can refine later.

### Budget Row

A budget row links one real envelope to an amount for the current period.

For income rows, the amount is expected income for the period. For expense rows, the amount is planned spending for the period.

Budget rows are not the same thing as envelopes. An envelope is the category. A budget row is this period's plan for that category.

Tutorial implication: when teaching the Budget page, say "choose envelopes for this period and allocate amounts."

### Reserve

Reserve is money the user wants to keep out of normal allocation. It is a safety buffer.

The unallocated calculation is:

income budgeted - expense budgeted - reserve

Tutorial implication: reserve is optional. Introduce it after the user understands income, expenses, and unallocated money.

### Transaction

A transaction records real activity.

Transactions include:

- account
- date
- type: income, expense, or transfer
- envelope assignment for income/expense
- description
- amount
- optional split rows

Income and expense transactions should resolve to real envelopes. Transfers move money between accounts and do not need an envelope.

Tutorial implication: transaction entry should reinforce the two-story model: account is where it happened; envelope is what it was for.

### Split

A split divides one transaction across multiple envelopes.

Example: a single store purchase may include groceries, household supplies, and clothing.

Tutorial implication: splits are an advanced feature. Mention them after basic transaction entry, not during the first three steps.

### Import Rule

An import rule uses a regex-style pattern to match transaction descriptions and assign an envelope.

Rules have:

- enabled flag
- name
- pattern
- target type
- target envelope
- priority

Tutorial implication: explain import rules as "automatic envelope suggestions during import", not as a programming feature first. Regex details can come later.

### Dashboard And Reports

The dashboard gives a quick view of current budget envelope progress. Reports and graphs compare budgeted amounts and actual spending.

Tutorial implication: dashboard is the reward screen. It makes the setup work visible.

## Intended User Workflow

### 1. Set The Budget Frame

The user starts in Options.

They set:

- budget title
- currency
- start date
- period length
- optional reserve

This creates the calendar frame that later budget rows and reports depend on.

### 2. Create The Envelope Catalog

The user opens Envelopes and creates a small catalog.

Recommended first setup:

- one income folder with one or two income envelopes
- one expense folder with the user's most common expense envelopes

The goal is not a perfect category system. The goal is a usable first pass.

### 3. Add Accounts

The user opens Accounts and adds the accounts they want to track.

At minimum, they need one account before recording transactions. Opening balances let Dough calculate current balances without needing every historic transaction.

### 4. Build The Current Period Budget

The user opens Budget.

They add income and expense envelopes to the current period, then allocate expected income and planned expense amounts.

Important feedback:

- income total
- expense total
- reserve
- unallocated

The user should understand that unallocated money is the amount not yet assigned to expenses or reserve.

### 5. Record Or Import Transactions

The user opens Transactions or Import.

They can:

- add a transaction manually
- import CSV/QIF
- review imported transaction assignments
- edit the envelope on any transaction
- split transactions when needed

Transactions turn the budget from a plan into a living record.

### 6. Improve Import Matching

The user opens Import and edits match rules.

Rules make repeated merchants easier:

- salary descriptions go to Salary
- supermarket descriptions go to Groceries
- petrol/service station descriptions go to Transport

The tutorial should present this as an optional speed-up after the user has seen manual assignment.

### 7. Review And Adjust

The user returns to Dashboard, Budget Report, and graphs.

They look for:

- envelopes close to or over budget
- categories with unused money
- transactions assigned to the wrong envelope
- import rules that need refinement

Budgeting is iterative. Dough should normalize adjustment rather than imply the first setup should be perfect.

### 8. Move Through Periods

The user moves to the next period when the current budget cycle ends.

They may copy budget rows, change allocations, and continue recording transactions.

Tutorial implication: period navigation should be introduced after the first budget exists, not before.

## First-Run Tutorial Mode Goals

Tutorial mode should be optional, restartable, and non-destructive.

It should not overwrite the user's data. It should guide the user through creating or reviewing real records in their current document. If sample data is ever offered, it should be clearly isolated from the user's real budget.

The tutorial should use popovers for short, contextual teaching moments. Each popover should explain one idea, point at one control or page area, and offer clear next/skip actions.

## Suggested Tutorial Sequence

### Step 1: Welcome

Explain the two-story model:

- accounts track where money is
- envelopes track what money is for

Primary action: start setup.

### Step 2: Options

Guide the user to set currency, start date, and period length.

Do not over-explain reserve yet. Mention that it is optional.

### Step 3: Envelopes

Guide the user to create a first income envelope and a few expense envelopes.

Suggested copy:

"Envelopes are the jobs you give your money. Start small; you can rename or add more later."

### Step 4: Accounts

Guide the user to add an account with an opening balance.

Suggested copy:

"Accounts are where money lives. Transactions will change these balances over time."

### Step 5: Budget

Guide the user to add envelopes to the current period and enter planned amounts.

Explain income, expenses, reserve, and unallocated.

Suggested copy:

"This page is the plan for the current period. Income adds money to allocate; expenses and reserve give that money a job."

### Step 6: Transactions

Guide the user through adding one transaction.

Explain account vs envelope assignment.

Suggested copy:

"The account says where the transaction happened. The envelope says what it was for."

### Step 7: Import

Introduce CSV/QIF import as a faster path once the basics are understood.

Explain that import rules can automatically assign envelopes from transaction descriptions.

### Step 8: Review

Return to Dashboard and Budget Report.

Explain that reports compare the plan with actual transactions.

### Step 9: Finish

Tell the user where to return:

- Envelopes to change categories
- Accounts to add real-world accounts
- Budget to plan each period
- Transactions/Import to record activity
- Reports to review progress

## Popover Design Rules

- One concept per popover.
- Keep copy short and concrete.
- Anchor popovers to real controls whenever possible.
- Prefer "Next", "Back", "Skip tutorial", and "Done" actions.
- Do not block ordinary app use after the user skips.
- If a required prerequisite is missing, guide the user to create it instead of showing an error.
- Avoid outside-click close for steps where the user may be typing.
- Persist tutorial completion state separately from budget data.

## Tutorial Readiness Checks

Tutorial mode can decide where to begin by checking the document state:

- no accounts: guide Accounts
- no folders/envelopes: guide Envelopes
- no budget rows: guide Budget
- no transactions: guide Transactions or Import
- import rules missing: offer Import Rules intro

These checks should help users resume setup naturally instead of forcing a fixed wizard from the beginning.

Tutorial state is stored separately from the budget document in Spinodb app metadata. Dough records whether the guide was completed, whether the first-run offer was dismissed, and the last guide step reached. Budget data stays portable and clean; onboarding state is treated as UI state.

## Tone

Dough should sound practical, calm, and lightly encouraging.

Use language like:

- "Give this money a job."
- "Start with the categories you actually use."
- "You can refine this later."
- "This transaction needs both an account and an envelope."

Avoid language like:

- "You did this wrong."
- "Invalid budget."
- "Advanced regex configuration required."
- "Perfect setup."

## Tutorial Mode Non-Goals

- It should not give financial advice.
- It should not require users to create a perfect zero-based budget.
- It should not import or generate sample data without explicit consent.
- It should not hide the real app behind a separate onboarding-only UI.
- It should not teach every advanced feature on first run.

## Open Product Questions

- Should tutorial mode also be available from Help/About or Options?
- Should users be able to reset tutorial progress?
- Should the app offer a separate sandbox/sample document for learning?
- How much regex detail should import rule tutorial expose initially?
