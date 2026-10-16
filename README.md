# IMAP Spam Filter (local LLM)

Classifies the email in your IMAP inbox as spam or not using a **local** model: a small
`qwen3:4b` on its own Ollama instance on the NVIDIA card, or optionally
[Hermes Agent](https://github.com/NousResearch/hermes-agent).
Your mail never leaves your machine apart from the IMAP connection itself.

It learns from your own **Spam / AI-Spam** folders. Senders, domains and subject words that
keep showing up there are passed to the model as hints. It can then move spam into a folder
you choose, and an **approved list** makes sure trusted senders and subjects are never touched.

```
 SPAM 0.95   phishing
   From:    PayPaI Security <alert@secure-paypa1-verify.xyz>
   Subject: Urgent: your account is suspended
   Reason:  Lookalike domain, urgency, credential lure
   Matched: domain secure-paypa1-verify.xyz appears 7x in Spam folder
   Ref:     679dd9

 ok   0.97  Mom <mom@gmail.com>                       Dinner Sunday?
 appr  ✓    Boss <boss@work.com>                      Weekly report
```

---

## 1. Setup

### Requirements

| What | Notes |
|---|---|
| Python **3.12+** | Standard library only, nothing to `pip install` |
| [Ollama](https://ollama.com) with CUDA | Arch: `sudo pacman -S ollama-cuda`, plus a second Ollama service on port 11435 (below) |
| NVIDIA GPU | Tested on an RTX 3070. `qwen3:4b` needs about 3.5 GB of free VRAM |
| Hermes Agent *(optional)* | Only for `--backend hermes` |
| IMAP account | SSL on port 993 |

### Ollama model

The classifier talks to a second Ollama on `127.0.0.1:11435` that sees only the NVIDIA card, so
your main Ollama (`11434`) stays free for other work. On this machine that is the system unit
`/etc/systemd/system/ollama-cuda.service`: a copy of `ollama.service` with

```ini
Environment="OLLAMA_HOST=127.0.0.1:11435"
Environment="CUDA_VISIBLE_DEVICES=0"
Environment="ROCR_VISIBLE_DEVICES=-1"
Environment="HIP_VISIBLE_DEVICES=-1"
```

`install.sh` checks that it answers and pulls `qwen3:4b` into it
(`OLLAMA_HOST=127.0.0.1:11435 ollama pull qwen3:4b`).

Any instruction-following model works: `--model`, or `SPAM_FILTER_MODEL` for the services
(e.g. `SPAM_FILTER_MODEL=qwen3:8b ./install.sh`, which needs about 6 GB of free VRAM).
`SPAM_OLLAMA_URL` points `install.sh` at a different Ollama.

If your main Ollama also has CUDA, keep it off the NVIDIA card by adding
`Environment="CUDA_VISIBLE_DEVICES=-1"` to its `ollama.service` override.

### Hermes Agent *(optional)*

`--backend hermes` calls `hermes -z` (one-shot mode), which uses the model in `~/.hermes/config.yaml`:

```yaml
model:
  default: qwen3-coder:30b
  provider: custom
  base_url: http://localhost:11434/v1
```

Check that it answers:

```bash
hermes -z 'Reply with only: {"verdict":"ham","confidence":0.9}' -t todo --ignore-rules
```

### IMAP credentials

Set them as environment variables. The password is prompted for if `IMAP_PASSWORD` isn't set:

```bash
export IMAP_HOST=imap.gmail.com
export IMAP_USER=you@gmail.com
export IMAP_PASSWORD='app-password'    # optional
```

You can keep them in a file such as `~/.config/spam-filter.env` (run `chmod 600` on it) and `source` it before running.

| Provider | Host | Notes |
|---|---|---|
| Gmail | `imap.gmail.com` | Needs 2FA and an [App Password](https://myaccount.google.com/apppasswords). Your normal password won't work |
| Outlook / M365 | `outlook.office365.com` | Many tenants turn off password IMAP login |
| Fastmail | `imap.fastmail.com` | App password |
| Dovecot / cPanel | your server | Folders usually look like `INBOX.Spam` |

### Make it executable

```bash
cd ~/Work/imap-spam-filter
chmod +x spam_filter.py
./spam_filter.py --help
```

---

## 2. Quick start

```bash
# 1. Learn from your Spam (+ AI-Spam) folders
./spam_filter.py --spam-folder AI-Spam learn

# 2. Dry run: classify the 20 newest inbox emails and change nothing
./spam_filter.py classify

# 3. Approve anything wrongly flagged, using the Ref shown in the output
./spam_filter.py approve 679dd9

# 4. Run for real: move confident spam into AI-Spam
./spam_filter.py --spam-folder AI-Spam classify --move --create-folder
```

> **Global options go *before* the command:** `--host`, `--user`, `--inbox`, `--spam-folder`, `--no-color`.
> `./spam_filter.py --spam-folder AI-Spam classify --move` ✅
> `./spam_filter.py classify --spam-folder AI-Spam --move` ❌

---

## 3. Commands

### `learn`: build the spam profile

Reads the From, Subject and Reply-To headers of your spam folders and your Inbox. It finds senders,
domains, display names and subject words that are much more common in spam than in your Inbox
(smoothed log-odds), and writes `spam_profile.json`.

```bash
./spam_filter.py learn                              # server Spam/Junk folder only
./spam_filter.py --spam-folder AI-Spam learn        # Spam/Junk + AI-Spam
./spam_filter.py learn --folders Spam,AI-Spam       # list folders explicitly
./spam_filter.py learn --learn-limit 3000           # scan more history per folder (default 1000)
```

- The Spam/Junk folder is found automatically from the IMAP `\Junk` flag, or by name.
- Folder names are matched loosely, so `AI-Spam` finds `INBOX.AI-Spam` or `INBOX/AI-Spam`.
- Folders that don't exist are skipped with a warning.
- Messages matching the **approved list** are left out of the profile.
- Large free-mail domains (gmail.com, outlook.com, and so on) are never flagged by domain.

Rerun `learn` now and then (weekly is plenty) to pick up new repeat offenders.

### `classify`: check inbox messages

```bash
./spam_filter.py classify                         # 20 newest, dry run
./spam_filter.py classify --limit 50              # 50 newest
./spam_filter.py classify --unseen                # only unread
./spam_filter.py --spam-folder AI-Spam classify --move                  # move confident spam
./spam_filter.py --spam-folder AI-Spam classify --move --create-folder  # create AI-Spam if missing
./spam_filter.py classify --move --min-confidence 0.9                   # stricter threshold
./spam_filter.py classify --model qwen3:8b                              # another Ollama model
./spam_filter.py classify --backend hermes                              # use Hermes Agent instead
./spam_filter.py classify --json results.json     # also save results as JSON
./spam_filter.py classify --recheck               # ignore cache, re-check everything
```

| Option | Default | Meaning |
|---|---|---|
| `--limit N` | 20 | Check the N **newest** messages, skipping ones already checked |
| `--unseen` | off | Only unread messages |
| `--move` | off | Move spam at or above `--min-confidence` to the spam folder |
| `--min-confidence` | 0.8 | Threshold for `--move`, and for red `SPAM` vs yellow `SPAM?` |
| `--create-folder` | off | Create `--spam-folder` if it doesn't exist (with `--move`) |
| `--backend` | ollama | `ollama` (direct API) or `hermes` (Hermes Agent CLI) |
| `--model` | `qwen3:4b` | Model override. Also `SPAM_FILTER_MODEL` env. Hermes uses its own config |
| `--ollama-url` | `http://127.0.0.1:11435` | Also `OLLAMA_URL` env |
| `--timeout` | 180 | Seconds per model call |
| `--max-bytes` | 60000 | Bytes downloaded per message |
| `--body-chars` | 1500 | Body characters sent to the model |
| `--recheck` | off | Ignore `classified.json` |
| `--json FILE` | – | Write the full results to a file |

**Reading the output**

| Shown as | Meaning |
|---|---|
| ` SPAM 0.95 ` red | Spam at or above `--min-confidence`. Moved when `--move` is set |
| ` SPAM? 0.62` yellow | Probably spam, but below the threshold. **Never moved.** Check these by hand |
| ` ok   0.97` green | Not spam |
| ` appr  ✓` cyan | On the approved list. The model isn't asked |
| `Matched:` magenta | What it matched in your spam history |
| `Ref:` | Short code for `approve <ref>` |

At the end, **Spam detected** lists every spam result marked `moved`, `sure` or `check`, with its Ref.

**Safety**
- Messages are read with `BODY.PEEK`, so they are **not marked as read**.
- Nothing moves without `--move`.
- If a move fails, the server's reason is printed and the message is tried again on the next run.

### `approve`: never treat as spam

Approved messages skip the model and are never moved. The list is stored in `approved.json`.
This command doesn't need IMAP credentials.

```bash
./spam_filter.py approve 679dd9                    # Ref from classify output: sender + subject
./spam_filter.py approve 679dd9 a1b2c3             # several at once
./spam_filter.py approve 679dd9 --from-only        # sender only
./spam_filter.py approve 679dd9 --subject-only     # subject only

./spam_filter.py approve --from boss@work.com      # one address
./spam_filter.py approve --from @work.com          # whole domain, subdomains included
./spam_filter.py approve --subject "weekly report" # subject contains this text, any case

./spam_filter.py approve --list
./spam_filter.py approve --remove "weekly report"
```

| Entry | Matches |
|---|---|
| sender | Exact address, case-insensitive |
| domain | Domain and its subdomains (`work.com` matches `mail.work.com`) |
| subject | Text anywhere in the subject, ignoring case. When added from a Ref, leading `Re:`/`Fwd:` are removed |

> ⚠️ Anyone can write any subject. Prefer approving **senders**, and keep subject entries specific
> (`"Acme invoice #"`, not `"invoice"`).

Approving a message that was **already moved** doesn't move it back. Drag it back to the Inbox yourself.
Refs work only for messages checked after the approve feature was added.

---

## 4. Run as a service (multiple accounts)

`install.sh` sets the filter up as **systemd user services**, one timer per email account.
No root is needed. IMAP passwords are stored **encrypted**, never in plain text.

### Install

```bash
cd ~/Work/imap-spam-filter
./install.sh                 # also run it again after changing spam_filter.py, to update
```

It copies the program to `~/.local/share/imap-spam-filter/` and the `imap-spam-filter` command to
`~/.local/bin/`, then creates the units and pulls the model into the Ollama on port 11435. It checks for Python 3.12+,
`systemd-creds`, that Ollama is answering, and lingering. Lingering lets checks keep running when you are logged out:
`loginctl enable-linger $USER`.

### Add accounts

```bash
imap-spam-filter add personal     # prompts: email, server (guessed), spam folder, options, interval, password
imap-spam-filter add work
```

`add` **tests the login** before saving anything, then encrypts the password and starts the account's
timers. It also runs a first `learn` in the background. For your first account, it offers to copy an
existing `spam_profile.json` / `approved.json` / `classified.json` from this folder.

### Day-to-day

```bash
imap-spam-filter list                         # accounts, timer state, next check, last result
imap-spam-filter logs work -f                 # follow that account's log
imap-spam-filter classify work --limit 10     # manual dry run (colors, Refs)
imap-spam-filter approve work 679dd9          # approve a false positive (Ref from logs/output)
imap-spam-filter approve work --from @acme.com
imap-spam-filter learn work                   # rebuild the spam profile now
imap-spam-filter run work <any spam_filter.py command and options>
imap-spam-filter edit work                    # change server/folder/options (picked up on the next run)
imap-spam-filter passwd work                  # replace the stored password
imap-spam-filter pause work | resume work
imap-spam-filter remove work [--purge]        # --purge also deletes learned data
./install.sh --uninstall                      # remove everything except settings, passwords and data
```

### What runs

| Unit | When | Does |
|---|---|---|
| `imap-spam-filter@<name>.timer` | 2 min after start, then 15 min after each run ends | `classify $CLASSIFY_ARGS` |
| `imap-spam-filter-learn@<name>.timer` | Sundays 03:00 (catches up if missed) | `learn $LEARN_ARGS` |

Each account's settings live in `~/.config/imap-spam-filter/accounts/<name>.conf`:

```bash
IMAP_HOST="imap.gmail.com"
IMAP_PORT="993"
IMAP_USER="you@gmail.com"
SPAM_FOLDER="AI-Spam"
CLASSIFY_ARGS="--limit 30 --move --create-folder --min-confidence 0.8"
LEARN_ARGS="--learn-limit 1000"
```

A run and a manual `imap-spam-filter run` for the same account never overlap; they share a lock.
Each account has its own profile, cache and approved list in `~/.local/state/imap-spam-filter/<name>/`.

### How passwords are kept safe

- Encrypted with **`systemd-creds --user`** into `~/.config/imap-spam-filter/creds/<name>.cred` (mode 600).
  The key comes from the machine's **TPM2** and is tied to your user account, so the file is useless if copied
  to another machine or read by another user.
- When a check runs, systemd decrypts the password into a **private, per-run, in-memory credentials
  directory** that only that service can read. It is deleted when the run ends.
- When you run `imap-spam-filter run/classify` by hand, the password goes to the script through a
  **pipe** (`/dev/fd/N`). It is never put in the environment, on a command line, in the logs, or on disk.
- When you type it, the password is hidden. The login is tested before it is stored.
- Settings, credentials and data folders are `700`, and files are created with `umask 077`.

> If the TPM is reset, or you move to a new machine, the old `.cred` files can't be decrypted.
> Run `imap-spam-filter passwd <name>` for each account.

### Without systemd (cron)

The script also reads the password from `IMAP_PASSWORD_FILE`, so you can use any secret store. For example:

```bash
#!/usr/bin/env bash
# e.g. ~/bin/spam-check, run from cron. The password comes from the GNOME keyring through a pipe.
IMAP_PASSWORD_FILE=<(secret-tool lookup service imap account work) \
  ~/Work/imap-spam-filter/spam_filter.py --no-color classify --move
```

## 5. How it works

```
             learn                                   classify
 ┌──────────────────────────┐        ┌────────────────────────────────────────┐
 │ Spam + AI-Spam headers   │        │ Inbox message (headers + body snippet) │
 │        vs Inbox headers  │        └───────────────┬────────────────────────┘
 └────────────┬─────────────┘                        │
              ▼                          on approved list? ── yes ─▶ ham (no model call)
     spam_profile.json  ───── hints ───────▶  │ no
   (senders, domains,                         ▼
    names, subject words)        prompt ─▶ Ollama / Hermes ─▶ {"verdict","confidence",...}
                                                              │
                                                --move & conf ≥ threshold ─▶ spam folder
```

**Prompt-injection protection.** Email content is untrusted. The Ollama backend gives the model no tools
at all. With `--backend hermes`, `hermes -z` auto-approves tool calls, so the script runs Hermes with only the harmless `todo` toolset (no terminal, files, browser or web),
plus `--ignore-rules`, from an empty temp directory. The prompt marks the email as data, not instructions.

---

## 6. Files

| File | Purpose | Safe to delete? |
|---|---|---|
| `spam_filter.py` | The script | – |
| `spam_profile.json` | Learned spam patterns | Yes, recreated by `learn` |
| `classified.json` | Cache of checked Message-IDs and their verdicts | Yes, everything gets re-checked |
| `approved.json` | Your approved list (you can edit it by hand) | ⚠️ You lose your approvals |
| `install.sh` | Installs/updates the services. `--uninstall` removes them | – |
| `imap-spam-filter` | Account manager (installed to `~/.local/bin`) | – |

When the program is **installed as a service**, each account's data files live in
`~/.local/state/imap-spam-filter/<name>/` instead of next to the script (`SPAM_FILTER_DATA_DIR`).

---

## 7. Tips and caveats

- **Clean AI-Spam before `learn`.** AI-Spam holds the model's own decisions, so real mail left there
  teaches the profile that its sender is spam. Move it back and `approve` it first.
- **`--limit` takes the newest N.** If those N were all checked before, the run does nothing.
  To go further back, raise `--limit` (cached messages are skipped, but still downloaded).
- Start with dry runs and a high `--min-confidence` before letting it move mail on its own.
- Bigger models are more accurate but slower and need more VRAM. qwen3's "thinking" mode is turned off
  for speed.

---

## 8. Troubleshooting

| Problem | Fix |
|---|---|
| `failed to move uid … : NO [TRYCREATE]` | The folder doesn't exist. Create it or add `--create-folder` |
| `Folder 'X' not found on server. Folders: …` | Use a name from the list, or `--create-folder` with `--move` |
| `Folder 'X' is ambiguous` | Pass the full name, e.g. `--spam-folder INBOX.AI-Spam` |
| `Could not find a Spam/Junk folder` | Pass `--spam-folder` (or `learn --folders`) |
| `LOGIN failed` / `AUTHENTICATIONFAILED` | Use an app password; check IMAP is enabled for the account |
| `Ollama is not answering on …:11435` | `systemctl status ollama-cuda`, then `journalctl -u ollama-cuda` |
| `Model 'qwen3:4b' is not pulled` | Rerun `./install.sh`, or run the `ollama pull` it prints |
| Slow, or `ollama ps` shows CPU | Run `OLLAMA_HOST=127.0.0.1:11435 ollama ps`. Check `ollama-cuda` is installed, or free VRAM on the NVIDIA card. Another model loaded on 11435 also pushes it out |
| `hermes exited …` / timeouts | Check `ollama ps`, or raise `--timeout` |
| `no verdict JSON in model output` | The model didn't return JSON. Try another `--model` |
| `Unknown ref` | The message was checked before Refs were added. Use `--from` / `--subject` |
| Escape codes like `^[[31m` in logs | Add `--no-color` or set `NO_COLOR=1` |
| `imap-spam-filter list` shows `failed` | `imap-spam-filter logs <name>`. Usually Ollama is down, or the password changed (`passwd`) |
| `Failed to decrypt` / credential errors | The TPM was reset or the machine changed. Run `imap-spam-filter passwd <name>` |
| No checks while logged out | `loginctl enable-linger $USER` |
| Running nothing new | Everything in `--limit` is cached. Raise `--limit` or use `--recheck` |
