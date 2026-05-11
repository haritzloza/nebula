-- Claude in-editor via CodeCompanion (Anthropic adapter)
-- Requiere: claude CLI o ANTHROPIC_API_KEY
return {
    {
        "olimorris/codecompanion.nvim",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-treesitter/nvim-treesitter",
        },
        cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions" },
        keys = {
            { "<leader>aa", "<cmd>CodeCompanionActions<cr>",     desc = "Claude actions" },
            { "<leader>ac", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Claude chat" },
            { "<leader>ai", "<cmd>CodeCompanionChat Add<cr>",    desc = "Add to Claude chat", mode = { "n", "v" } },
        },
        opts = {
            strategies = {
                chat   = { adapter = "anthropic" },
                inline = { adapter = "anthropic" },
            },
            adapters = {
                anthropic = function()
                    return require("codecompanion.adapters").extend("anthropic", {
                        schema = {
                            model = { default = "claude-sonnet-4-6" },
                        },
                    })
                end,
            },
            display = {
                chat = { window = { layout = "vertical", width = 0.35 } },
            },
        },
    },
}
