"use client";

import { useState, useRef, useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";
import Tilt from "react-parallax-tilt";
import { Sun, Moon, Mail, Award, ExternalLink, MessageSquare } from "lucide-react";
import { FiGithub, FiLinkedin, FiYoutube } from "react-icons/fi";
import Link from "next/link";

export default function Portfolio() {
  const [theme, setTheme] = useState("dark");

  useEffect(() => {
    // Read theme from html attribute set by layout.js script
    const currentTheme = document.documentElement.getAttribute("data-theme") || "dark";
    setTheme(currentTheme);
  }, []);

  const toggleTheme = () => {
    const newTheme = theme === "dark" ? "light" : "dark";
    setTheme(newTheme);
    document.documentElement.setAttribute("data-theme", newTheme);
    localStorage.setItem("theme", newTheme);
  };

  const experiences = [
    { company: "Thoughtworks", role: "Senior Infrastructure Consultant", date: "April 2022 - Present", details: "Lead infrastructure consultant orchestrating enterprise-scale cloud transformations for major automotive clients including Porsche AG, MBition, and Mercedes-Benz. Architected robust CI/CD pipelines, automated AWS provisioning using Terraform, and engineered scalable 'Fleeting Runners' and containerized environments. Spearheaded the deployment of generative AI chat capabilities and internal developer platforms, significantly improving operational efficiency and security posture." },
    { company: "receeve GmbH", role: "DevOps Engineer", date: "Jun 2021 - Nov 2022", details: "Led the provisioning of Infrastructure as Code using AWS CloudFormation and managed continuous deployment pipelines across Dev, QA, and Prod environments. Enforced robust cloud security by maintaining IAM permissions and auditing AWS resources for cost optimization. Directed the containerization strategy using Docker on AWS ECS Fargate, ensuring continuous security patching and vulnerability testing." },
    { company: "Orbem", role: "DevOps Engineer", date: "Oct 2021 - Dec 2021", details: "Spearheaded modular Infrastructure as Code provisioning using Terraform alongside GitLab CI/CD pipelines. Configured secure GKE clusters on GCP for staging environments and managed Kubernetes deployments using Helmfile. Oversaw the resolution of on-premises IT infrastructure and complex deployment challenges." },
    { company: "Zameen.com", role: "DevOps Engineer", date: "Jan 2021 - Jun 2021", details: "Architected comprehensive logging and monitoring dashboards utilizing AWS CloudWatch for server and application metrics. Deployed highly-available ECS services using on-demand CloudFormation stacks and Fargate. Managed large-scale distributed systems in production, focusing on debugging, failure handling, and advanced performance tuning." },
    { company: "NorthBay Solutions", role: "Software Engineer", date: "Jul 2019 - Dec 2020", details: "Provisioned secure Infrastructure as Code via Terraform Cloud and CloudFormation nested stacks while optimizing CI/CD pipelines with GitLab, Octopus Deploy, and AWS CodePipeline. Led complex 'lift and shift' cloud migrations to AWS and developed serverless microservices using AWS SAM. Championed containerization workflows with Docker and ECR, and ensured high availability through AWS AutoScaling and Route53." },
    { company: "AI & Multidisciplinary Research Lab", role: "Full Stack Developer", date: "Jan 2019 - Jun 2019", details: "Developed 'CodeFreak', an interactive programming competition platform. Engineered a secure code compilation server with isolated Docker containers, a robust ASP.NET Core RESTful backend, and an Angular 6 user interface with real-time Chat via SignalR." },
    { company: "AUTOMATA THE PLATFORM", role: "Blockchain and Application Developer", date: "Aug 2018 - Jan 2019", details: "Built 'Keyless', a permissionless decentralized peer-to-peer biometric authentication network. Developed an Ethereum Wallet and smart contracts (ERC-20), enabling a self-sovereign key management ecosystem without traditional private keys." }
  ];

  const projects = [
    { title: "Mercedes-Benz AG - OTR", date: "Apr 2025 - Present", tech: ["Kubernetes", "AWS", "AI Integration"], desc: "Engineered infrastructure for AI/Chatbot capabilities using Model Context Protocol (MCP) skills and Platypus. Configured Kubernetes CSI drivers for persistent storage and secured DocumentDB access via in-database gateways." },
    { title: "MBition - SWF Gitlab CI Runners", date: "Jul 2023 - Jan 2025", tech: ["Terraform", "Packer", "AWS EC2"], desc: "Designed a 'Fleeting Runner' architecture for GitLab CI/CD to optimize build times. Automated Base AMI processes using Packer and Terraform to dynamically scale self-hosted runners based on pipeline demand." },
    { title: "Porsche AG - Cloud Infrastructure", date: "Jan 2023 - Jun 2023", tech: ["AWS", "Terraform", "GitHub Actions"], desc: "Standardized cloud infrastructure through reusable automation and developed AWS base infrastructure tools. Implemented automated IAM role management, observability, and shared secrets management across development teams." },
    { title: "DealerMeter", date: "Mar 2021 - Apr 2021", tech: ["AWS Lambda", "AWS Glue", "Athena"], desc: "Built a personalized market data terminal processing vendor data via S3, Lambda, and Glue into Parquet format. Visualized performance and inventory data using Apache Superset querying Athena directly." },
    { title: "Vector Solutions", date: "Dec 2019 - Dec 2020", tech: ["AWS", "Terraform", "Octopus Deploy"], desc: "Provided AWS DevOps Architecture to migrate a RackSpace Production Environment to AWS via Lift, Shift, and Shape. Built a Warm Standby DR Environment and led CI/CD implementation using Terraform Cloud and Octopus Deploy." },
    { title: "Amway", date: "Sep 2019 - Dec 2019", tech: ["AWS CloudFormation", "Lambda", "CloudFront"], desc: "Maintained Batch Ingestion, Streamed Data, and Curation pipelines on AWS. Developed Serverless Lambda functions and set up CloudFront distributions with custom SSL and WAF ACLs to secure the application." },
    { title: "NorthBay Labs", date: "Jul 2019 - Sep 2019", tech: ["AWS SAM", "NodeJS", "Elasticsearch"], desc: "Developed a collection of CloudFormation Custom Resources to simplify CFN template development. Built Lambda handlers in NodeJS to automatically index CloudWatch logs into Elasticsearch and visualize them via Kibana." },
    { title: "CodeFreak Programming Platform", date: "Jan 2019 - Jun 2019", tech: ["Angular 6", "ASP.NET Core", "Docker"], desc: "Developed a programming competition platform with embedded code editor and isolated Docker containers for code compilation." },
    { title: "Keyless Decentralized Network", date: "Aug 2018 - Jan 2019", tech: ["Ethereum", "Smart Contracts", "Biometrics"], desc: "Built an Ethereum DApp and wallet with biometric authentication, creating a decentralized peer-to-peer network without private keys." }
  ];

  const education = [
    { degree: "Bachelor's degree, Computer Software Engineering", school: "University of the Punjab (PUCIT)", date: "Oct 2015 - Jun 2019", grade: "Grade: 3.74" },
    { degree: "Intermediate, Pre-Engineering", school: "Punjab Group of Colleges", date: "Sep 2012 - Sep 2014", grade: "Grade: A+" },
    { degree: "Matriculation, Computer Science", school: "The Educators", date: "Jan 2010 - Dec 2012", grade: "Grade: A+" }
  ];

  const certifications = [
    { title: "AWS Certified Cloud Practitioner", issuer: "Amazon Web Services", type: "Foundational", url: "https://www.credly.com/badges/9bb6cabf-544a-4b64-ae6d-822df476e675/public_url", image: "https://images.credly.com/size/600x600/images/00634f82-b07f-4bbd-a6bb-53de397fc3a6/image.png" },
    { title: "AWS Certified AI Practitioner", issuer: "Amazon Web Services", type: "Foundational", url: "https://www.credly.com/badges/ea0f6e7f-9668-4dd6-a645-549ffd801eaa/public_url", image: "https://images.credly.com/size/600x600/images/4d4693bb-530e-4bca-9327-de07f3aa2348/image.png" },
    { title: "AWS Certified Developer – Associate", issuer: "Amazon Web Services", type: "Associate", url: "https://www.credly.com/badges/0ac26dba-8408-43c4-9af5-75d67c511cf0/public_url", image: "https://images.credly.com/size/600x600/images/b9feab85-1a43-4f6c-99a5-631b88d5461b/image.png" },
    { title: "AWS Certified Solutions Architect – Associate", issuer: "Amazon Web Services", type: "Associate", url: "https://www.credly.com/badges/3e1061d9-3dc4-4094-8333-5892b5a9e2b1/public_url", image: "https://images.credly.com/size/600x600/images/0e284c3f-5164-4b21-8660-0d84737941bc/image.png" },
    { title: "AWS Certified DevOps Engineer – Professional", issuer: "Amazon Web Services", type: "Professional", url: "https://www.credly.com/badges/e68bf65e-ed5d-4a02-bdb5-5a76d6537b65/public_url", image: "https://images.credly.com/size/600x600/images/bd31ef42-d460-493e-8503-39592aaf0458/image.png" },
    { title: "AWS Certified Solutions Architect – Professional", issuer: "Amazon Web Services", type: "Professional", url: "https://www.credly.com/badges/2cf52be8-6b84-47bb-9c27-314bd07aa26b/public_url", image: "https://images.credly.com/size/600x600/images/2d84e428-9078-49b6-a804-13c15383d0de/image.png" },
    { title: "HashiCorp Certified: Terraform Associate (002)", issuer: "HashiCorp", type: "Associate", url: "https://www.credly.com/badges/a84d064f-d569-4211-b436-bab57aa7136c/public_url", image: "https://images.credly.com/size/600x600/images/cd038261-9d1c-4792-bc62-3a3b5bda175c/blob" },
    { title: "HashiCorp Certified: Terraform Associate (003)", issuer: "HashiCorp", type: "Associate", url: "https://www.credly.com/badges/959c19da-8a16-44c4-8c1d-4a76d5802afc/public_url", image: "https://images.credly.com/size/600x600/images/0dc62494-dc94-469a-83af-e35309f27356/blob" }
  ];

  return (
    <>
      {/* Background Ambient Orbs */}
      <div className="ambient-orb orb-1"></div>
      <div className="ambient-orb orb-2"></div>
      <div className="ambient-orb orb-3"></div>

      {/* Navigation Bar */}
      <nav className="navbar">
        <div></div>
        <div className="nav-links">
          <a href="#experience" className="nav-link">Experience</a>
          <a href="#education" className="nav-link">Education</a>
          <a href="#projects" className="nav-link">Projects</a>
          <a href="#certifications" className="nav-link">Certifications</a>
          <Link href="/avatar" className="nav-link text-accent" style={{ fontWeight: 600 }}>Digital Twin</Link>
          <button onClick={toggleTheme} className="theme-toggle" aria-label="Toggle Theme">
            {theme === "dark" ? <Sun size={20} /> : <Moon size={20} />}
          </button>
        </div>
      </nav>

      <div className="container">
        
        {/* HERO SECTION */}
        <section id="home" className="section" style={{ paddingTop: "6rem", minHeight: "80vh", display: "flex", alignItems: "center" }}>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(350px, 1fr))", gap: "4rem", width: "100%", alignItems: "center" }}>
            
            {/* LEFT COLUMN: Main Intro */}
            <motion.div initial={{ opacity: 0, y: 30 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.8 }}>
              <h1>Hi, I'm <span className="text-accent">Muhammad Salman</span></h1>
              <h2 style={{ fontSize: "1.8rem", marginBottom: "1rem" }}>Senior Infrastructure Consultant</h2>
              <p style={{ maxWidth: "600px", fontSize: "1.15rem", marginBottom: "2rem", lineHeight: 1.7 }}>
                6x AWS Certified professional specializing in Platform Engineering, Cloud Native architectures, and building scalable infrastructure for Generative AI. With over 4 years of experience, I automate complex, multi-account AWS environments using Terraform and Kubernetes to deliver resilient, enterprise-grade cloud solutions.
              </p>
              <div className="hero-contact">
                <a href="mailto:msalmansaeedch786@gmail.com" className="contact-btn"><Mail size={18} /> Email</a>
                <a href="https://github.com/msalmansaeedch" target="_blank" rel="noreferrer" className="contact-btn"><FiGithub size={18} /> GitHub</a>
                <a href="https://linkedin.com/in/msalmansaeedch" target="_blank" rel="noreferrer" className="contact-btn"><FiLinkedin size={18} /> LinkedIn</a>
                <a href="https://www.youtube.com/@msalmansaeedch" target="_blank" rel="noreferrer" className="contact-btn"><FiYoutube size={18} /> YouTube</a>
              </div>
            </motion.div>

            {/* RIGHT COLUMN: Digital Twin Widget */}
            <motion.div 
              initial={{ opacity: 0, scale: 0.9 }} 
              animate={{ opacity: 1, scale: 1 }} 
              transition={{ duration: 0.8, delay: 0.2 }}
              style={{
                background: "rgba(0, 242, 254, 0.03)",
                border: "1px solid rgba(0, 242, 254, 0.1)",
                borderRadius: "24px",
                padding: "2.5rem 2rem",
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                textAlign: "center",
                boxShadow: "0 10px 30px -10px rgba(0, 242, 254, 0.1)",
                backdropFilter: "blur(10px)",
                maxWidth: "500px",
                margin: "0 auto"
              }}
            >
              <img 
                src="/salman-avatar.jpg" 
                alt="Digital Twin" 
                style={{ width: "90px", height: "90px", borderRadius: "50%", objectFit: "cover", objectPosition: "center 20%", border: "2px solid rgba(0, 242, 254, 0.4)", marginBottom: "1.5rem" }} 
              />
              <h3 style={{ fontSize: "1.6rem", fontWeight: 500, marginBottom: "0.5rem", letterSpacing: "0.5px" }}>
                I'm Salman's <span style={{ fontStyle: "italic", color: "#00f2fe", fontWeight: 600 }}>digital twin</span>.
              </h3>
              <p style={{ fontSize: "1.2rem", fontWeight: 400, marginBottom: "1rem", lineHeight: 1.4 }}>
                Ask me anything – the real Salman might just chime in.
              </p>
              <p style={{ fontSize: "0.95rem", color: "var(--text-secondary)", marginBottom: "2rem", maxWidth: "90%" }}>
                I know Salman's complete background, projects, and tech stack. I can also put you in touch directly.
              </p>
              
              <div style={{ display: "flex", flexWrap: "wrap", justifyContent: "center", gap: "0.8rem", width: "100%" }}>
                <Link href="/avatar" style={{ fontSize: "1rem", fontWeight: 600, padding: "0.8rem 1.8rem", borderRadius: "25px", background: "linear-gradient(135deg, #00f2fe, #4facfe)", border: "none", color: "#000", textDecoration: "none", transition: "all 0.2s", marginTop: "0.5rem", display: "flex", alignItems: "center", gap: "0.5rem" }} onMouseOver={(e) => { e.currentTarget.style.transform = "translateY(-2px)"; e.currentTarget.style.boxShadow = "0 4px 15px rgba(0, 242, 254, 0.4)" }} onMouseOut={(e) => { e.currentTarget.style.transform = "translateY(0)"; e.currentTarget.style.boxShadow = "none" }}>
                  <MessageSquare size={20} />
                  Chat with Digital Twin
                </Link>
              </div>
            </motion.div>

          </div>
        </section>

        {/* EXPERIENCE SECTION */}
        <section id="experience" className="section">
          <h2>Experience</h2>
          <div className="timeline">
            {experiences.map((exp, index) => (
              <motion.div 
                key={index} 
                className="timeline-item"
                initial={{ opacity: 0, x: -50 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true, margin: "-100px" }}
                transition={{ duration: 0.5, delay: index * 0.1 }}
              >
                <div className="timeline-dot"></div>
                <div className="timeline-date">{exp.date}</div>
                <div className="timeline-title" style={{ fontSize: "1.4rem", fontWeight: "bold", color: "var(--neon-cyan)" }}>{exp.company}</div>
                <div className="timeline-company" style={{ fontSize: "1.1rem", marginBottom: "0.5rem" }}>{exp.role}</div>
                <p>{exp.details}</p>
              </motion.div>
            ))}
          </div>
        </section>

        {/* EDUCATION SECTION */}
        <section id="education" className="section">
          <h2>Education</h2>
          <div style={{ display: "flex", flexDirection: "column", gap: "1.5rem" }}>
            {education.map((edu, index) => (
              <motion.div 
                key={index}
                className="glass-panel" 
                style={{ padding: "2rem" }}
                initial={{ opacity: 0, y: 30 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ duration: 0.4, delay: index * 0.1 }}
              >
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", flexWrap: "wrap", gap: "1rem" }}>
                  <div>
                    <h3 style={{ fontSize: "1.3rem", marginBottom: "0.5rem", color: "var(--text-primary)" }}>{edu.degree}</h3>
                    <p style={{ color: "var(--text-secondary)", fontWeight: 600, fontSize: "1.1rem", margin: 0 }}>{edu.school}</p>
                  </div>
                  <div style={{ textAlign: "right" }}>
                    <div style={{ color: "var(--neon-cyan)", fontFamily: "'JetBrains Mono', monospace", marginBottom: "0.5rem", fontSize: "0.9rem", letterSpacing: "1px" }}>{edu.date}</div>
                    <span style={{ background: "rgba(0, 242, 254, 0.1)", color: "var(--neon-cyan)", padding: "0.2rem 0.8rem", borderRadius: "20px", fontSize: "0.8rem", fontWeight: 600 }}>{edu.grade}</span>
                  </div>
                </div>
              </motion.div>
            ))}
          </div>
        </section>

        {/* PROJECTS SECTION */}
        <section id="projects" className="section">
          <h2>Projects</h2>
          <div className="projects-grid">
            {projects.map((project, index) => (
              <Tilt key={index} tiltMaxAngleX={5} tiltMaxAngleY={5} scale={1.02} transitionSpeed={2000}>
                <motion.div 
                  className="project-card glass-panel"
                  initial={{ opacity: 0, scale: 0.9 }}
                  whileInView={{ opacity: 1, scale: 1 }}
                  viewport={{ once: true }}
                  transition={{ duration: 0.4, delay: index * 0.1 }}
                >
                  <div style={{ padding: "2rem" }}>
                    <div style={{ fontSize: "0.8rem", color: "var(--text-secondary)", marginBottom: "0.5rem", fontFamily: "'JetBrains Mono', monospace", letterSpacing: "1px" }}>{project.date}</div>
                    <h3 style={{ margin: "0 0 1rem 0", color: "var(--neon-cyan)" }}>{project.title}</h3>
                    <p>{project.desc}</p>
                    {project.tech && (
                      <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap", marginTop: "1rem" }}>
                        {project.tech.map((t, i) => (
                          <span key={i} style={{ background: "rgba(0, 242, 254, 0.1)", color: "var(--neon-cyan)", padding: "0.2rem 0.6rem", borderRadius: "12px", fontSize: "0.8rem", border: "1px solid rgba(0, 242, 254, 0.3)" }}>
                            {t}
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                </motion.div>
              </Tilt>
            ))}
          </div>
        </section>

        {/* CERTIFICATIONS SECTION */}
        <section id="certifications" className="section">
          <h2>Certifications & Badges</h2>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(300px, 1fr))", gap: "2rem" }}>
            {certifications.map((cert, index) => (
              <motion.a 
                href={cert.url}
                target="_blank"
                rel="noreferrer"
                key={index} 
                className="glass-panel"
                style={{ padding: "2rem", display: "flex", flexDirection: "column", alignItems: "center", textAlign: "center", textDecoration: "none", color: "var(--text-primary)", position: "relative" }}
                initial={{ opacity: 0, y: 30 }}
                whileInView={{ opacity: 1, y: 0 }}
                whileHover={{ scale: 1.03, borderColor: "var(--neon-cyan)" }}
                viewport={{ once: true }}
                transition={{ duration: 0.4, delay: index * 0.05 }}
              >
                <div style={{ position: "absolute", top: "1rem", right: "1rem" }}>
                  <ExternalLink size={20} style={{ color: "var(--text-secondary)" }} />
                </div>
                <img src={cert.image} alt={cert.title} style={{ width: "240px", height: "240px", objectFit: "contain", filter: "drop-shadow(0 12px 24px rgba(0,0,0,0.5))", marginBottom: "1.5rem" }} />
                <span style={{ background: "rgba(0, 242, 254, 0.1)", color: "var(--neon-cyan)", padding: "0.3rem 0.8rem", borderRadius: "20px", fontSize: "0.75rem", fontWeight: 600, letterSpacing: "1px", textTransform: "uppercase", marginBottom: "1rem" }}>
                  {cert.type}
                </span>
                <h3 style={{ margin: "0 0 0.5rem 0", fontSize: "1.1rem", lineHeight: 1.4 }}>{cert.title}</h3>
                <p style={{ margin: 0, color: "var(--text-secondary)", fontSize: "0.85rem", fontWeight: 600 }}>{cert.issuer}</p>
              </motion.a>
            ))}
          </div>
        </section>

      </div>

      {/* Main Call to Action: Talk to Digital Twin */}
      <div style={{ display: "flex", justifyContent: "center", padding: "4rem 0 6rem 0" }}>
        <Link href="/avatar" style={{ textDecoration: "none" }}>
          <motion.div 
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            style={{
              background: "linear-gradient(135deg, var(--neon-cyan), var(--neon-purple))",
              padding: "1rem 2rem",
              borderRadius: "50px",
              color: "#fff",
              fontWeight: 800,
              fontSize: "1.2rem",
              boxShadow: "0 10px 30px var(--neon-purple-glow)",
              display: "flex",
              alignItems: "center",
              gap: "1rem"
            }}
          >
            <div style={{ width: "20px", height: "20px", borderRadius: "50%", background: "#fff", animation: "pulse 2s infinite" }} />
            TALK TO MY DIGITAL TWIN
          </motion.div>
        </Link>
      </div>
    </>
  );
}
