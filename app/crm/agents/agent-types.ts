export const AGENT_STATUSES = ["active","paused","disabled","error"] as const;
export type AgentStatus = typeof AGENT_STATUSES[number];

export const RISK_LEVELS = ["low","medium","high","critical"] as const;
export type RiskLevel = typeof RISK_LEVELS[number];

export const EXECUTION_STATES = ["queued","running","waiting_approval","completed","failed","cancelled"] as const;
export type ExecutionState = typeof EXECUTION_STATES[number];

export const CAPABILITIES = [
  "READ_LEAD","UPDATE_LEAD","CREATE_TASK","UPDATE_TASK","CREATE_FOLLOWUP",
  "READ_CONVERSATION","SEND_MESSAGE","CREATE_NOTE","CREATE_ESCALATION",
  "ASSIGN_TASK","READ_KNOWLEDGE","SUMMARIZE_CONVERSATION",
  "DELETE_LEAD","PERMANENT_DELETE_TASK","FINANCIAL_ACTION","CHANGE_PERMISSION","SEND_BULK_MESSAGE"
] as const;
export type AgentCapability = typeof CAPABILITIES[number];

export type AgentRecord = {
  id:string;
  workspace_id?:string;
  name:string;
  slug:string;
  display_name:string;
  role_name:string;
  description:string|null;
  status:AgentStatus;
  avatar_icon:string|null;
  channels:string[];
  autonomy_level:string;
  approval_required:boolean;
  capabilities:string[];
  allowed_actions:string[];
  knowledge_scopes:string[];
  workflow_access:string[];
  task_permissions:string[];
  escalation_rules:Record<string,unknown>;
  working_hours:Record<string,unknown>;
  daily_limits:Record<string,unknown>;
  confidence_threshold:number;
  configuration:Record<string,unknown>;
  created_at:string;
  updated_at:string;
};

export type AgentExecution = {
  id:string;
  agent_id:string;
  command:string;
  input:Record<string,unknown>;
  planned_action:Record<string,unknown>|null;
  approval_status:string|null;
  execution_status:ExecutionState;
  output:Record<string,unknown>|null;
  error:string|null;
  started_at:string|null;
  completed_at:string|null;
  created_at:string;
};

export type AgentActionRequest = {
  agentId:string;
  action:AgentCapability;
  target:{ type:string; id?:string|null };
  payload?:Record<string,unknown>;
};

export const ACTION_RISK: Record<AgentCapability,RiskLevel> = {
  READ_LEAD:"low",
  UPDATE_LEAD:"medium",
  CREATE_TASK:"low",
  UPDATE_TASK:"medium",
  CREATE_FOLLOWUP:"medium",
  READ_CONVERSATION:"low",
  SEND_MESSAGE:"high",
  CREATE_NOTE:"low",
  CREATE_ESCALATION:"low",
  ASSIGN_TASK:"medium",
  READ_KNOWLEDGE:"low",
  SUMMARIZE_CONVERSATION:"low",
  DELETE_LEAD:"critical",
  PERMANENT_DELETE_TASK:"critical",
  FINANCIAL_ACTION:"critical",
  CHANGE_PERMISSION:"critical",
  SEND_BULK_MESSAGE:"high",
};

export function requiresHumanApproval(action:AgentCapability, risk:RiskLevel) {
  return risk === "high" || risk === "critical" ||
    ["DELETE_LEAD","PERMANENT_DELETE_TASK","FINANCIAL_ACTION","CHANGE_PERMISSION","SEND_BULK_MESSAGE"].includes(action);
}
