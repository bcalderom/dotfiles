return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-mini/mini.nvim",
    },
    ft = { "markdown" }, -- only load on markdown files
    config = function()
      require("render-markdown").setup({
        render_modes = { "n", "c", "t" },
      })
    end,
  },
}
