# secret-gate

Keep agent configuration in git without leaking credentials.

Agent setups accumulate secrets in many places: `.env` files, OAuth token JSON, MCP tokens,
config fields someone pasted a key into. Pattern scanners catch tokens that *look* like tokens;
they miss a plain 32-character password. `leakcheck.py` closes that gap by checking for the
**actual values** you have.

| Gate | What it catches |
|---|---|
| Export allowlist + masking (bring your own) | Only listed files enter the repo; `api_key:`, `token:`, `password:` fields become `<REDACTED>` |
| `leakcheck.py` | Any real value from your `.env` / auth / token files, anywhere in the tree |
| `gitleaks dir` / `gitleaks git` | Known token formats in the tree and in the commit history |

If any gate fails, `sync.sh` stops before pushing and sends an alert.

```bash
# one-off check of any directory
python3 leakcheck.py ./my-repo --source ~/.config/rclone/rclone.conf

# full pipeline, nightly via systemd timer or cron
REPO=~/hermes-setup NOTIFY_CMD=~/bin/notify.sh ./sync.sh
```

**Test it with a real secret before trusting it:** copy one line of your `.env` into the tree and
confirm `leakcheck.py` exits 1 and names the key. Then delete the file.

Requires Python 3.9+ and [gitleaks](https://github.com/gitleaks/gitleaks) 8.19+ (`gitleaks dir`).
