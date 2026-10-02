"use client";

import { FormEvent,useEffect,useMemo,useState } from "react";
import {
  Archive,ArrowUpRight,Bot,Check,CheckCheck,CircleAlert,Clock3,Filter,Inbox,
  Loader2,MessageSquareMore,Plus,RefreshCw,Search,Send,Tag,UserRound,Users,X
} from "lucide-react";
import {
  addInternalNote,assignConversation,closeConversation,createConversation,createInboxFollowup,createInboxTask,
  draftReply,escalateConversation,getConversation,getInboxContext,listConversations,markMessageRead,reopenConversation,
  retryMessage,sendMessage,updateConversation
} from "./inbox-service";
import { ConversationDetail,ConversationRecord,InboxContext,InboxMessage } from "./inbox-types";

export default function InboxModule(){
  const [context,setContext]=useState<InboxContext|null>(null);
  const [rows,setRows]=useState<ConversationRecord[]>([]);
  const [selected,setSelected]=useState<string|null>(null);
  const [detail,setDetail]=useState<ConversationDetail|null>(null);
  const [loading,setLoading]=useState(true);
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState("");
  const [notice,setNotice]=useState("");
  const [search,setSearch]=useState("");
  const [channel,setChannel]=useState("");
  const [status,setStatus]=useState("");
  const [assignment,setAssignment]=useState("");
  const [unreadOnly,setUnreadOnly]=useState(false);
  const [composer,setComposer]=useState("");
  const [selectedAgent,setSelectedAgent]=useState("");
  const [newOpen,setNewOpen]=useState(false);
  const [taskOpen,setTaskOpen]=useState<"task"|"followup"|null>(null);

  async function loadList(preferred?:string){
    setLoading(true);setError("");
    try{
      const qs=new URLSearchParams();
      if(search.trim())qs.set("search",search.trim());
      if(channel)qs.set("channel",channel);
      if(status)qs.set("status",status);
      if(assignment)qs.set("assignment",assignment);
      if(unreadOnly)qs.set("unread","1");
      const [ctx,res]=await Promise.all([context?Promise.resolve(context):getInboxContext(),listConversations(qs.toString())]);
      setContext(ctx);setRows(res.conversations||[]);
      const id=preferred||selected||res.conversations?.[0]?.id||null;
      setSelected(id);
      if(id)await loadDetail(id,false); else setDetail(null);
    }catch(e){setError(e instanceof Error?e.message:"Could not load Inbox.");}
    finally{setLoading(false);}
  }

  async function loadDetail(id:string,markRead=true){
    setSelected(id);setError("");
    try{
      let d=await getConversation(id);
      if(markRead){
        const unread=(d.messages||[]).filter(m=>m.direction==="inbound"&&!m.is_read);
        if(unread.length){
          await Promise.all(unread.map(m=>markMessageRead(m.id,true)));
          await updateConversation(id,{markUnread:false});
          d=await getConversation(id);
          setRows(r=>r.map(x=>x.id===id?{...x,unread_count:0}:x));
        }
      }
      setDetail(d);
    }catch(e){setError(e instanceof Error?e.message:"Could not load conversation.");}
  }

  useEffect(()=>{loadList();},[]);
  useEffect(()=>{const t=setTimeout(()=>{if(context)loadList();},250);return()=>clearTimeout(t);},[search,channel,status,assignment,unreadOnly]);

  const latestInbound=useMemo(()=>[...(detail?.messages||[])].reverse().find(m=>m.direction==="inbound"),[detail]);
  const unreadTotal=rows.reduce((n,r)=>n+r.unread_count,0);

  async function perform(action:()=>Promise<unknown>,success:string,refresh=true){
    setBusy(true);setError("");setNotice("");
    try{await action();setNotice(success);if(refresh&&selected)await loadDetail(selected,false);await loadList(selected||undefined);}
    catch(e){setError(e instanceof Error?e.message:"Inbox action failed.");}
    finally{setBusy(false);}
  }

  async function submitMessage(e:FormEvent){
    e.preventDefault();
    if(!selected||!composer.trim())return;
    setBusy(true);setError("");setNotice("");
    try{
      const result=await sendMessage({
        conversationId:selected,body:composer.trim(),messageType:"text",
        recipient:latestInbound?.sender||null,agentId:selectedAgent||null
      });
      if(result?.approval_required){
        setNotice("AI send request created and is waiting for human approval.");
      }else{
        setNotice(`Message status: ${result.delivery_status||"processed"}`);
        setComposer("");
      }
      await loadDetail(selected,false);await loadList(selected);
    }catch(e){setError(e instanceof Error?e.message:"Message send failed.");}
    finally{setBusy(false);}
  }

  async function generateDraft(){
    if(!detail?.messages?.length||!selectedAgent){setError("Select an AI agent and a source message first.");return;}
    const source=[...detail.messages].reverse().find(m=>m.direction==="inbound")||detail.messages[detail.messages.length-1];
    setBusy(true);setError("");
    try{const r=await draftReply(source.id,{agentId:selectedAgent,instruction:"Draft a helpful reply based only on this conversation."});setComposer(r.draft||"");setNotice("AI draft created. Sending remains separately controlled.");}
    catch(e){setError(e instanceof Error?e.message:"AI draft failed.");}
    finally{setBusy(false);}
  }

  if(loading&&!context)return <div className="inbox-loading"><Loader2 className="spin" size={20}/> Loading unified Inbox...</div>;

  return <div className="inbox-module">
    <div className="inbox-summary">
      <div className="crm-card"><span>Conversations</span><strong>{rows.length}</strong></div>
      <div className="crm-card"><span>Unread</span><strong>{unreadTotal}</strong></div>
      <div className="crm-card"><span>Unassigned</span><strong>{rows.filter(r=>!r.assigned_to&&!r.assigned_agent_id).length}</strong></div>
      <div className="crm-card"><span>Open</span><strong>{rows.filter(r=>r.status==="open").length}</strong></div>
    </div>
    {error&&<div className="task-error">{error}</div>}
    {notice&&<div className="agent-success">{notice}</div>}

    <div className="inbox-toolbar">
      <div className="crm-search"><Search size={14}/><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search conversations, customer, lead or message..."/></div>
      <div className="inbox-filter-row">
        <select value={channel} onChange={e=>setChannel(e.target.value)}><option value="">All channels</option>{["whatsapp","email","sms","voice","webchat"].map(x=><option key={x}>{x}</option>)}</select>
        <select value={status} onChange={e=>setStatus(e.target.value)}><option value="">All status</option>{["open","waiting","closed","archived"].map(x=><option key={x}>{x}</option>)}</select>
        <select value={assignment} onChange={e=>setAssignment(e.target.value)}><option value="">All assignment</option><option value="mine">Mine</option><option value="assigned">Assigned</option><option value="unassigned">Unassigned</option><option value="human">Human</option><option value="ai">AI</option></select>
        <button className={unreadOnly?"active":""} onClick={()=>setUnreadOnly(v=>!v)}><Filter size={11}/>Unread</button>
        <button onClick={()=>loadList()}><RefreshCw size={11}/>Refresh</button>
        <button className="task-new-btn" onClick={()=>setNewOpen(true)}><Plus size={11}/>New</button>
      </div>
    </div>

    <div className="inbox-shell">
      <aside className="inbox-list">
        {rows.length?rows.map(r=><button key={r.id} className={r.id===selected?"active":""} onClick={()=>loadDetail(r.id)}>
          <div className="inbox-list-top"><ChannelBadge channel={r.channel}/><time>{fmtCompact(r.last_message_at)}</time></div>
          <div className="inbox-list-title"><b>{r.related_name||r.subject||"Unknown contact"}</b>{r.unread_count>0&&<em>{r.unread_count}</em>}</div>
          <p>{r.last_message_preview||"No messages yet"}</p>
          <div className="inbox-list-meta"><span className={"priority "+r.priority}>{r.priority}</span><span>{r.assigned_agent_name||r.assigned_human_name||"Unassigned"}</span><span>{r.status}</span></div>
        </button>):<div className="crm-empty"><div><Inbox size={24}/><h3>No conversations</h3><p>Inbound threads and created conversations will appear here.</p></div></div>}
      </aside>

      <section className="inbox-thread">
        {!detail?<div className="crm-empty"><div><MessageSquareMore size={25}/><h3>Select a conversation</h3></div></div>:<>
          <ConversationHeader detail={detail} context={context} busy={busy}
            onReload={()=>loadDetail(detail.conversation.id,false)}
            onAction={perform}
            onTask={()=>setTaskOpen("task")} onFollowup={()=>setTaskOpen("followup")}
          />
          <div className="inbox-messages">
            {(detail.messages||[]).map(m=><MessageBubble key={m.id} message={m} onRetry={()=>perform(()=>retryMessage(m.id),"Retry processed.")}/>)}
          </div>
          <form className="inbox-composer" onSubmit={submitMessage}>
            <div className="inbox-compose-controls">
              <select value={detail.conversation.channel} disabled><option>{detail.conversation.channel}</option></select>
              <select value={selectedAgent} onChange={e=>setSelectedAgent(e.target.value)}><option value="">Human reply</option>{(context?.agents||[]).filter(a=>a.status==="active"&&a.channels?.includes(detail.conversation.channel)).map(a=><option key={a.id} value={a.id}>{a.display_name||a.name}</option>)}</select>
              <button type="button" onClick={generateDraft} disabled={!selectedAgent||busy}><Bot size={11}/>AI Draft</button>
            </div>
            <textarea value={composer} onChange={e=>setComposer(e.target.value)} placeholder={detail.conversation.status==="closed"?"Reopen conversation before replying...":"Write a message. External delivery is only confirmed by the configured provider."} disabled={detail.conversation.status==="closed"}/>
            <div className="inbox-compose-foot"><span>{selectedAgent?"AI send uses approval boundary":"Sending as authenticated CRM user"}</span><button className="primary" disabled={busy||!composer.trim()||detail.conversation.status==="closed"}><Send size={12}/>{busy?"Processing":"Send"}</button></div>
          </form>
          <ConversationActivity detail={detail}/>
        </>}
      </section>
    </div>

    {newOpen&&<NewConversationModal context={context} onClose={()=>setNewOpen(false)} onCreated={async id=>{setNewOpen(false);await loadList(id);}}/>}
    {taskOpen&&detail&&<TaskModal mode={taskOpen} conversationId={detail.conversation.id} context={context} onClose={()=>setTaskOpen(null)} onCreated={async()=>{setTaskOpen(null);setNotice(taskOpen==="task"?"Task created.":"Follow-up created.");await loadDetail(detail.conversation.id,false);}}/>}
  </div>;
}

function ConversationHeader({detail,context,busy,onReload,onAction,onTask,onFollowup}:any){
  const c=detail.conversation;
  const [tags,setTags]=useState((c.tags||[]).join(", "));
  return <div className="inbox-thread-head">
    <div><div className="inbox-title-line"><ChannelBadge channel={c.channel}/><h3>{c.related_name||c.subject||"Conversation"}</h3><span className={"priority "+c.priority}>{c.priority}</span></div><small>{c.subject||c.channel} · {c.status} · {c.unread_count||0} unread</small></div>
    <div className="inbox-head-actions">
      <select value={c.assigned_to||""} onChange={e=>onAction(()=>assignConversation(c.id,{assignmentType:"human",memberId:e.target.value,reason:"Inbox assignment"}),"Human assignment updated.")} disabled={!context?.permissions.assign||busy}><option value="">Assign human</option>{(context?.members||[]).map((m:any)=><option key={m.id} value={m.id}>{m.full_name||m.email}</option>)}</select>
      <select value={c.assigned_agent_id||""} onChange={e=>onAction(()=>assignConversation(c.id,{assignmentType:"ai",agentId:e.target.value,reason:"Inbox AI assignment"}),"AI assignment updated.")} disabled={!context?.permissions.assign_ai||busy}><option value="">Assign AI</option>{(context?.agents||[]).filter((a:any)=>a.status==="active"&&a.channels?.includes(c.channel)).map((a:any)=><option key={a.id} value={a.id}>{a.display_name||a.name}</option>)}</select>
      <button onClick={onTask}><Plus size={10}/>Task</button><button onClick={onFollowup}><Clock3 size={10}/>Follow-up</button>
      <button onClick={()=>onAction(()=>escalateConversation(c.id,"Escalated from Inbox"),"Conversation escalated.")}><ArrowUpRight size={10}/>Escalate</button>
      {c.status==="closed"?<button onClick={()=>onAction(()=>reopenConversation(c.id),"Conversation reopened.")}>Reopen</button>:<button onClick={()=>onAction(()=>closeConversation(c.id),"Conversation closed.")}>Close</button>}
      <button onClick={()=>onAction(()=>updateConversation(c.id,{markUnread:true}),"Conversation marked unread.")}>Unread</button>
      <button className="danger" onClick={()=>onAction(()=>updateConversation(c.id,{archive:true}),"Conversation archived.")} disabled={!context?.permissions.archive}><Archive size={10}/>Archive</button>
    </div>
    <div className="inbox-link-row">
      <select value={c.lead_id||""} onChange={e=>onAction(()=>updateConversation(c.id,{leadId:e.target.value||null}),"Lead link updated.")}><option value="">Link lead</option>{(context?.leads||[]).map((l:any)=><option key={l.id} value={l.id}>{l.title}</option>)}</select>
      <select value={c.contact_id||""} onChange={e=>onAction(()=>updateConversation(c.id,{contactId:e.target.value||null}),"Customer link updated.")}><option value="">Link customer/contact</option>{(context?.contacts||[]).map((x:any)=><option key={x.id} value={x.id}>{[x.first_name,x.last_name].filter(Boolean).join(" ")||x.company||x.email||x.phone}</option>)}</select>
      <input value={tags} onChange={e=>setTags(e.target.value)} placeholder="tags, comma separated"/>
      <button onClick={()=>onAction(()=>updateConversation(c.id,{tags:tags.split(",").map((x:string)=>x.trim()).filter(Boolean)}),"Tags updated.")}><Tag size={10}/>Save tags</button>
      <select value={c.priority} onChange={e=>onAction(()=>updateConversation(c.id,{priority:e.target.value}),"Priority updated.")}>{["low","medium","high","urgent"].map(x=><option key={x}>{x}</option>)}</select>
    </div>
    <InternalNote conversationId={c.id} onAction={onAction}/>
  </div>;
}

function InternalNote({conversationId,onAction}:{conversationId:string;onAction:any}){
 const [note,setNote]=useState("");
 return <div className="inbox-note-row"><input value={note} onChange={e=>setNote(e.target.value)} placeholder="Add internal note (not sent externally)"/><button disabled={!note.trim()} onClick={()=>onAction(async()=>{await addInternalNote(conversationId,note.trim());setNote("");},"Internal note added.")}>Add note</button></div>;
}

function MessageBubble({message,onRetry}:{message:InboxMessage;onRetry:()=>void}){
 const internal=message.message_type==="note"||message.metadata?.internal===true;
 return <div className={`inbox-message ${message.direction} ${internal?"internal":""}`}>
   <div className="inbox-message-meta"><span>{internal?"INTERNAL NOTE":message.sender_name||message.sender||message.direction}</span><time>{fmt(message.created_at)}</time></div>
   <div className="inbox-bubble">{message.body||<em>{message.message_type} attachment</em>}</div>
   <div className="inbox-delivery"><DeliveryIcon status={message.delivery_status}/><span>{message.delivery_status}</span>{message.error_code&&<b>{message.error_code}: {message.error_message}</b>}{message.delivery_status==="FAILED"&&<button onClick={onRetry}>Retry</button>}</div>
 </div>;
}
function DeliveryIcon({status}:{status:string}){if(status==="READ")return <CheckCheck size={10}/>;if(status==="DELIVERED"||status==="SENT")return <Check size={10}/>;if(status==="FAILED")return <CircleAlert size={10}/>;return <Clock3 size={10}/>;}

function ConversationActivity({detail}:{detail:ConversationDetail}){
 return <div className="inbox-activity"><div className="crm-panel-head"><h3>Conversation Activity</h3><span>{detail.activities?.length||0} events</span></div>{(detail.activities||[]).length?<div className="crm-activity-list">{detail.activities.map((a:any)=><div className="crm-activity" key={a.id}><i/><div><b>{a.title}</b><span>{a.description||a.activity_type}{a.actor_name?" · "+a.actor_name:""}</span></div><time>{fmt(a.created_at)}</time></div>)}</div>:<p>No activity yet.</p>}</div>;
}

function NewConversationModal({context,onClose,onCreated}:{context:InboxContext|null;onClose:()=>void;onCreated:(id:string)=>void}){
 const [error,setError]=useState("");const [saving,setSaving]=useState(false);
 async function submit(e:FormEvent<HTMLFormElement>){e.preventDefault();const fd=new FormData(e.currentTarget);setSaving(true);try{const relation=String(fd.get("relationType")||"");const relationId=String(fd.get("relationId")||"");const r=await createConversation({channel:String(fd.get("channel")),subject:String(fd.get("subject")||""),priority:String(fd.get("priority")||"medium"),leadId:relation==="lead"?relationId||null:null,contactId:relation==="contact"?relationId||null:null});onCreated(r.id);}catch(e){setError(e instanceof Error?e.message:"Create failed.");}finally{setSaving(false);}}
 return <div className="crm-modal-wrap"><form className="crm-modal" onSubmit={submit}><div className="crm-modal-head"><h3>New Conversation</h3><button type="button" onClick={onClose}><X size={14}/></button></div><div className="crm-form">
  <label>Channel<select name="channel">{["whatsapp","email","sms","voice","webchat"].map(x=><option key={x}>{x}</option>)}</select></label><label>Priority<select name="priority">{["medium","high","urgent","low"].map(x=><option key={x}>{x}</option>)}</select></label>
  <label className="full">Subject<input name="subject"/></label>
  <label>Relation<select name="relationType"><option value="">None</option><option value="lead">Lead</option><option value="contact">Customer/Contact</option></select></label>
  <label>Relation ID<select name="relationId"><option value="">None</option><optgroup label="Leads">{(context?.leads||[]).map(x=><option key={x.id} value={x.id}>{x.title}</option>)}</optgroup><optgroup label="Contacts">{(context?.contacts||[]).map(x=><option key={x.id} value={x.id}>{[x.first_name,x.last_name].filter(Boolean).join(" ")||x.company||x.email}</option>)}</optgroup></select></label>
  {error&&<div className="task-error full">{error}</div>}<div className="crm-form-actions"><button type="button" onClick={onClose}>Cancel</button><button className="primary" disabled={saving}>{saving?"Creating...":"Create"}</button></div>
 </div></form></div>;
}

function TaskModal({mode,conversationId,context,onClose,onCreated}:any){
 const [error,setError]=useState("");const [saving,setSaving]=useState(false);
 async function submit(e:FormEvent<HTMLFormElement>){e.preventDefault();const fd=new FormData(e.currentTarget);setSaving(true);const payload={conversationId,title:String(fd.get("title")||""),description:String(fd.get("description")||""),priority:String(fd.get("priority")||"medium"),dueAt:String(fd.get("dueAt")||"")||null,followupType:String(fd.get("followupType")||"general"),assigneeType:"human",assignedTo:String(fd.get("assignedTo")||"")||null};try{if(mode==="task")await createInboxTask(payload);else await createInboxFollowup(payload);onCreated();}catch(e){setError(e instanceof Error?e.message:"Create failed.");}finally{setSaving(false);}}
 return <div className="crm-modal-wrap"><form className="crm-modal" onSubmit={submit}><div className="crm-modal-head"><h3>{mode==="task"?"Create Task":"Create Follow-up"}</h3><button type="button" onClick={onClose}><X size={14}/></button></div><div className="crm-form"><label className="full">Title<input name="title" required minLength={3}/></label><label className="full">Description<textarea name="description"/></label>{mode==="followup"&&<label>Type<select name="followupType">{["general","call","whatsapp","email","meeting","document","payment","proposal","site_visit","support"].map(x=><option key={x}>{x}</option>)}</select></label>}<label>Priority<select name="priority">{["medium","high","urgent","low"].map(x=><option key={x}>{x}</option>)}</select></label><label>Due<input name="dueAt" type="datetime-local"/></label><label>Assign human<select name="assignedTo"><option value="">Me</option>{(context?.members||[]).map((m:any)=><option key={m.id} value={m.id}>{m.full_name||m.email}</option>)}</select></label>{error&&<div className="task-error full">{error}</div>}<div className="crm-form-actions"><button type="button" onClick={onClose}>Cancel</button><button className="primary" disabled={saving}>{saving?"Creating...":"Create"}</button></div></div></form></div>;
}

function ChannelBadge({channel}:{channel:string}){return <span className={"inbox-channel "+channel}>{channel}</span>}
function fmt(v?:string|null){return v?new Date(v).toLocaleString("en-IN"):"—";}
function fmtCompact(v?:string|null){if(!v)return "—";const d=new Date(v);return d.toLocaleDateString("en-IN",{day:"2-digit",month:"short"})+" "+d.toLocaleTimeString("en-IN",{hour:"2-digit",minute:"2-digit"});}
