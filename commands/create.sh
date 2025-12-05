#!/usr/bin/env bash
# shellcheck disable=SC2155

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

create() {
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

Create a new git branch with the pattern: <prefix>/<ISSUE>-<title>

Options:
  -h, --help       Show this help message
  -t, --type       Show branch type selector menu (feature, bugfix, hotfix, release)
  --feature        Use 'feature/' prefix (default)
  --bugfix         Use 'bugfix/' prefix
  --hotfix         Use 'hotfix/' prefix
  --release        Use 'release/' prefix

Configuration:
  - Default branch prefix can be set via GITBASH_FEATURE_BRANCH_PREFIX in ~/.gitbashrc
  - Run 'gitbash --config' to set default prefix

Branch Types:
  feature/  - New features and enhancements
  bugfix/   - Bug fixes
  hotfix/   - Urgent production fixes
  release/  - Release preparation branches

Interactive mode (no arguments):
  $ create
  Enter Jira link (e.g., https://jira.company.com/browse/PROJ-123):
  > https://jira.company.com/browse/PROJ-123
  Parsed issue number: PROJ-123

  Enter branch title (will be converted to lowercase with dashes):
  > Fix Login Bug
  
  Branch name: feature/PROJ-123-fix-login-bug
  Create this branch? (y/N): y

With type selector:
  $ create -t PROJ-123 urgent fix
  Branch type >
  > feature/ - New features and enhancements
    bugfix/  - Bug fixes
    hotfix/  - Urgent production fixes
    release/ - Release preparation branches
  
  # Select hotfix/, creates: hotfix/PROJ-123-urgent-fix

Quick type flags:
  $ create --bugfix PROJ-456 fix crash
  # Creates: bugfix/PROJ-456-fix-crash

One-liner mode (with arguments):
  $ create https://jira.company.com/browse/PROJ-123 fix login bug
  Parsed issue number: PROJ-123
  
  Branch name: feature/PROJ-123-fix-login-bug
  Create this branch? (y/N): y

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
    # 2. Get Jira link from user (or from arguments)
    # -----------------------------
    local jira_link
    local branch_title
    
    if [[ ${#positional_args[@]} -gt 0 ]]; then
        # Arguments provided - use one-liner mode
        jira_link="${positional_args[0]}"
        # Join remaining arguments as title
        if [[ ${#positional_args[@]} -gt 1 ]]; then
            branch_title="${positional_args[*]:1}"
        else
            branch_title=""
        fi
    else
        # Interactive mode
        echo "Enter Jira link (e.g., https://jira.company.com/browse/PROJ-123):"
        prompt_read " > " jira_link
    fi

    if [[ -z "$jira_link" ]]; then
        echo "Error: No Jira link provided."
        return 1
    fi

    # -----------------------------
    # 2. Parse issue number from Jira link
    # -----------------------------
    local issue_number
    # First try to match just the issue number pattern (e.g., PROJ-123)
    issue_number=$(echo "$jira_link" | grep -o -E '^[A-Z]+-[0-9]+$' | head -1)
    
    # If not a direct match, try to extract from URL
    if [[ -z "$issue_number" ]]; then
        # Match patterns like PROJ-123, ABC-456, etc.
        # Supports both /browse/PROJ-123 and selectedIssue=PROJ-123 formats
        issue_number=$(echo "$jira_link" | grep -o -E '(browse/|selectedIssue=)[A-Z]+-[0-9]+' | grep -o '[A-Z]\+-[0-9]\+' | head -1)
    fi

    if [[ -z "$issue_number" ]]; then
        echo "Warning: Could not parse issue number from Jira link. Using NOISSUE."
        issue_number="NOISSUE"
        # If parsing failed and we had arguments, include the first arg in the title
        if [[ -n "$branch_title" ]]; then
            branch_title="$jira_link $branch_title"
        else
            branch_title="$jira_link"
        fi
    else
        echo "Parsed issue number: $issue_number"
    fi
    echo

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
    local branch_name="${branch_prefix}${issue_number}-${branch_title}"
    
    echo
    echo "Branch name: $branch_name"
    echo

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
