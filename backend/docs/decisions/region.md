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

 SWA hostname: https://gentle-rock-06dc31e03.7.azurestaticapps.net  

## Neon Project

Neon project ID: winter-fog-77342787
