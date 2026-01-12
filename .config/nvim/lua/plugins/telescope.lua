return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope-file-browser.nvim",
    { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
  },

  keys = {
    { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find Files" },
    { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live Grep" },
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
    {
      "<leader>fb",
      function()
        require("telescope").extensions.file_browser.file_browser({
          path = vim.fn.expand("%:p:h"),
          cwd = vim.fn.expand("%:p:h"),
          select_buffer = true,
          hidden = true,
          respect_gitignore = false,
          grouped = true,
          initial_mode = "insert",
        })
      end,
      desc = "File Browser (here)",
    },
  },

  opts = {
    pickers = {
      find_files = {
        find_command = { "rg", "--files", "--hidden", "--glob", "!**/.git/*" },
      },
    },

    extensions = {
      file_browser = {
        mappings = {
          i = {
            ["<C-n>"] = "create",          -- new file / dir
            ["<C-r>"] = "rename",          -- rename
            ["<C-d>"] = "remove",          -- delete
            ["<C-m>"] = "move",            -- move
            ["<C-c>"] = "copy",            -- copy
            ["<C-h>"] = "goto_parent_dir",
            ["<C-l>"] = "goto_home_dir",
            ["<C-w>"] = "goto_cwd",
          },
          n = {
            ["n"] = "create",
            ["r"] = "rename",
            ["d"] = "remove",
            ["m"] = "move",
            ["c"] = "copy",
            ["h"] = "goto_parent_dir",
            ["~"] = "goto_home_dir",
            ["w"] = "goto_cwd",
          },
        },
      },
    },
  },

  config = function(_, opts)
    local telescope = require("telescope")

    -- resolve string action names to real functions
    local ok, fb_actions = pcall(function()
      return require("telescope").extensions.file_browser.actions
    end)

    if ok then
      local maps = opts.extensions.file_browser.mappings
      for _, mode in pairs({ "i", "n" }) do
        for k, v in pairs(maps[mode]) do
          if type(v) == "string" and fb_actions[v] then
            maps[mode][k] = fb_actions[v]
          end
        end
      end
    end

    telescope.setup(opts)
    pcall(telescope.load_extension, "fzf")
    pcall(telescope.load_extension, "file_browser")
  end,
}
