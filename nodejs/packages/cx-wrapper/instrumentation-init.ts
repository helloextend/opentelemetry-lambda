import { diag, Span } from '@opentelemetry/api';
import { Instrumentation, registerInstrumentations } from '@opentelemetry/instrumentation';
import { NormalizedResponse, AwsSdkRequestHookInformation, AwsSdkResponseHookInformation } from '@opentelemetry/instrumentation-aws-sdk';
import { OTEL_PAYLOAD_SIZE_LIMIT, OtelAttributes, parseBooleanEnvvar } from './common';
import { RequestOptions } from 'http';

declare global {
  function configureInstrumentations(): Instrumentation[]
}

export function initializeInstrumentations(): any[] {
  diag.debug('Initializing OpenTelemetry instrumentations');
  const instrumentations = (typeof configureInstrumentations === 'function' ? configureInstrumentations: defaultConfigureInstrumentations)();
  // Register instrumentations synchronously to ensure code is patched even before provider is ready.
  registerInstrumentations({instrumentations});
  return instrumentations;
}

function defaultConfigureInstrumentations(): Instrumentation[] {
  // Use require statements for instrumentation to avoid having to have transitive dependencies on all the typescript
  // definitions.
  const instrumentations: Instrumentation[] = [];

  const defaults = parseBooleanEnvvar("OTEL_INSTRUMENTATION_COMMON_DEFAULT_ENABLED") ?? true;

  if (parseBooleanEnvvar("OTEL_INSTRUMENTATION_HTTP_ENABLED") ?? defaults) {
    const { HttpInstrumentation } = require('@opentelemetry/instrumentation-http');
    instrumentations.push(new HttpInstrumentation({
      ignoreOutgoingRequestHook: (request: RequestOptions) =>
        request.hostname === "localhost" && Number(request.port) === 4318,
    }));
  }

  if (parseBooleanEnvvar("OTEL_INSTRUMENTATION_UNDICI_ENABLED") ?? defaults) {
    const { UndiciInstrumentation } = require('@opentelemetry/instrumentation-undici');
    instrumentations.push(new UndiciInstrumentation());
  }

  if (parseBooleanEnvvar("OTEL_INSTRUMENTATION_AWS_SDK_ENABLED") ?? defaults) {
    const { AwsInstrumentation } = require('@opentelemetry/instrumentation-aws-sdk');
    instrumentations.push(new AwsInstrumentation({
      suppressInternalInstrumentation: true,
      preRequestHook: (span: Span, { request }: AwsSdkRequestHookInformation) => {
        diag.debug(`preRequestHook for ${request.serviceName}.${request.commandName}`)

        const data = JSON.stringify(request.commandInput);
        if (data !== undefined) {
          span.setAttribute(
            OtelAttributes.RPC_REQUEST_PAYLOAD,
            data.substring(0, OTEL_PAYLOAD_SIZE_LIMIT)
          );
        }
      },
      responseHook: (span: Span, { response } : AwsSdkResponseHookInformation) => {
        diag.debug(`responseHook for ${response.request.serviceName}.${response.request.commandName}`)
        if (response.request.serviceName === 'S3') {
          if ('buckets' in response && Array.isArray(response.buckets)) {
            setResponsePayloadAttribute(span, JSON.stringify(response.buckets.map(b => b.Name)))
          } else if ('contents' in response && Array.isArray(response.contents)) {
            setResponsePayloadAttribute(span, JSON.stringify(response.contents.map(b => b.Key)))
          } else if ('data' in response && typeof response.data === 'object') {
            // data is too large and it contains cycles
          } else {
            const payload = responseDataToString(response)
            setResponsePayloadAttribute(span, payload)
          }
        } else {
          const payload = responseDataToString(response)
          setResponsePayloadAttribute(span, payload)
        }
      },
    }))
  }

  return instrumentations;
}

function responseDataToString(response: NormalizedResponse): string {
  return 'data' in response && typeof response.data === 'object'
    ? JSON.stringify(response.data)
    : response?.data?.toString();
}

function setResponsePayloadAttribute(span: Span, payload: string | undefined) {
  if (payload !== undefined) {
    span.setAttribute(
      OtelAttributes.RPC_RESPONSE_PAYLOAD,
      payload.substring(0, OTEL_PAYLOAD_SIZE_LIMIT)
    );
  }
}
