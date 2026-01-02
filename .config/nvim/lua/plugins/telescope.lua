return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
  },
  keys = {
    { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find Files" },
    { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live Grep (cwd)" },
    { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help Tags" },
    {
      "<leader>en",
      function()
        require("telescope.builtin").find_files({ cwd = vim.fn.stdpath("config") })
      end,
      desc = "Find Neovim Files",
    },
    {
      "<leader>fn",
      function()
        require("telescope.builtin").find_files({
          search_dirs = {
            vim.fn.expand("~/Obsidian/engineer/"),
            vim.fn.expand("~/Documents/Notes/"),
          },
        })
      end,
      desc = "Find Notes and Documents",
    },
    -- {
    --   "<leader>fp",
    --   function()
    --     require("telescope.builtin").find_files({ cwd = require("lazy.core.config").options.root })
    --   end,
    --   desc = "Find Plugin Files",
    -- },
  },
  opts = {
    pickers = {
      find_files = {
        find_command = { "rg", "--files", "--hidden", "--glob", "!**/.git/*" },
      },
    },
  },
  config = function(_, opts)
    require("telescope").setup(opts)
    pcall(require("telescope").load_extension, "fzf")
  end,
}
