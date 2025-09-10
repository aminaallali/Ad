const feedElement = document.getElementById('feed');
const videoTemplate = document.getElementById('videoTemplate');
const toggleUploadButton = document.getElementById('toggleUpload');
const cancelUploadButton = document.getElementById('cancelUpload');
const uploaderSection = document.getElementById('uploader');
const uploadForm = document.getElementById('uploadForm');
const uploadStatus = document.getElementById('uploadStatus');

let observer;
const viewedOnce = new Set();

async function fetchVideos() {
  const res = await fetch('/api/videos');
  if (!res.ok) throw new Error('Failed to load videos');
  return res.json();
}

function renderVideoCard(videoData, { appendToEnd = true } = {}) {
  const { id, url, caption, likes, views } = videoData;
  const node = document.importNode(videoTemplate.content, true);
  const section = node.querySelector('.video-card');
  const vid = node.querySelector('video');
  const captionEl = node.querySelector('.caption');
  const likeBtn = node.querySelector('.like');
  const likeCount = node.querySelector('.like-count');
  const viewCount = node.querySelector('.view-count');

  section.dataset.videoId = id;
  vid.src = url;
  vid.muted = true; // start muted so autoplay works on mobile
  captionEl.textContent = caption || '';
  likeCount.textContent = likes ?? 0;
  viewCount.textContent = views ?? 0;

  // Toggle mute on tap/click
  vid.addEventListener('click', () => {
    vid.muted = !vid.muted;
  });

  likeBtn.addEventListener('click', async (e) => {
    e.preventDefault();
    try {
      const res = await fetch(`/api/videos/${id}/like`, { method: 'POST' });
      if (res.ok) {
        const data = await res.json();
        likeCount.textContent = data.likes;
      }
    } catch (err) {
      // ignore for now
    }
  });

  if (appendToEnd) {
    feedElement.appendChild(node);
  } else {
    feedElement.insertBefore(node, feedElement.firstChild);
  }
}

function setupIntersectionObserver() {
  if (observer) observer.disconnect();
  observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      const video = entry.target;
      const section = video.closest('.video-card');
      const videoId = section?.dataset.videoId;
      if (entry.isIntersecting && entry.intersectionRatio >= 0.6) {
        // Pause other videos
        document.querySelectorAll('.video-card video').forEach(v => { if (v !== video) v.pause(); });
        // Autoplay current
        video.play().catch(() => {});

        if (videoId && !viewedOnce.has(videoId)) {
          viewedOnce.add(videoId);
          fetch(`/api/videos/${videoId}/view`, { method: 'POST' }).then(async (res) => {
            if (res.ok) {
              const data = await res.json();
              const viewCount = section.querySelector('.view-count');
              viewCount.textContent = data.views;
            }
          }).catch(() => {});
        }
      } else {
        video.pause();
      }
    });
  }, { threshold: [0, 0.25, 0.6, 0.75, 1] });

  document.querySelectorAll('.video-card video').forEach(v => observer.observe(v));
}

async function init() {
  try {
    const videos = await fetchVideos();
    videos.forEach(v => renderVideoCard(v));
    setupIntersectionObserver();
  } catch (err) {
    feedElement.innerHTML = `<div style="padding:24px;color:#9aa0a6;">Failed to load feed.</div>`;
  }
}

toggleUploadButton.addEventListener('click', () => {
  uploaderSection.classList.toggle('hidden');
});
cancelUploadButton.addEventListener('click', () => {
  uploaderSection.classList.add('hidden');
});

uploadForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const fileInput = document.getElementById('videoFile');
  const captionInput = document.getElementById('caption');
  if (!fileInput.files.length) return;
  const formData = new FormData();
  formData.append('video', fileInput.files[0]);
  formData.append('caption', captionInput.value);
  uploadStatus.textContent = 'Uploading...';
  try {
    const res = await fetch('/api/upload', { method: 'POST', body: formData });
    if (!res.ok) throw new Error('Upload failed');
    const newVideo = await res.json();
    renderVideoCard(newVideo, { appendToEnd: false });
    setupIntersectionObserver();
    // Reset form
    uploadForm.reset();
    uploaderSection.classList.add('hidden');
    uploadStatus.textContent = 'Uploaded!';
    // Scroll to top to see the new video
    feedElement.scrollTo({ top: 0, behavior: 'smooth' });
  } catch (err) {
    uploadStatus.textContent = err.message || 'Upload failed';
  } finally {
    setTimeout(() => { uploadStatus.textContent = ''; }, 2000);
  }
});

document.addEventListener('visibilitychange', () => {
  if (document.hidden) {
    document.querySelectorAll('.video-card video').forEach(v => v.pause());
  } else {
    // Trigger observer to play the visible one
    document.querySelectorAll('.video-card video').forEach(v => {
      const rect = v.getBoundingClientRect();
      const visibleRatio = Math.max(0, Math.min(rect.bottom, window.innerHeight) - Math.max(rect.top, 0)) / Math.min(rect.height, window.innerHeight);
      if (visibleRatio >= 0.6) v.play().catch(() => {});
    });
  }
});

window.addEventListener('load', init);

