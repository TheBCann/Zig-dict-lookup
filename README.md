# Zig-dict-lookup
Found this to be helpful with my terminal/neovim workflow

# MAKE SURE YOU HAVE FZF IN YOUR SYSPATH

zfn - Zig Standard Library Explorer
A CLI tool to fuzzy-find, list, and extract functions and tests from the Zig std lib.

USAGE:
  zfn [flags] [file] [filter]

ARGUMENTS:
  file      The standard library file (e.g., 'array_list' or 'net').
            If omitted, opens an interactive fuzzy finder (fzf).
  filter    The name of the function or test to extract.
            If provided, prints the full code block (Extract Mode).
            If omitted, lists one-line signatures (List Mode).

FLAGS:
  -t        Test Mode. Search for 'test' blocks instead of 'fn'.
  -f        Full Mode. Force printing full code blocks even without a filter.
  -h, --help Show this help menu.

EXAMPLES:
  zfn                        # Interactive mode
  zfn array_list             # List all function signatures
  zfn array_list append      # Show code for 'fn append'
  zfn -t array_list          # List all test names
  zfn -t array_list init     # Show code for tests matching 'init'
