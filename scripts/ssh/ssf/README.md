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
Enter       Accept the highlighted entry
Tab         Mark or unmark multiple upload sources
Ctrl-A      Accept marked entries, including directories
Ctrl-D      Open the highlighted directory
Ctrl-U      Move to the parent directory
Esc         Cancel the transfer
```

When an upload source is a directory, rsync asks whether to copy the directory
itself or only its contents. The latter preserves rsync's trailing-slash
semantics by adding `/` to that source.

## Session naming

Inside tmux, the current window is renamed before connecting:
`ssh-<alias>` for ssh, `scp-<alias>` / `rsync-<alias>` for transfers. The
tmux session is renamed as well, but only when its current name already
follows the ssf pattern (`ssh-*`, `scp-*`, `rsync-*`), so shared sessions
are never renamed. A numeric suffix is added when the target session name
is already taken.

## After a transfer

When an scp/rsync transfer finishes (or fails), a menu offers the next
step:

```text
ssh     Connect to the host with ssh
again   Run another transfer with the same tool
menu    Back to the ssf main menu
quit    Close this session
```

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
