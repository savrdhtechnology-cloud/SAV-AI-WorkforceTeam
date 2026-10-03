"use client";
import Link from "next/link";
import { Bell,CheckCheck } from "lucide-react";
import { useEffect,useState } from "react";
import { listNotifications,markAllNotificationsRead,markNotificationRead } from "./notification-service";
import { NotificationRecord } from "./notification-types";
export default function NotificationBell(){
 const [open,setOpen]=useState(false),[items,setItems]=useState<NotificationRecord[]>([]),[count,setCount]=useState(0);
 async function refresh(){try{const r=await listNotifications("read=unread");setItems((r.notifications||[]).slice(0,6));setCount(Number(r.metrics?.unread||0));}catch{}}
 useEffect(()=>{refresh();const id=window.setInterval(refresh,60000);return()=>window.clearInterval(id);},[]);
 return <div className="notification-bell-wrap"><button className="notification-bell" onClick={()=>setOpen(v=>!v)} aria-label="Notifications"><Bell size={14}/>{count>0&&<em>{count>99?"99+":count}</em>}</button>{open&&<div className="notification-bell-menu"><div className="notification-bell-head"><b>Notifications</b><button onClick={async()=>{await markAllNotificationsRead();await refresh();}}><CheckCheck size={11}/>Read all</button></div>{items.length?items.map(n=><Link key={n.id} href={n.deep_link||("/crm/notifications/"+n.id)} onClick={async()=>{await markNotificationRead(n.id);setOpen(false);await refresh();}}><span className={"dot "+n.priority}/><div><b>{n.title}</b><span>{n.body}</span><time>{new Date(n.created_at).toLocaleString("en-IN")}</time></div></Link>):<p>No unread notifications.</p>}<Link className="notification-bell-all" href="/crm/notifications" onClick={()=>setOpen(false)}>Open notification center</Link></div>}</div>;
}
