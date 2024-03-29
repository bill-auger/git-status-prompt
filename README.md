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

  # this script can be sluggish in repos with a large number of commits
  # such directories may be listed in a file named 'ignore_dirs' to avoid processing
```


[scrot]: data/git-status-prompt-scrot.png "git-status-prompt screenshot"
