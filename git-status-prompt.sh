#!/bin/bash

# git-status-prompt.sh - pretty format git sync and dirty status for shell prompt
# Copyright 2013-2017 bill-auger <http://github.com/bill-auger/git-status-prompt/issues>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


# FORMAT:
#   (branch-name status-indicators [divergence]) last-commit-date last-commit-message
#     where:
#       '*' character indicates that the working tree differs from HEAD (per .gitignore)
#       '!' character indicates that some tracked files have changed
#       '?' character indicates that some new or untracked files exist
#       '+' character indicates that some changes are staged for commit
#       '$' character indicates that a stash exists
#       [n<-->n] indicates the number of commits behind and ahead of upstream
#
# USAGE:
#   source /path/to/git-status-prompt/git-status-prompt.sh
#   PS1="\$(GitStatusPrompt)"


# this script can be sluggish in very large repos
declare -r -a IGNORED_DIRS=( $(grep -v ^# ignore_dirs 2> /dev/null) )


readonly RED='\033[1;31m'
readonly YELLOW='\033[01;33m'
readonly GREEN='\033[00;32m'
readonly LIME='\033[01;32m'
readonly PURPLE='\033[00;35m'
readonly BLUE='\033[00;36m'
readonly AQUA='\033[01;36m'
readonly CEND='\033[00m'
readonly DIRTY_CHAR="*"
readonly TRACKED_CHAR="!"
readonly UNTRACKED_CHAR="?"
readonly STAGED_CHAR="+"
readonly STASHED_CHAR="$"
readonly GIT_CLEAN_MSG_REGEX="nothing to commit,? (?working directory clean)?"
readonly CLEAN_COLOR=$GREEN
readonly DIRTY_COLOR=$YELLOW
readonly TRACKED_COLOR=$YELLOW
readonly UNTRACKED_COLOR=$RED
readonly STAGED_COLOR=$GREEN
readonly STASHED_COLOR=$LIME
readonly BEHIND_COLOR=$RED
readonly AHEAD_COLOR=$YELLOW
readonly EVEN_COLOR=$GREEN
readonly ROOT_COLOR=$RED
readonly USER_COLOR=$PURPLE
readonly LOGIN=$(whoami)
readonly ANSI_FILTER_REGEX="s/\\\033\[([0-9]{1,2}(;[0-9]{1,2})?)?m//g"
readonly TIMESTAMP_LEN=10


# helpers

function AssertIsNotIgnoredDir
{
  local ignored_dir

  for  ignored_dir in ${IGNORED_DIRS[*]}
  do   [[ "$(pwd)" =~ ^${ignored_dir} ]] && echo 0
  done

  echo 1
}

function AssertIsValidRepo
{
  [ "`git rev-parse --is-inside-work-tree 2> /dev/null`" == 'true' ] || \
  ! (($(AssertIsNotBareRepo)))                                       && echo 1 || echo 0
}

function AssertHasCommits
{
  # TODO: does this fail if detached HEAD ?
  [ "`git cat-file -t HEAD 2> /dev/null`" ] && echo 1 || echo 0
}

function AssertIsNotBareRepo
{
  [ "`git rev-parse --is-bare-repository 2> /dev/null`" != 'true' ] && echo 1 || echo 0
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

function LoginColor { (( $EUID )) && echo $USER_COLOR || echo $ROOT_COLOR ; }

function LoginHost
{
  [ -z "$STY" ] && echo "${USER}@${HOSTNAME}${CEND}:"   || \
                   echo "[${USER}@${HOSTNAME}]${CEND}:" # GNU screen
}

function CurrentDir { local pwd="${PWD}/" ; echo "${pwd/\/\//\/}" ; }

function GitStatus
{
  # ensure we are in a valid, non-bare git repository, with commits, and not blacklisted
  ! (($(AssertIsValidRepo    )))                                              && return
  ! (($(AssertIsNotBareRepo  ))) && echo $(TruncateToWidth "" "(bare repo)" ) && return
  ! (($(AssertHasCommits     ))) && echo $(TruncateToWidth "" "(no commits)") && return
  ! (($(AssertIsNotIgnoredDir))) && echo $(TruncateToWidth "" "(heavy-git)" ) && return

  # get the current state
  git_dir=`git rev-parse --show-toplevel`/.git     ; [ "$git_dir"        ] || return ;
  current_branch=`git rev-parse --abbrev-ref HEAD` ; [ "$current_branch" ] || return ;

  # detect detached HEAD state and abort
  if   [ -f "$git_dir/MERGE_HEAD" ] && [ ! -z "`cat $git_dir/MERGE_MSG | grep -E '^Merge'`" ]
  then merge_msg=`cat $git_dir/MERGE_MSG | grep -E "^Merge (.*)(branch|tag|commit) '"                                   | \
                  sed -e "s/^Merge \(.*\)\(branch\|tag\|commit\) '\(.*\)' \(of .* \)\?\(into .*\)\?$/\1 \2 \3 \4\5/"`

       echo $UNTRACKED_COLOR$(TruncateToWidth "" "(merging $merge_msg)")$CEND ; return ;

  elif [ -d "$git_dir/rebase-apply/" ] || [ -d "$git_dir/rebase-merge/" ]
  then rebase_dir=`ls -d $git_dir/rebase-* | sed -e "s/^\$\(git_dir\)\/rebase-\(.*\)$/\$\(git_dir\)\/rebase-\1/"`
       this_branch=`cat $rebase_dir/head-name | sed -e "s/^refs\/heads\/\(.*\)$/\1/"`
       their_commit=`cat $rebase_dir/onto`
       at_commit=`git log -n1 --oneline $(cat $rebase_dir/stopped-sha 2> /dev/null)`
       msg="(rebasing $this_branch onto ${their_commit::7} - at $at_commit)"

       echo $UNTRACKED_COLOR$(TruncateToWidth "" "$msg" )$CEND ; return ;

  elif [ "$current_branch" == "HEAD" ]
  then echo $UNTRACKED_COLOR$(TruncateToWidth "" "(detached)")$CEND ; return ;
  fi

  # loop over all branches to find remote tracking branch
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
    open_paren="$branch_color($CEND"
    close_paren="$branch_color)$CEND"
    open_bracket="$branch_color[$CEND"
    close_bracket="$branch_color]$CEND"
    tracked_msg=$TRACKED_COLOR$tracked$CEND
    untracked_msg=$UNTRACKED_COLOR$untracked$CEND
    staged_msg=$STAGED_COLOR$staged$CEND
    stashed_msg=$STASHED_COLOR$stashed$CEND
    branch_msg=$branch_color$current_branch$CEND
    status_msg=$stashed_msg$untracked_msg$tracked_msg$staged_msg
    [ $remote_branch ] && behind_msg="$behind_color$n_behind<-$CEND"
    [ $remote_branch ] && ahead_msg="$ahead_color->$n_ahead$CEND"
    [ $remote_branch ] && upstream_msg=$open_bracket$behind_msg$ahead_msg$close_bracket
    branch_status_msg=$open_paren$branch_msg$status_msg$upstream_msg$close_paren

    # append last commit message
    author_date=$(git log -n 1 --format=format:"%ai" $1 2> /dev/null)
    commit_log=$( git log -n 1 --format=format:\"%s\" | sed -r "s/\"//g")
    [ "$commit_log" ] || commit_log='<EMPTY>'

    echo $(TruncateToWidth "$branch_status_msg" " ${author_date:0:TIMESTAMP_LEN} $commit_log")

  done < <(git for-each-ref --format="%(refname:short) %(upstream:short)" refs/heads)
}

function TruncateToWidth
{
  branch_status_msg=$1
  commit_msg=$2

  # trunctuate to console width
  login_host=$(LoginHost | sed -r $ANSI_FILTER_REGEX --)
  current_dir=$(CurrentDir)
  status_msg=$(echo $branch_status_msg | sed -r $ANSI_FILTER_REGEX --)
  current_tty_w=$(($(stty -F /dev/tty size | cut -d ' ' -f2)))
  prompt_msg_len=$((${#login_host} + 1 + ${#current_dir} + 1 + ${#status_msg}))
  prompt_msg_mod=$(($prompt_msg_len % $current_tty_w))
  commit_msg_len=$(($current_tty_w - $prompt_msg_mod))
  min_len=$(($TIMESTAMP_LEN + 1))
  max_len=$(($current_tty_w - 1))
  [ $commit_msg_len -lt $min_len -o $commit_msg_len -gt $max_len ] && commit_msg_len=0

  echo "$branch_status_msg${commit_msg:0:commit_msg_len}"
}


# main entry point

function GitStatusPrompt
{
  login_host="$(LoginColor)$(LoginHost)${CEND}"
  pwd_path="${BLUE}$(CurrentDir)${CEND}"
  git_status="${GREEN}$(GitStatus)${CEND}"
  prompt_tail='\n$ '

  echo -e "$login_host $pwd_path$git_status$prompt_tail"
}
