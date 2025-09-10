/* Snake Game */
(() => {
  const GRID_SIZE = 20; // cells per row/col
  const CELL_PX = 24; // pixels per cell (CSS scales canvas but keep logical size)
  const TICK_BASE_MS = 120; // lower is faster

  /** @type {HTMLCanvasElement} */
  const canvas = document.getElementById('board');
  const ctx = canvas.getContext('2d');
  const scoreEl = document.getElementById('score');
  const bestEl = document.getElementById('best');
  const btnPause = document.getElementById('btn-pause');
  const btnRestart = document.getElementById('btn-restart');
  const dpad = document.querySelector('.dpad');

  // Ensure canvas logical size matches our grid
  canvas.width = GRID_SIZE * CELL_PX;
  canvas.height = GRID_SIZE * CELL_PX;

  const loadBest = () => Number(localStorage.getItem('snake_best') || '0');
  const saveBest = (v) => localStorage.setItem('snake_best', String(v));

  /** Direction vectors */
  const DIR = {
    up: { x: 0, y: -1 },
    down: { x: 0, y: 1 },
    left: { x: -1, y: 0 },
    right: { x: 1, y: 0 },
  };

  /** Immediate opposite pairs to prevent 180s */
  const OPPOSITE = {
    up: 'down',
    down: 'up',
    left: 'right',
    right: 'left',
  };

  /** Game state */
  let snake = [];
  let direction = 'right';
  let queuedDirection = 'right';
  let food = { x: 0, y: 0 };
  let score = 0;
  let best = loadBest();
  let isPaused = false;
  let isGameOver = false;
  let tickMs = TICK_BASE_MS;
  let lastTick = 0;

  function initializeGame() {
    snake = [
      { x: 8, y: 10 },
      { x: 7, y: 10 },
      { x: 6, y: 10 },
    ];
    direction = 'right';
    queuedDirection = 'right';
    score = 0;
    isPaused = false;
    isGameOver = false;
    tickMs = TICK_BASE_MS;
    best = loadBest();
    spawnFood();
    updateHud();
  }

  function updateHud() {
    scoreEl.textContent = String(score);
    bestEl.textContent = String(best);
    btnPause.textContent = isPaused ? 'Resume' : 'Pause';
  }

  function spawnFood() {
    const occupied = new Set(snake.map((s) => s.x + ',' + s.y));
    let x, y;
    do {
      x = Math.floor(Math.random() * GRID_SIZE);
      y = Math.floor(Math.random() * GRID_SIZE);
    } while (occupied.has(x + ',' + y));
    food = { x, y };
  }

  function setDirection(next) {
    if (OPPOSITE[next] === direction) return; // ignore 180
    queuedDirection = next;
  }

  function update(time) {
    if (isPaused || isGameOver) return;
    if (time - lastTick < tickMs) return;
    lastTick = time;

    // apply queued direction at start of tick
    direction = queuedDirection;
    const head = snake[0];
    const dx = DIR[direction].x;
    const dy = DIR[direction].y;
    const newHead = { x: head.x + dx, y: head.y + dy };

    // wall collision -> wrap or end. We'll end game.
    if (
      newHead.x < 0 ||
      newHead.x >= GRID_SIZE ||
      newHead.y < 0 ||
      newHead.y >= GRID_SIZE
    ) {
      gameOver();
      return;
    }

    // self collision
    for (let i = 0; i < snake.length; i++) {
      const seg = snake[i];
      if (seg.x === newHead.x && seg.y === newHead.y) {
        gameOver();
        return;
      }
    }

    // move
    snake.unshift(newHead);
    const ate = newHead.x === food.x && newHead.y === food.y;
    if (ate) {
      score += 1;
      if (score > best) {
        best = score;
        saveBest(best);
      }
      if (tickMs > 60) tickMs -= 2; // speed up slightly
      spawnFood();
      updateHud();
    } else {
      snake.pop();
    }
  }

  function gameOver() {
    isGameOver = true;
    updateHud();
    draw();
    toast('Game Over — press Restart');
  }

  function draw() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // draw food
    drawCell(food.x, food.y, '#f43f5e');

    // draw snake
    for (let i = snake.length - 1; i >= 0; i--) {
      const seg = snake[i];
      const alpha = i === 0 ? 1 : 0.9 - Math.min(0.7, i * 0.02);
      drawCell(seg.x, seg.y, `rgba(52, 211, 153, ${alpha})`);
    }
  }

  function drawCell(x, y, color) {
    ctx.fillStyle = color;
    ctx.fillRect(x * CELL_PX + 2, y * CELL_PX + 2, CELL_PX - 4, CELL_PX - 4);
  }

  function loop(time) {
    update(time || 0);
    draw();
    requestAnimationFrame(loop);
  }

  // lightweight toast
  let toastTimer;
  function toast(message) {
    clearTimeout(toastTimer);
    let el = document.getElementById('toast');
    if (!el) {
      el = document.createElement('div');
      el.id = 'toast';
      Object.assign(el.style, {
        position: 'fixed', left: '50%', bottom: '24px', transform: 'translateX(-50%)',
        background: 'rgba(0,0,0,0.7)', color: 'white', padding: '10px 14px', borderRadius: '8px',
        fontSize: '14px', zIndex: 9999, border: '1px solid rgba(255,255,255,0.2)'
      });
      document.body.appendChild(el);
    }
    el.textContent = message;
    el.style.opacity = '1';
    toastTimer = setTimeout(() => { el.style.opacity = '0'; }, 1800);
  }

  // Input: keyboard
  window.addEventListener('keydown', (e) => {
    switch (e.key) {
      case 'ArrowUp':
      case 'w':
      case 'W':
        setDirection('up'); break;
      case 'ArrowDown':
      case 's':
      case 'S':
        setDirection('down'); break;
      case 'ArrowLeft':
      case 'a':
      case 'A':
        setDirection('left'); break;
      case 'ArrowRight':
      case 'd':
      case 'D':
        setDirection('right'); break;
      case ' ':
      case 'Enter':
        togglePause(); break;
    }
  });

  // Buttons
  btnPause.addEventListener('click', togglePause);
  btnRestart.addEventListener('click', () => { initializeGame(); });

  function togglePause() {
    if (isGameOver) return; // ignore if over
    isPaused = !isPaused;
    updateHud();
    toast(isPaused ? 'Paused' : 'Resumed');
  }

  // Mobile dpad
  if (dpad) {
    dpad.addEventListener('click', (e) => {
      const target = e.target;
      if (!(target instanceof HTMLElement)) return;
      const dir = target.getAttribute('data-dir');
      if (dir && DIR[dir]) setDirection(dir);
    });
  }

  // Swipe support
  let touchStart = null;
  canvas.addEventListener('touchstart', (e) => {
    const t = e.changedTouches[0];
    touchStart = { x: t.clientX, y: t.clientY };
  }, { passive: true });
  canvas.addEventListener('touchend', (e) => {
    if (!touchStart) return;
    const t = e.changedTouches[0];
    const dx = t.clientX - touchStart.x;
    const dy = t.clientY - touchStart.y;
    const ax = Math.abs(dx), ay = Math.abs(dy);
    if (Math.max(ax, ay) > 24) {
      if (ax > ay) setDirection(dx > 0 ? 'right' : 'left');
      else setDirection(dy > 0 ? 'down' : 'up');
    }
    touchStart = null;
  }, { passive: true });

  // Kickoff
  initializeGame();
  requestAnimationFrame(loop);
})();
