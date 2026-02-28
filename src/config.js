// Configuration constants for MCP SSH Manager

/**
 * Parse an integer from a string, returning `defaultVal` if the result is NaN
 * or falls below `min` (defaults to 1 to reject zero and negative values that
 * could disable limits or cause unexpected behaviour).
 */
function safeParseInt(val, defaultVal, min = 1) {
  const n = parseInt(val, 10);
  if (isNaN(n) || n < min) return defaultVal;
  return n;
}

// Output limits to prevent Claude Code crashes
export const OUTPUT_LIMITS = {
  // Maximum length of stdout/stderr in responses (characters)
  MAX_OUTPUT_LENGTH: safeParseInt(process.env.MCP_SSH_MAX_OUTPUT_LENGTH, 10000),

  // Maximum length for log file tailing
  MAX_TAIL_LINES: safeParseInt(process.env.MCP_SSH_MAX_TAIL_LINES, 100),

  // Maximum length for rsync verbose output
  MAX_RSYNC_OUTPUT: safeParseInt(process.env.MCP_SSH_MAX_RSYNC_OUTPUT, 5000),
};

// Timeout configuration
export const TIMEOUTS = {
  // Default command execution timeout (milliseconds)
  DEFAULT_COMMAND_TIMEOUT: safeParseInt(process.env.MCP_SSH_DEFAULT_TIMEOUT, 120000), // 2 minutes

  // Maximum allowed command timeout (milliseconds)
  MAX_COMMAND_TIMEOUT: safeParseInt(process.env.MCP_SSH_MAX_TIMEOUT, 300000), // 5 minutes

  // Connection timeout (milliseconds)
  CONNECTION_TIMEOUT: safeParseInt(process.env.MCP_SSH_CONNECTION_TIMEOUT, 1800000), // 30 minutes

  // Keepalive interval (milliseconds)
  KEEPALIVE_INTERVAL: safeParseInt(process.env.MCP_SSH_KEEPALIVE_INTERVAL, 60000), // 1 minute
};

// Response formatting
export const RESPONSE_FORMAT = {
  // Whether to use compact JSON (no formatting)
  COMPACT_JSON: process.env.MCP_SSH_COMPACT_JSON === 'true',

  // Whether to include debug information in responses
  INCLUDE_DEBUG_INFO: process.env.MCP_SSH_DEBUG === 'true',
};

// Helper function to truncate output
export function truncateOutput(text, maxLength = OUTPUT_LIMITS.MAX_OUTPUT_LENGTH) {
  if (!text) return '';

  if (text.length <= maxLength) return text;

  const truncated = text.length - maxLength;
  return text.substring(0, maxLength) + `\n\n... [${truncated} characters truncated]`;
}

// Helper function to format JSON response
export function formatJSONResponse(data) {
  return JSON.stringify(data, null, RESPONSE_FORMAT.COMPACT_JSON ? 0 : 2);
}
