# TDD for X-Road

Red → Green → Refactor. Write the failing test first; let it define "done". Naive-correct before optimized.

## Test pyramid (bottom = many/fast, top = few/slow)

1. **Unit** — business logic in the consumer/provider information system. No network. Milliseconds.
2. **Contract** — validate request/response against the OpenAPI 3 spec (REST) or WSDL (SOAP).
   Provider: every response conforms to the published schema. Consumer: requests match what the provider expects.
   This is the X-Road equivalent of consumer-driven contract testing; the OpenAPI/WSDL *is* the contract.
3. **Integration** — call through a real Security Server in the local sandbox (see `sandbox.md`).
   Assert routing works, `X-Road-Client` is honored, ACL grants/denies as configured, and the message log records the exchange.
4. **End-to-end** — full Docker ecosystem: consumer IS → SS2 → SS3 → provider IS, with the test CA, OCSP, and timestamping live.

## What to assert that is X-Road specific

- Identifier correctness in headers and URLs (see `stack.md`).
- `X-Road-Request-Id` and `X-Road-Request-Hash` are present on responses.
- An **unauthorized** subsystem is rejected (ACL denies) — negative tests are mandatory for zero trust.
- OCSP-revoked or expired certificate paths fail closed, not open.
- The message log produces a signed, timestamped ASiC-E container for each exchange.

## Speed strategy

- Mock the Security Server (HTTP stub returning canned X-Road headers) for layers 1–2 so the suite stays fast.
- Reserve the `xrdsst`-provisioned sandbox for layers 3–4, ideally spun up once per CI job.
- Make the sandbox reproducible (declarative `xrdsst apply`) so integration tests are deterministic.

## Loop discipline

Per task: write test → watch it fail for the right reason → implement minimum to pass → refactor → repeat.
Do not advance to the next behavior while a test is red for the wrong reason.
