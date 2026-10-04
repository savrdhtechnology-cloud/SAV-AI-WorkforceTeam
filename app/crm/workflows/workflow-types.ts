export const WORKFLOW_STATUSES=["draft","active","paused","disabled","error","archived"] as const;
export type WorkflowStatus=typeof WORKFLOW_STATUSES[number];

export const WORKFLOW_NODE_TYPES=[
  "TRIGGER","CONDITION","AI_AGENT","ACTION","TASK","FOLLOW_UP","WAIT",
  "HUMAN_APPROVAL","ESCALATION","NOTIFICATION","END"
] as const;
export type WorkflowNodeType=typeof WORKFLOW_NODE_TYPES[number];

export const WORKFLOW_TRIGGERS=[
  "NEW_LEAD","LEAD_STATUS_CHANGED","PIPELINE_STAGE_CHANGED","TASK_CREATED","TASK_COMPLETED",
  "FOLLOWUP_DUE","REMINDER_DUE","CONVERSATION_RECEIVED","AI_ESCALATION","MANUAL_TRIGGER","SCHEDULED_TRIGGER",
  "CONVERSATION_CREATED","CONVERSATION_ASSIGNED","MESSAGE_RECEIVED","MESSAGE_DELIVERED","MESSAGE_FAILED",
  "CONVERSATION_CLOSED","CONVERSATION_REOPENED"
] as const;
export type WorkflowTrigger=typeof WORKFLOW_TRIGGERS[number];

export const CONDITION_OPERATORS=[
  "equals","not_equals","contains","not_contains","greater_than","less_than",
  "greater_or_equal","less_or_equal","is_empty","is_not_empty","in","not_in"
] as const;
export type ConditionOperator=typeof CONDITION_OPERATORS[number];

export const WORKFLOW_EXECUTION_STATES=[
  "queued","running","waiting","waiting_approval","completed","failed","cancelled"
] as const;
export type WorkflowExecutionState=typeof WORKFLOW_EXECUTION_STATES[number];

export type WorkflowNode={
  id:string;
  type:WorkflowNodeType;
  label:string;
  position:{x:number;y:number};
  config:Record<string,unknown>;
};

export type WorkflowEdge={
  id:string;
  source:string;
  target:string;
  branch?:string|null;
  condition?:Record<string,unknown>|null;
};

export type WorkflowGraph={nodes:WorkflowNode[];edges:WorkflowEdge[]};

export type WorkflowRecord={
  id:string;
  name:string;
  description:string|null;
  status:WorkflowStatus;
  trigger_type:WorkflowTrigger;
  version:number;
  graph:WorkflowGraph;
  created_at:string;
  updated_at:string;
  enabled_at:string|null;
  disabled_at:string|null;
};

export type WorkflowExecution={
  id:string;
  workflow_id:string;
  workflow_name?:string;
  workflow_version:number;
  trigger:string;
  context:Record<string,unknown>;
  current_node_id:string|null;
  execution_state:WorkflowExecutionState;
  scheduled_for:string|null;
  retry_count:number;
  max_retries:number;
  retry_delay_seconds:number;
  depth:number;
  idempotency_key:string;
  started_at:string|null;
  updated_at:string;
  completed_at:string|null;
  error:string|null;
};

export type WorkflowCondition={
  field:string;
  operator:ConditionOperator;
  value?:unknown;
};

export function evaluateCondition(condition:WorkflowCondition,context:Record<string,unknown>):boolean{
  const actual=getPath(context,condition.field);
  const expected=condition.value;
  switch(condition.operator){
    case "equals": return actual===expected;
    case "not_equals": return actual!==expected;
    case "contains": return String(actual??"").includes(String(expected??""));
    case "not_contains": return !String(actual??"").includes(String(expected??""));
    case "greater_than": return Number(actual)>Number(expected);
    case "less_than": return Number(actual)<Number(expected);
    case "greater_or_equal": return Number(actual)>=Number(expected);
    case "less_or_equal": return Number(actual)<=Number(expected);
    case "is_empty": return actual==null||actual===""||(Array.isArray(actual)&&actual.length===0);
    case "is_not_empty": return !(actual==null||actual===""||(Array.isArray(actual)&&actual.length===0));
    case "in": return Array.isArray(expected)&&expected.includes(actual);
    case "not_in": return Array.isArray(expected)&&!expected.includes(actual);
  }
}

function getPath(value:Record<string,unknown>,path:string):unknown{
  return path.split(".").reduce<unknown>((current,key)=>{
    if(current&&typeof current==="object"&&!Array.isArray(current)) return (current as Record<string,unknown>)[key];
    return undefined;
  },value);
}

export function validateGraph(graph:WorkflowGraph):string[]{
  const errors:string[]=[];
  if(!graph.nodes.some(n=>n.type==="TRIGGER"))errors.push("Workflow requires a TRIGGER node.");
  if(!graph.nodes.some(n=>n.type==="END"))errors.push("Workflow requires an END node.");
  const ids=new Set(graph.nodes.map(n=>n.id));
  if(ids.size!==graph.nodes.length)errors.push("Workflow node IDs must be unique.");
  for(const edge of graph.edges){
    if(!ids.has(edge.source)||!ids.has(edge.target))errors.push(`Edge ${edge.id} references a missing node.`);
    if(edge.source===edge.target)errors.push(`Edge ${edge.id} cannot point to the same node.`);
  }
  return errors;
}
