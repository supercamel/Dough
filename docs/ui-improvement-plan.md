# Dough GTK4 UI Improvement Plan

## Goal

Move Dough away from the old utility-window model and into a cohesive GTK4 workspace. The application should feel like one budgeting tool with persistent navigation, not a collection of separate pop-up windows.

## Current Problems

- Major features open as separate top-level windows: Accounts, Transactions, Import, Budget, Reports, Envelopes, Graphs, and Options.
- Editors and choosers use the same window mechanism as major features, so short tasks compete with full app sections.
- Navigation context is lost whenever another window opens.
- Repeated windows make refresh behavior fragile because each view owns its own copy of lists and controls.
- Destructive or heavy actions can feel too casual when they appear in disconnected windows.

## UX Direction

Use a single `Gtk.ApplicationWindow` as the app shell.

- Persistent header bar for global actions such as About and Quit.
- Persistent navigation strip for app sections.
- Central content area backed by one page host.
- Major features render as pages inside the main window.
- Short-lived editors and choosers render as centered overlay cards.
- Native GTK dialogs remain appropriate for OS-level or app-level dialogs such as file pickers and About.

## Page Model

The first migration keeps the existing view-building functions but changes where they present content.

Major pages:

- Dashboard
- Accounts
- Transactions
- Import
- Budget
- Budget Report
- Envelopes
- Line Graphs
- Pie Charts
- Options

Each page should be displayed in the central workspace. Clicking navigation should replace the current page instead of creating another top-level window.

## Overlay Model

Use an in-window overlay for task-focused surfaces:

- Add/Edit Transaction
- Transaction Splits
- Choose Budget Envelope

The overlay should contain:

- dimmed scrim
- centered card
- title row
- close button
- scrollable content area
- constrained card width/height

Future dialog candidates:

- import rule editor
- account editor
- envelope editor
- destructive confirmations

## Implementation Phases

### Phase 1: Shell Foundation

- Add app-level fields for the main content host and overlay host.
- Replace the dashboard-owned toolbar with a persistent navigation strip.
- Build a single root with:
  - navigation
  - page content area
  - status bar
  - overlay layer
- Add helpers:
  - `navigate_to(title, child)`
  - `show_page(title, child)`
  - `show_overlay(title, child, width, height)`
  - `close_overlay()`

### Phase 2: Major Page Migration

- Convert `show_window()` so major views render inside the page host.
- Route Accounts, Transactions, Import, Budget, Reports, Envelopes, Graphs, and Options through the page host.
- Keep About as a real `Gtk.AboutDialog`.
- Keep file selection as `Gtk.FileChooserNative`.

### Phase 3: Modal Task Migration

- Convert transaction add/edit from a window to the overlay card.
- Convert transaction splits from a window to the overlay card.
- Convert budget envelope chooser from a window to the overlay card.
- Ensure Save/Use actions close the overlay and refresh their parent page.

### Phase 4: Visual Polish

- Add CSS classes for the shell, navigation buttons, content area, overlay scrim, and overlay card.
- Improve spacing and minimum sizes so pages scan better.
- Keep buttons and controls predictable, compact, and suitable for repeated finance workflows.

### Phase 5: Later Refactors

- Split pages into modules once the presentation model stabilizes.
- Move overlay dialog building into a small reusable class/module.
- Replace list-row inline editors with side inspectors where it improves workflow.
- Add confirmation overlays for deleting accounts, envelopes, folders, budgets, and transactions.
- Add keyboard handling for Escape-to-close overlays.

## Acceptance Criteria

- Clicking major navigation entries does not open new top-level windows.
- The app retains one main window during normal workflows.
- Transaction editing works in an in-app overlay.
- Transaction splits work in an in-app overlay.
- Budget envelope choosing works in an in-app overlay.
- Status bar and document title continue to update.
- `sqgipkg --doctor` passes.
- A focused GTK runtime probe can construct and close the new shell/overlay widgets.

## Execution Status

Implemented in the first UI migration pass:

- Persistent single-window shell.
- Persistent top navigation.
- Central page host for the major app sections.
- `show_window()` now routes major views into the app workspace.
- Dashboard no longer owns the feature toolbar.
- Add/Edit Transaction uses an overlay card.
- Transaction Splits uses an overlay card.
- Choose Budget Envelope uses an overlay card.
- Overlay CSS for scrim, card, and dialog header.
- Scrollable navigation for smaller windows.
- Active navigation state for the current page.
- Escape-to-close support for overlays.
- Confirmation overlays for account delete, transaction delete, import rule reset/delete, budget clear/remove, folder delete, and envelope delete.

Remaining follow-up work:

- Split large page builders into dedicated modules.
- Add optional outside-click handling for overlays where it cannot discard unsaved edits.
- Add nested or inline confirmation for transaction split delete.
- Evaluate side inspectors for high-frequency edit flows.
