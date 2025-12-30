return {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
      },
      "nvim-telescope/telescope-symbols.nvim",
    },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find Files Telescope" },
    },

    -- NOTE:
    -- LazyVim (and other specs) may also configure Telescope.
    -- Using opts=function(_, opts) ensures our settings are MERGED instead of replaced/ignored.
    opts = function(_, opts)
      opts.defaults = opts.defaults or {}
      opts.pickers = opts.pickers or {}
      opts.pickers.find_files = opts.pickers.find_files or {}

      -- 1) Always hide these paths from results (backend-agnostic; works even if Telescope uses fd)
      opts.defaults.file_ignore_patterns = vim.list_extend(opts.defaults.file_ignore_patterns or {}, {
        "/%.git/",
        "^%.git/",
        "/%.local/",
        "^%.local/",
        "/go/",
        "^go/",
        "/%.thunderbird/",
        "^%.thunderbird/",
        "/cache/",
        "^cache/",
        "/.codeium/",
        "^.codeium/",
        "/.windsurf/",
        "^.windsurf/",
        "/.obsidian/",
        "^.obsidian/",
      })

      -- 2) Exclude at the source for find_files (fast) + include hidden + follow symlinks
      -- Put this under pickers.find_files so builtins.find_files picks it up reliably.
      opts.pickers.find_files.find_command = {
        "rg",
        "--files",
        "--hidden",
        "--follow",
        "--glob",
        "!**/.git/*",
        "--glob",
        "!**/.local/**",
        "--glob",
        "!**/go/**",
        "--glob",
        "!**/.thunderbird/**",
        "--glob",
        "!**/.cache/**",
        "--glob",
        "!**/.windsurf/**",
        "--glob",
        "!**/.obsidian/**",
        "--glob",
        "!**/.npm/**",
      }

      -- 3) (Optional but recommended) Make live_grep respect hidden + the same excludes
      opts.defaults.vimgrep_arguments = {
        "rg",
        "--color=never",
        "--no-heading",
        "--with-filename",
        "--line-number",
        "--column",
        "--smart-case",
        "--hidden",
        "--follow",
        "--glob",
        "!**/.git/*",
        "--glob",
        "!**/.local/**",
        "--glob",
        "!**/go/**",
        "--glob",
        "!**/.thunderbird/**",
        "--glob",
        "!**/.cache/**",
        "--glob",
        "!**/.windsurf/**",
        "--glob",
        "!**/.obsidian/**",
        "--glob",
        "!**/.npm/**",
      }
    end,

    config = function(_, opts)
      local telescope = require("telescope")
      telescope.setup(opts)
      -- Load fzf-native AFTER setup and only once.
      pcall(telescope.load_extension, "fzf")
    end,
  },

  -- Custom ripgrep configuration notes (kept for reference)

  -- I want to search in hidden/dot files.
  -- "--hidden"
  --
  -- I don't want to search in the `.git` directory.
  -- "--glob"
  -- "!**/.git/*"
  --
  -- I want to follow symbolic links
  -- "--follow"
}
