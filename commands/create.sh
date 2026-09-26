#!/usr/bin/env bash

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

# Turn free text into a branch-name slug: "Über Café fix!" -> "ueber-cafe-fix"
# (iconv's transliteration differs between platforms, so common letters are mapped here)
_create_slugify() {
  local map="ä:ae Ä:ae ö:oe Ö:oe ü:ue Ü:ue ß:ss à:a á:a â:a ã:a å:a À:a Á:a Â:a Ã:a Å:a
    è:e é:e ê:e ë:e È:e É:e Ê:e Ë:e ì:i í:i î:i ï:i Ì:i Í:i Î:i Ï:i
    ò:o ó:o ô:o õ:o ø:o Ò:o Ó:o Ô:o Õ:o Ø:o ù:u ú:u û:u Ù:u Ú:u Û:u ç:c Ç:c ñ:n Ñ:n"
  local script="" pair
  for pair in $map; do
    script+="s/${pair%%:*}/${pair#*:}/g;"
  done
  printf '%s' "$1" | LC_ALL=C sed "$script" |
    LC_ALL=C tr '[:upper:]' '[:lower:]' |
    LC_ALL=C sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

# Extract a Jira issue key (e.g. PROJ-123, AB2-45) from a key or URL
_create_parse_issue() {
  local input="$1" key=""
  local re_key='^([A-Za-z][A-Za-z0-9]+-[0-9]+)$'
  local re_url='(browse/|selectedIssue=)([A-Za-z][A-Za-z0-9]+-[0-9]+)'
  if [[ "$input" =~ $re_key ]]; then
    key="${BASH_REMATCH[1]}"
  elif [[ "$input" =~ $re_url ]]; then
    key="${BASH_REMATCH[2]}"
  fi
  [[ -z "$key" ]] && return 1
  printf '%s' "$key" | tr '[:lower:]' '[:upper:]'
}

create() {
  local no_issue_parsing="${GITBASH_CREATE_NO_ISSUE_PARSING:-no}"
  local issue_fallback="${GITBASH_CREATE_ISSUE_PARSING_FALLBACK:-NOISSUE}"
  local branch_prefix_config="${GITBASH_CREATE_BRANCH_PREFIX:-}"
  local auto_push="${GITBASH_CREATE_AUTO_PUSH:-yes}"

  local show_type_menu=false
  local branch_type=""
  local positional_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--version)
        echo "gitbash ${FUNCNAME[0]} v$VERSION"
        return 0
        ;;
      -h|--help)
        gb_help << 'EOF'
Usage: create [OPTIONS] [JIRA_LINK] [TITLE...]

Create a new git branch from the latest base branch, with optional Jira issue parsing.

Options:
  -h, --help       Show this help message
  -t, --type       Show branch type selector menu (feature, bugfix, hotfix, release)
  --feature        Use 'feature/' type (default)
  --bugfix         Use 'bugfix/' type
  --hotfix         Use 'hotfix/' type
  --release        Use 'release/' type
  -p, --push       Push the new branch to the remote (default: GITBASH_CREATE_AUTO_PUSH)
  --no-push        Don't push the new branch
  -y, --yes        Don't ask for confirmations (switches to an existing branch of the same name)

Configuration (run 'gitbash --config'):
  - GITBASH_CREATE_BRANCH_PREFIX: Custom prefix between type and issue (default: "")
  - GITBASH_CREATE_NO_ISSUE_PARSING: Disable Jira parsing (yes/no, default: "no")
  - GITBASH_CREATE_ISSUE_PARSING_FALLBACK: Fallback when no issue (default: "NOISSUE")
  - GITBASH_CREATE_AUTO_PUSH: Push new branches right away (yes/no, default: "yes")

Branch Name Format:
  <type><custom-prefix>/<ISSUE>-<title>  (with issue parsing)
  <type><custom-prefix>/<title>          (without issue parsing)

  Issue keys: PROJ-123, AB2-45 or a Jira URL (/browse/KEY or selectedIssue=KEY).
  Titles are lower-cased; umlauts and accents are transliterated (ü → ue, é → e) and other
  characters become dashes.

Behavior:
  - Fetches the base branch and creates the new branch from '<remote>/<base>'
    (falls back to the current HEAD if that fails)
  - If the branch already exists locally, offers to switch to it
  - If it already exists on the remote, stops (use 'switch' to check it out)

Examples:
  create PROJ-123 fix login bug             # feature/PROJ-123-fix-login-bug
  create https://jira.company.com/browse/PROJ-123 make some fixes
  create fix bug                            # feature/NOISSUE-fix-bug
  create --hotfix PROJ-999 critical fix     # hotfix/PROJ-999-critical-fix
  create -t PROJ-789 some work              # Show type menu

EOF
        return 0
        ;;
      -t|--type) show_type_menu=true; shift ;;
      --feature) branch_type="feature/"; shift ;;
      --bugfix) branch_type="bugfix/"; shift ;;
      --hotfix) branch_type="hotfix/"; shift ;;
      --release) branch_type="release/"; shift ;;
      -p|--push) auto_push="yes"; shift ;;
      -y|--yes) export GITBASH_ASSUME_YES=1; shift ;;
      --no-push) auto_push="no"; shift ;;
      --)
        shift
        positional_args+=("$@")
        break
        ;;
      -*)
        print_error "Unknown option: $1"
        return 1
        ;;
      *)
        positional_args+=("$1")
        shift
        ;;
    esac
  done

  require_git_repo || return 1

  # -----------------------------
  # 1. Branch type
  # -----------------------------
  local branch_prefix="feature/"
  if [[ -n "$branch_type" ]]; then
    branch_prefix="$branch_type"
  elif [[ "$show_type_menu" == true ]]; then
    require_fzf || return 1
    local selected_type
    selected_type=$(run_fzf --prompt="Branch type > " \
              -i \
              --reverse \
              --border \
              --header="Select branch type" \
              --no-multi \
              <<< "feature/ - New features and enhancements
bugfix/  - Bug fixes
hotfix/  - Urgent production fixes
release/ - Release preparation branches"
    ) || true
    if [[ -z "$selected_type" ]]; then
      echo "Aborted."
      return 0
    fi
    branch_prefix="${selected_type%% *}"
  fi

  # -----------------------------
  # 2. Issue number and title
  # -----------------------------
  local jira_link="" branch_title="" issue_number=""

  if [[ "$no_issue_parsing" == "yes" ]]; then
    if [[ ${#positional_args[@]} -gt 0 ]]; then
      branch_title="${positional_args[*]}"
    fi
  else
    if [[ ${#positional_args[@]} -gt 0 ]]; then
      jira_link="${positional_args[0]}"
      if [[ ${#positional_args[@]} -gt 1 ]]; then
        branch_title="${positional_args[*]:1}"
      fi
    else
      echo "Enter Jira link or issue key (e.g. PROJ-123), or press Enter to skip:"
      prompt_read " > " jira_link || true
    fi

    if [[ -z "$jira_link" ]]; then
      issue_number="$issue_fallback"
      print_info "No issue given. Using $issue_fallback."
    elif issue_number=$(_create_parse_issue "$jira_link"); then
      echo "Parsed issue number: $issue_number"
    else
      issue_number="$issue_fallback"
      print_warning "No issue key found in '$jira_link'. Using $issue_fallback."
      # The first word was part of the title
      if [[ -n "$branch_title" ]]; then
        branch_title="$jira_link $branch_title"
      else
        branch_title="$jira_link"
      fi
    fi
  fi

  if [[ -z "$branch_title" ]]; then
    echo "Enter branch title (will be converted to lowercase with dashes):"
    prompt_read " > " branch_title || true
  fi
  branch_title=$(_create_slugify "$branch_title")
  if [[ -z "$branch_title" ]]; then
    print_error "No branch title provided."
    return 1
  fi

  # -----------------------------
  # 3. Branch name
  # -----------------------------
  local custom_prefix_part="" branch_name
  if [[ -n "$branch_prefix_config" ]]; then
    custom_prefix_part="${branch_prefix_config}/"
  fi
  if [[ -n "$issue_number" ]]; then
    branch_name="${branch_prefix}${custom_prefix_part}${issue_number}-${branch_title}"
  else
    branch_name="${branch_prefix}${custom_prefix_part}${branch_title}"
  fi

  if ! git check-ref-format --branch "$branch_name" >/dev/null 2>&1; then
    print_error "'$branch_name' is not a valid branch name. Check GITBASH_CREATE_BRANCH_PREFIX and GITBASH_CREATE_ISSUE_PARSING_FALLBACK."
    return 1
  fi
  echo "Branch name: $branch_name"

  # -----------------------------
  # 4. Already exists?
  # -----------------------------
  if git show-ref --verify --quiet "refs/heads/$branch_name"; then
    print_warning "Branch '$branch_name' already exists locally."
    if gb_confirm "Switch to it instead?" y; then
      git switch "$branch_name" && print_success "Switched to existing branch: $branch_name"
      return $?
    fi
    echo "Aborted."
    return 1
  fi

  local remote
  remote=$(gb_remote)
  if git remote get-url "$remote" >/dev/null 2>&1 &&
     [[ -n "$(git ls-remote --heads "$remote" "refs/heads/$branch_name" 2>/dev/null)" ]]; then
    print_error "Branch '$branch_name' already exists on '$remote'. Use 'switch $branch_title' to check it out."
    return 1
  fi

  # -----------------------------
  # 5. Create from the latest base branch
  # -----------------------------
  local base_branch start_point=""
  if base_branch=$(gb_base_branch); then
    print_info "Fetching latest '$base_branch' from '$remote'..."
    if git fetch --quiet "$remote" "+refs/heads/$base_branch:refs/remotes/$remote/$base_branch" 2>/dev/null; then
      start_point="$remote/$base_branch"
    elif git show-ref --verify --quiet "refs/heads/$base_branch"; then
      print_warning "Could not fetch '$base_branch'. Creating the branch from local '$base_branch'."
      start_point="$base_branch"
    fi
  fi
  if [[ -z "$start_point" ]]; then
    print_warning "Could not find the base branch. Creating the branch from the current HEAD."
  fi

  print_info "Creating branch..."
  if [[ -n "$start_point" ]]; then
    git switch --quiet --no-track -c "$branch_name" "$start_point" || { print_error "Failed to create branch."; return 1; }
    print_success "Created and switched to '$branch_name' (from $start_point)"
  else
    git switch --quiet -c "$branch_name" || { print_error "Failed to create branch."; return 1; }
    print_success "Created and switched to '$branch_name'"
  fi

  # -----------------------------
  # 6. Push and set up tracking
  # -----------------------------
  if [[ "$auto_push" == "yes" ]]; then
    print_info "Pushing '$branch_name' to '$remote'..."
    if git push --quiet -u "$remote" "$branch_name"; then
      print_success "Pushed '$branch_name' to '$remote' with tracking."
    else
      print_warning "Failed to push. You can push it later with: git push -u $remote $branch_name"
    fi
  fi
  return 0
}
