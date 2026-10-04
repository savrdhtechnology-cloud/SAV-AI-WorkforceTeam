import AgentsRouteShell from "../AgentsRouteShell";
export default async function AgentDetailPage({params}:{params:Promise<{id:string}>}){const {id}=await params;return <AgentsRouteShell agentId={id}/>;}
