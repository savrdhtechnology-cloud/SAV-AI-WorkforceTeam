"use client";
import Link from "next/link";
import { useEffect,useState } from "react";
import { CheckCircle2,CircleAlert,Clock3,Loader2 } from "lucide-react";
import { getWorkflowExecution,reviewWorkflowApproval } from "./workflow-service";
import "../crm.css";
export default function ExecutionDetail({id}:{id:string}){
 const [data,setData]=useState<any>(null),[error,setError]=useState(""),[loading,setLoading]=useState(true);
 async function load(){setLoading(true);try{setData(await getWorkflowExecution(id));}catch(e){setError(e instanceof Error?e.message:"Could not load execution.");}finally{setLoading(false);}}
 useEffect(()=>{load();},[id]);
 async function review(aid:string,d:"approve"|"reject"){try{await reviewWorkflowApproval(aid,d,d==="approve"?"Approved from execution timeline":"Rejected from execution timeline");await load();}catch(e){setError(e instanceof Error?e.message:"Approval failed.");}}
 if(loading)return <div className="workflow-loading"><Loader2 className="spin" size={20}/>Loading execution...</div>;
 if(!data)return <div className="task-error">{error||"Execution not found."}</div>;
 const ex=data.execution;
 return <div className="workflow-execution-page"><header className="agent-route-head"><div><small>{ex.trigger}</small><h1>Workflow Execution</h1></div><Link href="/crm/workflows/executions">Back to Executions</Link></header>{error&&<div className="task-error">{error}</div>}
 <div className="workflow-execution-summary"><Info label="Status" value={ex.execution_state}/><Info label="Version" value={"v"+ex.workflow_version}/><Info label="Depth" value={String(ex.depth)}/><Info label="Retries" value={`${ex.retry_count}/${ex.max_retries}`}/></div>
 <div className="workflow-timeline">{(data.nodes||[]).map((n:any)=><div className="workflow-timeline-row" key={n.id}><span className={`timeline-dot ${n.status}`}>{n.status==="completed"?<CheckCircle2 size={12}/>:n.status.includes("waiting")?<Clock3 size={12}/>:<CircleAlert size={12}/>}</span><div><b>{n.node_label}</b><small>{n.node_type} · {n.status}</small>{n.last_error&&<em>{n.last_error}</em>}{n.output&&<pre>{JSON.stringify(n.output,null,2)}</pre>}</div></div>)}</div>
 {(data.approvals||[]).filter((a:any)=>a.status==="pending").map((a:any)=><div className="agent-approval-row" key={a.id}><div><b>Approval required</b><span>{a.risk_level} risk · {a.approval_reason}</span></div><div><button onClick={()=>review(a.id,"reject")}>Reject</button><button className="primary" onClick={()=>review(a.id,"approve")}>Approve</button></div></div>)}
 </div>;
}
function Info({label,value}:{label:string;value:string}){return <div className="crm-card"><span>{label}</span><strong>{value}</strong></div>}
