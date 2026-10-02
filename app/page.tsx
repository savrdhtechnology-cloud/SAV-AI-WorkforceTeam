import {
  Activity,
  ArrowRight,
  BarChart3,
  Bot,
  BrainCircuit,
  CheckCircle2,
  ChevronRight,
  Database,
  Headphones,
  Layers3,
  LockKeyhole,
  MessageCircleMore,
  Network,
  PhoneCall,
  Play,
  RefreshCw,
  ShieldCheck,
  Sparkles,
  Workflow,
  Zap,
} from "lucide-react";

const agents = [
  {
    icon: PhoneCall,
    title: "SAV Sales",
    text: "Qualifies leads, follows up automatically and keeps every prospect moving.",
    stat: "42 leads queued",
  },
  {
    icon: Headphones,
    title: "SAV Support",
    text: "Handles common customer questions, routes complex cases and never loses context.",
    stat: "24×7 available",
  },
  {
    icon: BrainCircuit,
    title: "SAV Operations",
    text: "Executes recurring operational tasks, updates records and coordinates workflows.",
    stat: "86 actions ready",
  },
];

const channels = ["WhatsApp", "Email", "SMS", "Voice", "CRM", "Web"];

const features = [
  {
    icon: Bot,
    title: "AI Agents",
    text: "Purpose-built virtual team members for sales, service, operations and internal tasks.",
  },
  {
    icon: Workflow,
    title: "Workflow Automation",
    text: "Turn repeat processes into governed automations with approval and escalation controls.",
  },
  {
    icon: MessageCircleMore,
    title: "Omnichannel",
    text: "Coordinate conversations across WhatsApp, email, SMS, voice and connected business systems.",
  },
  {
    icon: Database,
    title: "Knowledge + Memory",
    text: "Ground agents in your business information and preserve approved working context.",
  },
  {
    icon: ShieldCheck,
    title: "Human Control",
    text: "Keep sensitive decisions behind approval gates with clear activity history.",
  },
  {
    icon: BarChart3,
    title: "Live Analytics",
    text: "Track work completed, pending actions, channel outcomes and team productivity.",
  },
];

function BrandMark() {
  return (
    <div className="brand-mark" aria-hidden="true">
      <span />
      <span />
      <span />
    </div>
  );
}

function CommandPreview() {
  return (
    <div className="console-shell">
      <div className="console-top">
        <div className="console-brand">
          <BrandMark />
          <div>
            <strong>SAV AI WORKFORCE</strong>
            <small>Command Center</small>
          </div>
        </div>
        <div className="system-ready"><span /> All Systems Ready</div>
      </div>

      <div className="console-body">
        <aside className="console-side">
          {["Dashboard", "AI Agents", "Voice", "Channels", "Workflows", "Knowledge", "Memory", "Escalation", "Analytics"].map((item, i) => (
            <div className={i === 0 ? "mini-nav active" : "mini-nav"} key={item}>
              <span className="mini-dot" />
              {item}
            </div>
          ))}
        </aside>

        <div className="console-main">
          <div className="console-label">AI COMMAND CENTER</div>
          <div className="command-box">
            <span className="prompt-label">Tell SAV AI what you want to do...</span>
            <div className="typed-line">
              <ChevronRight size={16} />
              Start following up with today&apos;s pending leads
              <span className="typing-cursor" />
            </div>
            <button>EXECUTE <Zap size={14} /></button>
          </div>

          <div className="response-heading">AI RESPONSE</div>
          <div className="response-box">
            <div className="response-icon"><Sparkles size={18} /></div>
            <div>
              <strong>SAV-Sales will contact 42 pending leads through WhatsApp.</strong>
              <div className="response-stats">
                <span><b>86</b> estimated actions</span>
                <span><b>No</b> approval required</span>
              </div>
            </div>
          </div>

          <div className="agent-strip">
            <div><span className="live-dot" /> SAV-Sales</div>
            <div><RefreshCw size={13} /> Workflow running</div>
            <div><Activity size={13} /> Live activity</div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default function Home() {
  return (
    <main>
      <header className="site-header">
        <a className="logo" href="#top" aria-label="SAVRDH Intelligence Workforce">
          <BrandMark />
          <div>
            <span className="logo-main">SAVRDH</span>
            <span className="logo-sub">INTELLIGENCE WORKFORCE</span>
          </div>
        </a>
        <nav>
          <a href="#platform">Platform</a>
          <a href="#agents">AI Agents</a>
          <a href="#integrations">Integrations</a>
          <a href="#security">Security</a>
        </nav>
        <a className="header-cta" href="#contact">Request Demo <ArrowRight size={15} /></a>
      </header>

      <section className="hero" id="top">
        <div className="hero-glow glow-one" />
        <div className="hero-glow glow-two" />
        <div className="grid-overlay" />
        <div className="hero-copy">
          <div className="eyebrow"><Sparkles size={14} /> A Savrdh Technology Product</div>
          <h1>Your Intelligent<br /><span>Virtual Workforce.</span></h1>
          <p>
            Deploy AI agents that follow up, communicate, coordinate and execute business workflows—
            across your channels, around the clock, with human control built in.
          </p>
          <div className="hero-actions">
            <a href="#contact" className="primary-btn">Book a Demo <ArrowRight size={18} /></a>
            <a href="#platform" className="ghost-btn"><Play size={16} fill="currentColor" /> Explore Platform</a>
          </div>
          <div className="trust-row">
            <span><CheckCircle2 size={15} /> Human approvals</span>
            <span><CheckCircle2 size={15} /> Real-time activity</span>
            <span><CheckCircle2 size={15} /> Multi-channel</span>
          </div>
        </div>

        <div className="hero-product">
          <div className="floating-badge badge-one"><span /> 42 leads queued</div>
          <div className="floating-badge badge-two"><Zap size={13} /> Agent executing</div>
          <CommandPreview />
        </div>
      </section>

      <section className="logo-band" aria-label="Supported channels">
        <span className="band-label">ONE WORKFORCE. EVERY CHANNEL.</span>
        <div className="channel-row">
          {channels.map((channel) => <span key={channel}>{channel}</span>)}
        </div>
      </section>

      <section className="section platform-section" id="platform">
        <div className="section-kicker">THE OPERATING LAYER FOR AI WORK</div>
        <div className="section-heading">
          <h2>Give your business a workforce that never stops.</h2>
          <p>
            SAVRDH Intelligence Workforce brings AI agents, workflows, communication channels,
            knowledge, memory, approvals and analytics into one controlled workspace.
          </p>
        </div>
        <div className="feature-grid">
          {features.map(({ icon: Icon, title, text }) => (
            <article className="feature-card" key={title}>
              <div className="feature-icon"><Icon size={22} /></div>
              <h3>{title}</h3>
              <p>{text}</p>
              <span className="learn-link">Built for business <ArrowRight size={14} /></span>
            </article>
          ))}
        </div>
      </section>

      <section className="section agents-section" id="agents">
        <div className="agents-intro">
          <div className="section-kicker">MEET YOUR AI TEAM</div>
          <h2>Specialized agents.<br />One coordinated workforce.</h2>
          <p>
            Assign each agent a clear role, approved knowledge and operational boundaries.
            SAV coordinates the work and surfaces what needs human attention.
          </p>
          <div className="control-points">
            <span><LockKeyhole size={16} /> Role-based controls</span>
            <span><Network size={16} /> Connected workflows</span>
            <span><Activity size={16} /> Complete activity trail</span>
          </div>
        </div>
        <div className="agent-cards">
          {agents.map(({ icon: Icon, title, text, stat }, i) => (
            <article className={"agent-card agent-" + (i + 1)} key={title}>
              <div className="agent-card-top">
                <div className="agent-avatar"><Icon size={21} /></div>
                <span className="agent-status"><i /> ACTIVE</span>
              </div>
              <h3>{title}</h3>
              <p>{text}</p>
              <div className="agent-card-stat">{stat}</div>
            </article>
          ))}
        </div>
      </section>

      <section className="section workflow-section">
        <div className="workflow-panel">
          <div className="workflow-copy">
            <div className="section-kicker">FROM COMMAND TO EXECUTION</div>
            <h2>Tell SAV the outcome. Let the workforce coordinate the work.</h2>
            <p>
              Use natural-language commands for guided tasks, or automate recurring processes with
              triggers, business rules, approvals and escalations.
            </p>
            <a href="#contact" className="text-link">See how it works <ArrowRight size={16} /></a>
          </div>
          <div className="flow-visual">
            <div className="flow-node user-node"><MessageCircleMore size={18} /><span>Your command</span></div>
            <div className="flow-line"><span /></div>
            <div className="flow-node ai-node"><BrainCircuit size={20} /><span>SAV Orchestrator</span></div>
            <div className="flow-branches">
              <span />
              <span />
              <span />
            </div>
            <div className="flow-results">
              <div><PhoneCall size={16} /> Sales</div>
              <div><Workflow size={16} /> Workflow</div>
              <div><Layers3 size={16} /> CRM</div>
            </div>
          </div>
        </div>
      </section>

      <section className="section integrations-section" id="integrations">
        <div className="section-kicker">CONNECTED BY DESIGN</div>
        <div className="section-heading">
          <h2>Works with the systems your business already uses.</h2>
          <p>Connect communication, CRM, data and workflow systems so agents can operate from a shared source of truth.</p>
        </div>
        <div className="integration-cloud">
          {["WhatsApp", "Email", "SMS", "Voice", "Savrdh CRM", "Supabase", "Webhooks", "REST API"].map((x, i) => (
            <span className={"integration-pill pill-" + i} key={x}>{x}</span>
          ))}
          <div className="cloud-core"><BrandMark /><strong>SAV</strong><small>AI CORE</small></div>
        </div>
      </section>

      <section className="section security-section" id="security">
        <div className="security-card">
          <div>
            <div className="section-kicker">CONTROL WITHOUT SLOWING DOWN</div>
            <h2>Automation with governance built in.</h2>
            <p>
              Define what an agent can access, which actions are automatic, and where human approval
              is required. Every important action remains visible in activity history.
            </p>
          </div>
          <div className="security-list">
            {["Approval gates", "Role-based access", "Escalation rules", "Activity history"].map((x) => (
              <div key={x}><ShieldCheck size={18} /><span>{x}</span><CheckCircle2 size={17} /></div>
            ))}
          </div>
        </div>
      </section>

      <section className="cta-section" id="contact">
        <div className="cta-orb" />
        <div className="section-kicker">SAVRDH INTELLIGENCE WORKFORCE</div>
        <h2>Build a workforce that keeps working after your team logs off.</h2>
        <p>Your Intelligent Virtual Workforce. Always Working.</p>
        <div className="hero-actions cta-actions">
          <a className="primary-btn" href="mailto:info@savrdhtechnology.com">Request Product Demo <ArrowRight size={18} /></a>
          <a className="ghost-btn" href="https://www.savrdhtechnology.com">Visit Savrdh Technology</a>
        </div>
      </section>

      <footer>
        <div className="footer-brand"><BrandMark /><span>SAVRDH Intelligence Workforce</span></div>
        <p>© 2026 Savrdh Technology. All rights reserved.</p>
        <div className="footer-links">
          <a href="https://www.savrdhtechnology.com">savrdhtechnology.com</a>
          <a href="mailto:info@savrdhtechnology.com">Contact</a>
        </div>
      </footer>
    </main>
  );
}
