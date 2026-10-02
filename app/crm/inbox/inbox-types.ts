export const INBOX_CHANNELS=["whatsapp","email","sms","voice","webchat"] as const;
export type InboxChannel=typeof INBOX_CHANNELS[number];

export const MESSAGE_DIRECTIONS=["inbound","outbound"] as const;
export type MessageDirection=typeof MESSAGE_DIRECTIONS[number];

export const MESSAGE_TYPES=["text","html","image","file","audio","video","system","note"] as const;
export type MessageType=typeof MESSAGE_TYPES[number];

export const MESSAGE_STATUSES=["QUEUED","SENDING","SENT","DELIVERED","READ","FAILED"] as const;
export type MessageStatus=typeof MESSAGE_STATUSES[number];

export const CONVERSATION_STATUSES=["open","waiting","closed","archived"] as const;
export type ConversationStatus=typeof CONVERSATION_STATUSES[number];

export const CONVERSATION_PRIORITIES=["low","medium","high","urgent"] as const;
export type ConversationPriority=typeof CONVERSATION_PRIORITIES[number];

export type AttachmentMetadata={
  id?:string;
  file_name:string;
  mime_type:string;
  size_bytes?:number|null;
  external_url?:string|null;
  provider_attachment_id?:string|null;
  metadata?:Record<string,unknown>;
};

export type InboxMessage={
  id:string;
  conversation_id:string;
  channel:InboxChannel;
  direction:MessageDirection;
  sender:string|null;
  sender_name:string|null;
  recipient:string|null;
  message_type:MessageType;
  body:string|null;
  attachments?:AttachmentMetadata[];
  provider_message_id:string|null;
  delivery_status:MessageStatus;
  is_read:boolean;
  read_at:string|null;
  sent_by_member_id:string|null;
  sent_by_agent_id:string|null;
  error_code:string|null;
  error_message:string|null;
  metadata:Record<string,unknown>;
  created_at:string;
  updated_at:string;
};

export type ConversationRecord={
  id:string;
  channel:InboxChannel;
  status:ConversationStatus;
  priority:ConversationPriority;
  subject:string|null;
  lead_id:string|null;
  contact_id:string|null;
  related_name:string|null;
  assigned_to:string|null;
  assigned_human_name:string|null;
  assigned_agent_id:string|null;
  assigned_agent_name:string|null;
  unread_count:number;
  last_message_at:string|null;
  last_message_preview:string|null;
  tags:string[];
  archived_at:string|null;
  created_at:string;
  updated_at:string;
};

export type InboxContext={
  member:{id:string;role:string;full_name:string|null;email:string|null};
  members:Array<{id:string;full_name:string|null;email:string|null;role:string}>;
  agents:Array<{id:string;display_name:string;name:string;status:string;channels:string[];capabilities:string[]}>;
  leads:Array<{id:string;title:string;company:string|null}>;
  contacts:Array<{id:string;first_name:string|null;last_name:string|null;company:string|null;email:string|null;phone:string|null}>;
  channels:InboxChannel[];
  permissions:{reply:boolean;assign:boolean;assign_ai:boolean;archive:boolean;manage_channels:boolean;read_only:boolean};
};

export type ConversationDetail={
  conversation:ConversationRecord & Record<string,unknown>;
  messages:InboxMessage[];
  participants:Array<Record<string,unknown>>;
  activities:Array<Record<string,unknown>>;
  assignments:Array<Record<string,unknown>>;
};
