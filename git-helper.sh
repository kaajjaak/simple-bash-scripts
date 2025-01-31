#! /bin/bash
#
# git-helper.sh - a script to help with common git tasks and best practices.
#
# author: JAAK DAEMEN <jaak.daemen@student.hogent.be>

#------------------------------------------------------------------------------
# Shell settings
#------------------------------------------------------------------------------
set -o errexit    # Exit immediately if a command exits with non-zero status
set -o nounset    # Treat unset variables as an error
set -o pipefail   # Ensure pipelines fail on first non-zero status code
#------------------------------------------------------------------------------
# Variables
#------------------------------------------------------------------------------
REQUIRED_FILES=("README.md" ".gitignore" ".gitattributes")
UNSUPPORTED_FILES=("application/vnd.ms-excel" "application/msword" "application/vnd.openxmlformats-officedocument.wordprocessingml.document" "application/pdf" "application/x-iso9660-image" "application/x-executable")
REMOTE="origin"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
#------------------------------------------------------------------------------
# Main function
#------------------------------------------------------------------------------

# Usage: main "${@}"
#  Check command line arguments (using a case statement) and call the
#  appropriate function that implements the functionality.
main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  case $1 in
    check)
      check_basic_settings
      if [[ $# -ge 2 ]]; then
        check_repo "$2"
      fi
      ;;
    log) show_history ;;
    stats) stats ;;
    undo) undo_last_commit ;;
    sync) sync ;;
    help|--help|-h) usage ;;
    *) echo -e "${RED}Error: Unknown command${NC}" >&2; exit 1 ;;
  esac
}
#------------------------------------------------------------------------------
# Helper functions
#------------------------------------------------------------------------------
# If you notice that you are writing the same code in multiple places, don't
# hesitate to add functions to make your code more DRY!

# Usage: is_git_repo DIR
#  Predicate that checks if the specified DIR contains a Git repository.
#  This function does not produce output, but only returns the appropriate
#  exit code.
is_git_repo() {
  git -C "$1" rev-parse --is-inside-work-tree &>/dev/null
}

# Usage: check_basic_settings
#  Check if the basic git settings are configured
check_basic_settings() {
  local missing
  missing=()
  [[ -z $(git config user.name) ]] && missing+=("user.name")
  [[ -z $(git config user.email) ]] && missing+=("user.email")
  [[ -z $(git config push.default) ]] && missing+=("push.default")

  for setting in "${missing[@]}"; do
    echo -e "${RED}Git $setting not set. Set it using:" >&2
    echo -e "git config --global $setting \"value\"${NC}" >&2
  done
  [[ ${#missing[@]} -eq 0 ]] && echo -e "${GREEN}All basic settings configured${NC}"
}
# Usage: check_repo DIR
#  Perform some checks on the specified DIR that should contain a Git
#  repository.
check_repo() {
  local dir
  dir="${1:-.}"
  
  if ! is_git_repo "$dir"; then
    echo -e "${RED}Not a git repository: $dir${NC}" >&2
    return 1
  fi

  # Check if repository has a remote
  if [[ -z $(git -C "$dir" remote) ]]; then
    echo -e "${RED}Warning: Repository has no remote configured${NC}" >&2
  fi


  # Check required files
  for file in "${REQUIRED_FILES[@]}"; do
    [[ ! -f "$dir/$file" ]] && echo -e "${RED}Missing $file${NC}" >&2
  done

  # Check executables
  while IFS= read -r -d '' script; do
    if [[ -f "$script" && ! -x "$script" ]]; then
      printf "Script %s is not executable. Grant execute permission to file owner [y/N]? " "${script#$dir/}"
      read -r response < /dev/tty
      if [[ "$response" =~ ^[Yy]$ ]]; then
        chmod u+x "$script"
        # Change to the repository directory before git operations
        if cd "$dir"; then
          if git add "${script#$dir/}"; then
            git commit -m "Make scripts executable"
            echo -e "${GREEN}Execute permission granted.${NC}"
            echo "Committed changes to branch '$(git branch --show-current)'."
            cd - > /dev/null
          else
            echo -e "${RED}Failed to add file to git${NC}" >&2
            cd - > /dev/null
          fi
        else
          echo -e "${RED}Failed to change to repository directory${NC}" >&2
        fi
      fi
    fi
  done < <(find "$dir" -type f -name "*.sh" -print0)




  # Check unsupported files
  while IFS= read -r -d '' file; do
    mime_type=$(file --mime-type -b "$file")
    for unsupported in "${UNSUPPORTED_FILES[@]}"; do
      if [[ "$mime_type" == "$unsupported" ]]; then
        echo -e "${RED}Found unsupported file type ($mime_type): ${file#$dir/}${NC}" >&2
      fi
    done
  done < <(find "$dir" -type f -print0)


}

# Usage: show_history [DIR]
#  Show git log in the specified DIR or in the current directory if none was
#  specified.
show_history() {
  git log --pretty=format:"%s | %an | %ad" --date=short
}

# Usage: stats [DIR]
#  Show the number of commits and the number of contributors in the specified
#  DIR or in the current directory if none was specified.
stats() {
  local commits
  commits=$(git rev-list --count HEAD)
  local contributors
  contributors=$(git shortlog -s -n | wc -l)
  echo -e "${GREEN}$commits commits by $contributors contributors${NC}"
}

# Usage: undo_last_commit
#  Undo the last commit but keep local changes in the working directory.
undo_last_commit() {
  if [ $(git rev-list --count HEAD) -eq 0 ]; then
    echo -e "${RED}No commits to undo${NC}" >&2
    return 1
  fi
  
  if [ $(git rev-list --count HEAD) -eq 1 ]; then
    # For initial commit
    git update-ref -d HEAD
    echo -e "${GREEN}Undo of last commit successful${NC}"
    return 0
  fi
  
  local commit_msg
  commit_msg=$(git log -1 --pretty=%B)
  git reset --soft HEAD~1
  echo -e "${GREEN}Undo of last commit \"$commit_msg\" successful${NC}"
}



# Usage: sync
#  Sync the currently checked out branch in the local repository with the
#  remote repository by performing:
#
#  - git stash if there are local changes
#  - git pull --rebase
#  - git push
#  - git push all labels (tags)
#  - git stash pop if there were local changes
sync() {
  local changes
  changes=$(git status --porcelain)
  [[ -n "$changes" ]] && git stash
  
  git pull --rebase "$REMOTE" "$(git branch --show-current)"
  git push "$REMOTE" "$(git branch --show-current)"
  git push --tags
  
  [[ -n "$changes" ]] && git stash pop
}
# Usage: usage
#   Print usage message
usage() {
  cat <<EOF
Usage: ./git-helper.sh COMMAND [ARGUMENTS]...

check
        check basic git user configuration
check DIR
    check basic git user configuration and check DIR for
    deviations of standard git practices
log
    display a brief overview of the git log of the PWD
stats
    display some brief stats about the PWD repository
undo
    undo last commit from git working tree while preserving
    local changes.
sync
    sync local branch with remote
EOF
}

main "${@}"