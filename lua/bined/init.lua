local M = {}

local view = require("bined.view")



function M.setup(opts)
    opts = opts or {}
    local hl_groups = {
        BinedString      = { link = "String" },
        BinedNull        = { link = "Folded" },
        BinedNewline     = { link = "SpecialChar" },
        BinedAddress     = { link = "Label" },
        BinedCurrentLine = { link = "Cursorline" },
        BinedCurrentChar = { link = "Substitute" },
    }
    for name, hl in pairs(hl_groups) do
        vim.api.nvim_set_hl(0, name, { link = hl.link, default = true })
    end

    vim.api.nvim_create_user_command("Bined", function(args)
        local base = args.args == "" and "hex" or args.args
        if base ~= "hex" and base ~= "oct" and base ~= "bin" then
            vim.notify("Invalid base: " .. args.args, vim.log.levels.ERROR)
            return false
        end
        view.attach_to_or_upd_buffer(vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win(), base)
    end, {
        complete = function()
            return { "hex", "bin", "oct" }
        end,
        nargs = "?"
    })
end

return M
