return {
  "rebelot/kanagawa.nvim",
  priority = 1000,
  config = function()
    require("kanagawa").setup({
      theme = "dragon", -- wave (default), dragon, lotus
    })
    require("kanagawa").load()
  end,
}
