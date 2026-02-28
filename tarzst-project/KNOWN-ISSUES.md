**Known Issues**

| Issue Name | Description |
|------------|-------------|
| `tarzst.sh` byte‑code output | When running `tarzst.sh` to archive files, the script prints raw byte code to the terminal. This output is visible to the user and should be suppressed or redirected to avoid cluttering the console. |
| `tarzst.sh` doesn't encrypt correctly | The GPG function in the script doesn't encrypt test-archives correctly. |