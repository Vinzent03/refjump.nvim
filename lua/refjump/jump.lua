local M = {}

---@alias RefjumpReferencePosition { character: integer, line: integer }
---@alias RefjumpReferenceRange { start: RefjumpReferencePosition, end: RefjumpReferencePosition }
---@alias RefjumpReference { range: RefjumpReferenceRange, uri: string }

---@param ref_pos RefjumpReferencePosition
---@param current_line integer
---@param current_col integer
---@return boolean
local function reference_is_after_current_position(ref_pos, current_line, current_col)
  return ref_pos.line > current_line
      or (ref_pos.line == current_line and ref_pos.character > current_col)
end

---@param ref_pos RefjumpReferencePosition
---@param current_line integer
---@param current_col integer
---@return boolean
local function reference_is_before_current_position(ref_pos, current_line, current_col)
  return ref_pos.line < current_line
      or (ref_pos.line == current_line and ref_pos.character < current_col)
end

---Find n:th next reference in `references` from `current_position` where n is
---`count`. Search forward if `forward` is `true`, otherwise search backwards.
---@param references RefjumpReference[]
---@param forward boolean
---@param count integer
---@param current_position integer[]
---@return table
local function find_next_reference(references, forward, count, current_position)
  local current_line = current_position[1] - 1
  local current_col = current_position[2]

  local iter = forward
      and vim.iter(references)
      or vim.iter(references):rev()

  return iter:filter(function(ref)
    local ref_pos = ref.range.start
    if forward then
      return reference_is_after_current_position(ref_pos, current_line, current_col)
    else
      return reference_is_before_current_position(ref_pos, current_line, current_col)
    end
  end):nth(count)
end

---@param next_reference table
local function jump_to(next_reference)
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

---@param next_reference integer[]
---@param forward boolean
---@param references RefjumpReference[]
local function jump_to_next_reference(next_reference, forward, references)
  -- If no reference is found, loop around
  if not next_reference then
    next_reference = forward and references[1] or references[#references]
  end

  if next_reference then
    jump_to(next_reference)
  else
    vim.notify('refjump.nvim: Could not find the next reference', vim.log.levels.WARN)
  end
end

---@param references RefjumpReference[]
---@param forward boolean
---@param count integer
---@param current_position integer[]
local function jump_to_next_reference_and_highlight(references, forward, count, current_position)
  local next_reference = find_next_reference(references, forward, count, current_position)
  jump_to_next_reference(next_reference, forward, references)

  if require('refjump').get_options().highlights.enable then
    require('refjump.highlight').enable_reference_highlights(references, 0)
  end
end

---Move cursor from `current_position` to the next LSP reference in the current
---buffer if `forward` is `true`, otherwise move to the previous reference.
---
---If `references` is not `nil`, `references` is used to determine next
---position. If `references` is `nil` they will be requested from the LSP
---server and passed to `with_references`.
---@param current_position integer[]
---@param opts { forward: boolean }
---@param count integer
---@param references? RefjumpReference[]
---@param with_references? function(RefjumpReference[]) Called if `references` is `nil` with LSP references for item at `current_position`
function M.reference_jump_from(current_position, opts, count, references, with_references)
  opts = opts or { forward = true }

  -- If references have already been computed (i.e. we're repeating the jump)
  if references then
    jump_to_next_reference_and_highlight(references, opts.forward, count, current_position)
    return
  end

  local params = vim.lsp.util.make_position_params()
  local context = { includeDeclaration = true }
  params = vim.tbl_extend('error', params, { context = context })

  vim.lsp.buf_request(0, 'textDocument/references', params, function(err, refs, _, _)
    if err then
      vim.notify('refjump.nvim: LSP Error: ' .. err.message, vim.log.levels.ERROR)
      return
    end

    if not refs or vim.tbl_isempty(refs) then
      if require('refjump').get_options().verbose then
        vim.notify('No references found', vim.log.levels.INFO)
      end
      return
    end

    jump_to_next_reference_and_highlight(refs, opts.forward, count, current_position)

    if with_references then
      with_references(refs)
    end
  end)
end

---Move cursor to next LSP reference in the current buffer if `forward` is
---`true`, otherwise move to the previous reference.
---
---If `references` is not `nil`, `references` is used to determine next
---position. If `references` is `nil` they will be requested from the LSP
---server and passed to `with_references`.
---@param opts { forward: boolean }
---@param references? RefjumpReference[]
---@param with_references? function(RefjumpReference[]) Called if `references` is `nil` with LSP references for item at `current_position`
function M.reference_jump(opts, references, with_references)
  local current_position = vim.api.nvim_win_get_cursor(0)
  local count = vim.v.count1
  M.reference_jump_from(current_position, opts, count, references, with_references)
end

return M
