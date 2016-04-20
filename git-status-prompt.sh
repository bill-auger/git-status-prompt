#!/bin/bash

# git-status-prompt.sh
# Copyright 2013-2016 http://github.com/bill-auger

# this script formats git branch name plus dirty and sync status for appending to bash prompt
# format is: (branch-name status-indicators [divergence]) last-commit-message
#   '*' character indicates that the working tree differs from HEAD
#   '!' character indicates that some tracked files have changed
#   '?' character indicates that some new or untracked files exist
#   '+' character indicates that some changes are staged for commit
#   '$' character indicates that a stash exists
#   [n<-->n] indicates the number of commits behind and ahead of upstream
# usage:
#   source ~/bin/git-status-prompt/git-status-prompt.sh
#   PS1="\$(GitStatusPrompt)"


readonly PROMPT_HEAD='\033[01;32m'$USER@$HOSTNAME'\033[00m:\033[01;36m'
readonly PROMPT_MID='\033[00m\033[00;32m'
readonly PROMPT_TAIL='\033[00m\n$ '
readonly DIRTY_CHAR="*"
readonly TRACKED_CHAR="!"
readonly UNTRACKED_CHAR="?"
readonly STAGED_CHAR="+"
readonly STASHED_CHAR="$"
readonly GIT_CLEAN_MSG_REGEX="nothing to commit,? (?working directory clean)?"
readonly GREEN='\033[0;32m'
readonly LIME='\033[1;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[1;31m'
readonly END='\033[0m'
readonly CLEAN_COLOR=$GREEN
readonly DIRTY_COLOR=$YELLOW
readonly TRACKED_COLOR=$YELLOW
readonly UNTRACKED_COLOR=$RED
readonly STAGED_COLOR=$GREEN
readonly STASHED_COLOR=$LIME
readonly BEHIND_COLOR=$RED
readonly AHEAD_COLOR=$YELLOW
readonly EVEN_COLOR=$GREEN
readonly ANSI_FILTER_REGEX="s/\\\033\[([0-9]{1,2}(;[0-9]{1,2})?)?m//g"
readonly TIMESTAMP_LEN=10


# helpers

function AssertIsValidRepo
{
  git rev-parse --is-inside-work-tree > /dev/null 2>&1 && echo "OK"
}

function AssertHasCommits
{
  # TODO: does this fail if detached HEAD ?
  git cat-file -t HEAD > /dev/null 2>&1 && echo "OK"
}

function HasAnyChanges
{
  [ "`git status 2> /dev/null | tail -n1 | grep -E \"$GIT_CLEAN_MSG_REGEX\"`" ] || echo "$DIRTY_CHAR"
}

function HasTrackedChanges
{
  git diff --no-ext-diff --quiet --exit-code || echo "$TRACKED_CHAR"
}

function HasUntrackedChanges
{
  [ -n "$(git ls-files --others --exclude-standard)" ] && echo "$UNTRACKED_CHAR"
}

function HasStagedChanges
{
  git diff-index --cached --quiet HEAD -- || echo "$STAGED_CHAR"
}

function HasStashedChanges
{
  git rev-parse --verify refs/stash > /dev/null 2>&1 && echo "$STASHED_CHAR"
}

function SyncStatus
{
  local_branch=$1 ; remote_branch=$2 ;
  status=`git rev-list --left-right ${local_branch}...${remote_branch} -- 2>/dev/null`
  [ $(($?)) -eq 0 ] && echo $status
}

function GitStatus
{
  # ensure we are in a valid git repository with commits
  [ ! $(AssertIsValidRepo) ]                        && return
  [ ! $(AssertHasCommits)  ] && echo "(no commits)" && return

  current_branch=`git rev-parse --abbrev-ref HEAD` ; [ $current_branch ] || return ;

  # loop over all branches
  while read local_branch remote_branch
  do
    # filter branches by name
    [ "$current_branch" != "$local_branch" ] && continue

    # set branch color based on dirty status
    if [ -z "$(HasAnyChanges)" ] ; then branch_color=$CLEAN_COLOR ; else branch_color=$DIRTY_COLOR ; fi ;

    # get sync status
    if [ $remote_branch ] ; then
      status=$(SyncStatus $local_branch $remote_branch)
      n_behind=`echo "$status" | tr " " "\n" | grep -c '^>'`
      n_ahead=` echo "$status" | tr " " "\n" | grep -c '^<'`

      # set sync color
      if [ "$n_behind" -ne 0 ] ; then behind_color=$BEHIND_COLOR ; else behind_color=$EVEN_COLOR ; fi ;
      if [ "$n_ahead"  -ne 0 ] ; then ahead_color=$AHEAD_COLOR ;   else ahead_color=$EVEN_COLOR ;  fi ;
    fi

    # get tracked status
    tracked=$(HasTrackedChanges)

    # get untracked status
    untracked=$(HasUntrackedChanges)

    # get staged status
    staged=$(HasStagedChanges)

    # get stashed status
    stashed=$(HasStashedChanges)

    # build output
    current_dir="$(pwd)"
    open_paren="$branch_color($END"
    close_paren="$branch_color)$END"
    open_bracket="$branch_color[$END"
    close_bracket="$branch_color]$END"
    tracked_msg=$TRACKED_COLOR$tracked$END
    untracked_msg=$UNTRACKED_COLOR$untracked$END
    staged_msg=$STAGED_COLOR$staged$END
    stashed_msg=$STASHED_COLOR$stashed$END
    branch_msg=$branch_color$current_branch$END
    status_msg=$stashed_msg$untracked_msg$tracked_msg$staged_msg
    [ $remote_branch ] && behind_msg="$behind_color$n_behind<-$END"
    [ $remote_branch ] && ahead_msg="$ahead_color->$n_ahead$END"
    [ $remote_branch ] && upstream_msg=$open_bracket$behind_msg$ahead_msg$close_bracket
    branch_status_msg=$open_paren$branch_msg$status_msg$upstream_msg$close_paren

    # append last commit message trunctuated to console width
    status_msg=$(echo $branch_status_msg | sed -r $ANSI_FILTER_REGEX --)
    author_date=$(git log -n 1 --format=format:"%ai" $1 2> /dev/null)
    commit_log=$( git log -n 1 --format=format:\"%s\" | sed -r "s/\"//g")
    commit_msg=" ${author_date:0:TIMESTAMP_LEN} $commit_log"
    current_tty_w=$(($(stty -F /dev/tty size | cut -d ' ' -f2)))
    prompt_msg_len=$((${#USER} + 1 + ${#HOSTNAME} + 1 + ${#current_dir} + 1 + ${#status_msg}))
    prompt_msg_mod=$(($prompt_msg_len % $current_tty_w))
    commit_msg_len=$(($current_tty_w - $prompt_msg_mod))
    min_len=$(($TIMESTAMP_LEN + 1))
    max_len=$(($current_tty_w - 1))
    [ $commit_msg_len -lt $min_len -o $commit_msg_len -gt $max_len ] && commit_msg_len=0
    commit_msg=${commit_msg:0:commit_msg_len}

    echo "$branch_status_msg$commit_msg"

  done < <(git for-each-ref --format="%(refname:short) %(upstream:short)" refs/heads)
}


# main entry point

function GitStatusPrompt
{
  echo -e "$PROMPT_HEAD$(pwd)/$PROMPT_MID$(GitStatus)$PROMPT_TAIL"
}
