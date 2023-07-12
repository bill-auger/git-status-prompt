#!/bin/bash

# git-status-prompt.sh - pretty format git sync and dirty status for shell prompt
# Copyright 2013-2020, 2022-2023 bill-auger <http://github.com/bill-auger/git-status-prompt/issues>
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
CFG_IGNORED_DIRS=( $(grep -v ^# "$(dirname ${BASH_SOURCE})/ignore_dirs" 2> /dev/null) )


readonly GBS_TS_FILE=~/.GSP_TS
readonly RED='\033[1;31m'
readonly YELLOW='\033[01;33m'
readonly GREEN='\033[00;32m'
readonly LIME='\033[01;32m'
readonly PURPLE='\033[00;35m'
readonly BLUE='\033[00;34m'
readonly AQUA='\033[00;36m'
readonly CYAN='\033[01;36m'
readonly CEND='\033[00m'
readonly DIRTY_CHAR="*"
readonly TRACKED_CHAR="!"
readonly UNTRACKED_CHAR="?"
readonly STAGED_CHAR="+"
readonly STASHED_CHAR="$"
readonly GIT_CLEAN_MSG_REGEX="nothing to commit, working directory clean"
readonly ROOT_COLOR=${RED}
readonly USER_COLOR=${PURPLE}
readonly PWD_COLOR=${AQUA}
readonly CLEAN_COLOR=${GREEN}
readonly DIRTY_COLOR=${YELLOW}
readonly UNO_COLOR=${LIME}
readonly TRACKED_COLOR=${YELLOW}
readonly UNTRACKED_COLOR=${RED}
readonly STAGED_COLOR=${GREEN}
readonly STASHED_COLOR=${LIME}
readonly BEHIND_COLOR=${RED}
readonly AHEAD_COLOR=${YELLOW}
readonly EVEN_COLOR=${GREEN}
readonly DATE_COLOR=${BLUE}
readonly LOGIN=$(whoami)
readonly ANSI_FILTER_REGEX="s|\\\033\[([0-9]{1,2}(;[0-9]{1,2})?)?m||g"
readonly TIMESTAMP_LEN=10


## debugging ##

Dbg() { (>&2 echo -e "[GitStatusPrompt]: $@") ; }

DbgTruncateToWidth()
{
  Dbg "(login_host_len=${#1}) + (current_dir_len=${#2}) + (status_msg_len=${#3}) = (prompt_len=$prompt_len)"
  Dbg "(current_tty_w=$current_tty_w) - (prompt_mod=$prompt_mod) = (truncate_len=$truncate_len)"
  Dbg "(min_len=$min_len) < (truncate_len=$truncate_len) < (max_len=$max_len)"
  Dbg 123456789_123456789_123456789_123456789_123456789_123456789_123456789_123456789_123456789_123456789_....
}

DbgGitStatusAssertions()
{
  Dbg "AssertIsValidRepo=$(    AssertIsValidRepo     && echo 'true' || echo 'false - bailing')"
  Dbg "AssertIsNotBareRepo=$(  AssertIsNotBareRepo   && echo 'true' || echo 'false - bailing')"
  Dbg "AssertHasCommits=$(     AssertHasCommits      && echo 'true' || echo 'false - bailing')"
  Dbg "AssertIsNotIgnoredDir=$(AssertIsNotIgnoredDir && echo 'true' || echo 'false'          )"
}

DbgGitStatusState()
{
  Dbg "current_branch=${current_branch}"
  Dbg "git_dir=${git_dir}"
  Dbg "is_valid_git_dir=$(       [[ -n "${git_dir}"        ]]    && echo 'true' || echo 'false - bailing')"
  Dbg "is_valid_current_branch=$([[ -n "${current_branch}" ]]    && echo 'true' || echo 'false - bailing')"
  Dbg "is_unsafe=$(              [[ -n "${unsafe_msg}"     ]]    && echo 'true' || echo 'false'          )"
  Dbg "is_detached=$(            [[ -n "${detached_msg}"   ]]    && echo 'true' || echo 'false'          )"
  Dbg "is_local_branch=$(        IsLocalBranch ${current_branch} && echo 'true' || echo 'false - bailing')"
}

DbgGitStatusChars()
{
  Dbg "tracked=$tracked untracked=$untracked staged=$staged stashed=$stashed\n"
}

DbgGitStatusPrompt()
{
  Dbg "login_host=${login_host} pwd_path=${pwd_path} git_status=${git_status} prompt_tail=${prompt_tail}"
}

DbgSourced() { Dbg "sourced" ; }


## helpers ##

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
  [[ -n "$(git cat-file -t HEAD 2> /dev/null)" ]]
}

AssertIsNotIgnoredDir()
{
  local ignored_dir

  for  ignored_dir in ${CFG_IGNORED_DIRS[@]} ${GSP_IGNORED_DIRS[@]}
  do   [[ "$(pwd)/" =~ ^${ignored_dir} ]] && return 1
  done

  return 0
}

GitDir() { echo "$(git rev-parse --show-toplevel 2> /dev/null)/.git" ; }

CurrentBranch() { git rev-parse --abbrev-ref HEAD 2> /dev/null ; }

UnsafeMsg()
{
  local git_status="$(git status 2>&1 1>/dev/null | sed '/^$/d')"
  local my_advice="\nor, simply white-list them all:\n\tgit config --global --add safe.directory *"

  [[ "${git_status}" =~ ^'fatal: unsafe repository ' ]] && echo -e "${git_status}${my_advice}"
}

DetachedMsg() # (git_dir current_branch)
{
  local git_dir=$1
  local current_branch=$2

  [[ -n "${git_dir}" && -n "${current_branch}" ]] || return

  if   [[ -f "${git_dir}/MERGE_HEAD" && ! -z "$(cat ${git_dir}/MERGE_MSG | grep -E '^Merge')" ]]
  then local merge_msg=$(cat ${git_dir}/MERGE_MSG | grep -E "^Merge (.*)(branch|tag|commit) '"                            | \
                         sed -e "s/^Merge \(.*\)\(branch\|tag\|commit\) '\(.*\)' \(of .* \)\?\(into .*\)\?$/\1\2 \3 \4\5/")

       echo "${UNTRACKED_COLOR}$(TruncateToWidth "" "(merging ${merge_msg})")${CEND}"

  elif [[ -d "${git_dir}/rebase-apply/" || -d "${git_dir}/rebase-merge/" ]]
  then local rebase_dir=$(  ls -d ${git_dir}/rebase-* | sed -e "s|^\$\(git_dir\)/rebase-\(.*\)$|\$\(git_dir\)/rebase-\1|")
       local this_branch=$( cat ${rebase_dir}/head-name | sed -e "s|^refs/heads/\(.*\)$|\1|" )
       local their_commit=$(cat ${rebase_dir}/onto                                             )
       local at_commit=$(   git log -n1 --oneline $(cat ${rebase_dir}/stopped-sha 2> /dev/null))
       local msg="(rebasing ${this_branch} onto ${their_commit::7} - at ${at_commit})"

       echo "${UNTRACKED_COLOR}$(TruncateToWidth "" "${msg}" )${CEND}"

  elif [[ "${current_branch}" == "HEAD" ]]
  then echo "${UNTRACKED_COLOR}$(TruncateToWidth "" "(detached)")${CEND}"
  fi
}

IsLocalBranch() # (branch_name)
{
  local branch=$1

  [[ -n "$(git branch -a 2> /dev/null | grep -E "^.* $branch$")" ]]
}

HasAnyChanges()
{
  ! [[ "$(git status 2> /dev/null | tail -n1 | grep -E "${GIT_CLEAN_MSG_REGEX}")" ]]
}

HasTrackedChanges()
{
  ! git diff --no-ext-diff --quiet --exit-code
}

HasUntrackedChanges()
{
  [[ -n "$(git ls-files --others --exclude-standard 2> /dev/null)" ]]
}

HasStagedChanges()
{
  ! git diff-index --cached --quiet HEAD --
}

HasStashedChanges()
{
  git rev-parse --verify refs/stash > /dev/null 2>&1
}

AnyChanges()       { HasAnyChanges       && echo -n "${DIRTY_CHAR}"     ; }

TrackedChanges()   { HasTrackedChanges   && echo -n "${TRACKED_CHAR}"   ; }

UntrackedChanges() { HasUntrackedChanges && echo -n "${UNTRACKED_CHAR}" ; }

StagedChanges()    { HasStagedChanges    && echo -n "${STAGED_CHAR}"    ; }

StashedChanges()   { HasStashedChanges   && echo -n "${STASHED_CHAR}"   ; }

SyncStatus() # (local_branch remote_branch status)
{
  local local_branch=$1
  local remote_branch=$2
  local status=$(git rev-list --left-right ${local_branch}...${remote_branch} -- 2>/dev/null)

  [[ $(( $? )) -eq 0 ]] && echo ${status}
}

LoginColor() { (( ${EUID} )) && echo ${USER_COLOR} || echo ${ROOT_COLOR} ; }

LoginHost()
{
  [[ -z "${STY}" ]] && echo "${USER}@${HOSTNAME}${CEND}:"   || \
                       echo "[${USER}@${HOSTNAME}]${CEND}:" # GNU screen
}

CurrentDir() { local pwd="${PWD}/" ; echo "${pwd/\/\//\/}" ; }

TruncateToWidth() # (fixed_len_prefix truncate_msg)
{
  local fixed_len_prefix=$( [[ "$1" ]] && echo "$1 " )
  local truncate_msg=$2

  # trunctuate to console width
  local login_host=$( echo $(LoginHost)          | sed -r ${ANSI_FILTER_REGEX} --)
  local current_dir=$(CurrentDir                                          )
  local status_msg=$( echo "${fixed_len_prefix}" | sed -r ${ANSI_FILTER_REGEX} --)
  local current_tty_w=$(( $(stty -F /dev/tty size | cut -d ' ' -f2)         ))
  local prompt_len=$((    ${#login_host} + ${#current_dir} + ${#status_msg} ))
  local prompt_mod=$((    ${prompt_len} % ${current_tty_w}                  ))
  local truncate_len=$((  ${current_tty_w} - ${prompt_mod}                  ))
  local min_len=${TIMESTAMP_LEN}
  local max_len=${current_tty_w}
  [[ ${truncate_len} -lt ${min_len} || ${truncate_len} -gt ${max_len} ]] && truncate_len=0

# DbgTruncateToWidth

  echo "${truncate_msg:0:truncate_len}"
}


## business ##

GitStatus()
{
# DbgGitStatusAssertions

  # get current state
  local unsafe_msg="$(   UnsafeMsg                                   )"
  local git_dir="$(      GitDir                                      )"
  local current_branch=$(CurrentBranch                               )
  local detached_msg="$( DetachedMsg "${git_dir}" "${current_branch}")"

# DbgGitStatusState

  # validate current state
  [[ -z "${unsafe_msg}"                        ]] || ! echo "${unsafe_msg}" >&2 || return
  [[ -n "${git_dir}" && -n "${current_branch}" ]]                               || return
  [[ -z "${detached_msg}"                      ]] || ! echo "${detached_msg}"   || return
  IsLocalBranch ${current_branch}                                               || return

  # ensure we are in a valid, non-bare git repository, with commits, and not blacklisted
  AssertIsValidRepo                                                             || return
  AssertIsNotBareRepo   || ! echo "$(TruncateToWidth "" "(bare repo)"        )" || return
  AssertHasCommits      || ! echo "$(TruncateToWidth "" "(no commits)"       )" || return
  AssertIsNotIgnoredDir || ! echo "$(TruncateToWidth "" "(${current_branch})")" || return

  # get remote tracking branch
  local local_branch
  local remote_branch
  local should_count_divergences
  while read local_branch remote_branch
  do    [[ "${current_branch}" == "${local_branch}" ]]                              && \
        should_count_divergences=$([[ -n "${remote_branch}" ]] && echo 1 || echo 0) && \
        break
  done < <(git for-each-ref --format="%(refname:short) %(upstream:short)" refs/heads)

  # set branch color based on dirty status
  local branch_color=$( ( HasTrackedChanges && echo -n ${DIRTY_COLOR} ) ||
                        ( HasAnyChanges     && echo -n ${UNO_COLOR}   ) ||
                                               echo -n ${CLEAN_COLOR}    )

  # get sync status
  if   (( ${should_count_divergences} ))
  then local status=$(       SyncStatus ${current_branch} ${remote_branch}                           )
       local n_behind=$(     echo "${status}" | tr " " "\n" | grep -c '^>'                           )
       local n_ahead=$(      echo "${status}" | tr " " "\n" | grep -c '^<'                           )
       local behind_color=$( [[ "${n_behind}" -ne 0 ]] && echo ${BEHIND_COLOR} || echo ${EVEN_COLOR} )
       local ahead_color=$(  [[ "${n_ahead}"  -ne 0 ]] && echo ${AHEAD_COLOR}  || echo ${EVEN_COLOR} )
  fi

  # get tracked status
  local tracked=$(TrackedChanges)

  # get untracked status
  local untracked=$(UntrackedChanges)

  # get staged status
  local staged=$(StagedChanges)

  # get stashed status
  local stashed=$(StashedChanges)

# DbgGitStatusChars

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
  if   (( ${should_count_divergences} ))
  then local behind_msg="${behind_color}${n_behind}<-${CEND}"
       local ahead_msg="${ahead_color}->${n_ahead}${CEND}"
       local upstream_msg="${open_bracket}${behind_msg}${ahead_msg}${close_bracket}"
  fi
  local branch_status_msg="${open_paren}${branch_msg}${status_msg}${upstream_msg}${close_paren}"

  # append last commit message
  local author_date=$(git log --max-count=1 --format=format:"%ai" 2> /dev/null       )
  local commit_log=$( git log --max-count=1 --format=format:\"%s\" | sed -r "s|\"||g")
  [[ -n "${commit_log}" ]] || commit_log='<EMPTY>'
  local commit_msg="${author_date:0:TIMESTAMP_LEN} ${commit_log}"
  commit_msg="$(TruncateToWidth "${branch_status_msg}" "${commit_msg}")"
  commit_msg="${DATE_COLOR}${commit_msg:0:TIMESTAMP_LEN}${CEND} ${commit_msg:(TIMESTAMP_LEN + 1)}"

  echo "${branch_status_msg} ${commit_msg}"
}


## main entry ##

GitStatusPrompt()
{
  local status=$?
  local exit_color="$( (( ! status )) && echo "${GREEN}" || echo "${RED}" )"
  local date_time="$(date +'%Y-%m-%d %T')"
  local ts=$(date +%s --date="${date_time}")
  local last_ts=$(cat "${GBS_TS_FILE}" 2> /dev/null)
  printf "${ts}" > "${GBS_TS_FILE}" # TODO: better way to store this?
  declare -i elapsed_t=$(( ts - last_ts ))
  declare -i elapsed_h=$((  elapsed_t / 3600       ))
  declare -i elapsed_m=$(( (elapsed_t / 60) % 3600 ))
  declare -i elapsed_s=$((  elapsed_t % 60         ))
  local elapsed="${elapsed_m}m ${elapsed_s}s"
  local login_host="$(LoginColor)$(LoginHost)${CEND}"
  local pwd_path="${PWD_COLOR}$(CurrentDir)${CEND}"
  local git_status="$(GitStatus)"
  local prompt_tail='\n$ '

# DbgGitStatusPrompt

  echo -e "${exit_color}->[${status}]${CEND} ${date_time} (${elapsed})"
  echo -e "${login_host}${pwd_path}${git_status}${prompt_tail}"
}

# DbgSourced
