-- State machine: orchestrates phase transitions (build -> invasion -> result).
-- Owns the active phase and exposes update/handlers that route to the right module.
-- Pure logic, no rendering.

local M = {}

return M
