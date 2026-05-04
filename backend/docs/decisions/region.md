# Region Decision — Voxio Telemetry Backend

**Status:** Decided (immutable)
**Date:** 2026-05-04

## Decision

| Resource | Region |
|---|---|
| Azure Static Web Apps | West Europe |
| Neon Postgres project | aws-eu-central-1 |

## Why this is immutable

The Neon project region cannot be changed after creation without recreating the project and losing all data. The SWA region is tightly coupled to the Neon region for latency reasons. Do not change either without a full data migration plan.

## SWA Hostname

*(Record here after T-4103 is complete)*

## Neon Project

*(Record connection string location and project name here after T-4104 is complete)*
