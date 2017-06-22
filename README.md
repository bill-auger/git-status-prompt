### git-status-prompt.sh - pretty format git sync and dirty status for shell prompt

![git-status-prompt screenshot][scrot]

```
FORMAT:
  (branch-name status-indicators [divergence]) last-commit-date last-commit-message
    where:
      '*' character indicates that the working tree differs from HEAD (per .gitignore)
      '!' character indicates that some tracked files have changed
      '?' character indicates that some new or untracked files exist
      '+' character indicates that some changes are staged for commit
      '$' character indicates that a stash exists
      [n<-->n] indicates the number of commits behind and ahead of upstream

USAGE:
  # ~/.bashrc
  source /path/to/git-status-prompt/git-status-prompt.sh
  PS1="\$(GitStatusPrompt)"
```


[scrot]:  http://bill-auger.github.io/git-status-prompt-scrot.png "git-status-prompt screenshot"
