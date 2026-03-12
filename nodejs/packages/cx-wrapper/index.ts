import { diag, DiagConsoleLogger, DiagLogLevel } from '@opentelemetry/api';

// configure lambda logging (before we load libraries that might log)
const envLogLevel = process.env.OTEL_LOG_LEVEL?.toUpperCase();
const diagLogLevel =
  envLogLevel && envLogLevel in DiagLogLevel
    ? (DiagLogLevel[envLogLevel as keyof typeof DiagLogLevel] as DiagLogLevel)
    : undefined;
diag.setLogger(new DiagConsoleLogger(), diagLogLevel);

import { Callback, Context } from 'aws-lambda';
import { Handler } from 'aws-lambda/handler.js';
import { load } from './loader.js';
import { initializeInstrumentations } from './instrumentation-init.js';
import { initializeProvider } from './provider-init.js';
import { makeLambdaInstrumentation } from './lambda-instrumentation-init.js';
import { parseBooleanEnvvar } from './common.js';

const instrumentations = initializeInstrumentations();
const tracerProvider = initializeProvider(instrumentations);
const lambdaInstrumentation = makeLambdaInstrumentation();

if (process.env.CX_ORIGINAL_HANDLER === undefined)
  throw Error('CX_ORIGINAL_HANDLER is missing');

// We want user code to get initialized during lambda init phase
try {
  (async () => {
    diag.debug(`Initialization: Loading original handler ${process.env.CX_ORIGINAL_HANDLER}`);
    await load(
      process.env.LAMBDA_TASK_ROOT,
      process.env.CX_ORIGINAL_HANDLER
    );
    diag.debug(`Initialization: Original handler loaded`);
  })();
} catch (e) {}

if (parseBooleanEnvvar("OTEL_WARM_UP_EXPORTER") ?? true) {
  // We want exporter code to get initialized during lambda init phase
  try {
    (async () => {
      try {
        diag.debug(`Initialization: warming up exporter`);
        const warmupSpan = tracerProvider.getTracer('cx-wrapper').startSpan('warmup');
        warmupSpan.setAttribute('cx.internal.span.role', 'warmup');
        warmupSpan.end();
        await tracerProvider.forceFlush();
        diag.debug(`Initialization: exporter warmed up`);
      } catch (e) {
        // The export may fail with timeout if the lambda instance gets frozen between init and the first invocation. We don't really care about that failure.
        // diag.error(`Initialization: exporter warmup failed: ${e}`);
      }
    })();
  } catch (e) {}
}

async function invokePatchedHandler(
  patchedHandler: Handler,
  event: any,
  context: Context
) {
  // Handlers that declare a callback parameter should only resolve via that callback;
  // short‑circuiting their returned promise causes API Gateway to receive `undefined`.
  const expectsCallback = patchedHandler.length >= 3;

  return new Promise((resolve, reject) => {
    let settled = false;
    const wrappedCallback: Callback = (err, result) => {
      if (settled) {
        return;
      }
      settled = true;
      if (err) {
        reject(err);
      } else {
        resolve(result);
      }
    };

    try {
      const maybePromise = patchedHandler(event, context, wrappedCallback);
      if (
        maybePromise &&
        typeof (maybePromise as Promise<unknown>).then === 'function'
      ) {
        (maybePromise as Promise<unknown>).then(
          value => {
            if (!settled && !expectsCallback) {
              settled = true;
              resolve(value);
            }
          },
          err => {
            if (!settled) {
              settled = true;
              reject(err);
            }
          }
        );
      } else if (!expectsCallback) {
        settled = true;
        resolve(maybePromise);
      }
    } catch (err) {
      if (!settled) {
        settled = true;
        reject(err);
      }
    }
  });
}

export const handler = async (event: any, context: Context) => {
  diag.debug(`Loading original handler ${process.env.CX_ORIGINAL_HANDLER}`);
  try {
    const originalHandler = await load(
      process.env.LAMBDA_TASK_ROOT,
      process.env.CX_ORIGINAL_HANDLER
    );

    diag.debug(`Instrumenting handler`);
    const patchedHandler = lambdaInstrumentation.getPatchHandler(
      originalHandler
    ) as unknown as Handler;
    diag.debug(
      `Running CX handler and redirecting to ${process.env.CX_ORIGINAL_HANDLER}`
    );
    return await invokePatchedHandler(patchedHandler, event, context);
  } catch (err) {
    context.callbackWaitsForEmptyEventLoop = false;
    diag.error('CX handler failed to execute', err as Error);
    throw err;
  }
};

diag.debug('OpenTelemetry instrumentation is ready');
