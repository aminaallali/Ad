# MiniTik - Tiny TikTok-style Web App

A minimal full-stack app with a vertical, autoplaying video feed and an upload form. Built with Express and plain HTML/CSS/JS.

## Features
- Upload videos (mp4/webm/ogg/mov/mkv) up to ~200 MB
- Vertical feed with scroll-snap; current video autoplays
- Tap video to toggle sound; like and view counters
- Simple JSON file storage (no DB setup)

## Quickstart

```bash
npm run dev
# then open http://localhost:3000
```

Or run without auto-reload:

```bash
npm start
```

## Endpoints
- GET `/api/health` - health check
- GET `/api/videos` - list of videos
- POST `/api/upload` - upload a video (multipart/form-data, field `video`, optional `caption`)
- POST `/api/videos/:id/like` - increment like count
- POST `/api/videos/:id/view` - increment view count

## Storage Layout
- Uploaded files: `uploads/videos/`
- Metadata JSON: `data/videos.json`

## Notes
- Browsers often require user interaction to play audio; videos start muted so autoplay works.
- This project is for demo/learning. For production, use a CDN/storage bucket and sanitize inputs.