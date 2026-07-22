# ssf

Interactive SSH launcher and transfer helper for hosts defined in
`~/.ssh/config`.

## Usage

```bash
ssf
ssf --config ~/.ssh/config
ssf --collapsed
```

The host selector provides these main actions:

```text
Enter    Connect with ssh
Ctrl-S   Transfer with scp
Ctrl-R   Transfer with rsync
Ctrl-T   Open the connection in a tmux window
```

## Transfers

Both transfer actions first use `fzf` to choose upload or download.

For an upload, `ssf` opens a local file browser. Select one or more source
files or directories, then enter the remote destination as an absolute path or
as a path relative to the remote home directory.

For a download, enter the remote source path first. `ssf` then opens the local
browser to select one destination directory. Remote paths are not browsed.

Browser keys:

```text
Enter       Open the highlighted directory or accept a file
Tab         Mark or unmark multiple upload sources
Ctrl-A      Accept marked entries, including directories
Backspace   Move to the parent directory
Esc         Cancel the transfer
```

When an upload source is a directory, rsync asks whether to copy the directory
itself or only its contents. The latter preserves rsync's trailing-slash
semantics by adding `/` to that source.

## Dependencies

Normal use requires `ssh` and `fzf`. The corresponding transfer action also
requires `scp` or rsync 3.x. rsync transfers use `--protect-args` so paths with
spaces remain separate arguments.

## Tests

```bash
bash tests/test-ssf.sh
bash tests/test-transfer.sh
bash ../../tests/test-script-structure.sh
```
