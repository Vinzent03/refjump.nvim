local M = {}

---Used to keep track of if LSP reference highlights should be enabled
local highlight_references = false

---@class RefjumpKeymapOptions
---@field enable? boolean
---@field next? string Keymap to jump to next LSP reference
---@field prev? string Keymap to jump to previous LSP reference

---@class RefjumpHighlightOptions
---@field enable? boolean
---@field auto_clear boolean Automatically clear highlights when cursor moves

---@class RefjumpIntegrationOptions
---@field demicolon? { enable?: boolean } Make `]r`/`[r` repeatable with `;`/`,` using demicolon.nvim

---@class RefjumpOptions
---@field keymaps? RefjumpKeymapOptions
---@field highlights? RefjumpHighlightOptions
---@field integrations RefjumpIntegrationOptions
---@field verbose boolean Print warnings if no reference is found
local options = {
  keymaps = {
    enable = true,
    next = ']r',
    prev = '[r',
  },
  highlights = {
    enable = true,
    auto_clear = true,
  },
  integrations = {
    demicolon = {
      enable = true,
    },
  },
  verbose = true,
}

---@param references table[]
---@param forward boolean
---@param current_position integer[]
---@return table
local function find_next_reference(references, forward, current_position)
  local current_line = current_position[1] - 1
  local current_col = current_position[2]

  local next_reference
  if forward then
    next_reference = vim.iter(references):find(function(ref)
      local ref_pos = ref.range.start
      return ref_pos.line > current_line or (ref_pos.line == current_line and ref_pos.character > current_col)
    end)
  else
    next_reference = vim.iter(references):rfind(function(ref)
      local ref_pos = ref.range.start
      return ref_pos.line < current_line or (ref_pos.line == current_line and ref_pos.character < current_col)
    end)
  end

  return next_reference
end

---@param next_reference table
local function move_cursor_to(next_reference)
  local uri = next_reference.uri or next_reference.targetUri
  if not uri then
    vim.notify('refjump.nvim: Invalid URI in LSP response', vim.log.levels.ERROR)
    return
  end

  local bufnr = vim.uri_to_bufnr(uri)

  vim.fn.bufload(bufnr)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_win_set_cursor(0, {
    next_reference.range.start.line + 1,
    next_reference.range.start.character,
  })

  -- Open folds if the reference is inside a fold
  vim.cmd('normal! zv')
end

---Move cursor to next LSP reference if `forward` is `true`, otherwise move to
---the previous reference
---@param opts { forward: boolean }
function M.reference_jump(opts)
  opts = opts or { forward = true }

  vim.lsp.buf.document_highlight()

  local params = vim.lsp.util.make_position_params()
  local context = { includeDeclaration = true }
  params = vim.tbl_extend('error', params, { context = context })

  vim.lsp.buf_request(0, 'textDocument/references', params, function(err, references, _, _)
    if err then
      vim.notify('refjump.nvim: LSP Error: ' .. err.message, vim.log.levels.ERROR)
      return
    end

    if not references or vim.tbl_isempty(references) then
      if options.verbose then
        vim.notify('No references found', vim.log.levels.INFO)
      end
      return
    end

    local current_position = vim.api.nvim_win_get_cursor(0)
    local next_reference = find_next_reference(references, opts.forward, current_position)

    -- If no reference is found, loop around
    if not next_reference then
      next_reference = opts.forward and references[1] or references[#references]
    end

    if next_reference then
      move_cursor_to(next_reference)
      highlight_references = true
    else
      vim.notify('refjump.nvim: Could not find the next reference', vim.log.levels.WARN)
    end
  end)
end

local function clear_highlights_on_cursor_move()
  vim.api.nvim_create_autocmd('CursorMoved', {
    -- TODO: expose clear function to user
    callback = function()
      if not highlight_references then
        vim.lsp.buf.clear_references()
      else
        highlight_references = false
      end
    end,
  })
end

---@param opts RefjumpOptions
function M.setup(opts)
  options = vim.tbl_deep_extend('force', options, opts)

  if options.keymaps.enable then
    require('refjump.keymaps').create_keymaps(options)
  end

  if options.highlights.enable and options.highlights.auto_clear then
    clear_highlights_on_cursor_move()
  end
end

return M
