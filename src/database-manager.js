/**
 * Database Manager for MCP SSH Manager
 * Provides database operations for MySQL, PostgreSQL, and MongoDB
 */

// ──────────────────────────────────────────────────────────────
// Credential-safe command wrappers
// ──────────────────────────────────────────────────────────────

/**
 * Escape a string for embedding inside single quotes in shell.
 */
function shellSingleQuote(s) {
  return "'" + s.replace(/'/g, "'\\''") + "'";
}

/**
 * Escape a MySQL identifier (database/table name) for backtick quoting.
 * Prevents SQL injection when names are embedded in inline SQL strings.
 */
function escapeMySQLIdentifier(name) {
  return '`' + name.replace(/`/g, '``') + '`';
}

/**
 * Escape a string literal for safe embedding in SQL single quotes.
 * Uses standard SQL escape doubling of single quotes (works in both MySQL and PostgreSQL).
 */
function escapeSQLStringLiteral(s) {
  return "'" + s.replace(/'/g, "''") + "'";
}

/**
 * Escape a field for use in a PostgreSQL .pgpass file.
 * pgpass fields use ':' as separator; backslash-escape ':' and '\'.
 */
function escapePgPassField(s) {
  return s.replace(/\\/g, '\\\\').replace(/:/g, '\\:');
}

/**
 * Wrap a MySQL/mysqldump/mysql client command with a temp credentials file.
 * Avoids exposing the password in `ps aux` output.
 * The `toolCmd` must NOT already include a -p or --password flag.
 *
 * Uses `trap` for cleanup so it works correctly with pipes and on failure.
 */
function withMySQLCredFile(password, toolCmd) {
  const escapedPass = shellSingleQuote(password);
  // Insert --defaults-extra-file right after the tool name (first word).
  // Use indexOf to preserve any multi-space sequences in the rest of the command.
  const spaceIdx = toolCmd.indexOf(' ');
  const wrappedCmd =
    spaceIdx >= 0
      ? `${toolCmd.slice(0, spaceIdx)} --defaults-extra-file="$MCPTMPF" ${toolCmd.slice(spaceIdx + 1)}`
      : `${toolCmd} --defaults-extra-file="$MCPTMPF"`;
  return [
    `MCPTMPF=$(mktemp /tmp/.mcp_my_XXXXXX)`,
    `chmod 600 "$MCPTMPF"`,
    `printf '[client]\\npassword=%s\\n' ${escapedPass} > "$MCPTMPF"`,
    `trap 'rm -f "$MCPTMPF"' EXIT INT TERM`,
    wrappedCmd,
  ].join('; ');
}

/**
 * Wrap a PostgreSQL command with a temp .pgpass file.
 * Uses PGPASSFILE to avoid exposing the password in `ps aux` or /proc/self/environ.
 * The `toolCmd` must NOT already include a PGPASSWORD/PGPASSFILE prefix.
 *
 * Uses `trap` for cleanup so it works correctly with pipes and on failure.
 */
function withPGPassFile(host, port, database, user, password, toolCmd) {
  const pgpassEntry = [host, String(port), database, user, password]
    .map(escapePgPassField)
    .join(':');
  const escapedEntry = shellSingleQuote(pgpassEntry);
  return [
    `MCPTMPF=$(mktemp /tmp/.mcp_pg_XXXXXX)`,
    `chmod 600 "$MCPTMPF"`,
    `printf '%s\\n' ${escapedEntry} > "$MCPTMPF"`,
    `trap 'rm -f "$MCPTMPF"' EXIT INT TERM`,
    `PGPASSFILE="$MCPTMPF" ${toolCmd}`,
  ].join('; ');
}

/**
 * Build a MongoDB URI connection string.
 * Using URI keeps credentials out of individual --password flags visible in `ps aux`.
 */
function buildMongoURI(host, port, user, password, database = '') {
  const encodedUser = encodeURIComponent(user);
  const encodedPass = encodeURIComponent(password);
  const db = database ? `/${database}` : '';
  return `mongodb://${encodedUser}:${encodedPass}@${host}:${port}${db}`;
}

// Supported database types
export const DB_TYPES = {
  MYSQL: 'mysql',
  POSTGRESQL: 'postgresql',
  MONGODB: 'mongodb',
};

// Default ports
export const DB_PORTS = {
  mysql: 3306,
  postgresql: 5432,
  mongodb: 27017,
};

/**
 * Build MySQL dump command
 */
export function buildMySQLDumpCommand(options) {
  const {
    database,
    user,
    password,
    host = 'localhost',
    port = 3306,
    outputFile,
    compress = true,
    tables = null,
  } = options;

  let base = 'mysqldump';
  if (user) base += ` -u${user}`;
  if (host) base += ` -h ${host}`;
  if (port) base += ` -P ${port}`;
  base += ' --single-transaction --routines --triggers';
  base += ` ${database}`;
  if (tables && Array.isArray(tables)) base += ` ${tables.join(' ')}`;
  if (compress) {
    base += ` | gzip > "${outputFile}"`;
  } else {
    base += ` > "${outputFile}"`;
  }

  return password ? withMySQLCredFile(password, base) : base;
}

/**
 * Build PostgreSQL dump command
 */
export function buildPostgreSQLDumpCommand(options) {
  const {
    database,
    user,
    password,
    host = 'localhost',
    port = 5432,
    outputFile,
    compress = true,
    tables = null,
  } = options;

  let base = 'pg_dump';
  if (user) base += ` -U ${user}`;
  if (host) base += ` -h ${host}`;
  if (port) base += ` -p ${port}`;
  base += ' --format=custom --clean --if-exists';
  if (tables && Array.isArray(tables)) {
    for (const table of tables) base += ` -t ${table}`;
  }
  base += ` ${database}`;
  if (compress) {
    base += ` | gzip > "${outputFile}"`;
  } else {
    base += ` > "${outputFile}"`;
  }

  return password ? withPGPassFile(host, port, database, user, password, base) : base;
}

/**
 * Build MongoDB dump command
 * Note: mongodump URI puts credentials in command args; this is the MongoDB-standard approach.
 */
export function buildMongoDBDumpCommand(options) {
  const {
    database,
    user,
    password,
    host = 'localhost',
    port = 27017,
    outputDir,
    compress = true,
    collections = null,
  } = options;

  let command = 'mongodump';
  if (user && password) {
    command += ` --uri ${shellSingleQuote(buildMongoURI(host, port, user, password, database))}`;
  } else {
    if (host) command += ` --host ${host}`;
    if (port) command += ` --port ${port}`;
    if (database) command += ` --db ${database}`;
  }

  if (collections && Array.isArray(collections)) {
    for (const collection of collections) command += ` --collection ${collection}`;
  }
  command += ` --out "${outputDir}"`;

  if (compress) {
    command += ` && tar -czf "${outputDir}.tar.gz" -C "$(dirname ${outputDir})" "$(basename ${outputDir})"`;
    command += ` && rm -rf "${outputDir}"`;
  }

  return command;
}

/**
 * Build MySQL import command
 */
export function buildMySQLImportCommand(options) {
  const { database, user, password, host = 'localhost', port = 3306, inputFile } = options;

  const prefix = inputFile.endsWith('.gz')
    ? `gunzip -c "${inputFile}" | `
    : `cat "${inputFile}" | `;

  let base = 'mysql';
  if (user) base += ` -u${user}`;
  if (host) base += ` -h ${host}`;
  if (port) base += ` -P ${port}`;
  base += ` ${database}`;

  const mysqlCmd = password ? withMySQLCredFile(password, base) : base;
  return `${prefix}${mysqlCmd}`;
}

/**
 * Build PostgreSQL import command
 */
export function buildPostgreSQLImportCommand(options) {
  const { database, user, password, host = 'localhost', port = 5432, inputFile } = options;

  let base = 'pg_restore';
  if (user) base += ` -U ${user}`;
  if (host) base += ` -h ${host}`;
  if (port) base += ` -p ${port}`;
  base += ' --clean --if-exists';
  base += ` -d ${database}`;

  const pgCmd = password ? withPGPassFile(host, port, database, user, password, base) : base;

  if (inputFile.endsWith('.gz')) {
    return `gunzip -c "${inputFile}" | ${pgCmd}`;
  }
  return `${pgCmd} "${inputFile}"`;
}

/**
 * Build MongoDB restore command
 */
export function buildMongoDBRestoreCommand(options) {
  const {
    database,
    user,
    password,
    host = 'localhost',
    port = 27017,
    inputPath,
    drop = true,
  } = options;

  const uriFlag =
    user && password
      ? `--uri ${shellSingleQuote(buildMongoURI(host, port, user, password, database))}`
      : `--host ${host} --port ${port}`;

  if (inputPath.endsWith('.tar.gz')) {
    const extractDir = inputPath.slice(0, -'.tar.gz'.length);
    return (
      `tar -xzf "${inputPath}" -C "$(dirname ${inputPath})" && ` +
      `mongorestore ${drop ? '--drop ' : ''}${uriFlag} "${extractDir}"` +
      ` && rm -rf "${extractDir}"`
    );
  }

  return `mongorestore ${drop ? '--drop ' : ''}${uriFlag} "${inputPath}"`;
}

/**
 * Build MySQL list databases command
 */
export function buildMySQLListDatabasesCommand(options) {
  const { user, password, host = 'localhost', port = 3306 } = options;

  let base = 'mysql';
  if (user) base += ` -u${user}`;
  if (host) base += ` -h ${host}`;
  if (port) base += ` -P ${port}`;
  base += ' -e "SHOW DATABASES;" | tail -n +2';

  return password ? withMySQLCredFile(password, base) : base;
}

/**
 * Build MySQL list tables command
 */
export function buildMySQLListTablesCommand(options) {
  const { database, user, password, host = 'localhost', port = 3306 } = options;

  let base = 'mysql';
  if (user) base += ` -u${user}`;
  if (host) base += ` -h ${host}`;
  if (port) base += ` -P ${port}`;
  base += ` -e "USE ${escapeMySQLIdentifier(database)}; SHOW TABLES;" | tail -n +2`;

  return password ? withMySQLCredFile(password, base) : base;
}

/**
 * Build PostgreSQL list databases command
 */
export function buildPostgreSQLListDatabasesCommand(options) {
  const { user, password, host = 'localhost', port = 5432 } = options;

  let base = 'psql';
  if (user) base += ` -U ${user}`;
  if (host) base += ` -h ${host}`;
  if (port) base += ` -p ${port}`;
  base +=
    " -t -c \"SELECT datname FROM pg_database WHERE datistemplate = false;\" | sed '/^$/d' | sed 's/^[ \\t]*//'";

  return password ? withPGPassFile(host, port, '*', user, password, base) : base;
}

/**
 * Build PostgreSQL list tables command
 */
export function buildPostgreSQLListTablesCommand(options) {
  const { database, user, password, host = 'localhost', port = 5432 } = options;

  let base = 'psql';
  if (user) base += ` -U ${user}`;
  if (host) base += ` -h ${host}`;
  if (port) base += ` -p ${port}`;
  base += ` -d ${database}`;
  base +=
    " -t -c \"SELECT tablename FROM pg_tables WHERE schemaname = 'public';\" | sed '/^$/d' | sed 's/^[ \\t]*//'";

  return password ? withPGPassFile(host, port, database, user, password, base) : base;
}

/**
 * Build MongoDB list databases command
 */
export function buildMongoDBListDatabasesCommand(options) {
  const { user, password, host = 'localhost', port = 27017 } = options;

  let command = 'mongo';
  if (user && password) {
    command += ` --uri ${shellSingleQuote(buildMongoURI(host, port, user, password, 'admin'))}`;
  } else {
    if (host) command += ` --host ${host}`;
    if (port) command += ` --port ${port}`;
  }
  command +=
    ' --quiet --eval "db.adminCommand(\'listDatabases\').databases.forEach(function(d){print(d.name)})"';

  return command;
}

/**
 * Build MongoDB list collections command
 */
export function buildMongoDBListCollectionsCommand(options) {
  const { database, user, password, host = 'localhost', port = 27017 } = options;

  let command = 'mongo';
  if (user && password) {
    command += ` --uri ${shellSingleQuote(buildMongoURI(host, port, user, password, database))}`;
  } else {
    if (host) command += ` --host ${host}`;
    if (port) command += ` --port ${port}`;
    command += ` ${database}`;
  }
  command += ' --quiet --eval "db.getCollectionNames().forEach(function(c){print(c)})"';

  return command;
}

/**
 * Build MySQL query command (SELECT only)
 */
export function buildMySQLQueryCommand(options) {
  const {
    database,
    query,
    user,
    password,
    host = 'localhost',
    port = 3306,
    format = 'json',
  } = options;

  if (!isSafeQuery(query)) {
    throw new Error('Only SELECT queries are allowed');
  }

  let base = 'mysql';
  if (user) base += ` -u${user}`;
  if (host) base += ` -h ${host}`;
  if (port) base += ` -P ${port}`;
  base += ` ${database}`;

  if (format === 'json') {
    base += ` -e "${query}" --batch --skip-column-names | awk 'BEGIN{print "["} {if(NR>1)print ","; printf "{\\"row\\":%d,\\"data\\":\\"%s\\"}", NR, $0} END{print "]"}'`;
  } else {
    base += ` -e "${query}"`;
  }

  return password ? withMySQLCredFile(password, base) : base;
}

/**
 * Build PostgreSQL query command (SELECT only)
 */
export function buildPostgreSQLQueryCommand(options) {
  const { database, query, user, password, host = 'localhost', port = 5432 } = options;

  if (!isSafeQuery(query)) {
    throw new Error('Only SELECT queries are allowed');
  }

  let base = 'psql';
  if (user) base += ` -U ${user}`;
  if (host) base += ` -h ${host}`;
  if (port) base += ` -p ${port}`;
  base += ` -d ${database}`;
  base += ` -c "${query}"`;

  return password ? withPGPassFile(host, port, database, user, password, base) : base;
}

/**
 * Build MongoDB query command
 */
export function buildMongoDBQueryCommand(options) {
  const { database, collection, query, user, password, host = 'localhost', port = 27017 } = options;

  let command = 'mongo';
  if (user && password) {
    command += ` --uri ${shellSingleQuote(buildMongoURI(host, port, user, password, database))}`;
  } else {
    if (host) command += ` --host ${host}`;
    if (port) command += ` --port ${port}`;
    command += ` ${database}`;
  }
  command += ` --quiet --eval "db.${collection}.find(${query || '{}'}).forEach(printjson)"`;

  return command;
}

/**
 * Validate query is safe (SELECT only, no multi-statements, word-boundary checks)
 */
export function isSafeQuery(query) {
  const trimmed = query.trim();

  // Must start with SELECT (word boundary)
  if (!/^SELECT\s/i.test(trimmed)) {
    return false;
  }

  // Block multi-statements: semicolon followed by non-whitespace
  if (/;\s*\S/.test(trimmed)) {
    return false;
  }

  // Block dangerous keywords using word boundaries to avoid false positives on column names
  // UNION is blocked to prevent data-exfiltration via UNION-based injection.
  // INTO is blocked to prevent SELECT INTO FILE attacks.
  if (
    /\b(INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE|GRANT|REVOKE|EXEC|EXECUTE|UNION|INTO)\b/i.test(
      trimmed
    )
  ) {
    return false;
  }

  return true;
}

/**
 * Parse database list output
 */
export function parseDatabaseList(output, type) {
  const lines = output
    .trim()
    .split('\n')
    .filter((l) => l.trim());

  // Filter out system databases
  return lines.filter((db) => {
    const dbLower = db.toLowerCase();
    if (type === DB_TYPES.MYSQL) {
      return !['information_schema', 'performance_schema', 'mysql', 'sys'].includes(dbLower);
    } else if (type === DB_TYPES.POSTGRESQL) {
      return !['template0', 'template1', 'postgres'].includes(dbLower);
    } else if (type === DB_TYPES.MONGODB) {
      return !['admin', 'config', 'local'].includes(dbLower);
    }
    return true;
  });
}

/**
 * Parse table/collection list output
 */
export function parseTableList(output) {
  return output
    .trim()
    .split('\n')
    .filter((l) => l.trim());
}

/**
 * Estimate dump size command
 */
export function buildEstimateSizeCommand(type, database, options = {}) {
  const { user, password, host = 'localhost', port } = options;
  const effectivePort = port || DB_PORTS[type];

  switch (type) {
    case DB_TYPES.MYSQL: {
      let base = 'mysql';
      if (user) base += ` -u${user}`;
      if (host) base += ` -h ${host}`;
      if (effectivePort) base += ` -P ${effectivePort}`;
      base += ` -e "SELECT SUM(data_length + index_length) FROM information_schema.TABLES WHERE table_schema=${escapeSQLStringLiteral(database)};" | tail -n 1`;
      return password ? withMySQLCredFile(password, base) : base;
    }

    case DB_TYPES.POSTGRESQL: {
      let base = 'psql';
      if (user) base += ` -U ${user}`;
      if (host) base += ` -h ${host}`;
      if (effectivePort) base += ` -p ${effectivePort}`;
      base += ` -d ${database}`;
      base += ` -t -c "SELECT pg_database_size(${escapeSQLStringLiteral(database)});" | sed 's/^[ \\t]*//'`;
      return password ? withPGPassFile(host, effectivePort, database, user, password, base) : base;
    }

    case DB_TYPES.MONGODB: {
      let command = 'mongo';
      if (user && password) {
        command += ` --uri ${shellSingleQuote(buildMongoURI(host, effectivePort, user, password, database))}`;
      } else {
        if (host) command += ` --host ${host}`;
        if (effectivePort) command += ` --port ${effectivePort}`;
        command += ` ${database}`;
      }
      command += ' --quiet --eval "db.stats().dataSize"';
      return command;
    }

    default:
      throw new Error(`Unknown database type: ${type}`);
  }
}

/**
 * Parse size output to bytes
 */
export function parseSize(output) {
  const size = parseInt(output.trim());
  return isNaN(size) ? 0 : size;
}

/**
 * Format bytes to human readable
 */
export function formatBytes(bytes) {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

/**
 * Get database connection info
 */
export function getConnectionInfo(type, options) {
  const { host = 'localhost', port, user, database } = options;
  const defaultPort = DB_PORTS[type];

  return {
    type,
    host,
    port: port || defaultPort,
    user: user || 'default',
    database: database || 'all',
  };
}
