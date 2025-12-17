const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');

const DEBUG = process.env.CX_DEBUG_USER_FUNCTION_RESOLUTION === 'true';

function logDebug(message) {
  if (DEBUG) {
    // eslint-disable-next-line no-console
    console.debug(`[cx-wrapper] ${message}`);
  }
}

// Break "module.sub.handler" into the module path and exported symbol chain.
function splitHandlerString(handler) {
  const lastDot = handler.lastIndexOf('.');
  if (lastDot === -1 || lastDot === handler.length - 1) {
    throw new Error(
      `CX handler "${handler}" must be in "module.submodule.handler" format.`
    );
  }
  return [handler.slice(0, lastDot), handler.slice(lastDot + 1)];
}

// Walk the export tree (foo.bar.baz) to grab the final handler reference.
function resolveHandler(userApp, handlerPath) {
  return handlerPath.split('.').reduce((acc, key) => {
    if (acc == null) {
      return undefined;
    }
    return acc[key];
  }, userApp);
}

// Resolve the handler module even if Node's default lookup no longer includes it.
function resolveModuleFile(modulePath) {
  try {
    const resolved = require.resolve(modulePath);
    logDebug(`Resolved handler module via require.resolve: ${resolved}`);
    return resolved;
  } catch (err) {
    if (err?.code !== 'MODULE_NOT_FOUND') {
      throw err;
    }
  }

  const extensions = ['', '.js', '.cjs', '.mjs'];
  for (const ext of extensions) {
    const candidate = modulePath + ext;
    if (fs.existsSync(candidate)) {
      logDebug(`Resolved handler module via fs lookup: ${candidate}`);
      return candidate;
    }
  }

  logDebug(`Falling back to unresolved handler module path: ${modulePath}`);
  return modulePath;
}

// Require the user module, retrying via dynamic import when the file is ESM-only.
async function loadUserModule(resolvedPath) {
  try {
    logDebug(`Attempting to require handler module: ${resolvedPath}`);
    // eslint-disable-next-line global-require, import/no-dynamic-require
    return require(resolvedPath);
  } catch (err) {
    if (err?.code === 'ERR_REQUIRE_ESM') {
      const url = pathToFileURL(resolvedPath).href;
      logDebug(
        `Handler module is ESM. Retrying with dynamic import: ${url} (${err.message})`
      );
      return import(url);
    }
    logDebug(
      `Failed to require handler module (${resolvedPath}): ${err?.message}`
    );
    throw err;
  }
}

// Resolve and return the original Lambda handler function.
async function load(appRoot = process.env.LAMBDA_TASK_ROOT, handlerString) {
  const finalHandler = handlerString ?? process.env.CX_ORIGINAL_HANDLER;
  if (!appRoot) {
    throw new Error('LAMBDA_TASK_ROOT is not defined');
  }
  if (!finalHandler) {
    throw new Error('CX_ORIGINAL_HANDLER is not defined');
  }

  const [modulePath, handlerPath] = splitHandlerString(finalHandler);
  const absoluteModulePath = path.resolve(appRoot, modulePath);
  const resolvedModulePath = resolveModuleFile(absoluteModulePath);
  const userApp = await loadUserModule(resolvedModulePath);
  const handler = resolveHandler(userApp, handlerPath);

  if (typeof handler !== 'function') {
    throw new Error(
      `Handler "${finalHandler}" resolved to "${handler}" instead of a function`
    );
  }

  logDebug(`Successfully loaded handler ${finalHandler}`);
  return handler;
}

module.exports = { load };
