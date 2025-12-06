#!/usr/bin/env bash
# shellcheck disable=SC2155

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

create() {
    # Load configuration
    local no_issue_parsing="${GITBASH_CREATE_NO_ISSUE_PARSING:-no}"
    local issue_fallback="${GITBASH_CREATE_ISSUE_PARSING_FALLBACK:-NOISSUE}"

    # -----------------------------
    # 0. Check for help/version flag and parse options
    # -----------------------------
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
                cat << 'EOF'
Usage: create [OPTIONS] [JIRA_LINK] [TITLE...]

Create a new git branch with optional Jira issue parsing.

Options:
  -h, --help       Show this help message
  -t, --type       Show branch type selector menu (feature, bugfix, hotfix, release)
  --feature        Use 'feature/' prefix (default)
  --bugfix         Use 'bugfix/' prefix
  --hotfix         Use 'hotfix/' prefix
  --release        Use 'release/' prefix

Configuration (run 'gitbash --config'):
  - GITBASH_FEATURE_BRANCH_PREFIX: Default branch prefix (default: "feature/")
  - GITBASH_CREATE_NO_ISSUE_PARSING: Disable Jira parsing (yes/no, default: "no")
  - GITBASH_CREATE_ISSUE_PARSING_FALLBACK: Fallback when no issue (default: "NOISSUE")

Branch Types:
  feature/  - New features and enhancements
  bugfix/   - Bug fixes
  hotfix/   - Urgent production fixes
  release/  - Release preparation branches

Branch Name Patterns:

With issue parsing enabled (default):
  Pattern: <prefix>/<ISSUE>-<title>
  
  $ create PROJ-123 fix login bug
  # → feature/PROJ-123-fix-login-bug
  
  $ create fix bug
  # → feature/NOISSUE-fix-bug (uses fallback)

With issue parsing disabled (GITBASH_CREATE_NO_ISSUE_PARSING="yes"):
  Pattern: <prefix>/<title>
  
  $ create fix login bug
  # → feature/fix-login-bug

Interactive Mode:
  $ create
  # Prompts for Jira link (if parsing enabled) and title

Examples:
  create https://jira.company.com/browse/PROJ-123 make some fixes
  create PROJ-456 implement new feature
  create -t PROJ-789 some work                    # Show type menu
  create --hotfix PROJ-999 critical fix           # Use hotfix prefix

EOF
                return 0
                ;;
            -t|--type)
                show_type_menu=true
                shift
                ;;
            --feature)
                branch_type="feature/"
                shift
                ;;
            --bugfix)
                branch_type="bugfix/"
                shift
                ;;
            --hotfix)
                branch_type="hotfix/"
                shift
                ;;
            --release)
                branch_type="release/"
                shift
                ;;
            *)
                positional_args+=("$1")
                shift
                ;;
        esac
    done

    # -----------------------------
    # 1. Determine branch prefix
    # -----------------------------
    local branch_prefix
    if [[ -n "$branch_type" ]]; then
        branch_prefix="$branch_type"
    elif [[ "$show_type_menu" == true ]]; then
        if ! command -v fzf >/dev/null 2>&1; then
            print_error "fzf is required for type selector. Install it or use --feature/--bugfix/--hotfix/--release flags."
            return 1
        fi

        local type_options
        type_options=$(cat << 'TYPES'
feature/ - New features and enhancements
bugfix/  - Bug fixes  
hotfix/  - Urgent production fixes
release/ - Release preparation branches
TYPES
)

        local selected_type
        selected_type=$(echo "$type_options" | fzf --prompt="Branch type > " \
                  -i \
                  --reverse \
                  --border \
                  --header="Select branch type" \
                  --no-multi \
                  --bind=enter:accept \
        ) </dev/tty || true

        if [[ -z "$selected_type" ]]; then
            echo "Aborted."
            return 1
        fi

        # Extract just the prefix (first word)
        branch_prefix=$(echo "$selected_type" | awk '{print $1}')
    else
        branch_prefix="${GITBASH_FEATURE_BRANCH_PREFIX:-feature/}"
    fi

    # -----------------------------
    # 2. Get Jira link from user (or from arguments) - skip if parsing disabled
    # -----------------------------
    local jira_link
    local branch_title
    
    if [[ "$no_issue_parsing" == "yes" ]]; then
        # Issue parsing disabled - treat all args as branch title
        if [[ ${#positional_args[@]} -gt 0 ]]; then
            if [[ -n "${ZSH_VERSION:-}" ]]; then
                branch_title="${positional_args[*]}"
            else
                branch_title="${positional_args[*]}"
            fi
        fi
        jira_link=""
    elif [[ ${#positional_args[@]} -gt 0 ]]; then
        # Arguments provided - use one-liner mode
        # Use array index 1 for zsh compatibility (zsh arrays are 1-indexed, bash uses 0)
        if [[ -n "${ZSH_VERSION:-}" ]]; then
            jira_link="${positional_args[1]}"
            if [[ ${#positional_args[@]} -gt 1 ]]; then
                branch_title="${positional_args[*]:1}"
            else
                branch_title=""
            fi
        else
            jira_link="${positional_args[0]}"
            if [[ ${#positional_args[@]} -gt 1 ]]; then
                branch_title="${positional_args[*]:1}"
            else
                branch_title=""
            fi
        fi
    else
        # Interactive mode
        if [[ "$no_issue_parsing" == "yes" ]]; then
            # Skip Jira link prompt when parsing is disabled
            jira_link=""
        else
            echo "Enter Jira link (e.g., https://jira.company.com/browse/PROJ-123) or press Enter to skip:"
            prompt_read " > " jira_link
        fi
    fi

    # -----------------------------
    # 2. Parse issue number from Jira link
    # -----------------------------
    local issue_number
    
    if [[ "$no_issue_parsing" == "yes" ]]; then
        # Issue parsing disabled - no issue number in branch name
        issue_number=""
    elif [[ -z "$jira_link" ]]; then
        # No Jira link provided, use configured fallback
        issue_number="$issue_fallback"
        print_info "No Jira link provided. Using $issue_fallback."
    else
        # First try to match just the issue number pattern (e.g., PROJ-123)
        issue_number=$(echo "$jira_link" | grep -o -E '^[A-Z]+-[0-9]+$' | head -1 || true)
        
        # If not a direct match, try to extract from URL
        if [[ -z "$issue_number" ]]; then
            # Match patterns like PROJ-123, ABC-456, etc.
            # Supports both /browse/PROJ-123 and selectedIssue=PROJ-123 formats
            issue_number=$(echo "$jira_link" | grep -o -E '(browse/|selectedIssue=)[A-Z]+-[0-9]+' | grep -o '[A-Z]\+-[0-9]\+' | head -1 || true)
        fi

        if [[ -z "$issue_number" ]]; then
            print_warning "Could not parse issue number from Jira link. Using $issue_fallback."
            issue_number="$issue_fallback"
            # If parsing failed and we had arguments, include the first arg in the title
            if [[ -n "$branch_title" ]]; then
                branch_title="$jira_link $branch_title"
            else
                branch_title="$jira_link"
            fi
        else
            echo "Parsed issue number: $issue_number"
        fi
    fi

    # -----------------------------
    # 3. Get branch title from user (if not already provided)
    # -----------------------------
    if [[ -z "$branch_title" ]]; then
        echo "Enter branch title (will be converted to lowercase with dashes):"
        prompt_read " > " branch_title
    fi

    if [[ -z "$branch_title" ]]; then
        echo "Error: No branch title provided."
        return 1
    fi

    # Convert title to lowercase and replace spaces/special chars with dashes
    branch_title=$(echo "$branch_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

    # -----------------------------
    # 4. Construct branch name
    # -----------------------------
    # branch_prefix is set earlier from type menu, flag, or config
    local branch_name
    if [[ -n "$issue_number" ]]; then
        branch_name="${branch_prefix}${issue_number}-${branch_title}"
    else
        branch_name="${branch_prefix}${branch_title}"
    fi
    
    echo "Branch name: $branch_name"

    # -----------------------------
    # 5. Check if branch already exists
    # -----------------------------
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        print_warning "Branch '$branch_name' already exists locally."
        prompt_read "Switch to this branch instead? (Y/n): " ans
        case "$ans" in
            [nN][oO]|[nN])
                echo "Aborted."
                return 1
                ;;
            *)
                git checkout "$branch_name"
                print_success "Switched to existing branch: $branch_name"
                return 0
                ;;
        esac
    fi

    # -----------------------------
    # 6. Update main/master branch before creating new branch
    # -----------------------------
    # Detect base branch: main or master
    local base_branch
    if git show-ref --verify --quiet refs/heads/main; then
        base_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        base_branch="master"
    else
        print_warning "Could not detect 'main' or 'master' branch. Creating branch from current HEAD."
        base_branch=""
    fi

    if [[ -n "$base_branch" ]]; then
        print_info "Updating '$base_branch' from origin..."
        if git fetch origin "$base_branch:$base_branch" 2>/dev/null; then
            print_success "'$base_branch' is up to date."
        else
            print_warning "Could not update '$base_branch' from origin. Creating branch from local '$base_branch'."
        fi
    fi

    # -----------------------------
    # 7. Create branch
    # -----------------------------
    print_info "Creating branch..."
    if [[ -n "$base_branch" ]]; then
        # Create branch from updated base branch
        if git checkout -b "$branch_name" "$base_branch"; then
            print_success "Successfully created and switched to branch: $branch_name (from $base_branch)"
        else
            print_error "Failed to create branch."
            return 1
        fi
    else
        # Fallback: create from current HEAD
        if git checkout -b "$branch_name"; then
            print_success "Successfully created and switched to branch: $branch_name"
        else
            print_error "Failed to create branch."
            return 1
        fi
    fi

    # -----------------------------
    # 8. Push branch to origin and set up tracking
    # -----------------------------
    print_info "Pushing branch to origin and setting up tracking..."
    if git push -u origin "$branch_name"; then
        print_success "Successfully pushed '$branch_name' to origin with tracking."
    else
        print_warning "Failed to push branch to origin. You can push it later with: git push -u origin $branch_name"
    fi
}
