import express from 'express';
import cors from 'cors';
import fs from 'node:fs';
import { createServer } from 'node:http';
import { attachVoicePipeline } from '@unctad-ai/voice-agent-server';
import { siteConfig } from './voice-config.js';

const app = express();
const port = parseInt(process.env.PORT || '3001');

app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }));
app.use(express.json());

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
  kyutaiSttUrl: process.env.KYUTAI_STT_URL,
  qwen3TtsUrl: process.env.QWEN3_TTS_URL,
  pocketTtsUrl: process.env.POCKET_TTS_URL,
  personaDir,
}, app);

server.listen(port, () => console.log(`Server running on port ${port} (WebSocket at /api/voice)`));
