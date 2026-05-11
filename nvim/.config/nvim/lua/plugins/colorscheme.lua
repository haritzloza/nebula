return {
    {
        "catppuccin/nvim",
        name = "catppuccin",
        priority = 1000,
        opts = {
            flavour = "mocha",
            transparent_background = false,
            integrations = {
                cmp = true, gitsigns = true, telescope = true, treesitter = true,
                mason = true, neotree = true, which_key = true, notify = true,
            },
        },
    },
    { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin" } },
}
