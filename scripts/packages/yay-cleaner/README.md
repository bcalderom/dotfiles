# yay-cleaner

## Purpose

Clean local package/cache artifacts related to Yay/Arch package maintenance.

## Usage

```bash
yay-cleaner
```

## Configuration

`XDG_STATE_HOME` controls where the log file is written. The default is
`$HOME/.local/state`, so logs normally go to
`$HOME/.local/state/yay-cleaner.log`.

```bash
XDG_STATE_HOME="$HOME/.local/state" yay-cleaner
```

## Tests

```bash
bash tests/test-yay-cleaner.sh
```
