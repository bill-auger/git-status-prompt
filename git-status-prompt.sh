#!/bin/bash

# git-status-prompt.sh - pretty format git sync and dirty status for shell prompt
# Copyright 2013-2019 bill-auger <http://github.com/bill-auger/git-status-prompt/issues>
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
declare -r -a IGNORED_DIRS=( $(grep -v ^# "$(dirname ${BASH_SOURCE})/ignore_dirs" 2> /dev/null) )

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
readonly CLEAN_COLOR=${GREEN}
readonly DIRTY_COLOR=${YELLOW}
readonly TRACKED_COLOR=${YELLOW}
readonly UNTRACKED_COLOR=${RED}
readonly STAGED_COLOR=${GREEN}
readonly STASHED_COLOR=${LIME}
readonly BEHIND_COLOR=${RED}
readonly AHEAD_COLOR=${YELLOW}
readonly EVEN_COLOR=${GREEN}
readonly ROOT_COLOR=${RED}
readonly USER_COLOR=${PURPLE}
readonly LOGIN=$(whoami)
readonly ANSI_FILTER_REGEX="s/\\\033\[([0-9]{1,2}(;[0-9]{1,2})?)?m//g"
readonly TIMESTAMP_LEN=10


# helpers

AssertIsNotIgnoredDir()
{
  local ignored_dir

  for  ignored_dir in ${IGNORED_DIRS[*]}
  do   [[ "$(pwd)" =~ ^${ignored_dir} ]] && return 1
  done

  return 0
}

AssertIsValidRepo()
{
  [[ "$(git rev-parse --is-inside-work-tree 2> /dev/null)" == 'true' ]] || \
  [[ "$(git rev-parse --is-bare-repository  2> /dev/null)" == 'true' ]]
}

AssertIsNotBareRepo()
{
  [[ "$(git rev-parse --is-bare-repository 2> /dev/null)" != 'true' ]]
}

AssertHasCommits()
{
  # TODO: does this fail if detached HEAD ?
  [[ "$(git cat-file -t HEAD 2> /dev/null)" ]]
}

HasAnyChanges()
{
  [ "$(git status 2> /dev/null | tail -n1 | grep -E "${GIT_CLEAN_MSG_REGEX}")" ] || echo "${DIRTY_CHAR}"
}

HasTrackedChanges()
{
  git diff --no-ext-diff --quiet --exit-code || echo "${TRACKED_CHAR}"
}

HasUntrackedChanges()
{
  [ -n "$(git ls-files --others --exclude-standard)" ] && echo "${UNTRACKED_CHAR}"
}

HasStagedChanges()
{
  git diff-index --cached --quiet HEAD -- || echo "${STAGED_CHAR}"
}

HasStashedChanges()
{
  git rev-parse --verify refs/stash > /dev/null 2>&1 && echo "${STASHED_CHAR}"
}

SyncStatus()
{
  local local_branch=$1
  local remote_branch=$2
  local status=$(git rev-list --left-right ${local_branch}...${remote_branch} -- 2>/dev/null)

  [ $(( $? )) -eq 0 ] && echo ${status}
}

LoginColor() { (( ${EUID} )) && echo ${USER_COLOR} || echo ${ROOT_COLOR} ; }

LoginHost()
{
  [ -z "${STY}" ] && echo "${USER}@${HOSTNAME}${CEND}:"   || \
                     echo "[${USER}@${HOSTNAME}]${CEND}:" # GNU screen
}

CurrentDir() { local pwd="${PWD}/" ; echo "${pwd/\/\//\/}" ; }

TruncateToWidth()
{
  local fixed_len_msg=$1
  local truncate_msg=$2

  # trunctuate to console width
  local login_host=$( echo $(LoginHost)   | sed -r ${ANSI_FILTER_REGEX} --)
  local current_dir=$(CurrentDir                                          )
  local status_msg=$( echo $fixed_len_msg | sed -r ${ANSI_FILTER_REGEX} --)
  local current_tty_w=$(( $(stty -F /dev/tty size | cut -d ' ' -f2)         ))
  local prompt_len=$((    ${#login_host} + ${#current_dir} + ${#status_msg} ))
  local prompt_mod=$((    ${prompt_len} % ${current_tty_w}                  ))
  local truncate_len=$((  ${current_tty_w} - ${prompt_mod}                  ))
  local min_len=$(( ${TIMESTAMP_LEN} + 1 ))
  local max_len=$(( ${current_tty_w} - 1 ))
  [ ${truncate_len} -lt ${min_len} -o ${truncate_len} -gt ${max_len} ] && truncate_len=0
  local truncate_msg=${truncate_msg:0:truncate_len}

# (>&2 echo "(login_host=${#login_host}) + (current_dir=${#current_dir}) + (status_msg=${#status_msg}) = (prompt_len=$prompt_len)")
# (>&2 echo "(current_tty_w=$current_tty_w) - (prompt_mod=$prompt_mod) = (truncate_len=$truncate_len)")
# (>&2 echo 123456789_123456789_123456789_123456789_123456789_123456789_123456789_123456789_123456789_123456789_....)

  echo "${fixed_len_msg}${truncate_msg}"
}

GitStatus()
{
# (>&2 echo "AssertIsValidRepo=$(    AssertIsValidRepo     && echo 'true' || echo 'false - bailing')")
# (>&2 echo "AssertIsNotBareRepo=$(  AssertIsNotBareRepo   && echo 'true' || echo 'false - bailing')")
# (>&2 echo "AssertHasCommits=$(     AssertHasCommits      && echo 'true' || echo 'false - bailing')")
# (>&2 echo "AssertIsNotIgnoredDir=$(AssertIsNotIgnoredDir && echo 'true' || echo 'false - bailing')")

  # ensure we are in a valid, non-bare git repository, with commits, and not blacklisted
  ! AssertIsValidRepo                                                  && return
  ! AssertIsNotBareRepo   && echo $(TruncateToWidth "" "(bare repo)" ) && return
  ! AssertHasCommits      && echo $(TruncateToWidth "" "(no commits)") && return
  ! AssertIsNotIgnoredDir && echo $(TruncateToWidth "" "(heavy-git)" ) && return

  # get the current state
  local git_dir=$(       git rev-parse --show-toplevel  )/.git ; [ "${git_dir}"        ] || return ;
  local current_branch=$(git rev-parse --abbrev-ref HEAD)      ; [ "${current_branch}" ] || return ;

  # detect detached HEAD state and abort
  if   [ -f "${git_dir}/MERGE_HEAD" ] && [ ! -z "$(cat ${git_dir}/MERGE_MSG | grep -E '^Merge')" ]
  then local merge_msg=$(cat ${git_dir}/MERGE_MSG | grep -E "^Merge (.*)(branch|tag|commit) '"                             | \
                         sed -e "s/^Merge \(.*\)\(branch\|tag\|commit\) '\(.*\)' \(of .* \)\?\(into .*\)\?$/\1 \2 \3 \4\5/")

       echo ${UNTRACKED_COLOR}$(TruncateToWidth "" "(merging $merge_msg)")${CEND} ; return ;

  elif [ -d "${git_dir}/rebase-apply/" ] || [ -d "${git_dir}/rebase-merge/" ]
  then local rebase_dir=$(  ls -d ${git_dir}/rebase-* | sed -e "s/^\$\(git_dir\)\/rebase-\(.*\)$/\$\(git_dir\)\/rebase-\1/")
       local this_branch=$( cat ${rebase_dir}/head-name | sed -e "s/^refs\/heads\/\(.*\)$/\1/" )
       local their_commit=$(cat ${rebase_dir}/onto                                             )
       local at_commit=$(   git log -n1 --oneline $(cat ${rebase_dir}/stopped-sha 2> /dev/null))
       local msg="(rebasing ${this_branch} onto ${their_commit::7} - at ${at_commit})"

       echo ${UNTRACKED_COLOR}$(TruncateToWidth "" "${msg}" )${CEND} ; return ;

  elif [ "${current_branch}" == "HEAD" ]
  then echo ${UNTRACKED_COLOR}$(TruncateToWidth "" "(detached)")${CEND} ; return ;
  fi

  # loop over all branches to find remote tracking branch
  local local_branch
  local remote_branch
  while read local_branch remote_branch
  do
    # filter branches by name
    [ "${current_branch}" != "${local_branch}" ] && continue

    # set branch color based on dirty status
    local branch_color=$([ -z "$(HasAnyChanges)" ] && echo ${CLEAN_COLOR} || echo ${DIRTY_COLOR})

    # get sync status
    if [ ${remote_branch} ] ; then
      local status=$(SyncStatus ${local_branch} ${remote_branch})
      local n_behind=$(echo "${status}" | tr " " "\n" | grep -c '^>')
      local n_ahead=$( echo "${status}" | tr " " "\n" | grep -c '^<')

      # set sync color
      local behind_color=$([ "$n_behind" -ne 0 ] && echo ${BEHIND_COLOR} || echo ${EVEN_COLOR})
      local ahead_color=$( [ "$n_ahead"  -ne 0 ] && echo ${AHEAD_COLOR}  || echo ${EVEN_COLOR})
    fi

    # get tracked status
    local tracked=$(HasTrackedChanges)

    # get untracked status
    local untracked=$(HasUntrackedChanges)

    # get staged status
    local staged=$(HasStagedChanges)

    # get stashed status
    local stashed=$(HasStashedChanges)

    # build output
    local open_paren="${branch_color}(${CEND}"
    local close_paren="${branch_color})${CEND}"
    local open_bracket="${branch_color}[${CEND}"
    local close_bracket="${branch_color}]${CEND}"
    local tracked_msg=${TRACKED_COLOR}${tracked}${CEND}
    local untracked_msg=${UNTRACKED_COLOR}${untracked}${CEND}
    local staged_msg=${STAGED_COLOR}${staged}${CEND}
    local stashed_msg=${STASHED_COLOR}${stashed}${CEND}
    local branch_msg=${branch_color}${current_branch}${CEND}
    local status_msg=${stashed_msg}${untracked_msg}${tracked_msg}${staged_msg}
    local behind_msg=$(  [ $remote_branch ] && echo "${behind_color}${n_behind}<-${CEND}"                     )
    local ahead_msg=$(   [ $remote_branch ] && echo "${ahead_color}->${n_ahead}${CEND}"                       )
    local upstream_msg=$([ $remote_branch ] && echo "${open_bracket}${behind_msg}${ahead_msg}${close_bracket}")
    local branch_status_msg="${open_paren}${branch_msg}${status_msg}${upstream_msg}${close_paren}"

    # append last commit message
    local author_date=$(git log --max-count=1 --format=format:"%ai" 2> /dev/null       )
    local commit_log=$( git log --max-count=1 --format=format:\"%s\" | sed -r "s/\"//g")
    [ "${commit_log}" ] || commit_log='<EMPTY>'
    local commit_msg=" ${author_date:0:TIMESTAMP_LEN} ${commit_log}"

    echo $(TruncateToWidth "${branch_status_msg}" "${commit_msg}")

  done < <(git for-each-ref --format="%(refname:short) %(upstream:short)" refs/heads)
}


# main entry point

GitStatusPrompt()
{
  local login_host="$(LoginColor)$(LoginHost)${CEND}"
  local pwd_path="${BLUE}$(CurrentDir)${CEND}"
  local git_status="${GREEN}$(GitStatus)${CEND}"
  local prompt_tail='\n$ '

  echo -e "${login_host}${pwd_path}${git_status}${prompt_tail}"
}
