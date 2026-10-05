# ADR-001: Local-first web architecture

## Status

Accepted — 2026-08-29

## Context

The native macOS application stores research projects locally and exports a
portable `AnalysisProject` JSON document. The former browser prototype used a
different, lossy `localStorage` model and static sample content, which made it
impossible to move real work safely between the two applications.

## Decision

The web application is a TypeScript/React client with a repository boundary
backed by IndexedDB. Each project is an independent record and its payload is
validated against the native JSON contract before import, persistence, and
export. Native JSON and ZIP backups remain the interchange format.

No OpenAI API key is accepted or stored by the browser client. A same-origin
local server gateway reads the key from the native application's macOS Keychain
entry (with a one-time legacy preference fallback) or from the server-only
`OPENAI_API_KEY` environment variable. It sends an explicitly selected audio
file to OpenAI's transcription endpoint and returns only diarized segments to
the browser. A future shared service can replace the local gateway and IndexedDB
repository without changing the domain model or screens.

## Consequences

- The web app works offline and does not upload research data implicitly.
- Browser and native projects can be exchanged without schema translation.
- Static sample counts, quotes, themes, and maps are prohibited; every analytic
  view is derived from the persisted project.
- Audio transcription is explicit and same-origin; credentials never enter the
  browser bundle, IndexedDB project, or backup.
- Multi-device synchronization still requires an authenticated remote
  repository and is not simulated client-side.
