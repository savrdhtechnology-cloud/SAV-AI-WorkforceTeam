import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const service = readFileSync(new URL("../app/crm/tasks/task-service.ts", import.meta.url), "utf8");
const types = readFileSync(new URL("../app/crm/tasks/task-types.ts", import.meta.url), "utf8");
const view = readFileSync(new URL("../app/crm/tasks/TasksView.tsx", import.meta.url), "utf8");
const migration = readFileSync(new URL("../supabase/migrations/20261002_tasks_followup_module.sql", import.meta.url), "utf8");

test("task service exposes the complete controlled RPC surface", () => {
  for (const rpc of [
    "sav_ai_crm_task_context",
    "sav_ai_crm_list_tasks",
    "sav_ai_crm_task_detail",
    "sav_ai_crm_create_task",
    "sav_ai_crm_update_task",
    "sav_ai_crm_set_task_status",
    "sav_ai_crm_archive_task",
    "sav_ai_crm_delete_task",
    "sav_ai_crm_agent_task_action",
  ]) {
    assert.match(service, new RegExp(rpc));
    assert.match(migration, new RegExp(rpc));
  }
});

test("tasks support both lead and customer relations", () => {
  assert.match(types, /contactId: string/);
  assert.match(service, /p_contact_id: draft\.contactId/);
  assert.match(view, /Related customer/);
  assert.match(migration, /p_contact_id uuid default null/);
  assert.match(migration, /Related customer is outside this workspace/);
});

test("agent actions trust server controlled app metadata, not user metadata", () => {
  assert.match(migration, /auth\.jwt\(\)->'app_metadata'->>'sav_ai_agent_id'/);
  assert.doesNotMatch(migration, /user_metadata[^\n]*sav_ai_agent_id/);
});

test("task mutation RPCs are not granted to anonymous callers", () => {
  assert.match(migration, /revoke all on function public\.sav_ai_crm_create_task[\s\S]*from public, anon/);
  assert.match(migration, /grant execute on function public\.sav_ai_crm_create_task[\s\S]*to authenticated/);
  assert.match(migration, /Permanent task deletion requires owner or admin permission/);
});

test("task UI includes required operational views and states", () => {
  for (const label of ["Overdue", "Today", "Upcoming", "Completed", "New Task", "Activity history"]) {
    assert.match(view, new RegExp(label));
  }
  assert.match(view, /Loading tasks/);
  assert.match(view, /No tasks in this view/);
  assert.match(view, /reminder due/);
});
