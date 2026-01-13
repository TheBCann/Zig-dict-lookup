#!/bin/bash

# Configuration
STD_LIB="$HOME/.zig/lib/std"
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ==========================================
#  HELP MENU
# ==========================================
function show_help() {
  echo -e "${BLUE}${BOLD}zfn${NC} - Zig Standard Library Explorer"
  echo -e "A CLI tool to fuzzy-find, list, and extract functions and tests from the Zig std lib."
  echo
  echo -e "${BOLD}USAGE:${NC}"
  echo -e "  zfn [flags] [file] [filter]"
  echo
  echo -e "${BOLD}ARGUMENTS:${NC}"
  echo -e "  ${BOLD}file${NC}      The standard library file (e.g., 'array_list' or 'net')."
  echo -e "            If omitted, opens an interactive fuzzy finder (fzf)."
  echo -e "  ${BOLD}filter${NC}    The name of the function or test to extract."
  echo -e "            If provided, prints the full code block (Extract Mode)."
  echo -e "            If omitted, lists one-line signatures (List Mode)."
  echo
  echo -e "${BOLD}FLAGS:${NC}"
  echo -e "  ${BOLD}-t${NC}        Test Mode. Search for 'test' blocks instead of 'fn'."
  echo -e "  ${BOLD}-f${NC}        Full Mode. Force printing full code blocks even without a filter."
  echo -e "  ${BOLD}-h, --help${NC} Show this help menu."
  echo
  echo -e "${BOLD}EXAMPLES:${NC}"
  echo -e "  ${BLUE}zfn${NC}                        # Interactive mode"
  echo -e "  ${BLUE}zfn array_list${NC}             # List all function signatures"
  echo -e "  ${BLUE}zfn array_list append${NC}      # Show code for 'fn append'"
  echo -e "  ${BLUE}zfn -t array_list${NC}          # List all test names"
  echo -e "  ${BLUE}zfn -t array_list init${NC}     # Show code for tests matching 'init'"
  echo
}

# ==========================================
#  ARGUMENT PARSING
# ==========================================
MODE="fn"
SHOW_FULL=0

# Parse flags until we hit a non-flag argument
while [[ "$1" == -* ]]; do
  case "$1" in
  -h | --help)
    show_help
    exit 0
    ;;
  -t)
    MODE="test"
    shift
    ;;
  -f)
    SHOW_FULL=1
    shift
    ;;
  *)
    echo "Unknown option: $1"
    show_help
    exit 1
    ;;
  esac
done

# ==========================================
#  DETERMINE TARGET
# ==========================================
if [ -z "$1" ]; then
  # No file arg -> Use fzf
  TARGET=$(cd "$STD_LIB" && find . -name "*.zig" | sed 's|^\./||' | fzf --height=40% --layout=reverse --border --prompt="Zig StdLib> ")
  if [ -z "$TARGET" ]; then exit 0; fi
else
  # File arg provided
  TARGET="$1"
fi
shift # Remove filename from args, leaving only the filter

# Handle extension and filter variable
FILTER="$*"
if [[ "$TARGET" != *.zig ]]; then TARGET="${TARGET}.zig"; fi

echo -e "\n${BLUE} *** $TARGET ($MODE) *** ${NC}"

# ==========================================
#  CORE FUNCTIONS
# ==========================================

# 1. LIST MODE (Fast, Signatures only)
function list_signatures() {
  local pattern=""
  if [ "$MODE" == "test" ]; then
    pattern='test[[:space:]]+"[^"]*"'
  else
    pattern='(pub[[:space:]]+)?fn[[:space:]]+[a-zA-Z_]'
  fi

  rg "$pattern" "$STD_LIB/$TARGET" --trim --color=never | bat -l zig --style=plain --paging=never
}

# 2. EXTRACT MODE (Smart, Full Blocks)
function extract_bodies() {
  local awk_script=""

  if [ "$MODE" == "test" ]; then
    # Awk for TESTS
    awk_script='
        BEGIN { brace_depth=0; in_block=0 }
        /test[[:space:]]+"[^"]*"/ {
            if (filter != "" && $0 !~ filter) next;
            in_block=1
        }
        in_block {
            print $0
            brace_depth += (split($0, a, "{") - 1) - (split($0, b, "}") - 1)
            if (brace_depth <= 0) { in_block=0; brace_depth=0; print "" }
        }'
  else
    # Awk for FUNCTIONS (Strict Match)
    awk_script='
        BEGIN { brace_depth=0; in_block=0; block_opened=0 }
        /(pub[[:space:]]+)?fn[[:space:]]+[a-zA-Z_]/ {
            if (filter != "") {
                # Strict boundary check: name + (space or non-identifier)
                regex = "fn[[:space:]]+" filter "([^a-zA-Z0-9_]|$)"
                if ($0 !~ regex) next;
            }
            in_block=1; block_opened=0
        }
        in_block {
            print $0
            open_count = split($0, a, "{") - 1
            close_count = split($0, b, "}") - 1
            brace_depth += (open_count - close_count)
            if (open_count > 0) block_opened=1

            if (block_opened == 1 && brace_depth <= 0) {
                in_block=0; brace_depth=0; print ""
            } else if (block_opened == 0 && $0 ~ /;[[:space:]]*$/) {
                in_block=0; brace_depth=0; print ""
            }
        }'
  fi

  awk -v filter="$FILTER" "$awk_script" "$STD_LIB/$TARGET" | bat -l zig --style=plain --paging=never
}

# ==========================================
#  MAIN EXECUTION
# ==========================================

# Logic:
# If FILTER is provided OR -f flag is used -> Extract Bodies
# Otherwise -> List Signatures

if [ -n "$FILTER" ] || [ "$SHOW_FULL" -eq 1 ]; then
  extract_bodies
else
  list_signatures
fi
