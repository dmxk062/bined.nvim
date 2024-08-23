local parser = require("bined.parser")
local M = {}

local function redraw_edit_buffer(bufnum)
    local data = vim.b[bufnum].bined_data
    local lines = parser.buffer_to_repr(data.bufnum, data.base, data.width)
    vim.api.nvim_buf_set_lines(data.edit_buf, 0, -1, true, lines)
end

---@param bufnum integer
---@param winnum integer
---@param base string
function M.attach_to_or_upd_buffer(bufnum, winnum, base)
    if vim.b[bufnum].bined_data then
        local data = vim.b[bufnum].bined_data
        data.base = base
        print(data.width)
        vim.b[bufnum].bined_data = data
        vim.schedule(function() redraw_edit_buffer(bufnum) end)
    else
        local edit_buf = vim.api.nvim_create_buf(true, false)
        local edit_win = vim.api.nvim_open_win(edit_buf, true, { win = winnum, split = "left" })
        local width = vim.api.nvim_win_get_width(edit_win)
        local augroup = vim.api.nvim_create_augroup("bined_win" .. edit_win .. "_buf" .. bufnum, { clear = true })
        vim.b[edit_buf].bined_data = {
            augroup = augroup,
            bufnum = bufnum,
            winnum = winnum,
            base = base,
            width = width,
            edit_win = edit_win,
            edit_buf = edit_buf,
        }
        vim.api.nvim_create_autocmd("WinResized", {
            group = augroup,
            buffer = edit_buf,
            callback = function(args)
                local data = vim.b[edit_buf].bined_data
                data.width = vim.api.nvim_win_get_width(edit_win)
                vim.b[bufnum].bined_data = data
                vim.schedule(function() redraw_edit_buffer(bufnum) end)
            end
        })

        vim.api.nvim_create_autocmd("WinClosed", {
            once = true,
            buffer = edit_buf,
            callback = function(args)
                vim.api.nvim_buf_delete(edit_buf, {force = true})
                vim.api.nvim_del_augroup_by_id(augroup)
            end
        })
        vim.api.nvim_create_autocmd("WinClosed", {
            once = true,
            buffer = bufnum,
            nested = true,
            callback = function(args)
                vim.api.nvim_win_close(edit_win, true)
            end
        })
        vim.schedule(function() redraw_edit_buffer(bufnum) end)
    end

end

return M
