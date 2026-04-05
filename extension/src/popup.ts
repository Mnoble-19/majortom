import { getSavedWords, toggleStar, getState, setState } from './storage';

// ── Tabs ──────────────────────────────────────────────────────────────────────
document.querySelectorAll('.tab').forEach(tab => {
  tab.addEventListener('click', () => {
    const target = (tab as HTMLElement).dataset.tab!;
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
    tab.classList.add('active');
    document.getElementById(`tab-${target}`)!.classList.add('active');
  });
});

// ── Settings ──────────────────────────────────────────────────────────────────
async function initSettings() {
  const state = await getState();
  const primaryEl = document.getElementById('primaryLang') as HTMLSelectElement;
  const secondaryEl = document.getElementById('secondaryLang') as HTMLSelectElement;

  primaryEl.value = state.primaryLang;
  secondaryEl.value = state.secondaryLang;

  primaryEl.addEventListener('change', () => setState({ primaryLang: primaryEl.value }));
  secondaryEl.addEventListener('change', () => setState({ secondaryLang: secondaryEl.value }));
}

// ── Words ─────────────────────────────────────────────────────────────────────
async function renderWords() {
  const words = await getSavedWords();
  const list = document.getElementById('wordList')!;
  const stats = document.getElementById('stats')!;

  stats.textContent = `${words.length} saved word${words.length !== 1 ? 's' : ''}`;

  if (words.length === 0) {
    list.innerHTML = '<div class="empty">No saved words yet.<br>Click words in subtitles to save them.</div>';
    return;
  }

  const grouped = new Map<string, typeof words>();
  words.forEach(w => {
    const key = `${w.source} / ${w.program}`;
    if (!grouped.has(key)) grouped.set(key, []);
    grouped.get(key)!.push(w);
  });

  list.innerHTML = '';
  grouped.forEach((items, group) => {
    const header = document.createElement('div');
    header.className = 'group-header';
    header.textContent = group;
    list.appendChild(header);

    items.forEach(w => {
      const item = document.createElement('div');
      item.className = 'word-item';
      item.innerHTML = `
        <div>
          <div class="word-text">${w.word}</div>
          <div class="word-context">${w.context}</div>
          <div class="word-meta">${w.date}</div>
        </div>
        <span class="star ${w.starred ? 'active' : ''}" data-word="${w.word}">&#9733;</span>
      `;
      list.appendChild(item);
    });
  });

  list.querySelectorAll('.star').forEach(star => {
    star.addEventListener('click', async (e) => {
      const word = (e.target as HTMLElement).dataset.word!;
      await toggleStar(word);
      renderWords();
    });
  });
}

initSettings();
renderWords();
