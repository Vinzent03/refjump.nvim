local M = {}

local options = {
  keymaps = {
    enable = true,
    next = ']r',
    prev = '[r',
  },
}

function M.reference_jump(opts)
  opts = opts or { forward = true }

  local params = vim.lsp.util.make_position_params()
  local context = { includeDeclaration = true }
  params = vim.tbl_extend('error', params, { context = context })

  vim.lsp.buf_request(0, 'textDocument/references', params, function(err, references, _, _)
    if err then
      vim.notify('LSP Error: ' .. err.message, vim.log.levels.ERROR)
      return
    end

    if not references or vim.tbl_isempty(references) then
      vim.notify('No references found', vim.log.levels.INFO)
      return
    end

    local current_position = vim.api.nvim_win_get_cursor(0)
    local current_line = current_position[1] - 1
    local current_col = current_position[2]

    -- Find the next or previous reference
    local next_reference = opts.forward and
        vim.iter(references):find(function(ref)
          local ref_pos = ref.range.start
          return ref_pos.line > current_line or (ref_pos.line == current_line and ref_pos.character > current_col)
        end) or
        vim.iter(references):rfind(function(ref)
          local ref_pos = ref.range.start
          return ref_pos.line < current_line or (ref_pos.line == current_line and ref_pos.character < current_col)
        end)

    -- If no reference is found in the chosen direction, loop around
    if not next_reference then
      next_reference = opts.forward and references[1] or references[#references]
    end

    if next_reference then
      local uri = next_reference.uri or next_reference.targetUri
      if not uri then
        vim.notify('Invalid URI in LSP response', vim.log.levels.ERROR)
        return
      end

      local bufnr = vim.uri_to_bufnr(uri)

      vim.fn.bufload(bufnr)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, {
        next_reference.range.start.line + 1,
        next_reference.range.start.character,
      })

      vim.cmd('normal! zv') -- Open folds if the reference is inside a fold
    else
      vim.notify('Could not find the next reference', vim.log.levels.WARN)
    end
  end)
end

function M.setup(opts)
  options = vim.tbl_deep_extend('force', options, opts)

  if options.keymaps.enable then
    require('refjump.keymaps').create_keymaps(options)
  end
end

return M
