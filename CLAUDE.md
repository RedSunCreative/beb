# Boo Production Suite — Claude Code Briefing

## Who I Am
Mark Caddell, founder of Red Sun Creative Studio, Austin TX.
This is a live video production tool suite for **Little Big Voices**, a community-focused live video podcast.

## The Bigger Picture — Boo Podcast Production Suite
BEB and BSM are two tools in a three-product suite being built for sale to other clients (5–10/year, low monthly fee or consulting hours bundled):

1. **Boo Producer** — Pre-production: season arc, episode intent, guest research, topics, questions. Universal — works for any show. Highest commercial value. Currently exists as `boo-producer_13.html` (built in Claude chat, no persistence, not yet in this repo).
2. **Boo Episode Builder (BEB)** — Run of show generation. Currently LBV-specific. Will be generalized via show profile config.
3. **Boo Show Manager (BSM)** — Live runtime. Roadmap: simplified mode for recorded podcasts, then hardware integration (Stream Deck macros, ATEM switching, NDI camera presets, audio mixer control).

**The missing piece:** A **show profile** — a config object defining any show (name, hosts, format, segment types, crew roles, branding). Once this exists, new client = new config, not new code. Producer → Builder → Manager data chain follows.

**First external client:** Anno Coding podcast (Matt + Kartik). Audio-first, recorded on Riverside, 2 hosts + guests. Season 1: 8 eps, mid-August launch. Boo Producer is the primary tool needed.

**Market thesis:** As AI generates everything, authentic human experience becomes more valuable. Boo is infrastructure for live, human shows.

**Do not treat BEB/BSM as isolated tools.** Every architectural decision should consider how it fits the suite.

## Project Structure
All files live in: `~/Documents/Boo Production Suite/beb/`

### Boo Episode Builder (BEB)
- **File:** `beb.html`
- **Purpose:** Pre-production tool. Hosts enter episode details, guests, segments, and timing. BEB calls the Claude API (claude-sonnet-4-20250514) to generate a structured run-of-show JSON that feeds BSM.
- **Key system prompt behavior:** Generates cue objects with fields including: `scene`, `liveLabel`, `dur`, `prelive`, `stageType`, `booName`, `booMsg`, `w5`, `w2`, `nextScene`, `nextHint`, `audioNow`, `videoNow`, `camerasNow`, `lightingNow`, `audioNext`, `videoNext`, `camerasNext`, `lightingNext`, `standbyWho`, `standbyStage`, `cueCard`

### Boo Show Manager (BSM)
- **Files:** `bsm-e9.html` (current episode), `bsm-template.html` (reusable template)
- **Purpose:** Live show runtime tool. Consumes the JSON from BEB and drives the show — teleprompter, countdown timers, Boo cards (guest ready cues on studio TV screens), standby cues, director overlays.
- **Key feature — Boo Cards:** Studio TV screens show personalized get-ready messages to guests. `booName` = next guest up. `booMsg` = message written directly to them. `{M}` is a live countdown placeholder replaced in real-time with remaining minutes in gold: `<span style="color:#F5D03A;font-weight:900;">${m} ${min}</span>`

## How They Work Together
BEB generates → BSM consumes. Development goes back and forth between both as features are added to one side and need to be reflected in the other.

## Infrastructure
- `server.js` — local Node server
- `supabase/` — Supabase integration for data persistence
- `node_modules/`, `package.json` — Node dependencies
- Git repo active on `main` branch

## Current State (as of June 6, 2026)
### Speed fixes applied:
- Dynamic `max_tokens`: simple queries use 512 (fast path), cue builds use 8192. Committed `151ecd4`.
- Root cause of slowness: system prompt grew 6× during dev (now ~4,300 tokens static + showData JSON). Full cue-array builds generate 7,500+ output tokens — inherently slow without streaming.
- Streaming proxy (Supabase Edge Function) is the next fix — requires one `supabase functions deploy` command from Mark.

### Pending verification:
- Gold `{M}` countdown rendering in `bsm-template.html` — never visually confirmed after fix.

## Working Style
- I prefer direct, action-oriented responses
- Commit and push after each meaningful change
- Use git commit messages that are descriptive
- `/compact` early in long sessions — don't let context balloon
- Test changes before moving to the next feature

## Important Notes
- `Claude Console API Key.rtf` is in the project folder — do not commit this file
- E9 = Episode 9 (current production episode)
- "Boo" = the AI system prompt persona used in BEB to generate show cues
- Stages: "pod" (main interview stage), "music", "kitchen", "video"
