import express from 'express';
import cors from 'cors';
import { createVoiceRoutes } from '@unctad-ai/voice-agent-server';
import { siteConfig } from './voice-config.js';

const app = express();
const port = parseInt(process.env.PORT || '3001');

app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }));
app.use(express.json());

const voice = createVoiceRoutes({
  config: siteConfig,
  groqApiKey: process.env.GROQ_API_KEY!,
  kyutaiSttUrl: process.env.KYUTAI_STT_URL,
  qwen3TtsUrl: process.env.QWEN3_TTS_URL,
  pocketTtsUrl: process.env.POCKET_TTS_URL,
});

app.post('/api/chat', voice.chat);
app.use('/api/stt', voice.stt);
app.use('/api/tts', voice.tts);
app.get('/api/health', (_req, res) => res.json({ status: 'ok' }));

app.listen(port, () => console.log(`Server running on port ${port}`));
