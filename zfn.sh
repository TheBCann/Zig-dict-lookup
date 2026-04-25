#!/bin/bash

# Configuration
STD_LIB="$HOME/.zig-versions/nightly/lib/std"
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ==========================================
#  HELP MENU
# ==========================================
function show_help() {
  echo -e "${BLUE}${BOLD}zfn${NC} - Zig Standard Library Explorer"
  echo -e "A CLI tool to fuzzy-find, list, and extract functions, tests, and interfaces from the Zig std lib."
  echo
  echo -e "${BOLD}USAGE:${NC}"
  echo -e "  zfn [flags] [file] [filter]"
  echo
  echo -e "${BOLD}ARGUMENTS:${NC}"
  echo -e "  ${BOLD}file${NC}       The standard library file (e.g., 'array_list' or 'net')."
  echo -e "            If omitted, opens an interactive fuzzy finder (fzf)."
  echo -e "  ${BOLD}filter${NC}     The name of the function, test, or struct to extract."
  echo -e "            If provided, prints the full code block (Extract Mode)."
  echo -e "            If omitted, lists one-line signatures (List Mode)."
  echo
  echo -e "${BOLD}FLAGS:${NC}"
  echo -e "  ${BOLD}-t${NC}        Test Mode. Search for 'test' blocks."
  echo -e "  ${BOLD}-i${NC}        Interface Mode. Search for structs, unions, and enums."
  echo -e "  ${BOLD}-d${NC}        Data Mode. When used with -i, shows fields but hides methods."
  echo -e "  ${BOLD}-f${NC}        Full Mode. Force printing full code blocks even without a filter."
  echo -e "  ${BOLD}-h, --help${NC} Show this help menu."
  echo
  echo -e "${BOLD}EXAMPLES:${NC}"
  echo -e "  ${BLUE}zfn -i -d net${NC}              # List all structs in 'net' with their fields"
  echo -e "  ${BLUE}zfn -i net Address${NC}         # Show full code (methods included) for 'Address'"
  echo
}

# ==========================================
#  ARGUMENT PARSING
# ==========================================
MODE="fn"
SHOW_FULL=0
SHOW_FIELDS=0

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
  -i)
    MODE="interface"
    shift
    ;;
  -f)
    SHOW_FULL=1
    shift
    ;;
  -d)
    SHOW_FIELDS=1
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
  elif [ "$MODE" == "interface" ]; then
    # Allows indentation to catch nested structs
    pattern='^[[:space:]]*(pub[[:space:]]+)?const[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*=[[:space:]]*([a-z]+[[:space:]]+)?(struct|union|enum|opaque)'
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
  elif [ "$MODE" == "interface" ]; then
    # Awk for INTERFACES (Structs/Unions/Enums)
    awk_script='
         BEGIN { brace_depth=0; in_block=0; block_opened=0; skipping_fn=0; fn_brace_start=0 }
         # Matches top-level definitions, allows indentation
         /^[[:space:]]*(pub[[:space:]]+)?const[[:space:]]+[a-zA-Z0-9_]+[[:space:]]*=[[:space:]]*([a-z]+[[:space:]]+)?(struct|union|enum|opaque)/ {
             if (in_block == 0) {
                 if (filter != "") {
                     regex = "const[[:space:]]+" filter "[[:space:]]*="
                     if ($0 !~ regex) next;
                 }
                 in_block=1; block_opened=0
             }
         }
         in_block {
             should_print = 1

             # LOGIC: Skip Functions/Tests if -d flag is set
             if (show_fields == 1) {
                 if ($0 ~ /(pub[[:space:]]+)?fn[[:space:]]+|test[[:space:]]+"[^"]*"/) {
                     skipping_fn = 1
                     fn_brace_start = brace_depth
                 }
                 if (skipping_fn) should_print = 0
             }

             if (should_print) print $0

             open_count = split($0, a, "{") - 1
             close_count = split($0, b, "}") - 1
             brace_depth += (open_count - close_count)
             if (open_count > 0) block_opened=1

             # LOGIC: Check if we finished skipping
             if (show_fields == 1 && skipping_fn) {
                 if (brace_depth <= fn_brace_start) {
                     skipping_fn = 0
                 }
             }

             if (block_opened == 1 && brace_depth <= 0) {
                 in_block=0; brace_depth=0; print ""
             } else if (block_opened == 0 && $0 ~ /;[[:space:]]*$/) {
                 in_block=0; brace_depth=0; print ""
             }
         }'
  else
    # Awk for FUNCTIONS (Strict Match)
    awk_script='
         BEGIN { brace_depth=0; in_block=0; block_opened=0 }
         /(pub[[:space:]]+)?fn[[:space:]]+[a-zA-Z_]/ {
             if (filter != "") {
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

  awk -v filter="$FILTER" -v show_fields="$SHOW_FIELDS" "$awk_script" "$STD_LIB/$TARGET" | bat -l zig --style=plain --paging=never
}

# ==========================================
#  MAIN EXECUTION
# ==========================================

if [ "$SHOW_FULL" -eq 1 ] && [ -z "$FILTER" ]; then
  # Print the entire file top-to-bottom, preserving all globals and imports
  bat -l zig --style=plain --paging=never "$STD_LIB/$TARGET"
elif [ -n "$FILTER" ] || [ "$SHOW_FIELDS" -eq 1 ]; then
  # Filter provided, or interface data mode triggered
  extract_bodies
else
  # Default to one-line signatures
  list_signatures
fi
