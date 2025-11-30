#!/usr/bin/env node

/**
 * MCP SSH Manager - HTTP/WebSocket Server
 *
 * This server exposes the MCP tools via HTTP/WebSocket for Flutter and other clients.
 *
 * Usage:
 *   node src/server-http.js [--port 3000] [--host 0.0.0.0]
 *
 * Endpoints:
 *   GET  /          - Server info
 *   GET  /health    - Health check
 *   WS   /mcp       - MCP WebSocket endpoint
 */

import { HttpServerTransport } from './http-transport.js';
import SSHManager from './ssh-manager.js';
import { configLoader } from './config-loader.js';
import { logger } from './logger.js';
import * as dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

// Load environment variables
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '..', '.env') });

// Parse command line arguments
const args = process.argv.slice(2);
let port = 3000;
let host = '0.0.0.0';

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--port' && args[i + 1]) {
    port = parseInt(args[i + 1], 10);
    i++;
  } else if (args[i] === '--host' && args[i + 1]) {
    host = args[i + 1];
    i++;
  }
}

// Connection pool for SSH
const connections = new Map();

/**
 * Get or create SSH connection
 */
async function getConnection(serverName) {
  const normalizedName = serverName.toLowerCase();

  // Check existing connection
  if (connections.has(normalizedName)) {
    const conn = connections.get(normalizedName);
    if (conn.isConnected()) {
      return conn;
    }
    // Connection lost, remove it
    conn.dispose();
    connections.delete(normalizedName);
  }

  // Get server config
  const config = configLoader.getServer(normalizedName);
  if (!config) {
    throw new Error(`Server not found: ${serverName}`);
  }

  // Create new connection
  const ssh = new SSHManager(config);
  await ssh.connect();
  connections.set(normalizedName, ssh);

  return ssh;
}

/**
 * MCP Server implementation for HTTP transport
 */
class McpSshServer {
  constructor() {
    this.tools = this.defineTools();
  }

  defineTools() {
    return [
      {
        name: 'ssh_list_servers',
        description: 'List all configured SSH servers',
        inputSchema: {
          type: 'object',
          properties: {},
          required: []
        }
      },
      {
        name: 'ssh_execute',
        description: 'Execute a command on a remote SSH server',
        inputSchema: {
          type: 'object',
          properties: {
            server: { type: 'string', description: 'Server name' },
            command: { type: 'string', description: 'Command to execute' },
            cwd: { type: 'string', description: 'Working directory (optional)' },
            timeout: { type: 'number', description: 'Timeout in ms (default: 30000)' }
          },
          required: ['server', 'command']
        }
      },
      {
        name: 'ssh_upload',
        description: 'Upload a file to a remote server',
        inputSchema: {
          type: 'object',
          properties: {
            server: { type: 'string', description: 'Server name' },
            localPath: { type: 'string', description: 'Local file path' },
            remotePath: { type: 'string', description: 'Remote destination path' }
          },
          required: ['server', 'localPath', 'remotePath']
        }
      },
      {
        name: 'ssh_download',
        description: 'Download a file from a remote server',
        inputSchema: {
          type: 'object',
          properties: {
            server: { type: 'string', description: 'Server name' },
            remotePath: { type: 'string', description: 'Remote file path' },
            localPath: { type: 'string', description: 'Local destination path' }
          },
          required: ['server', 'remotePath', 'localPath']
        }
      },
      {
        name: 'ssh_list_files',
        description: 'List files in a directory on a remote server',
        inputSchema: {
          type: 'object',
          properties: {
            server: { type: 'string', description: 'Server name' },
            path: { type: 'string', description: 'Directory path (default: ~)' },
            showHidden: { type: 'boolean', description: 'Show hidden files' }
          },
          required: ['server']
        }
      },
      {
        name: 'ssh_file_info',
        description: 'Get detailed information about a file or directory',
        inputSchema: {
          type: 'object',
          properties: {
            server: { type: 'string', description: 'Server name' },
            path: { type: 'string', description: 'File or directory path' }
          },
          required: ['server', 'path']
        }
      },
      {
        name: 'ssh_mkdir',
        description: 'Create a directory on a remote server',
        inputSchema: {
          type: 'object',
          properties: {
            server: { type: 'string', description: 'Server name' },
            path: { type: 'string', description: 'Directory path to create' },
            recursive: { type: 'boolean', description: 'Create parent directories' }
          },
          required: ['server', 'path']
        }
      },
      {
        name: 'ssh_delete',
        description: 'Delete a file or directory on a remote server',
        inputSchema: {
          type: 'object',
          properties: {
            server: { type: 'string', description: 'Server name' },
            path: { type: 'string', description: 'Path to delete' },
            recursive: { type: 'boolean', description: 'Delete directories recursively' }
          },
          required: ['server', 'path']
        }
      },
      {
        name: 'ssh_rename',
        description: 'Rename or move a file on a remote server',
        inputSchema: {
          type: 'object',
          properties: {
            server: { type: 'string', description: 'Server name' },
            oldPath: { type: 'string', description: 'Current path' },
            newPath: { type: 'string', description: 'New path' }
          },
          required: ['server', 'oldPath', 'newPath']
        }
      },
      {
        name: 'ssh_read_file',
        description: 'Read the contents of a file on a remote server',
        inputSchema: {
          type: 'object',
          properties: {
            server: { type: 'string', description: 'Server name' },
            path: { type: 'string', description: 'File path' },
            encoding: { type: 'string', description: 'Text encoding (default: utf8)' }
          },
          required: ['server', 'path']
        }
      }
    ];
  }

  async listTools() {
    return this.tools;
  }

  async callTool(name, args) {
    switch (name) {
      case 'ssh_list_servers':
        return this.listServers();
      case 'ssh_execute':
        return this.execute(args);
      case 'ssh_upload':
        return this.upload(args);
      case 'ssh_download':
        return this.download(args);
      case 'ssh_list_files':
        return this.listFiles(args);
      case 'ssh_file_info':
        return this.fileInfo(args);
      case 'ssh_mkdir':
        return this.mkdir(args);
      case 'ssh_delete':
        return this.deleteFile(args);
      case 'ssh_rename':
        return this.rename(args);
      case 'ssh_read_file':
        return this.readFile(args);
      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  }

  async listServers() {
    const servers = configLoader.getAllServers();
    return {
      content: [{
        type: 'text',
        text: JSON.stringify(servers, null, 2)
      }]
    };
  }

  async execute({ server, command, cwd, timeout = 30000 }) {
    const ssh = await getConnection(server);
    const result = await ssh.execCommand(command, { cwd, timeout });
    return {
      content: [{
        type: 'text',
        text: JSON.stringify({
          stdout: result.stdout,
          stderr: result.stderr,
          code: result.code
        }, null, 2)
      }]
    };
  }

  async upload({ server, localPath, remotePath }) {
    const ssh = await getConnection(server);
    await ssh.putFile(localPath, remotePath);
    return {
      content: [{
        type: 'text',
        text: JSON.stringify({ success: true, message: `Uploaded ${localPath} to ${remotePath}` })
      }]
    };
  }

  async download({ server, remotePath, localPath }) {
    const ssh = await getConnection(server);
    await ssh.getFile(localPath, remotePath);
    return {
      content: [{
        type: 'text',
        text: JSON.stringify({ success: true, message: `Downloaded ${remotePath} to ${localPath}` })
      }]
    };
  }

  async listFiles({ server, path = '~', showHidden = false }) {
    const ssh = await getConnection(server);
    const lsFlags = showHidden ? '-la' : '-l';
    const result = await ssh.execCommand(`ls ${lsFlags} --time-style=long-iso "${path}" 2>/dev/null || ls ${lsFlags} "${path}"`, { timeout: 10000 });

    // Parse ls output
    const lines = result.stdout.trim().split('\n').filter(line => line && !line.startsWith('total'));
    const files = lines.map(line => {
      const parts = line.split(/\s+/);
      if (parts.length >= 8) {
        const permissions = parts[0];
        const isDirectory = permissions.startsWith('d');
        const isLink = permissions.startsWith('l');
        const size = parseInt(parts[4], 10);
        const date = `${parts[5]} ${parts[6]}`;
        const name = parts.slice(7).join(' ').split(' -> ')[0]; // Handle symlinks

        return {
          name,
          isDirectory,
          isLink,
          permissions,
          size,
          modified: date
        };
      }
      return null;
    }).filter(f => f !== null);

    return {
      content: [{
        type: 'text',
        text: JSON.stringify({ path, files }, null, 2)
      }]
    };
  }

  async fileInfo({ server, path }) {
    const ssh = await getConnection(server);
    const result = await ssh.execCommand(`stat "${path}" && file "${path}"`, { timeout: 10000 });
    return {
      content: [{
        type: 'text',
        text: result.stdout + (result.stderr ? `\nErrors: ${result.stderr}` : '')
      }]
    };
  }

  async mkdir({ server, path, recursive = true }) {
    const ssh = await getConnection(server);
    const flags = recursive ? '-p' : '';
    const result = await ssh.execCommand(`mkdir ${flags} "${path}"`, { timeout: 10000 });
    return {
      content: [{
        type: 'text',
        text: JSON.stringify({
          success: result.code === 0,
          message: result.code === 0 ? `Created directory: ${path}` : result.stderr
        })
      }]
    };
  }

  async deleteFile({ server, path, recursive = false }) {
    const ssh = await getConnection(server);
    const flags = recursive ? '-rf' : '-f';
    const result = await ssh.execCommand(`rm ${flags} "${path}"`, { timeout: 30000 });
    return {
      content: [{
        type: 'text',
        text: JSON.stringify({
          success: result.code === 0,
          message: result.code === 0 ? `Deleted: ${path}` : result.stderr
        })
      }]
    };
  }

  async rename({ server, oldPath, newPath }) {
    const ssh = await getConnection(server);
    const result = await ssh.execCommand(`mv "${oldPath}" "${newPath}"`, { timeout: 10000 });
    return {
      content: [{
        type: 'text',
        text: JSON.stringify({
          success: result.code === 0,
          message: result.code === 0 ? `Renamed ${oldPath} to ${newPath}` : result.stderr
        })
      }]
    };
  }

  async readFile({ server, path, encoding = 'utf8' }) {
    const ssh = await getConnection(server);
    const result = await ssh.execCommand(`cat "${path}"`, { timeout: 30000 });
    return {
      content: [{
        type: 'text',
        text: result.code === 0 ? result.stdout : `Error: ${result.stderr}`
      }]
    };
  }
}

// Start server
async function main() {
  console.error('╔════════════════════════════════════════════════════════════╗');
  console.error('║          MCP SSH Manager - HTTP/WebSocket Server           ║');
  console.error('╚════════════════════════════════════════════════════════════╝');
  console.error('');

  // Load configuration
  await configLoader.load({
    envPath: path.join(__dirname, '..', '.env')
  });

  const transport = new HttpServerTransport({ port, host });
  const mcpServer = new McpSshServer();

  // Wrap MCP server with HTTP transport handler
  transport.on('message', async (message, clientId) => {
    try {
      const { method, params, id } = message;
      let response;

      switch (method) {
        case 'initialize':
          response = {
            jsonrpc: '2.0',
            result: {
              protocolVersion: '2024-11-05',
              capabilities: { tools: {} },
              serverInfo: { name: 'mcp-ssh-manager', version: '3.1.0' }
            },
            id
          };
          break;

        case 'notifications/initialized':
          // No response needed
          return;

        case 'tools/list':
          const tools = await mcpServer.listTools();
          response = { jsonrpc: '2.0', result: { tools }, id };
          break;

        case 'tools/call':
          try {
            const result = await mcpServer.callTool(params.name, params.arguments || {});
            response = { jsonrpc: '2.0', result, id };
          } catch (err) {
            response = {
              jsonrpc: '2.0',
              error: { code: -32000, message: err.message },
              id
            };
          }
          break;

        default:
          response = {
            jsonrpc: '2.0',
            error: { code: -32601, message: `Method not found: ${method}` },
            id
          };
      }

      if (response) {
        transport.send(response, clientId);
      }
    } catch (err) {
      console.error('[Server] Error:', err);
      transport.send({
        jsonrpc: '2.0',
        error: { code: -32603, message: err.message },
        id: message.id || null
      }, clientId);
    }
  });

  await transport.start();

  console.error('');
  console.error('Available servers:', configLoader.getAllServers().map(s => s.name).join(', ') || '(none configured)');
  console.error('');
  console.error('Connect your Flutter app to: ws://' + host + ':' + port + '/mcp');
  console.error('');

  // Handle shutdown
  process.on('SIGINT', async () => {
    console.error('\nShutting down...');
    for (const [name, conn] of connections) {
      conn.dispose();
    }
    await transport.close();
    process.exit(0);
  });
}

main().catch(err => {
  console.error('Failed to start server:', err);
  process.exit(1);
});
