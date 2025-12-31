return {
  {
    "obsidian-nvim/obsidian.nvim",
    version = "*",
    lazy = true,

    -- Load on markdown OR when running :Obsidian
    ft = "markdown",
    cmd = { "Obsidian" },

    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
    },

    opts = {
      workspaces = {
        {
          name = "engineer",
          path = "~/Obsidian/engineer/",
        },
      },

      -- Avoid auto frontmatter injection
      disable_frontmatter = function(_fname)
        return true
      end,

      -- Filename from title (slug)
      note_id_func = function(title)
        title = title or "untitled"
        local slug = title:lower():gsub("%s+", "-"):gsub("[^%w%-]", ""):gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", "")
        return (slug ~= "" and slug) or tostring(os.time())
      end,

      -- Force all new notes into Inbox
      note_path_func = function(spec)
        local fname = (spec.id or tostring(os.time())) .. ".md"
        return "0 Inbox/" .. fname
      end,

      templates = {
        folder = "3 Resources/templates",
        substitutions = {
          created_iso = function()
            return os.date("%Y-%m-%dT%H:%M")
          end,
        },
      },

      callbacks = {
        pre_write_note = function(_client, note)
          if not note then
            return
          end

          -- Depending on version it may be metadata or frontmatter
          local fm = note.metadata or note.frontmatter
          if type(fm) ~= "table" then
            return
          end

          fm.id = nil
          fm.aliases = nil

          -- If Created accidentally became a table (older bug), remove it
          if type(fm.Created) == "table" then
            fm.Created = nil
          end
        end,
      },
    },

    keys = {
      { "<leader>sO", "<cmd>Obsidian search<cr>", desc = "Obsidian: Search Notes" },

      {
        "<leader>on",
        function()
          vim.ui.input({ prompt = "Note title: " }, function(title)
            if not title or title == "" then
              return
            end
            vim.cmd(string.format([[Obsidian new_from_template "%s" new-nvim-note]], title))
          end)
        end,
        desc = "Obsidian: New Note (template + title)",
      },

      { "<leader>od", "<cmd>Obsidian dailies<cr>", desc = "Obsidian: Dailies" },
    },
  },
}
