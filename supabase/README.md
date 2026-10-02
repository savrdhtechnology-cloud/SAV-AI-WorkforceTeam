# SAV AI CRM database migrations

This directory tracks database changes required by the CRM UI.

## Current environment

The live CRM currently points to the **Savrdh Technology** Supabase project and uses the isolated `sav_ai_crm` schema. The existing foundation migrations are already present in the hosted database, but they were created before this repository started tracking migrations.

## Tasks / Follow-up migration

`migrations/20261002_tasks_followup_module.sql` extends the existing Tasks foundation with:

- follow-up type, notes, reminders, archive and updated timestamps
- human and AI-agent assignment
- task activity linkage and history
- overdue/today/upcoming/completed queries
- search/filter/sort support
- workspace and role validation
- create/update/status/archive/delete RPCs
- reminder query boundary
- authenticated future AI-agent task action boundary using server-controlled `app_metadata`
- audit log entries for task mutations

### Important

This migration is **prepared but intentionally not applied to production**. Apply only after the feature branch passes build/type verification and hosted end-to-end testing.

The current production database must not be modified merely to make the UI appear functional. The UI should surface RPC errors until the migration is explicitly approved and applied.
