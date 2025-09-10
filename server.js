import express from 'express';
import multer from 'multer';
import cors from 'cors';
import morgan from 'morgan';
import { v4 as uuidv4 } from 'uuid';
import fs from 'fs-extra';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const port = process.env.PORT || 3000;

const uploadsRootDirectory = path.join(__dirname, 'uploads');
const videosDirectory = path.join(uploadsRootDirectory, 'videos');
const dataDirectory = path.join(__dirname, 'data');
const dbFilePath = path.join(dataDirectory, 'videos.json');

// Ensure required directories/files exist at startup
await fs.ensureDir(videosDirectory);
await fs.ensureDir(dataDirectory);
await fs.ensureFile(dbFilePath);
try {
  const existing = await fs.readFile(dbFilePath, 'utf-8');
  if (!existing.trim()) {
    await fs.writeFile(dbFilePath, '[]', 'utf-8');
  }
} catch (err) {
  await fs.writeFile(dbFilePath, '[]', 'utf-8');
}

app.use(cors());
app.use(morgan('dev'));
app.use(express.json({ limit: '2mb' }));

// Static serving
app.use('/uploads', express.static(uploadsRootDirectory));
app.use(express.static(path.join(__dirname, 'public')));

// Simple JSON DB helpers
async function loadVideos() {
  try {
    const content = await fs.readFile(dbFilePath, 'utf-8');
    const parsed = JSON.parse(content || '[]');
    if (!Array.isArray(parsed)) return [];
    return parsed;
  } catch (err) {
    return [];
  }
}

async function saveVideos(videos) {
  await fs.writeFile(dbFilePath, JSON.stringify(videos, null, 2), 'utf-8');
}

// Multer setup for video uploads
const allowedMimeTypes = new Set([
  'video/mp4',
  'video/webm',
  'video/ogg',
  'video/quicktime',
  'video/x-matroska'
]);

const storage = multer.diskStorage({
  destination: function (_req, _file, cb) {
    cb(null, videosDirectory);
  },
  filename: function (_req, file, cb) {
    const ext = path.extname(file.originalname) || '.mp4';
    const safeName = `${uuidv4()}${ext}`;
    cb(null, safeName);
  }
});

function fileFilter(_req, file, cb) {
  if (allowedMimeTypes.has(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error('Only video files are allowed'));
  }
}

const upload = multer({
  storage,
  fileFilter,
  limits: { fileSize: 200 * 1024 * 1024 } // 200MB
});

// Routes
app.get('/api/health', (_req, res) => {
  res.json({ ok: true });
});

app.get('/api/videos', async (_req, res) => {
  const videos = await loadVideos();
  videos.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  res.json(videos);
});

app.post('/api/upload', upload.single('video'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'Video file is required' });
    }

    const caption = (req.body.caption || '').toString().slice(0, 200);
    const id = uuidv4();
    const filename = req.file.filename;
    const url = `/uploads/videos/${filename}`;
    const createdAt = new Date().toISOString();

    const newVideo = { id, filename, url, caption, likes: 0, views: 0, createdAt };
    const videos = await loadVideos();
    videos.unshift(newVideo);
    await saveVideos(videos);

    res.status(201).json(newVideo);
  } catch (err) {
    res.status(500).json({ error: 'Upload failed', details: err?.message || String(err) });
  }
});

app.post('/api/videos/:id/like', async (req, res) => {
  const { id } = req.params;
  const videos = await loadVideos();
  const idx = videos.findIndex(v => v.id === id);
  if (idx === -1) return res.status(404).json({ error: 'Video not found' });
  videos[idx].likes = (videos[idx].likes || 0) + 1;
  await saveVideos(videos);
  res.json({ likes: videos[idx].likes });
});

app.post('/api/videos/:id/view', async (req, res) => {
  const { id } = req.params;
  const videos = await loadVideos();
  const idx = videos.findIndex(v => v.id === id);
  if (idx === -1) return res.status(404).json({ error: 'Video not found' });
  videos[idx].views = (videos[idx].views || 0) + 1;
  await saveVideos(videos);
  res.json({ views: videos[idx].views });
});

// Fallback: serve index.html for non-API routes (Express 5 compatible)
app.get(/^\/(?!api).*/, (_req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`Server listening on http://localhost:${port}`);
});

