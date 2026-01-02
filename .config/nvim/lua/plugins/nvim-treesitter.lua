return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "lua",
        "vim",
        "vimdoc",
        "bash",
        "python",
        "javascript",
        "html",
        "css",
        "json",
        "yaml",
        "toml",
        "markdown",
        "markdown_inline",
        "dockerfile",
        "gitignore",
      },
      auto_install = true, -- install missing parsers when entering buffer
    },
  },
}
