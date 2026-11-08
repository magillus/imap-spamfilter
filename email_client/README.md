# IMAP Spam Triage & AI Training Email Client

A desktop Flutter email client purpose-built to work side-by-side with `imap-spam-filter`.

## Features

- **Three-Column Layout**:
  - **Left**: `Inbox`
  - **Center**: `AI-Spam` (Default triage focus)
  - **Right**: `Spam` (Server Spam / Junk)
- **Fast Triaging with Arrow Keys & Delete**:
  - `↑` / `↓`: Navigate up and down between emails in the active column.
  - `←` (Left Arrow):
    - When in **AI-Spam**: Moves the email to **Inbox**, marks as Ham/Not Spam, and adds the sender to `approved.json`.
    - When in **Spam**: Moves the email to **Inbox**.
  - `→` (Right Arrow):
    - When in **AI-Spam**: Moves the email to **Spam**, updates `classified.json`, and increments repeat offender signals in `spam_profile.json`.
    - When in **Inbox**: Moves the email to **Spam**.
  - `Delete` / `Backspace` (or Trash icon):
    - Moves the selected email out of the current folder (Spam / AI-Spam / Inbox) directly to **Trash** (`INBOX.Trash`).
  - `1`, `2`, `3`: Switch active column focus to Inbox (`1`), AI-Spam (`2`), or Spam (`3`).
  - `Enter` / `Space`: Open full email inspection (headers, AI classification breakdown, message body, and action buttons).
  - `R`: Refresh the current column; `Shift + R`: Refresh all columns.
- **Recheck Column with Retrained Profile**:
  - Right next to the Refresh button in each column header is the **Recheck** button (`Icons.rule_folder_outlined`).
  - Evaluates all emails in the group/column against the freshest retrained spam profile (`spam_profile.json`) and whitelist (`approved.json`).
  - Detects repeat spam senders, repeat spam domains, spam display names, and common spam subject tokens.
  - Opens the **Recheck Results** dialog with real-time stats and one-click batch actions:
    - In **Inbox**: Move detected spam profile matches directly to **AI-Spam** or **Spam**.
    - In **AI-Spam**: Move newly approved emails to **Inbox**, or confirmed repeat offenders to **Spam**.
    - In **Spam**: Move newly approved emails to **Inbox**.
- **Cataloging & Batch Spam Move**:
  - When moving an email to Spam (via `→` or button), if there are other emails in the source folder from the same sender or with the same subject title (normalized by stripping `Re:`, `Fwd:`, etc.), a cataloging popup dialog appears:
    - `↑` / `↓` arrows: switch between subsets (e.g. *By Sender: email@domain.com*, *By Subject: "Title"*, or *Combined*).
    - `Enter`: preselected **"Move All (N emails)"** to move the entire matching subset to Spam and train the filter.
    - `→` (Right Arrow): **"Move Single"** (only move the current email to Spam).
    - `Esc` / `←`: cancel without moving.
- **Smart Batched Retraining (No Queue Overload)**:
  - Local state updates (`classified.json`, `approved.json`, repeat offender memory) happen **instantaneously** upon moving emails.
  - The heavy background `imap-spam-filter learn` command is **debounced and batched**:
    - During active triaging, calls are batched to avoid queuing long-running IMAP learn tasks or locking the database.
    - An automatic background retrain fires once after **45 seconds of inactivity** or when reaching **25 batched changes**.
    - The bottom status bar shows the live count of batched changes (e.g. `[5 Batched]`), and a highlighted `Retrain (N)` button is available to flush and run immediately whenever desired.
- **Accounts & Credential Integration**:
  - Automatically discovers accounts in `~/.config/imap-spam-filter/accounts/*.conf`.
  - Seamlessly decrypts passwords using `systemd-creds` without needing plain text storage.
  - Supports switching accounts or entering custom manual connection details.
- **Pagination**:
  - Shows top 100 newest emails per column by default (sorted with newest on top).
  - "Load more (+100)" button at the bottom of each column with remaining message count indicator.

## Running the App

```bash
# From workspace root:
./run-gui.sh

# Or via imap-spam-filter CLI:
./imap-spam-filter gui

# Or directly in email_client:
cd email_client
flutter run -d linux
```
