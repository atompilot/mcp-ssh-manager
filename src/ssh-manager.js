import { Client } from 'ssh2';
import fs from 'fs';
import os from 'os';
import crypto from 'crypto';
import {
  isHostKnown,
  addHostKey,
  storeFingerprint,
  getStoredFingerprint,
} from './ssh-key-manager.js';
import { logger } from './logger.js';

/**
 * Safely wrap a path in single quotes for shell argument use.
 * Escapes any single quotes within the path.
 */
function escapeShellArg(str) {
  return "'" + str.replace(/'/g, "'\\''") + "'";
}

class SSHManager {
  constructor(config) {
    this.config = config;
    this.client = new Client();
    this.connected = false;
    this.sftp = null;
    this.cachedHomeDir = null;
    this.autoAcceptHostKey = config.autoAcceptHostKey || false;
    this.hostKeyVerification = config.hostKeyVerification !== false; // Default true
  }

  async connect() {
    return new Promise((resolve, reject) => {
      this.client.on('ready', () => {
        this.connected = true;
        resolve();
      });

      this.client.on('error', (err) => {
        this.connected = false;
        reject(err);
      });

      this.client.on('end', () => {
        this.connected = false;
      });

      // Build connection config
      const connConfig = {
        host: this.config.host,
        port: this.config.port || 22,
        username: this.config.user,
        readyTimeout: 60000, // Increased from 20000 to 60000 for slow connections
        keepaliveInterval: 10000,
        // Add compatibility options for problematic servers
        algorithms: {
          kex: [
            'ecdh-sha2-nistp256',
            'ecdh-sha2-nistp384',
            'ecdh-sha2-nistp521',
            'diffie-hellman-group-exchange-sha256',
            'diffie-hellman-group14-sha256',
            'diffie-hellman-group14-sha1',
          ],
          cipher: [
            'aes128-ctr',
            'aes192-ctr',
            'aes256-ctr',
            'aes128-gcm',
            'aes256-gcm',
            'aes128-cbc',
            'aes192-cbc',
            'aes256-cbc',
          ],
          serverHostKey: [
            'ssh-rsa',
            'ecdsa-sha2-nistp256',
            'ecdsa-sha2-nistp384',
            'ecdsa-sha2-nistp521',
            'ssh-ed25519',
          ],
          hmac: ['hmac-sha2-256', 'hmac-sha2-512', 'hmac-sha1'],
        },
        debug: (info) => {
          if (info.includes('Handshake') || info.includes('error')) {
            logger.debug('SSH2 Debug', { info });
          }
        },
      };

      // Add host key verification callback if enabled
      if (this.hostKeyVerification) {
        connConfig.hostVerifier = (hashedKey) => {
          const port = this.config.port || 22;
          const host = this.config.host;

          // Despite the misleading name "hashedKey", ssh2 v1.x passes the RAW
          // public key Buffer here (not a pre-hashed value) when no hostHash
          // option is configured. SHA256 of this buffer matches what
          // ssh-keygen -l -E sha256 and our getHostKeyFingerprint() produce.
          const fingerprint = crypto.createHash('sha256').update(hashedKey).digest('base64');

          // Check MCP fingerprint store first (takes precedence over system known_hosts)
          const storedFingerprint = getStoredFingerprint(host, port);
          if (storedFingerprint) {
            if (storedFingerprint !== fingerprint) {
              logger.error('HOST KEY MISMATCH - possible MITM attack!', {
                host,
                port,
                stored: storedFingerprint,
                received: fingerprint,
              });
              return false;
            }
            logger.info('Host key fingerprint verified', { host, port });
            return true;
          }

          // Fall back to system known_hosts presence check
          if (isHostKnown(host, port)) {
            // Host is in known_hosts - store fingerprint for future verification
            storeFingerprint(host, port, fingerprint);
            logger.info('Host key verified and fingerprint cached', { host, port });
            return true;
          }

          // Unknown host - apply TOFU policy
          if (this.autoAcceptHostKey) {
            logger.info('New host: storing fingerprint (TOFU)', { host, port, fingerprint });
            storeFingerprint(host, port, fingerprint);
            setImmediate(async () => {
              try {
                await addHostKey(host, port);
              } catch (err) {
                logger.warn('Failed to add host key to known_hosts', {
                  host,
                  port,
                  error: err.message,
                });
              }
            });
            return true;
          }

          // autoAcceptHostKey is false - reject unknown host
          logger.error('Unknown host rejected. Enable autoAcceptHostKey or add manually.', {
            host,
            port,
            fingerprint,
          });
          return false;
        };
      }

      // Add authentication (support both keyPath and keypath for compatibility)
      const keyPath = this.config.keyPath || this.config.keypath;
      if (keyPath) {
        const resolvedKeyPath = keyPath.replace('~', os.homedir());
        connConfig.privateKey = fs.readFileSync(resolvedKeyPath);
      } else if (this.config.password) {
        connConfig.password = this.config.password;
      }

      this.client.connect(connConfig);
    });
  }

  async execCommand(command, options = {}) {
    if (!this.connected) {
      throw new Error('Not connected to SSH server');
    }

    const { timeout = 30000, cwd, rawCommand = false } = options;
    const fullCommand = cwd && !rawCommand ? `cd ${escapeShellArg(cwd)} && ${command}` : command;

    return new Promise((resolve, reject) => {
      let stdout = '';
      let stderr = '';
      let completed = false;
      let stream = null;
      let timeoutId = null;

      // Setup timeout first
      if (timeout > 0) {
        timeoutId = setTimeout(() => {
          if (!completed) {
            completed = true;

            // Try multiple ways to kill the stream
            if (stream) {
              try {
                stream.write('\x03'); // Send Ctrl+C
                stream.end();
                stream.destroy();
              } catch (e) {
                // Ignore errors
              }
            }

            // Kill the entire client connection as last resort
            try {
              this.client.end();
              this.connected = false;
            } catch (e) {
              // Ignore errors
            }

            reject(
              new Error(`Command timeout after ${timeout}ms: ${command.substring(0, 100)}...`)
            );
          }
        }, timeout);
      }

      this.client.exec(fullCommand, (err, streamObj) => {
        if (err) {
          completed = true;
          if (timeoutId) clearTimeout(timeoutId);
          reject(err);
          return;
        }

        stream = streamObj;

        stream.on('close', (code, signal) => {
          if (!completed) {
            completed = true;
            if (timeoutId) clearTimeout(timeoutId);
            resolve({
              stdout,
              stderr,
              code: code || 0,
              signal,
            });
          }
        });

        stream.on('data', (data) => {
          stdout += data.toString();
        });

        stream.stderr.on('data', (data) => {
          stderr += data.toString();
        });

        stream.on('error', (err) => {
          if (!completed) {
            completed = true;
            if (timeoutId) clearTimeout(timeoutId);
            reject(err);
          }
        });
      });
    });
  }

  async execCommandStream(command, options = {}) {
    if (!this.connected) {
      throw new Error('Not connected to SSH server');
    }

    const { cwd, onStdout, onStderr } = options;
    const fullCommand = cwd ? `cd ${escapeShellArg(cwd)} && ${command}` : command;

    return new Promise((resolve, reject) => {
      this.client.exec(fullCommand, (err, stream) => {
        if (err) {
          reject(err);
          return;
        }

        let stdout = '';
        let stderr = '';

        stream.on('close', (code, signal) => {
          resolve({
            stdout,
            stderr,
            code: code || 0,
            signal,
            stream,
          });
        });

        stream.on('data', (data) => {
          const chunk = data.toString();
          stdout += chunk;
          if (onStdout) onStdout(chunk);
        });

        stream.stderr.on('data', (data) => {
          const chunk = data.toString();
          stderr += chunk;
          if (onStderr) onStderr(chunk);
        });

        stream.on('error', reject);
      });
    });
  }

  async requestShell(options = {}) {
    if (!this.connected) {
      throw new Error('Not connected to SSH server');
    }

    return new Promise((resolve, reject) => {
      this.client.shell(options, (err, stream) => {
        if (err) {
          reject(err);
          return;
        }
        resolve(stream);
      });
    });
  }

  async getSFTP() {
    if (this.sftp) return this.sftp;

    return new Promise((resolve, reject) => {
      this.client.sftp((err, sftp) => {
        if (err) {
          reject(err);
          return;
        }
        this.sftp = sftp;
        resolve(sftp);
      });
    });
  }

  async resolveHomePath() {
    if (this.cachedHomeDir) {
      return this.cachedHomeDir;
    }

    let homeDir = null;

    // Method 1: Try getent (most reliable)
    try {
      const result = await this.execCommand('getent passwd $USER | cut -d: -f6', {
        timeout: 5000,
        rawCommand: true,
      });
      homeDir = result.stdout.trim();
      if (homeDir && homeDir.startsWith('/')) {
        this.cachedHomeDir = homeDir;
        return homeDir;
      }
    } catch (err) {
      // getent might not be available, try next method
    }

    // Method 2: Try env -i to get clean HOME
    try {
      const result = await this.execCommand('env -i HOME=$HOME bash -c "echo $HOME"', {
        timeout: 5000,
        rawCommand: true,
      });
      homeDir = result.stdout.trim();
      if (homeDir && homeDir.startsWith('/')) {
        this.cachedHomeDir = homeDir;
        return homeDir;
      }
    } catch (err) {
      // env method failed, try next
    }

    // Method 3: Parse /etc/passwd directly
    try {
      const result = await this.execCommand('grep "^$USER:" /etc/passwd | cut -d: -f6', {
        timeout: 5000,
        rawCommand: true,
      });
      homeDir = result.stdout.trim();
      if (homeDir && homeDir.startsWith('/')) {
        this.cachedHomeDir = homeDir;
        return homeDir;
      }
    } catch (err) {
      // /etc/passwd parsing failed, try last resort
    }

    // Method 4: Last resort - try cd ~ && pwd
    try {
      const result = await this.execCommand('cd ~ && pwd', {
        timeout: 5000,
        rawCommand: true,
      });
      homeDir = result.stdout.trim();
      if (homeDir && homeDir.startsWith('/')) {
        this.cachedHomeDir = homeDir;
        return homeDir;
      }
    } catch (err) {
      // All methods failed
    }

    throw new Error('Unable to determine home directory on remote server');
  }

  async putFile(localPath, remotePath) {
    // SFTP doesn't resolve ~ automatically, we need to get the real path
    let resolvedRemotePath = remotePath;
    if (remotePath.includes('~')) {
      try {
        const homeDir = await this.resolveHomePath();
        // Replace ~ with the actual home directory
        // Handle both ~/path and ~ alone
        if (remotePath === '~') {
          resolvedRemotePath = homeDir;
        } else if (remotePath.startsWith('~/')) {
          resolvedRemotePath = homeDir + remotePath.substring(1);
        } else {
          // If ~ is not at the beginning, don't replace it
          resolvedRemotePath = remotePath;
        }
      } catch (err) {
        // If we can't resolve home, throw a more descriptive error
        throw new Error(`Failed to resolve home directory for path: ${remotePath}. ${err.message}`);
      }
    }

    const sftp = await this.getSFTP();
    return new Promise((resolve, reject) => {
      // Check if local file exists and is readable
      if (!fs.existsSync(localPath)) {
        reject(new Error(`Local file does not exist: ${localPath}`));
        return;
      }

      sftp.fastPut(localPath, resolvedRemotePath, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
  }

  async getFile(localPath, remotePath) {
    // SFTP doesn't resolve ~ automatically, we need to get the real path
    let resolvedRemotePath = remotePath;
    if (remotePath.includes('~')) {
      try {
        const homeDir = await this.resolveHomePath();
        // Replace ~ with the actual home directory
        // Handle both ~/path and ~ alone
        if (remotePath === '~') {
          resolvedRemotePath = homeDir;
        } else if (remotePath.startsWith('~/')) {
          resolvedRemotePath = homeDir + remotePath.substring(1);
        } else {
          // If ~ is not at the beginning, don't replace it
          resolvedRemotePath = remotePath;
        }
      } catch (err) {
        // If we can't resolve home, throw a more descriptive error
        throw new Error(`Failed to resolve home directory for path: ${remotePath}. ${err.message}`);
      }
    }

    const sftp = await this.getSFTP();
    return new Promise((resolve, reject) => {
      sftp.fastGet(resolvedRemotePath, localPath, (err) => {
        if (err) reject(err);
        else resolve();
      });
    });
  }

  async putFiles(files, options = {}) {
    const sftp = await this.getSFTP();
    const results = [];

    for (const file of files) {
      try {
        await this.putFile(file.local, file.remote);
        results.push({ ...file, success: true });
      } catch (error) {
        results.push({ ...file, success: false, error: error.message });
        if (options.stopOnError) break;
      }
    }

    return results;
  }

  isConnected() {
    return this.connected && this.client && !this.client.destroyed;
  }

  dispose() {
    if (this.sftp) {
      this.sftp.end();
      this.sftp = null;
    }
    if (this.client) {
      this.client.end();
      this.connected = false;
    }
  }

  async ping() {
    try {
      const result = await this.execCommand('echo "ping"', { timeout: 5000 });
      return result.stdout.trim() === 'ping';
    } catch (error) {
      return false;
    }
  }
}

export default SSHManager;
