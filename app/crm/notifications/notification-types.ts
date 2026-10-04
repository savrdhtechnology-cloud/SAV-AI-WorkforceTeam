export const NOTIFICATION_TYPES=[
  "SYSTEM_NOTIFICATION","SECURITY_NOTIFICATION","ACCOUNT_NOTIFICATION",
  "LEAD_NOTIFICATION","CUSTOMER_NOTIFICATION","TASK_NOTIFICATION","FOLLOWUP_NOTIFICATION","ASSIGNMENT_NOTIFICATION","ESCALATION_NOTIFICATION",
  "AI_AGENT_NOTIFICATION","AI_ACTION_NOTIFICATION","AI_APPROVAL_REQUEST","AI_ACTION_COMPLETED","AI_ACTION_FAILED",
  "WORKFLOW_STARTED","WORKFLOW_COMPLETED","WORKFLOW_FAILED","WORKFLOW_APPROVAL_REQUIRED","WORKFLOW_RETRY","WORKFLOW_ESCALATION",
  "NEW_CONVERSATION","NEW_INBOUND_MESSAGE","MESSAGE_DELIVERY_UPDATE","CONVERSATION_ASSIGNMENT","CONVERSATION_ESCALATION",
  "TASK_REMINDER","FOLLOWUP_REMINDER","SCHEDULED_REMINDER","OVERDUE_REMINDER"
] as const;
export type NotificationType=typeof NOTIFICATION_TYPES[number];

export const NOTIFICATION_CHANNELS=["in_app","email","whatsapp","sms","push","webhook"] as const;
export type NotificationChannel=typeof NOTIFICATION_CHANNELS[number];

export const NOTIFICATION_STATUSES=["QUEUED","SCHEDULED","SENDING","SENT","DELIVERED","READ","FAILED","CANCELLED","WAITING_APPROVAL","RETRYING"] as const;
export type NotificationStatus=typeof NOTIFICATION_STATUSES[number];

export const NOTIFICATION_PRIORITIES=["low","medium","high","urgent","critical"] as const;
export type NotificationPriority=typeof NOTIFICATION_PRIORITIES[number];

export type NotificationRecord={
 id:string;workspace_id?:string;recipient_member_id:string|null;recipient_address:string|null;
 notification_type:NotificationType;title:string;body:string;priority:NotificationPriority;channel:NotificationChannel;
 status:NotificationStatus;source_type:string;source_id:string|null;deep_link:string|null;
 lead_id:string|null;contact_id:string|null;task_id:string|null;workflow_id:string|null;workflow_execution_id:string|null;
 conversation_id:string|null;agent_id:string|null;scheduled_at:string|null;next_attempt_at:string|null;
 retry_count:number;max_retries:number;sent_at:string|null;delivered_at:string|null;read_at:string|null;failed_at:string|null;
 error_code:string|null;error_message:string|null;metadata:Record<string,unknown>;idempotency_key:string;created_at:string;updated_at:string;
};

export type NotificationMetrics={total:number;unread:number;read:number;scheduled:number;sent:number;delivered:number;failed:number;cancelled:number;pending_approval:number};

export type NotificationContext={
 member:{id:string;role:string;full_name:string|null;email:string|null};
 members:Array<{id:string;full_name:string|null;email:string|null;role:string}>;
 agents:Array<{id:string;display_name:string;name:string;status:string;capabilities:string[]}>;
 workflows:Array<{id:string;name:string;status:string}>;
 permissions:{manage:boolean;create:boolean;templates:boolean;channels:boolean;read_only:boolean};
};

export type NotificationListResponse={notifications:NotificationRecord[];metrics:NotificationMetrics;upcoming:NotificationRecord[];context:NotificationContext};
export type NotificationDelivery={id:string;channel:NotificationChannel;status:NotificationStatus;provider:string|null;provider_message_id:string|null;attempt_number:number;error_code:string|null;error_message:string|null;created_at:string;updated_at:string};
export type NotificationDetail={notification:NotificationRecord;deliveries:NotificationDelivery[];events:Array<Record<string,unknown>>};

export type NotificationPreference={id:string;category:string;enabled:boolean;preferred_channel:NotificationChannel;quiet_hours_start:string|null;quiet_hours_end:string|null;digest_frequency:string};
export type NotificationTemplate={id:string;name:string;notification_type:NotificationType;channel:NotificationChannel;subject:string|null;body:string;variables:string[];is_active:boolean;version:number;updated_at:string};
export type NotificationSchedule={id:string;notification_type:NotificationType;channel:NotificationChannel;title:string;scheduled_at:string;next_run_at:string|null;recurrence_rule:string|null;status:string;created_at:string};
