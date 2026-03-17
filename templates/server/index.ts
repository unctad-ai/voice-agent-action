import express from 'express';
import cors from 'cors';
import fs from 'node:fs';
import path from 'node:path';
import compression from 'compression';
import { createServer } from 'node:http';
import { attachVoicePipeline } from '@unctad-ai/voice-agent-server';
import { siteConfig } from './voice-config.js';

const app = express();
const port = parseInt(process.env.PORT || '80');

app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }));
app.use(express.json());
app.use(compression());

const personaDir = process.env.PERSONA_DIR || './data/persona';
if (!fs.existsSync(personaDir)) fs.mkdirSync(personaDir, { recursive: true });

app.get('/api/health', async (_req, res) => {
  const llm = { status: 'ok' as const };
  if (!process.env.GROQ_API_KEY) {
    return res.json({ status: 'ok', llm: { status: 'error', error: { message: 'GROQ_API_KEY not configured' } } });
  }
  try {
    const r = await fetch('https://api.groq.com/openai/v1/models', {
      headers: { Authorization: `Bearer ${process.env.GROQ_API_KEY}` },
      signal: AbortSignal.timeout(5000),
    });
    if (!r.ok) throw new Error(`Groq API returned ${r.status}`);
  } catch (e: any) {
    return res.json({ status: 'ok', llm: { status: 'error', error: { message: e.message } } });
  }
  res.json({ status: 'ok', llm });
});

const server = createServer(app);

attachVoicePipeline(server, {
  config: siteConfig,
  groqApiKey: process.env.GROQ_API_KEY!,
  sttUrl: process.env.STT_URL,
  qwen3TtsUrl: process.env.QWEN3_TTS_URL,
  pocketTtsUrl: process.env.POCKET_TTS_URL,
  luxTtsUrl: process.env.LUXTTS_URL,
  vllmOmniTtsUrl: process.env.VLLM_OMNI_TTS_URL,
  sttHallucinationFilter: process.env.STT_HALLUCINATION_FILTER !== '0',
  personaDir,
  adminPassword: process.env.ADMIN_PASSWORD,
}, app);

// Serve Vite build output
app.use(express.static(path.join(import.meta.dirname, 'build')));
app.get('/{*path}', (_req, res) => {
  res.sendFile(path.join(import.meta.dirname, 'build', 'index.html'));
});

server.listen(port, () => console.log(`Server running on port ${port} (WebSocket at /api/voice)`));
